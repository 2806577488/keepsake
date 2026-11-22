// 「按住说话」状态机：按住录音 → 松手转写 → 回填文本 / 取消。
//
// 状态：idle / recording / transcribing / error
// 事件：状态流（stateStream）、ValueListenable（listenable）、文本回调（onText）、
//      错误回调（onError）、统一回调（onState）。
//
// 文案：
//   * 按住说话            → VoiceHoldController.holdHint
//   * 松开转文字 · 0:03   → VoiceHoldController.releaseHint(elapsed)
//   * 正在转写…           → VoiceText.transcribing（转写阶段）
//   * 按住时间太短，说完再松手 / 没有录到声音，再试一次 … → VoiceError.message

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;

import 'package:keepsake/core/voice/asr_client.dart';
import 'package:keepsake/core/voice/recorder.dart';
import 'package:keepsake/core/voice/voice_error.dart';
import 'package:keepsake/core/voice/voice_guards.dart';

/// 按住说话的阶段。
enum VoicePhase {
  /// 空闲，等待按下。
  idle,

  /// 正在录音（按住中）。
  recording,

  /// 录音已结束，正在请求 ASR。
  transcribing,

  /// 上一步失败；VoiceHoldState.error 带可展示文案，下次按下自动复位。
  error,
}

/// 按住说话的不可变状态快照。
class VoiceHoldState {
  const VoiceHoldState({
    this.phase = VoicePhase.idle,
    this.elapsed = Duration.zero,
    this.amplitude = 0,
    this.text,
    this.error,
    this.autoStopped = false,
  });

  final VoicePhase phase;

  /// 录音已持续时长（recording 阶段实时更新）。
  final Duration elapsed;

  /// 当前振幅 0..1（供音量条动画）。
  final double amplitude;

  /// 最近一次识别成功的文本。
  final String? text;

  /// 失败时的错误（phase == error 时有值）。
  final VoiceError? error;

  /// 是否因达到最大时长自动结束（而不是用户松手）。
  final bool autoStopped;

  bool get isRecording => phase == VoicePhase.recording;

  bool get isTranscribing => phase == VoicePhase.transcribing;

  bool get isBusy => isRecording || isTranscribing;

  bool get hasError => phase == VoicePhase.error;

  /// 可直接展示的状态文案（按钮下方/输入框上方）。
  String get hintText {
    switch (phase) {
      case VoicePhase.idle:
        return VoiceHoldController.holdHint;
      case VoicePhase.recording:
        return VoiceHoldController.releaseHint(elapsed);
      case VoicePhase.transcribing:
        return VoiceText.transcribing;
      case VoicePhase.error:
        return error?.message ?? VoiceText.serviceErrorPrefix;
    }
  }

  /// 录音时长的展示文本（`0:03`）。
  String get durationLabel => formatVoiceDuration(elapsed);

  /// 剩余可录时长（UI 可显示倒计时）。
  Duration get remaining {
    final left = VoiceRecorder.defaultMaxDuration - elapsed;
    return left > Duration.zero ? left : Duration.zero;
  }

  static const Object _unset = Object();

  VoiceHoldState copyWith({
    VoicePhase? phase,
    Duration? elapsed,
    double? amplitude,
    Object? text = _unset,
    Object? error = _unset,
    bool? autoStopped,
  }) {
    return VoiceHoldState(
      phase: phase ?? this.phase,
      elapsed: elapsed ?? this.elapsed,
      amplitude: amplitude ?? this.amplitude,
      text: identical(text, _unset) ? this.text : text as String?,
      error: identical(error, _unset) ? this.error : error as VoiceError?,
      autoStopped: autoStopped ?? this.autoStopped,
    );
  }

  @override
  String toString() =>
      'VoiceHoldState($phase, ${elapsed.inMilliseconds}ms, '
      'amplitude=$amplitude, text=$text, error=$error)';
}

/// 把时长格式化成 `分:秒`（`0:03`、`1:09`）。
String formatVoiceDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// 按住说话控制器。
///
/// 使用（Widget 持有或由 Riverpod Provider 持有均可，本类不依赖 Riverpod）：
/// ```dart
/// final hold = VoiceHoldController(
///   capabilities: () => VoiceCapabilities.forProvider(currentProvider),
///   onText: (text) => controller.insertText(text),
///   onError: (error) => toast(voiceErrorMessage(error)),
/// );
/// // Listener(onPointerDown: (_) => hold.start(), onPointerUp: (_) => hold.stop())
/// StreamBuilder<VoiceHoldState>(stream: hold.stateStream, ...)
/// ```
///
/// 生命周期：Widget dispose 时调用 `hold.dispose()`（异步，unawaited 即可）。
/// 控制器拥有注入的 VoiceRecorder / AsrClient，由自己释放。
class VoiceHoldController {
  VoiceHoldController({
    VoiceRecorder? recorder,
    AsrClient? asrClient,
    this.capabilities,
    this.onText,
    this.onError,
    this.onState,
  })  : _recorder = recorder ?? VoiceRecorder(),
        _asr = asrClient ?? AsrClient();

  /// 「按住说话」提示原文。
  static const String holdHint = VoiceText.holdToTalk;

  /// 「正在转写…」提示原文。
  static const String transcribingHint = VoiceText.transcribing;

  /// 「松开转文字 · 」前缀原文（尾随空格保留）。
  static const String releaseHintPrefix = VoiceText.releaseToTranscribePrefix;

  /// 录音中提示：`松开转文字 · 0:03`。
  static String releaseHint(Duration elapsed) =>
      '$releaseHintPrefix${formatVoiceDuration(elapsed)}';

  final VoiceRecorder _recorder;
  final AsrClient _asr;

  /// 取当前 AI 平台语音能力的回调（转写前读取）。
  final VoiceCapabilities Function()? capabilities;

  /// 识别成功后回调，UI 把文本回填输入框。
  final void Function(String text)? onText;

  /// 失败时回调，UI 用 `voiceErrorMessage(error)` 展示。
  final void Function(VoiceError error)? onError;

  /// 每次状态变化回调（可选）。
  final void Function(VoiceHoldState state)? onState;

  final StreamController<VoiceHoldState> _controller =
      StreamController<VoiceHoldState>.broadcast();
  final ValueNotifier<VoiceHoldState> _notifier =
      ValueNotifier<VoiceHoldState>(const VoiceHoldState());

  VoiceHoldState _state = const VoiceHoldState();
  StreamSubscription<VoiceRecordingTick>? _tickSub;
  Future<void>? _startFuture;
  bool _finishing = false;
  int _generation = 0;
  bool _closed = false;

  /// 当前状态快照。
  VoiceHoldState get state => _state;

  /// 状态变化流（广播）。
  Stream<VoiceHoldState> get stateStream => _controller.stream;

  /// 状态 ValueListenable（适合 ValueListenableBuilder）。
  ValueListenable<VoiceHoldState> get listenable => _notifier;

  /// 底层录音器（UI 可读 maxDuration 画倒计时）。
  VoiceRecorder get recorder => _recorder;

  /// 当前是否可开始新一轮录音。
  bool get canStart =>
      !_closed &&
      (_state.phase == VoicePhase.idle || _state.phase == VoicePhase.error);

  /// 按下：开始录音。
  Future<void> start() async {
    if (!canStart) return;
    final generation = ++_generation;
    _emit(
      _state.copyWith(
        phase: VoicePhase.recording,
        elapsed: Duration.zero,
        amplitude: 0,
        autoStopped: false,
        text: null,
        error: null,
      ),
    );
    final future = _startRecording(generation);
    _startFuture = future;
    await future;
  }

  /// 松开：结束录音 → 转写 → 回调文本。
  Future<void> stop() async {
    if (_closed) return;
    final pending = _startFuture;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // 启动失败已由 _startRecording 转成 error 状态
      }
    }
    if (_closed || _state.phase != VoicePhase.recording) return;
    await _finish();
  }

  /// 取消（录音中丢弃本次录音；转写中丢弃返回结果）。
  Future<void> cancel() async {
    if (_closed) return;
    _generation++;
    final subscription = _tickSub;
    _tickSub = null;
    await subscription?.cancel();
    final wasRecording = _state.phase == VoicePhase.recording;
    if (wasRecording) {
      try {
        await _recorder.cancel();
      } catch (_) {
        // ignore
      }
    }
    if (!_closed) _emit(const VoiceHoldState());
  }

  /// 清除错误状态（回到 idle）。
  void clearError() {
    if (_closed) return;
    if (_state.phase == VoicePhase.error) {
      _emit(const VoiceHoldState());
    }
  }

  /// 释放录音器、ASR client 与事件流；之后不可再使用。
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _generation++;
    final subscription = _tickSub;
    _tickSub = null;
    await subscription?.cancel();
    try {
      await _recorder.dispose();
    } catch (_) {
      // ignore
    }
    try {
      _asr.close();
    } catch (_) {
      // ignore
    }
    _notifier.dispose();
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  Future<void> _startRecording(int generation) async {
    try {
      await _recorder.start();
      if (_closed || generation != _generation) {
        await _recorder.cancel();
        return;
      }
      _tickSub = _recorder.ticks.listen(
        _onTick,
        onError: (Object error) => _fail(generation, VoiceError.wrap(error)),
      );
      _emit(
        _state.copyWith(
          phase: VoicePhase.recording,
          elapsed: _recorder.elapsed,
          amplitude: _recorder.amplitude,
          autoStopped: false,
        ),
      );
    } on VoiceError catch (error) {
      _fail(generation, error);
    } catch (error) {
      _fail(generation, VoiceError.wrap(error));
    }
  }

  void _onTick(VoiceRecordingTick tick) {
    if (_closed || _state.phase != VoicePhase.recording) return;
    _emit(_state.copyWith(elapsed: tick.elapsed, amplitude: tick.amplitude));
    if (tick.elapsed >= _recorder.maxDuration) {
      unawaited(_finish());
    }
  }

  Future<void> _finish() async {
    if (_finishing || _closed) return;
    _finishing = true;
    final generation = _generation;
    final subscription = _tickSub;
    _tickSub = null;
    await subscription?.cancel();
    try {
      final clip = await _recorder.stop();
      if (_closed || generation != _generation) return;
      _emit(
        _state.copyWith(
          phase: VoicePhase.transcribing,
          elapsed: Duration.zero,
          amplitude: 0,
          autoStopped: _recorder.autoStopped,
          error: null,
        ),
      );
      final caps = capabilities?.call();
      if (caps == null) {
        _fail(generation, const VoiceError.notConfigured());
        return;
      }
      final text = await _asr.transcribe(caps: caps, wav: clip.bytes);
      if (_closed || generation != _generation) return;
      _emit(VoiceHoldState(phase: VoicePhase.idle, text: text));
      onText?.call(text);
    } on VoiceError catch (error) {
      if (!_closed && generation == _generation) {
        _fail(generation, error);
      }
    } catch (error) {
      if (!_closed && generation == _generation) {
        _fail(generation, VoiceError.wrap(error));
      }
    } finally {
      _finishing = false;
    }
  }

  void _fail(int generation, VoiceError error) {
    if (_closed || generation != _generation) return;
    _emit(VoiceHoldState(phase: VoicePhase.error, error: error));
    onError?.call(error);
  }

  void _emit(VoiceHoldState state) {
    if (_closed) return;
    _state = state;
    _notifier.value = state;
    if (!_controller.isClosed) {
      _controller.add(state);
    }
    onState?.call(state);
  }
}
