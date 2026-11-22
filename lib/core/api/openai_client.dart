/// Keepsake（留声）— OpenAI 兼容聊天客户端。
///
/// 协议证据（`reports/apk/http-api.md` §3/§4）：`POST {base}/chat/completions`、
/// `Authorization: Bearer`、SSE `data:` + `[DONE]`、
/// `choices[0].delta.content` / `delta.reasoning_content` / `finish_reason` /
/// `usage`、`stream_options.include_usage`；非流式回退文案
/// 「无法解析非流式响应」「意外的响应类型：」。
///
/// 符号证据：`OpenAiClient`、`openAiMessagesFromAnthropic`、`get:chatUrl`、
/// `get:modelsUrl`、`ensureReasoning`。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../chat/attachments.dart' show Attachment;
import '../usage/usage.dart';
import 'chat_backend.dart';
import 'model_list.dart' show fetchProviderModels, modelsUrlOf;
import 'sse.dart';

/// OpenAI 兼容客户端。
class OpenAiClient extends HttpChatBackend {
  OpenAiClient({
    required super.provider,
    super.clientFactory,
    super.timeout,
  });

  /// `POST {base}/chat/completions`。
  @override
  String get chatUrl {
    final base = normalizedBase;
    if (base.toLowerCase().endsWith('/chat/completions')) return base;
    return '$base/chat/completions';
  }

  /// `GET {base}/models`。
  @override
  String get modelsUrl => modelsUrlOf(normalizedBase);

  /// 拉取真实模型列表。
  @override
  Future<List<ProviderModel>> listModels() async {
    final client = openClient();
    try {
      return await fetchProviderModels(
        baseUrl: normalizedBase,
        apiKey: apiKey,
        kind: provider.kind,
        client: client,
        timeout: defaultTimeout,
      );
    } finally {
      releaseClient(client);
    }
  }

  // -------------------------------------------------------------------
  // 请求体
  // -------------------------------------------------------------------

  /// 组装 `POST /chat/completions` 的 JSON body。
  ///
  /// 支持的 key：`model`、`messages`（含 `reasoning_content` 与 `file`
  /// content block）、`stream`、`max_tokens`、`thinking{type}`、
  /// `reasoning_effort`、`stop`、`tools`、`stream_options.include_usage`。
  Map<String, Object?> buildRequestBody(ChatRequest request) {
    final model = request.modelName;
    if (model.isEmpty) {
      throw ApiError('先填一个模型名', kind: ApiErrorKind.parse);
    }

    final messages = <Map<String, Object?>>[];
    // 附件只挂在最后一条 user 消息上（多轮时不能挂到别人头上）。
    int? lastUserIndex;
    final system = request.effectiveSystemPrompt;
    if (system.isNotEmpty) {
      messages.add(<String, Object?>{'role': 'system', 'content': system});
    }
    for (final turn in request.messages) {
      final content = turn.content;
      if (content.trim().isEmpty && !turn.isUser) continue;
      final message = <String, Object?>{
        'role': _wireRole(turn.role),
        'content': content,
      };
      // 带 tools 的请求必须回传历史轮的 reasoning_content，否则官方 400；
      // 不带 tools 时该字段被官方忽略，所以只在搜索（tools）时回传。
      final reasoning = turn.reasoningContent?.trim() ?? '';
      if (request.search && turn.isAssistant && reasoning.isNotEmpty) {
        message['reasoning_content'] = reasoning;
      }
      messages.add(message);
      if (turn.isUser) lastUserIndex = messages.length - 1;
    }

    final body = <String, Object?>{
      'model': model,
      'messages': messages,
      'stream': true,
      'stream_options': <String, Object?>{'include_usage': true},
    };

    final maxTokens = request.maxTokens;
    if (maxTokens != null && maxTokens > 0) {
      body['max_tokens'] = maxTokens;
    }
    ensureReasoning(
      body,
      enabled: request.thinking,
      thinkingLevel: request.thinkingLevel,
    );
    final stop = request.stop;
    if (stop != null && stop.isNotEmpty) {
      body['stop'] = stop;
    }
    if (request.search) {
      body['tools'] = _openAiTools();
    }
    final metadata = request.metadata;
    if (metadata != null && metadata.isNotEmpty) {
      body['metadata'] = metadata;
    }
    _attachFilesToLastUser(messages, request.attachments, lastUserIndex);
    return body;
  }

  Map<String, String> _requestHeaders() {
    final headers = <String, String>{
      'content-type': 'application/json',
      'accept': sseContentType,
    };
    final key = apiKey.trim();
    if (key.isNotEmpty) headers['authorization'] = 'Bearer $key';
    return headers;
  }

  // -------------------------------------------------------------------
  // 流式请求
  // -------------------------------------------------------------------

  /// 发起流式请求。
  ///
  /// 用显式 [StreamController] 而不是 `async*`：`await subscription.cancel()`
  /// 在 `async*` 生成器卡在 pending await 时**不会完成**（Dart 取消不会打断
  /// await），而且取消后再断流会把 `SseInterruptedException` 变成未捕获错误。
  /// 这里取消回调同步关掉 HTTP client 并置位 `isCancelled`，
  /// 取消 future 立即完成；迟到事件/错误按「已取消」静默丢弃。
  @override
  Stream<ChatEvent> streamChat(ChatRequest request) {
    final client = openClient();
    late final StreamController<ChatEvent> controller;
    controller = StreamController<ChatEvent>(
      onListen: () => unawaited(_pump(request, controller, client)),
      // 同步 abort：cancel() 里没有 await，返回的 future 已立即完成。
      onCancel: () => unawaited(cancel()),
    );
    return controller.stream;
  }

  Future<void> _pump(
    ChatRequest request,
    StreamController<ChatEvent> controller,
    http.Client client,
  ) async {
    try {
      final body = jsonEncode(buildRequestBody(request));
      final httpRequest = http.Request('POST', _parseChatUri())
        ..headers.addAll(_requestHeaders())
        ..body = body;

      final response = await sendStreamed(
        client,
        httpRequest,
        timeout: request.timeout,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final errorBody = await response.stream.bytesToString();
        throw apiErrorFromStatus(response.statusCode, errorBody);
      }
      if (isCancelled || controller.isClosed) return;

      final contentType = response.headers['content-type'];
      if (!HttpChatBackend.isEventStreamContentType(contentType)) {
        final text = await response.stream.bytesToString();
        if (isCancelled || controller.isClosed) return;
        if (!HttpChatBackend.isJsonContentType(contentType)) {
          throw ApiError(
            '$kUnexpectedResponseTypeMessage${contentType ?? 'unknown'}',
            kind: ApiErrorKind.parse,
          );
        }
        for (final event in _nonStreamEvents(text)) {
          if (isCancelled || controller.isClosed) return;
          controller.add(event);
        }
        return;
      }

      await for (final event in _sseEvents(response.stream)) {
        if (isCancelled || controller.isClosed) return;
        controller.add(event);
      }
    } on ApiError catch (error, stackTrace) {
      _report(controller, error, stackTrace);
    } on SseInterruptedException catch (error, stackTrace) {
      _report(controller, HttpChatBackend.interruptedError(error), stackTrace);
    } on TimeoutException catch (error, stackTrace) {
      _report(controller, ApiError.timeout(error), stackTrace);
    } on http.ClientException catch (error, stackTrace) {
      _report(controller, ApiError.network(error), stackTrace);
    } catch (error, stackTrace) {
      _report(controller, ApiError.network(error), stackTrace);
    } finally {
      releaseClient(client);
      if (!controller.isClosed) unawaited(controller.close());
    }
  }

  void _report(
    StreamController<ChatEvent> controller,
    ApiError error,
    StackTrace stackTrace,
  ) {
    // 取消后的断流/客户端错误不进 UI，也不产生未捕获异步错误。
    if (isCancelled || controller.isClosed) return;
    controller.addError(error, stackTrace);
  }

  /// SSE：`choices[0].delta.content` / `reasoning_content` / `usage` / `[DONE]`。
  Stream<ChatEvent> _sseEvents(Stream<List<int>> stream) async* {
    String? finishReason;
    var sawAny = false;
    await for (final event in parseSse(
      stream,
      isTerminator: isOpenAiTerminator,
      interruptedMessage: sseInterruptedMessage,
    )) {
      if (isCancelled) return;
      if (event.isDone) {
        if (finishReason == 'tool_calls') {
          // 平台把联网工具当成了客户端函数：模型只回 tool_calls、不产出正文，
          // 客户端不执行它，界面就会一直停在「搜索中」。这里明确报错。
          yield Failure(
            ApiError(
              '联网搜索没有被服务端执行（收到客户端 tool_calls）。'
              '请关闭「联网搜索」重试，或换用支持服务端搜索的平台与协议。',
              kind: ApiErrorKind.http,
            ),
          );
        }
        yield Done(finishReason: finishReason);
        return;
      }
      final json = event.json;
      if (json == null) continue;
      sawAny = true;

      final errorNode = json['error'];
      if (errorNode != null) {
        final detail = extractApiErrorDetail(jsonEncode(<String, Object?>{
              'error': errorNode,
            })) ??
            errorNode.toString();
        yield Failure(ApiError(detail, kind: ApiErrorKind.http));
        yield Done(finishReason: 'error');
        return;
      }

      final choices = json['choices'];
      if (choices is List && choices.isNotEmpty) {
        final choice = choices.first;
        if (choice is Map) {
          final choiceMap = Map<String, Object?>.from(choice);
          // DeepSeek 服务端联网工具进度（与 delta 同级的 extension 字段）。
          final serverEvent = choiceMap['server_tool_event'];
          if (serverEvent is Map) {
            for (final toolEvent in _toolEventsFromServerEvent(
              Map<String, Object?>.from(serverEvent),
            )) {
              yield toolEvent;
            }
          }
          final deltaNode = choiceMap['delta'] ?? choiceMap['message'];
          if (deltaNode is Map) {
            final delta = Map<String, Object?>.from(deltaNode);
            final reasoning =
                delta['reasoning_content'] ?? delta['reasoning'];
            if (reasoning is String && reasoning.isNotEmpty) {
              yield ThinkingDelta(reasoning);
            }
            final content = delta['content'];
            if (content is String && content.isNotEmpty) {
              yield TextDelta(content);
            } else if (content is List) {
              for (final part in content) {
                final text = _contentPartText(part);
                if (text.isNotEmpty) yield TextDelta(text);
              }
            }
            // 最后一个 chunk 一次性下发完整 server_tool_calls / annotations。
            for (final toolEvent in _toolEventsFromDelta(delta)) {
              yield toolEvent;
            }
          }
          final reason = choiceMap['finish_reason'];
          if (reason != null) finishReason = reason.toString();
        }
      }

      final usage = parseUsage(json);
      if (usage != null) {
        yield Usage(usage);
        sawAny = true;
      }
    }
    // 正常 [DONE] 已在循环里返回；这里兜底（服务端没发结束标记时
    // parseSse 会先抛断流异常，所以通常到不了）。
    if (!sawAny) {
      throw ApiError(kUnparsableNonStreamMessage, kind: ApiErrorKind.parse);
    }
    yield Done(finishReason: finishReason);
  }

  /// 非流式回退（服务端忽略 `stream: true` 时）。
  Iterable<ChatEvent> _nonStreamEvents(String body) sync* {
    final json = HttpChatBackend.decodeJsonObject(body);
    final errorNode = json['error'];
    if (errorNode != null) {
      throw ApiError(
        extractApiErrorDetail(body) ?? errorNode.toString(),
        kind: ApiErrorKind.http,
      );
    }
    final choices = json['choices'];
    if (choices is! List || choices.isEmpty) {
      throw ApiError(kUnparsableNonStreamMessage, kind: ApiErrorKind.parse);
    }
    final choice = choices.first;
    if (choice is! Map) {
      throw ApiError(kUnparsableNonStreamMessage, kind: ApiErrorKind.parse);
    }
    final choiceMap = Map<String, Object?>.from(choice);
    final messageNode = choiceMap['message'] ?? choiceMap['delta'];
    if (messageNode is! Map) {
      throw ApiError(kUnparsableNonStreamMessage, kind: ApiErrorKind.parse);
    }
    final message = Map<String, Object?>.from(messageNode);
    final reasoning = message['reasoning_content'] ?? message['reasoning'];
    if (reasoning is String && reasoning.isNotEmpty) {
      yield ThinkingDelta(reasoning);
    }
    final content = message['content'];
    if (content is String && content.isNotEmpty) {
      yield TextDelta(content);
    } else if (content is List) {
      for (final part in content) {
        final text = _contentPartText(part);
        if (text.isNotEmpty) yield TextDelta(text);
      }
    }
    final usage = parseUsage(json);
    if (usage != null) yield Usage(usage);
    // 非流式响应里，服务端工具的结果在 message.server_tool_calls。
    for (final toolEvent in _toolEventsFromDelta(message)) {
      yield toolEvent;
    }
    final reason = choiceMap['finish_reason'];
    if (reason?.toString() == 'tool_calls') {
      yield Failure(
        ApiError(
          '联网搜索没有被服务端执行（收到客户端 tool_calls）。'
          '请关闭「联网搜索」重试，或换用支持服务端搜索的平台与协议。',
          kind: ApiErrorKind.http,
        ),
      );
    }
    yield Done(finishReason: reason?.toString());
  }

  Uri _parseChatUri() {
    final uri = Uri.tryParse(chatUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw ApiError('接口地址无效（${provider.baseUrl}）',
          kind: ApiErrorKind.parse);
    }
    return uri;
  }

  static String _wireRole(String role) {
    switch (role) {
      case 'assistant':
        return 'assistant';
      case 'system':
        return 'system';
      default:
        return 'user';
    }
  }

  static String _contentPartText(Object? part) {
    if (part is String) return part;
    if (part is Map) {
      final map = Map<String, Object?>.from(part);
      final text = map['text'];
      if (text is String) return text;
      final content = map['content'];
      if (content is String) return content;
    }
    return '';
  }

  /// 联网搜索工具：DeepSeek 的 Chat Completions 扩展要求声明成**服务端工具**
  /// `{"type": "deepseek_web_search"}`（官方文档「联网工具 › Chat Completions API」）。
  /// 按 OpenAI `type: function` 声明会被当成**客户端**工具：模型只回 `tool_calls`、
  /// 不产出正文，客户端又不执行它，表现就是「搜索时卡住」。
  static List<Map<String, Object?>> _openAiTools() => <Map<String, Object?>>[
        <String, Object?>{'type': kToolWebSearch},
        <String, Object?>{'type': kToolReadUrl},
      ];

  // -------------------------------------------------------------------
  // DeepSeek 服务端联网工具（Chat Completions 扩展字段）
  // -------------------------------------------------------------------

  /// `choice.server_tool_event`：`call_started` / `call_completed` 进度。
  static Iterable<ToolResult> _toolEventsFromServerEvent(
    Map<String, Object?> event,
  ) sync* {
    final type = (event['type'] ?? '').toString();
    if (type != 'call_started' && type != 'call_completed') return;
    final call = event['call'];
    if (call is! Map) return;
    final callMap = Map<String, Object?>.from(call);
    final tool = (callMap['type'] ?? kToolWebSearch).toString();
    if (type == 'call_started') {
      yield ToolResult(tool: tool, running: true, query: _firstQueryOf(callMap));
      return;
    }
    yield ToolResult(
      tool: tool,
      running: false,
      sources: _sourcesOfToolCall(callMap),
      text: _pageTitleOf(callMap),
    );
  }

  /// 最后一个 chunk 的 `delta.server_tool_calls` / `delta.annotations`：
  /// 完整的调用结果与引用一次性下发。
  static Iterable<ToolResult> _toolEventsFromDelta(
    Map<String, Object?> delta,
  ) sync* {
    final steps = delta['server_tool_calls'];
    if (steps is List) {
      for (final step in steps) {
        if (step is! Map) continue;
        final calls = step['calls'];
        if (calls is! List) continue;
        for (final call in calls) {
          if (call is! Map) continue;
          final callMap = Map<String, Object?>.from(call);
          final sources = _sourcesOfToolCall(callMap);
          if (sources.isEmpty) continue;
          yield ToolResult(
            tool: (callMap['type'] ?? kToolWebSearch).toString(),
            running: false,
            sources: sources,
          );
        }
      }
    }
    final annotations = delta['annotations'];
    if (annotations is List) {
      final sources = <SearchSource>[];
      final citations = <CitationMark>[];
      for (final node in annotations) {
        if (node is! Map) continue;
        final citation = node['url_citation'];
        if (citation is! Map) continue;
        final map = Map<String, Object?>.from(citation);
        final url = (map['url'] ?? '').toString();
        if (url.isEmpty) continue;
        final title = map['title']?.toString();
        sources.add(SearchSource(url: url, title: title));
        final end = _intOf(map['end_index']);
        if (end > 0) {
          citations.add(
            CitationMark(
              url: url,
              title: title,
              start: _intOf(map['start_index']),
              end: end,
            ),
          );
        }
      }
      if (sources.isNotEmpty) {
        yield ToolResult(
          tool: kToolWebSearch,
          running: false,
          sources: sources,
          citations: citations,
        );
      }
    }
  }

  static int _intOf(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  /// 一次调用的结果：`sources`（搜索）或 `page`（读链接/打开网页）。
  static List<SearchSource> _sourcesOfToolCall(Map<String, Object?> call) {
    final result = <SearchSource>[];
    final raw = call['sources'];
    if (raw is List) {
      for (final node in raw) {
        if (node is! Map) continue;
        final source = SearchSource.fromJson(Map<String, Object?>.from(node));
        if (source.url.trim().isNotEmpty) result.add(source);
      }
    }
    final page = call['page'];
    if (page is Map) {
      final map = Map<String, Object?>.from(page);
      final url = (map['url'] ?? '').toString();
      if (url.isNotEmpty) {
        result.add(
          SearchSource(
            url: url,
            title: map['title']?.toString(),
            publishedAt: map['published_at']?.toString(),
          ),
        );
      }
    }
    return result;
  }

  static String? _firstQueryOf(Map<String, Object?> call) {
    final action = call['action'];
    if (action is! Map) return null;
    final queries = action['queries'];
    if (queries is List && queries.isNotEmpty) return queries.first.toString();
    return null;
  }

  static String _pageTitleOf(Map<String, Object?> call) {
    final page = call['page'];
    if (page is Map) return (page['title'] ?? '').toString();
    return '';
  }

  /// 附件：把 `file_id` 以 **content block** 挂到最后一条 user 消息上。
  ///
  /// 官方「Files API › Use an Uploaded File in a Chat Request」：
  /// ```json
  /// {"role": "user", "content": [
  ///   {"type": "text", "text": "..."},
  ///   {"type": "file", "file_id": "file-api-..."}
  /// ]}
  /// ```
  /// 见 https://api-docs.deepseek.com/guides/files_api#use-an-uploaded-file-in-a-chat-request
  /// 旧实现的顶层 `attachments[]` / `file_id` 不是 Chat Completions 的字段，
  /// 已删除（文件根本不会进上下文）。
  static void _attachFilesToLastUser(
    List<Map<String, Object?>> messages,
    List<Attachment> attachments,
    int? lastUserIndex,
  ) {
    final fileBlocks = <Map<String, Object?>>[];
    for (final attachment in attachments) {
      final id = attachment.fileId?.trim() ?? '';
      if (id.isEmpty) continue;
      fileBlocks.add(<String, Object?>{'type': 'file', 'file_id': id});
    }
    if (fileBlocks.isEmpty) return;

    final index = lastUserIndex;
    if (index == null || index >= messages.length) {
      messages.add(<String, Object?>{'role': 'user', 'content': fileBlocks});
      return;
    }
    final text = (messages[index]['content'] ?? '').toString();
    messages[index]['content'] = <Map<String, Object?>>[
      if (text.trim().isNotEmpty)
        <String, Object?>{'type': 'text', 'text': text},
      ...fileBlocks,
    ];
  }
}
