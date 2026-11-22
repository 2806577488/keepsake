/// Keepsake（留声）— 设置页「数据维护」区块（v3.3 §2.2 / §2.3）。
///
/// 信息架构规则：**影响所有数据的，从设置进**。所以「修复会话数据（补建角色卡）」
/// 和「清理孤立角色卡」只出现在这里，会话列表的多选菜单与会话内菜单都不再放
/// 批量修复入口。
///
/// 视觉规则（v3.3 §2.3）：
/// - 每项**先说「有什么问题」「影响多少」**（「N 个会话缺少角色卡」），
///   再给动宾按钮（「开始补建」/「开始清理」）；
/// - **没有问题时整项不显示**——两项都没有问题时整个「数据维护」区块（含标题）
///   一起消失，不留「0 个会话缺少角色卡」这种噪点；
/// - 执行中在项内显示进度条（补建走 [cardBackfillProvider]，清理走
///   [cardCleanupProvider]，两者都是全局后台任务，切页面不中断）。
///
/// 数量来源（都是实时查询，不缓存计数）：
/// - 缺卡会话：`CharacterService.unboundSessionIds()`（没有 character_id，
///   或绑到已删卡）；
/// - 孤立卡：`CharacterService.list()` 里 `sessionCount == 0` 的张数。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:keepsake/core/characters/card_backfill_task.dart';
import 'package:keepsake/core/characters/card_cleanup_task.dart';
import 'package:keepsake/core/characters/character_service.dart';
import 'package:keepsake/core/providers.dart';
import 'package:keepsake/core/theme.dart';

// ---------------------------------------------------------------------------
// 数量（设置页 watch 的 FutureProvider）
// ---------------------------------------------------------------------------

/// 缺少角色卡的会话（同时给数量和补建用的 [Session] 列表）。
///
/// 用 `unboundSessionIds()` 的口径：`character_id` 为空，或指向已删掉的卡，
/// 都算「缺卡」——和补建动作里的 `ensureForSession` 判据一致。
final FutureProvider<List<Session>> missingCardSessionsProvider =
    FutureProvider<List<Session>>((ref) async {
      final AppDatabase db = ref.watch(databaseProvider);
      final Set<String> ids = (await CharacterService(
        db,
      ).unboundSessionIds()).toSet();
      if (ids.isEmpty) return const <Session>[];
      final List<Session> sessions = await db.allSessions();
      return <Session>[
        for (final Session session in sessions)
          if (ids.contains(session.id)) session,
      ];
    });

/// 孤立角色卡（`sessionCount == 0`）。
final FutureProvider<List<CharacterSummary>> orphanCharactersProvider =
    FutureProvider<List<CharacterSummary>>((ref) async {
      final AppDatabase db = ref.watch(databaseProvider);
      final List<CharacterSummary> cards = await CharacterService(db).list();
      return <CharacterSummary>[
        for (final CharacterSummary summary in cards)
          if (summary.sessionCount == 0) summary,
      ];
    });

// ---------------------------------------------------------------------------
// 区块
// ---------------------------------------------------------------------------

/// 「数据维护」区块：没有需要修的东西时**整块不渲染**（含分区标题）。
class DataMaintenanceSection extends ConsumerStatefulWidget {
  const DataMaintenanceSection({super.key});

  @override
  ConsumerState<DataMaintenanceSection> createState() =>
      _DataMaintenanceSectionState();
}

class _DataMaintenanceSectionState extends ConsumerState<DataMaintenanceSection> {
  /// 补建中（本地标记：真正进度在 cardBackfillProvider 里）。
  bool _backfilling = false;

  /// 清理中（同上，进度在 cardCleanupProvider 里）。
  bool _cleaning = false;

  void _toast(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  /// 补建缺卡会话：交给全局 [cardBackfillProvider]，逐条让出事件循环。
  Future<void> _backfill() async {
    if (_backfilling) return;
    final List<Session> missing =
        ref.read(missingCardSessionsProvider).value ?? const <Session>[];
    if (missing.isEmpty) {
      _toast('所有会话都已经有角色卡');
      return;
    }
    setState(() => _backfilling = true);
    _toast('正在补建角色卡（共 ${missing.length} 个），完成前可以继续操作');
    try {
      final CardBackfillResult result = await ref
          .read(cardBackfillProvider.notifier)
          .run(missing);
      if (!mounted) return;
      ref.invalidate(sessionsProvider);
      ref.invalidate(missingCardSessionsProvider);
      ref.invalidate(orphanCharactersProvider);
      _toast(result.message);
    } catch (error) {
      if (mounted) _toast('补建失败：$error');
    } finally {
      if (mounted) setState(() => _backfilling = false);
    }
  }

  /// 清理孤立卡：确认一次 → 交给全局 [cardCleanupProvider] 逐张删。
  Future<void> _cleanOrphans() async {
    if (_cleaning) return;
    final List<CharacterSummary> orphans =
        ref.read(orphanCharactersProvider).value ?? const <CharacterSummary>[];
    if (orphans.isEmpty) return;
    final bool ok =
        (await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            final s = KeepsakeSkinColors.of(dialogContext);
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: s.rSheet),
              title: const Text('清理孤立角色卡？'),
              content: Text(
                '有 ${orphans.length} 张角色卡已经没有对应的会话了。'
                '清理会同时删掉它们的记忆、情绪和人格，无法恢复。',
              ),
              actions: <Widget>[
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(64, KeepsakeTheme.sheetButtonHeight),
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(64, KeepsakeTheme.sheetButtonHeight),
                    backgroundColor: s.c.errBg,
                    foregroundColor: s.c.onErrBg,
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('开始清理'),
                ),
              ],
            );
          },
        )) ??
        false;
    if (!ok || !mounted) return;

    setState(() => _cleaning = true);
    try {
      final int removed = await ref
          .read(cardCleanupProvider.notifier)
          .run(<String>[for (final o in orphans) o.card.id]);
      if (!mounted) return;
      ref.invalidate(orphanCharactersProvider);
      ref.invalidate(missingCardSessionsProvider);
      _toast('已清理 $removed 张孤立角色卡');
    } catch (error) {
      if (mounted) _toast('清理失败：$error');
    } finally {
      if (mounted) setState(() => _cleaning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Session>> missing = ref.watch(
      missingCardSessionsProvider,
    );
    final AsyncValue<List<CharacterSummary>> orphans = ref.watch(
      orphanCharactersProvider,
    );
    final CardBackfillProgress backfill = ref.watch(cardBackfillProvider);
    final CardCleanupProgress cleanup = ref.watch(cardCleanupProvider);

    final int missingCount = missing.value?.length ?? 0;
    final int orphanCount = orphans.value?.length ?? 0;
    // 没有问题时整项不显示；但正在跑的后台任务仍要在项内显示进度。
    final bool showFix = missingCount > 0 || backfill.running || _backfilling;
    final bool showClean = orphanCount > 0 || cleanup.running || _cleaning;
    if (!showFix && !showClean) return const SizedBox.shrink();

    final s = KeepsakeSkinColors.of(context);
    final Widget? progressFix = (backfill.running || _backfilling)
        ? _ProgressLine(
            fraction: backfill.fraction,
            caption: backfill.running ? backfill.label : '正在准备…',
          )
        : null;
    final Widget? progressClean = (cleanup.running || _cleaning)
        ? _ProgressLine(
            fraction: cleanup.fraction,
            caption: cleanup.running ? cleanup.label : '正在准备…',
          )
        : null;

    final bool busy = backfill.running || cleanup.running;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SectionTitle('数据维护'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            '批量修复所有会话的数据；只修坏掉的部分，不动聊天原文',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: s.c.onV),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Container(
            decoration: BoxDecoration(
              color: s.c.high,
              borderRadius: s.rCard,
              border: s.hairlineBorder,
            ),
            child: Column(
              children: <Widget>[
                if (showFix)
                  _MaintenanceItem(
                    title: '修复会话数据',
                    problem: '$missingCount 个会话缺少角色卡',
                    actionLabel: '开始补建',
                    busy: busy,
                    progress: progressFix,
                    onPressed: _backfill,
                  ),
                if (showFix && showClean) const Divider(height: 1),
                if (showClean)
                  _MaintenanceItem(
                    title: '清理孤立角色卡',
                    problem: '$orphanCount 张角色卡没有对应的会话',
                    actionLabel: '开始清理',
                    busy: busy,
                    progress: progressClean,
                    onPressed: _cleanOrphans,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 一项维护操作：标题 + 「有什么问题」+ 动宾按钮（执行中换成进度条）。
class _MaintenanceItem extends StatelessWidget {
  const _MaintenanceItem({
    required this.title,
    required this.problem,
    required this.actionLabel,
    required this.busy,
    required this.onPressed,
    this.progress,
  });

  final String title;

  /// 「12 个会话缺少角色卡」这类先摆问题的文案。
  final String problem;

  /// 动宾按钮文案（「开始补建」而不是「补建」）。
  final String actionLabel;

  /// 任一任务在跑时为 true（按钮置灰，避免并发打库）。
  final bool busy;

  /// 执行中的进度条；为 null 时显示问题文案。
  final Widget? progress;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final KeepsakeSkinColors s = KeepsakeSkinColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontSize: s.fsTitle,
                    fontWeight: s.titleWeight,
                    letterSpacing: s.titleLetterSpacing,
                    color: s.c.onS,
                  ),
                ),
                const SizedBox(height: 2),
                if (progress != null)
                  progress!
                else
                  Text(
                    problem,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: s.fsSub,
                      fontFamily: s.metaFontFamily,
                      color: s.c.onV,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            // 动宾文案 + 主按钮几何：pC 底 / onPC 字 / 高 36 / 圆角 rChip。
            style: FilledButton.styleFrom(
              backgroundColor: s.c.pC,
              foregroundColor: s.c.onPC,
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: s.rChip),
              textStyle: theme.textTheme.labelLarge?.copyWith(
                fontSize: s.fsSub,
                fontWeight: s.titleWeight,
              ),
            ),
            onPressed: busy ? null : onPressed,
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

/// 一行细进度条 + 说明（复用设置页「后台任务」的视觉）。
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.fraction, required this.caption});

  final double? fraction;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final KeepsakeSkinColors s = KeepsakeSkinColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        LinearProgressIndicator(
          value: fraction,
          minHeight: 3,
          borderRadius: s.rPill,
        ),
        const SizedBox(height: 4),
        Text(
          caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(color: s.c.onV),
        ),
      ],
    );
  }
}

/// 分区标题：与设置页私有的 `_SectionTitle` 视觉一致（同一份 token 推导）。
///
/// 为什么在本文件复制一份：区块要能**连标题一起隐藏**（没问题时整块不渲染），
/// 所以标题必须跟着区块返回，不能留在 `settings_screen.dart` 的 children 里。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final KeepsakeSkinColors s = KeepsakeSkinColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: s.titleWeight,
          letterSpacing: s.titleLetterSpacing,
          fontFamily: s.fontFamily,
        ),
      ),
    );
  }
}
