/// 批量删除会话的「后台任务」。
///
/// 为什么单独抽出来：用户确认删除后就应该**无条件删完**——不能因为他退出
/// 全选、离开列表页、进聊天页而中断，也不该让界面一直干等。所以删除由
/// 这个 provider 持有：界面只负责启动 + 显示进度（设置 → 后台任务）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/characters/character_service.dart';
import '../../core/providers.dart';
import '../../core/usage/usage_store.dart';

/// 删除任务进度（`done / total`）。`running == false` 表示没有删除任务。
class DeleteTaskState {
  const DeleteTaskState({this.done = 0, this.total = 0, this.running = false});

  final int done;
  final int total;
  final bool running;

  bool get active => running;

  String get label => running ? '正在删除会话：$done / $total' : '没在删除';

  double get fraction => total == 0 ? 1.0 : (done / total).clamp(0.0, 1.0);
}

/// 批量删除控制器。
///
/// `start()` 返回删除成功的条数；调用方通常 `unawaited(...)` 后立刻退出多选，
/// 任务在后台继续跑完。
class DeleteTaskController extends Notifier<DeleteTaskState> {
  @override
  DeleteTaskState build() => const DeleteTaskState();

  Future<int> start({
    required List<String> ids,
    List<String> characterIds = const <String>[],
  }) async {
    if (ids.isEmpty || state.running) return 0;
    state = DeleteTaskState(done: 0, total: ids.length, running: true);

    final db = ref.read(databaseProvider);
    var removed = 0;
    try {
      await db.deleteSessions(
        ids,
        onProgress: (int done, int total) {
          state = DeleteTaskState(done: done, total: total, running: true);
        },
      );
      removed = ids.length;
    } catch (_) {
      // 批量失败退回逐条，尽量删掉能删的。
      for (final String id in ids) {
        try {
          await db.deleteSession(id);
          removed++;
        } catch (_) {
          // 单条失败不影响其余会话。
        }
      }
    }

    // 用量清理逐条做（单条 update，比删会话轻得多）。
    try {
      final UsageStore? store = await ref.read(usageStoreProvider.future);
      for (final String id in ids) {
        try {
          await store?.resetSession(id);
        } catch (_) {
          // 同上。
        }
      }
    } catch (_) {
      // 用量清理失败不影响删会话。
    }

    // 孤儿角色卡：删完后没有会话再引用的，连同它的记忆/情绪/人格一起清掉。
    //
    // 走 [CharacterService.deleteCharacter] 而不是直接删表：它内部会
    // `_brain.clearAll(characterId)`，把该角色隔离的记忆一并清空——
    // 「删了会话就等于这段记忆从 AI 的记忆系统里清了」。
    try {
      final List<Session> remaining = await db.allSessions();
      final Set<String> stillUsed = <String>{
        for (final Session session in remaining)
          if ((session.characterId ?? '').isNotEmpty) session.characterId!,
      };
      final CharacterService service = CharacterService(db);
      for (final String characterId in characterIds) {
        if (stillUsed.contains(characterId)) continue;
        try {
          await service.deleteCharacter(characterId);
        } catch (_) {
          // 角色卡清理失败不影响删会话。
        }
      }
    } catch (_) {
      // 同上。
    }

    state = const DeleteTaskState();
    return removed;
  }
}

/// 全局删除任务进度（列表页启动，设置页展示）。
final NotifierProvider<DeleteTaskController, DeleteTaskState> deleteTaskProvider =
    NotifierProvider<DeleteTaskController, DeleteTaskState>(
      DeleteTaskController.new,
    );
