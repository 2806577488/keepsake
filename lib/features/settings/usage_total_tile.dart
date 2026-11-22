/// Keepsake（留声）— 设置页「用量 → 用量统计」行（全局累计）。
///
/// 原 `features/sessions/usage_bar.dart`（会话列表/对话页顶部条）改造而来：
/// 对话页不再显示全局总计，改为设置 → 用量里的一行，右侧 ⟳ 重置全部累计值。
///
/// 文案依据 `ui-strings.txt` §8：
/// - 空态：`缓存命中率 — · 输入 — · 输出 — · 请求 —`
/// - 重置确认：`重置用量统计？` / `累计的缓存命中率、输入/输出 token 与请求数都会清零，无法恢复。`
/// - 完成：`用量统计已重置`
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:keepsake/core/usage/usage.dart';
import 'package:keepsake/core/usage/usage_store.dart';

/// 「用量统计」行（全局累计）。
class TotalUsageTile extends ConsumerStatefulWidget {
  const TotalUsageTile({super.key});

  @override
  ConsumerState<TotalUsageTile> createState() => _TotalUsageTileState();
}

class _TotalUsageTileState extends ConsumerState<TotalUsageTile> {
  bool _resetting = false;

  Future<UsageStore> _load() => ref.read(usageStoreProvider.future);

  Future<void> _confirmReset() async {
    if (_resetting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重置用量统计？'),
        content: const Text('累计的缓存命中率、输入/输出 token 与请求数都会清零，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _resetting = true);
    try {
      final store = await _load();
      await store.reset();
      if (mounted) _toast('用量统计已重置');
    } catch (error) {
      if (mounted) _toast('重置失败：$error');
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  void _toast(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  @override
  Widget build(BuildContext context) {
    final storeAsync = ref.watch(usageStoreProvider);
    return storeAsync.when(
      loading: () => const ListTile(
        leading: Icon(Icons.data_usage),
        title: Text('用量统计'),
        subtitle: Text('正在读取…'),
      ),
      error: (error, _) => ListTile(
        leading: const Icon(Icons.data_usage),
        title: const Text('用量统计'),
        subtitle: Text('读取失败：$error'),
      ),
      data: (store) {
        return StreamBuilder<UsageTotals>(
          stream: store.changes,
          initialData: store.totals,
          builder: (context, snapshot) {
            final totals = snapshot.data ?? store.totals;
            return ListTile(
              leading: const Icon(Icons.data_usage),
              title: const Text('用量统计'),
              subtitle: Text(_summary(totals)),
              trailing: IconButton(
                tooltip: '重置用量统计',
                icon: _resetting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.restart_alt),
                onPressed: _resetting ? null : _confirmReset,
              ),
            );
          },
        );
      },
    );
  }

  /// `缓存命中率 — · 输入 — · 输出 — · 请求 —`（总量为 0 时照 ui-strings 原文）。
  String _summary(UsageTotals totals) {
    if (totals.isEmpty) {
      return '缓存命中率 — · 输入 — · 输出 — · 请求 —';
    }
    return '缓存命中率 ${formatCacheHitPercent(totals)} · '
        '输入 ${formatCompactCount(totals.inputTokens)} · '
        '输出 ${formatCompactCount(totals.outputTokens)} · '
        '请求 ${formatCompactCount(totals.requests)}';
  }
}
