/// Keepsake（留声）— 累计用量持久化（SharedPreferences）。
///
/// 符号证据（`reports/apk/dart-symbols.md` §2、`db-schema.md` §5）：
/// `UsageStore`、`resetUsageSnapshots`、`usage_totals`、`accumulated_token_usage`、
/// `token_usage`、`_reportedUsage`、`_jsonCount`、`_readCount`。
///
/// 存储：SharedPreferences 里 `usage_totals`（JSON 字符串，主存储）+
/// `accumulated_token_usage`（同内容镜像，兼容旧版本/旧 key）；
/// 单会话用量单独存在 `usage_session_<sessionId>`，JSON 里额外带
/// `last_prompt_tokens`（最近一次请求的 prompt tokens，用于计算占用率）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'usage.dart';

/// 单会话用量：累计值 + **最近一次请求的 prompt tokens**。
///
/// 持久化在 `usage_session_<sessionId>`（与 [UsageTotals.toJson] 同层，
/// 额外一个 `last_prompt_tokens` 字段）；旧数据缺这个字段时读成 0。
class SessionUsage {
  const SessionUsage({
    this.totals = UsageTotals.empty,
    this.lastPromptTokens = 0,
  });

  /// 本会话累计用量（缓存命中率、输入/输出、请求数）。
  final UsageTotals totals;

  /// 最近一次请求的 prompt（input）tokens；`<= 0` 表示没有数据。
  final int lastPromptTokens;

  bool get isEmpty => totals.isEmpty && lastPromptTokens <= 0;

  bool get isNotEmpty => !isEmpty;

  /// 累加一次用量；[promptTokens] 有值时覆盖 `lastPromptTokens`。
  SessionUsage add(
    UsageDelta delta, {
    bool countRequest = true,
    int? promptTokens,
  }) {
    final prompt = promptTokens ?? lastPromptTokens;
    return SessionUsage(
      totals: totals.add(delta, countRequest: countRequest),
      lastPromptTokens: prompt < 0 ? 0 : prompt,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    ...totals.toJson(),
    'last_prompt_tokens': lastPromptTokens,
  };

  /// 容错解析：既接受带 `last_prompt_tokens` 的新数据，也接受旧版纯累计 JSON。
  factory SessionUsage.fromJson(Map<String, Object?>? json) {
    if (json == null || json.isEmpty) return const SessionUsage();
    return SessionUsage(
      totals: UsageTotals.fromJson(json),
      lastPromptTokens: _intOf(json['last_prompt_tokens']) ?? 0,
    );
  }

  /// 从 SharedPreferences 里的 JSON 字符串解析（坏数据返回空）。
  static SessionUsage fromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const SessionUsage();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return SessionUsage.fromJson(Map<String, Object?>.from(decoded));
      }
    } catch (_) {
      // 忽略坏数据。
    }
    return const SessionUsage();
  }

  @override
  String toString() => 'SessionUsage($totals, lastPrompt=$lastPromptTokens)';
}

/// 累计 token 用量存储。
///
/// ```dart
/// final store = await UsageStore.load(await SharedPreferences.getInstance());
/// await store.record(event.usage);   // 每次收到 Usage 事件
/// final totals = store.totals;       // 统计页展示
/// await store.reset();               // 「重置用量统计？」
/// ```
class UsageStore {
  /// 构造时同步读一遍 SharedPreferences（`SharedPreferences` 已异步加载完成）。
  UsageStore(this._prefs) : _totals = _readTotals(_prefs);

  /// 显式异步加载入口（UI/测试都可用）。
  static Future<UsageStore> load(SharedPreferences prefs) async =>
      UsageStore(prefs);

  /// 主存储 key（JSON 文本）。
  static const String usageTotalsKey = 'usage_totals';

  /// 旧 key（同内容镜像，读取时作为 fallback）。
  static const String accumulatedTokenUsageKey = 'accumulated_token_usage';

  /// 旧 key（读取时作为 fallback）。
  static const String tokenUsageKey = 'token_usage';

  final SharedPreferences _prefs;
  UsageTotals _totals;
  final StreamController<UsageTotals> _changes =
      StreamController<UsageTotals>.broadcast();
  bool _disposed = false;

  /// 当前累计值（同步读取，UI 可直接用）。
  UsageTotals get totals => _totals;

  /// 空态判断：统计页渲染「缓存命中率 — · 输入 — · 输出 — · 请求 —」。
  bool get isEmpty => _totals.isEmpty;

  bool get isNotEmpty => _totals.isNotEmpty;

  /// 每次 [record] / [reset] / [refresh] 推一次当前累计值。
  Stream<UsageTotals> get changes => _changes.stream;

  /// 累加一次用量并持久化。
  ///
  /// [countRequest] 默认 `true`：即使响应里没有 usage，也算一次请求
  /// （统计页「 请求 」计数）。
  Future<UsageTotals> record(
    UsageDelta delta, {
    bool countRequest = true,
  }) async {
    _totals = _totals.add(delta, countRequest: countRequest);
    await _persist();
    _emit();
    return _totals;
  }

  /// [record] 的别名。
  Future<void> add(UsageDelta delta, {bool countRequest = true}) async {
    await record(delta, countRequest: countRequest);
  }

  /// 重置全部累计值（设置页「重置用量统计？」）。
  Future<void> reset() async {
    _totals = UsageTotals.empty;
    await _persist();
    _emit();
  }

  /// 从 SharedPreferences 重新读取（外部改动/导入后刷新）。
  Future<void> refresh() async {
    _totals = _readTotals(_prefs);
    _emit();
  }

  Future<void> _persist() async {
    final encoded = jsonEncode(_totals.toJson());
    await _prefs.setString(usageTotalsKey, encoded);
    // 同时镜像旧 key，保证旧版本/旧统计逻辑读到同一份数据。
    await _prefs.setString(accumulatedTokenUsageKey, encoded);
  }

  void _emit() {
    if (_disposed || _changes.isClosed) return;
    _changes.add(_totals);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _changes.close();
    for (final controller in _sessionChanges.values) {
      controller.close();
    }
    _sessionChanges.clear();
  }

  // -------------------------------------------------------------------------
  // 单会话用量（对话界面「当前对话」统计）
  // -------------------------------------------------------------------------

  /// 单会话累计 key 前缀；完整 key 为 `usage_session_<sessionId>`。
  static const String sessionKeyPrefix = 'usage_session_';

  /// 某一轮会话的累计 key（会话 id 做 URL 之外的原样拼接，id 由数据库生成）。
  static String sessionKey(String sessionId) => '$sessionKeyPrefix$sessionId';

  /// 已加载过的单会话用量（懒加载缓存）。
  final Map<String, SessionUsage> _sessions = <String, SessionUsage>{};

  /// 每个会话一个广播流，UI 订阅当前会话即可。
  final Map<String, StreamController<SessionUsage>> _sessionChanges =
      <String, StreamController<SessionUsage>>{};

  /// 某一轮会话的完整用量（累计 + 最近一次 prompt tokens）。
  SessionUsage sessionUsage(String sessionId) =>
      _sessions.putIfAbsent(sessionId, () => _readSessionUsage(sessionId));

  /// 某一轮会话的累计值（同步；首次读 SharedPreferences）。
  UsageTotals sessionTotals(String sessionId) => sessionUsage(sessionId).totals;

  /// 某一轮会话最近一次请求的 prompt tokens（无数据为 0）。
  int sessionLastPromptTokens(String sessionId) =>
      sessionUsage(sessionId).lastPromptTokens;

  /// 某一轮会话用量变化流（`recordSession` / `resetSession` 时推送）。
  Stream<SessionUsage> sessionChanges(String sessionId) =>
      (_sessionChanges[sessionId] ??=
              StreamController<SessionUsage>.broadcast())
          .stream;

  /// 累加一次单会话用量并持久化。
  ///
  /// [promptTokens] 传最近一次请求的 prompt(input) tokens，供对话页计算「占用率」；
  /// 不传则保留上一次的值。
  Future<SessionUsage> recordSession(
    String sessionId,
    UsageDelta delta, {
    bool countRequest = true,
    int? promptTokens,
  }) async {
    if (sessionId.isEmpty) return const SessionUsage();
    final next = sessionUsage(sessionId)
        .add(delta, countRequest: countRequest, promptTokens: promptTokens);
    _sessions[sessionId] = next;
    await _prefs.setString(sessionKey(sessionId), jsonEncode(next.toJson()));
    _emitSession(sessionId);
    return next;
  }

  /// 只重置某一轮会话的累计值（不影响全局累计与其它会话）。
  Future<SessionUsage> resetSession(String sessionId) async {
    if (sessionId.isEmpty) return const SessionUsage();
    const empty = SessionUsage();
    _sessions[sessionId] = empty;
    await _prefs.remove(sessionKey(sessionId));
    _emitSession(sessionId);
    return empty;
  }

  void _emitSession(String sessionId) {
    if (_disposed) return;
    final controller = _sessionChanges[sessionId];
    if (controller == null || controller.isClosed) return;
    controller.add(_sessions[sessionId] ?? const SessionUsage());
  }

  /// 读取某一轮会话的持久化用量；缺失/坏数据返回空。
  SessionUsage _readSessionUsage(String sessionId) =>
      SessionUsage.fromJsonString(_prefs.getString(sessionKey(sessionId)));

  static UsageTotals _readTotals(SharedPreferences prefs) {
    for (final key in const <String>[
      usageTotalsKey,
      accumulatedTokenUsageKey,
      tokenUsageKey,
    ]) {
      final raw = prefs.getString(key);
      if (raw == null || raw.trim().isEmpty) continue;
      final parsed = UsageTotals.fromJsonString(raw);
      if (parsed.isNotEmpty) return parsed;
      // 值存在但为空对象时也认为读取成功（保持 0 而不是继续 fallback）。
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return parsed;
      } catch (_) {
        // 坏数据：继续尝试下一个 key。
      }
    }
    return UsageTotals.empty;
  }

  @override
  String toString() => 'UsageStore($_totals)';
}

/// 清空累计用量（符号证据：`resetUsageSnapshots`）。
Future<void> resetUsageSnapshots(UsageStore store) => store.reset();

/// 全局用量存储。
///
/// 统计页 `UsageTile` 直接 `ref.watch(usageStoreProvider)`；聊天页在收到
/// `ChatEvent.Usage` 时 `await store.record(delta)`。
final FutureProvider<UsageStore> usageStoreProvider =
    FutureProvider<UsageStore>((ref) async {
      final prefs = await SharedPreferences.getInstance();
      final store = UsageStore(prefs);
      ref.onDispose(store.dispose);
      return store;
    });

/// 容错整数解析（`last_prompt_tokens` 可能是 int / double / 字符串）。
int? _intOf(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return int.tryParse(trimmed) ?? double.tryParse(trimmed)?.round();
  }
  return null;
}
