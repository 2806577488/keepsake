/// Keepsake（留声）— App 内「自带大脑」的编排层。
///
/// 三层职责：
/// - 发请求前 `buildInjection`：人格一句 + 情绪一句 + 相关回忆（原文片段/事实/情节），
///   按预算注入 system prompt；同时把命中项记入 `memory_recall_stats`；
/// - 落库后 `observeTurn`：规则抽取事实、每 N 轮生成情节、更新情绪/人格、做召回学习；
/// - 全失败静默：最坏退回普通聊天，不依赖 DSH / 电脑 / 网络。
library;

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show OrderingTerm;

import '../db/database.dart';
import '../providers.dart' show databaseProvider;
import 'brain_store.dart';
import 'brain_types.dart';
import 'fact_extractor.dart';
import 'mood.dart';
import 'persona.dart';
import 'recall.dart';
import 'recall_learning.dart';

/// 本轮注入过的条目（供下一轮归因学习）。
class _PendingInjection {
  const _PendingInjection({
    required this.items,
    required this.terms,
    required this.components,
    required this.scores,
  });

  final List<RecallItem> items;
  final Map<String, List<String>> terms;
  final Map<String, Map<String, double>> components;
  final Map<String, double> scores;
}

/// 大脑编排服务（App 内单机实现）。
class BrainService {
  BrainService(this._db);

  final AppDatabase _db;

  BrainStore get _store => BrainStore(_db);

  /// 每个角色上一轮注入的条目。
  final Map<String, _PendingInjection> _pending = <String, _PendingInjection>{};

  /// 每个角色已观察的轮数（决定何时生成 episode）。
  final Map<String, int> _turnCounters = <String, int>{};

  List<String> _termsOf(String text, {int max = 8}) {
    final grams = bigramsOf(text).toList(growable: false);
    if (grams.length <= max) return grams;
    return grams.take(max).toList(growable: false);
  }

  /// 生成要追加到 system prompt 末尾的整段注入文本。
  Future<BrainInjection> buildInjection({
    required BrainConfig config,
    required String characterId,
    String? sessionId,
    required String currentInput,
    List<String> recentUserTexts = const <String>[],
    Set<String> recentMessageIds = const <String>{},
    int baseSystemChars = 0,
  }) async {
    if (!config.anyEnabled || characterId.trim().isEmpty) {
      return const BrainInjection();
    }
    final budget = config.systemInjectMaxChars - baseSystemChars;
    if (budget <= 0) return const BrainInjection();

    var personaLine = '';
    var moodLine = '';
    final items = <RecallItem>[];
    final terms = <String, List<String>>{};
    final components = <String, Map<String, double>>{};
    final scores = <String, double>{};
    final recallLines = <String>[];

    final weights = await RecallWeights.load();
    final wRel = weights.weightOf('relevance');
    final wRec = weights.weightOf('recency');
    final wTop = weights.weightOf('topic');
    final normalizer = math.max(0.001, wRel + wRec + wTop);

    // 1) 人格：一句「表达倾向」。
    if (config.personaEnabled) {
      try {
        final traits = await _store.personaTraits(characterId);
        final self = describeSelfTendency(traits).trim();
        final user = describeUserPreference(traits).trim();
        if (self.isNotEmpty || user.isNotEmpty) {
          personaLine = [
            if (self.isNotEmpty) '你的表达倾向：$self',
            if (user.isNotEmpty) '对方的沟通偏好：$user',
          ].join('；');
        }
      } catch (_) {
        personaLine = '';
      }
    }

    // 2) 情绪：一句「当前心情」。
    if (config.moodEnabled) {
      try {
        final state = await _store.mood(characterId);
        if (state != null) moodLine = '当前心情：${describeMood(state)}';
      } catch (_) {
        moodLine = '';
      }
    }

    // 3) 记忆：相关原文片段 + 事实 + 情节。
    if (config.memoryEnabled) {
      try {
        final candidates = await _store.recallCandidates(
          characterId: characterId,
          sessionId: sessionId,
        );
        final now = DateTime.now();
        for (final candidate in candidates) {
          if (recallLines.length >= config.recallTurnLimit) break;
          if (recentMessageIds.contains(candidate.messageId)) continue;
          if (isNoiseRecallText(candidate.text, candidate.role)) continue;
          final relevance = bigramRelevance(currentInput, candidate.text);
          if (relevance <= 0) continue;
          final hours = now.difference(candidate.createdAt).inHours;
          final recency = (1 / (1 + hours / 24)).clamp(0.0, 1.0);
          var topic = 0.0;
          for (final previous in recentUserTexts) {
            final value = bigramRelevance(previous, candidate.text);
            if (value > topic) topic = value;
          }
          final score =
              (relevance * wRel + recency * wRec + topic * wTop) / normalizer +
              math.min(candidate.useCount, 5) * 0.02;
          if (score < 0.06) continue;
          final snippet = oneLine(candidate.text, config.recallSnippetChars);
          if (snippet.isEmpty) continue;
          recallLines.add('- 你以前说过（${timeLabel(candidate.createdAt)}）：$snippet');
          items.add(
            RecallItem(
              kind: 'turn',
              id: candidate.messageId,
              line: snippet,
              terms: _termsOf(candidate.text),
            ),
          );
          terms[candidate.messageId] = _termsOf(candidate.text);
          components[candidate.messageId] = recallComponents(
            relevance: relevance,
            recency: recency,
            topic: topic,
          );
          scores[candidate.messageId] = score;
        }

        // 事实。
        if (recallLines.length < config.recallTurnLimit) {
          final facts = await _store.allFacts(characterId: characterId);
          for (final fact in facts) {
            if (recallLines.length >= config.recallTurnLimit) break;
            final relevance = bigramRelevance(currentInput, fact.text);
            if (relevance <= 0.02) continue;
            final line =
                '- ${fact.side == 'self' ? '你自己' : '用户'}：${fact.text}';
            recallLines.add(line);
            items.add(RecallItem(kind: 'fact', id: fact.id, line: line));
            terms[fact.id] = _termsOf(fact.text);
            components[fact.id] = recallComponents(relevance: relevance);
            scores[fact.id] = relevance * wRel;
          }
        }

        // 情节。
        if (recallLines.length < config.recallTurnLimit) {
          final episodes = await _store.recentEpisodes(
            characterId: characterId,
            limit: 20,
          );
          for (final episode in episodes) {
            if (recallLines.length >= config.recallTurnLimit) break;
            // 记忆域隔离：只召回本会话产出的情节（跨对话默认不串）。
            if (sessionId != null &&
                sessionId.trim().isNotEmpty &&
                episode.sessionId != sessionId) {
              continue;
            }
            final relevance = bigramRelevance(currentInput, episode.summary);
            if (relevance <= 0.02) continue;
            final line = '- 更早的片段：${oneLine(episode.summary, 80)}';
            recallLines.add(line);
            items.add(RecallItem(kind: 'episode', id: episode.id, line: line));
            terms[episode.id] = _termsOf(episode.summary);
            components[episode.id] = recallComponents(
              relevance: relevance,
              salience: episode.salience,
            );
            scores[episode.id] = relevance * wRel + episode.salience * 0.2;
          }
        }
      } catch (_) {
        items.clear();
        terms.clear();
        components.clear();
        scores.clear();
        recallLines.clear();
      }
    }

    // 4) 预算内组装（先砍回忆，再砍情绪，最后人格）。
    String recallText() => recallLines.isEmpty
        ? ''
        : '【工作记忆 · 相关回忆】\n${recallLines.join('\n')}';
    var text = <String>[
      if (personaLine.isNotEmpty) '【人格】$personaLine',
      if (moodLine.isNotEmpty) '【情绪】$moodLine',
      if (recallLines.isNotEmpty) recallText(),
    ].join('\n');
    var dropped = 0;
    while (text.length > budget && recallLines.isNotEmpty) {
      recallLines.removeLast();
      dropped++;
      text = <String>[
        if (personaLine.isNotEmpty) '【人格】$personaLine',
        if (moodLine.isNotEmpty) '【情绪】$moodLine',
        if (recallLines.isNotEmpty) recallText(),
      ].join('\n');
    }
    if (text.length > budget) {
      final short = <String>[
        if (personaLine.isNotEmpty) '【人格】$personaLine',
        if (moodLine.isNotEmpty) '【情绪】$moodLine',
      ].join('\n');
      text = short.length <= budget ? short : '';
    }
    if (text.isEmpty) return const BrainInjection();

    final keptIds = <String>{
      for (final line in recallLines)
        for (final item in items)
          if (line.contains(item.line)) item.id,
    };
    final keptItems = items.where((item) => keptIds.contains(item.id)).toList();
    if (keptItems.isNotEmpty) {
      try {
        await _store.recordInjected(characterId, keptItems);
        _pending[characterId] = _PendingInjection(
          items: keptItems,
          terms: {
            for (final item in keptItems)
              if (terms[item.id] != null) item.id: terms[item.id]!,
          },
          components: {
            for (final item in keptItems)
              if (components[item.id] != null) item.id: components[item.id]!,
          },
          scores: {
            for (final item in keptItems)
              if (scores[item.id] != null) item.id: scores[item.id]!,
          },
        );
      } catch (_) {}
    }

    return BrainInjection(
      text: text,
      items: keptItems,
      moodLine: text.contains('【情绪】') ? moodLine : '',
      personaLine: text.contains('【人格】') ? personaLine : '',
      recallChars: recallText().length,
      dropped: dropped,
    );
  }

  /// 一轮结束后后台静默整理：情绪 / 人格 / 事实 / 情节 / 召回学习。
  Future<void> observeTurn({
    required BrainConfig config,
    required String characterId,
    required String sessionId,
    required List<String> turnMessageIds,
    required String userText,
    required String assistantText,
  }) async {
    if (!config.anyEnabled || characterId.trim().isEmpty) return;

    // 情绪：先衰减再按信号 EMA 更新，落库 + 轨迹。
    MoodState? mood;
    var moodReason = '';
    if (config.moodEnabled) {
      try {
        final current = await _store.mood(characterId) ?? MoodState.initial();
        final update = applyMoodTurn(
          current,
          userText: userText,
          assistantText: assistantText,
        );
        mood = update.state;
        moodReason = update.reason;
        await _store.saveMood(characterId, update.state, reason: update.reason);
      } catch (_) {}
    }

    // 人格：有变化才写回。
    if (config.personaEnabled) {
      try {
        final traits = await _store.personaTraits(characterId);
        final update = collectTraits(
          traits,
          userText: userText,
          assistantText: assistantText,
        );
        if (update.changed) {
          await _store.savePersonaTraits(characterId, update.traits);
        }
      } catch (_) {}
    }

    if (config.memoryEnabled) {
      // 事实：用户侧 + 助手侧（规则抽取）。
      try {
        final userFacts = extractUserFacts(userText);
        if (userFacts.isNotEmpty) {
          await _store.mergeFacts('user', userFacts, characterId: characterId);
        }
        final selfFacts = extractSelfFacts(assistantText);
        if (selfFacts.isNotEmpty) {
          await _store.mergeFacts('self', selfFacts, characterId: characterId);
        }
      } catch (_) {}

      // 情节：每 N 轮生成一条。
      final counter = (_turnCounters[characterId] ?? 0) + 1;
      _turnCounters[characterId] = counter;
      final every = math.max(1, config.consolidateEveryTurns);
      if (counter % every == 0) {
        try {
          final summary = summarizeEpisode(
            userText: userText,
            assistantText: assistantText,
          );
          if (summary.trim().length >= 10) {
            await _store.addEpisode(
              characterId: characterId,
              sessionId: sessionId,
              turnIds: turnMessageIds,
              summary: summary,
              valence: mood?.valence,
              salience: clamp01(0.45 + (userText.length >= 120 ? 0.05 : 0)),
            );
          }
        } catch (_) {}
      }
    }

    // 召回学习：上一轮注入的条目这轮有没有被用上。
    final pending = _pending.remove(characterId);
    if (pending == null || pending.items.isEmpty) return;
    try {
      await _store.recordUsageFromReply(
        characterId,
        pending.terms,
        assistantText,
      );
      final weights = await RecallWeights.load();
      for (final item in pending.items) {
        final itemTerms = pending.terms[item.id] ?? const <String>[];
        final used = itemTerms.any(
          (term) => term.length >= 2 && assistantText.contains(term),
        );
        final score = pending.scores[item.id] ?? 0.5;
        weights.update(
          components: pending.components[item.id] ?? const <String, double>{},
          error: used ? (1 - score) : -score,
        );
      }
      await weights.save();
    } catch (_) {}
  }

  /// 清空记忆 / 情绪 / 人格（设置页危险操作；`characterId` 为空 = 全部）。
  Future<void> clearAll({String? characterId}) =>
      _store.clearAll(characterId: characterId);

  /// 概览（设置页 / 调试）。
  Future<BrainStats> stats({String? characterId}) =>
      _store.stats(characterId: characterId);

  /// 导入后把整批历史「消化」进记忆层（事实 / 情节 / 人格 / 情绪）。
  ///
  /// - 幂等：已有情节的会话跳过；事实按相似度合并去重；
  /// - 每 40 个会话让出一次事件循环，避免长时间占住 UI isolate；
  /// - 返回处理过的会话数；单会话失败静默跳过。
  Future<int> consolidateImportedSessions({
    int maxSessions = 4000,
    int maxMessagesPerSession = 40,
  }) async {
    final watched = <String>{
      for (final row in await _db.select(_db.memoryEpisodes).get())
        if (row.sessionId.trim().isNotEmpty) row.sessionId,
    };
    final sessions = await _db.allSessions();
    var done = 0;
    for (final session in sessions) {
      if (done >= maxSessions) break;
      final characterId = (session.characterId ?? '').trim();
      if (characterId.isEmpty) continue;
      if (watched.contains(session.id)) continue;
      try {
        final rows = await (_db.select(_db.messages)
              ..where((t) => t.sessionId.equals(session.id))
              ..orderBy([(t) => OrderingTerm.asc(t.index)])
              ..limit(maxMessagesPerSession))
            .get();
        if (rows.isEmpty) continue;
        final userTexts = <String>[];
        final assistantTexts = <String>[];
        for (final row in rows) {
          final text = BrainStore.messageText(row.content);
          if (text.trim().isEmpty) continue;
          if (row.role == 'user') {
            userTexts.add(text);
          } else if (row.role == 'assistant') {
            assistantTexts.add(text);
          }
        }
        if (userTexts.isEmpty) continue;
        final facts = <FactCandidate>[];
        for (final text in userTexts.take(12)) {
          facts.addAll(extractUserFacts(text));
        }
        if (facts.isNotEmpty) {
          await _store.mergeFacts('user', facts, characterId: characterId);
        }
        final selfFacts = <FactCandidate>[];
        for (final text in assistantTexts.take(4)) {
          selfFacts.addAll(extractSelfFacts(text));
        }
        if (selfFacts.isNotEmpty) {
          await _store.mergeFacts('self', selfFacts, characterId: characterId);
        }
        final summary = summarizeEpisode(
          userText: userTexts.first,
          assistantText: assistantTexts.isEmpty ? '' : assistantTexts.first,
        );
        if (summary.trim().length >= 10) {
          await _store.addEpisode(
            characterId: characterId,
            sessionId: session.id,
            turnIds: <String>[for (final row in rows.take(4)) row.id],
            summary: summary,
            salience: 0.5,
          );
        }
        final traits = await _store.personaTraits(characterId);
        final update = collectTraits(
          traits,
          userText: userTexts.take(6).join('\n'),
          assistantText: assistantTexts.take(3).join('\n'),
        );
        if (update.changed) {
          await _store.savePersonaTraits(characterId, update.traits);
        }
        if (await _store.mood(characterId) == null) {
          await _store.saveMood(characterId, MoodState.initial(), reason: 'import');
        }
        watched.add(session.id);
        done++;
        if (done % 40 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      } catch (_) {
        // 单会话失败不影响其它会话。
      }
    }
    return done;
  }
}

/// 由 `main()` 的 ProviderScope 间接注入数据库；测试可 override。
final Provider<BrainService> brainServiceProvider = Provider<BrainService>(
  (ref) => BrainService(ref.watch(databaseProvider)),
);
