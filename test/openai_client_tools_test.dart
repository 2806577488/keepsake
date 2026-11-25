import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:keepsake/core/api/chat_backend.dart';
import 'package:keepsake/core/api/openai_client.dart';
import 'package:keepsake/core/api/provider_models.dart';
import 'package:keepsake/core/search/web_search.dart';

final AiProvider _deepSeek = AiProvider(
  id: 'p1',
  presetId: presetDeepSeekId,
  name: 'DeepSeek（官方）',
  baseUrl: 'https://api.deepseek.com',
  apiKey: 'sk-test',
  model: 'deepseek-flash',
  supportsSearch: true,
);

String _sse(List<Map<String, Object?>> chunks) =>
    '${chunks.map((chunk) => 'data: ${jsonEncode(chunk)}\n\n').join()}'
    'data: [DONE]\n\n';

String _toolCallSse() => _sse(<Map<String, Object?>>[
      <String, Object?>{
        'choices': <Object?>[
          <String, Object?>{
            'index': 0,
            'delta': <String, Object?>{
              'role': 'assistant',
              'tool_calls': <Object?>[
                <String, Object?>{
                  'index': 0,
                  'id': 'call_1',
                  'type': 'function',
                  'function': <String, Object?>{
                    'name': 'web_search',
                    'arguments': '{"query": "杭州 天气"}',
                  },
                },
              ],
            },
            'finish_reason': null,
          },
        ],
      },
      <String, Object?>{
        'choices': <Object?>[
          <String, Object?>{'index': 0, 'delta': <String, Object?>{}, 'finish_reason': 'tool_calls'},
        ],
      },
    ]);

String _finalSse() => _sse(<Map<String, Object?>>[
      <String, Object?>{
        'choices': <Object?>[
          <String, Object?>{
            'index': 0,
            'delta': <String, Object?>{'content': '晴，26 度'},
            'finish_reason': null,
          },
        ],
      },
      <String, Object?>{
        'choices': <Object?>[
          <String, Object?>{'index': 0, 'delta': <String, Object?>{}, 'finish_reason': 'stop'},
        ],
        'usage': <String, Object?>{
          'prompt_tokens': 30,
          'completion_tokens': 5,
          'total_tokens': 35,
        },
      },
    ]);

class _FakeSearch implements WebSearchService {
  final List<String> queries = <String>[];

  @override
  bool get isConfigured => true;

  @override
  bool get supportsFetch => true;

  @override
  Future<List<WebSearchItem>> search(String query, {int count = 8}) async {
    queries.add(query);
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

void main() {
  test('联网走客户端 function 工具 + 外部搜索，多轮回填', () async {
    final bodies = <String>[];
    final search = _FakeSearch();
    final client = MockClient.streaming((request, bodyStream) async {
      bodies.add(utf8.decode(await bodyStream.toBytes()));
      final sse = bodies.length == 1 ? _toolCallSse() : _finalSse();
      return http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode(sse)),
        200,
        headers: <String, String>{'content-type': 'text/event-stream'},
      );
    });
    final backend = OpenAiClient(
      provider: _deepSeek,
      clientFactory: () => client,
      webSearchService: search,
    );

    final events = <ChatEvent>[];
    await for (final event in backend.streamChat(ChatRequest(
      provider: _deepSeek,
      messages: <ChatTurn>[ChatTurn.user('杭州今天天气怎么样？')],
      search: true,
      webSearch: const WebSearchConfig(mode: WebSearchMode.external),
    ))) {
      events.add(event);
    }

    // 1) 第一轮请求：声明的是普通 function 工具，而不是服务端工具。
    expect(bodies, hasLength(2));
    final first = jsonDecode(bodies[0]) as Map<String, Object?>;
    final tools = (first['tools'] as List<Object?>).cast<Map<String, Object?>>();
    expect(tools, hasLength(2));
    expect(tools.every((tool) => tool['type'] == 'function'), isTrue);
    expect(bodies[0], isNot(contains('deepseek_web_search')));

    // 2) 第二轮请求：assistant(tool_calls) + role:"tool" 结果都回填了。
    final second = jsonDecode(bodies[1]) as Map<String, Object?>;
    final messages =
        (second['messages'] as List<Object?>).cast<Map<String, Object?>>();
    final assistant = messages.firstWhere(
      (message) =>
          message['role'] == 'assistant' && message['tool_calls'] != null,
    );
    final toolCalls = assistant['tool_calls'] as List<Object?>;
    expect(toolCalls, hasLength(1));
    final toolMessage = messages.firstWhere(
      (message) => message['role'] == 'tool',
    );
    expect(toolMessage['tool_call_id'], 'call_1');
    expect('${toolMessage['content']}', contains('新闻A'));
    expect(search.queries, <String>['杭州 天气']);

    // 3) UI 事件：搜索中 → 来源；最终正文与结束。
    final results = events.whereType<ToolResult>().toList();
    expect(results.where((event) => event.running).length, 1);
    final finished = results.last;
    expect(finished.running, isFalse);
    expect(finished.sources.single.url, 'https://news.example/a');
    expect(
      events.whereType<TextDelta>().map((event) => event.text).join(),
      '晴，26 度',
    );
    expect(events.whereType<Done>(), hasLength(1));
  });

  test('非 DeepSeek 平台仍走服务端工具（老路径）', () {
    final other = _deepSeek.copyWith(baseUrl: 'https://api.example.com');
    final backend = OpenAiClient(provider: other);
    final body = backend.buildRequestBody(ChatRequest(
      provider: other,
      messages: <ChatTurn>[ChatTurn.user('hi')],
      search: true,
    ));
    final tools = (body['tools'] as List<Object?>).cast<Map<String, Object?>>();
    expect(tools.first['type'], 'deepseek_web_search');
  });
}
