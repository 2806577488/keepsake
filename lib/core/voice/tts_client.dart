// TTS（语音合成）客户端 + just_audio 播放。
//
// 端点：`ttsUrlOf(baseUrl)` = `{base}/audio/speech`（推断，OpenAI 风格）。
// 请求体：由 `ttsBodyOf(text, voice, speed, format)` 生成，含
//   `input` / `voice_id` / `speed` / `response_format`（均为 APK 字符串表证据字段）。
// 响应：音频字节（wav/mp3）→ 写临时文件 `/keepsake_tts_*` → just_audio 播放。
// 计费字数：`ttsBillingChars(text)`。
//
// 只有 DeepSeek 平台声明 supportsTts（详见 voice_guards.dart）。
// 错误全部转成 VoiceError；音频临时文件在替换/释放时清理。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'package:keepsake/core/voice/voice_error.dart';
import 'package:keepsake/core/voice/voice_guards.dart';

/// TTS 路径后缀（推断，OpenAI 风格）。
const String ttsPathSuffix = '/audio/speech';

/// 默认 voice_id（接口未配置音色时的兜底值）。
const String ttsDefaultVoice = 'default';

/// 默认音频格式。
const String ttsDefaultFormat = 'mp3';

/// 默认语速。
const double ttsDefaultSpeed = 1.0;

/// TTS 临时文件前缀（情报原文 `/keepsake_tts_`）。
const String tempTtsFilePrefix = '/keepsake_tts_';

/// 推断的 TTS 端点。
String ttsUrlOf(String baseUrl) {
  return '${normalizeVoiceBaseUrl(baseUrl)}$ttsPathSuffix';
}

/// 生成 TTS 请求体。
///
/// 字段名来自 APK 字符串表：`voice_id`、`input`、`speed`、`response_format`。
Map<String, Object?> ttsBodyOf(
  String text, [
  String voice = ttsDefaultVoice,
  double speed = ttsDefaultSpeed,
  String format = ttsDefaultFormat,
]) {
  return <String, Object?>{
    'input': text,
    'voice_id': voice,
    'speed': speed,
    'response_format': format,
  };
}

/// 计费字数：按 Unicode 码点计数并忽略空白（中文 1 字 = 1）。
int ttsBillingChars(String text) {
  if (text.isEmpty) return 0;
  return text.replaceAll(RegExp(r'\s+'), '').runes.length;
}

/// 播放阶段（对应 UI 的 `_SpeakPhase`：idle / loading / playing）。
enum TtsPhase { idle, loading, playing }

/// 一次合成结果。
class TtsClip {
  const TtsClip({
    required this.path,
    required this.bytes,
    required this.format,
    required this.text,
    required this.billingChars,
    this.duration,
  });

  /// 临时文件路径（`/keepsake_tts_*`）。
  final String path;

  /// 音频字节。
  final Uint8List bytes;

  /// 实际音频格式（由响应 content-type 推断，失败时用请求值）。
  final String format;

  /// 实际送去合成的文本（已 trim）。
  final String text;

  /// 计费字数。
  final int billingChars;

  /// 播放器解析出的时长（可能为 null）。
  final Duration? duration;

  int get sizeInBytes => bytes.length;

  bool get isEmpty => bytes.isEmpty;

  @override
  String toString() => 'TtsClip($path, $format, $sizeInBytes bytes)';
}

/// 语音合成 + 播放客户端。
///
/// 典型用法（SpeakButton）：
/// ```dart
/// final tts = TtsClient();
/// await tts.speak(caps: VoiceCapabilities.forProvider(provider), text: messageText);
/// await tts.stop();
/// ```
class TtsClient {
  TtsClient({
    http.Client? client,
    AudioPlayer? player,
    this.timeout = const Duration(seconds: 60),
  })  : _injectedClient = client,
        _injectedPlayer = player;

  final http.Client? _injectedClient;
  final AudioPlayer? _injectedPlayer;

  /// 单次请求超时。
  final Duration timeout;

  http.Client? _ownedClient;
  AudioPlayer? _player;
  final StreamController<TtsPhase> _phaseController =
      StreamController<TtsPhase>.broadcast();
  final Set<String> _tempFiles = <String>{};

  TtsPhase _phase = TtsPhase.idle;
  TtsClip? _currentClip;
  Duration? _duration;
  bool _sessionReady = false;
  bool _stoppedByUser = false;
  bool _disposed = false;

  http.Client get _http =>
      _injectedClient ?? (_ownedClient ??= http.Client());

  /// 当前播放阶段。
  TtsPhase get phase => _phase;

  /// 播放阶段变化流（广播）。
  Stream<TtsPhase> get phaseStream => _phaseController.stream;

  /// 当前播放位置（播放器未创建时为 Duration.zero）。
  Duration get position => _player?.position ?? Duration.zero;

  /// 当前音频时长（未知时为 null）。
  Duration? get duration => _duration ?? _player?.duration;

  /// 播放位置流（播放器未创建时为空流）。
  Stream<Duration> get positionStream =>
      _player?.positionStream ?? const Stream<Duration>.empty();

  /// 当前合成结果（最后一次）。
  TtsClip? get currentClip => _currentClip;

  /// 把文本合成为音频并写入临时文件（不播放）。
  ///
  /// 空文本抛「要朗读的文本为空」；返回空字节抛「TTS 返回了空音频」；
  /// 响应是 JSON 错误体时抛「TTS 返回了错误响应」。
  Future<TtsClip> synthesize({
    required VoiceCapabilities caps,
    required String text,
    String? voiceId,
    double speed = ttsDefaultSpeed,
    String? format,
  }) async {
    if (_disposed) throw const VoiceError.ttsEmptyAudio();
    final baseUrl = caps.baseUrl?.trim() ?? '';
    final apiKey = caps.apiKey?.trim() ?? '';
    if (baseUrl.isEmpty || apiKey.isEmpty) {
      throw const VoiceError.notConfigured();
    }
    if (!voiceSupportsTts(caps)) {
      throw VoiceError(
        VoiceErrorKind.ttsUnsupported,
        '${VoiceText.responseErrorPrefix}${VoiceText.ttsUnsupportedProvider}',
      );
    }
    final spoken = text.trim();
    if (spoken.isEmpty) throw const VoiceError.ttsEmptyText();

    final uri = Uri.tryParse(ttsUrlOf(baseUrl));
    if (uri == null || uri.host.isEmpty) {
      throw const VoiceError.notConfigured();
    }

    final requestedFormat = _nonEmpty(format) ?? ttsDefaultFormat;
    final voice = _nonEmpty(voiceId) ?? ttsDefaultVoice;
    final body = ttsBodyOf(spoken, voice, speed, requestedFormat);
    final request = http.Request('POST', uri)
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..headers['Content-Type'] = 'application/json; charset=utf-8'
      ..headers['Accept'] = 'audio/*, application/json'
      ..body = jsonEncode(body);

    try {
      final streamed = await _http.send(request).timeout(timeout);
      final status = streamed.statusCode;
      final contentType =
          (streamed.headers['content-type'] ?? '').toLowerCase();
      final bytes = await streamed.stream.toBytes().timeout(timeout);

      if (status < 200 || status >= 300) {
        throw VoiceError(
          VoiceErrorKind.ttsBadResponse,
          '${VoiceText.responseReturnPrefix}${VoiceError.httpDetail(status)}',
          statusCode: status,
        );
      }
      if (bytes.isEmpty) throw const VoiceError.ttsEmptyAudio();
      if (contentType.contains('application/json') || _looksLikeJson(bytes)) {
        throw const VoiceError.ttsBadResponse();
      }

      final actualFormat = _formatFromContentType(contentType) ??
          _normalizeFormat(requestedFormat);
      final path = await _writeTempFile(bytes, actualFormat);
      if (_disposed) {
        await _deleteQuietly(path);
        throw const VoiceError.ttsEmptyAudio();
      }
      final clip = TtsClip(
        path: path,
        bytes: bytes,
        format: actualFormat,
        text: spoken,
        billingChars: ttsBillingChars(spoken),
      );
      final previous = _currentClip;
      _currentClip = clip;
      if (previous != null && previous.path != clip.path) {
        _tempFiles.remove(previous.path);
        await _deleteQuietly(previous.path);
      }
      return clip;
    } on VoiceError {
      rethrow;
    } on TimeoutException catch (error) {
      throw VoiceError.network(cause: error);
    } on http.ClientException catch (error) {
      throw VoiceError.network(cause: error);
    } on SocketException catch (error) {
      throw VoiceError.network(cause: error);
    } catch (error) {
      throw VoiceError.wrap(
        error,
        kind: VoiceErrorKind.ttsBadResponse,
        message: '${VoiceText.serviceErrorPrefix}$error',
      );
    }
  }

  /// 播放一个已合成的音频片段。
  Future<void> play(TtsClip clip) async {
    if (!voicePlaybackAvailable) {
      throw const VoiceError.playbackUnsupported();
    }
    if (clip.bytes.isEmpty) throw const VoiceError.ttsEmptyAudio();
    final player = _player ??= _injectedPlayer ?? AudioPlayer();
    await _ensureAudioSession();
    _stoppedByUser = false;
    _setPhase(TtsPhase.loading);
    try {
      final duration = await player.setFilePath(clip.path);
      _duration = duration ?? clip.duration;
      _setPhase(TtsPhase.playing);
      await player.play();
      if (!_stoppedByUser && _phase == TtsPhase.playing) {
        _setPhase(TtsPhase.idle);
      }
    } on VoiceError {
      rethrow;
    } catch (error) {
      if (_stoppedByUser) return;
      _setPhase(TtsPhase.idle);
      throw VoiceError(
        VoiceErrorKind.playbackFailed,
        '${VoiceText.playbackFailedPrefix}${_shortError(error)}',
        cause: error,
      );
    }
  }

  /// 合成并播放（一键朗读）。
  ///
  /// 文本剔除代码块/图片等不可朗读内容后为空 → 「这条消息没有可朗读的文字」。
  Future<void> speak({
    required VoiceCapabilities caps,
    required String text,
    String? voiceId,
    double speed = ttsDefaultSpeed,
    String? format,
  }) async {
    final spoken = speakableTextOf(text);
    if (spoken.isEmpty) throw const VoiceError.nothingToSpeak();
    final clip = await synthesize(
      caps: caps,
      text: spoken,
      voiceId: voiceId,
      speed: speed,
      format: format,
    );
    await play(clip);
  }

  /// 停止播放（幂等）。
  Future<void> stop() async {
    _stoppedByUser = true;
    try {
      await _player?.stop();
    } catch (_) {
      // 播放器未创建/已释放时忽略
    }
    _setPhase(TtsPhase.idle);
  }

  /// 释放播放器、HTTP client 与全部临时文件。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _stoppedByUser = true;
    try {
      await _player?.stop();
    } catch (_) {
      // ignore
    }
    try {
      await _player?.dispose();
    } catch (_) {
      // ignore
    }
    _player = null;
    _ownedClient?.close();
    _ownedClient = null;
    for (final path in _tempFiles.toList(growable: false)) {
      await _deleteQuietly(path);
    }
    _tempFiles.clear();
    _currentClip = null;
    if (!_phaseController.isClosed) {
      await _phaseController.close();
    }
  }

  /// 剔除不可朗读内容（代码块/行内代码/图片），压缩空白。
  static String speakableTextOf(String? raw) {
    if (raw == null) return '';
    var text = raw.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
    text = text.replaceAll(RegExp(r'`[^`]*`'), ' ');
    text = text.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ' ');
    text = text.replaceAllMapped(
      RegExp(r'\[([^\]]*)\]\([^)]*\)'),
      (match) => match.group(1) ?? '',
    );
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text;
  }

  Future<void> _ensureAudioSession() async {
    if (_sessionReady) return;
    _sessionReady = true;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
    } catch (_) {
      // audio_session 在部分平台不可用；配置失败不阻塞播放
    }
  }

  Future<String> _writeTempFile(Uint8List bytes, String format) async {
    final directory = await getTemporaryDirectory();
    final extension = _normalizeFormat(format);
    final name = DateTime.now().microsecondsSinceEpoch;
    final path = '${directory.path}$tempTtsFilePrefix$name.$extension';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    final length = await file.length();
    if (length <= 0) {
      await _deleteQuietly(path);
      throw const VoiceError.ttsEmptyFile();
    }
    _tempFiles.add(path);
    return path;
  }

  void _setPhase(TtsPhase phase) {
    _phase = phase;
    if (!_phaseController.isClosed) {
      _phaseController.add(phase);
    }
  }

  Future<void> _deleteQuietly(String path) async {
    if (path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 删除失败不影响主流程
    }
  }

  static bool _looksLikeJson(Uint8List bytes) {
    for (final byte in bytes) {
      if (byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D) {
        continue;
      }
      return byte == 0x7B || byte == 0x5B; // '{' or '['
    }
    return false;
  }

  static String _shortError(Object error) {
    var text = error.toString();
    if (text.startsWith('Exception: ')) {
      text = text.substring('Exception: '.length);
    }
    if (text.length > 120) {
      text = '${text.substring(0, 120)}…';
    }
    return text;
  }

  static String? _formatFromContentType(String contentType) {
    if (contentType.isEmpty) return null;
    if (contentType.contains('wav') || contentType.contains('pcm')) {
      return 'wav';
    }
    if (contentType.contains('mpeg') || contentType.contains('mp3')) {
      return 'mp3';
    }
    if (contentType.contains('ogg') || contentType.contains('opus')) {
      return 'ogg';
    }
    if (contentType.contains('aac') ||
        contentType.contains('mp4') ||
        contentType.contains('m4a')) {
      return 'm4a';
    }
    if (contentType.contains('webm')) return 'webm';
    return null;
  }

  static String _normalizeFormat(String format) {
    final value = format.trim().toLowerCase();
    if (value.isEmpty) return ttsDefaultFormat;
    final slash = value.indexOf('/');
    if (slash >= 0) {
      return _normalizeFormat(value.substring(slash + 1));
    }
    switch (value) {
      case 'mpeg':
      case 'mp3':
        return 'mp3';
      case 'x-wav':
      case 'wave':
        return 'wav';
      case 'mp4':
        return 'm4a';
      case 'opus':
        return 'ogg';
    }
    if (RegExp(r'^[a-z0-9]{2,5}$').hasMatch(value)) return value;
    return ttsDefaultFormat;
  }
}

String? _nonEmpty(String? value) {
  final text = value?.trim() ?? '';
  return text.isEmpty ? null : text;
}
