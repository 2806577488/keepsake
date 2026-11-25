/// Keepsake（留声）— 外部联网服务（Search / Fetch API）。
///
/// 背景：DeepSeek 的「服务端联网工具」（`deepseek_web_search` / `deepseek_read_url`）
/// 一旦声明，整个请求就进入 DeepSeek 的扩展模式：**当前这一轮的最后一条 user
/// 消息会被限制在 32768 tokens**，带 4MB 文档必挂。因此联网支持「外部 API」：
///
/// ```
/// 模型（1M 上下文，读完整份文档）
///   → 输出 function_call: web_search("…")
///   → App 调外部搜索 API
///   → 结果回填
///   → 模型继续回答（可多轮）
/// ```
///
/// 目前支持 4 家：DeepSeek（官方 Search/Fetch）、Tavily（Search/Extract）、
/// 博查 Bocha（仅搜索）、Brave Search（仅搜索）。设置页按 `serviceId` 选。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api/chat_backend.dart'
    show ApiError, ApiErrorKind, apiErrorFromStatus, extractApiErrorDetail;
import '../api/provider_models.dart' show normalizeProviderBase;

import 'search_config.dart';

export 'search_config.dart';

/// 一条搜索结果。
class WebSearchItem {
  const WebSearchItem({
    required this.url,
    this.title,
    this.snippet,
    this.summary,
    this.content,
    this.siteName,
    this.publishedAt,
  });

  final String url;
  final String? title;

  /// 100–200 字短摘要（UI 展示用）。
  final String? snippet;

  /// 600–800 字长摘要（给模型读）。
  final String? summary;

  /// 页面正文（部分服务会直接给）。
  final String? content;

  final String? siteName;
  final String? publishedAt;

  factory WebSearchItem.fromJson(Map<String, Object?> json) => WebSearchItem(
        url: (json['url'] ?? '').toString(),
        title: _str(json['title'] ?? json['name']),
        snippet:
            _str(json['snippet'] ?? json['description'] ?? json['content']),
        summary: _str(json['summary']),
        content: _str(json['raw_content']),
        siteName: _str(
          json['site_name'] ??
              json['siteName'] ??
              (json['profile'] is Map
                  ? (json['profile'] as Map)['name']
                  : null),
        ),
        publishedAt: _str(
          json['date'] ?? json['published_date'] ?? json['page_age'],
        ),
      );

  /// 给模型读的紧凑文本（一条一行，正文按需截断）。
  String toModelText({int index = 1, int maxContentChars = 4000}) {
    final buffer = StringBuffer('[$index] ${title ?? url}\n$url');
    final body = (summary ?? '').trim().isNotEmpty
        ? summary!.trim()
        : (snippet ?? '').trim();
    if (body.isNotEmpty) buffer.write('\n$body');
    final page = (content ?? '').trim();
    if (page.isNotEmpty) {
      final clipped =
          page.length > maxContentChars ? page.substring(0, maxContentChars) : page;
      buffer.write('\n$clipped');
    }
    return buffer.toString();
  }

  static String? _str(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}

/// 抓取结果（URL → Markdown）。
class WebFetchPage {
  const WebFetchPage({required this.url, this.title, required this.content});

  final String url;
  final String? title;
  final String content;
}

/// 外部联网服务抽象。
abstract interface class WebSearchService {
  /// 是否已配置（缺 key / 缺地址时 UI 可提示）。
  bool get isConfigured;

  /// 是否支持 `read_url`（抓正文）。博查 / Brave 只有搜索。
  bool get supportsFetch;

  /// 搜索；[count] 1–50。
  Future<List<WebSearchItem>> search(String query, {int count = 8});

  /// 抓取单页正文（Markdown）；[supportsFetch] 为 false 时抛错。
  Future<WebFetchPage> fetchPage(String url);

  /// 释放 HTTP client。
  void dispose();
}

/// 各家共用的 HTTP 骨架：鉴权头、超时、错误映射、client 生命周期。
abstract class HttpWebSearchService implements WebSearchService {
  HttpWebSearchService({
    required this.baseUrl,
    required this.apiKey,
    http.Client Function()? clientFactory,
    this.timeout = const Duration(seconds: 40),
  }) : _clientFactory = clientFactory ?? http.Client.new;

  final String baseUrl;
  final String apiKey;
  final Duration timeout;
  final http.Client Function() _clientFactory;

  http.Client? _client;

  @override
  bool get isConfigured =>
      apiKey.trim().isNotEmpty && normalizeProviderBase(baseUrl).isNotEmpty;

  /// 去掉尾部 `/`；DeepSeek 额外兼容用户把 base 填成 `.../v1` 的情况。
  String get root {
    final base = normalizeProviderBase(baseUrl);
    if (base.toLowerCase().endsWith('/v1')) {
      return base.substring(0, base.length - 3);
    }
    return base;
  }

  /// 鉴权头（各家不同）。
  Map<String, String> get authHeaders;

  Future<Map<String, Object?>> postJson(
    String path,
    Map<String, Object?> payload,
  ) async {
    final uri = _uri(path);
    return _send(
      uri,
      () => _client!.post(
        uri,
        headers: <String, String>{
          ...authHeaders,
          'content-type': 'application/json',
          'accept': 'application/json',
        },
        body: jsonEncode(payload),
      ),
    );
  }

  Future<Map<String, Object?>> getJson(
    String path,
    Map<String, String> query,
  ) async {
    final uri = _uri(path, query);
    return _send(
      uri,
      () => _client!.get(
        uri,
        headers: <String, String>{
          ...authHeaders,
          'accept': 'application/json',
        },
      ),
    );
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    if (!isConfigured) {
      throw const ApiError('联网服务未配置：缺少 API Key', kind: ApiErrorKind.auth);
    }
    final suffix = path.startsWith('/') ? path : '/$path';
    final uri = Uri.tryParse('$root$suffix');
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw ApiError('联网服务地址无效（$baseUrl）', kind: ApiErrorKind.parse);
    }
    return query == null || query.isEmpty
        ? uri
        : uri.replace(queryParameters: query);
  }

  Future<Map<String, Object?>> _send(
    Uri uri,
    Future<http.Response> Function() request,
  ) async {
    final client = _clientFactory();
    _client = client;
    try {
      final response = await request().timeout(timeout);
      final text = utf8.decode(response.bodyBytes, allowMalformed: true);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final mapped = apiErrorFromStatus(response.statusCode, text);
        throw ApiError(
          '联网服务请求失败：${mapped.message}',
          statusCode: response.statusCode,
          body: text,
          kind: mapped.kind,
        );
      }
      final decoded = jsonDecode(text);
      if (decoded is Map) return Map<String, Object?>.from(decoded);
      throw const ApiError('联网服务返回格式异常', kind: ApiErrorKind.parse);
    } on ApiError {
      rethrow;
    } on TimeoutException catch (error) {
      throw ApiError(
        '联网服务超时，稍后再试',
        cause: error,
        kind: ApiErrorKind.timeout,
      );
    } on FormatException catch (error) {
      throw ApiError(
        '联网服务返回格式异常',
        cause: error,
        kind: ApiErrorKind.parse,
      );
    } catch (error) {
      throw ApiError(
        '联网服务请求失败：${extractApiErrorDetail(error.toString()) ?? error}',
        cause: error,
        kind: ApiErrorKind.network,
      );
    } finally {
      if (identical(_client, client)) _client = null;
      client.close();
    }
  }

  @override
  void dispose() {
    final client = _client;
    _client = null;
    client?.close();
  }
}

/// DeepSeek 官方 Search / Fetch API。
///
/// `POST {base}/v1/tools/search`、`POST {base}/v1/tools/fetch`。
class DeepSeekWebSearchService extends HttpWebSearchService {
  DeepSeekWebSearchService({
    required super.baseUrl,
    required super.apiKey,
    super.clientFactory,
    super.timeout,
  });

  @override
  bool get supportsFetch => true;

  @override
  Map<String, String> get authHeaders =>
      <String, String>{'authorization': 'Bearer ${apiKey.trim()}'};

  @override
  Future<List<WebSearchItem>> search(String query, {int count = 8}) async {
    final body = await postJson('/v1/tools/search', <String, Object?>{
      'query': query,
      'count': count.clamp(1, 50),
      'need_content': false,
    });
    return _itemsOf(body['results']);
  }

  @override
  Future<WebFetchPage> fetchPage(String url) async {
    final body = await postJson('/v1/tools/fetch', <String, Object?>{'url': url});
    return WebFetchPage(
      url: url,
      title: body['title']?.toString(),
      content: (body['content'] ?? '').toString(),
    );
  }
}

/// Tavily Search / Extract。
///
/// `POST {base}/search`、`POST {base}/extract`；Bearer 鉴权。
class TavilyWebSearchService extends HttpWebSearchService {
  TavilyWebSearchService({
    required super.baseUrl,
    required super.apiKey,
    super.clientFactory,
    super.timeout,
  });

  @override
  bool get supportsFetch => true;

  @override
  Map<String, String> get authHeaders =>
      <String, String>{'authorization': 'Bearer ${apiKey.trim()}'};

  @override
  Future<List<WebSearchItem>> search(String query, {int count = 8}) async {
    final body = await postJson('/search', <String, Object?>{
      'query': query,
      'max_results': count.clamp(1, 20),
      'search_depth': 'basic',
      'include_raw_content': false,
    });
    return _itemsOf(body['results']);
  }

  @override
  Future<WebFetchPage> fetchPage(String url) async {
    final body = await postJson('/extract', <String, Object?>{
      'urls': <String>[url],
      'format': 'markdown',
    });
    final results = body['results'];
    if (results is List && results.isNotEmpty && results.first is Map) {
      final first = Map<String, Object?>.from(results.first as Map);
      return WebFetchPage(
        url: url,
        title: first['title']?.toString(),
        content: (first['raw_content'] ?? '').toString(),
      );
    }
    final failed = body['failed_results'];
    final reason = failed is List && failed.isNotEmpty && failed.first is Map
        ? (Map<String, Object?>.from(failed.first as Map)['error'] ??
                '无法提取正文')
            .toString()
        : '无法提取正文';
    throw ApiError('读取链接失败：$reason', kind: ApiErrorKind.parse);
  }
}

/// 博查 Bocha Web Search（仅搜索）。
///
/// `POST {base}/v1/web-search`；Bearer 鉴权；`summary: true` 返回长摘要。
class BochaWebSearchService extends HttpWebSearchService {
  BochaWebSearchService({
    required super.baseUrl,
    required super.apiKey,
    super.clientFactory,
    super.timeout,
  });

  @override
  bool get supportsFetch => false;

  @override
  Map<String, String> get authHeaders =>
      <String, String>{'authorization': 'Bearer ${apiKey.trim()}'};

  @override
  Future<List<WebSearchItem>> search(String query, {int count = 8}) async {
    final body = await postJson('/v1/web-search', <String, Object?>{
      'query': query,
      'count': count.clamp(1, 50),
      'summary': true,
    });
    final data = body['data'];
    if (data is! Map) return const <WebSearchItem>[];
    final pages = data['webPages'];
    if (pages is! Map) return const <WebSearchItem>[];
    return _itemsOf(pages['value']);
  }

  @override
  Future<WebFetchPage> fetchPage(String url) async {
    throw const ApiError(
      '博查服务不支持读取链接（read_url），请改用支持抓取的搜索服务',
      kind: ApiErrorKind.parse,
    );
  }
}

/// Brave Search（仅搜索）。
///
/// `GET {base}/res/v1/web/search?q=…&count=…`；`X-Subscription-Token` 鉴权。
class BraveWebSearchService extends HttpWebSearchService {
  BraveWebSearchService({
    required super.baseUrl,
    required super.apiKey,
    super.clientFactory,
    super.timeout,
  });

  @override
  bool get supportsFetch => false;

  @override
  Map<String, String> get authHeaders => <String, String>{
        'x-subscription-token': apiKey.trim(),
      };

  @override
  Future<List<WebSearchItem>> search(String query, {int count = 8}) async {
    final body = await getJson('/res/v1/web/search', <String, String>{
      'q': query,
      'count': '${count.clamp(1, 20)}',
      'result_filter': 'web',
    });
    final web = body['web'];
    if (web is! Map) return const <WebSearchItem>[];
    return _itemsOf(web['results']);
  }

  @override
  Future<WebFetchPage> fetchPage(String url) async {
    throw const ApiError(
      'Brave Search 不支持读取链接（read_url），请改用支持抓取的搜索服务',
      kind: ApiErrorKind.parse,
    );
  }
}

/// `results[]` → [WebSearchItem] 列表（丢弃没有 url 的条目）。
List<WebSearchItem> _itemsOf(Object? raw) {
  if (raw is! List) return const <WebSearchItem>[];
  return <WebSearchItem>[
    for (final item in raw)
      if (item is Map) WebSearchItem.fromJson(Map<String, Object?>.from(item)),
  ].where((item) => item.url.trim().isNotEmpty).toList(growable: false);
}

/// 按配置构造外部搜索服务；未配置（缺 Key / 缺地址）时返回 null。
WebSearchService? webSearchServiceFor(
  WebSearchConfig config, {
  String fallbackApiKey = '',
  http.Client Function()? clientFactory,
}) {
  final base = config.effectiveBaseUrl;
  final key = config.effectiveApiKey(fallbackApiKey);
  if (base.isEmpty || key.isEmpty) return null;
  switch (config.serviceId) {
    case kSearchServiceTavily:
      return TavilyWebSearchService(
        baseUrl: base,
        apiKey: key,
        clientFactory: clientFactory,
      );
    case kSearchServiceBocha:
      return BochaWebSearchService(
        baseUrl: base,
        apiKey: key,
        clientFactory: clientFactory,
      );
    case kSearchServiceBrave:
      return BraveWebSearchService(
        baseUrl: base,
        apiKey: key,
        clientFactory: clientFactory,
      );
    case kSearchServiceDeepSeek:
    default:
      return DeepSeekWebSearchService(
        baseUrl: base,
        apiKey: key,
        clientFactory: clientFactory,
      );
  }
}
