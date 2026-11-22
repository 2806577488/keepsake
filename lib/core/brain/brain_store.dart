/// Keepsake（留声）— 「自带大脑」的本机存储层（drift / SQLite）。
///
/// 只做搬运：把 `lib/core/brain/*` 的纯逻辑结果写进 v4 新增的 6 张表，或从表里读出来。
/// 原文（`messages.content`）是唯一事实来源，这里**不删、不改任何消息**；
/// `memory_episodes.turn_ids_json` 只是指针。
///
/// **记忆隔离（硬规则）**：所有读写都带 `characterId`。
/// 六个记忆/情绪/人格表都按角色分区，任何查询都先按 `character_id` 过滤——
/// 跨角色既写不进去，也召不回来。
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../chat/blocks.dart' as blk;
import '../db/database.dart';
import 'brain_types.dart';
import 'fact_extractor.dart' show trimFactText;
import 'mood.dart';
import 'persona.dart';
import 'recall.dart';

const Uuid _uuid = Uuid();

/// 设置页展示用的汇总。
class BrainStats {
  const BrainStats({
    this.userFacts = 0,
    this.selfFacts = 0,
    this.episodes = 0,
    this.moodName = '',
    this.consolidatedTurns = 0,
  });

  final int userFacts;
  final int selfFacts;
  final int episodes;
  final String moodName;

  /// 已整理进 episode 的轮次数。
  final int consolidatedTurns;

  bool get isEmpty => userFacts == 0 && selfFacts == 0 && episodes == 0;

  @override
  String toString() =>
      'BrainStats(facts=$userFacts/$selfFacts, episodes=$episodes)';
}

/// 大脑存储。所有方法都可能抛（调用方统一 try/catch 静默）。
class BrainStore {
  BrainStore(this.db);

  final AppDatabase db;

  // -------------------------------------------------------------------------
  // facts
  // -------------------------------------------------------------------------

  Future<List<MemoryFact>> factsOf(String side, {required String characterId}) async {
    final rows = await (db.select(db.memoryFacts)
          ..where(
            (t) => t.side.equals(side) & t.characterId.equals(characterId),
          )
          ..orderBy(<OrderingTerm Function(MemoryFacts)>[
            (t) => OrderingTerm(expression: t.weight, mode: OrderingMode.desc),
            (t) => OrderingTerm(
                  expression: t.updatedAt,
                  mode: OrderingMode.desc,
                ),
          ]))
        .get();
    return rows.map(_factOf).toList(growable: false);
  }

  Future<List<MemoryFact>> allFacts({required String characterId}) async {
    final rows = await (db.select(db.memoryFacts)
          ..where((t) => t.characterId.equals(characterId)))
        .get();
    return rows.map(_factOf).toList(growable: false);
  }

  MemoryFact _factOf(MemoryFactRow row) => MemoryFact(
        id: row.id,
        side: row.side,
        text: row.factText,
        weight: row.weight,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        lastUsedAt: row.lastUsedAt,
        useCount: row.useCount,
      );

  /// 并入一批候选事实：相似度 ≥0.8 视为同一条（权重微增），否则新增；
  /// 每侧超过 [kMaxFactsPerSide] 时按「权重 × 新近度」淘汰最弱的一条。
  ///
  /// 返回实际新增 + 合并的条数。
  Future<int> mergeFacts(
    String side,
    List<FactCandidate> incoming, {
    required String characterId,
    DateTime? now,
  }) async {
    if (incoming.isEmpty) return 0;
    final at = now ?? DateTime.now();
    final existing = List<MemoryFact>.of(
      await factsOf(side, characterId: characterId),
    );
    var changed = 0;
    for (final item in incoming) {
      final text = trimFactText(item.text);
      if (text.isEmpty) continue;
      MemoryFact? match;
      for (final fact in existing) {
        if (textSimilarity(fact.text, text) >= 0.8) {
          match = fact;
          break;
        }
      }
      if (match != null) {
        final nextText = text.length > match.text.length ? text : match.text;
        final nextWeight = clamp01(match.weight + 0.04);
        final index = existing.indexOf(match);
        final updated = MemoryFact(
          id: match.id,
          side: side,
          text: nextText,
          weight: nextWeight,
          createdAt: match.createdAt,
          updatedAt: at,
          lastUsedAt: match.lastUsedAt,
          useCount: match.useCount,
        );
        existing[index] = updated;
        await (db.update(db.memoryFacts)..where((t) => t.id.equals(match!.id)))
            .write(
          MemoryFactsCompanion(
            factText: Value(nextText),
            weight: Value(nextWeight),
            updatedAt: Value(at),
          ),
        );
        changed += 1;
        continue;
      }
      final fact = MemoryFact(
        id: _uuid.v4(),
        side: side,
        text: text,
        weight: clamp01(item.weight),
        createdAt: at,
        updatedAt: at,
      );
      await db.into(db.memoryFacts).insert(
            MemoryFactsCompanion.insert(
              id: fact.id,
              characterId: Value(characterId),
              side: side,
              factText: Value(fact.text),
              weight: Value(fact.weight),
              createdAt: Value(at),
              updatedAt: Value(at),
            ),
          );
      existing.add(fact);
      changed += 1;
    }

    // 每侧上限：淘汰保留分数最低的。
    while (existing.length > kMaxFactsPerSide) {
      var worstIndex = 0;
      var worstScore = double.infinity;
      for (var i = 0; i < existing.length; i++) {
        final score = _factKeepScore(existing[i], at);
        if (score < worstScore) {
          worstScore = score;
          worstIndex = i;
        }
      }
      final removed = existing.removeAt(worstIndex);
      await (db.delete(db.memoryFacts)..where((t) => t.id.equals(removed.id)))
          .go();
    }
    return changed;
  }

  double _factKeepScore(MemoryFact fact, DateTime now) {
    final at = fact.updatedAt ?? fact.createdAt;
    if (at == null) return fact.weight * 0.5;
    final days = now.difference(at).inMinutes / (60 * 24);
    final recency = 1 / (1 + (days < 0 ? 0 : days) / 14);
    return fact.weight * recency;
  }

  /// 标记「这句用上了」：`last_used_at` 更新、`use_count + 1`。
  Future<void> markFactsUsed(
    String characterId,
    List<String> ids,
  ) async {
    for (final id in ids) {
      final row = await (db.select(db.memoryFacts)
            ..where(
              (t) => t.id.equals(id) & t.characterId.equals(characterId),
            ))
          .getSingleOrNull();
      if (row == null) continue;
      await (db.update(db.memoryFacts)..where((t) => t.id.equals(id))).write(
        MemoryFactsCompanion(
          useCount: Value(row.useCount + 1),
          lastUsedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  // -------------------------------------------------------------------------
  // episodes
  // -------------------------------------------------------------------------

  Future<List<MemoryEpisode>> recentEpisodes({
    required String characterId,
    int limit = 40,
  }) async {
    final rows = await (db.select(db.memoryEpisodes)
          ..where((t) => t.characterId.equals(characterId))
          ..orderBy(<OrderingTerm Function(MemoryEpisodes)>[
            (t) => OrderingTerm(
                  expression: t.createdAt,
                  mode: OrderingMode.desc,
                ),
          ])
          ..limit(limit))
        .get();
    return rows.map(_episodeOf).toList(growable: false);
  }

  MemoryEpisode _episodeOf(MemoryEpisodeRow row) {
    var turnIds = const <String>[];
    try {
      final decoded = jsonDecode(row.turnIdsJson);
      if (decoded is List) {
        turnIds = decoded.whereType<String>().toList(growable: false);
      }
    } catch (_) {
      turnIds = const <String>[];
    }
    return MemoryEpisode(
      id: row.id,
      sessionId: row.sessionId,
      summary: row.summary,
      salience: row.salience,
      turnIds: turnIds,
      valence: row.mood,
      createdAt: row.createdAt,
      lastUsedAt: row.lastUsedAt,
    );
  }

  Future<void> addEpisode({
    required String characterId,
    required String sessionId,
    required List<String> turnIds,
    required String summary,
    double? valence,
    double salience = 0.5,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    await db.into(db.memoryEpisodes).insert(
          MemoryEpisodesCompanion.insert(
            id: _uuid.v4(),
            characterId: Value(characterId),
            sessionId: Value(sessionId),
            turnIdsJson: Value(jsonEncode(turnIds)),
            summary: Value(summary),
            mood: Value(valence),
            salience: Value(clamp01(salience)),
            createdAt: Value(at),
          ),
        );
  }

  Future<void> markEpisodesUsed(
    String characterId,
    List<String> ids,
  ) async {
    for (final id in ids) {
      await (db.update(db.memoryEpisodes)
            ..where(
              (t) => t.id.equals(id) & t.characterId.equals(characterId),
            ))
          .write(
        MemoryEpisodesCompanion(lastUsedAt: Value(DateTime.now())),
      );
    }
  }

  // -------------------------------------------------------------------------
  // mood
  // -------------------------------------------------------------------------

  Future<MoodState?> mood(String characterId) async {
    final row = await (db.select(db.moodStates)
          ..where((t) => t.characterId.equals(characterId)))
        .getSingleOrNull();
    if (row == null) return null;
    return MoodState(
      name: row.name,
      valence: row.valence,
      affection: row.affection,
      energy: row.energy,
      updatedAt: row.updatedAt,
    );
  }

  /// 写入当前情绪 + 追加一条轨迹，并把轨迹裁剪到 [kMoodHistoryLimit] 条。
  Future<void> saveMood(
    String characterId,
    MoodState state, {
    required String reason,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    await db.into(db.moodStates).insertOnConflictUpdate(
          MoodStatesCompanion.insert(
            characterId: characterId,
            name: Value(state.name),
            valence: Value(state.valence),
            affection: Value(state.affection),
            energy: Value(state.energy),
            updatedAt: Value(at),
          ),
        );
    await db.into(db.moodHistory).insert(
          MoodHistoryCompanion.insert(
            characterId: Value(characterId),
            name: Value(state.name),
            valence: Value(state.valence),
            affection: Value(state.affection),
            energy: Value(state.energy),
            reason: Value(reason),
            createdAt: Value(at),
          ),
        );
    final rows = await (db.select(db.moodHistory)
          ..where((t) => t.characterId.equals(characterId))
          ..orderBy(<OrderingTerm Function(MoodHistory)>[
            (t) => OrderingTerm(expression: t.id, mode: OrderingMode.asc),
          ]))
        .get();
    final overflow = rows.length - kMoodHistoryLimit;
    if (overflow > 0) {
      final ids = <int>[for (var i = 0; i < overflow; i++) rows[i].id];
      await (db.delete(db.moodHistory)..where((t) => t.id.isIn(ids))).go();
    }
  }

  // -------------------------------------------------------------------------
  // persona
  // -------------------------------------------------------------------------

  Future<PersonaTraits> personaTraits(String characterId) async {
    final rows = await (db.select(db.personaTraitRows)
          ..where((t) => t.characterId.equals(characterId)))
        .get();
    if (rows.isEmpty) return PersonaTraits.baseline();
    final user = <String, double>{};
    final self = <String, double>{};
    DateTime? userUpdatedAt;
    DateTime? selfUpdatedAt;
    for (final row in rows) {
      if (row.side == 'self') {
        self[row.key] = row.value;
        if (selfUpdatedAt == null || row.updatedAt.isAfter(selfUpdatedAt)) {
          selfUpdatedAt = row.updatedAt;
        }
      } else {
        user[row.key] = row.value;
        if (userUpdatedAt == null || row.updatedAt.isAfter(userUpdatedAt)) {
          userUpdatedAt = row.updatedAt;
        }
      }
    }
    for (final key in kUserTraitKeys) {
      user.putIfAbsent(key, () => kDefaultUserBaseline[key] ?? 0.5);
    }
    for (final key in kSelfTraitKeys) {
      self.putIfAbsent(key, () => kDefaultSelfBaseline[key] ?? 0.5);
    }
    return PersonaTraits(
      user: user,
      self: self,
      userUpdatedAt: userUpdatedAt,
      selfUpdatedAt: selfUpdatedAt,
    );
  }

  /// 写回两侧倾向；值有变化的键 `hit_count + 1`。
  Future<void> savePersonaTraits(
    String characterId,
    PersonaTraits traits, {
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final existing = await (db.select(db.personaTraitRows)
          ..where((t) => t.characterId.equals(characterId)))
        .get();
    final hits = <String, int>{
      for (final row in existing) '${row.side}/${row.key}': row.hitCount,
    };
    Future<void> writeSide(
      String side,
      Map<String, double> values,
      Map<String, double> baseline,
    ) async {
      for (final entry in values.entries) {
        final key = '${side}/${entry.key}';
        final previous = existing.firstWhere(
          (row) => row.side == side && row.key == entry.key,
          orElse: () => PersonaTraitRow(
            characterId: characterId,
            side: side,
            key: entry.key,
            value: entry.value,
            baseline: baseline[entry.key] ?? 0.5,
            hitCount: 0,
            updatedAt: at,
          ),
        );
        final changed = (previous.value - entry.value).abs() > 1e-6;
        final hitCount = (hits[key] ?? previous.hitCount) + (changed ? 1 : 0);
        await db.into(db.personaTraitRows).insertOnConflictUpdate(
              PersonaTraitRowsCompanion.insert(
                characterId: Value(characterId),
                side: side,
                key: entry.key,
                value: Value(clamp01(entry.value)),
                baseline: Value(baseline[entry.key] ?? 0.5),
                hitCount: Value(hitCount),
                updatedAt: Value(at),
              ),
            );
      }
    }

    await writeSide('user', traits.user, kDefaultUserBaseline);
    await writeSide('self', traits.self, kDefaultSelfBaseline);
  }

  // -------------------------------------------------------------------------
  // 召回统计（v1 只统计）
  // -------------------------------------------------------------------------

  Future<void> recordInjected(
    String characterId,
    List<RecallItem> items, {
    DateTime? now,
  }) async {
    if (items.isEmpty) return;
    final at = now ?? DateTime.now();
    for (final item in items) {
      final row = await (db.select(db.memoryRecallStats)
            ..where(
              (t) =>
                  t.kind.equals(item.kind) &
                  t.memoryId.equals(item.id) &
                  t.characterId.equals(characterId),
            ))
          .getSingleOrNull();
      final injected = (row?.injected ?? 0) + 1;
      final used = row?.used ?? 0;
      final ignored = row?.ignored ?? 0;
      final usefulness = (used + 1) / (injected + 1);
      await db.into(db.memoryRecallStats).insertOnConflictUpdate(
            MemoryRecallStatsCompanion.insert(
              kind: item.kind,
              memoryId: item.id,
              characterId: Value(characterId),
              injected: Value(injected),
              used: Value(used),
              ignored: Value(ignored),
              usefulness: Value(clamp01(usefulness)),
              updatedAt: Value(at),
            ),
          );
    }
  }

  Future<void> recordUsed(
    String characterId,
    List<String> ids, {
    DateTime? now,
  }) async {
    if (ids.isEmpty) return;
    final at = now ?? DateTime.now();
    for (final id in ids) {
      final rows = await (db.select(db.memoryRecallStats)
            ..where(
              (t) => t.memoryId.equals(id) & t.characterId.equals(characterId),
            ))
          .get();
      for (final row in rows) {
        final used = row.used + 1;
        final usefulness = (used + 1) / (row.injected + 1);
        await (db.update(db.memoryRecallStats)
              ..where(
                (t) =>
                    t.kind.equals(row.kind) &
                    t.memoryId.equals(id) &
                    t.characterId.equals(characterId),
              ))
            .write(
          MemoryRecallStatsCompanion(
            used: Value(used),
            usefulness: Value(clamp01(usefulness)),
            updatedAt: Value(at),
          ),
        );
      }
    }
  }

  /// 某一轮之后的「用上了没有」：assistant 文本里出现命中词就算用上。
  Future<void> recordUsageFromReply(
    String characterId,
    Map<String, List<String>> termsById,
    String assistantText, {
    DateTime? now,
  }) async {
    if (termsById.isEmpty || assistantText.trim().isEmpty) return;
    final usedIds = <String>[];
    for (final entry in termsById.entries) {
      final mentioned = entry.value.any(
        (term) => term.length >= 2 && assistantText.contains(term),
      );
      if (mentioned) usedIds.add(entry.key);
    }
    if (usedIds.isEmpty) return;
    await recordUsed(characterId, usedIds, now: now);
    await markFactsUsed(characterId, usedIds);
    await markEpisodesUsed(characterId, usedIds);
  }

  // -------------------------------------------------------------------------
  // 召回候选（旧消息原文）
  // -------------------------------------------------------------------------

  /// 从 `messages` 里取**同一个角色**下的最近原文，供 bigram 召回。
  ///
  /// 通过 `sessions.character_id` 过滤：跨角色绝不召回。
  /// 只取 `user` / `assistant` 且无错误标记的消息；返回纯文本（去掉 blocks JSON）。
  Future<List<RecallCandidateTurn>> recallCandidates({
    required String characterId,
    String? sessionId,
    int limit = 800,
  }) async {
    if (characterId.trim().isEmpty) return const <RecallCandidateTurn>[];
    final scopedSession = (sessionId ?? '').trim();
    // 默认按「记忆域」召回：传了 sessionId 就只查本会话（不跨对话），
    // 没传才退化为角色级（兼容旧调用）。
    final sql = scopedSession.isEmpty
        ? 'SELECT m.id, m.role, m.content, m.created_at FROM messages m '
            'JOIN sessions s ON s.id = m.session_id '
            'WHERE s.character_id = ?1 AND m.role IN (\'user\', \'assistant\') '
            'ORDER BY m.created_at DESC LIMIT ?2'
        : 'SELECT m.id, m.role, m.content, m.created_at FROM messages m '
            'JOIN sessions s ON s.id = m.session_id '
            'WHERE s.character_id = ?1 AND m.session_id = ?3 '
            'AND m.role IN (\'user\', \'assistant\') '
            'ORDER BY m.created_at DESC LIMIT ?2';
    final rows = await db.customSelect(
      sql,
      variables: <Variable<Object>>[
        Variable<String>(characterId),
        Variable<int>(limit),
        if (scopedSession.isNotEmpty) Variable<String>(scopedSession),
      ],
      readsFrom: <ResultSetImplementation>{db.messages, db.sessions},
    ).get();
    if (rows.isEmpty) return const <RecallCandidateTurn>[];

    final stats = await (db.select(db.memoryRecallStats)
          ..where(
            (t) =>
                t.kind.equals('turn') &
                t.characterId.equals(characterId),
          ))
        .get();
    final usedById = <String, int>{
      for (final stat in stats) stat.memoryId: stat.used,
    };

    final result = <RecallCandidateTurn>[];
    for (final row in rows) {
      final content = row.read<String>('content');
      final role = row.read<String>('role');
      if (role != 'user' && role != 'assistant') continue;
      final text = messageText(content);
      if (text.isEmpty) continue;
      result.add(
        RecallCandidateTurn(
          messageId: row.read<String>('id'),
          role: role,
          text: text,
          createdAt: _secondsToDate(row.read<int>('created_at')),
          useCount: usedById[row.read<String>('id')] ?? 0,
        ),
      );
    }
    return result;
  }

  static DateTime _secondsToDate(int? seconds) => seconds == null
      ? DateTime.fromMillisecondsSinceEpoch(0)
      : DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

  /// 直接从消息内容里取正文（只取 text 块，跳过思考/搜索/附件）。
  static String messageText(String? content) {
    final blocks = blk.decodeBlocks(content);
    final parts = <String>[];
    for (final block in blocks) {
      if (block.type == blk.BlockType.text && block.plainText.isNotEmpty) {
        parts.add(block.plainText);
      }
    }
    return parts.join('\n').trim();
  }

  // -------------------------------------------------------------------------
  // 设置页：统计 / 清空 / 合并
  // -------------------------------------------------------------------------

  /// 统计。[characterId] 为空时统计全部角色。
  Future<BrainStats> stats({String? characterId}) async {
    final scoped = characterId != null && characterId.trim().isNotEmpty;
    final factQuery = db.select(db.memoryFacts);
    if (scoped) {
      factQuery.where((t) => t.characterId.equals(characterId));
    }
    final facts = await factQuery.get();
    final episodeQuery = db.select(db.memoryEpisodes);
    if (scoped) {
      episodeQuery.where((t) => t.characterId.equals(characterId));
    }
    final episodes = await episodeQuery.get();
    final moodRow = scoped ? await mood(characterId!) : null;
    var turnCount = 0;
    for (final episode in episodes) {
      // 生成列叫 `turnIdsJson`（纯文本 JSON），解析失败按 0 计。
      try {
        final decoded = jsonDecode(episode.turnIdsJson);
        if (decoded is List) turnCount += decoded.length;
      } catch (_) {
        // 坏数据不影响统计。
      }
    }
    return BrainStats(
      userFacts: facts.where((row) => row.side == 'user').length,
      selfFacts: facts.where((row) => row.side == 'self').length,
      episodes: episodes.length,
      moodName: moodRow?.name ?? '',
      consolidatedTurns: turnCount,
    );
  }

  /// 「清空记忆数据」：只清大脑表，不动 sessions / messages（原文全部保留）。
  ///
  /// [characterId] 为空时清**全部角色**（设置页会给二次确认）；
  /// 指定角色时只清那一个角色，别的角色一点不动。
  Future<void> clearAll({String? characterId}) async {
    final scoped = characterId != null && characterId.trim().isNotEmpty;
    await db.transaction(() async {
      if (!scoped) {
        await db.delete(db.memoryFacts).go();
        await db.delete(db.memoryEpisodes).go();
        await db.delete(db.memoryRecallStats).go();
        await db.delete(db.moodStates).go();
        await db.delete(db.moodHistory).go();
        await db.delete(db.personaTraitRows).go();
        return;
      }
      await (db.delete(db.memoryFacts)
            ..where((t) => t.characterId.equals(characterId)))
          .go();
      await (db.delete(db.memoryEpisodes)
            ..where((t) => t.characterId.equals(characterId)))
          .go();
      await (db.delete(db.memoryRecallStats)
            ..where((t) => t.characterId.equals(characterId)))
          .go();
      await (db.delete(db.moodStates)
            ..where((t) => t.characterId.equals(characterId)))
          .go();
      await (db.delete(db.moodHistory)
            ..where((t) => t.characterId.equals(characterId)))
          .go();
      await (db.delete(db.personaTraitRows)
            ..where((t) => t.characterId.equals(characterId)))
          .go();
    });
  }

  /// 把 [fromCharacterId] 的记忆并进 [toCharacterId]（角色卡合并用）。
  ///
  /// - 事实按相似度去重后合并（`mergeFacts`）；
  /// - episode / 召回统计 / 情绪轨迹直接改绑（并集）；
  /// - 情绪状态：目标没有才继承，有就以目标为准（避免两段情绪互相覆盖）；
  /// - 人格：目标缺的键才从源补；
  /// - 最后删掉源角色的所有记忆行（源卡随后由 `CharacterService` 删除）。
  Future<void> mergeIntoCharacter({
    required String fromCharacterId,
    required String toCharacterId,
  }) async {
    if (fromCharacterId.trim().isEmpty ||
        toCharacterId.trim().isEmpty ||
        fromCharacterId == toCharacterId) {
      return;
    }
    // 1) 事实：按 side 合并去重。
    for (final side in <String>['user', 'self']) {
      final facts = await factsOf(side, characterId: fromCharacterId);
      if (facts.isEmpty) continue;
      await mergeFacts(
        side,
        <FactCandidate>[
          for (final fact in facts)
            FactCandidate(text: fact.text, kind: side, weight: fact.weight),
        ],
        characterId: toCharacterId,
      );
    }
    await (db.delete(db.memoryFacts)
          ..where((t) => t.characterId.equals(fromCharacterId)))
        .go();

    // 2) episode / 召回统计 / 情绪轨迹：改绑成目标角色。
    await (db.update(db.memoryEpisodes)
          ..where((t) => t.characterId.equals(fromCharacterId)))
        .write(MemoryEpisodesCompanion(characterId: Value(toCharacterId)));
    await (db.update(db.memoryRecallStats)
          ..where((t) => t.characterId.equals(fromCharacterId)))
        .write(MemoryRecallStatsCompanion(characterId: Value(toCharacterId)));
    await (db.update(db.moodHistory)
          ..where((t) => t.characterId.equals(fromCharacterId)))
        .write(MoodHistoryCompanion(characterId: Value(toCharacterId)));

    // 3) 情绪状态：目标没有才继承。
    final targetMood = await mood(toCharacterId);
    if (targetMood == null) {
      final sourceMood = await mood(fromCharacterId);
      if (sourceMood != null) {
        await db.into(db.moodStates).insertOnConflictUpdate(
              MoodStatesCompanion.insert(
                characterId: toCharacterId,
                name: Value(sourceMood.name),
                valence: Value(sourceMood.valence),
                affection: Value(sourceMood.affection),
                energy: Value(sourceMood.energy),
                updatedAt: Value(sourceMood.updatedAt ?? DateTime.now()),
              ),
            );
      }
    }
    await (db.delete(db.moodStates)
          ..where((t) => t.characterId.equals(fromCharacterId)))
        .go();

    // 4) 人格：目标缺的键才补。
    final sourceTraits = await (db.select(db.personaTraitRows)
          ..where((t) => t.characterId.equals(fromCharacterId)))
        .get();
    final targetKeys = <String>{
      for (final row in await (db.select(db.personaTraitRows)
            ..where((t) => t.characterId.equals(toCharacterId)))
          .get())
        '${row.side}/${row.key}',
    };
    for (final row in sourceTraits) {
      if (targetKeys.contains('${row.side}/${row.key}')) continue;
      await db.into(db.personaTraitRows).insertOnConflictUpdate(
            PersonaTraitRowsCompanion.insert(
              characterId: Value(toCharacterId),
              side: row.side,
              key: row.key,
              value: Value(row.value),
              baseline: Value(row.baseline),
              hitCount: Value(row.hitCount),
              updatedAt: Value(row.updatedAt),
            ),
          );
    }
    await (db.delete(db.personaTraitRows)
          ..where((t) => t.characterId.equals(fromCharacterId)))
        .go();
  }
}
