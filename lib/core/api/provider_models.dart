/// Keepsake（留声）— AI 提供方模型与内置预设表。
///
/// **契约 A（冻结）**：本文件是被其它所有批次依赖的公共类型。
/// 依据：`reports/apk/http-api.md` §2（13 个预设 / base_url / 模型候选 / 能力位）、
/// `reports/apk/dart-symbols.md`（`ProviderKind{openai,anthropic}`、`anthropicBaseOf`、
/// `normalizeProviderBase`、`providerFromPreset`、`newProvider`）。
///
/// 命名约定：
/// - Dart 侧用 camelCase；持久化（SharedPreferences JSON）用 **snake_case**，与旧数据兼容
///   （字符串表实证 key：`provider_id`、`base_url`、`api_key`、`models`、`kind`、`model`、
///   `name`、`ai_providers`）。`fromJson` 对 snake/camel 两种写法都容错。
/// - 本文件**不**依赖 Flutter / Riverpod，纯 Dart，任何层都可安全 import。
library;

import 'package:uuid/uuid.dart';

/// 协议类型（字符串表实证值：`openai` / `anthropic`）。
enum ProviderKind {
  openai('openai', 'OpenAI 兼容'),
  anthropic('anthropic', 'Anthropic 兼容');

  const ProviderKind(this.wireName, this.protocolLabel);

  /// JSON / 存储里的字符串值。
  final String wireName;

  /// 设置页展示文案（http-api.md §2 [确定]：`OpenAI 兼容` / `Anthropic 兼容`）。
  final String protocolLabel;

  static ProviderKind parse(Object? raw, {ProviderKind fallback = ProviderKind.openai}) {
    if (raw is ProviderKind) return raw;
    final value = raw?.toString().toLowerCase().trim() ?? '';
    if (value == 'anthropic') return ProviderKind.anthropic;
    if (value == 'openai') return ProviderKind.openai;
    return fallback;
  }
}

/// 内置预设（11 官方 + 2 自定义）。
///
/// 全部为 `const`：`providerPresets` 是不可变常量表，UI 直接遍历。
class ProviderPreset {
  const ProviderPreset({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.kind = ProviderKind.openai,
    this.models = const <String>[],
    this.defaultModel = '',
    this.supportsThinking = false,
    this.supportsSearch = false,
    this.supportsFiles = false,
    this.supportsAsr = false,
    this.supportsTts = false,
    this.isCustom = false,
  });

  /// 稳定 id（用于 `AiProvider.presetId` 与 SharedPreferences 反查，勿改）。
  final String id;

  /// 显示名（http-api.md §2 原文）。
  final String name;

  /// 默认接口地址；自定义预设为空串（由用户填写）。
  final String baseUrl;

  final ProviderKind kind;

  /// 模型候选（字符串实证；火山方舟等未知的留空，靠 `GET /models` 拉真实列表）。
  final List<String> models;

  /// 默认模型；空串表示需要用户填写（对应 UI「先填一个模型名」）。
  final String defaultModel;

  final bool supportsThinking;
  final bool supportsSearch;
  final bool supportsFiles;
  final bool supportsAsr;
  final bool supportsTts;

  /// 是否为「自定义（OpenAI/Anthropic 兼容）」预设。
  final bool isCustom;

  /// 协议标签，等价 `kind.protocolLabel`（设置页/编辑弹窗用）。
  String get protocolLabel => kind.protocolLabel;

  /// 该预设是否可用 Anthropic 兼容协议（DeepSeek 官方双协议）。
  bool get hasAnthropicProtocol =>
      id == presetDeepSeekId || kind == ProviderKind.anthropic;

  /// Anthropic 兼容时的基址。
  String get anthropicBaseUrl => anthropicBaseOf(baseUrl);

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'base_url': baseUrl,
        'kind': kind.wireName,
        'models': models,
        'default_model': defaultModel,
        'supports_thinking': supportsThinking,
        'supports_search': supportsSearch,
        'supports_files': supportsFiles,
        'supports_asr': supportsAsr,
        'supports_tts': supportsTts,
        'is_custom': isCustom,
      };

  @override
  String toString() => 'ProviderPreset($id, $name)';
}

// ---------------------------------------------------------------------------
// 预设 id 常量（供其它批次按名字引用，避免魔法字符串）
// ---------------------------------------------------------------------------

const String presetDeepSeekId = 'deepseek';
const String presetMoonshotId = 'moonshot';
const String presetZhipuId = 'zhipu';
const String presetSiliconFlowId = 'siliconflow';
const String presetBaichuanId = 'baichuan';
const String presetQianfanId = 'qianfan';
const String presetVolcengineId = 'volcengine';
const String presetMiniMaxId = 'minimax';
const String presetDashScopeId = 'dashscope';
const String presetStepFunId = 'stepfun';
const String presetHunyuanId = 'hunyuan';
const String presetCustomOpenAiId = 'custom-openai';
const String presetCustomAnthropicId = 'custom-anthropic';

/// 默认模型（http-api.md §2 [高置信]）：DeepSeek 官方低档 / 高档。
const String kDefaultModelName = 'deepseek-flash';
const String kProModelName = 'deepseek-v4-pro';

/// 思考强度档位标签（ui-strings §2 [确定]：高 / 中 / 低）。
const List<String> kThinkingLevelLabels = <String>['低', '中', '高'];

/// 13 个内置预设：11 个官方 + 2 个自定义。
///
/// 模型候选归属为 **[推断]**（AOT 字符串表不保证模型↔平台相邻）；
/// 实现以「预设给候选列表 + `/models` 拉真实列表」为准。
const List<ProviderPreset> providerPresets = <ProviderPreset>[
  ProviderPreset(
    id: presetDeepSeekId,
    name: 'DeepSeek（官方）',
    baseUrl: 'https://api.deepseek.com',
    kind: ProviderKind.openai,
    models: <String>[kDefaultModelName, kProModelName],
    defaultModel: kDefaultModelName,
    supportsThinking: true,
    // 唯一声明 Files API / 联网搜索 / ASR 的平台（http-api.md §2 [确定]）。
    supportsSearch: true,
    supportsFiles: true,
    supportsAsr: true,
    supportsTts: true, // [推断] ASR 同源派生 TTS；仅 DeepSeek 声明
  ),
  ProviderPreset(
    id: presetMoonshotId,
    name: '月之暗面 Kimi',
    baseUrl: 'https://api.moonshot.cn/v1',
    // 官方现已到 kimi-k2.x：旧的 kimi-k2-turbo-preview 属早期预览名，随时下线。
    // 思考能力由 `-thinking` 模型提供（不是参数开关）。
    models: <String>['kimi-k2.6', 'kimi-k2.5', 'kimi-k2-thinking'],
    defaultModel: 'kimi-k2.6',
    // Kimi 把 reasoning 放单独字段 → 支持思考。
    supportsThinking: true,
  ),
  ProviderPreset(
    id: presetZhipuId,
    name: '智谱 GLM',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    models: <String>['glm-4.6', 'glm-4-flash'],
    defaultModel: 'glm-4.6',
    supportsThinking: true,
  ),
  ProviderPreset(
    id: presetSiliconFlowId,
    name: '硅基流动 SiliconFlow',
    baseUrl: 'https://api.siliconflow.cn/v1',
    // 官方 /v1/models 当前可见 V4 系列；V3/V3.2/R1 已被取代。
    models: <String>[
      'deepseek-ai/DeepSeek-V4-Flash',
      'deepseek-ai/DeepSeek-V4.1-Flash',
      'deepseek-ai/DeepSeek-V4-Pro',
    ],
    defaultModel: 'deepseek-ai/DeepSeek-V4-Flash',
    supportsThinking: true,
  ),
  ProviderPreset(
    id: presetBaichuanId,
    name: '百川智能',
    baseUrl: 'https://api.baichuan-ai.com/v1',
    models: <String>['Baichuan4-Turbo', 'Baichuan3-Turbo'],
    defaultModel: 'Baichuan4-Turbo',
  ),
  ProviderPreset(
    id: presetQianfanId,
    name: '百度千帆（文心）',
    baseUrl: 'https://qianfan.baidubce.com/v2',
    models: <String>['ernie-4.5-turbo-128k', 'ernie-speed-128k'],
    defaultModel: 'ernie-4.5-turbo-128k',
  ),
  ProviderPreset(
    id: presetVolcengineId,
    name: '火山方舟（豆包）',
    baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    // 字符串表未捕获该平台 model id → 留空，靠 /models 拉真实列表。
    models: <String>[],
    defaultModel: '',
  ),
  ProviderPreset(
    id: presetMiniMaxId,
    name: 'MiniMax',
    // 官网现行 OpenAI 兼容 base_url 是 api.minimax.cn（旧 api.minimaxi.com）。
    baseUrl: 'https://api.minimax.cn/v1',
    models: <String>['MiniMax-M3', 'MiniMax-M3.1-Flash'],
    defaultModel: 'MiniMax-M3',
  ),
  ProviderPreset(
    id: presetDashScopeId,
    name: '阿里云百炼（通义千问）',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    models: <String>['qwen3-max', 'qwen-plus', 'qwen-turbo'],
    defaultModel: 'qwen3-max',
  ),
  ProviderPreset(
    id: presetStepFunId,
    name: '阶跃星辰 StepFun',
    baseUrl: 'https://api.stepfun.com/v1',
    // 官网现行模型已到 step-3.x 系列（旧的 step-1/step-2 已过时）。
    models: <String>['step-3.7-flash'],
    defaultModel: 'step-3.7-flash',
  ),
  ProviderPreset(
    id: presetHunyuanId,
    name: '腾讯混元',
    baseUrl: 'https://api.hunyuan.cloud.tencent.com/v1',
    models: <String>['hunyuan-turbos-latest', 'hunyuan-lite'],
    defaultModel: 'hunyuan-turbos-latest',
  ),
  ProviderPreset(
    id: presetCustomOpenAiId,
    name: '自定义（OpenAI 兼容）',
    baseUrl: '',
    kind: ProviderKind.openai,
    isCustom: true,
  ),
  ProviderPreset(
    id: presetCustomAnthropicId,
    name: '自定义（Anthropic 兼容）',
    baseUrl: '',
    kind: ProviderKind.anthropic,
    isCustom: true,
  ),
];

/// 按 id 查预设；找不到返回 `null`。
ProviderPreset? presetById(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final preset in providerPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}

/// DeepSeek 官方预设（默认平台）。
final ProviderPreset deepSeekPreset = providerPresets.first;

// ---------------------------------------------------------------------------
// URL 规范化 / 派生
// ---------------------------------------------------------------------------

/// 规范化用户填写的接口地址：
/// - 去首尾空白与尾部 `/`；
/// - 无 scheme 时自动补 `https://`（`usesCleartextTraffic=false`，只允许 https）；
/// - 空串原样返回空串（由调用方给「先填接口地址」）。
///
/// 符号证据：`normalizeBaseUrl` / `normalizeProviderBase` [确定]。
String normalizeProviderBase(String raw) {
  var base = raw.trim();
  if (base.isEmpty) return '';
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  if (base.isEmpty) return '';
  final lower = base.toLowerCase();
  if (lower.startsWith('http://')) {
    // 明文 http 在 Android 上会被 usesCleartextTraffic=false 拦掉，
    // 但用户可能填的是内网代理；保留原样，由 http 层报错（不静默改协议）。
    return base;
  }
  if (!lower.startsWith('https://')) {
    base = 'https://$base';
  }
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  return base;
}

/// `normalizeProviderBase` 的别名（符号表两个名字都存在）。
String normalizeBaseUrl(String raw) => normalizeProviderBase(raw);

/// DeepSeek 官方 Anthropic 兼容基址（http-api.md §1 [确定]）。
const String kDeepSeekAnthropicBase = 'https://api.deepseek.com/anthropic/v1';

/// 由 OpenAI 兼容 base 派生 Anthropic 兼容 base。
///
/// 官方（https://api-docs.deepseek.com/guides/anthropic_api）：Anthropic SDK 的
/// `base_url` 是 `https://api.deepseek.com/anthropic`，直连 HTTP 用
/// `POST /anthropic/v1/messages`；Files API 在 `/anthropic/v1/` 下。
///
/// - DeepSeek 官方：固定 `https://api.deepseek.com/anthropic/v1`；
/// - 其它平台（含自定义 Anthropic 兼容平台）：用户填的地址**本身就是**
///   Anthropic 基址，绝不插入 `/anthropic`；已以 `/v1` 结尾时原样返回
///   （避免重复拼接），缺 `/v1` 才补一次。
///
/// 旧实现会给自定义平台拼成 `https://api.anthropic.com/anthropic/v1`（404）。
///
/// 符号证据：`anthropicBaseOf`、字面量 `/anthropic`、`/anthropic/v1` [确定]。
String anthropicBaseOf(String baseUrl) {
  final base = normalizeProviderBase(baseUrl);
  if (base.isEmpty) return '';
  final lower = base.toLowerCase();

  if (lower.contains('api.deepseek.com')) {
    // DeepSeek 官方基址固定（含 /anthropic/v1）；兼容用户填了 /v1 或 /anthropic 的情况。
    return kDeepSeekAnthropicBase;
  }
  // 用户可能直接粘了完整端点；去掉后再判断 /v1。
  if (lower.endsWith('/messages')) {
    return base.substring(0, base.length - '/messages'.length);
  }
  if (lower.endsWith('/v1')) return base;
  return '$base/v1';
}

// ---------------------------------------------------------------------------
// 用户配置的 AI 平台实例
// ---------------------------------------------------------------------------

/// 用户配置的一个 AI 平台（列表项 + API Key + 当前模型 + 能力位）。
///
/// 持久化在 SharedPreferences 的 `ai_providers` JSON 里；`toJson` 用 snake_case。
class AiProvider {
  const AiProvider({
    required this.id,
    required this.presetId,
    required this.name,
    required this.baseUrl,
    this.apiKey = '',
    this.model = '',
    this.kind = ProviderKind.openai,
    this.models = const <String>[],
    this.supportsThinking = false,
    this.supportsSearch = false,
    this.supportsFiles = false,
    this.supportsAsr = false,
    this.supportsTts = false,
  });

  /// 本机唯一 id（uuid v4）。
  final String id;

  /// 来源预设 id；自定义/手改后仍保留原预设便于回显。
  final String presetId;

  /// 用户可见名字（默认取预设 name，可改）。
  final String name;

  /// 接口地址（已规范化）。
  final String baseUrl;

  final String apiKey;

  /// 当前选中模型。
  final String model;

  final ProviderKind kind;

  /// 候选模型（可被 `/models` 拉取结果覆盖）。
  final List<String> models;

  final bool supportsThinking;
  final bool supportsSearch;
  final bool supportsFiles;
  final bool supportsAsr;
  final bool supportsTts;

  /// 预设（可能已被删除/改名，找不到时返回 null）。
  ProviderPreset? get preset => presetById(presetId);

  /// 协议标签。
  String get protocolLabel => kind.protocolLabel;

  /// 接口地址是否可用（非空）。
  bool get hasBaseUrl => baseUrl.trim().isNotEmpty;

  /// API Key 是否已填。
  bool get hasApiKey => apiKey.trim().isNotEmpty;

  /// 模型是否已确定。
  bool get hasModel => model.trim().isNotEmpty;

  /// 四项都齐（可发起请求）。
  bool get isReady => hasBaseUrl && hasApiKey && hasModel;

  /// Anthropic 兼容基址（仅 `kind == anthropic` 时有意义，DeepSeek 双协议也用）。
  String get anthropicBaseUrl => anthropicBaseOf(baseUrl);

  /// 实际请求用的基址（Anthropic 走派生地址）。
  String get effectiveBaseUrl =>
      kind == ProviderKind.anthropic ? anthropicBaseUrl : baseUrl;

  AiProvider copyWith({
    String? id,
    String? presetId,
    String? name,
    String? baseUrl,
    String? apiKey,
    String? model,
    ProviderKind? kind,
    List<String>? models,
    bool? supportsThinking,
    bool? supportsSearch,
    bool? supportsFiles,
    bool? supportsAsr,
    bool? supportsTts,
  }) {
    return AiProvider(
      id: id ?? this.id,
      presetId: presetId ?? this.presetId,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      kind: kind ?? this.kind,
      models: models ?? this.models,
      supportsThinking: supportsThinking ?? this.supportsThinking,
      supportsSearch: supportsSearch ?? this.supportsSearch,
      supportsFiles: supportsFiles ?? this.supportsFiles,
      supportsAsr: supportsAsr ?? this.supportsAsr,
      supportsTts: supportsTts ?? this.supportsTts,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'preset_id': presetId,
        'name': name,
        'base_url': baseUrl,
        'api_key': apiKey,
        'model': model,
        'kind': kind.wireName,
        'models': models,
        'supports_thinking': supportsThinking,
        'supports_search': supportsSearch,
        'supports_files': supportsFiles,
        'supports_asr': supportsAsr,
        'supports_tts': supportsTts,
      };

  /// 容错解析：snake_case（新旧本机数据）/ camelCase 都接受；缺字段用预设补齐。
  factory AiProvider.fromJson(Map<String, Object?> json, {ProviderPreset? fallback}) {
    final presetId = _str(json, 'preset_id', 'presetId') ?? fallback?.id ?? '';
    final preset = presetById(presetId) ?? fallback;
    final kindRaw = _str(json, 'kind');
    final kind = kindRaw == null
        ? (preset?.kind ?? ProviderKind.openai)
        : ProviderKind.parse(kindRaw, fallback: preset?.kind ?? ProviderKind.openai);
    final rawModels = json['models'];
    final models = rawModels is List
        ? rawModels.map((e) => e.toString()).where((e) => e.isNotEmpty).toList(growable: false)
        : (preset?.models ?? const <String>[]);
    return AiProvider(
      id: _str(json, 'id') ?? newProviderId(),
      presetId: presetId,
      name: _str(json, 'name') ?? preset?.name ?? '未命名平台',
      baseUrl: _str(json, 'base_url', 'baseUrl') ?? preset?.baseUrl ?? '',
      apiKey: _str(json, 'api_key', 'apiKey', 'key') ?? '',
      model: _str(json, 'model', 'default_model', 'defaultModel') ??
          preset?.defaultModel ??
          '',
      kind: kind,
      models: models,
      supportsThinking:
          _bool(json, 'supports_thinking', 'supportsThinking') ?? preset?.supportsThinking ?? false,
      supportsSearch:
          _bool(json, 'supports_search', 'supportsSearch') ?? preset?.supportsSearch ?? false,
      supportsFiles:
          _bool(json, 'supports_files', 'supportsFiles') ?? preset?.supportsFiles ?? false,
      supportsAsr: _bool(json, 'supports_asr', 'supportsAsr') ?? preset?.supportsAsr ?? false,
      supportsTts: _bool(json, 'supports_tts', 'supportsTts') ?? preset?.supportsTts ?? false,
    );
  }

  @override
  String toString() => 'AiProvider($id, $name, $kind)';
}

/// 从预设生成一个平台实例（保留预设的能力位与默认模型）。
///
/// 符号证据：`providerFromPreset` [确定]。
AiProvider providerFromPreset(
  ProviderPreset preset, {
  String? apiKey,
  String? model,
  String? name,
  ProviderKind? kind,
}) {
  return AiProvider(
    id: newProviderId(),
    presetId: preset.id,
    name: name ?? preset.name,
    baseUrl: preset.baseUrl,
    apiKey: apiKey ?? '',
    model: model ?? preset.defaultModel,
    kind: kind ?? preset.kind,
    models: preset.models,
    supportsThinking: preset.supportsThinking,
    supportsSearch: preset.supportsSearch,
    supportsFiles: preset.supportsFiles,
    supportsAsr: preset.supportsAsr,
    supportsTts: preset.supportsTts,
  );
}

/// 生成一个平台实例的新 id。
///
/// 符号证据：`newProvider` [确定]。
String newProviderId() => const Uuid().v4();

/// 空配置下新建的平台实例（预设 fallback 到 DeepSeek 官方）。
AiProvider newProvider({ProviderPreset? preset, String? apiKey, String? model}) =>
    providerFromPreset(preset ?? deepSeekPreset, apiKey: apiKey, model: model);

// ---------------------------------------------------------------------------
// /models 返回的模型条目
// ---------------------------------------------------------------------------

/// `GET {base}/models` 的 `data[]` 条目。
class ProviderModel {
  const ProviderModel({required this.id, this.ownedBy});

  final String id;
  final String? ownedBy;

  factory ProviderModel.fromJson(Map<String, Object?> json) => ProviderModel(
        id: (json['id'] ?? json['model'] ?? '').toString(),
        ownedBy: (json['owned_by'] ?? json['ownedBy'])?.toString(),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        if (ownedBy != null) 'owned_by': ownedBy,
      };

  @override
  bool operator ==(Object other) =>
      other is ProviderModel && other.id == id && other.ownedBy == ownedBy;

  @override
  int get hashCode => Object.hash(id, ownedBy);

  @override
  String toString() => 'ProviderModel($id)';
}

// ---------------------------------------------------------------------------
// 内部解析小工具（容错 JSON）
// ---------------------------------------------------------------------------

String? _str(Map<String, Object?> json, String key, [String? alt, String? alt2]) {
  for (final k in <String?>[key, alt, alt2]) {
    if (k == null) continue;
    final value = json[k];
    if (value == null) continue;
    final text = value.toString();
    if (text.isNotEmpty) return text;
  }
  return null;
}

bool? _bool(Map<String, Object?> json, String key, [String? alt]) {
  for (final k in <String?>[key, alt]) {
    if (k == null) continue;
    final value = json[k];
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final v = value.toLowerCase().trim();
      if (v == 'true' || v == '1') return true;
      if (v == 'false' || v == '0') return false;
    }
  }
  return null;
}
