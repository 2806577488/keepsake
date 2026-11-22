/// Keepsake（留声）— 模型列表（`GET {base}/models`）。
///
/// 协议证据（`reports/apk/http-api.md` §1/§3）：`/models` 字面量、
/// 文案「填好后会从 /models 拉真实列表」、「模型列表请求失败：HTTP 」；
/// 符号证据（`dart-symbols.md` §2）：`fetchProviderModels`、`ProviderModel`、
/// 私有 `_findModels`。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'chat_backend.dart'
    show
        ApiError,
        ApiErrorKind,
        kRateLimitErrorMessage,
        kInsufficientBalanceMessage,
        kInvalidApiKeyMessage;
import 'provider_models.dart';

export 'provider_models.dart' show ProviderModel;

/// 「模型列表请求失败：HTTP 」（ui-strings §11 原文 [确定]）。
const String kModelListFailedPrefix = '模型列表请求失败：HTTP ';

/// Anthropic 兼容请求需要的版本头（[推断] 标准值）。
const String kAnthropicVersionHeader = 'anthropic-version';
const String kAnthropicVersion = '2023-06-01';

/// `{base}/models`。
String modelsUrlOf(String baseUrl) {
  final base = normalizeProviderBase(baseUrl);
  if (base.toLowerCase().endsWith('/models')) return base;
  return '$base/models';
}

/// 拉取真实模型列表。
///
/// - `kind == anthropic` 时用 `x-api-key` + `anthropic-version` 头；
/// - 解析 `data[].id`（兼容 `models[]` / `data: {"id": {...}}` / 纯字符串数组）；
/// - HTTP 错误文案固定为「模型列表请求失败：HTTP <code>」。
Future<List<ProviderModel>> fetchProviderModels({
  required String baseUrl,
  required String apiKey,
  ProviderKind kind = ProviderKind.openai,
  http.Client? client,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final url = _parseUrl(modelsUrlOf(baseUrl), baseUrl);
  final ownsClient = client == null;
  final httpClient = client ?? http.Client();
  try {
    final response = await httpClient
        .get(url, headers: _headers(apiKey, kind))
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _modelListError(response.statusCode, response.body);
    }
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw ApiError(
        '$kModelListFailedPrefix${response.statusCode}',
        statusCode: response.statusCode,
        body: response.body,
        cause: error,
        kind: ApiErrorKind.parse,
      );
    }
    return _findModels(decoded);
  } on TimeoutException catch (error) {
    throw ApiError.timeout(error);
  } on http.ClientException catch (error) {
    throw ApiError.network(error);
  } on ApiError {
    rethrow;
  } catch (error) {
    throw ApiError.network(error);
  } finally {
    if (ownsClient) httpClient.close();
  }
}

Uri _parseUrl(String url, String baseUrl) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw ApiError(
      '模型列表请求失败：接口地址无效（$baseUrl）',
      kind: ApiErrorKind.parse,
    );
  }
  return uri;
}

Map<String, String> _headers(String apiKey, ProviderKind kind) {
  final headers = <String, String>{
    'accept': 'application/json',
  };
  final key = apiKey.trim();
  if (key.isNotEmpty) {
    if (kind == ProviderKind.anthropic) {
      headers['x-api-key'] = key;
      headers[kAnthropicVersionHeader] = kAnthropicVersion;
      headers['authorization'] = 'Bearer $key';
    } else {
      headers['authorization'] = 'Bearer $key';
    }
  }
  return headers;
}

ApiError _modelListError(int statusCode, String body) {
  // 可展示的固定文案（http-api.md §3 [确定]）。
  final message = '$kModelListFailedPrefix$statusCode';
  final kind = switch (statusCode) {
    401 || 403 => ApiErrorKind.auth,
    402 => ApiErrorKind.insufficientBalance,
    429 => ApiErrorKind.rateLimit,
    >= 500 => ApiErrorKind.network,
    _ => ApiErrorKind.http,
  };
  final detailSuffix = switch (statusCode) {
    401 || 403 => kInvalidApiKeyMessage,
    402 => kInsufficientBalanceMessage,
    429 => kRateLimitErrorMessage,
    _ => null,
  };
  final text = detailSuffix == null ? message : '$message（$detailSuffix）';
  return ApiError(text, statusCode: statusCode, body: body, kind: kind);
}

/// 从未知形态的 JSON 里挖出模型条目（符号表 `_findModels`）。
List<ProviderModel> _findModels(Object? decoded) {
  final models = <ProviderModel>[];

  void addOne(Object? node) {
    if (node is String) {
      final id = node.trim();
      if (id.isNotEmpty) models.add(ProviderModel(id: id));
      return;
    }
    if (node is Map) {
      final map = Map<String, Object?>.from(node);
      final id = (map['id'] ?? map['model'] ?? map['name'] ?? '').toString().trim();
      if (id.isEmpty) return;
      final ownedBy = map['owned_by'] ?? map['ownedBy'] ?? map['provider'];
      models.add(
        ProviderModel(
          id: id,
          ownedBy: ownedBy?.toString().trim().isEmpty ?? true
              ? null
              : ownedBy.toString().trim(),
        ),
      );
    }
  }

  void addAll(Object? node) {
    if (node == null) return;
    if (node is List) {
      for (final item in node) {
        addOne(item);
      }
      return;
    }
    if (node is Map) {
      final map = Map<String, Object?>.from(node);
      // {"data":[...]} / {"models":[...]} / {"result":[...]}
      for (final key in const <String>['data', 'models', 'result', 'items']) {
        final value = map[key];
        if (value is List) {
          for (final item in value) {
            addOne(item);
          }
          return;
        }
        if (value is Map) {
          // {"data": {"model-id": {...}}}
          for (final entry in value.entries) {
            final item = entry.value;
            if (item is Map) {
              addOne(<String, Object?>{...Map<String, Object?>.from(item), 'id': entry.key});
            } else {
              addOne(entry.key);
            }
          }
          return;
        }
      }
      // 单个模型对象。
      addOne(map);
      return;
    }
  }

  addAll(decoded);

  // 去重（保留首次出现顺序）。
  final seen = <String>{};
  final result = <ProviderModel>[];
  for (final model in models) {
    if (seen.add(model.id)) result.add(model);
  }
  return result;
}
