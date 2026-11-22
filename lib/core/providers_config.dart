/// Keepsake（留声）— 平台配置解析（给 C/D 批次取 API Key / Base URL / 模型的统一入口）。
///
/// 符号证据（dart-symbols.md）：本文件原属 `ProviderPreset` / `ProviderKind` / `AiProvider` /
/// `normalizeProviderBase` / `anthropicBaseOf` 的归属。为了「契约 A 单一来源」，这些类型
/// 现在定义在 `core/api/provider_models.dart`，本文件 **re-export** 它们，并提供
/// `ProviderConfig` / `ProviderConfigResolver` 这层最小抽象（[推断] 的新增 API，供 C/D 用）。
library;

import 'api/provider_models.dart';
import 'provider_store.dart' show ProviderBook;
import 'settings.dart' show Settings;

export 'api/provider_models.dart';

/// 一次请求实际要用的平台配置（已解析、已校验）。
class ProviderConfig {
  const ProviderConfig({
    required this.providerId,
    required this.providerName,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.kind,
    this.supportsThinking = false,
    this.supportsSearch = false,
    this.supportsFiles = false,
    this.supportsAsr = false,
    this.supportsTts = false,
  });

  final String providerId;
  final String providerName;

  /// 已经过 [normalizeProviderBase] 的地址；Anthropic 协议时是派生地址。
  final String baseUrl;

  final String apiKey;
  final String model;
  final ProviderKind kind;

  final bool supportsThinking;
  final bool supportsSearch;
  final bool supportsFiles;
  final bool supportsAsr;
  final bool supportsTts;

  /// OpenAI 兼容端点基址（`{base}/chat/completions`、`{base}/models`、`{base}/files`）。
  String get openAiBaseUrl => baseUrl;

  /// Anthropic 兼容端点基址（`{base}/messages`）。
  String get anthropicBaseUrl => anthropicBaseOf(baseUrl);

  /// 是否走了 Anthropic 协议。
  bool get isAnthropic => kind == ProviderKind.anthropic;

  Map<String, String> get authHeaders => isAnthropic
      ? <String, String>{
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        }
      : <String, String>{
          'Authorization': 'Bearer $apiKey',
          'content-type': 'application/json',
        };

  @override
  String toString() => 'ProviderConfig($providerName, $kind, model=$model)';
}

/// 从「平台列表 + 设置」解析出可用的 [ProviderConfig]。
///
/// 侧别：纯 Dart，不依赖 Riverpod；上层（C/D/F）用
/// `ProviderConfigResolver(book: ref.watch(providerBookProvider), settings: ref.watch(settingsProvider))`
/// 构造即可。
class ProviderConfigResolver {
  const ProviderConfigResolver({required this.book, required this.settings});

  final ProviderBook book;
  final Settings settings;

  /// 生效平台 id：显式传入 > 设置里的 providerId > 列表第一个。
  String? effectiveProviderId(String? providerId) {
    final explicit = providerId?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final fromSettings = settings.providerId.trim();
    if (fromSettings.isNotEmpty) return fromSettings;
    final first = book.providers.isEmpty ? null : book.providers.first.id;
    return first;
  }

  /// 生效模型：显式传入 > 平台当前 model > 设置默认模型。
  String effectiveModel(AiProvider provider, String? model) {
    final explicit = model?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    if (provider.model.trim().isNotEmpty) return provider.model;
    return settings.defaultModel;
  }

  /// 解析配置；缺项时返回 null（具体原因用 [problemOf]）。
  ProviderConfig? resolve({String? providerId, String? model}) {
    final provider = book.byId(effectiveProviderId(providerId));
    if (provider == null) return null;
    final base = normalizeProviderBase(provider.baseUrl);
    if (base.isEmpty) return null;
    if (provider.apiKey.trim().isEmpty) return null;
    final resolvedModel = effectiveModel(provider, model);
    if (resolvedModel.trim().isEmpty) return null;
    return ProviderConfig(
      providerId: provider.id,
      providerName: provider.name,
      baseUrl: provider.kind == ProviderKind.anthropic ? anthropicBaseOf(base) : base,
      apiKey: provider.apiKey.trim(),
      model: resolvedModel.trim(),
      kind: provider.kind,
      supportsThinking: provider.supportsThinking,
      supportsSearch: provider.supportsSearch,
      supportsFiles: provider.supportsFiles,
      supportsAsr: provider.supportsAsr,
      supportsTts: provider.supportsTts,
    );
  }

  /// 不可用的原因（产品文案，ui-strings §5 [确定]）。
  String problemOf({String? providerId, String? model}) {
    if (book.providers.isEmpty) {
      return '还没有配置 AI 平台，去设置里添加一个';
    }
    final id = effectiveProviderId(providerId);
    final provider = book.byId(id);
    if (provider == null) {
      return '选中的平台不存在了，去设置里重新选一个';
    }
    if (normalizeProviderBase(provider.baseUrl).isEmpty) {
      return '先填接口地址';
    }
    if (provider.apiKey.trim().isEmpty) {
      return ' 还没填 API Key';
    }
    if (effectiveModel(provider, model).trim().isEmpty) {
      return '先填一个模型名';
    }
    return '';
  }

  /// 当前是否可用。
  bool get isReady => resolve() != null;
}
