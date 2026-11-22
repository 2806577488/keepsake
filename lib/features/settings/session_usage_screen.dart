/// Keepsake（留声）— 设置 → 用量 →「每个对话的占用」子页面。
///
/// 数据来源：
/// - 会话标题 / 更新时间：drift `sessions`（`sessionsProvider`）；
/// - 每会话累计与最近一次 prompt tokens：`UsageStore`（`usage_session_<id>`）；
/// - 上下文窗口：`Settings.contextWindowTokens`。
///
/// 每行：标题（空则 `未命名会话`）、`占用 X%`、`缓存命中 Y%`、输入/输出 token、相对时间。
/// 排序：占用率降序（无数据排最后，同档按更新时间倒序）。
/// 空态：`还没有对话用量`。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:keepsake/core/providers.dart';
import 'package:keepsake/core/usage/usage.dart';
import 'package:keepsake/core/usage/usage_store.dart';

/// 「每个对话的占用」页面。
class SessionUsageScreen extends ConsumerWidget {
  const SessionUsageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(sessionsProvider);
    final storeAsync = ref.watch(usageStoreProvider);
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('每个对话的占用')),
      body: sessionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorBody(message: '读取会话失败：$error'),
        data: (sessions) => storeAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ErrorBody(message: '读取用量失败：$error'),
          data: (store) => _SessionUsageList(
            sessions: sessions,
            store: store,
            contextWindowTokens: settings.contextWindowTokens,
          ),
        ),
      ),
    );
  }
}

class _SessionUsageList extends StatelessWidget {
  const _SessionUsageList({
    required this.sessions,
    required this.store,
    required this.contextWindowTokens,
  });

  final List<Session> sessions;
  final UsageStore store;
  final int contextWindowTokens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = sessions
        .map(
          (session) =>
              _Row(session: session, usage: store.sessionUsage(session.id)),
        )
        .toList(growable: true);

    final hasAny = rows.any((row) => row.usage.isNotEmpty);
    if (!hasAny) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.forum_outlined,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                '还没有对话用量',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    rows.sort((a, b) {
      final left = a.rate(contextWindowTokens);
      final right = b.rate(contextWindowTokens);
      if (left == null && right == null) {
        return b.session.updatedAt.compareTo(a.session.updatedAt);
      }
      if (left == null) return 1;
      if (right == null) return -1;
      final byRate = right.compareTo(left);
      if (byRate != 0) return byRate;
      return b.session.updatedAt.compareTo(a.session.updatedAt);
    });

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
      itemBuilder: (context, index) => _SessionUsageTile(
        row: rows[index],
        contextWindowTokens: contextWindowTokens,
      ),
    );
  }
}

class _SessionUsageTile extends StatelessWidget {
  const _SessionUsageTile({
    required this.row,
    required this.contextWindowTokens,
  });

  final _Row row;
  final int contextWindowTokens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = row.session.title.trim().isEmpty
        ? '未命名会话'
        : row.session.title.trim();
    final usage = row.usage;
    final occupancy = formatOccupancyPercent(
      promptTokens: usage.lastPromptTokens,
      contextWindowTokens: contextWindowTokens,
    );
    final cacheHit = formatCacheHitPercent(usage.totals);
    final hasTotals = usage.totals.isNotEmpty;
    final input = hasTotals
        ? formatCompactCount(usage.totals.inputTokens)
        : '—';
    final output = hasTotals
        ? formatCompactCount(usage.totals.outputTokens)
        : '—';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(
          Icons.chat_bubble_outline,
          size: 20,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('占用 $occupancy · 缓存命中 $cacheHit'),
          Text(
            '输入 $input / 输出 $output · '
            '${_relativeTime(row.session.updatedAt)}',
          ),
        ],
      ),
      isThreeLine: true,
    );
  }
}

class _Row {
  const _Row({required this.session, required this.usage});

  final Session session;
  final SessionUsage usage;

  /// 与对话条/设置页同一口径：最近一次 prompt tokens ÷ 上下文窗口 × 100。
  double? rate(int contextWindowTokens) => occupancyPercent(
    promptTokens: usage.lastPromptTokens,
    contextWindowTokens: contextWindowTokens,
  );
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ),
    );
  }
}

/// 相对时间（与会话列表页口径一致：刚刚 / N 分钟前 / N 小时前 / N 天前 / 日期）。
String _relativeTime(DateTime updatedAt) {
  final now = DateTime.now();
  final time = updatedAt.isUtc ? updatedAt.toLocal() : updatedAt;
  final diff = now.difference(time);
  if (diff.isNegative || diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays < 7) return '${diff.inDays} 天前';
  if (time.year == now.year) return '${time.month} 月 ${time.day} 日';
  return '${time.year} 年 ${time.month} 月 ${time.day} 日';
}
