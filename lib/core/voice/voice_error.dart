// 语音链路的统一错误类型与中文可展示文案。
//
// 文案全部取自 APK 字符串表（reports/apk/ui-strings.txt §4、prompts.md §7），
// 带冒号的是「前缀 + 详情」式拼接文案，保持原文冒号（含全角冒号）。
//
// 设计目标：
//   * 语音链路上任何失败都收敛成 [VoiceError]，UI 只需 `voiceErrorMessage(e)` 即可展示；
//   * 不依赖 core/api 的 ApiError（避免跨批次编译依赖），HTTP 状态码映射在本文件内完成。

/// 语音错误分类，便于 UI 决定展示方式（toast / 行内 / 是否可重试）。
enum VoiceErrorKind {
  /// 当前平台/环境不具备该能力（录音、播放等）。
  unsupportedEnvironment,

  /// 麦克风权限被拒绝。
  permissionDenied,

  /// 录音启动失败或录音文件损坏。
  recordingFailed,

  /// 按住时间太短。
  recordingTooShort,

  /// 录音为空（没有文件/没有 PCM 数据）。
  recordingEmpty,

  /// 录到了音频但全是静音。
  recordingSilent,

  /// 录音文件超过体积上限。
  recordingTooLarge,

  /// 没有可用的平台配置（baseUrl / apiKey 缺失）。
  notConfigured,

  /// 当前平台/平台配置不支持 ASR。
  asrUnsupported,

  /// ASR 返回空响应体。
  asrEmptyResponse,

  /// ASR 响应无法解析。
  asrBadResponse,

  /// ASR 响应里没有 text 字段。
  asrNoText,

  /// ASR 成功但识别文本为空。
  asrNoSpeech,

  /// 要朗读的文本为空。
  ttsEmptyText,

  /// 当前平台/平台配置不支持 TTS。
  ttsUnsupported,

  /// TTS 返回空字节。
  ttsEmptyAudio,

  /// TTS 音频写入临时文件后长度为 0。
  ttsEmptyFile,

  /// TTS 返回了 JSON 错误体而不是音频。
  ttsBadResponse,

  /// 播放器播放失败。
  playbackFailed,

  /// 网络不可用 / 超时。
  network,

  /// 未归类错误。
  unknown,
}

/// 语音相关中文文案原文（来自 APK 字符串表，标注 [确定]）。
class VoiceText {
  const VoiceText._();

  // ---- 录音 ----
  static const String unsupportedRecording = '当前环境不支持录音';
  static const String noMicrophonePermission = '没有麦克风权限';
  static const String recordingTooShort = '按住时间太短，说完再松手';
  static const String recordingSilent = '没有录到声音，再试一次';
  static const String recordingEmpty = '录音为空，没有可识别的内容';
  static const String recordingTooLarge = '录音文件太大，请缩短录音';

  // ---- ASR ----
  static const String asrNoTextField = '识别结果里没有 text 字段';
  static const String asrEmptyResponse = '识别服务返回了空响应';
  static const String asrBadResponse = '无法解析识别结果';
  static const String asrNoSpeech = '没有识别到语音';
  static const String asrUnsupported =
      '语音识别接口不存在：当前平台可能不支持 ASR（目前只有 DeepSeek 提供）';

  // ---- 服务错误前缀 ----
  static const String serviceErrorPrefix = '语音服务出错：';
  static const String serviceBusy = '语音服务繁忙，稍后再试';
  static const String responseErrorPrefix = '语音服务响应异常：';
  static const String responseReturnPrefix = '语音服务返回异常：';

  // ---- TTS ----
  static const String ttsEmptyAudio = 'TTS 返回了空音频';
  static const String ttsEmptyFile = 'TTS 音频为空';
  static const String ttsBadResponse = 'TTS 返回了错误响应';
  static const String ttsEmptyText = '要朗读的文本为空';
  static const String nothingToSpeak = '这条消息没有可朗读的文字';
  static const String ttsUnsupportedProvider = '当前平台可能不支持 TTS';

  // ---- 播放 ----
  static const String playbackUnsupportedShort = '当前环境不支持播放';
  static const String playbackUnsupported = '当前环境不支持播放音频';
  static const String playbackFailedShort = '播放失败';
  static const String playbackFailedPrefix = '播放失败：';

  // ---- 通用 ----
  static const String networkError = '网络错误，请检查网络后重试';
  static const String tooManyRequests = '请求太频繁，稍后再试';
  static const String insufficientBalance = '余额不足，请充值后再试';
  static const String invalidApiKey = 'API Key 无效或未填写';
  static const String notConfigured = '先到设置里配置 AI 平台的 Key 和地址';

  // ---- 状态/交互 ----
  static const String transcribing = '正在转写…';
  static const String synthesizing = '正在合成语音…';
  static const String holdToTalk = '按住说话';
  static const String releaseToTranscribePrefix = '松开转文字 · ';
  static const String stopped = '已停止';
  static const String voice = '语音';
}

/// 语音链路统一错误类型。
///
/// [message] 是可以直接展示给用户的中文文案；[cause] 保留底层异常便于排查；
/// [statusCode] 在 HTTP 失败时给出状态码。
class VoiceError implements Exception {
  const VoiceError(
    this.kind,
    this.message, {
    this.cause,
    this.statusCode,
  });

  final VoiceErrorKind kind;
  final String message;
  final Object? cause;
  final int? statusCode;

  // ---- 录音 ----

  const VoiceError.unsupportedRecording({Object? cause})
      : this(
          VoiceErrorKind.unsupportedEnvironment,
          VoiceText.unsupportedRecording,
          cause: cause,
        );

  const VoiceError.noMicrophonePermission({Object? cause})
      : this(
          VoiceErrorKind.permissionDenied,
          VoiceText.noMicrophonePermission,
          cause: cause,
        );

  const VoiceError.recordingTooShort()
      : this(VoiceErrorKind.recordingTooShort, VoiceText.recordingTooShort);

  const VoiceError.recordingEmpty()
      : this(VoiceErrorKind.recordingEmpty, VoiceText.recordingEmpty);

  const VoiceError.recordingSilent()
      : this(VoiceErrorKind.recordingSilent, VoiceText.recordingSilent);

  const VoiceError.recordingTooLarge()
      : this(VoiceErrorKind.recordingTooLarge, VoiceText.recordingTooLarge);

  // ---- 配置 ----

  const VoiceError.notConfigured()
      : this(VoiceErrorKind.notConfigured, VoiceText.notConfigured);

  // ---- ASR ----

  const VoiceError.asrUnsupported()
      : this(VoiceErrorKind.asrUnsupported, VoiceText.asrUnsupported);

  const VoiceError.asrEmptyResponse()
      : this(VoiceErrorKind.asrEmptyResponse, VoiceText.asrEmptyResponse);

  const VoiceError.asrBadResponse()
      : this(VoiceErrorKind.asrBadResponse, VoiceText.asrBadResponse);

  const VoiceError.asrNoText()
      : this(VoiceErrorKind.asrNoText, VoiceText.asrNoTextField);

  const VoiceError.asrNoSpeech()
      : this(VoiceErrorKind.asrNoSpeech, VoiceText.asrNoSpeech);

  // ---- TTS ----

  const VoiceError.ttsEmptyText()
      : this(VoiceErrorKind.ttsEmptyText, VoiceText.ttsEmptyText);

  const VoiceError.ttsEmptyAudio()
      : this(VoiceErrorKind.ttsEmptyAudio, VoiceText.ttsEmptyAudio);

  const VoiceError.ttsEmptyFile()
      : this(VoiceErrorKind.ttsEmptyFile, VoiceText.ttsEmptyFile);

  const VoiceError.ttsBadResponse()
      : this(VoiceErrorKind.ttsBadResponse, VoiceText.ttsBadResponse);

  const VoiceError.nothingToSpeak()
      : this(VoiceErrorKind.ttsEmptyText, VoiceText.nothingToSpeak);

  // ---- 播放 ----

  const VoiceError.playbackUnsupported()
      : this(
          VoiceErrorKind.unsupportedEnvironment,
          VoiceText.playbackUnsupported,
        );

  const VoiceError.playbackFailed({Object? cause})
      : this(
          VoiceErrorKind.playbackFailed,
          VoiceText.playbackFailedShort,
          cause: cause,
        );

  // ---- 通用 ----

  const VoiceError.network({Object? cause})
      : this(
          VoiceErrorKind.network,
          VoiceText.networkError,
          cause: cause,
        );

  /// 把任意异常收敛为 [VoiceError]；已经是 [VoiceError] 时原样返回。
  factory VoiceError.wrap(
    Object error, {
    VoiceErrorKind kind = VoiceErrorKind.unknown,
    String? message,
  }) {
    if (error is VoiceError) return error;
    final detail = '$error';
    return VoiceError(
      kind,
      message ?? '${VoiceText.serviceErrorPrefix}$detail',
      cause: error,
    );
  }

  /// HTTP 状态码 → 可展示的中文原因（没有对应文案时返回空串）。
  static String hintOf(int statusCode) {
    if (statusCode == 401 || statusCode == 403) return VoiceText.invalidApiKey;
    if (statusCode == 402) return VoiceText.insufficientBalance;
    if (statusCode == 429) return VoiceText.tooManyRequests;
    if (statusCode >= 500) return VoiceText.serviceBusy;
    return '';
  }

  /// 「HTTP 429 请求太频繁，稍后再试」这样的详情串。
  static String httpDetail(int statusCode) {
    final hint = hintOf(statusCode);
    return hint.isEmpty ? 'HTTP $statusCode' : 'HTTP $statusCode $hint';
  }

  bool get isNetwork => kind == VoiceErrorKind.network;

  bool get isPermission => kind == VoiceErrorKind.permissionDenied;

  bool get isUnsupported => kind == VoiceErrorKind.unsupportedEnvironment ||
      kind == VoiceErrorKind.asrUnsupported ||
      kind == VoiceErrorKind.ttsUnsupported;

  @override
  String toString() => message;
}

/// 从任意错误取一条可展示的中文文案。
///
/// 用于 UI 的 `catch (e) { toast(voiceErrorMessage(e)); }`：
/// * [VoiceError] → 原样文案；
/// * 非空 [String] → 视为已经是文案；
/// * 其它 → 套上「语音服务出错：」前缀。
String voiceErrorMessage(Object? error) {
  if (error == null) return '';
  if (error is VoiceError) return error.message;
  if (error is String) {
    final text = error.trim();
    if (text.isNotEmpty) return text;
    return VoiceText.serviceErrorPrefix;
  }
  final detail = error.toString().trim();
  if (detail.isEmpty) return VoiceText.serviceErrorPrefix;
  return '${VoiceText.serviceErrorPrefix}$detail';
}
