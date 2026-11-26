/// App 内实体层的**存储与检索**（v0.4.35，对应 dsh-brain 的 `createEntityStore`）。
///
/// 纯规则抽取在 `brain_entities.dart`（无 DB）；这里负责落库、关联原文、表意识槽位、
/// 激活扩散，以及"这一轮在说谁"的解析。
///
/// 隔离：所有查询都带 `characterId`——App 里一张角色卡 = 一个记忆域，实体不跨卡。
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import 'brain_entities.dart';

/// 一条要入库的消息（来自 chat 层的 user/assistant 文本）。
class IngestMessage {
  const IngestMessage({
    required this.messageId,
    required this.userText,
    this.assistantText = '',
    required this.at,
  });

  final String messageId;
  final String userText;
  final String assistantText;
  final DateTime at;
}

/// 一轮"在说谁"的解析结果。
typedef EntityResolution = ({
  List<EntityProfileView> profiles,
  bool viaFocus,
  List<EntityRelatedView> related,
});

class BrainEntityStore {
  BrainEntityStore(this._db);

  final AppDatabase _db;

  static const _uuid = Uuid();

  // -------------------------------------------------------------------------
  // 读
  // -------------------------------------------------------------------------

  Future<List<EntityRow>> listForCharacter(
    String characterId, {
    int limit = 500,
  }) {
    return (_db.select(_db.entities)
          ..where((t) => t.characterId.equals(characterId))
          ..orderBy(<OrderClauseGenerator<$EntitiesTable>>[
            (t) => OrderingTerm.desc(t.updatedAt),
          ])
          ..limit(limit))
        .get();
  }

  Future<EntityRow?> findByName(String characterId, String name) async {
    final target = normalizeEntityName(name);
    if (target.isEmpty) return null;
    for (final row in await listForCharacter(characterId)) {
      if (normalizeEntityName(row.name) == target) return row;
      for (final alias in _decodeAliases(row.aliasesJson)) {
        if (normalizeEntityName(alias) == target) return row;
      }
    }
    return null;
  }

  /// 本轮文本里出现的已知对象（长名优先）。
  Future<List<EntityRow>> resolveMentions(
    String characterId,
    String text, {
    int limit = 2,
  }) async {
    if (text.trim().isEmpty) return const <EntityRow>[];
    final hits = <({EntityRow entity, int length})>[];
    for (final row in await listForCharacter(characterId)) {
      final names = <String>[
        row.name,
        ..._decodeAliases(row.aliasesJson),
      ].where((name) => name.length >= 2);
      for (final name in names) {
        if (text.contains(name)) {
          hits.add((entity: row, length: name.length));
          break;
        }
      }
    }
    hits.sort((left, right) => right.length.compareTo(left.length));
    return hits.take(limit).map((hit) => hit.entity).toList(growable: false);
  }

  /// 跟这些对象一起出现过的其他对象（同一段对话里共同出现 = 有牵连）。
  Future<List<EntityRelatedView>> related(
    String characterId,
    List<String> activeIds, {
    int limit = 3,
  }) async {
    if (activeIds.isEmpty) return const <EntityRelatedView>[];
    final active = activeIds.toSet().toList(growable: false);
    final mine = await (_db.select(_db.entityTurns)
          ..where(
            (t) => t.characterId.equals(characterId) & t.entityId.isIn(active),
          ))
        .get();
    final messageIds = mine.map((row) => row.messageId).toSet().toList();
    if (messageIds.isEmpty) return const <EntityRelatedView>[];
    final others = await (_db.select(_db.entityTurns)
          ..where(
            (t) =>
                t.characterId.equals(characterId) &
                t.messageId.isIn(messageIds) &
                t.entityId.isNotIn(active),
          ))
        .get();
    final counts = <String, int>{};
    for (final row in others) {
      counts[row.entityId] = (counts[row.entityId] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    final result = <EntityRelatedView>[];
    for (final entry in sorted.take(limit)) {
      final entity = await (_db.select(_db.entities)
            ..where((t) => t.id.equals(entry.key)))
          .getSingleOrNull();
      if (entity == null) continue;
      result.add(
        EntityRelatedView(name: entity.name, reason: '和当前对象在同一段对话里出现过'),
      );
    }
    return result;
  }

  Future<EntityProfileView?> profile({
    required String characterId,
    required String entityId,
    int factLimit = 6,
    int turnLimit = 3,
  }) async {
    final entity = await (_db.select(_db.entities)
          ..where((t) => t.id.equals(entityId)))
        .getSingleOrNull();
    if (entity == null || entity.characterId != characterId) return null;
    final facts = await (_db.select(_db.entityFacts)
          ..where((t) => t.entityId.equals(entityId))
          ..orderBy(<OrderClauseGenerator<$EntityFactsTable>>[
            (t) => OrderingTerm.desc(t.createdAt),
          ])
          ..limit(factLimit))
        .get();
    final turns = await (_db.select(_db.entityTurns)
          ..where((t) => t.entityId.equals(entityId))
          ..orderBy(<OrderClauseGenerator<$EntityTurnsTable>>[
            (t) => OrderingTerm.desc(t.at),
          ])
          ..limit(turnLimit))
        .get();
    return EntityProfileView(
      name: entity.name,
      kindLabel: kindLabelOf(entity.kind),
      facts: <EntityFactView>[
        for (final row in facts)
          EntityFactView(
            kind: row.kind,
            text: row.factText,
            at: _iso(row.createdAt),
          ),
      ],
      turns: <EntityTurnView>[
        for (final row in turns)
          EntityTurnView(text: row.snippet, at: _iso(row.at)),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // 写（幂等）
  // -------------------------------------------------------------------------

  Future<EntityRow> upsert({
    required String characterId,
    required String kind,
    required String name,
  }) async {
    final clean = name.trim();
    final existing = await findByName(characterId, clean);
    final now = DateTime.now();
    if (existing != null) {
      await (_db.update(_db.entities)..where((t) => t.id.equals(existing.id)))
          .write(EntitiesCompanion(updatedAt: Value(now), lastSeenAt: Value(now)));
      return existing;
    }
    final row = EntityRow(
      id: _uuid.v4(),
      characterId: characterId,
      kind: kind.trim().isEmpty ? 'person' : kind.trim(),
      name: clean,
      aliasesJson: '[]',
      createdAt: now,
      updatedAt: now,
      lastSeenAt: now,
    );
    await _db.into(_db.entities).insert(row);
    return row;
  }

  Future<void> linkTurn({
    required String characterId,
    required String entityId,
    required String messageId,
    required DateTime at,
    String snippet = '',
  }) async {
    await _db.into(_db.entityTurns).insert(
          EntityTurnRow(
            characterId: characterId,
            entityId: entityId,
            messageId: messageId,
            snippet: flattenText(snippet, maxChars: 80),
            at: at,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  /// 加一条要点（同文本去重；白名单外的 kind 落「备注」）。
  Future<bool> addFact({
    required String characterId,
    required String entityId,
    required String kind,
    required String text,
    DateTime? at,
  }) async {
    final value = flattenText(text, maxChars: 120);
    if (value.isEmpty) return false;
    final existing = await (_db.select(_db.entityFacts)
          ..where((t) => t.entityId.equals(entityId) & t.factText.equals(value))
          ..limit(1))
        .getSingleOrNull();
    if (existing != null) return false;
    await _db.into(_db.entityFacts).insert(
          EntityFactRow(
            id: _uuid.v4(),
            characterId: characterId,
            entityId: entityId,
            kind: kEntityFactKinds.contains(kind) ? kind : '备注',
            factText: value,
            createdAt: at ?? DateTime.now(),
          ),
        );
    return true;
  }

  /// 睡眠期结构化巩固：把模型抽出的字段写进档案（只认已知对象，同文本去重）。
  Future<int> applyExtraction({
    required String characterId,
    required String name,
    required List<ExtractedFact> facts,
  }) async {
    final entity = await findByName(characterId, name);
    if (entity == null) return 0;
    var created = 0;
    for (final fact in facts) {
      final ok = await addFact(
        characterId: characterId,
        entityId: entity.id,
        kind: fact.kind,
        text: fact.text,
      );
      if (ok) created += 1;
    }
    return created;
  }

  // -------------------------------------------------------------------------
  // 表意识槽位（"眼下在说谁"）
  // -------------------------------------------------------------------------

  Future<void> rememberFocus(
    String characterId,
    String sessionId,
    List<String> ids,
  ) async {
    final now = DateTime.now();
    final clean = ids.where((id) => id.isNotEmpty).take(3).toList(growable: false);
    await _db.into(_db.brainWmState).insertOnConflictUpdate(
          BrainWmStateRow(
            characterId: characterId,
            sessionId: sessionId,
            dataJson: jsonEncode(<String, Object?>{
              'ids': clean,
              'at': now.toIso8601String(),
            }),
            updatedAt: now,
          ),
        );
  }

  Future<List<EntityRow>> focusEntities(
    String characterId,
    String sessionId, {
    Duration ttl = const Duration(minutes: 30),
  }) async {
    // 非正 TTL 表示"焦点一律不算数"（等价于关闭槽位）。
    if (ttl <= Duration.zero) return const <EntityRow>[];
    final row = await (_db.select(_db.brainWmState)
          ..where((t) => t.sessionId.equals(sessionId)))
        .getSingleOrNull();
    if (row == null || row.characterId != characterId) return const <EntityRow>[];
    final decoded = _decodeJson(row.dataJson);
    if (decoded == null) return const <EntityRow>[];
    final ids = (decoded['ids'] as List?)?.cast<String>() ?? const <String>[];
    final at = DateTime.tryParse(decoded['at']?.toString() ?? '');
    if (at == null || DateTime.now().difference(at) > ttl) {
      return const <EntityRow>[];
    }
    final result = <EntityRow>[];
    for (final id in ids) {
      final entity = await (_db.select(_db.entities)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (entity != null) result.add(entity);
    }
    return result;
  }

  /// 本轮「在说谁」的完整解析：点名优先 → 焦点兜底 → 相关对象（激活扩散）。
  Future<EntityResolution> resolveForTurn({
    required String characterId,
    required String sessionId,
    required String text,
    int limit = 2,
    int factLimit = 6,
    int turnLimit = 3,
    Duration ttl = const Duration(minutes: 30),
    bool spread = true,
  }) async {
    var entities = await resolveMentions(characterId, text, limit: limit);
    var viaFocus = false;
    if (entities.isNotEmpty) {
      await rememberFocus(
        characterId,
        sessionId,
        entities.map((entity) => entity.id).toList(growable: false),
      );
    } else {
      entities = await focusEntities(characterId, sessionId, ttl: ttl);
      viaFocus = entities.isNotEmpty;
    }
    final profiles = <EntityProfileView>[];
    for (final entity in entities.take(limit)) {
      final view = await profile(
        characterId: characterId,
        entityId: entity.id,
        factLimit: factLimit,
        turnLimit: turnLimit,
      );
      if (view != null) profiles.add(view);
    }
    var relatedViews = const <EntityRelatedView>[];
    if (spread && entities.isNotEmpty) {
      relatedViews = await related(
        characterId,
        entities.map((entity) => entity.id).toList(growable: false),
      );
    }
    return (profiles: profiles, viaFocus: viaFocus, related: relatedViews);
  }

  // -------------------------------------------------------------------------
  // 后台消化：从消息里抽对象 + 建关联
  // -------------------------------------------------------------------------

  /// 两类都挂：
  /// 1. 本轮**新出现**的对象（「患者张三…」）；
  /// 2. 本轮**只提到名字**的既有对象（「张三复诊…」）——这才是"接着上次说"。
  Future<({int created, int links})> ingestMessages({
    required String characterId,
    required String sessionId,
    required List<IngestMessage> messages,
  }) async {
    var created = 0;
    var links = 0;
    for (final message in messages) {
      final combined = '${message.userText}\n${message.assistantText}';
      if (combined.trim().isEmpty) continue;
      final handled = <String>{};

      Future<void> handle(EntityRow entity) async {
        if (!handled.add(entity.id)) return;
        links += 1;
        await linkTurn(
          characterId: characterId,
          entityId: entity.id,
          messageId: message.messageId,
          at: message.at,
          snippet: message.userText,
        );
        await addFact(
          characterId: characterId,
          entityId: entity.id,
          kind: '备注',
          text: message.userText,
          at: message.at,
        );
      }

      for (final candidate in extractEntityCandidates(combined)) {
        final before = await findByName(characterId, candidate.name);
        final entity = await upsert(
          characterId: characterId,
          kind: candidate.kind,
          name: candidate.name,
        );
        if (before == null) created += 1;
        await handle(entity);
      }
      for (final entity in await resolveMentions(characterId, combined, limit: 5)) {
        await handle(entity);
      }
    }
    return (created: created, links: links);
  }

  // -------------------------------------------------------------------------
  // 小工具
  // -------------------------------------------------------------------------

  static List<String> _decodeAliases(String raw) {
    final decoded = _decodeJson(raw);
    final list = decoded?['aliases'];
    if (list is List) return list.map((item) => item.toString()).toList();
    // 兼容逗号分隔的老格式
    return raw.split(',').map((item) => item.trim()).where((item) => item.isNotEmpty).toList();
  }

  static Map<String, dynamic>? _decodeJson(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // 不是 JSON：返回 null，由调用方回退
    }
    return null;
  }

  static String? _iso(DateTime? value) => value?.toIso8601String();
}
