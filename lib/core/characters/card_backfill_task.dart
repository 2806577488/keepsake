/// Keepsake（留声）— 后台「补建角色卡」任务。
///
/// 会话列表左上角多选菜单里的「为缺少角色卡的会话补建」原来直接写在
/// `features/sessions/sessions_screen.dart` 的 `_backfillCards` 里，循环跑完
/// 之前用户切到设置页看不到任何进度。这里把补建抽成 **可监听的状态对象 +
/// Riverpod provider**：
///
/// - [CardBackfillProgress]：`running / done / total / failed`（不可变）；
/// - [CardBackfillTask]：`Notifier<CardBackfillProgress>`，`run()` 逐条补建
///   （每条之间 `await Future<void>.delayed(Duration.zero)` 让出事件循环，
///   UI 才能刷新进度条）；
/// - [cardBackfillProvider]：全局单例（非 autoDispose，离开列表页也会继续跑）。
///
/// 建议 toast 仍然只由调用方在**开始 / 结束**各提示一次，循环里不弹
/// （进度改由设置页「后台任务」看，避免列表上反复闪 SnackBar）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:keepsake/core/characters/character_service.dart';
import 'package:keepsake/core/providers.dart';

/// 补建角色卡的进度（不可变，供 UI `watch`）。
class CardBackfillProgress {
  const CardBackfillProgress({
    this.running = false,
    this.done = 0,
    this.total = 0,
    this.failed = 0,
  });

  /// 是否正在补建。
  final bool running;

  /// 已处理条数（含失败）。
  final int done;

  /// 本次要补建的会话总数。
  final int total;

  /// 失败条数。
  final int failed;

  /// 0..1 进度；`total <= 0` 时为 null（不显示进度条）。
  double? get fraction {
    if (total <= 0) return null;
    final double value = done / total;
    return value < 0 ? 0 : (value > 1 ? 1 : value);
  }

  /// 设置页「后台任务」那行文案。
  String get label => '正在补建角色卡：$done / $total';

  CardBackfillProgress copyWith({
    bool? running,
    int? done,
    int? total,
    int? failed,
  }) {
    return CardBackfillProgress(
      running: running ?? this.running,
      done: done ?? this.done,
      total: total ?? this.total,
      failed: failed ?? this.failed,
    );
  }
}

/// 补建结果（调用方据此 toast 一次）。
class CardBackfillResult {
  const CardBackfillResult({required this.done, required this.failed});

  final int done;
  final int failed;

  /// 「已补建 N 张角色卡，失败 M 个」（失败为 0 时不带后半句）。
  String get message => '已补建 $done 张角色卡${failed > 0 ? '，失败 $failed 个' : ''}';
}

/// 后台补建任务（全局单例）。
class CardBackfillTask extends Notifier<CardBackfillProgress> {
  bool _disposed = false;

  @override
  CardBackfillProgress build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    return const CardBackfillProgress();
  }

  bool get running => state.running;

  /// 逐条补建 [sessions] 里缺角色卡的会话。
  ///
  /// 已有角色卡的会话会被 [CharacterService.ensureForSession] 跳过（幂等），
  /// 所以重跑安全。任务已在跑时直接返回当前计数（不并发起第二个循环）。
  Future<CardBackfillResult> run(List<Session> sessions) async {
    if (state.running) {
      return CardBackfillResult(done: state.done, failed: state.failed);
    }
    if (sessions.isEmpty) {
      return const CardBackfillResult(done: 0, failed: 0);
    }

    state = CardBackfillProgress(running: true, total: sessions.length);
    final AppDatabase db = ref.read(databaseProvider);
    final CharacterService service = CharacterService(db);
    int done = 0;
    int failed = 0;

    for (final Session session in sessions) {
      try {
        final card = await service.ensureForSession(session.id);
        await db.setSessionCharacter(session.id, card.id);
        done++;
      } catch (_) {
        failed++;
      }
      if (_disposed) {
        return CardBackfillResult(done: done, failed: failed);
      }
      state = state.copyWith(done: done, failed: failed);
      // 让出事件循环：设置页的进度条 / 列表刷新才有机会重建。
      await Future<void>.delayed(Duration.zero);
    }

    if (!_disposed) {
      state = state.copyWith(running: false, done: done, failed: failed);
    }
    return CardBackfillResult(done: done, failed: failed);
  }
}

/// 全局补建任务：会话列表点「补建」时 `ref.read(cardBackfillProvider).run(...)`，
/// 设置页 `ref.watch(cardBackfillProvider)` 显示进度。
final NotifierProvider<CardBackfillTask, CardBackfillProgress>
cardBackfillProvider =
    NotifierProvider<CardBackfillTask, CardBackfillProgress>(
      CardBackfillTask.new,
    );
