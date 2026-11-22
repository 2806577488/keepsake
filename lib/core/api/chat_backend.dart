/// Keepsake（留声）— 聊天后端统一抽象 / 事件模型 / 网络错误。
///
/// 符号证据（`reports/apk/dart-symbols.md` §2）：`ChatBackend`、`ChatStream`、
/// `ApiError`、`apiErrorFromStatus`；事件类型字符串：`text_delta`、
/// `thinking_delta`、`web_search_tool_result`、`usage`、`message_stop`。
///
/// 结构：
/// - [ChatBackend]（接口）→ [HttpChatBackend]（HTTP/取消/错误映射公共实现）
///   → `OpenAiClient` / `AnthropicClient`（批次 C 同一目录）；
/// - 对外只暴露 `Stream<ChatEvent> streamChat(ChatRequest)`；
/// - 取消：`ChatBackend.cancel()` 直接关掉在飞 HTTP，流静默结束（不报错），
///   或由调用方取消订阅（async* 生成器会把内层订阅一起取消）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../chat/attachments.dart';
import '../usage/usage.dart';
import 'anthropic_client.dart';
import 'openai_client.dart';
import 'provider_models.dart';
import 'sse.dart';

export '../usage/usage.dart' show UsageDelta, UsageTotals;
export 'provider_models.dart' show AiProvider, ProviderKind, ProviderModel;

// ---------------------------------------------------------------------------
// 错误文案（ui-strings.txt §11 原文 [确定]）
// ---------------------------------------------------------------------------

const String kNetworkErrorMessage = '网络错误，请检查网络后重试';
const String kRateLimitErrorMessage = '请求太频繁，稍后再试';
const String kInsufficientBalanceMessage = '余额不足，请充值后再试';
const String kInvalidApiKeyMessage = 'API Key 无效或未填写';
const String kUnexpectedResponseTypeMessage = '意外的响应类型：';
const String kUnparsableNonStreamMessage = '无法解析非流式响应';
const String kRequestFailedPrefix = '请求失败：HTTP ';

/// 思考强度 → `budget_tokens` 档位（[推断] 数值，字段名有实证）。
const int kThinkingBudgetLow = 2048;
const int kThinkingBudgetMedium = 8192;
const int kThinkingBudgetHigh = 16384;

/// 联网搜索工具名（http-api.md §4 原文 [确定]）。
const String kToolWebSearch = 'deepseek_web_search';
const String kToolReadUrl = 'deepseek_read_url';

/// 工具类型常量（字符串表原文 `TOOL_SEARCH` / `Search Web`）。
const String kToolSearch = 'TOOL_SEARCH';
const String kToolSearchDescription = 'Search Web';

/// 错误分类，UI 可据此决定是否给「重试」按钮。
enum ApiErrorKind {
  unknown,
  network,
  timeout,
  cancelled,
  auth,
  rateLimit,
  insufficientBalance,
  http,
  parse,
}

/// 可直接展示给用户的 API/网络错误。
class ApiError implements Exception {
  const ApiError(
    this.message, {
    this.statusCode,
    this.body,
    this.cause,
    this.kind = ApiErrorKind.unknown,
  });

  /// 已本地化、可直接展示的中文文案。
  final String message;

  /// HTTP 状态码（网络层错误为 null）。
  final int? statusCode;

  /// 响应体（调试/日志用，不含 Key）。
  final String? body;

  /// 原始异常（`TimeoutException` / `ClientException` / `FormatException`…）。
  final Object? cause;

  final ApiErrorKind kind;

  bool get isNetwork => kind == ApiErrorKind.network;
  bool get isTimeout => kind == ApiErrorKind.timeout;
  bool get isCancelled => kind == ApiErrorKind.cancelled;
  bool get isAuth => kind == ApiErrorKind.auth;
  bool get isRateLimited => kind == ApiErrorKind.rateLimit;
  bool get isInsufficientBalance =>
      kind == ApiErrorKind.insufficientBalance;
  bool get isParseError => kind == ApiErrorKind.parse;

  /// 是否值得给用户「重试」。
  bool get isRetryable =>
      isNetwork || isTimeout || isRateLimited ||
      (statusCode != null && statusCode! >= 500);

  factory ApiError.network([Object? cause]) =>
      ApiError(kNetworkErrorMessage, cause: cause, kind: ApiErrorKind.network);

  factory ApiError.timeout([Object? cause]) =>
      ApiError(kNetworkErrorMessage, cause: cause, kind: ApiErrorKind.timeout);

  factory ApiError.cancelled() =>
      const ApiError('已取消', kind: ApiErrorKind.cancelled);

  factory ApiError.parse(String message, {Object? cause}) =>
      ApiError(message, cause: cause, kind: ApiErrorKind.parse);

  @override
  String toString() => message;
}

/// HTTP 状态码 → 本地化 [ApiError]。
///
/// 映射（ui-strings §11）：401/403 → API Key 无效或未填写；402 → 余额不足；
/// 429 → 请求太频繁；408/5xx → 网络错误；其它 4xx → 响应体里的 error.message
/// 或 `请求失败：HTTP <code>`。
ApiError apiErrorFromStatus(int statusCode, [String? body]) {
  final text = body ?? '';
  if (statusCode == 401 || statusCode == 403) {
    return ApiError(
      kInvalidApiKeyMessage,
      statusCode: statusCode,
      body: text,
      kind: ApiErrorKind.auth,
    );
  }
  if (statusCode == 402) {
    return ApiError(
      kInsufficientBalanceMessage,
      statusCode: statusCode,
      body: text,
      kind: ApiErrorKind.insufficientBalance,
    );
  }
  if (statusCode == 429) {
    return ApiError(
      kRateLimitErrorMessage,
      statusCode: statusCode,
      body: text,
      kind: ApiErrorKind.rateLimit,
    );
  }
  if (statusCode == 408 || statusCode >= 500) {
    return ApiError(
      kNetworkErrorMessage,
      statusCode: statusCode,
      body: text,
      kind: ApiErrorKind.network,
    );
  }
  final detail = extractApiErrorDetail(text);
  return ApiError(
    detail ?? '$kRequestFailedPrefix$statusCode',
    statusCode: statusCode,
    body: text,
    kind: ApiErrorKind.http,
  );
}

/// 从常见错误 JSON（`{"error":{"message":...}}` / `{"message":...}`）里取文案。
String? extractApiErrorDetail(String body) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) return null;
  try {
    final decoded = jsonDecode(trimmed);
    final detail = _errorDetailOf(decoded);
    if (detail != null && detail.trim().isNotEmpty) return detail.trim();
  } catch (_) {
    // 不是 JSON：把纯文本当错误信息（截断，避免粘出整页 HTML）。
  }
  return trimmed.length > 300 ? '${trimmed.substring(0, 300)}…' : trimmed;
}

String? _errorDetailOf(Object? node) {
  if (node is String) return node;
  if (node is Map) {
    final map = Map<String, Object?>.from(node);
    for (final key in const <String>[
      'error',
      'message',
      'detail',
      'msg',
      'error_msg',
      'errors',
    ]) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value;
      if (value is Map || value is List) {
        final nested = _errorDetailOf(value);
        if (nested != null && nested.trim().isNotEmpty) return nested;
      }
    }
  }
  if (node is List) {
    for (final item in node) {
      final nested = _errorDetailOf(item);
      if (nested != null && nested.trim().isNotEmpty) return nested;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// 消息 / 请求
// ---------------------------------------------------------------------------

/// 一条发往模型的消息（role + 纯文本正文 + 可选的思考内容）。
class ChatTurn {
  const ChatTurn({
    required this.role,
    required this.content,
    this.reasoningContent,
  });

  const ChatTurn.system(this.content)
      : role = 'system',
        reasoningContent = null;
  const ChatTurn.user(this.content)
      : role = 'user',
        reasoningContent = null;
  const ChatTurn.assistant(this.content, {this.reasoningContent})
      : role = 'assistant';

  final String role;
  final String content;

  /// assistant 轮的思考原文（`reasoning_content`）。
  ///
  /// 官方「Thinking Mode › Tool Calls」：请求带 `tools` 时，历史轮次的
  /// `reasoning_content` 必须完整回传，否则返回 400；不带 `tools` 时该字段
  /// 会被官方忽略（https://api-docs.deepseek.com/guides/thinking_mode#tool-calls）。
  final String? reasoningContent;

  bool get isSystem => role == 'system';
  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  factory ChatTurn.fromJson(Map<String, Object?> json) => ChatTurn(
        role: (json['role'] ?? 'user').toString(),
        content: (json['content'] ?? '').toString(),
        reasoningContent: (json['reasoning_content'] ??
                json['reasoningContent'])
            ?.toString(),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'role': role,
        'content': content,
        'reasoning_content': ?reasoningContent,
      };

  @override
  String toString() => 'ChatTurn($role, ${content.length} chars)';
}

/// 一次聊天请求的参数（provider 由 [ChatBackend] 绑定）。
class ChatRequest {
  ChatRequest({
    required this.provider,
    required List<ChatTurn> messages,
    List<Attachment> attachments = const <Attachment>[],
    this.systemPrompt,
    this.model,
    this.maxTokens,
    this.thinking = false,
    this.thinkingLevel,
    this.search = false,
    this.stop,
    this.metadata,
    this.timeout,
  })  : messages = List<ChatTurn>.unmodifiable(messages),
        attachments = List<Attachment>.unmodifiable(attachments);

  final AiProvider provider;

  /// 历史消息（不含 system；system 由 [systemPrompt] 单独给）。
  final List<ChatTurn> messages;

  /// 只对最后一条 user 消息生效的附件（DeepSeek Files API）。
  final List<Attachment> attachments;

  final String? systemPrompt;
  final String? model;
  final int? maxTokens;

  /// 深度思考开关。
  final bool thinking;

  /// 思考档位：'低'/'中'/'高' 字符串，或 Settings 里可能存的 int（0=关/1/2/3）。
  final Object? thinkingLevel;

  /// 联网搜索（DeepSeek 扩展工具）。
  final bool search;

  final List<String>? stop;
  final Map<String, Object?>? metadata;

  /// 覆盖默认超时。
  final Duration? timeout;

  /// 实际使用的模型名。
  String get modelName {
    final explicit = (model ?? '').trim();
    return explicit.isEmpty ? provider.model.trim() : explicit;
  }

  String get effectiveSystemPrompt => (systemPrompt ?? '').trim();

  int get thinkingBudget => thinkingBudgetOf(thinkingLevel);

  ChatRequest copyWith({
    AiProvider? provider,
    List<ChatTurn>? messages,
    List<Attachment>? attachments,
    String? systemPrompt,
    String? model,
    int? maxTokens,
    bool? thinking,
    Object? thinkingLevel,
    bool? search,
    List<String>? stop,
    Map<String, Object?>? metadata,
    Duration? timeout,
  }) =>
      ChatRequest(
        provider: provider ?? this.provider,
        messages: messages ?? this.messages,
        attachments: attachments ?? this.attachments,
        systemPrompt: systemPrompt ?? this.systemPrompt,
        model: model ?? this.model,
        maxTokens: maxTokens ?? this.maxTokens,
        thinking: thinking ?? this.thinking,
        thinkingLevel: thinkingLevel ?? this.thinkingLevel,
        search: search ?? this.search,
        stop: stop ?? this.stop,
        metadata: metadata ?? this.metadata,
        timeout: timeout ?? this.timeout,
      );
}

/// 思考档位 → `budget_tokens`。
///
/// 兼容：`null`（默认中档）、int（0=关 / 1 / 2 / 3）、字符串
/// （`低`/`中`/`高`、`low`/`medium`/`high`）、以及 Settings 的
/// `ThinkingLevel` 枚举（按 `.label` / `toString()` 识别）。
int thinkingBudgetOf(Object? level) => switch (_thinkingKeyOf(level)) {
      'off' => 0,
      'low' => kThinkingBudgetLow,
      'high' => kThinkingBudgetHigh,
      _ => kThinkingBudgetMedium,
    };

/// 思考档位 → UI 标签（`低` / `中` / `高`），无法判定返回 null。
String? thinkingLevelLabelOf(Object? level) =>
    switch (_thinkingKeyOf(level)) {
      'low' => '低',
      'medium' => '中',
      'high' => '高',
      _ => null,
    };

/// 把各种写法的档位归一成 `off` / `low` / `medium` / `high`。
String? _thinkingKeyOf(Object? level) {
  if (level == null) return null;
  if (level is int) {
    if (level <= 0) return 'off';
    if (level == 1) return 'low';
    if (level == 2) return 'medium';
    return 'high';
  }
  if (level is num) return _thinkingKeyOf(level.round());
  if (level is String) {
    final text = level.trim();
    if (text.isEmpty) return null;
    final lower = text.toLowerCase();
    if (lower == 'off' || text == '关' || lower == 'false') return 'off';
    if (text.contains('高') || lower.contains('high')) return 'high';
    if (text.contains('中') || lower.contains('medium')) return 'medium';
    if (text.contains('低') || lower.contains('low')) return 'low';
    final parsed = int.tryParse(text);
    return parsed == null ? null : _thinkingKeyOf(parsed);
  }
  // Settings.ThinkingLevel 等枚举：先看 .label，再看 .wireName，最后 toString。
  final dynamic node = level;
  try {
    final dynamic label = node.label;
    if (label is String && label.trim().isNotEmpty) {
      final key = _thinkingKeyOf(label);
      if (key != null) return key;
    }
  } catch (_) {
    // 不是枚举，继续。
  }
  try {
    final dynamic wire = node.wireName;
    if (wire is String && wire.trim().isNotEmpty) {
      final key = _thinkingKeyOf(wire);
      if (key != null) return key;
    }
  } catch (_) {
    // 忽略。
  }
  return _thinkingKeyOf(level.toString());
}

/// 思考档位 → 官方 `reasoning_effort` / `output_config.effort`。
///
/// 官方映射（https://api-docs.deepseek.com/guides/thinking_mode）：
/// `minimal→low`、`low→low`、`medium→high`、`high→high`、`xhigh→high`、
/// `max→max`、`ultra→max`。UI 只有三档，所以：
/// 低 → `low`，中 → `high`，高 → `max`（用 `medium` 会让「中/高」无差别）。
/// `off` / 无法识别 → null（不下发强度字段）。
String? thinkingEffortOf(Object? level) => switch (_thinkingKeyOf(level)) {
      'low' => 'low',
      'medium' => 'high',
      'high' => 'max',
      _ => null,
    };

/// 把思考开关/强度补进请求体（OpenAI 兼容格式）。
///
/// 官方字段（https://api-docs.deepseek.com/api/create-chat-completion）：
/// - 开关：`thinking: {"type": "enabled"|"disabled"}`，省略时**默认开启**，
///   所以关闭时必须显式发 `disabled`；
/// - 强度：顶层 `reasoning_effort`（`low`/`high`/`max`）。
///
/// 旧实现发的 `reasoning: {level, budget_tokens}` 不是 Chat Completions 的
/// 字段，已删除（`budget_tokens` 只在 Anthropic 侧且被官方标记为 Ignored）。
void ensureReasoning(
  Map<String, Object?> body, {
  required bool enabled,
  Object? thinkingLevel,
}) {
  body['thinking'] = <String, Object?>{'type': enabled ? 'enabled' : 'disabled'};
  // 关闭时不下发强度字段（开关优先级高于 reasoning_effort）。
  if (!enabled) return;
  final effort = thinkingEffortOf(thinkingLevel);
  if (effort == null) return;
  body['reasoning_effort'] = effort;
}

/// DeepSeek 联网工具声明（服务端工具，Anthropic Messages 协议形状）。
///
/// 按官方文档「联网工具」：`{"type": "deepseek_web_search", "name": "deepseek_web_search"}`。
/// 声明成普通自定义工具（只有 name/input_schema、没有 type）时，模型会走客户端
/// `tool_use`，而客户端并不执行它 —— 表现就是「搜索时卡住」。
List<Map<String, Object?>> deepSeekSearchTools() => <Map<String, Object?>>[
      <String, Object?>{'type': kToolWebSearch, 'name': kToolWebSearch},
      <String, Object?>{'type': kToolReadUrl, 'name': kToolReadUrl},
    ];

// ---------------------------------------------------------------------------
// 流式事件
// ---------------------------------------------------------------------------

/// 联网搜索结果条目。
class SearchSource {
  const SearchSource({
    required this.url,
    this.title,
    this.snippet,
    this.siteName,
    this.publishedAt,
  });

  final String url;
  final String? title;
  final String? snippet;
  final String? siteName;
  final String? publishedAt;

  factory SearchSource.fromJson(Map<String, Object?> json) => SearchSource(
        url: (json['url'] ?? '').toString(),
        title: json['title']?.toString(),
        snippet: (json['snippet'] ?? json['text'] ?? json['content'])?.toString(),
        siteName: (json['site_name'] ?? json['siteName'] ?? json['site'])
            ?.toString(),
        publishedAt: (json['published_at'] ??
                json['publishedAt'] ??
                json['date'])
            ?.toString(),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'url': url,
        'title': ?title,
        'snippet': ?snippet,
        'site_name': ?siteName,
        'published_at': ?publishedAt,
      };

  @override
  String toString() => 'SearchSource($url)';
}

/// 流式聊天事件。
sealed class ChatEvent {
  const ChatEvent();
}

/// 正文增量。
final class TextDelta extends ChatEvent {
  const TextDelta(this.text);

  final String text;

  @override
  String toString() => 'TextDelta(${text.length} chars)';
}

/// 思考过程增量。
final class ThinkingDelta extends ChatEvent {
  const ThinkingDelta(this.text);

  final String text;

  @override
  String toString() => 'ThinkingDelta(${text.length} chars)';
}

/// token 用量（OpenAI 尾部 usage / Anthropic message_start+message_delta）。
final class Usage extends ChatEvent {
  const Usage(this.usage);

  final UsageDelta usage;

  @override
  String toString() => 'Usage($usage)';
}

/// 正文里的一处引用（DeepSeek `annotations`/`citations` 的定位信息）。
///
/// [start] / [end] 是正文里的字符下标（按 Unicode 码点计，DeepSeek 约定），
/// 渲染时在 [end] 处插入形如 `[3]` 的编号角标。
class CitationMark {
  const CitationMark({
    required this.url,
    this.title,
    required this.start,
    required this.end,
  });

  final String url;
  final String? title;
  final int start;
  final int end;

  @override
  String toString() => 'CitationMark($url @$start..$end)';
}

/// 联网搜索 / 读链接进度与结果。
///
/// [running] 为 true 时 UI 显示「正在联网搜索」/「正在读取链接」；
/// [sources] 非空时是最终结果。
final class ToolResult extends ChatEvent {
  const ToolResult({
    required this.tool,
    this.resultType,
    this.running = false,
    this.sources = const <SearchSource>[],
    this.text = '',
    this.query,
    this.citations = const <CitationMark>[],
  });

  /// `deepseek_web_search` / `deepseek_read_url`。
  final String tool;

  /// `web_search_tool_result` / `web_fetch_tool_result`（[结果类型] 字符串）。
  final String? resultType;

  final bool running;

  final List<SearchSource> sources;

  /// 工具返回的文本（读链接时的正文摘要）。
  final String text;

  final String? query;

  /// 正文里的引用角标（`annotations` / `citations_delta` 的定位）。
  final List<CitationMark> citations;

  bool get isReadUrl => tool == kToolReadUrl;

  /// UI 文案：「正在联网搜索」/「正在读取链接」。
  String get label => isReadUrl ? '正在读取链接' : '正在联网搜索';

  @override
  String toString() => 'ToolResult($tool, running: $running, '
      '${sources.length} sources)';
}

/// 流正常结束。
final class Done extends ChatEvent {
  const Done({this.finishReason});

  /// `stop` / `length` / `tool_use` 等。
  final String? finishReason;

  @override
  String toString() => 'Done($finishReason)';
}

/// 流内非致命错误（HTTP/网络级致命错误直接抛 [ApiError]）。
final class Failure extends ChatEvent {
  const Failure(this.error);

  final ApiError error;

  @override
  String toString() => 'Failure($error)';
}

/// 一次可取消的聊天流。
class ChatStream {
  ChatStream(this.events, {this.onCancel});

  factory ChatStream.of(
    Stream<ChatEvent> events, {
    Future<void> Function()? onCancel,
  }) =>
      ChatStream(events, onCancel: onCancel);

  final Stream<ChatEvent> events;

  /// 取消回调（通常是 `ChatBackend.cancel`）。
  final Future<void> Function()? onCancel;

  StreamSubscription<ChatEvent> listen(
    void Function(ChatEvent event)? onEvent, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      events.listen(
        onEvent,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  /// 中止底层请求（关闭 HTTP client）。
  Future<void> cancel() async {
    final callback = onCancel;
    if (callback != null) await callback();
  }
}

// ---------------------------------------------------------------------------
// 后端接口
// ---------------------------------------------------------------------------

/// 聊天后端（OpenAI 兼容 / Anthropic 兼容统一入口）。
abstract interface class ChatBackend {
  /// 绑定的平台配置。
  AiProvider get provider;

  /// `POST` 聊天地址。
  String get chatUrl;

  /// `GET` 模型列表地址。
  String get modelsUrl;

  /// 是否已被 [cancel] 取消。
  bool get isCancelled;

  /// 发起流式聊天；错误以 stream error 形式抛出 [ApiError]。
  Stream<ChatEvent> streamChat(ChatRequest request);

  /// [streamChat] + 取消句柄。
  ChatStream openChat(ChatRequest request);

  /// 拉取真实模型列表（`GET {base}/models`）。
  Future<List<ProviderModel>> listModels();

  /// 中止在飞请求；流静默结束。
  Future<void> cancel();

  /// 释放资源。
  void dispose();

  /// 按 `provider.kind` 选择实现。
  static ChatBackend of(
    AiProvider provider, {
    http.Client Function()? clientFactory,
    Duration? timeout,
  }) =>
      chatBackendFor(
        provider,
        clientFactory: clientFactory,
        timeout: timeout,
      );
}

/// HTTP 后端公共实现：client 生命周期、取消、错误映射、SSE 判定。
abstract class HttpChatBackend implements ChatBackend {
  HttpChatBackend({
    required this.provider,
    http.Client Function()? clientFactory,
    Duration? timeout,
  })  : _clientFactory = clientFactory ?? http.Client.new,
        defaultTimeout = timeout ?? const Duration(seconds: 90);

  @override
  final AiProvider provider;

  final http.Client Function() _clientFactory;

  /// 默认请求超时（仅覆盖「拿到响应头」阶段，流式正文不受影响）。
  final Duration defaultTimeout;

  http.Client? _activeClient;
  bool _cancelled = false;
  bool _disposed = false;

  @override
  bool get isCancelled => _cancelled;

  bool get isDisposed => _disposed;

  /// 规范化后的接口地址（去尾部 `/`、补 https）。
  String get normalizedBase => normalizeProviderBase(provider.baseUrl);

  /// 实际使用的模型名。
  String get modelName => provider.model;

  /// API Key。
  String get apiKey => provider.apiKey;

  /// 创建并登记一个 HTTP client（[releaseClient] 负责关闭）。
  http.Client openClient() {
    if (_disposed) throw ApiError.cancelled();
    _cancelled = false;
    final client = _clientFactory();
    _activeClient = client;
    return client;
  }

  void releaseClient(http.Client client) {
    if (identical(_activeClient, client)) _activeClient = null;
    client.close();
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
    final client = _activeClient;
    _activeClient = null;
    client?.close();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelled = true;
    final client = _activeClient;
    _activeClient = null;
    client?.close();
  }

  @override
  ChatStream openChat(ChatRequest request) =>
      ChatStream.of(streamChat(request), onCancel: cancel);

  /// 发送请求（只覆盖响应头阶段；`TimeoutException` → [ApiError]）。
  Future<http.StreamedResponse> sendStreamed(
    http.Client client,
    http.BaseRequest request, {
    Duration? timeout,
  }) async {
    try {
      return await client.send(request).timeout(timeout ?? defaultTimeout);
    } on TimeoutException catch (error) {
      throw ApiError.timeout(error);
    } on http.ClientException catch (error) {
      if (_cancelled) throw ApiError.cancelled();
      throw ApiError.network(error);
    } on ApiError {
      rethrow;
    } catch (error) {
      if (_cancelled) throw ApiError.cancelled();
      throw ApiError.network(error);
    }
  }

  /// `Content-Type` 是否 `text/event-stream`。
  static bool isEventStreamContentType(String? contentType) =>
      (contentType ?? '').toLowerCase().contains(sseContentType);

  /// `Content-Type` 是否 JSON。
  static bool isJsonContentType(String? contentType) =>
      (contentType ?? '').toLowerCase().contains('json');

  /// 非 2xx 直接抛 [ApiError]。
  static void ensureSuccess(int statusCode, String body) {
    if (statusCode >= 200 && statusCode < 300) return;
    throw apiErrorFromStatus(statusCode, body);
  }

  /// 把响应体解析成 JSON 对象（失败 → 「无法解析非流式响应」）。
  static Map<String, Object?> decodeJsonObject(
    String body, {
    String message = kUnparsableNonStreamMessage,
  }) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } catch (_) {
      // fall through
    }
    throw ApiError(message, kind: ApiErrorKind.parse);
  }

  /// 把 SSE 断流异常转成 [ApiError]。
  static ApiError interruptedError(SseInterruptedException error) =>
      ApiError(error.message, kind: ApiErrorKind.network);
}

/// 按平台协议类型构造后端。
///
/// `provider.kind == anthropic` → `AnthropicClient`，否则 `OpenAiClient`。
ChatBackend chatBackendFor(
  AiProvider provider, {
  http.Client Function()? clientFactory,
  Duration? timeout,
}) {
  switch (provider.kind) {
    case ProviderKind.anthropic:
      return AnthropicClient(
        provider: provider,
        clientFactory: clientFactory,
        timeout: timeout,
      );
    case ProviderKind.openai:
      return OpenAiClient(
        provider: provider,
        clientFactory: clientFactory,
        timeout: timeout,
      );
  }
}
