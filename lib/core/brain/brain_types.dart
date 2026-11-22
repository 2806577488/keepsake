/// Keepsake（留声）— App 内「自带大脑」的共享类型与纯文本工具。
///
/// 设计原则（与 DSH 插件 `dsh-brain` 的**功能对齐**，不是搬代码）：
/// - **不依赖 DSH、不依赖电脑**：全部是纯 Dart + 本机 drift；
/// - 原文永远以 `messages.content` 为准，本模块只做「整理 / 召回 / 注入」，
///   不截断、不删除任何原文；
/// - 打分只用可解释的**中文 bigram + 关键词 + 时间衰减 + 使用次数**，
///   不引入向量库或新依赖；
/// - 任何一层失败都静默（降级成普通聊天），绝不阻塞主链路。
///
/// 本文件只放常量、数据模型和纯函数，方便单测直接调用（不碰 Flutter 绑定）。
library;

// ---------------------------------------------------------------------------
// 默认预算 / 阈值（设置页只暴露三个开关，细项用这里的默认值）
// ---------------------------------------------------------------------------

/// 「工作记忆」单次注入的字符预算（脱敏后约 400–600 汉字）。
const int kDefaultRecallMaxChars = 1200;

/// 每 N 轮做一次后台整理（摘要 episode + 事实合并）。
const int kDefaultConsolidateEveryTurns = 3;

/// system prompt 的总注入预算（默认提示词 + 人格/情绪 + 回忆）。
/// 超出时**优先砍回忆**，其次砍情绪/人格句，绝不改用户的系统提示词。
const int kDefaultSystemInjectMaxChars = 4000;

/// 单条原文召回片段的字符上限。
const int kRecallSnippetMaxChars = 120;

/// 一条 episode 摘要的字符上限（`≤160 字`）。
const int kEpisodeSummaryMaxChars = 160;

/// 一条事实文本的字符上限。
const int kFactTextMaxChars = 60;

/// 每侧事实的条数上限（超出按权重 × 新近度淘汰）。
const int kMaxFactsPerSide = 120;

/// 同一条记忆的注入冷却轮数（3 轮内不重复注入）。
const int kRecallCooldownTurns = 3;

/// 每次召回最多注入几条原文片段。
const int kRecallTurnLimit = 2;

/// 每次召回最多注入几条事实。
const int kRecallFactLimit = 4;

/// 每次召回最多注入几条 episode。
const int kRecallEpisodeLimit = 2;

/// 噪声 bigram：只表达「接着聊 / 泛泛而谈」，不足以证明相关。
///
/// 这些二元组在 [bigramsOf] 里直接**过滤掉**（查询侧与文档侧同时过滤），
/// 否则「继续 / 问题 / 时候」这类高频词会把无关旧事捞上来，也会让
/// `bigramRelevance` 虚高。列表只收「单独出现时没有信息量」的词。
const Set<String> kGenericBigrams = <String>{
  '继续',
  '然后',
  '还有',
  '好的',
  '嗯嗯',
  '这个',
  '那个',
  '怎么',
  '什么',
  '可以',
  '现在',
  '开始',
  '一下',
  '我们',
  '你们',
  '一个',
  '就是',
  '不是',
  '上下',
  '下文',
  '上面',
  '下面',
  '我的',
  '你的',
  '不会',
  '一轮',
  '一句',
  '两句',
  '说到',
  '看到',
  '想到',
  '时候',
  '东西',
  '问题',
};

// ---------------------------------------------------------------------------
// 纯文本工具（全模块共用；单测直接断言这些函数）
// ---------------------------------------------------------------------------

/// 0..1 夹取（NaN 用 [fallback]）。
double clamp01(double value, [double fallback = 0.5]) {
  if (value.isNaN) return fallback;
  if (value < 0) return 0;
  if (value > 1) return 1;
  return value;
}

final RegExp _nonWord = RegExp(r'[\s\p{P}\p{S}]', unicode: true);

/// 归一化（只用于相似度 / 召回比较）：小写 + 去掉空白与标点符号。
String normalizeForMatch(String? text) =>
    (text ?? '').toLowerCase().replaceAll(_nonWord, '');

/// 取字符二元组集合（中文短文本的轻量「词袋」）。
///
/// **噪声 bigram（[kGenericBigrams]）在这里统一剔除**：只表达「接着聊」的
/// 二元组没有区分度，留着只会把无关旧事捞上来。文档侧与查询侧口径一致，
/// 所以 `bigramRelevance` / `textSimilarity` 的分母也一起变小、更可信。
Set<String> bigramsOf(String? text) {
  final value = normalizeForMatch(text);
  final grams = <String>{};
  for (var i = 0; i + 1 < value.length; i++) {
    final gram = value.substring(i, i + 2);
    if (kGenericBigrams.contains(gram)) continue;
    grams.add(gram);
  }
  return grams;
}

// ---------------------------------------------------------------------------
// 召回自学习的特征权重（纯常量 + 纯函数；持久化在 recall_learning.dart）
// ---------------------------------------------------------------------------

/// 可学习的五个召回特征（顺序即 JSON 里的键顺序）。
const List<String> kRecallFeatures = <String>[
  'relevance',
  'salience',
  'recency',
  'topic',
  'affection',
];

/// 权重默认值（未学习过的特征）。
const double kRecallWeightDefault = 1.0;

/// 权重的地板 / 天花板：学坏也要留住最基本的判断力。
const double kRecallWeightFloor = 0.5;
const double kRecallWeightCeiling = 1.5;

/// 把权重夹到 `[0.5, 1.5]`（NaN 回落到默认值）。
double clampRecallWeight(double value) {
  if (value.isNaN) return kRecallWeightDefault;
  if (value < kRecallWeightFloor) return kRecallWeightFloor;
  if (value > kRecallWeightCeiling) return kRecallWeightCeiling;
  return value;
}

/// 把「可能缺项 / 可能越界」的外部权重表补全成五个特征的完整表，
/// 缺项用 [kRecallWeightDefault]，越界值夹取。
Map<String, double> resolveRecallFeatureWeights(Map<String, double>? raw) {
  final result = <String, double>{};
  for (final feature in kRecallFeatures) {
    final value = raw?[feature];
    result[feature] = clampRecallWeight(value ?? kRecallWeightDefault);
  }
  return result;
}

/// 两条文本的相似度（Dice 系数，0..1）。`≥ 0.8` 视为同一条事实。
double textSimilarity(String a, String b) {
  final left = normalizeForMatch(a);
  final right = normalizeForMatch(b);
  if (left.isEmpty || right.isEmpty) return 0;
  if (left == right) return 1;
  if (left.length >= 4 &&
      right.length >= 4 &&
      (left.contains(right) || right.contains(left))) {
    return 0.85;
  }
  final leftGrams = bigramsOf(left);
  final rightGrams = bigramsOf(right);
  if (leftGrams.isEmpty || rightGrams.isEmpty) return 0;
  var overlap = 0;
  for (final gram in leftGrams) {
    if (rightGrams.contains(gram)) overlap += 1;
  }
  return 2 * overlap / (leftGrams.length + rightGrams.length);
}

/// 压成一行并限长（超长用 `…` 收尾）。
String oneLine(String text, int maxChars) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.length <= maxChars) return flat;
  return '${flat.substring(0, maxChars - 1)}…';
}

/// 召回来源的时间标签：`11-21 14:30`（只到分钟，不暴露秒/时区）。
String timeLabel(DateTime at) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}';
}

/// 召回来源的消息 id 标签：`#a1b2c3d4`。
String messageLabel(String messageId) {
  final id = messageId.trim();
  if (id.isEmpty) return '#???';
  return '#${id.length <= 8 ? id : id.substring(0, 8)}';
}

/// 启动时的默认大脑配置（设置页三个开关会覆盖 enabled 位）。
class BrainConfig {
  const BrainConfig({
    this.memoryEnabled = true,
    this.moodEnabled = true,
    this.personaEnabled = true,
    this.consolidateEveryTurns = kDefaultConsolidateEveryTurns,
    this.recallMaxChars = kDefaultRecallMaxChars,
    this.systemInjectMaxChars = kDefaultSystemInjectMaxChars,
    this.recallSnippetChars = kRecallSnippetMaxChars,
    this.recallTurnLimit = kRecallTurnLimit,
    this.recallFactLimit = kRecallFactLimit,
    this.recallEpisodeLimit = kRecallEpisodeLimit,
  });

  /// 记忆与回忆（关掉后退化成普通聊天，也不做后台整理）。
  final bool memoryEnabled;

  /// 情绪（关掉后不注入心情、也不更新情绪表）。
  final bool moodEnabled;

  /// 人格（关掉后不注入表达倾向、也不收集倾向）。
  final bool personaEnabled;

  /// 每 N 轮整理一次。
  final int consolidateEveryTurns;

  /// 回忆注入预算（字符）。
  final int recallMaxChars;

  /// system prompt 总注入预算（字符）。
  final int systemInjectMaxChars;

  /// 单条原文片段上限（字符）。
  final int recallSnippetChars;

  final int recallTurnLimit;
  final int recallFactLimit;
  final int recallEpisodeLimit;

  bool get anyEnabled => memoryEnabled || moodEnabled || personaEnabled;

  BrainConfig copyWith({
    bool? memoryEnabled,
    bool? moodEnabled,
    bool? personaEnabled,
    int? consolidateEveryTurns,
    int? recallMaxChars,
    int? systemInjectMaxChars,
    int? recallSnippetChars,
    int? recallTurnLimit,
    int? recallFactLimit,
    int? recallEpisodeLimit,
  }) =>
      BrainConfig(
        memoryEnabled: memoryEnabled ?? this.memoryEnabled,
        moodEnabled: moodEnabled ?? this.moodEnabled,
        personaEnabled: personaEnabled ?? this.personaEnabled,
        consolidateEveryTurns:
            consolidateEveryTurns ?? this.consolidateEveryTurns,
        recallMaxChars: recallMaxChars ?? this.recallMaxChars,
        systemInjectMaxChars: systemInjectMaxChars ?? this.systemInjectMaxChars,
        recallSnippetChars: recallSnippetChars ?? this.recallSnippetChars,
        recallTurnLimit: recallTurnLimit ?? this.recallTurnLimit,
        recallFactLimit: recallFactLimit ?? this.recallFactLimit,
        recallEpisodeLimit: recallEpisodeLimit ?? this.recallEpisodeLimit,
      );

  @override
  String toString() =>
      'BrainConfig(memory=$memoryEnabled, mood=$moodEnabled, '
      'persona=$personaEnabled, every=$consolidateEveryTurns, '
      'recall=$recallMaxChars)';
}

// ---------------------------------------------------------------------------
// 数据模型（与 drift 表一一对应；store 层负责搬运）
// ---------------------------------------------------------------------------

/// 一条结构化事实（`memory_facts` 一行）。
class MemoryFact {
  const MemoryFact({
    required this.id,
    required this.side,
    required this.text,
    required this.weight,
    this.createdAt,
    this.updatedAt,
    this.lastUsedAt,
    this.useCount = 0,
  });

  final String id;

  /// `user`（关于用户）/ `self`（关于助手自己）。
  final String side;

  final String text;

  /// 0..1，越大越可信 / 越重要。
  final double weight;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastUsedAt;
  final int useCount;

  @override
  String toString() => 'MemoryFact($side, $text, w=$weight)';
}

/// 抽取出来的候选事实（还没落库）。
class FactCandidate {
  const FactCandidate({
    required this.text,
    required this.kind,
    required this.weight,
  });

  final String text;
  final String kind;
  final double weight;
}

/// 一条情节记忆（`memory_episodes` 一行）。
class MemoryEpisode {
  const MemoryEpisode({
    required this.id,
    required this.sessionId,
    required this.summary,
    required this.salience,
    this.turnIds = const <String>[],
    this.valence,
    this.createdAt,
    this.lastUsedAt,
  });

  final String id;
  final String sessionId;

  /// `≤160 字`的中文小摘要。
  final String summary;

  /// 0..1 重要度。
  final double salience;

  /// 涉及的原文消息 id（指针，原文仍在 `messages` 里）。
  final List<String> turnIds;

  /// 当时的用户心情值（`mood_history` 的 valence，可空）。
  final double? valence;

  final DateTime? createdAt;
  final DateTime? lastUsedAt;

  @override
  String toString() => 'MemoryEpisode($id, ${summary.length} chars)';
}

/// 从旧消息里召回到的一条原文片段。
class RecalledTurn {
  const RecalledTurn({
    required this.messageId,
    required this.role,
    required this.snippet,
    required this.createdAt,
    required this.score,
    this.terms = const <String>[],
    this.relevance = 0,
    this.components = const <String, double>{},
  });

  final String messageId;

  /// `user` / `assistant`。
  final String role;

  /// `≤120 字`的原文片段（不是摘要）。
  final String snippet;

  final DateTime createdAt;

  /// 综合分（相关度 + 时间衰减 + 使用次数）。
  final double score;

  /// 命中的 bigram / 关键词（脱敏渲染用）。
  final List<String> terms;

  final double relevance;

  /// 五个特征的归一化值（`relevance/salience/recency/topic/affection`），
  /// 只用于「召回自学习」的归因，不参与渲染。
  final Map<String, double> components;

  @override
  String toString() => 'RecalledTurn($messageId, ${score.toStringAsFixed(2)})';
}

/// 注入到 system prompt 的一条「相关回忆」。
class RecallItem {
  const RecallItem({
    required this.kind,
    required this.id,
    required this.line,
    this.terms = const <String>[],
  });

  /// `turn` / `fact` / `episode`（也是 `memory_recall_stats.kind`）。
  final String kind;

  final String id;

  /// 渲染好的一行（不含 `- ` 前缀）。
  final String line;

  final List<String> terms;

  int get chars => line.length;

  @override
  String toString() => 'RecallItem($kind, $id)';
}

/// 一次「准备注入」的结果。
class BrainInjection {
  const BrainInjection({
    this.text = '',
    this.items = const <RecallItem>[],
    this.moodLine = '',
    this.personaLine = '',
    this.recallChars = 0,
    this.dropped = 0,
  });

  /// 要追加到 system prompt 末尾的整段文本（空串表示不注入）。
  final String text;

  /// 回忆条目（用于统计 injected / used）。
  final List<RecallItem> items;

  /// 「当前心情」那一句（关掉情绪层时为空）。
  final String moodLine;

  /// 「表达倾向」那一句（关掉人格层时为空）。
  final String personaLine;

  /// 回忆部分实际占用字符数。
  final int recallChars;

  /// 因预算被砍掉的条目数。
  final int dropped;

  bool get isEmpty => text.trim().isEmpty;

  @override
  String toString() =>
      'BrainInjection(${items.length} items, $recallChars chars)';
}
