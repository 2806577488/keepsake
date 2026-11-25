import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:keepsake/core/api/anthropic_client.dart';
import 'package:keepsake/core/api/chat_backend.dart';
import 'package:keepsake/core/api/provider_models.dart';
import 'package:keepsake/core/search/web_search.dart';

final AiProvider _anthropicProvider = AiProvider(
  id: 'p2',
  presetId: presetDeepSeekId,
  name: 'DeepSeek（Anthropic 兼容）',
  baseUrl: 'https://api.deepseek.com',
  apiKey: 'sk-test',
  model: 'deepseek-chat',
  kind: ProviderKind.anthropic,
  supportsSearch: true,
);

/// 一个 Anthropic SSE 事件（`event:` 名 + 带 `type` 的 data）。
String _event(String name, Map<String, Object?> data) =>
    'event: $name\n'
    'data: ${jsonEncode(<String, Object?>{'type': name, ...data})}\n\n';

/// 第一轮：模型发起 `web_search` 客户端工具调用（参数分两段下发）。
String _toolUseSse() =>
    _event('message_start', <String, Object?>{
      'message': <String, Object?>{
        'id': 'msg_1',
        'type': 'message',
        'role': 'assistant',
        'content': <Object?>[],
        'usage': <String, Object?>{'input_tokens': 12, 'output_tokens': 1},
      },
    }) +
    _event('content_block_start', <String, Object?>{
      'index': 0,
      'content_block': <String, Object?>{
        'type': 'tool_use',
        'id': 'toolu_1',
        'name': 'web_search',
        'input': <String, Object?>{},
      },
    }) +
    _event('content_block_delta', <String, Object?>{
      'index': 0,
      'delta': <String, Object?>{
        'type': 'input_json_delta',
        'partial_json': '{"query": "杭州 ',
      },
    }) +
    _event('content_block_delta', <String, Object?>{
      'index': 0,
      'delta': <String, Object?>{
        'type': 'input_json_delta',
        'partial_json': '天气"}',
      },
    }) +
    _event('content_block_stop', <String, Object?>{'index': 0}) +
    _event('message_delta', <String, Object?>{
      'delta': <String, Object?>{'stop_reason': 'tool_use', 'stop_sequence': null},
      'usage': <String, Object?>{'output_tokens': 20},
    }) +
    _event('message_stop', <String, Object?>{});

/// 第二轮：模型基于回填的搜索结果出正文。
String _finalSse() =>
    _event('message_start', <String, Object?>{
      'message': <String, Object?>{
        'id': 'msg_2',
        'type': 'message',
        'role': 'assistant',
        'content': <Object?>[],
        'usage': <String, Object?>{'input_tokens': 40, 'output_tokens': 1},
      },
    }) +
    _event('content_block_start', <String, Object?>{
      'index': 0,
      'content_block': <String, Object?>{'type': 'text', 'text': ''},
    }) +
    _event('content_block_delta', <String, Object?>{
      'index': 0,
      'delta': <String, Object?>{'type': 'text_delta', 'text': '晴，'},
    }) +
    _event('content_block_delta', <String, Object?>{
      'index': 0,
      'delta': <String, Object?>{'type': 'text_delta', 'text': '26 度'},
    }) +
    _event('content_block_stop', <String, Object?>{'index': 0}) +
    _event('message_delta', <String, Object?>{
      'delta': <String, Object?>{'stop_reason': 'end_turn'},
      'usage': <String, Object?>{'output_tokens': 5},
    }) +
    _event('message_stop', <String, Object?>{});

class _FakeSearch implements WebSearchService {
  final List<String> queries = <String>[];
  final List<int> counts = <int>[];

  @override
  bool get isConfigured => true;

  @override
  bool get supportsFetch => true;

  @override
  Future<List<WebSearchItem>> search(String query, {int count = 8}) async {
    queries.add(query);
    counts.add(count);
    return const <WebSearchItem>[
      WebSearchItem(
        url: 'https://news.example/a',
        title: '新闻A',
        snippet: '摘要',
        summary: '长摘要',
      ),
    ];
  }

  @override
  Future<WebFetchPage> fetchPage(String url) async =>
      WebFetchPage(url: url, title: '页面', content: '正文');

  @override
  void dispose() {}
}

class _FailingSearch implements WebSearchService {
  @override
  bool get isConfigured => true;

  @override
  bool get supportsFetch => false;

  @override
  Future<List<WebSearchItem>> search(String query, {int count = 8}) async =>
      throw const ApiError('搜索服务挂了', kind: ApiErrorKind.network);

  @override
  Future<WebFetchPage> fetchPage(String url) async =>
      throw const ApiError('抓取服务挂了', kind: ApiErrorKind.network);

  @override
  void dispose() {}
}

void main() {
  test('Anthropic 联网走客户端工具 + 外部搜索，多轮回填', () async {
    final bodies = <String>[];
    final search = _FakeSearch();
    final client = MockClient.streaming((request, bodyStream) async {
      bodies.add(utf8.decode(await bodyStream.toBytes()));
      final sse = bodies.length == 1 ? _toolUseSse() : _finalSse();
      return http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode(sse)),
        200,
        headers: <String, String>{'content-type': 'text/event-stream'},
      );
    });
    final backend = AnthropicClient(
      provider: _anthropicProvider,
      clientFactory: () => client,
      webSearchService: search,
    );

    final events = <ChatEvent>[];
    await for (final event in backend.streamChat(ChatRequest(
      provider: _anthropicProvider,
      messages: <ChatTurn>[ChatTurn.user('杭州今天天气怎么样？')],
      search: true,
      webSearch: const WebSearchConfig(
        mode: WebSearchMode.external,
        count: 5,
      ),
    ))) {
      events.add(event);
    }

    // 1) 第一轮请求：声明的是普通 Anthropic 工具，没有服务端 deepseek_* 工具。
    expect(bodies, hasLength(2));
    final first = jsonDecode(bodies[0]) as Map<String, Object?>;
    final tools = (first['tools'] as List<Object?>).cast<Map<String, Object?>>();
    expect(tools, hasLength(2));
    expect(
      tools.map((tool) => tool['name']),
      containsAll(<String>['web_search', 'read_url']),
    );
    expect(tools.every((tool) => tool['input_schema'] is Map), isTrue);
    expect(bodies[0], isNot(contains('deepseek_web_search')));
    expect(bodies[0], isNot(contains('deepseek_read_url')));

    // 2) 第二轮请求：assistant `tool_use` + user `tool_result` 都回填了。
    final second = jsonDecode(bodies[1]) as Map<String, Object?>;
    final messages =
        (second['messages'] as List<Object?>).cast<Map<String, Object?>>();
    final assistant = messages.firstWhere(
      (message) => message['role'] == 'assistant',
    );
    final assistantBlocks = (assistant['content'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final toolUse = assistantBlocks.firstWhere(
      (block) => block['type'] == 'tool_use',
    );
    expect(toolUse['id'], 'toolu_1');
    expect(toolUse['name'], 'web_search');
    expect((toolUse['input'] as Map<String, Object?>)['query'], '杭州 天气');

    final toolResultMessage = messages.lastWhere(
      (message) => message['role'] == 'user',
    );
    final resultBlocks = (toolResultMessage['content'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final toolResult = resultBlocks.single;
    expect(toolResult['type'], 'tool_result');
    expect(toolResult['tool_use_id'], 'toolu_1');
    expect('${toolResult['content']}', contains('新闻A'));

    // 搜索用配置里的 count、解析出的 query。
    expect(search.queries, <String>['杭州 天气']);
    expect(search.counts, <int>[5]);

    // 3) UI 事件：搜索中 → 来源；最终正文、用量与结束。
    expect(events.whereType<Failure>(), isEmpty);
    final results = events.whereType<ToolResult>().toList();
    expect(results.where((event) => event.running).length, 1);
    expect(results.where((event) => !event.running).length, 1);
    final finished = results.last;
    expect(finished.tool, kToolWebSearch);
    expect(finished.query, '杭州 天气');
    expect(finished.sources.single.url, 'https://news.example/a');
    expect(
      events.whereType<TextDelta>().map((event) => event.text).join(),
      '晴，26 度',
    );
    expect(events.whereType<Usage>(), isNotEmpty);
    final done = events.whereType<Done>().toList();
    expect(done, hasLength(1));
    expect(done.single.finishReason, 'end_turn');
  });

  test('非 external 模式仍声明服务端联网工具（老路径不变）', () {
    final backend = AnthropicClient(provider: _anthropicProvider);
    final body = backend.buildRequestBody(ChatRequest(
      provider: _anthropicProvider,
      messages: <ChatTurn>[ChatTurn.user('hi')],
      search: true,
      webSearch: const WebSearchConfig(),
    ));
    final tools = (body['tools'] as List<Object?>).cast<Map<String, Object?>>();
    expect(tools, hasLength(2));
    expect(
      tools.map((tool) => tool['type']),
      containsAll(<String>[kToolWebSearch, kToolReadUrl]),
    );
  });

  test('工具失败不中断：错误文本回填后模型仍能出正文', () async {
    final bodies = <String>[];
    final client = MockClient.streaming((request, bodyStream) async {
      bodies.add(utf8.decode(await bodyStream.toBytes()));
      final sse = bodies.length == 1 ? _toolUseSse() : _finalSse();
      return http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode(sse)),
        200,
        headers: <String, String>{'content-type': 'text/event-stream'},
      );
    });
    final backend = AnthropicClient(
      provider: _anthropicProvider,
      clientFactory: () => client,
      webSearchService: _FailingSearch(),
    );

    final events = <ChatEvent>[];
    await for (final event in backend.streamChat(ChatRequest(
      provider: _anthropicProvider,
      messages: <ChatTurn>[ChatTurn.user('杭州今天天气怎么样？')],
      search: true,
      webSearch: const WebSearchConfig(mode: WebSearchMode.external),
    ))) {
      events.add(event);
    }

    expect(bodies, hasLength(2));
    final second = jsonDecode(bodies[1]) as Map<String, Object?>;
    final messages =
        (second['messages'] as List<Object?>).cast<Map<String, Object?>>();
    final toolResultMessage = messages.lastWhere(
      (message) => message['role'] == 'user',
    );
    final blocks = (toolResultMessage['content'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect('${blocks.single['content']}', contains('联网搜索失败'));
    expect(events.whereType<Failure>(), isEmpty);
    expect(
      events.whereType<TextDelta>().map((event) => event.text).join(),
      '晴，26 度',
    );
    expect(events.whereType<Done>(), hasLength(1));
  });

  test('最多 4 轮：最后一轮不再声明 tools（强制出正文）', () async {
    final bodies = <String>[];
    final client = MockClient.streaming((request, bodyStream) async {
      bodies.add(utf8.decode(await bodyStream.toBytes()));
      final sse = bodies.length <= 3 ? _toolUseSse() : _finalSse();
      return http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode(sse)),
        200,
        headers: <String, String>{'content-type': 'text/event-stream'},
      );
    });
    final search = _FakeSearch();
    final backend = AnthropicClient(
      provider: _anthropicProvider,
      clientFactory: () => client,
      webSearchService: search,
    );

    final events = <ChatEvent>[];
    await for (final event in backend.streamChat(ChatRequest(
      provider: _anthropicProvider,
      messages: <ChatTurn>[ChatTurn.user('杭州今天天气怎么样？')],
      search: true,
      webSearch: const WebSearchConfig(mode: WebSearchMode.external),
    ))) {
      events.add(event);
    }

    // 4 轮：前 3 轮带工具并执行，第 4 轮不带工具、直接出正文。
    expect(bodies, hasLength(4));
    expect(
      (jsonDecode(bodies[0]) as Map<String, Object?>).containsKey('tools'),
      isTrue,
    );
    expect(
      (jsonDecode(bodies[3]) as Map<String, Object?>).containsKey('tools'),
      isFalse,
    );
    expect(search.queries, hasLength(3));
    final done = events.whereType<Done>().toList();
    expect(done, hasLength(1));
    expect(done.single.finishReason, 'end_turn');
  });
}
