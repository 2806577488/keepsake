/// Keepsake（留声）— 聊天页语音控件。
///
/// 本文件包含两个控件（对应 `dart-symbols.md` `@1164506904` 与 `next-steps.md` §2）：
///
/// 1. [SpeakButton] — 「朗读这条消息 / 停止朗读」TTS 按钮。
///    私有符号：`_SpeakButtonState`、`_SpeakPhase`（idle / loading / playing）、`_toast`、`_toggle`。
/// 2. [HoldToTalkButton] — 「按住说话」按钮，接批次 D 的 `VoiceHoldController` / `VoicePhase`：
///    pointerDown → start（录音），pointerUp → stop（转写并回填），pointerCancel → cancel。
///
/// 文案（ui-strings §4 / prompts.md §7）：
/// 「按住说话」「松开转文字 · 」「正在转写…」「朗读这条消息」「停止朗读」「已停止」
/// 「当前环境不支持录音」「当前环境不支持播放音频」「这条消息没有可朗读的文字」
/// 「语音识别接口不存在：当前平台可能不支持 ASR（目前只有 DeepSeek 提供）」。
///
/// 语音能力（ASR/TTS）只有 DeepSeek 声明；平台不支持时按钮置灰并给出提示，
/// 不会抛异常、不会崩溃（`voicePluginsAvailable` 是同步 bool，web/桌面为 false）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/voice/tts_client.dart';
import '../../core/voice/voice_error.dart';
import '../../core/voice/voice_guards.dart';
import '../../core/voice/voice_hold.dart';

// ---------------------------------------------------------------------------
// 朗读按钮（TTS）
// ---------------------------------------------------------------------------

/// 「朗读这条消息 / 停止朗读」按钮。
///
/// 用法（消息气泡右上角）：
/// ```dart
/// SpeakButton(text: message.plainText, onToast: _toast)
/// ```
class SpeakButton extends ConsumerStatefulWidget {
  const SpeakButton({
    super.key,
    required this.text,
    this.iconSize = 18,
    this.showLabel = false,
    this.onToast,
  });

  /// 要朗读的原始文本（markdown 会先被 [TtsClient.speakableTextOf] 清洗）。
  final String text;

  final double iconSize;

  /// 是否在图标旁显示「朗读这条消息 / 停止朗读」文字。
  final bool showLabel;

  /// 错误/提示文案回调；为空时用 SnackBar。
  final void Function(String message)? onToast;

  @override
  ConsumerState<SpeakButton> createState() => _SpeakButtonState();
}

/// 朗读按钮的三态（符号表 `_SpeakPhase`：idle / loading / playing）。
enum _SpeakPhase {
  /// 空闲。
  idle,

  /// 正在合成语音。
  loading,

  /// 正在播放。
  playing,
}

class _SpeakButtonState extends ConsumerState<SpeakButton> {
  late final TtsClient _tts;
  StreamSubscription<TtsPhase>? _phaseSub;
  _SpeakPhase _phase = _SpeakPhase.idle;

  bool get _busy => _phase != _SpeakPhase.idle;

  @override
  void initState() {
    super.initState();
    _tts = TtsClient();
    _phaseSub = _tts.phaseStream.listen((TtsPhase phase) {
      if (!mounted) return;
      setState(() {
        _phase = switch (phase) {
          TtsPhase.idle => _SpeakPhase.idle,
          TtsPhase.loading => _SpeakPhase.loading,
          TtsPhase.playing => _SpeakPhase.playing,
        };
      });
    });
  }

  @override
  void dispose() {
    unawaited(_phaseSub?.cancel());
    unawaited(_tts.dispose());
    super.dispose();
  }

  /// 统一提示出口（符号表 `_toast`）。
  void _toast(String message) {
    final handler = widget.onToast;
    if (handler != null) {
      handler(message);
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  /// 播放 / 停止切换（符号表 `_toggle`）。
  Future<void> _toggle() async {
    if (_busy) {
      try {
        await _tts.stop();
        _toast(VoiceText.stopped);
      } catch (error) {
        _toast(voiceErrorMessage(error));
      }
      return;
    }
    if (widget.text.trim().isEmpty) {
      _toast(VoiceText.nothingToSpeak);
      return;
    }
    if (!voicePlaybackAvailable) {
      _toast(VoiceText.playbackUnsupported);
      return;
    }
    final config = _resolveConfig();
    if (config == null) {
      _toast(VoiceText.notConfigured);
      return;
    }
    final caps = VoiceCapabilities.fromProviderConfig(config);
    if (!voiceSupportsTts(caps)) {
      _toast('${VoiceText.responseReturnPrefix}当前平台可能不支持 TTS');
      return;
    }
    final speakable = TtsClient.speakableTextOf(widget.text);
    if (speakable.trim().isEmpty) {
      _toast(VoiceText.nothingToSpeak);
      return;
    }
    final settings = ref.read(settingsProvider);
    try {
      await _tts.speak(
        caps: caps,
        text: widget.text,
        voiceId: settings.ttsVoice.trim().isEmpty ? null : settings.ttsVoice.trim(),
        speed: settings.ttsSpeed <= 0 ? 1.0 : settings.ttsSpeed,
      );
    } catch (error) {
      _toast(voiceErrorMessage(error));
    }
  }

  /// 解析当前平台配置（会话/设置/列表首个，优先级由 [ProviderConfigResolver] 决定）。
  ProviderConfig? _resolveConfig() {
    final book = ref.read(providerBookProvider);
    final settings = ref.read(settingsProvider);
    return ProviderConfigResolver(book: book, settings: settings).resolve();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = widget.text.trim().isNotEmpty;
    final color = _busy ? scheme.primary : scheme.onSurfaceVariant;
    final icon = switch (_phase) {
      _SpeakPhase.idle => Icons.volume_up_outlined,
      _SpeakPhase.loading => Icons.graphic_eq_rounded,
      _SpeakPhase.playing => Icons.stop_circle_outlined,
    };
    final tooltip = switch (_phase) {
      _SpeakPhase.idle => '朗读这条消息',
      _SpeakPhase.loading => VoiceText.synthesizing,
      _SpeakPhase.playing => '停止朗读',
    };
    final button = IconButton(
      onPressed: enabled ? _toggle : null,
      iconSize: widget.iconSize,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: const EdgeInsets.all(4),
      tooltip: tooltip,
      icon: Icon(icon, color: enabled ? color : scheme.onSurfaceVariant.withValues(alpha: 0.4)),
    );
    if (!widget.showLabel) return button;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        button,
        Text(
          tooltip,
          style: theme.textTheme.labelSmall?.copyWith(
            color: enabled ? color : scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 按住说话按钮（ASR）
// ---------------------------------------------------------------------------

/// 「按住说话」按钮：按住录音，松手转文字并回填输入框。
///
/// - 环境/插件不可用（web、桌面无录音实现）→ 置灰，点击提示「当前环境不支持录音」；
/// - 当前平台不支持 ASR（非 DeepSeek）→ 提示
///   「语音识别接口不存在：当前平台可能不支持 ASR（目前只有 DeepSeek 提供）」；
/// - 其余失败由 `VoiceError` → 中文文案（`voiceErrorMessage`）走 [onToast]。
class HoldToTalkButton extends ConsumerStatefulWidget {
  const HoldToTalkButton({
    super.key,
    required this.onText,
    this.onToast,
    this.enabled = true,
    this.showHint = true,
    this.size = 40,
  });

  /// 识别成功后的回填回调（把文本插到输入框光标处）。
  final void Function(String text) onText;

  /// 提示文案回调；为空时用 SnackBar。
  final void Function(String message)? onToast;

  /// 外层是否允许使用（例如正在流式生成时置灰）。
  final bool enabled;

  /// 是否在按钮旁显示状态提示（「按住说话」/「松开转文字 · 0:03」/「正在转写…」）。
  final bool showHint;

  /// 按钮直径。
  final double size;

  @override
  ConsumerState<HoldToTalkButton> createState() => _HoldToTalkButtonState();
}

class _HoldToTalkButtonState extends ConsumerState<HoldToTalkButton>
    with WidgetsBindingObserver {
  VoiceHoldController? _hold;
  VoiceHoldState _state = const VoiceHoldState();
  bool _disposed = false;

  VoicePhase get _phase => _state.phase;

  bool get _recording => _phase == VoicePhase.recording;

  bool get _transcribing => _phase == VoicePhase.transcribing;

  /// 插件/平台是否支持录音（同步 bool）。
  bool get _environmentOk => voicePluginsAvailable && voiceRecordingAvailable;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    final hold = _hold;
    _hold = null;
    if (hold != null) unawaited(hold.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 切后台时丢弃本次录音，避免一直占着麦克风。
    if (state != AppLifecycleState.resumed) {
      final hold = _hold;
      if (hold != null && hold.state.isBusy) unawaited(hold.cancel());
    }
  }

  /// 懒建控制器（`onText` / `capabilities` 在按下时才读最新配置）。
  VoiceHoldController get _controller => _hold ??= VoiceHoldController(
        // 注意：批次 D 的 `capabilities` 回调是非空返回，所以拿不到配置时给一个
        // 「无凭据」的能力对象；真正的门禁在 [_onPointerDown] 里先行提示。
        capabilities: () => _capabilitiesOrNull() ?? VoiceCapabilities.forProvider(null),
        onText: (String text) {
          if (_disposed) return;
          widget.onText(text);
        },
        onError: (VoiceError error) => _toast(voiceErrorMessage(error)),
        onState: (VoiceHoldState state) {
          if (_disposed || !mounted) return;
          setState(() => _state = state);
        },
      );

  /// 转写前读取当前平台能力；未配置平台时返回 null。
  VoiceCapabilities? _capabilitiesOrNull() {
    final book = ref.read(providerBookProvider);
    final settings = ref.read(settingsProvider);
    final config = ProviderConfigResolver(book: book, settings: settings).resolve();
    if (config == null) return null;
    return VoiceCapabilities.fromProviderConfig(config);
  }

  void _toast(String message) {
    final handler = widget.onToast;
    if (handler != null) {
      handler(message);
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  /// 按下：做门禁检查后开始录音。
  Future<void> _onPointerDown(PointerDownEvent event) async {
    if (!widget.enabled || _transcribing) return;
    if (!_environmentOk) {
      _toast(VoiceText.unsupportedRecording);
      return;
    }
    final caps = _capabilitiesOrNull();
    if (caps == null) {
      _toast(VoiceText.notConfigured);
      return;
    }
    if (!voiceSupportsAsr(caps)) {
      _toast(VoiceText.asrUnsupported);
      return;
    }
    await _controller.start();
  }

  /// 松开：结束录音并转写（不 await，避免阻塞手势）。
  void _onPointerUp(PointerUpEvent event) {
    if (!_recording) {
      // 极短点击（没进入 recording）也要把残留状态清干净。
      if (!_transcribing) _controller.clearError();
      return;
    }
    unawaited(_controller.stop());
  }

  /// 取消（手指划出按钮/系统打断）。
  void _onPointerCancel(PointerCancelEvent event) {
    unawaited(_controller.cancel());
  }

  /// 点击（辅助功能 / 无障碍）：不支持按住时给提示。
  VoidCallback? get _onTap {
    if (!_environmentOk || !widget.enabled) {
      return () => _toast(VoiceText.unsupportedRecording);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final usable = widget.enabled && _environmentOk && !_transcribing;
    final foreground = _recording
        ? scheme.onErrorContainer
        : usable
            ? scheme.onSurfaceVariant
            : scheme.onSurfaceVariant.withValues(alpha: 0.4);
    final background = _recording
        ? scheme.errorContainer
        : _transcribing
            ? scheme.primaryContainer
            : Colors.transparent;

    final mic = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
      ),
      child: _transcribing
          ? Padding(
              padding: EdgeInsets.all(widget.size * 0.3),
              child: const CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              _recording ? Icons.mic_rounded : Icons.mic_none_rounded,
              size: widget.size * 0.55,
              color: foreground,
            ),
    );

    final hint = _state.hintText;
    final label = _recording ? _state.hintText : (usable ? '按住说话' : '语音不可用');

    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: usable || _recording ? '按住说话' : '当前环境不支持录音',
        child: GestureDetector(
          onTap: _onTap,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onPointerDown,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerCancel,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                mic,
                if (widget.showHint && _state.phase != VoicePhase.idle)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      hint,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _recording ? scheme.error : scheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
