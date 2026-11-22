/// Keepsake（留声）— 相关回忆的**可解释打分**（bigram + 关键词 + 时间衰减 + 使用次数）。
///
/// 语义对齐 `dsh-brain` 的 `recallOriginals` / `selectFacts` / `scoreEpisode`
/// （`src/memory.js`），但简化到「一次查询、几条结果」的量级：
/// - 相关度：中文 bigram 的 IDF 加权命中率（越少见的词越值钱）；
/// - 话题连续性：与最近 1–2 轮用户输入的 bigram 重叠，避免「继续」把无关旧事捞上来；
/// - 时间衰减：14 天半衰期（`1 / (1 + ageDays / 14)`）；
/// - 使用次数：被成功用过的记忆略微加权（v1 只统计，不参与训练）。
///
/// 相关度为 0 的候选一律丢弃：**宁可不召回，也不塞无关记忆**。
library;

import 'dart:math' as math;

import 'brain_types.dart';

/// 一条参与召回的旧消息（store 层从 `messages` 表读出来的纯数据）。
class RecallCandidateTurn {
  const RecallCandidateTurn({
    required this.messageId,
    required this.role,
    required this.text,
    required this.createdAt,
    this.useCount = 0,
  });

  final String messageId;

  /// `user` / `assistant`。
  final String role;

  final String text;
  final DateTime createdAt;

  /// 之前被召回后「用上」的次数（`memory_recall_stats.used`）。
  final int useCount;

  @override
  String toString() => 'RecallCandidateTurn($messageId, $role)';
}

/// 历史里混进来的「非对话噪声」前缀（DSH 采样行、agent 提示、归档占位）。
const List<String> kNoiseRecallPrefixes = <String>[
  'Time sampled while',
  'You are an AI agent',
  'Agent ',
  '[已归档到记忆库',
];

/// 这条候选是不是噪声（不该参与召回，也不该污染 IDF）。
///
/// 判据：`role == 'system'`，或者文本以 [kNoiseRecallPrefixes] 之一开头。
/// 这些行是采集/归档工具写进来的，人不会拿来聊天，召回只会污染工作记忆。
bool isNoiseRecallText(String? text, String? role) {
  if ((role ?? '').trim().toLowerCase() == 'system') return true;
  final value = (text ?? '').trimLeft();
  if (value.isEmpty) return false;
  for (final prefix in kNoiseRecallPrefixes) {
    if (value.startsWith(prefix)) return true;
  }
  return false;
}

/// 五个特征的归一化归因值（0..1），供召回自学习更新权重用。
Map<String, double> recallComponents({
  double relevance = 0,
  double salience = 0,
  double recency = 0,
  double topic = 0,
  double affection = 0,
}) =>
    <String, double>{
      'relevance': clamp01(relevance, 0),
      'salience': clamp01(salience, 0),
      'recency': clamp01(recency, 0),
      'topic': clamp01(topic, 0),
      'affection': clamp01(affection, 0),
    };

/// 相关度：query 的 bigram 在文本中的命中率（0..1，不做 IDF）。
double bigramRelevance(String query, String text) {
  final queryGrams = bigramsOf(query);
  if (queryGrams.isEmpty) return 0;
  final target = bigramsOf(text);
  if (target.isEmpty) return 0;
  var overlap = 0;
  for (final gram in queryGrams) {
    if (target.contains(gram)) overlap += 1;
  }
  return overlap / queryGrams.length;
}

double _recencyOf(DateTime? at, DateTime now) {
  if (at == null) return 0.5;
  final ageDays = now.difference(at).inMinutes / (60 * 24);
  final clamped = ageDays < 0 ? 0.0 : ageDays;
  return 1 / (1 + clamped / 14);
}

/// 从旧消息里召回原文片段。
///
/// - [query]：本轮输入 + 最近 1–2 轮用户输入拼接；
/// - [recentTexts]：最近两轮用户输入（只用于话题连续性）；
/// - [excludedMessageIds]：最近窗口内的消息（不参与召回，避免和上下文重复）；
/// - [featureWeights]：`relevance/topic/recency` 各自的乘性权重
///   （来自召回自学习；缺项用默认 1.0）；
/// - 只返回 `relevance > 0` 的候选，按综合分降序取前 [limit] 条。
List<RecalledTurn> recallTurns({
  required String query,
  required List<RecallCandidateTurn> candidates,
  String recentTexts = '',
  Set<String> excludedMessageIds = const <String>{},
  int limit = kRecallTurnLimit,
  int snippetChars = kRecallSnippetMaxChars,
  Map<String, double>? featureWeights,
  double affection = 0,
  DateTime? now,
}) {
  if (limit <= 0 || candidates.isEmpty) return const <RecalledTurn>[];
  final queryGrams = bigramsOf(query);
  if (queryGrams.isEmpty) return const <RecalledTurn>[];
  final at = now ?? DateTime.now();
  final weights = resolveRecallFeatureWeights(featureWeights);

  // 噪声行（system / 采样行 / 归档占位）先剔除：不参与 IDF、也不参与召回。
  final usable = <RecallCandidateTurn>[
    for (final turn in candidates)
      if (!isNoiseRecallText(turn.text, turn.role)) turn,
  ];
  if (usable.isEmpty) return const <RecalledTurn>[];

  // 每行一条「文档」算 IDF。
  final gramsByTurn = <String, Set<String>>{};
  final df = <String, int>{};
  for (final turn in usable) {
    final grams = bigramsOf('${turn.text} ${turn.role}');
    gramsByTurn[turn.messageId] = grams;
    for (final gram in grams) {
      df[gram] = (df[gram] ?? 0) + 1;
    }
  }
  final total = usable.length;
  final topicGrams = bigramsOf(recentTexts);
  final queryTokens = RegExp(r'[a-z0-9][a-z0-9_+.-]{1,23}')
      .allMatches(query.toLowerCase())
      .map((m) => m.group(0)!)
      .toList(growable: false);

  final scored = <RecalledTurn>[];
  for (final turn in usable) {
    if (excludedMessageIds.contains(turn.messageId)) continue;
    final text = turn.text.trim();
    if (text.isEmpty) continue;
    final grams = gramsByTurn[turn.messageId];
    if (grams == null || grams.isEmpty) continue;

    var idfScore = 0.0;
    var hits = 0;
    final matched = <String>[];
    for (final gram in queryGrams) {
      if (!grams.contains(gram)) continue;
      hits += 1;
      idfScore += _idf(gram, df, total);
      matched.add(gram);
    }
    if (hits == 0) continue;

    // 拉丁词 / 数字：作为独立关键词额外加权（它们不构成中文 bigram）。
    for (final token in queryTokens) {
      if (normalizeForMatch(text).contains(token)) {
        matched.add(token);
        idfScore += 0.8;
      }
    }

    var topicOverlap = 0.0;
    if (topicGrams.isNotEmpty) {
      var overlap = 0;
      for (final gram in topicGrams) {
        if (grams.contains(gram)) overlap += 1;
      }
      topicOverlap = overlap / (topicGrams.length < 20 ? topicGrams.length : 20);
    }

    // 只靠「继续 / 然后」这类通用词命中的旧消息不召回（除非本轮点名了具体主题）。
    final specificHit = matched.any((gram) => !kGenericBigrams.contains(gram));
    if (!specificHit && topicOverlap == 0) continue;

    final relevance = idfScore / (queryGrams.length < 12 ? queryGrams.length : 12);
    final recency = _recencyOf(turn.createdAt, at);
    final useBonus = turn.useCount > 0 ? 0.05 : 0.0;
    final relevanceNorm = relevance.clamp(0.0, 1.0);
    final topicNorm = topicOverlap.clamp(0.0, 1.0);
    // 各特征先乘自己的学习权重，再加权求和（默认权重 1.0 = 旧行为）。
    final score = relevanceNorm * 0.55 * weights['relevance']! +
        topicNorm * 0.20 * weights['topic']! +
        recency * 0.15 * weights['recency']! +
        useBonus;

    scored.add(
      RecalledTurn(
        messageId: turn.messageId,
        role: turn.role,
        snippet: _snippetOf(text, matched, snippetChars),
        createdAt: turn.createdAt,
        score: score,
        terms: matched.toSet().take(10).toList(growable: false),
        relevance: relevanceNorm,
        components: recallComponents(
          relevance: relevanceNorm,
          // 原文片段没有显式的「重要度」：被用过一次就更高。
          salience: turn.useCount > 0 ? 0.7 : 0.4,
          recency: recency,
          topic: topicNorm,
          affection: affection,
        ),
      ),
    );
  }
  scored.sort((a, b) => b.score.compareTo(a.score));
  return scored.take(limit).toList(growable: false);
}

double _idf(String gram, Map<String, int> df, int total) {
  final documentFrequency = df[gram] ?? 1;
  final value = 1 + total / (documentFrequency < 1 ? 1 : documentFrequency);
  return math.log(value);
}

/// 取命中关键词的那一段原文；没有命中段就取开头。`≤ snippetChars` 字。
String _snippetOf(String text, List<String> grams, int snippetChars) {
  final clauses = text.split(RegExp(r'[。！？!?\n\r]+'));
  String source = text.trim();
  for (final clause in clauses) {
    final raw = clause.trim();
    if (raw.isEmpty) continue;
    final normalized = normalizeForMatch(raw);
    if (grams.any(normalized.contains)) {
      source = raw;
      break;
    }
  }
  final flat = source.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.length <= snippetChars) return flat;
  return '${flat.substring(0, snippetChars - 1)}…';
}

/// 给「单条回忆」算一个是否值得注入的分数（供测试 / 调试）。
double recallScoreOf(RecalledTurn turn) => turn.score;

// ---------------------------------------------------------------------------
// facts / episodes 的选择
// ---------------------------------------------------------------------------

/// 事实类型在提示词里的优先级（与抽取权重分开：注入时更看类型）。
const Map<String, double> kFactKindPriority = <String, double>{
  'profile': 1,
  'promise': 0.85,
  'project': 0.8,
  'preference': 0.76,
  'style': 0.72,
  'memory': 0.7,
  'relation': 0.68,
  'event': 0.5,
  'other': 0.3,
};

/// 一条事实的打分（同时给「召回选择」和「自学习归因」用，保证口径一致）。
///
/// 事实这一路没有独立的「话题连续性」信号，所以 `topic` 权重在这里不参与；
/// `relevance` / `recency` 各自乘上学习权重（默认 1.0 = 旧行为）。
({double score, Map<String, double> components}) factScoreOf(
  MemoryFact fact,
  String query, {
  DateTime? now,
  Map<String, double>? featureWeights,
  double affection = 0,
}) {
  final weights = resolveRecallFeatureWeights(featureWeights);
  final at = now ?? DateTime.now();
  final relevance = clamp01(bigramRelevance(query, fact.text), 0);
  final recency = _recencyOf(fact.updatedAt ?? fact.createdAt, at);
  final priority = kFactKindPriority[_kindOf(fact)] ?? 0.3;
  final salience = clamp01(fact.weight, 0);
  final score = salience * 0.45 +
      relevance * 0.35 * weights['relevance']! +
      priority * 0.15 +
      recency * 0.05 * weights['recency']! +
      (fact.useCount > 0 ? 0.03 : 0.0);
  return (
    score: score,
    components: recallComponents(
      relevance: relevance,
      salience: salience,
      recency: recency,
      topic: priority,
      affection: affection,
    ),
  );
}

/// 按相关度 + 权重挑事实（一侧）。
List<MemoryFact> selectFacts(
  List<MemoryFact> facts,
  String query, {
  int limit = kRecallFactLimit,
  String? kindOf,
  Map<String, double>? featureWeights,
  double affection = 0,
  DateTime? now,
}) {
  if (facts.isEmpty || limit <= 0) return const <MemoryFact>[];
  final at = now ?? DateTime.now();
  final scored = <MapEntry<MemoryFact, double>>[];
  for (final fact in facts) {
    final result = factScoreOf(
      fact,
      query,
      now: at,
      featureWeights: featureWeights,
      affection: affection,
    );
    scored.add(MapEntry(fact, result.score));
  }
  scored.sort((a, b) => b.value.compareTo(a.value));
  return scored.take(limit).map((entry) => entry.key).toList(growable: false);
}

/// 事实类型从文本前缀猜（DB 表结构里没有 kind 列，v1 只保留 side/text）。
String _kindOf(MemoryFact fact) {
  final text = fact.text;
  if (text.startsWith('用户叫') || text.startsWith('用户是')) return 'profile';
  if (text.contains('答应') || text.contains('约好')) return 'promise';
  if (text.contains('在做') ||
      text.contains('开发') ||
      text.contains('项目') ||
      text.contains('准备')) {
    return 'project';
  }
  if (text.contains('喜欢') || text.contains('讨厌')) return 'preference';
  if (text.contains('偏好')) return 'style';
  if (text.contains('今天') || text.contains('明天') || text.contains('周末')) {
    return 'event';
  }
  if (text.contains('我们') || text.contains('关系')) return 'relation';
  return 'other';
}

/// 一条 episode 的打分（供选择与自学习归因共用）。
({double score, Map<String, double> components}) episodeScoreOf(
  MemoryEpisode episode,
  String query, {
  DateTime? now,
  Map<String, double>? featureWeights,
  double affection = 0,
}) {
  final weights = resolveRecallFeatureWeights(featureWeights);
  final at = now ?? DateTime.now();
  final relevance = clamp01(bigramRelevance(query, episode.summary), 0);
  final recency = _recencyOf(episode.createdAt, at);
  final salience = clamp01(episode.salience, 0);
  final score = relevance * 0.55 * weights['relevance']! +
      salience * 0.30 +
      recency * 0.15 * weights['recency']!;
  return (
    score: score,
    components: recallComponents(
      relevance: relevance,
      salience: salience,
      recency: recency,
      topic: relevance,
      affection: affection,
    ),
  );
}

/// 按相关度 + 重要度 + 新近度挑 episode（相关度为 0 直接丢）。
List<MemoryEpisode> selectEpisodes(
  List<MemoryEpisode> episodes,
  String query, {
  int limit = kRecallEpisodeLimit,
  Map<String, double>? featureWeights,
  double affection = 0,
  DateTime? now,
}) {
  if (episodes.isEmpty || limit <= 0) return const <MemoryEpisode>[];
  final at = now ?? DateTime.now();
  final scored = <MapEntry<MemoryEpisode, double>>[];
  for (final episode in episodes) {
    final result = episodeScoreOf(
      episode,
      query,
      now: at,
      featureWeights: featureWeights,
      affection: affection,
    );
    if (result.components['relevance']! <= 0) continue;
    scored.add(MapEntry(episode, result.score));
  }
  scored.sort((a, b) => b.value.compareTo(a.value));
  return scored.take(limit).map((entry) => entry.key).toList(growable: false);
}

/// 注入冷却：同一条记忆在 [kRecallCooldownTurns] 轮内不重复注入；
/// 本轮再次提到它的关键词时允许刷新。
class RecallCooldown {
  RecallCooldown();

  int _round = 0;
  final Map<String, int> _lastRoundById = <String, int>{};
  final Map<String, List<String>> _termsById = <String, List<String>>{};

  int get round => _round;

  /// 进入下一轮（每次组装请求前调用一次）。
  void nextRound() => _round += 1;

  /// 该 id 是否还在冷却期（且本轮没再被提到）。
  bool isCooling(String id, String query) {
    final last = _lastRoundById[id];
    if (last == null) return false;
    if (_round - last >= kRecallCooldownTurns) return false;
    final normalizedQuery = normalizeForMatch(query);
    if (normalizedQuery.isEmpty) return true;
    final terms = _termsById[id] ?? const <String>[];
    for (final term in terms) {
      if (term.length < 2) continue;
      if (normalizedQuery.contains(normalizeForMatch(term))) return false;
    }
    return true;
  }

  /// 记录本轮注入过的 id 与命中词。
  void markInjected(String id, List<String> terms) {
    _lastRoundById[id] = _round;
    _termsById[id] = List<String>.of(terms);
  }
}
