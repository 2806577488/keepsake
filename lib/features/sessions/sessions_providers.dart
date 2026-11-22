/// Keepsake（留声）— 会话列表页的 **UI 侧组合 provider**。
///
/// 底层 provider 由基座（A 批次）在 `lib/core/providers.dart` 里冻结，本文件**不再重复定义**：
///
/// ```dart
/// final StreamProvider<List<Session>> sessionsProvider;                            // watchSessions()，updated_at/sort 已排序
/// final FutureProviderFamily<List<SessionSearchHit>, String> sessionSearchProvider; // 参数 = 查询串 q
/// final FutureProviderFamily<List<ProviderModel>, String> providerModelsProvider;   // 参数 = AiProvider.id
/// ```
///
/// 这里只放会话列表 / 全局搜索需要的 UI 组合：
/// - [sessionSearchQueryProvider] 搜索框文本（防抖在 UI 层用 Timer 做，provider 只存值）；
/// - [sessionSearchResultsProvider] 搜索结果：空 query 直接返回空列表，不发 SQL；
/// - [orderedSessionsProvider] 展示顺序：**置顶优先**，其余按 `updated_at` 倒序。
///
/// 依据：`reports/apk/dart-symbols.md`（`features/sessions/sessions_providers.dart`：
/// `allSessions` / `watchSessions` / `searchSessions`）、`db-schema.md`（`flags` 位域、
/// 搜索 SQL 按 `messages.content LIKE`）、`ui-strings.txt` §1。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:keepsake/core/providers.dart';

/// 会话是否置顶（位值来自 `core/db/database.dart` 的 `SessionFlag.pinned`）。
bool isSessionPinned(Session session) =>
    (session.flags & SessionFlag.pinned) != 0;

/// 会话显示标题（空标题回退到「未命名会话」原文）。
String sessionDisplayTitle(Session session) {
  final title = session.title.trim();
  return title.isEmpty ? '未命名会话' : title;
}

/// 展示顺序：置顶优先，其余按 `updated_at` 倒序（同刻按 id 稳定排序，避免列表抖动）。
List<Session> sortSessionsForDisplay(List<Session> sessions) {
  final sorted = List<Session>.of(sessions);
  sorted.sort((a, b) {
    final pinnedA = isSessionPinned(a);
    final pinnedB = isSessionPinned(b);
    if (pinnedA != pinnedB) return pinnedA ? -1 : 1;
    final byUpdated = b.updatedAt.compareTo(a.updatedAt);
    if (byUpdated != 0) return byUpdated;
    return a.id.compareTo(b.id);
  });
  return sorted;
}

// ---------------------------------------------------------------------------
// 搜索框文本
// ---------------------------------------------------------------------------

/// 全局搜索框的当前文本（''=未搜索）。
///
/// Riverpod 3 里 `StateProvider` 已移到 `legacy.dart`，这里用 `Notifier`。
class SessionSearchQuery extends Notifier<String> {
  @override
  String build() => '';

  /// 更新查询串（相同值不触发重建）。
  void setQuery(String value) {
    if (state != value) state = value;
  }

  /// 清空。
  void clear() => setQuery('');
}

final NotifierProvider<SessionSearchQuery, String> sessionSearchQueryProvider =
    NotifierProvider<SessionSearchQuery, String>(SessionSearchQuery.new);

// ---------------------------------------------------------------------------
// 搜索结果
// ---------------------------------------------------------------------------

/// 全局搜索结果（`SessionSearchHit`：消息正文命中的会话，含所属会话标题）。
///
/// 空 query 不发请求（直接返回空列表），避免列表页一进来就打一次全表 LIKE。
final FutureProvider<List<SessionSearchHit>> sessionSearchResultsProvider =
    FutureProvider<List<SessionSearchHit>>((ref) async {
      final query = ref.watch(sessionSearchQueryProvider).trim();
      if (query.isEmpty) return const <SessionSearchHit>[];
      return ref.watch(sessionSearchProvider(query).future);
    });

// ---------------------------------------------------------------------------
// 会话列表展示顺序
// ---------------------------------------------------------------------------

/// 会话列表（含置顶排序）。`AsyncValue` 的 loading / error 原样透传，
/// 数据分支再做排序，UI 直接 `.when(...)`。
final Provider<AsyncValue<List<Session>>> orderedSessionsProvider =
    Provider<AsyncValue<List<Session>>>((ref) {
      final sessions = ref.watch(sessionsProvider);
      return sessions.whenData(sortSessionsForDisplay);
    });
