// ==========================================================================
// 摘录文件：lib/features/settings/settings_screen.dart
// 原文件共 664 行。以下仅为设计师需要看的片段，代码内容原样保留（含原注释）。
// 保留了 _BackgroundTasksSection + _ProgressBar。
// ==========================================================================


// ---- 摘录 1/1 · 原文件第 494–594 行 ----

/// 「后台任务」区块：导入进度 + 补建角色卡进度。
///
/// - 导入：watch 现有 `importProgressProvider`（`ImportTask`），显示
///   `ImportProgress.label` + `fraction` 进度条（跑完且没失败时整行隐藏）；
/// - 补建角色卡：watch `cardBackfillProvider`（`CardBackfillTask`），
///   跑的时候显示「正在补建角色卡：done / total」+ 进度条，不跑时不显示该行。
///
/// 两条任务都可能由别的页面启动（导入在设置页 / 列表顶部，补建在会话列表），
/// 这里只负责显示，不提供启动按钮。
class _BackgroundTasksSection extends ConsumerWidget {
  const _BackgroundTasksSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ImportProgress? progress = ref.watch(importProgressProvider).value;
    final CardBackfillProgress backfill = ref.watch(cardBackfillProvider);

    final List<Widget> rows = <Widget>[];
    if (progress != null && (progress.running || progress.hasFailures)) {
      rows.add(
        ListTile(
          leading: Icon(
            progress.running
                ? Icons.cloud_download_outlined
                : Icons.error_outline,
            color: progress.running ? null : theme.colorScheme.error,
          ),
          title: Text(
            progress.running ? progress.label : '有 ${progress.failed} 条没导上',
          ),
          subtitle: progress.running
              ? _ProgressBar(
                  fraction: progress.fraction,
                  caption: progress.currentTitle,
                )
              : null,
        ),
      );
    }
    if (backfill.running) {
      rows.add(
        ListTile(
          leading: const Icon(Icons.badge_outlined),
          title: Text(backfill.label),
          subtitle: _ProgressBar(fraction: backfill.fraction),
        ),
      );
    }

    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Text(
          '没有正在运行的后台任务',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

/// 一行细进度条 + 可选说明文字（当前导入的会话标题）。
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.fraction, this.caption});

  final double? fraction;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = caption;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: fraction,
          minHeight: 3,
          borderRadius: BorderRadius.circular(2),
        ),
        if (text != null && text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

// ==========================================================================
// 摘录结束。
// ==========================================================================
