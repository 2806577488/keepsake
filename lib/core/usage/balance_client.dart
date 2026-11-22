/// Keepsake（留声）— DeepSeek 官方账户余额接口客户端。
///
/// 接口：`GET {root}/user/balance`，头 `Authorization: Bearer <apiKey>`。
/// 响应形如：
/// ```json
/// {"is_available":true,
///  "balance_infos":[{"currency":"CNY","total_balance":"12.50",
///                    "granted_balance":"2.50","topped_up_balance":"10.00"}]}
/// ```
///
/// `root` = provider 的 `baseUrl` 去掉结尾 `/`、再去掉 `/v1` 或 `/anthropic/v1`
/// 后缀（DeepSeek 官方 `https://api.deepseek.com` → `https://api.deepseek.com/user/balance`）。
///
/// 本文件不依赖 Flutter / Riverpod，纯 Dart + `http`，方便单测。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// 余额查询结果（已解析，字段缺失时用安全默认值）。
class BalanceReply {
  const BalanceReply({
    required this.totalBalance,
    this.grantedBalance = 0,
    this.toppedUpBalance = 0,
    this.currency = 'CNY',
    this.isAvailable = false,
  });

  /// 官方 `total_balance`：当前剩余总金额。
  final double totalBalance;

  /// 赠送余额 `granted_balance`。
  final double grantedBalance;

  /// 充值余额 `topped_up_balance`。
  final double toppedUpBalance;

  /// 币种（默认 CNY）。
  final String currency;

  /// 账户是否可用 `is_available`。
  final bool isAvailable;

  @override
  String toString() =>
      'BalanceReply($currency $totalBalance, '
      'granted=$grantedBalance, topped=$toppedUpBalance, available=$isAvailable)';
}

/// 余额查询失败（消息可直接展示给用户，统一以「余额获取失败：」开头）。
class BalanceException implements Exception {
  const BalanceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 余额接口客户端（纯函数式入口，便于测试注入 mock client）。
abstract final class BalanceClient {
  /// 默认超时。
  static const Duration defaultTimeout = Duration(seconds: 15);

  /// 由 provider 的 baseUrl 派生余额接口根地址。
  ///
  /// 例：
  /// - `https://api.deepseek.com/v1/` → `https://api.deepseek.com`
  /// - `https://api.deepseek.com/anthropic/v1` → `https://api.deepseek.com`
  /// - `http://127.0.0.1:18721/v1` → `http://127.0.0.1:18721`
  static String balanceBaseOf(String baseUrl) {
    var base = baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    for (final suffix in const <String>['/anthropic/v1', '/v1']) {
      if (base.toLowerCase().endsWith(suffix)) {
        base = base.substring(0, base.length - suffix.length);
        break;
      }
    }
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return base;
  }

  /// 余额接口完整 URI。
  static Uri balanceUriOf(String baseUrl) =>
      Uri.parse('${balanceBaseOf(baseUrl)}/user/balance');

  /// 请求并解析余额。
  ///
  /// [httpClient] 为空时内部创建并关闭；传入时由调用方负责关闭。
  /// 失败统一抛 [BalanceException]（401/403/网络/超时/坏响应都给可读消息）。
  static Future<BalanceReply> fetch({
    required String baseUrl,
    required String apiKey,
    http.Client? httpClient,
    Duration timeout = defaultTimeout,
  }) async {
    final root = balanceBaseOf(baseUrl);
    if (root.isEmpty) {
      throw const BalanceException('余额获取失败：接口地址为空');
    }
    final uri = Uri.parse('$root/user/balance');
    final client = httpClient ?? http.Client();
    final owned = httpClient == null;
    try {
      final response = await client
          .get(
            uri,
            headers: <String, String>{
              'Authorization': 'Bearer $apiKey',
              'Accept': 'application/json',
            },
          )
          .timeout(timeout);

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw BalanceException(
          '余额获取失败：API Key 无效或无权限（HTTP ${response.statusCode}）',
        );
      }
      if (response.statusCode != 200) {
        throw BalanceException('余额获取失败：HTTP ${response.statusCode}');
      }

      Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        throw const BalanceException('余额获取失败：响应不是有效 JSON');
      }
      if (decoded is! Map) {
        throw const BalanceException('余额获取失败：响应格式不正确');
      }
      final map = Map<String, Object?>.from(decoded);
      return _parse(map);
    } on BalanceException {
      rethrow;
    } on TimeoutException {
      throw const BalanceException('余额获取失败：请求超时');
    } on http.ClientException catch (error) {
      throw BalanceException('余额获取失败：网络错误（${error.message}）');
    } on FormatException {
      throw const BalanceException('余额获取失败：响应不是有效 JSON');
    } catch (error) {
      throw BalanceException('余额获取失败：$error');
    } finally {
      if (owned) client.close();
    }
  }

  static BalanceReply _parse(Map<String, Object?> map) {
    Map<String, Object?> info = map;
    final infos = map['balance_infos'];
    if (infos is List) {
      if (infos.isEmpty) {
        throw const BalanceException('余额获取失败：接口未返回余额信息');
      }
      final first = infos.first;
      if (first is Map) {
        info = Map<String, Object?>.from(first);
      } else {
        throw const BalanceException('余额获取失败：余额信息格式不正确');
      }
    }

    final total =
        _doubleOf(info['total_balance']) ?? _doubleOf(map['total_balance']);
    if (total == null) {
      throw const BalanceException('余额获取失败：响应缺少 total_balance');
    }

    final currencyRaw = info['currency']?.toString().trim() ?? '';
    final currency = currencyRaw.isEmpty ? 'CNY' : currencyRaw.toUpperCase();
    final available =
        _boolOf(map['is_available']) ??
        _boolOf(info['is_available']) ??
        total > 0;

    return BalanceReply(
      totalBalance: total < 0 ? 0 : total,
      grantedBalance: _doubleOf(info['granted_balance']) ?? 0,
      toppedUpBalance: _doubleOf(info['topped_up_balance']) ?? 0,
      currency: currency,
      isAvailable: available,
    );
  }
}

double? _doubleOf(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed);
  }
  return null;
}

bool? _boolOf(Object? value) {
  if (value == null) return null;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    switch (value.trim().toLowerCase()) {
      case 'true':
      case '1':
        return true;
      case 'false':
      case '0':
        return false;
    }
  }
  return null;
}
