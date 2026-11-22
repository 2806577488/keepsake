/// Keepsake（留声）— Anthropic 兼容聊天客户端。
///
/// 协议证据（`reports/apk/http-api.md` §4/§6）：`POST {base}/messages`、
/// 头 `x-api-key` / `anthropic-version` / `anthropic-beta` / `Authorization`；
/// SSE 事件 `message_start` / `content_block_start` / `content_block_delta` /
/// `content_block_stop` / `message_delta` / `message_stop`；
/// 增量 `text_delta` / `thinking_delta` / `input_json_delta` / `signature_delta` /
/// `citations_delta`；usage `input_tokens`/`output_tokens`/`cache_*`；
/// DeepSeek 联网搜索工具 `deepseek_web_search` / `deepseek_read_url`，
/// 结果类型 `web_search_tool_result` / `web_fetch_tool_result`；
/// 文案「正在联网搜索」「正在读取链接」「链接内容」。
///
/// 符号证据：`AnthropicClient`、`anthropicBaseOf`、`openAiMessagesFromAnthropic`。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../chat/attachments.dart' show Attachment;
import '../usage/usage.dart';
import 'chat_backend.dart';
import 'model_list.dart'
    show
        fetchProviderModels,
        modelsUrlOf,
        kAnthropicVersion,
        kAnthropicVersionHeader;
import 'provider_models.dart';
import 'sse.dart';

/// Anthropic API 默认 `max_tokens`（必填字段；[推断] 4k 起步）。
const int kDefaultAnthropicMaxTokens = 4096;

/// 用 `source.type=file` 引用已上传文件时必须带的 beta 头。
///
/// 官方：Anthropic 兼容端点引用 `file_id` 时 HTTP 头必须带
/// `anthropic-beta: files-api-2025-04-14`，否则 400。
/// 见 https://api-docs.deepseek.com/guides/files_api#anthropic-compatible-files-api
const String kAnthropicFilesBetaHeader = 'anthropic-beta';
const String kAnthropicFilesBetaValue = 'files-api-2025-04-14';

/// Anthropic 兼容客户端（DeepSeek 官方走 `/anthropic/v1` 派生基址）。
class AnthropicClient extends HttpChatBackend {
  AnthropicClient({
    required super.provider,
    super.clientFactory,
    super.timeout,
  });

  /// Anthropic 兼容基址。
  ///
  /// - DeepSeek 官方（`api.deepseek.com`）→ `anthropicBaseOf(base)`
  ///   （`https://api.deepseek.com/anthropic/v1`，[确定]）；
  /// - 自定义 Anthropic 兼容平台 → 用户填的地址本身就是基址（例如
  ///   `https://api.anthropic.com/v1`），不再追加 `/anthropic/v1`。
  String get anthropicBase {
    final base = normalizeProviderBase(provider.baseUrl);
    if (base.isEmpty) return '';
    if (base.toLowerCase().contains('api.deepseek.com')) {
      return anthropicBaseOf(base);
    }
    final lower = base.toLowerCase();
    if (lower.endsWith('/messages')) {
      return base.substring(0, base.length - '/messages'.length);
    }
    return base;
  }

  /// `POST {anthropicBase}/messages`。
  @override
  String get chatUrl {
    final base = anthropicBase;
    if (base.toLowerCase().endsWith('/messages')) return base;
    return '$base/messages';
  }

  /// `GET {providerBase}/models`。
  @override
  String get modelsUrl {
    final base = normalizeProviderBase(provider.baseUrl);
    final lower = base.toLowerCase();
    if (lower.endsWith('/messages')) {
      return modelsUrlOf(base.substring(0, base.length - '/messages'.length));
    }
    return modelsUrlOf(base);
  }

  @override
  Future<List<ProviderModel>> listModels() async {
    final client = openClient();
    try {
      return await fetchProviderModels(
        baseUrl: normalizeProviderBase(provider.baseUrl),
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

  /// 组装 `POST /messages` 的 JSON body。
  ///
  /// 支持的 key：`model`、`messages`、`system`、`max_tokens`、`stream`、
  /// `thinking{type}`、`output_config{effort}`、`tools`、`stop_sequences`、
  /// `metadata`。
  Map<String, Object?> buildRequestBody(ChatRequest request) {
    final model = request.modelName;
    if (model.isEmpty) {
      throw ApiError('先填一个模型名', kind: ApiErrorKind.parse);
    }

    final systemParts = <String>[];
    final system = request.effectiveSystemPrompt;
    if (system.isNotEmpty) systemParts.add(system);

    final messages = <Map<String, Object?>>[];
    final pendingAttachments = <Attachment>[
      for (final attachment in request.attachments)
        if ((attachment.fileId ?? '').trim().isNotEmpty) attachment,
    ];

    // 附件只挂到最后一条 user 消息上（挂到 assistant 会被 400）。
    var lastUserIndex = -1;
    for (var i = 0; i < request.messages.length; i++) {
      if (request.messages[i].isUser) lastUserIndex = i;
    }

    for (var i = 0; i < request.messages.length; i++) {
      final turn = request.messages[i];
      if (turn.isSystem) {
        final content = turn.content.trim();
        if (content.isNotEmpty) systemParts.add(content);
        continue;
      }
      if (turn.content.trim().isEmpty) continue;
      final attachHere = i == lastUserIndex && pendingAttachments.isNotEmpty;
      messages.add(<String, Object?>{
        'role': turn.isAssistant ? 'assistant' : 'user',
        'content': attachHere
            ? _userContentWithAttachments(turn.content, pendingAttachments)
            : turn.content,
      });
    }

    // Anthropic 要求 user/assistant 交替且首条为 user；合并连续同角色。
    final normalized = _normalizeMessages(messages);

    final body = <String, Object?>{
      'model': model,
      'messages': normalized,
      'max_tokens': (request.maxTokens != null && request.maxTokens! > 0)
          ? request.maxTokens
          : kDefaultAnthropicMaxTokens,
      'stream': true,
    };
    if (systemParts.isNotEmpty) {
      body['system'] = systemParts.join('\n\n');
    }
    // 思考开关与强度（官方 Messages API）：
    // - `thinking: {"type": "enabled"|"disabled"}`：省略时默认开启，关闭必须显式
    //   发 disabled；`adaptive` 视为 enabled；
    // - `output_config.effort`：low/high/max 承载档位；
    //   官方明确 `thinking.budget_tokens` 被 Ignored，所以不再下发。
    // 见 https://api-docs.deepseek.com/api/create-message 与
    // https://api-docs.deepseek.com/guides/thinking_mode
    body['thinking'] = <String, Object?>{
      'type': request.thinking ? 'enabled' : 'disabled',
    };
    if (request.thinking) {
      final effort = thinkingEffortOf(request.thinkingLevel);
      if (effort != null) {
        body['output_config'] = <String, Object?>{'effort': effort};
      }
    }
    if (request.search) {
      body['tools'] = deepSeekSearchTools();
    }
    final stop = request.stop;
    if (stop != null && stop.isNotEmpty) {
      body['stop_sequences'] = stop;
    }
    final metadata = request.metadata;
    if (metadata != null && metadata.isNotEmpty) {
      body['metadata'] = metadata;
    }
    return body;
  }

  /// 请求头。
  ///
  /// [withFiles] 为 true 时补 `anthropic-beta: files-api-2025-04-14`：
  /// `source.type=file` 引用已上传文件（图片或文档）时官方**要求**该头，
  /// 缺了会 400。
  /// 见 https://api-docs.deepseek.com/guides/files_api#anthropic-compatible-files-api
  Map<String, String> _requestHeaders({bool withFiles = false}) {
    final headers = <String, String>{
      'content-type': 'application/json',
      'accept': sseContentType,
      kAnthropicVersionHeader: kAnthropicVersion,
    };
    final key = apiKey.trim();
    if (key.isNotEmpty) {
      headers['x-api-key'] = key;
      headers['authorization'] = 'Bearer $key';
    }
    if (withFiles) {
      headers[kAnthropicFilesBetaHeader] = kAnthropicFilesBetaValue;
    }
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
      // 只在本请求真的引用 file_id 时补 anthropic-beta 头。
      final hasFileRefs = request.attachments
          .any((attachment) => (attachment.fileId ?? '').trim().isNotEmpty);
      final httpRequest = http.Request('POST', _parseChatUri())
        ..headers.addAll(_requestHeaders(withFiles: hasFileRefs))
        ..body = jsonEncode(buildRequestBody(request));

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

  /// Anthropic SSE 事件 → [ChatEvent]。
  Stream<ChatEvent> _sseEvents(Stream<List<int>> stream) async* {
    final blockTypes = <int, String>{};
    final toolNames = <int, String>{};
    final toolInput = <int, StringBuffer>{};
    String? finishReason;

    await for (final event in parseSse(
      stream,
      isTerminator: isAnthropicTerminator,
      interruptedMessage: sseInterruptedEventMessage,
    )) {
      if (isCancelled) return;
      final json = event.json;
      final type = event.event ?? json?['type']?.toString();
      if (type == null) {
        // 官方「Streaming」：等待生成超时时，服务端会发一个既没有 SSE event 名、
        // 也没有顶层 `type` 的 data 帧 `{"error":{"message":"..."}}`，然后关连接。
        // 旧实现直接 continue，把这类错误静默吞掉了。
        // 见 https://api-docs.deepseek.com/guides/anthropic_api#streaming
        final errorNode = json?['error'];
        if (errorNode != null) {
          final detail = extractApiErrorDetail(jsonEncode(<String, Object?>{
                'error': errorNode,
              })) ??
              errorNode.toString();
          yield Failure(ApiError(detail, kind: ApiErrorKind.http));
          yield Done(finishReason: 'error');
          return;
        }
        continue;
      }

      switch (type) {
        case 'message_start':
          final message = json?['message'];
          if (message is Map) {
            final usage = parseUsage(<String, Object?>{'message': message});
            if (usage != null && usage.isNotEmpty) yield Usage(usage);
          }
        case 'content_block_start':
          final index = _intOf(json?['index']);
          final blockNode = json?['content_block'];
          if (blockNode is Map) {
            final block = Map<String, Object?>.from(blockNode);
            final blockType = (block['type'] ?? '').toString();
            blockTypes[index] = blockType;
            switch (blockType) {
              case 'text':
                final text = block['text'];
                if (text is String && text.isNotEmpty) yield TextDelta(text);
              case 'thinking':
              case 'redacted_thinking':
                final thinking = block['thinking'];
                if (thinking is String && thinking.isNotEmpty) {
                  yield ThinkingDelta(thinking);
                }
              case 'server_tool_use':
                final name = (block['name'] ?? kToolWebSearch).toString();
                toolNames[index] = name;
                final input = block['input'];
                final query = _toolQueryOf(name, input);
                yield ToolResult(tool: name, running: true, query: query);
              case 'tool_use':
                toolNames[index] =
                    (block['name'] ?? kToolWebSearch).toString();
              case 'web_search_tool_result':
              case 'web_fetch_tool_result':
                final toolName = _toolNameForResult(type);
                final content = block['content'];
                yield ToolResult(
                  tool: toolName,
                  resultType: blockType,
                  running: false,
                  sources: _sourcesOf(content),
                  text: _toolTextOf(content),
                );
              default:
                break;
            }
          }
        case 'content_block_delta':
          final index = _intOf(json?['index']);
          final deltaNode = json?['delta'];
          if (deltaNode is Map) {
            final delta = Map<String, Object?>.from(deltaNode);
            final deltaType = (delta['type'] ?? '').toString();
            switch (deltaType) {
              case 'text_delta':
                final text = delta['text'];
                if (text is String && text.isNotEmpty) yield TextDelta(text);
              case 'thinking_delta':
                final thinking = delta['thinking'];
                if (thinking is String && thinking.isNotEmpty) {
                  yield ThinkingDelta(thinking);
                }
              case 'input_json_delta':
                final partial = delta['partial_json'];
                if (partial is String && partial.isNotEmpty) {
                  (toolInput[index] ??= StringBuffer()).write(partial);
                }
              case 'signature_delta':
              case 'citations_delta':
                break;
              default:
                final text = delta['text'];
                if (text is String && text.isNotEmpty) yield TextDelta(text);
            }
          }
        case 'content_block_stop':
          final index = _intOf(json?['index']);
          final buffered = toolInput.remove(index);
          if (buffered != null && buffered.isNotEmpty) {
            final name = toolNames[index] ?? kToolWebSearch;
            final input = _tryDecodeJson(buffered.toString());
            yield ToolResult(
              tool: name,
              running: true,
              query: _toolQueryOf(name, input),
            );
          }
        case 'message_delta':
          final usage = parseUsage(json);
          if (usage != null && usage.isNotEmpty) yield Usage(usage);
          final deltaNode = json?['delta'];
          if (deltaNode is Map) {
            final delta = Map<String, Object?>.from(deltaNode);
            final reason = delta['stop_reason'];
            if (reason != null) finishReason = reason.toString();
          }
        case 'message_stop':
          break;
        case 'error':
          final detail = extractApiErrorDetail(jsonEncode(<String, Object?>{
                'error': json?['error'],
              })) ??
              'unknown';
          yield Failure(ApiError(detail, kind: ApiErrorKind.http));
        case 'ping':
          break;
        default:
          break;
      }
    }

    if (finishReason == 'tool_use') {
      // 平台把联网工具当成了客户端工具：模型只发 tool_use、客户端不执行，
      // 界面就会一直停在「搜索中」。这里明确报错，避免静默卡死。
      yield Failure(
        ApiError(
          '联网搜索没有被服务端执行（收到客户端工具调用）。'
          '请关闭「联网搜索」重试，或改用支持服务端搜索的平台与协议。',
          kind: ApiErrorKind.http,
        ),
      );
    }
    yield Done(finishReason: finishReason);
  }

  /// 非流式回退（`{"content":[...],"usage":{...},"stop_reason":...}`）。
  Iterable<ChatEvent> _nonStreamEvents(String body) sync* {
    final json = HttpChatBackend.decodeJsonObject(body);
    final errorNode = json['error'];
    if (errorNode != null) {
      throw ApiError(
        extractApiErrorDetail(jsonEncode(<String, Object?>{'error': errorNode})) ??
            errorNode.toString(),
        kind: ApiErrorKind.http,
      );
    }
    final content = json['content'];
    if (content is List) {
      for (final blockNode in content) {
        if (blockNode is! Map) continue;
        final block = Map<String, Object?>.from(blockNode);
        final blockType = (block['type'] ?? 'text').toString();
        if (blockType == 'text') {
          final text = block['text'];
          if (text is String && text.isNotEmpty) yield TextDelta(text);
        } else if (blockType == 'thinking') {
          final thinking = block['thinking'];
          if (thinking is String && thinking.isNotEmpty) {
            yield ThinkingDelta(thinking);
          }
        } else if (blockType == 'web_search_tool_result' ||
            blockType == 'web_fetch_tool_result') {
          yield ToolResult(
            tool: blockType == 'web_fetch_tool_result'
                ? kToolReadUrl
                : kToolWebSearch,
            resultType: blockType,
            sources: _sourcesOf(block['content']),
            text: _toolTextOf(block['content']),
          );
        }
      }
    }
    final usage = parseUsage(json);
    if (usage != null && usage.isNotEmpty) yield Usage(usage);
    final reason = json['stop_reason'];
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

  static List<Map<String, Object?>> _normalizeMessages(
    List<Map<String, Object?>> messages,
  ) {
    final normalized = <Map<String, Object?>>[];
    for (final message in messages) {
      if (normalized.isNotEmpty &&
          normalized.last['role'] == message['role']) {
        _mergeContent(normalized.last, message['content']);
      } else {
        normalized.add(<String, Object?>{
          'role': message['role'],
          'content': message['content'],
        });
      }
    }
    // Anthropic 首条必须是 user。
    if (normalized.isNotEmpty && normalized.first['role'] == 'assistant') {
      normalized.insert(0, <String, Object?>{'role': 'user', 'content': '继续。'});
    }
    return normalized;
  }

  /// 合并相邻同角色消息的 content（字符串与 blocks 列表都支持）。
  static void _mergeContent(Map<String, Object?> target, Object? content) {
    final existing = target['content'];
    if (existing is List || content is List) {
      final blocks = <Object?>[];
      if (existing is List) {
        blocks.addAll(existing);
      } else if ((existing ?? '').toString().trim().isNotEmpty) {
        blocks.add(<String, Object?>{'type': 'text', 'text': existing.toString()});
      }
      if (content is List) {
        blocks.addAll(content);
      } else if ((content ?? '').toString().trim().isNotEmpty) {
        blocks.add(<String, Object?>{'type': 'text', 'text': content.toString()});
      }
      target['content'] = blocks;
      return;
    }
    target['content'] = '${existing ?? ''}\n\n${content ?? ''}';
  }

  /// 附件 → Anthropic content blocks（图片 `image`、其它 `document`）。
  Object _userContentWithAttachments(
    String text,
    List<Attachment> attachments,
  ) {
    final blocks = <Map<String, Object?>>[];
    if (text.trim().isNotEmpty) {
      blocks.add(<String, Object?>{'type': 'text', 'text': text});
    }
    for (final attachment in attachments) {
      final fileId = attachment.fileId?.trim() ?? '';
      if (fileId.isEmpty) continue;
      final type = attachment.isImage ? 'image' : 'document';
      blocks.add(<String, Object?>{
        'type': type,
        'source': <String, Object?>{
          'type': 'file',
          'file_id': fileId,
        },
      });
    }
    if (blocks.isEmpty) return text;
    return blocks;
  }

  static String _toolNameForResult(String resultType) =>
      resultType == 'web_fetch_tool_result' ? kToolReadUrl : kToolWebSearch;

  static String? _toolQueryOf(String name, Object? input) {
    if (input is! Map) return null;
    final map = Map<String, Object?>.from(input);
    final value = name == kToolReadUrl
        ? map['url']
        : (map['query'] ?? map['q'] ?? map['keyword']);
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static Object? _tryDecodeJson(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return null;
    }
  }

  /// 从工具结果 content 里挖出搜索来源。
  static List<SearchSource> _sourcesOf(Object? node) {
    final sources = <SearchSource>[];
    void visit(Object? current) {
      if (current is Map) {
        final map = Map<String, Object?>.from(current);
        final type = (map['type'] ?? '').toString();
        final hasUrl = (map['url'] ?? '').toString().trim().isNotEmpty;
        if (hasUrl &&
            (type == 'web_search_result' ||
                type == 'web_fetch_result' ||
                type.isEmpty)) {
          sources.add(SearchSource.fromJson(map));
          return;
        }
        final content = map['content'] ?? map['results'];
        if (content != null) visit(content);
        return;
      }
      if (current is List) {
        for (final item in current) {
          visit(item);
        }
      }
    }

    visit(node);
    return sources;
  }

  /// 读链接时的正文（`web_fetch_tool_result.content`）。
  static String _toolTextOf(Object? node) {
    if (node is String) return node;
    if (node is List) {
      for (final item in node) {
        final text = _toolTextOf(item);
        if (text.isNotEmpty) return text;
      }
      return '';
    }
    if (node is Map) {
      final map = Map<String, Object?>.from(node);
      for (final key in const <String>['content', 'text', 'snippet']) {
        final value = map[key];
        if (value is String && value.trim().isNotEmpty) return value;
        if (value is List || value is Map) {
          final nested = _toolTextOf(value);
          if (nested.isNotEmpty) return nested;
        }
      }
    }
    return '';
  }
}

/// 把 Anthropic 形状的 `messages` 转成 OpenAI 形状。
///
/// 用途：切换平台/导入 Anthropic 来源的历史时，把 content blocks 拍平成文本。
/// [system] 作为首条 system 消息插入。
List<Map<String, Object?>> openAiMessagesFromAnthropic(
  List<Map<String, Object?>> messages, {
  String? system,
}) {
  final result = <Map<String, Object?>>[];
  final systemText = (system ?? '').trim();
  if (systemText.isNotEmpty) {
    result.add(<String, Object?>{'role': 'system', 'content': systemText});
  }
  for (final raw in messages) {
    final role = (raw['role'] ?? 'user').toString();
    final text = anthropicContentText(raw['content']).trim();
    if (text.isEmpty) continue;
    if (role == 'system') {
      result.add(<String, Object?>{'role': 'system', 'content': text});
      continue;
    }
    result.add(<String, Object?>{
      'role': role == 'assistant' ? 'assistant' : 'user',
      'content': text,
    });
  }
  return result;
}

/// Anthropic content（字符串或 blocks 数组）→ 纯文本。
String anthropicContentText(Object? content) {
  if (content == null) return '';
  if (content is String) return content;
  if (content is List) {
    final parts = <String>[];
    for (final block in content) {
      if (block is String) {
        parts.add(block);
        continue;
      }
      if (block is! Map) continue;
      final map = Map<String, Object?>.from(block);
      final type = (map['type'] ?? '').toString();
      switch (type) {
        case 'text':
          final text = map['text'];
          if (text is String) parts.add(text);
        case 'thinking':
          final thinking = map['thinking'];
          if (thinking is String) parts.add(thinking);
        case 'tool_result':
          final nested = anthropicContentText(map['content']);
          if (nested.isNotEmpty) parts.add(nested);
        default:
          final text = map['text'];
          if (text is String) parts.add(text);
      }
    }
    return parts.join('\n');
  }
  return content.toString();
}

int _intOf(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}
