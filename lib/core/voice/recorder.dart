// 录音封装（record 插件）。
//
// 职责：
//   * 权限检查、编码器可用性检查；
//   * 落盘为 WAV（PCM16 单声道 16kHz），临时文件前缀 `/keepsake_rec_`；
//   * 最大时长（默认 60s，到点自动结束本次录音）与体积上限；
//   * 空录音 / 静音 / 太短 的检测，错误全部转成 VoiceError；
//   * 临时文件在读完字节后立即删除（ASR 上传用的是内存字节，不依赖文件）。

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'package:keepsake/core/voice/voice_error.dart';
import 'package:keepsake/core/voice/voice_guards.dart';
import 'package:keepsake/core/voice/wav.dart';

/// 录音过程中的实时回调（结束时 elapsed 为最终时长）。
typedef VoiceRecordingTick = ({Duration elapsed, double amplitude});

/// 一次录音的结果（字节是 ASR 上传的真正来源）。
class RecordedClip {
  const RecordedClip({
    required this.path,
    required this.bytes,
    required this.duration,
    required this.peak,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
  });

  /// 临时文件路径（读完字节后已被删除，仅用于排查）。
  final String path;

  /// WAV 完整字节（含头）。
  final Uint8List bytes;

  /// 时长（由 WAV 头计算）。
  final Duration duration;

  /// 峰值振幅 0..1。
  final double peak;

  final int sampleRate;
  final int channels;
  final int bitsPerSample;

  int get sizeInBytes => bytes.length;

  double get sizeMb => bytes.length / (1024 * 1024);

  bool get isEmpty => bytes.isEmpty || duration <= Duration.zero;

  bool get isPcm16Mono16k =>
      bitsPerSample == 16 && channels == 1 && sampleRate == 16000;

  @override
  String toString() =>
      'RecordedClip($path, ${duration.inMilliseconds}ms, $sizeInBytes bytes)';
}

/// record 插件封装。
///
/// 使用方式（按住说话）：
/// ```dart
/// await recorder.start();
/// final sub = recorder.ticks.listen((t) => setState(...));
/// final clip = await recorder.stop();  // 或到 60s 自动结束
/// final text = await asr.transcribe(caps: caps, wav: clip.bytes);
/// ```
class VoiceRecorder {
  VoiceRecorder({
    AudioRecorder? recorder,
    this.maxDuration = defaultMaxDuration,
    this.minDuration = defaultMinDuration,
    this.maxBytes = defaultMaxBytes,
    this.silenceThreshold = defaultSilenceThreshold,
    this.sampleRate = defaultSampleRate,
    this.channels = defaultChannels,
  }) : _injectedRecorder = recorder;

  /// 临时文件前缀（情报原文 `/keepsake_rec_`）。
  static const String tempFilePrefix = '/keepsake_rec_';

  /// 最大录音时长；到点自动结束本次录音（仍会走 ASR）。
  static const Duration defaultMaxDuration = Duration(seconds: 60);

  /// 最短录音时长，短于此值提示「按住时间太短，说完再松手」。
  static const Duration defaultMinDuration = Duration(milliseconds: 500);

  /// 最大录音体积（25MB），超过提示「录音文件太大，请缩短录音」。
  static const int defaultMaxBytes = 25 * 1024 * 1024;

  /// 静音判定阈值（峰值振幅，0.01 约 -40dBFS）。
  static const double defaultSilenceThreshold = 0.01;

  /// ASR 推荐采样率。
  static const int defaultSampleRate = 16000;

  /// ASR 推荐声道数。
  static const int defaultChannels = 1;

  /// 实时回调间隔（UI 进度/波形刷新）。
  static const Duration tickInterval = Duration(milliseconds: 120);

  /// 最大录音时长。
  final Duration maxDuration;

  /// 最短录音时长。
  final Duration minDuration;

  /// 最大录音体积。
  final int maxBytes;

  /// 静音判定阈值（峰值振幅）。
  final double silenceThreshold;

  /// 录音采样率。
  final int sampleRate;

  /// 录音声道数。
  final int channels;

  final AudioRecorder? _injectedRecorder;

  AudioRecorder? _recorder;
  final StreamController<VoiceRecordingTick> _ticks =
      StreamController<VoiceRecordingTick>.broadcast();

  Timer? _timer;
  DateTime? _startedAt;
  String? _path;
  Duration _lastElapsed = Duration.zero;
  double _lastAmplitude = 0;
  bool _recording = false;
  bool _autoStopped = false;
  bool _disposed = false;
  Future<RecordedClip>? _stopFuture;

  /// 是否正在录音。
  bool get isRecording => _recording;

  /// 是否因达到最大时长而自动结束（这次结果仍可 stop() 取到）。
  bool get autoStopped => _autoStopped;

  /// 当前临时文件路径（未在录音时为 null）。
  String? get currentPath => _path;

  /// 当前/最近一次录音时长。
  Duration get elapsed => _recording ? _elapsedNow() : _lastElapsed;

  /// 距离最大时长还剩多久（不会为负）。
  Duration get remaining {
    final left = maxDuration - elapsed;
    return left > Duration.zero ? left : Duration.zero;
  }

  /// 当前振幅 0..1（供 UI 画音量条）。
  double get amplitude => _lastAmplitude;

  /// 录音中的实时回调流（广播）。
  Stream<VoiceRecordingTick> get ticks => _ticks.stream;

  RecordConfig get _config => RecordConfig(
        encoder: AudioEncoder.wav,
        bitRate: 256000,
        sampleRate: sampleRate,
        numChannels: channels,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: true,
      );

  AudioRecorder get _engine =>
      _recorder ??= _injectedRecorder ?? AudioRecorder();

  /// 当前环境/编码器是否支持录音。
  Future<bool> isSupported() async {
    if (!voiceRecordingAvailable) return false;
    try {
      return await _engine.isEncoderSupported(AudioEncoder.wav);
    } catch (_) {
      return false;
    }
  }

  /// 检查（并可选请求）麦克风权限。
  Future<bool> hasPermission({bool request = true}) async {
    try {
      return await _engine.hasPermission(request: request);
    } catch (_) {
      return false;
    }
  }

  /// 开始录音；失败抛 [VoiceError]。
  Future<void> start() async {
    if (_disposed) throw const VoiceError.unsupportedRecording();
    if (_recording) return;
    _resetTake();
    if (!await isSupported()) {
      throw const VoiceError.unsupportedRecording();
    }
    if (!await hasPermission()) {
      throw const VoiceError.noMicrophonePermission();
    }

    final Directory directory;
    try {
      directory = await getTemporaryDirectory();
    } catch (error) {
      throw VoiceError(
        VoiceErrorKind.unsupportedEnvironment,
        VoiceText.unsupportedRecording,
        cause: error,
      );
    }
    final name = '${DateTime.now().microsecondsSinceEpoch}';
    final path = '${directory.path}$tempFilePrefix$name.wav';
    _path = path;
    try {
      await _engine.start(_config, path: path);
    } catch (error) {
      _path = null;
      if (error is VoiceError) rethrow;
      final denied = error is PlatformException &&
          (error.code == 'permission' ||
              error.code == 'record_permission' ||
              error.code == 'audio_permission');
      if (denied) {
        throw VoiceError.noMicrophonePermission(cause: error);
      }
      throw VoiceError(
        VoiceErrorKind.unsupportedEnvironment,
        VoiceText.unsupportedRecording,
        cause: error,
      );
    }
    _startedAt = DateTime.now();
    _recording = true;
    _timer = Timer.periodic(tickInterval, (_) => _onTick());
    _emitTick();
  }

  /// 结束录音并返回结果；自动结束时与显式调用共享同一个 Future。
  ///
  /// 校验顺序：文件存在 → 字节非空 → 体积 → WAV 头可解析 → 有数据 →
  /// 时长不短于 [minDuration] → 非静音。
  Future<RecordedClip> stop() {
    final existing = _stopFuture;
    if (existing != null) return existing;
    final future = _finishTake();
    _stopFuture = future;
    return future;
  }

  /// 取消录音并删除临时文件。
  Future<void> cancel() async {
    _stopTimer();
    _recording = false;
    _stopFuture = null;
    _lastElapsed = Duration.zero;
    _lastAmplitude = 0;
    _autoStopped = false;
    final path = _path;
    _path = null;
    _emitTick();
    try {
      await _engine.cancel();
    } catch (_) {
      // 插件未启动/平台不支持时忽略
    }
    await _deleteQuietly(path);
  }

  /// 释放录音器与临时文件；之后不可再使用该实例。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _stopTimer();
    _recording = false;
    final path = _path;
    _path = null;
    final recorder = _recorder;
    _recorder = null;
    if (recorder != null) {
      try {
        await recorder.cancel();
      } catch (_) {
        // ignore
      }
      try {
        await recorder.dispose();
      } catch (_) {
        // ignore
      }
    }
    await _deleteQuietly(path);
    await _ticks.close();
  }

  Future<RecordedClip> _finishTake() async {
    final startedAt = _startedAt;
    _stopTimer();
    _recording = false;
    _lastAmplitude = 0;
    if (startedAt != null) {
      _lastElapsed = DateTime.now().difference(startedAt);
    }

    var path = _path;
    try {
      final stoppedPath = await _engine.stop();
      if (stoppedPath != null && stoppedPath.isNotEmpty) {
        path = stoppedPath;
      }
    } catch (error) {
      if (path == null || path.isEmpty) {
        throw VoiceError(
          VoiceErrorKind.recordingFailed,
          VoiceText.unsupportedRecording,
          cause: error,
        );
      }
      // 平台 stop 失败时仍尝试读取已落盘的文件
    }
    _path = null;

    if (path == null || path.isEmpty) {
      throw const VoiceError.recordingEmpty();
    }
    final filePath = path;
    Uint8List bytes;
    final file = File(filePath);
    try {
      if (!await file.exists()) throw const VoiceError.recordingEmpty();
      bytes = await file.readAsBytes();
    } on VoiceError {
      rethrow;
    } catch (error) {
      throw VoiceError(
        VoiceErrorKind.recordingFailed,
        VoiceText.recordingEmpty,
        cause: error,
      );
    } finally {
      await _deleteQuietly(filePath);
    }

    if (bytes.isEmpty) throw const VoiceError.recordingEmpty();
    if (bytes.length > maxBytes) throw const VoiceError.recordingTooLarge();

    final WavHeader header;
    try {
      header = parseWavHeader(bytes);
    } catch (error) {
      throw VoiceError(
        VoiceErrorKind.recordingFailed,
        VoiceText.recordingEmpty,
        cause: error,
      );
    }
    if (header.dataSize <= 0) throw const VoiceError.recordingEmpty();

    final duration = header.duration;
    if (duration <= Duration.zero) throw const VoiceError.recordingEmpty();
    if (duration < minDuration) throw const VoiceError.recordingTooShort();

    final peak = wavPeak(bytes);
    if (peak < silenceThreshold) throw const VoiceError.recordingSilent();

    return RecordedClip(
      path: filePath,
      bytes: bytes,
      duration: duration,
      peak: peak,
      sampleRate: header.sampleRate,
      channels: header.numChannels,
      bitsPerSample: header.bitsPerSample,
    );
  }

  void _onTick() {
    if (!_recording) return;
    final elapsed = _elapsedNow();
    _lastElapsed = elapsed;
    if (elapsed >= maxDuration && !_autoStopped) {
      _autoStopped = true;
      unawaited(
        stop().then<void>(
          (_) {},
          onError: (Object _) {
            // 错误会通过共享的 stop() Future 抛给调用方；这里只避免未处理异步错误
          },
        ),
      );
      return;
    }
    unawaited(_refreshAmplitude(elapsed));
  }

  Future<void> _refreshAmplitude(Duration elapsed) async {
    try {
      final amplitude = await _engine.getAmplitude();
      _lastAmplitude = _normalizeAmplitude(amplitude.current);
    } catch (_) {
      _lastAmplitude = 0;
    }
    _emitTick(elapsed: elapsed);
  }

  void _emitTick({Duration? elapsed}) {
    if (_ticks.isClosed) return;
    _ticks.add((
      elapsed: elapsed ?? _lastElapsed,
      amplitude: _lastAmplitude,
    ));
  }

  Duration _elapsedNow() {
    final startedAt = _startedAt;
    if (startedAt == null) return Duration.zero;
    final elapsed = DateTime.now().difference(startedAt);
    return elapsed > Duration.zero ? elapsed : Duration.zero;
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    _startedAt = null;
  }

  void _resetTake() {
    _stopTimer();
    _stopFuture = null;
    _autoStopped = false;
    _lastElapsed = Duration.zero;
    _lastAmplitude = 0;
    _path = null;
  }

  static double _normalizeAmplitude(double dbfs) {
    if (dbfs.isNaN || dbfs.isInfinite) return 0;
    const floor = -60.0;
    if (dbfs <= floor) return 0;
    if (dbfs >= 0) return 1;
    return (dbfs - floor) / -floor;
  }

  Future<void> _deleteQuietly(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 删除失败不影响主流程
    }
  }
}
