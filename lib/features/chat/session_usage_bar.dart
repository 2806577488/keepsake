/// Keepsake（留声）— 对话界面顶部的「本会话用量」条。
///
/// 对话页只保留这一条统计（全局「总计」已移到设置 → 用量）：
/// - **占用**：最近一次请求的 prompt(input) tokens ÷ 模型上下文窗口（设置可改）× 100；
/// - **缓存命中**：本会话累计缓存命中率；
/// - 主文案后面用小字展示 token 数（`1.3万 / 12.8万`）便于核对；
/// - 无数据统一显示 `—`，占用率超过 100% 照实显示；
/// - 不再提供本会话重置（避免误触；全局重置在设置 → 用量）。
///
/// 文案：`本会话 占用 10% · 缓存命中 33%`。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:keepsake/core/settings.dart';
import 'package:keepsake/core/usage/usage.dart';
import 'package:keepsake/core/usage/usage_store.dart';

/// 对话界面顶部的「本会话用量」条。
class SessionUsageBar extends ConsumerWidget {
  const SessionUsageBar({super.key, required this.sessionId});

  /// 当前打开会话的 id；空字符串时组件不渲染。
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (sessionId.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final storeAsync = ref.watch(usageStoreProvider);
    return storeAsync.when(
      loading: () => _Shell(
        theme: theme,
        summary: '本会话 正在读取…',
        iconColor: theme.colorScheme.onSurfaceVariant,
      ),
      error: (error, _) => _Shell(
        theme: theme,
        summary: '本会话 读取失败：$error',
        iconColor: theme.colorScheme.error,
      ),
      data: (store) {
        return StreamBuilder<SessionUsage>(
          stream: store.sessionChanges(sessionId),
          initialData: store.sessionUsage(sessionId),
          builder: (context, snapshot) {
            final usage = snapshot.data ?? store.sessionUsage(sessionId);
            final occupancy = formatOccupancyPercent(
              promptTokens: usage.lastPromptTokens,
              contextWindowTokens: settings.contextWindowTokens,
            );
            final cacheHit = formatCacheHitPercent(usage.totals);
            return _Shell(
              theme: theme,
              summary: '本会话 占用 $occupancy · 缓存命中 $cacheHit',
              hint: usage.lastPromptTokens > 0
                  ? '${formatCompactCount(usage.lastPromptTokens)} / '
                        '${formatCompactCount(settings.contextWindowTokens)}'
                  : null,
              iconColor: theme.colorScheme.primary,
            );
          },
        );
      },
    );
  }
}

/// 统一的紧凑外壳：浅色底、单行、无分割线。
class _Shell extends StatelessWidget {
  const _Shell({
    required this.theme,
    required this.summary,
    required this.iconColor,
    this.hint,
  });

  final ThemeData theme;
  final String summary;
  final Color iconColor;

  /// 主文案后的小字（token 数）；null 不显示。
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final hintText = hint;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.data_usage, size: 16, color: iconColor),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (hintText != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      hintText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
