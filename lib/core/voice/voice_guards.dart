// 语音链路的平台/环境能力守卫，以及从 AI 平台配置里读取语音能力的适配层。
//
// 两个目的：
//   1. 让 UI 在「没有插件 / 平台不支持」时直接给文案，而不是等插件抛异常；
//   2. 把 ASR/TTS 端点所需的 baseUrl / apiKey / 平台判断从 UI 解耦出来。
//
// 注意：批次 A 的 `core/api/provider_models.dart`（AiProvider / ProviderPreset）
// 由另一个智能体并行编写，字段名可能有差异。为避免跨批次编译依赖，本文件不 import
// 它，而是通过 `VoiceCapabilities.forProvider(...)` 用「鸭子类型 + 候选字段名」读取，
// 找不到字段时按「仅 DeepSeek 支持语音」的既定规则推断。

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

// 批次 A 的冻结契约：`AiProvider` / `ProviderConfig`（providers_config re-export
// provider_models）。语音只需 baseUrl + apiKey + 能力位，故用下面的两个具名工厂
// 做「强类型」适配；`forProvider` 仍保留鸭子类型兜底，方便测试与未来改名。
import 'package:keepsake/core/providers_config.dart'
    show AiProvider, ProviderConfig;

/// 语音插件（record + just_audio）在当前平台是否可用。
///
/// 判定依据是 pubspec 依赖里实际带的原生实现（.flutter-plugins-dependencies）：
/// just_audio 只在 Android / iOS / macOS 提供原生实现，本项目的语音门面以它为准。
bool get voicePluginsAvailable => !kIsWeb && voicePlaybackAvailable;

/// 当前平台是否支持录音（record 插件原生实现：Android/iOS/macOS/Windows/Linux）。
bool get voiceRecordingAvailable {
  if (kIsWeb) return false;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.fuchsia:
      return true;
  }
}

/// 当前平台是否支持播放音频（just_audio 原生实现：Android/iOS/macOS）。
bool get voicePlaybackAvailable {
  if (kIsWeb) return false;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return true;
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.fuchsia:
      return false;
  }
}

/// 当前平台 + 平台配置是否支持 ASR。
///
/// 情报（http-api.md §6、next-steps §2）：只有 DeepSeek 声明 `supportsAsr`，
/// 其它平台要提示「语音识别接口不存在：当前平台可能不支持 ASR（目前只有 DeepSeek 提供）」。
bool voiceSupportsAsr(VoiceCapabilities caps) {
  if (!caps.hasCredentials) return false;
  return caps.isDeepSeek && caps.supportsAsr;
}

/// 当前平台 + 平台配置是否支持 TTS。
bool voiceSupportsTts(VoiceCapabilities caps) {
  if (!caps.hasCredentials) return false;
  return caps.isDeepSeek && caps.supportsTts;
}

/// 规范化语音端点基址：去首尾空白、缺 scheme 补 `https://`、去尾部 `/`。
///
/// 与 `normalizeProviderBase` 语义一致，但本文件不依赖批次 A，避免编译耦合。
String normalizeVoiceBaseUrl(String baseUrl) {
  var value = baseUrl.trim();
  if (value.isEmpty) return value;
  final lower = value.toLowerCase();
  if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
    value = 'https://$value';
  }
  while (value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}

/// 语音链路需要的平台配置快照（AI 平台 / 预设的能力位与凭据）。
///
/// UI 侧推荐：
/// ```dart
/// final caps = VoiceCapabilities.forProvider(provider);
/// if (!voiceSupportsAsr(caps)) { show('语音识别接口不存在…'); }
/// ```
class VoiceCapabilities {
  const VoiceCapabilities({
    this.presetId,
    this.name,
    this.baseUrl,
    this.apiKey,
    this.model,
    this.supportsAsr = false,
    this.supportsTts = false,
  });

  final String? presetId;
  final String? name;
  final String? baseUrl;
  final String? apiKey;
  final String? model;
  final bool supportsAsr;
  final bool supportsTts;

  /// 从 map（ProviderBook 的 JSON / preset 表）构造。
  factory VoiceCapabilities.fromMap(Map<String, Object?> map) {
    final presetId = _mapText(map, const ['presetId', 'preset_id', 'preset']);
    final name = _mapText(
      map,
      const ['name', 'providerName', 'provider_name', 'displayName'],
    );
    final baseUrl = _mapText(
      map,
      const ['baseUrl', 'base_url', 'base', 'endpoint'],
    );
    final apiKey = _mapText(map, const ['apiKey', 'api_key', 'key']);
    final model = _mapText(map, const ['model', 'defaultModel', 'default_model']);
    final asr = _mapFlag(
      map,
      const ['supportsAsr', 'supports_asr', 'supportsSpeech', 'supports_speech'],
    );
    final tts = _mapFlag(
      map,
      const ['supportsTts', 'supports_tts', 'supportsSpeech', 'supports_speech'],
    );
    final deepSeek = looksLikeDeepSeek(
      presetId: presetId,
      name: name,
      baseUrl: baseUrl,
    );
    return VoiceCapabilities(
      presetId: presetId,
      name: name,
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      supportsAsr: asr ?? deepSeek,
      supportsTts: tts ?? deepSeek,
    );
  }

  /// 从批次 A 冻结契约的 [ProviderConfig] 构造（UI 首选）。
  ///
  /// 典型拿法：
  /// ```dart
  /// final config = ProviderConfigResolver(
  ///   book: ref.watch(providerBookProvider),
  ///   settings: ref.watch(settingsProvider),
  /// ).resolve();
  /// final caps = config == null ? null : VoiceCapabilities.fromProviderConfig(config);
  /// ```
  factory VoiceCapabilities.fromProviderConfig(ProviderConfig config) {
    return VoiceCapabilities(
      name: config.providerName,
      baseUrl: config.baseUrl,
      apiKey: config.apiKey,
      model: config.model,
      supportsAsr: config.supportsAsr,
      supportsTts: config.supportsTts,
    );
  }

  /// 从批次 A 冻结契约的 [AiProvider] 构造（设置页/未解析时用）。
  factory VoiceCapabilities.fromAiProvider(AiProvider provider) {
    return VoiceCapabilities(
      presetId: provider.presetId,
      name: provider.name,
      baseUrl: provider.baseUrl,
      apiKey: provider.apiKey,
      model: provider.model,
      supportsAsr: provider.supportsAsr,
      supportsTts: provider.supportsTts,
    );
  }

  /// 从任意 AI 平台对象（AiProvider / ProviderPreset / ProviderConfig）读取。
  ///
  /// 优先走上面的强类型工厂；其它对象（含未来字段改名）用 dynamic 逐字段试探 +
  /// try/catch 兜底，缺字段时退回「仅 DeepSeek 支持语音」的推断。
  factory VoiceCapabilities.forProvider(Object? provider) {
    if (provider == null) return const VoiceCapabilities();
    if (provider is VoiceCapabilities) return provider;
    if (provider is ProviderConfig) {
      return VoiceCapabilities.fromProviderConfig(provider);
    }
    if (provider is AiProvider) {
      return VoiceCapabilities.fromAiProvider(provider);
    }
    if (provider is Map) {
      return VoiceCapabilities.fromMap(
        provider.map((key, value) => MapEntry('$key', value)),
      );
    }

    final presetId =
        _objectText(provider, const ['presetId', 'preset_id', 'preset']);
    final name = _objectText(
      provider,
      const ['name', 'providerName', 'provider_name', 'displayName'],
    );
    final baseUrl = _objectText(
      provider,
      const ['baseUrl', 'base_url', 'base', 'endpoint'],
    );
    final apiKey = _objectText(provider, const ['apiKey', 'api_key', 'key']);
    final model =
        _objectText(provider, const ['model', 'defaultModel', 'default_model']);
    final asr = _objectFlag(
      provider,
      const ['supportsAsr', 'supports_asr', 'supportsSpeech', 'supports_speech'],
    );
    final tts = _objectFlag(
      provider,
      const ['supportsTts', 'supports_tts', 'supportsSpeech', 'supports_speech'],
    );
    final deepSeek = looksLikeDeepSeek(
      presetId: presetId,
      name: name,
      baseUrl: baseUrl,
    );
    return VoiceCapabilities(
      presetId: presetId,
      name: name,
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      supportsAsr: asr ?? deepSeek,
      supportsTts: tts ?? deepSeek,
    );
  }

  /// 是否是 DeepSeek 平台（预设 id / 名称 / 域名任一命中）。
  bool get isDeepSeek => looksLikeDeepSeek(
        presetId: presetId,
        name: name,
        baseUrl: baseUrl,
      );

  /// baseUrl 与 apiKey 是否都已填写。
  bool get hasCredentials {
    final base = baseUrl?.trim() ?? '';
    final key = apiKey?.trim() ?? '';
    return base.isNotEmpty && key.isNotEmpty;
  }

  /// 规范化后的 baseUrl（可能为空串）。
  String get normalizedBaseUrl => normalizeVoiceBaseUrl(baseUrl ?? '');

  VoiceCapabilities copyWith({
    String? presetId,
    String? name,
    String? baseUrl,
    String? apiKey,
    String? model,
    bool? supportsAsr,
    bool? supportsTts,
  }) {
    return VoiceCapabilities(
      presetId: presetId ?? this.presetId,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      supportsAsr: supportsAsr ?? this.supportsAsr,
      supportsTts: supportsTts ?? this.supportsTts,
    );
  }

  @override
  String toString() => 'VoiceCapabilities(presetId=$presetId, name=$name, '
      'baseUrl=$baseUrl, supportsAsr=$supportsAsr, supportsTts=$supportsTts)';
}

/// 按 id / 名称 / baseUrl 判断是否 DeepSeek 平台。
bool looksLikeDeepSeek({
  String? presetId,
  String? name,
  String? baseUrl,
}) {
  final id = (presetId ?? '').toLowerCase();
  if (id.contains('deepseek')) return true;
  final display = (name ?? '').toLowerCase();
  if (display.contains('deepseek')) return true;
  final base = normalizeVoiceBaseUrl(baseUrl ?? '').toLowerCase();
  if (base.isEmpty) return false;
  return base.contains('deepseek.com') || base.contains('deepseek');
}

String? _mapText(Map<String, Object?> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

bool? _mapFlag(Map<String, Object?> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is bool) return value;
  }
  return null;
}

String? _objectText(Object target, List<String> names) {
  for (final name in names) {
    try {
      final value = _readObjectField(target, name);
      if (value is String && value.trim().isNotEmpty) return value.trim();
    } on NoSuchMethodError {
      continue;
    } on TypeError {
      continue;
    } on ArgumentError {
      continue;
    }
  }
  return null;
}

bool? _objectFlag(Object target, List<String> names) {
  for (final name in names) {
    try {
      final value = _readObjectField(target, name);
      if (value is bool) return value;
    } on NoSuchMethodError {
      continue;
    } on TypeError {
      continue;
    } on ArgumentError {
      continue;
    }
  }
  return null;
}

/// 逐字段读取（Dart 无反射，用 switch 列出候选字段名）。
Object? _readObjectField(Object target, String name) {
  final dynamic value = target;
  switch (name) {
    case 'presetId':
      return value.presetId;
    case 'preset_id':
      return value.preset_id;
    case 'preset':
      return value.preset;
    case 'name':
      return value.name;
    case 'providerName':
      return value.providerName;
    case 'provider_name':
      return value.provider_name;
    case 'displayName':
      return value.displayName;
    case 'baseUrl':
      return value.baseUrl;
    case 'base_url':
      return value.base_url;
    case 'base':
      return value.base;
    case 'endpoint':
      return value.endpoint;
    case 'apiKey':
      return value.apiKey;
    case 'api_key':
      return value.api_key;
    case 'key':
      return value.key;
    case 'model':
      return value.model;
    case 'defaultModel':
      return value.defaultModel;
    case 'default_model':
      return value.default_model;
    case 'supportsAsr':
      return value.supportsAsr;
    case 'supports_asr':
      return value.supports_asr;
    case 'supportsTts':
      return value.supportsTts;
    case 'supports_tts':
      return value.supports_tts;
    case 'supportsSpeech':
      return value.supportsSpeech;
    case 'supports_speech':
      return value.supports_speech;
  }
  throw ArgumentError('unknown field $name');
}
