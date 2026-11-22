/// Keepsake（留声）— 后台「清理孤立角色卡」任务。
///
/// v3.3 §2.2：清理孤立角色卡属于**影响所有会话**的批量操作，入口只在
/// 「设置 › 数据维护」。这里把它抽成**可监听的状态对象 + Riverpod provider**，
/// 与 [CardBackfillTask] 对称：
///
/// - [CardCleanupProgress]：`running / done / total / failed`（不可变）；
/// - [CardCleanupTask]：`Notifier<CardCleanupProgress>`，`run()` 逐张删卡
///   （每张之间 `await Future<void>.delayed(Duration.zero)` 让出事件循环，
///   设置页的进度条才有机会重建）；
/// - [cardCleanupProvider]：全局单例（非 autoDispose，离开设置页也会继续跑）。
///
/// 删除走 [CharacterService.deleteCharacter]：内部 `_brain.clearAll`，
/// 记忆 / 情绪 / 人格一起清，和「删会话 = 记忆从 AI 记忆系统里清掉」同一语义。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:keepsake/core/characters/character_service.dart';
import 'package:keepsake/core/providers.dart';

/// 清理孤立角色卡的进度（不可变，供 UI `watch`）。
class CardCleanupProgress {
  const CardCleanupProgress({
    this.running = false,
    this.done = 0,
    this.total = 0,
    this.failed = 0,
  });

  /// 是否正在清理。
  final bool running;

  /// 已处理张数（含失败）。
  final int done;

  /// 本次要清理的孤立卡总数。
  final int total;

  /// 失败张数。
  final int failed;

  /// 0..1 进度；`total <= 0` 时为 null（不显示进度条）。
  double? get fraction {
    if (total <= 0) return null;
    final double value = done / total;
    return value < 0 ? 0 : (value > 1 ? 1 : value);
  }

  /// 设置页「后台任务」那行文案。
  String get label => '正在清理孤立角色卡：$done / $total';
}

/// 后台清理任务（全局单例）。
class CardCleanupTask extends Notifier<CardCleanupProgress> {
  bool _disposed = false;

  @override
  CardCleanupProgress build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    return const CardCleanupProgress();
  }

  /// 逐张删除 [characterIds] 里的角色卡，返回成功删掉的张数。
  ///
  /// 任务已在跑时直接返回 0（不并发起第二个循环）。
  Future<int> run(List<String> characterIds) async {
    if (state.running || characterIds.isEmpty) return 0;

    state = CardCleanupProgress(running: true, total: characterIds.length);
    final AppDatabase db = ref.read(databaseProvider);
    final CharacterService service = CharacterService(db);
    int done = 0;
    int failed = 0;

    for (final String id in characterIds) {
      try {
        await service.deleteCharacter(id);
        done++;
      } catch (_) {
        failed++;
      }
      if (_disposed) return done;
      state = CardCleanupProgress(
        running: true,
        done: done,
        total: characterIds.length,
        failed: failed,
      );
      // 让出事件循环：进度条 / 统计数字才有机会刷新。
      await Future<void>.delayed(Duration.zero);
    }

    if (!_disposed) {
      state = CardCleanupProgress(
        done: done,
        total: characterIds.length,
        failed: failed,
      );
    }
    return done;
  }
}

/// 全局清理任务：设置 › 数据维护 点「开始清理」时
/// `ref.read(cardCleanupProvider.notifier).run(ids)`，进度在设置页看。
final NotifierProvider<CardCleanupTask, CardCleanupProgress>
cardCleanupProvider =
    NotifierProvider<CardCleanupTask, CardCleanupProgress>(
      CardCleanupTask.new,
    );
