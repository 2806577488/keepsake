/// Keepsake（留声）— 角色卡与「记忆隔离」的规则层。
///
/// 为什么要有角色卡：
/// - 用户从手机导入一堆历史对话，很多是**同一段关系 / 同一个话题换个对话接着聊**；
/// - 所以导入时默认**按话题聚类**，一个聚类 = 一张角色卡（不是每个会话一张）；
/// - 记忆、情绪、人格跟着角色走，**跨角色绝不召回**（见 `BrainStore`）。
///
/// 建卡**不调用 LLM**：全部本地规则，导入几千个会话也只是几次 INSERT。
/// 聚类算法在 `character_clustering.dart`（纯函数、可单测）。
library;

import 'package:drift/drift.dart';

import 'package:keepsake/core/brain/brain_store.dart';
import 'package:keepsake/core/db/database.dart';

import 'character_clustering.dart';

export 'character_clustering.dart';

/// 没有任何标题时的角色名。
const String kDefaultCharacterName = '未命名角色';

/// 默认头像（一个 emoji，纯文本落库，不引入图片资源）。
const String kDefaultCharacterEmoji = '🤖';

/// 角色来源：手动新建。
const String kCharacterSourceManual = 'manual';

/// 角色来源：导入历史对话自动生成。
const String kCharacterSourceImport = 'import';

/// 角色来源：老会话首次打开时补的默认卡。
const String kCharacterSourceDefault = 'default';

/// 默认人设模板（`{name}` 换成角色名；不写死具体性格，留给用户改）。
String defaultCharacterPrompt(String name, {List<String> topicTerms = const <String>[]}) {
  final who = name.trim().isEmpty ? kDefaultCharacterName : name.trim();
  final base = '你是「$who」，和用户长期聊天。'
      '保持这个身份的说话方式、性格和边界；'
      '不要自称 AI 模型，也不要把别的角色的经历和记忆混进来。';
  final terms = topicTerms.take(3).join('、');
  if (terms.isEmpty) return base;
  return '$base\n这个角色来自这些会话的共同话题：$terms；'
      '不确定时按这些话题的语境说话。';
}

/// 会话标题 → 角色名。
String characterNameFor(String? sessionTitle) {
  final title = (sessionTitle ?? '').trim();
  return title.isEmpty ? kDefaultCharacterName : title;
}

/// 这些标题不是「角色名」，只是会话状态/占位（导入时很常见）。
const Set<String> kGenericCardTitles = <String>{
  '未命名会话',
  '未命名',
  '新对话',
  '导入的对话',
  '导出的对话',
  '会话',
  '对话',
  'hello',
  'Hello',
  '你好',
  '测试',
};

/// 标题是否不适合当角色卡名（空、通用占位、状态句、纯数字、过长句子）。
bool isGenericCardTitle(String? name) {
  final title = (name ?? '').trim();
  if (title.isEmpty) return true;
  if (kGenericCardTitles.contains(title)) return true;
  if (RegExp(r'^\d+$').hasMatch(title)) return true;
  if (RegExp(r'^(未命名|新对话|会话|对话|导入的)').hasMatch(title)) return true;
  if (RegExp(r'(已开启|已关闭|已启用|已停用)').hasMatch(title)) return true;
  if (title.length > 24) return true;
  return false;
}

/// 聚类簇 → 角色卡名：优先非通用标题，其次主题词，最后「角色」。
String cardNameForCluster(SessionCluster cluster) {
  final title = cluster.title.trim();
  if (!isGenericCardTitle(title)) return title;
  final terms = <String>[
    for (final term in cluster.topicTerms)
      if (term.trim().length >= 2) term.trim(),
  ];
  if (terms.isNotEmpty) return terms.take(2).join(' · ');
  return '角色';
}

/// 首条 user 消息 → 角色简介（压成一行、`≤60 字`）。
String characterDescriptionFrom(String? firstUserText) {
  final flat = (firstUserText ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.isEmpty) return '';
  if (flat.length <= 60) return flat;
  return '${flat.substring(0, 59)}…';
}

/// 角色 + 会话数的展示行（设置页「角色卡」列表用）。
class CharacterSummary {
  const CharacterSummary({required this.card, this.sessionCount = 0});

  final CharacterRow card;
  final int sessionCount;

  String get name => card.name.trim().isEmpty ? kDefaultCharacterName : card.name;

  String get emoji =>
      card.emoji.trim().isEmpty ? kDefaultCharacterEmoji : card.emoji;

  String get title => '$emoji $name';
}

/// 角色卡读写 + 自动建卡规则。
class CharacterService {
  CharacterService(this.db);

  final AppDatabase db;

  BrainStore get _brain => BrainStore(db);

  // -------------------------------------------------------------------------
  // 单卡：读 / 建 / 绑
  // -------------------------------------------------------------------------

  /// 取会话的角色；没有就**按需建默认卡**并绑上。
  Future<CharacterRow> ensureForSession(
    String sessionId, {
    String source = kCharacterSourceDefault,
    String? description,
    String? name,
  }) async {
    final session = await db.sessionById(sessionId);
    final existingId = (session?.characterId ?? '').trim();
    if (existingId.isNotEmpty) {
      final existing = await db.characterById(existingId);
      if (existing != null) return existing;
    }
    final cardName = (name ?? '').trim().isNotEmpty
        ? name!.trim()
        : characterNameFor(session?.title);
    final card = await db.createCharacter(
      name: cardName,
      prompt: defaultCharacterPrompt(cardName),
      description: (description ?? '').trim().isEmpty ? null : description!.trim(),
      emoji: kDefaultCharacterEmoji,
      source: source,
    );
    if (session != null) {
      await db.setSessionCharacter(sessionId, card.id);
    }
    return card;
  }

  Future<List<CharacterSummary>> list() async {
    final cards = await db.allCharacters();
    final counts = await db.sessionCountsByCharacter();
    return <CharacterSummary>[
      for (final card in cards)
        CharacterSummary(card: card, sessionCount: counts[card.id] ?? 0),
    ];
  }

  /// 手动新建（设置页「新建角色」）。
  Future<CharacterRow> create({
    required String name,
    String? prompt,
    String? description,
    String? emoji,
  }) async {
    final cardName = characterNameFor(name);
    return db.createCharacter(
      name: cardName,
      prompt: (prompt ?? '').trim().isEmpty
          ? defaultCharacterPrompt(cardName)
          : prompt!.trim(),
      description: (description ?? '').trim().isEmpty ? null : description!.trim(),
      emoji: (emoji ?? '').trim().isEmpty ? kDefaultCharacterEmoji : emoji!.trim(),
      source: kCharacterSourceManual,
    );
  }

  Future<void> update({
    required String id,
    String? name,
    String? prompt,
    String? description,
    String? emoji,
  }) =>
      db.updateCharacter(
        id,
        name: (name ?? '').trim().isEmpty ? null : name!.trim(),
        prompt: prompt,
        description: description,
        emoji: (emoji ?? '').trim().isEmpty ? null : emoji!.trim(),
      );

  Future<String?> labelOfSession(String sessionId) async {
    final session = await db.sessionById(sessionId);
    final id = (session?.characterId ?? '').trim();
    if (id.isEmpty) return null;
    final card = await db.characterById(id);
    return card == null ? null : '${card.emoji.trim().isEmpty ? kDefaultCharacterEmoji : card.emoji} ${characterNameFor(card.name)}';
  }

  Future<String?> nameOfSession(String sessionId) async {
    final session = await db.sessionById(sessionId);
    final id = (session?.characterId ?? '').trim();
    if (id.isEmpty) return null;
    final card = await db.characterById(id);
    return card == null ? null : characterNameFor(card.name);
  }

  /// 把会话移到指定角色（设置页「把某会话移到另一张卡」）。
  Future<void> moveSessionToCharacter(String sessionId, String characterId) async {
    await db.setSessionCharacter(sessionId, characterId);
    await db.updateCharacter(characterId);
  }

  // -------------------------------------------------------------------------
  // 导入：按话题聚类建卡（三种模式）
  // -------------------------------------------------------------------------

  /// 从数据库读聚类用的会话摘要（标题 + 前 3 条 user + 首条 assistant）。
  ///
  /// 只在导入完成 / 重试后调用，读的是本地已落库的消息，不再解 ZIP。
  Future<List<SessionPreview>> previewsOf(List<String> sessionIds) async {
    final previews = <SessionPreview>[];
    for (final id in sessionIds) {
      final session = await db.sessionById(id);
      if (session == null) continue;
      final userRows = await (db.select(db.messages)
            ..where((t) => t.sessionId.equals(id) & t.role.equals('user'))
            ..orderBy(<OrderingTerm Function(Messages)>[
              (t) => OrderingTerm(expression: t.index, mode: OrderingMode.asc),
            ])
            ..limit(kClusterUserMessageLimit))
          .get();
      final assistantRow = await (db.select(db.messages)
            ..where((t) => t.sessionId.equals(id) & t.role.equals('assistant'))
            ..orderBy(<OrderingTerm Function(Messages)>[
              (t) => OrderingTerm(expression: t.index, mode: OrderingMode.asc),
            ])
            ..limit(1))
          .getSingleOrNull();
      previews.add(
        SessionPreview(
          sessionId: id,
          title: session.title,
          userTexts: <String>[
            for (final row in userRows) BrainStore.messageText(row.content),
          ].where((text) => text.isNotEmpty).toList(growable: false),
          assistantText:
              assistantRow == null ? '' : BrainStore.messageText(assistantRow.content),
          messageCount: session.messageCount,
        ),
      );
    }
    return previews;
  }

  /// 导入后：给这批**还没绑角色**的会话按模式建卡并绑定。
  ///
  /// - 已绑角色的会话一律跳过（重复导入不重复建卡）；
  /// - `autoCluster`：`clusterSessions` 聚类，一簇一张卡；
  /// - `singleCard`：全部并到一张卡（名字可指定）；
  /// - `perSession`：每个会话一张卡（老行为，不推荐）。
  ///
  /// 返回本次新建的角色卡数量。
  Future<int> assignCharactersForSessions(
    List<String> sessionIds, {
    CharacterImportMode mode = CharacterImportMode.autoCluster,
    String? singleCardName,
    double threshold = kClusterThreshold,
  }) async {
    final unbound = <String>[];
    for (final id in sessionIds) {
      final session = await db.sessionById(id);
      if (session == null) continue;
      final characterId = (session.characterId ?? '').trim();
      if (characterId.isNotEmpty) {
        final existing = await db.characterById(characterId);
        if (existing != null) continue;
      }
      unbound.add(id);
    }
    if (unbound.isEmpty) return 0;
    final previews = await previewsOf(unbound);
    if (previews.isEmpty) return 0;

    final existingNames = <String>{
      for (final card in await db.allCharacters()) card.name.trim(),
    };
    final created = <String>[];

    Future<String> createCard({
      required String name,
      String? description,
      List<String> topicTerms = const <String>[],
    }) async {
      final unique = _uniqueCharacterName(name, existingNames);
      existingNames.add(unique);
      final card = await db.createCharacter(
        name: unique,
        prompt: defaultCharacterPrompt(unique, topicTerms: topicTerms),
        description: description,
        emoji: kDefaultCharacterEmoji,
        source: kCharacterSourceImport,
      );
      created.add(card.id);
      return card.id;
    }

    Future<void> bind(List<String> ids, String characterId) async {
      for (final id in ids) {
        await db.setSessionCharacter(id, characterId);
      }
    }

    switch (mode) {
      case CharacterImportMode.autoCluster:
        final clusters = clusterSessions(previews, threshold: threshold);
        // 大簇先建卡，名字更可能是「主题名」。
        for (final cluster in clusters) {
          final cardId = await createCard(
            name: cardNameForCluster(cluster),
            description: cluster.description,
            topicTerms: cluster.topicTerms,
          );
          await bind(cluster.sessionIds, cardId);
        }
      case CharacterImportMode.singleCard:
        final base = (singleCardName ?? '').trim();
        final cardId = await createCard(
          name: base.isEmpty ? '导入的对话' : base,
          description: '${previews.length} 个会话',
        );
        await bind(<String>[for (final p in previews) p.sessionId], cardId);
      case CharacterImportMode.perSession:
        for (final preview in previews) {
          final cardId = await createCard(
            name: characterNameFor(preview.title),
            description: characterDescriptionFrom(
              preview.userTexts.isEmpty ? null : preview.userTexts.first,
            ),
          );
          await bind(<String>[preview.sessionId], cardId);
        }
    }
    return created.length;
  }

  /// 全局重跑一次聚类：把**所有还没绑角色**的老会话按话题补卡。
  Future<int> backfillUnboundSessions({double threshold = kClusterThreshold}) async {
    final rows = await db.allSessions();
    final ids = <String>[
      for (final row in rows)
        if ((row.characterId ?? '').trim().isEmpty) row.id,
    ];
    return assignCharactersForSessions(ids, threshold: threshold);
  }

  /// 把「未命名会话/状态句」这类通用角色名改成主题名（导入后调用一次）。
  Future<int> renameGenericCards() async {
    final cards = await db.allCharacters();
    final sessions = await db.allSessions();
    final byCharacter = <String, List<Session>>{};
    for (final session in sessions) {
      final id = (session.characterId ?? '').trim();
      if (id.isEmpty) continue;
      byCharacter.putIfAbsent(id, () => <Session>[]).add(session);
    }
    var renamed = 0;
    for (final card in cards) {
      if (!isGenericCardTitle(card.name)) continue;
      var next = '';
      for (final session in byCharacter[card.id] ?? const <Session>[]) {
        final title = session.title.trim();
        if (!isGenericCardTitle(title)) {
          next = title;
          break;
        }
      }
      if (next.isEmpty) next = '角色';
      await db.updateCharacter(card.id, name: next);
      renamed++;
    }
    return renamed;
  }

  // -------------------------------------------------------------------------
  // 合并 / 删除
  // -------------------------------------------------------------------------

  /// 把 [fromId] 合并进 [toId]：会话改绑 + 记忆/情绪/人格迁移去重，然后删源卡。
  Future<void> mergeCharacters(String fromId, String toId) async {
    if (fromId.isEmpty || toId.isEmpty || fromId == toId) return;
    final target = await db.characterById(toId);
    if (target == null) return;
    final source = await db.characterById(fromId);
    if (source == null) return;

    // 记忆层：事实合并去重、episode/情绪/人格迁移。
    await _brain.mergeIntoCharacter(fromCharacterId: fromId, toCharacterId: toId);

    // 会话改绑 + 删除源卡（deleteCharacter 会先把指向它的会话解绑）。
    final sessionIds = await db.sessionIdsOfCharacter(fromId);
    for (final id in sessionIds) {
      await db.setSessionCharacter(id, toId);
    }
    await db.deleteCharacter(fromId);
  }

  /// 删除角色卡。
  ///
  /// [deleteSessions] 为 true 时连同它的会话一起删；false 时只解绑会话
  /// （会话回到「未绑定」，下次打开会按需建默认卡）。
  /// 两种方式都会清掉这个角色的记忆/情绪/人格（只影响这一个角色）。
  Future<void> deleteCharacter(
    String id, {
    bool deleteSessions = false,
  }) async {
    if (id.isEmpty) return;
    final sessionIds = await db.sessionIdsOfCharacter(id);
    if (deleteSessions) {
      for (final sessionId in sessionIds) {
        await db.deleteSession(sessionId);
      }
    }
    await _brain.clearAll(characterId: id);
    // deleteCharacter 内部：会话 character_id 置 NULL + 删卡。
    await db.deleteCharacter(id);
  }

  /// 还没绑定（或绑到已删卡）的会话 id；导入后建卡/绑卡用。
  Future<List<String>> unboundSessionIds() async {
    final ids = <String>[];
    for (final session in await db.allSessions()) {
      final characterId = (session.characterId ?? '').trim();
      if (characterId.isEmpty) {
        ids.add(session.id);
        continue;
      }
      if (await db.characterById(characterId) == null) ids.add(session.id);
    }
    return ids;
  }

  /// 角色名去重：`名字`、`名字 2`、`名字 3`…
  static String _uniqueCharacterName(String raw, Set<String> used) {
    final base = characterNameFor(raw);
    if (!used.contains(base)) return base;
    var index = 2;
    while (used.contains('$base $index')) {
      index += 1;
    }
    return '$base $index';
  }
}
