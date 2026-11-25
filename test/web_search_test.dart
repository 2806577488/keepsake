import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:keepsake/core/search/web_search.dart';

void main() {
  test('Search API：请求形状与结果解析', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode(<String, Object?>{
          'results': <Object?>[
            <String, Object?>{
              'title': '标题A',
              'url': 'https://a.example/1',
              'snippet': '摘要A',
              'summary': '长摘要A',
              'site_name': '站A',
              'date': '2026-11-01T00:00:00+00:00',
            },
            <String, Object?>{'title': '没有链接', 'url': ''},
          ],
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final service = DeepSeekWebSearchService(
      baseUrl: 'https://api.deepseek.com',
      apiKey: 'sk-test',
      clientFactory: () => client,
    );

    final items = await service.search('杭州天气', count: 5);

    expect(captured.url.toString(), 'https://api.deepseek.com/v1/tools/search');
    expect(captured.headers['authorization'], 'Bearer sk-test');
    final body = jsonDecode(captured.body) as Map<String, Object?>;
    expect(body['query'], '杭州天气');
    expect(body['count'], 5);
    expect(body['need_content'], false);

    expect(items, hasLength(1));
    expect(items.first.title, '标题A');
    expect(items.first.siteName, '站A');
    final text = items.first.toModelText(index: 1);
    expect(text, contains('https://a.example/1'));
    expect(text, contains('长摘要A'));
  });

  test('Fetch API：返回 Markdown 正文', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode(<String, Object?>{
          'title': '页面标题',
          'content': '# 正文\n\n内容',
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final service = DeepSeekWebSearchService(
      baseUrl: 'https://api.deepseek.com',
      apiKey: 'sk-test',
      clientFactory: () => client,
    );

    final page = await service.fetchPage('https://example.com/a');

    expect(captured.url.toString(), 'https://api.deepseek.com/v1/tools/fetch');
    expect(page.title, '页面标题');
    expect(page.content, contains('正文'));
  });

  test('baseUrl 填成 /v1 时不会拼出 /v1/v1/tools', () async {
    late Uri captured;
    final client = MockClient((request) async {
      captured = request.url;
      return http.Response(jsonEncode(<String, Object?>{'results': <Object?>[]}), 200);
    });
    final service = DeepSeekWebSearchService(
      baseUrl: 'https://api.deepseek.com/v1',
      apiKey: 'sk-test',
      clientFactory: () => client,
    );

    await service.search('x');

    expect(captured.toString(), 'https://api.deepseek.com/v1/tools/search');
  });

  test('HTTP 错误映射成可读中文', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode(<String, Object?>{
          'error': <String, Object?>{'message': 'Rate limit reached'},
        }),
        429,
      );
    });
    final service = DeepSeekWebSearchService(
      baseUrl: 'https://api.deepseek.com',
      apiKey: 'sk-test',
      clientFactory: () => client,
    );

    await expectLater(
      service.search('x'),
      throwsA(
        isA<Object>().having(
          (error) => error.toString(),
          'message',
          contains('联网服务请求失败'),
        ),
      ),
    );
  });

  test('Tavily：搜索请求形状与结果解析', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode(<String, Object?>{
          'results': <Object?>[
            <String, Object?>{
              'title': 'Tavily 结果',
              'url': 'https://t.example/1',
              'content': '页面摘要',
              'published_date': '2026-01-01T00:00:00Z',
            },
          ],
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final service = TavilyWebSearchService(
      baseUrl: 'https://api.tavily.com',
      apiKey: 'tvly-test',
      clientFactory: () => client,
    );

    final items = await service.search('天气', count: 3);

    expect(captured.url.toString(), 'https://api.tavily.com/search');
    expect(captured.headers['authorization'], 'Bearer tvly-test');
    final body = jsonDecode(captured.body) as Map<String, Object?>;
    expect(body['query'], '天气');
    expect(body['max_results'], 3);
    expect(items.single.url, 'https://t.example/1');
    expect(service.supportsFetch, isTrue);
  });

  test('Tavily：extract 抓正文', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode(<String, Object?>{
          'results': <Object?>[
            <String, Object?>{'url': 'https://t.example/1', 'raw_content': '# 正文'},
          ],
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final service = TavilyWebSearchService(
      baseUrl: 'https://api.tavily.com',
      apiKey: 'tvly-test',
      clientFactory: () => client,
    );

    final page = await service.fetchPage('https://t.example/1');

    expect(captured.url.toString(), 'https://api.tavily.com/extract');
    expect(page.content, contains('正文'));
  });

  test('博查：解析 data.webPages.value', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode(<String, Object?>{
          'code': 200,
          'data': <String, Object?>{
            'webPages': <String, Object?>{
              'value': <Object?>[
                <String, Object?>{
                  'name': '博查结果',
                  'url': 'https://b.example/1',
                  'snippet': '摘要',
                  'summary': '长摘要',
                  'siteName': '站点',
                },
              ],
            },
          },
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final service = BochaWebSearchService(
      baseUrl: 'https://api.bochaai.com',
      apiKey: 'bocha-test',
      clientFactory: () => client,
    );

    final items = await service.search('天气', count: 5);

    expect(captured.url.toString(), 'https://api.bochaai.com/v1/web-search');
    expect(items.single.title, '博查结果');
    expect(items.single.siteName, '站点');
    expect(service.supportsFetch, isFalse);
  });

  test('Brave：GET 参数、鉴权头与结果解析', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode(<String, Object?>{
          'web': <String, Object?>{
            'results': <Object?>[
              <String, Object?>{
                'title': 'Brave 结果',
                'url': 'https://c.example/1',
                'description': '描述',
                'profile': <String, Object?>{'name': '站点'},
              },
            ],
          },
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final service = BraveWebSearchService(
      baseUrl: 'https://api.search.brave.com',
      apiKey: 'brave-test',
      clientFactory: () => client,
    );

    final items = await service.search('天气', count: 4);

    expect(captured.url.path, '/res/v1/web/search');
    expect(captured.url.queryParameters['q'], '天气');
    expect(captured.url.queryParameters['count'], '4');
    expect(captured.headers['x-subscription-token'], 'brave-test');
    expect(items.single.title, 'Brave 结果');
    expect(service.supportsFetch, isFalse);
  });

  test('webSearchServiceFor 按 serviceId 选实现', () {
    final tavily = webSearchServiceFor(const WebSearchConfig(
      mode: WebSearchMode.external,
      serviceId: kSearchServiceTavily,
      apiKey: 'k',
    ));
    expect(tavily, isA<TavilyWebSearchService>());
    expect(tavily!.supportsFetch, isTrue);

    final bocha = webSearchServiceFor(const WebSearchConfig(
      mode: WebSearchMode.external,
      serviceId: kSearchServiceBocha,
      apiKey: 'k',
    ));
    expect(bocha, isA<BochaWebSearchService>());
    expect(bocha!.supportsFetch, isFalse);

    final none = webSearchServiceFor(const WebSearchConfig(
      mode: WebSearchMode.external,
      serviceId: kSearchServiceTavily,
    ));
    expect(none, isNull);
  });
}
