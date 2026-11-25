/// Keepsake（留声）— 联网方式配置（设置页「联网服务」）。
///
/// 单独一个文件：`chat_backend.dart` 要引用 [WebSearchConfig]，而
/// `web_search.dart` 又要引用 `chat_backend.dart` 的错误类型，拆开避免循环依赖。
library;

/// 联网方式：
/// - [server]：DeepSeek 服务端免费联网工具（搜索本身不计费），
///   但会进入扩展模式，**当前轮 user 输入限 32768 tokens**；
/// - [external]：客户端 function 工具 + 外部 Search / Fetch API，
///   搜索按次计费（$0.75/1000 次），但不进扩展模式，大文档也能联网。
enum WebSearchMode { server, external }

const String kSearchServiceDeepSeek = 'deepseek';
const String kSearchServiceTavily = 'tavily';
const String kSearchServiceBocha = 'bocha';
const String kSearchServiceBrave = 'brave';
const String kSearchServiceCustom = 'custom';

/// 外部服务的默认基址（用户可在设置里覆盖）。
const Map<String, String> kSearchServiceDefaultBase = <String, String>{
  kSearchServiceDeepSeek: 'https://api.deepseek.com',
  kSearchServiceTavily: 'https://api.tavily.com',
  kSearchServiceBocha: 'https://api.bochaai.com',
  kSearchServiceBrave: 'https://api.search.brave.com',
};

/// 服务显示名（设置页下拉）。
String searchServiceLabel(String serviceId) => switch (serviceId) {
      kSearchServiceTavily => 'Tavily',
      kSearchServiceBocha => '博查 Bocha',
      kSearchServiceBrave => 'Brave Search',
      kSearchServiceCustom => '自定义（DeepSeek 形状）',
      _ => 'DeepSeek',
    };


/// 外部联网服务的地址 / Key / 条数（[WebSearchMode.external] 时生效）。
class WebSearchConfig {
  const WebSearchConfig({
    this.mode = WebSearchMode.server,
    this.serviceId = kSearchServiceDeepSeek,
    this.baseUrl = '',
    this.apiKey = '',
    this.count = 8,
  });

  final WebSearchMode mode;

  /// `deepseek`（官方 Search/Fetch API）或 `custom`（兼容同一请求/响应形状的自建服务）。
  final String serviceId;

  /// 接口基址；空串 = 按 [serviceId] 用默认值（DeepSeek 官方）。
  final String baseUrl;

  /// 外部服务 Key；空串 = 复用当前聊天平台的 Key（DeepSeek 官方时正确）。
  final String apiKey;

  /// 每次搜索返回条数（1–50）。
  final int count;

  bool get isExternal => mode == WebSearchMode.external;

  /// 默认基址（按服务 id）。
  String get effectiveBaseUrl {
    final explicit = baseUrl.trim();
    if (explicit.isNotEmpty) return explicit;
    return kSearchServiceDefaultBase[serviceId] ?? '';
  }

  /// 实际使用的 Key（空串回落到聊天平台的 Key）。
  String effectiveApiKey(String fallback) {
    final explicit = apiKey.trim();
    return explicit.isEmpty ? fallback.trim() : explicit;
  }

  WebSearchConfig copyWith({
    WebSearchMode? mode,
    String? serviceId,
    String? baseUrl,
    String? apiKey,
    int? count,
  }) =>
      WebSearchConfig(
        mode: mode ?? this.mode,
        serviceId: serviceId ?? this.serviceId,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        count: count ?? this.count,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'mode': mode.name,
        'service_id': serviceId,
        'base_url': baseUrl,
        'api_key': apiKey,
        'count': count,
      };

  factory WebSearchConfig.fromJson(Object? raw) {
    if (raw is! Map) return const WebSearchConfig();
    final map = Map<String, Object?>.from(raw);
    final mode = (map['mode'] ?? 'server').toString();
    final count = map['count'];
    return WebSearchConfig(
      mode: mode == 'external' ? WebSearchMode.external : WebSearchMode.server,
      serviceId: (map['service_id'] ?? kSearchServiceDeepSeek).toString(),
      baseUrl: (map['base_url'] ?? '').toString(),
      apiKey: (map['api_key'] ?? '').toString(),
      count: count is num ? count.toInt().clamp(1, 50) : 8,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WebSearchConfig &&
      other.mode == mode &&
      other.serviceId == serviceId &&
      other.baseUrl == baseUrl &&
      other.apiKey == apiKey &&
      other.count == count;

  @override
  int get hashCode => Object.hash(mode, serviceId, baseUrl, apiKey, count);

  @override
  String toString() => 'WebSearchConfig(${mode.name}, $serviceId)';
}
