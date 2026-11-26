/// Keepsake（留声）— 账户余额快照持久化 + 基线（消费）计算 + Riverpod 接线。
///
/// **基线逻辑（关键设计）**：
/// - 第一次成功获取余额：`baseline = total_balance`；
/// - 之后每次刷新：若 `当前余额 > 基线`（说明有充值），
///   `baseline = baseline + (当前余额 − 上次余额)`，把充值计入基线；
/// - `整体已用费用 = max(0, baseline − 当前余额)`；
/// - `整体剩余费用 = 当前余额`；
/// - `剩余率 = 当前余额 ÷ baseline × 100`（baseline 为 0 显示 `—`）。
///
/// 存储：SharedPreferences 一个 JSON 字符串，key = `balance_snapshot`。
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers.dart';
import 'balance_client.dart';

/// 是否支持余额查询：按预设 id 判断，仅 DeepSeek 官方。
///
/// 用 `presetId` 而不是 baseUrl：用户可能把 DeepSeek 官方平台改成代理地址，
/// 仍然需要能查余额。
bool supportsBalanceQuery(AiProvider? provider) =>
    provider != null && provider.presetId == presetDeepSeekId;

/// 币种符号（CNY → ¥，USD → $，其它显示代码）。
String currencySymbolOf(String currency) => switch (currency.toUpperCase()) {
  'CNY' => '¥',
  'USD' => r'$',
  final String code => code.isEmpty ? '¥' : '$code ',
};

/// 金额文案（两位小数 + 币种符号）。
String formatAmount(double value, String currency) =>
    '${currencySymbolOf(currency)}${value.toStringAsFixed(2)}';

/// 余额快照（含基线；不可变）。
class BalanceSnapshot {
  const BalanceSnapshot({
    required this.baseline,
    required this.current,
    this.currency = 'CNY',
    this.updatedAt,
    this.isAvailable = false,
    this.granted = 0,
    this.toppedUp = 0,
  });

  /// 空快照（首次查询前）。
  static const BalanceSnapshot empty = BalanceSnapshot(baseline: 0, current: 0);

  /// 基线余额（首次成功获取的余额；充值会累加进基线）。
  final double baseline;

  /// 当前官方剩余余额（`total_balance`）。
  final double current;

  /// 币种（默认 CNY）。
  final String currency;

  /// 最近一次成功刷新时间。
  final DateTime? updatedAt;

  /// `is_available`。
  final bool isAvailable;

  /// 赠送余额 `granted_balance`。
  final double granted;

  /// 充值余额 `topped_up_balance`。
  final double toppedUp;

  /// 整体已用费用 = max(0, 基线 − 当前余额)。
  double get used => math.max(0, baseline - current);

  /// 剩余率（百分比数值）；基线为 0 时返回 null（UI 显示 `—`）。
  double? get remainingRate {
    if (baseline <= 0) return null;
    final percent = current / baseline * 100;
    if (percent.isNaN || percent.isInfinite) return null;
    return percent;
  }

  /// 有数据（成功查询过）。
  bool get hasData => updatedAt != null;

  /// 超过这个时长就认为余额过期，进页面时自动刷新一次（防抖，避免反复请求）。
  static const Duration staleAfter = Duration(seconds: 60);

  /// 是否过期（没数据也算过期）。
  bool isStale([DateTime? now]) {
    final at = updatedAt;
    if (at == null) return true;
    return (now ?? DateTime.now()).difference(at) > staleAfter;
  }

  /// 应用一次接口结果，返回新快照。
  ///
  /// 充值判定与基线累加规则见文件头注释；币种变化时重置基线（避免混币种计算）。
  BalanceSnapshot apply(BalanceReply reply, {DateTime? now}) {
    final nextCurrent = reply.totalBalance;
    var nextBaseline = baseline;
    final sameCurrency = currency.toUpperCase() == reply.currency.toUpperCase();
    if (nextBaseline <= 0 || !sameCurrency) {
      nextBaseline = nextCurrent;
    } else if (nextCurrent > nextBaseline) {
      nextBaseline = nextBaseline + (nextCurrent - current);
    }
    return BalanceSnapshot(
      baseline: nextBaseline,
      current: nextCurrent,
      currency: reply.currency,
      updatedAt: now ?? DateTime.now(),
      isAvailable: reply.isAvailable,
      granted: reply.grantedBalance,
      toppedUp: reply.toppedUpBalance,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'baseline': baseline,
    'current': current,
    'currency': currency,
    'updated_at': updatedAt?.toIso8601String(),
    'is_available': isAvailable,
    'granted': granted,
    'topped_up': toppedUp,
  };

  /// 容错解析：缺字段用默认值。
  factory BalanceSnapshot.fromJson(Map<String, Object?>? json) {
    if (json == null || json.isEmpty) return empty;
    return BalanceSnapshot(
      baseline: _doubleOf(json['baseline']) ?? 0,
      current: _doubleOf(json['current']) ?? 0,
      currency: _stringOf(json['currency']) ?? 'CNY',
      updatedAt: _dateOf(json['updated_at']),
      isAvailable: _boolOf(json['is_available']) ?? false,
      granted: _doubleOf(json['granted']) ?? 0,
      toppedUp: _doubleOf(json['topped_up']) ?? 0,
    );
  }

  /// 从 SharedPreferences 的 JSON 字符串解析；坏数据返回 `null`（当作从未查询）。
  static BalanceSnapshot? fromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return BalanceSnapshot.fromJson(Map<String, Object?>.from(decoded));
      }
    } catch (_) {
      // 坏数据。
    }
    return null;
  }

  @override
  String toString() =>
      'BalanceSnapshot(baseline=$baseline, current=$current, '
      'currency=$currency, used=$used)';
}

/// 余额快照存储（SharedPreferences key = `balance_snapshot`）。
class BalanceStore {
  BalanceStore(this._prefs) : _snapshot = _read(_prefs);

  /// SharedPreferences key。
  static const String prefsKey = 'balance_snapshot';

  final SharedPreferences _prefs;
  BalanceSnapshot? _snapshot;

  /// 当前快照（未查询过为 null）。
  BalanceSnapshot? get snapshot => _snapshot;

  /// 应用接口结果并持久化（基线规则在 [BalanceSnapshot.apply] 里）。
  Future<BalanceSnapshot> apply(BalanceReply reply) async {
    final next = (_snapshot ?? BalanceSnapshot.empty).apply(reply);
    _snapshot = next;
    try {
      await _prefs.setString(prefsKey, jsonEncode(next.toJson()));
    } catch (_) {
      // 落盘失败不影响本次展示（下次刷新再写）。
    }
    return next;
  }

  static BalanceSnapshot? _read(SharedPreferences prefs) =>
      BalanceSnapshot.fromJsonString(prefs.getString(prefsKey));
}

// ---------------------------------------------------------------------------
// Riverpod 接线
// ---------------------------------------------------------------------------

/// 余额快照存储。
final FutureProvider<BalanceStore> balanceStoreProvider =
    FutureProvider<BalanceStore>((Ref ref) async {
      final prefs = await SharedPreferences.getInstance();
      return BalanceStore(prefs);
    });

/// 余额控制器：`ref.watch(balanceProvider)` 拿快照；`refresh()` 重新请求接口。
class BalanceController extends AsyncNotifier<BalanceSnapshot?> {
  @override
  Future<BalanceSnapshot?> build() async {
    final store = await ref.watch(balanceStoreProvider.future);
    return store.snapshot;
  }

  /// 重新请求当前平台的余额（DeepSeek 官方）。
  ///
  /// 前置校验失败时抛 [BalanceException]（文案即 UI 要展示的提示）。
  /// 刷新失败不清空已有快照：页面用 toast + 错误卡片展示本次错误。
  Future<BalanceSnapshot> refresh() async {
    final book = ref.read(providerBookProvider);
    final provider = book.current;
    if (provider == null ||
        provider.baseUrl.trim().isEmpty ||
        !provider.hasApiKey) {
      throw const BalanceException('先配置 AI 平台和 API Key');
    }
    if (!supportsBalanceQuery(provider)) {
      throw const BalanceException('当前平台不支持余额查询（仅 DeepSeek 官方支持）');
    }

    final client = ref.read(httpClientFactoryProvider)();
    try {
      final reply = await BalanceClient.fetch(
        baseUrl: provider.baseUrl,
        apiKey: provider.apiKey.trim(),
        httpClient: client,
      );
      final store = await ref.read(balanceStoreProvider.future);
      final snapshot = await store.apply(reply);
      state = AsyncData<BalanceSnapshot?>(snapshot);
      return snapshot;
    } finally {
      client.close();
    }
  }
}

/// 余额快照（异步；未查询过为 `data(null)`）。
final AsyncNotifierProvider<BalanceController, BalanceSnapshot?>
balanceProvider = AsyncNotifierProvider<BalanceController, BalanceSnapshot?>(
  BalanceController.new,
  name: 'balanceProvider',
);

// ---------------------------------------------------------------------------
// 内部 JSON 解析小工具
// ---------------------------------------------------------------------------

double? _doubleOf(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

String? _stringOf(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

bool? _boolOf(Object? value) {
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

DateTime? _dateOf(Object? value) {
  final text = _stringOf(value);
  if (text == null) return null;
  return DateTime.tryParse(text)?.toLocal();
}
