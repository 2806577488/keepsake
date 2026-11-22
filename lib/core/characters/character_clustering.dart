/// Keepsake（留声）— 导入会话的**话题聚类**（纯函数，可单测，不碰 UI/DB）。
///
/// 为什么需要：用户手机里往往有几百上千个历史对话，很多是**同一段关系 / 同一个话题
/// 换了个对话继续聊**。按「每个会话一张角色卡」会生成一大堆重复卡，反而毁掉记忆隔离
/// 的意义——所以导入时默认按话题聚类，**一个聚类 = 一张角色卡**。
///
/// 算法（离线、确定性、可解释）：
/// 1. 文本归一化：去标点 / 空白 / 日期 / 「新对话」「未命名」这类噪声词；
/// 2. 特征：
///    - 标题 bigram（权重 [kTitleWeight]）；
///    - 前几条 user 消息 + 首条 assistant 消息的 bigram（权重 [kBodyWeight]）；
/// 3. 相似度：标题用 Jaccard，正文用 TF-IDF 余弦，按 `0.5 / 0.5` 加权；
/// 4. 聚类：并查集（union-find），`相似度 >= threshold` 就把两段会话并到一类；
/// 5. 结果按簇大小降序（同大小按首次出现顺序），簇名取「簇中心标题」并去重。
///
/// 单条不成簇的会话各自成卡（宁可不合，也不硬塞进无关话题）。
library;

import 'dart:math' as math;

/// 默认相似度阈值（见 `reports/keepsake/brain-in-app.md`；单测覆盖）。
const double kClusterThreshold = 0.32;

/// 标题在相似度里的权重。
const double kTitleWeight = 0.5;

/// 正文在相似度里的权重。
const double kBodyWeight = 0.5;

/// 会话文本进入特征时的上限（前 N 条 user 消息）。
const int kClusterUserMessageLimit = 3;

/// 每段文本参与 bigram 的字符上限（防止超长会话拖慢导入）。
const int kClusterTextMaxChars = 400;

/// 标题里不算信息量的噪声词（归一化后仍然只是「在聊天」）。
const Set<String> kTitleNoiseWords = <String>{
  '新对话',
  '新会话',
  '新的对话',
  '未命名',
  '未命名会话',
  '未命名对话',
  '对话',
  '会话',
  '聊天',
  '继续',
  '接着聊',
  '补充',
  '临时',
  '测试',
};

/// 一个会话参与聚类所需的文本（导入后从 `messages` 表取，不读 ZIP）。
class SessionPreview {
  const SessionPreview({
    required this.sessionId,
    required this.title,
    this.userTexts = const <String>[],
    this.assistantText = '',
    this.messageCount = 0,
  });

  final String sessionId;
  final String title;

  /// 前 [kClusterUserMessageLimit] 条 user 消息正文。
  final List<String> userTexts;

  /// 首条 assistant 消息正文（只用前 [kClusterTextMaxChars] 字）。
  final String assistantText;

  final int messageCount;

  /// 参与相似度计算的正文（user + assistant）。
  String get bodyText {
    final parts = <String>[
      ...userTexts,
      if (assistantText.trim().isNotEmpty) assistantText,
    ];
    final joined = parts.map((e) => e.trim()).where((e) => e.isNotEmpty).join('。');
    return joined.length <= kClusterTextMaxChars
        ? joined
        : joined.substring(0, kClusterTextMaxChars);
  }

  @override
  String toString() => 'SessionPreview($sessionId, $title)';
}

/// 一个聚类（对应一张待生成的角色卡）。
class SessionCluster {
  const SessionCluster({
    required this.sessionIds,
    required this.title,
    this.topicTerms = const <String>[],
  });

  final List<String> sessionIds;

  /// 簇中心标题（已经做过重名去重前的原始标题）。
  final String title;

  /// 主题词（`description` 用）。
  final List<String> topicTerms;

  int get size => sessionIds.length;

  /// 角色简介：`话题：xxx、yyy · N 个会话`。
  String get description {
    final terms = topicTerms.take(3).join('、');
    final head = terms.isEmpty ? '' : '话题：$terms · ';
    return '$head${sessionIds.length} 个会话';
  }

  @override
  String toString() => 'SessionCluster($title, ${sessionIds.length})';
}

/// 话题聚类结果（含模式选择，供导入任务直接落库）。
enum CharacterImportMode {
  /// 自动按话题分组（默认，推荐）。
  autoCluster,

  /// 全部并到一张角色卡。
  singleCard,

  /// 每个会话一张卡（老行为，不推荐）。
  perSession,
}

final RegExp _noiseDates = RegExp(
  r'\d{4}[-/年.]\d{1,2}[-/月.]\d{1,2}日?|\d{1,2}[-/月.]\d{1,2}日?'
  r'|\d{1,2}:\d{2}(:\d{2})?|\d+月\d+日',
);
final RegExp _nonWord = RegExp(r'[\s\p{P}\p{S}]', unicode: true);

/// 标题归一化：去日期 / 噪声词 / 括号序号 / 标点空白。
String normalizeClusterTitle(String? raw) {
  var text = (raw ?? '').trim();
  if (text.isEmpty) return '';
  text = text.replaceAll(_noiseDates, ' ');
  // 「（2）」「(3)」「#4」「- 5」这类序号不携带话题信息。
  text = text.replaceAll(RegExp(r'[（(]\s*\d+\s*[)）]'), ' ');
  text = text.replaceAll(RegExp(r'[#＃]\s*\d+'), ' ');
  text = text.replaceAll(RegExp(r'\s*[-—–]\s*\d+\s*$'), ' ');
  final compact = text.replaceAll(_nonWord, '').toLowerCase();
  for (final word in kTitleNoiseWords) {
    if (compact == word) return '';
  }
  return compact;
}

/// 归一化后的字符 bigram 词频。
Map<String, double> bigramFrequencies(
  String? text, {
  int maxChars = kClusterTextMaxChars,
}) {
  final normalized = (text ?? '').replaceAll(_nonWord, '').toLowerCase();
  final source =
      normalized.length <= maxChars ? normalized : normalized.substring(0, maxChars);
  final result = <String, double>{};
  for (var i = 0; i + 1 < source.length; i++) {
    final gram = source.substring(i, i + 2);
    if (gram.trim().isEmpty) continue;
    result[gram] = (result[gram] ?? 0) + 1;
  }
  if (result.isEmpty && source.isNotEmpty) {
    result[source] = 1;
  }
  return result;
}

/// 两段文本的 Jaccard 相似度（0..1）。
double jaccardOf(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  var intersection = 0;
  for (final item in a) {
    if (b.contains(item)) intersection += 1;
  }
  final union = a.length + b.length - intersection;
  return union <= 0 ? 0 : intersection / union;
}

/// 余弦相似度（0..1；空向量返回 0）。
double cosineOf(Map<String, double> a, Map<String, double> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  var dot = 0.0;
  var normA = 0.0;
  var normB = 0.0;
  for (final entry in a.entries) {
    normA += entry.value * entry.value;
    final other = b[entry.key];
    if (other != null) dot += entry.value * other;
  }
  for (final value in b.values) {
    normB += value * value;
  }
  if (normA <= 0 || normB <= 0) return 0;
  return dot / (math.sqrt(normA) * math.sqrt(normB));
}

/// 预处理后的会话特征（一次算好，重复用于两两比较）。
class _Features {
  _Features(SessionPreview preview)
      : titleGrams = <String>{
          for (final entry in bigramFrequencies(preview.title, maxChars: 80).keys)
            entry,
        },
        bodyFreq = bigramFrequencies(preview.bodyText);

  final Set<String> titleGrams;
  final Map<String, double> bodyFreq;

  bool get isEmpty => titleGrams.isEmpty && bodyFreq.isEmpty;
}

/// 两条会话的相似度（0..1）：标题 Jaccard × 0.5 + 正文 TF-IDF 余弦 × 0.5。
double sessionSimilarity(
  SessionPreview a,
  SessionPreview b, {
  _Features? featureA,
  _Features? featureB,
  double titleWeight = kTitleWeight,
  double bodyWeight = kBodyWeight,
}) {
  final fa = featureA ?? _Features(a);
  final fb = featureB ?? _Features(b);
  final titleSim = jaccardOf(fa.titleGrams, fb.titleGrams);
  final bodySim = cosineOf(fa.bodyFreq, fb.bodyFreq);
  final weightSum = titleWeight + bodyWeight;
  if (weightSum <= 0) return 0;
  final sim = (titleSim * titleWeight + bodySim * bodyWeight) / weightSum;
  // 标题完全相同且不属于噪声：至少给一个「确认是同一话题」的下限。
  final normalizedA = normalizeClusterTitle(a.title);
  final normalizedB = normalizeClusterTitle(b.title);
  if (normalizedA.isNotEmpty && normalizedA == normalizedB) {
    return math.max(sim, 0.75);
  }
  return sim;
}

/// 并查集。
class _UnionFind {
  _UnionFind(int size)
      : _parent = List<int>.generate(size, (int index) => index);

  final List<int> _parent;

  int find(int x) {
    var root = x;
    while (_parent[root] != root) {
      root = _parent[root];
    }
    var current = x;
    while (_parent[current] != current) {
      final next = _parent[current];
      _parent[current] = root;
      current = next;
    }
    return root;
  }

  void union(int a, int b) {
    final ra = find(a);
    final rb = find(b);
    if (ra != rb) _parent[rb] = ra;
  }
}

/// **导入聚类主函数**（纯函数，单测直接调）。
///
/// - [sessions]：只传**还没绑定角色**的会话（已绑的由调用方跳过，不重复建卡）；
/// - [threshold]：相似度阈值，默认 [kClusterThreshold]；
/// - 返回：每个聚类一条，按簇大小降序；簇名已按重复次数去重（`名字 2`、`名字 3`）。
List<SessionCluster> clusterSessions(
  List<SessionPreview> sessions, {
  double threshold = kClusterThreshold,
  int titleDedupeStart = 2,
}) {
  if (sessions.isEmpty) return const <SessionCluster>[];
  final features = <_Features>[for (final s in sessions) _Features(s)];

  // 1) 两两比较，超过阈值就并类。
  final uf = _UnionFind(sessions.length);
  for (var i = 0; i < sessions.length; i++) {
    if (features[i].isEmpty) continue;
    for (var j = i + 1; j < sessions.length; j++) {
      if (features[j].isEmpty) continue;
      final sim = sessionSimilarity(
        sessions[i],
        sessions[j],
        featureA: features[i],
        featureB: features[j],
      );
      if (sim >= threshold) uf.union(i, j);
    }
  }

  // 2) 按根聚组，保持首次出现顺序。
  final groups = <int, List<int>>{};
  for (var i = 0; i < sessions.length; i++) {
    groups.putIfAbsent(uf.find(i), () => <int>[]).add(i);
  }

  // 3) 每组挑「簇中心标题」：与组内其他成员相似度之和最高，其次更短。
  final clusters = <SessionCluster>[];
  for (final members in groups.values) {
    var bestIndex = members.first;
    var bestScore = -1.0;
    for (final candidate in members) {
      var score = 0.0;
      for (final other in members) {
        if (other == candidate) continue;
        score += sessionSimilarity(
          sessions[candidate],
          sessions[other],
          featureA: features[candidate],
          featureB: features[other],
        );
      }
      final length = normalizeClusterTitle(sessions[candidate].title).length;
      // 同分时更短的标题更像「主题名」。
      final adjusted = score - length * 0.001;
      if (adjusted > bestScore) {
        bestScore = adjusted;
        bestIndex = candidate;
      }
    }
    final rawTitle = sessions[bestIndex].title.trim();
    final title = rawTitle.isEmpty ? '导入的对话' : rawTitle;
    final terms = _topicTerms(members, features, sessions);
    clusters.add(
      SessionCluster(
        sessionIds: <String>[for (final i in members) sessions[i].sessionId],
        title: title,
        topicTerms: terms,
      ),
    );
  }

  // 4) 大的簇排前面（同大小按首次出现）。
  final order = <String, int>{
    for (var i = 0; i < sessions.length; i++) sessions[i].sessionId: i,
  };
  clusters.sort((a, b) {
    final bySize = b.size.compareTo(a.size);
    if (bySize != 0) return bySize;
    return (order[a.sessionIds.first] ?? 0).compareTo(order[b.sessionIds.first] ?? 0);
  });

  // 5) 簇名去重（不同话题可能都叫「RAG 笔记」）。
  final usedNames = <String>{};
  final result = <SessionCluster>[];
  for (final cluster in clusters) {
    var name = cluster.title;
    if (usedNames.contains(name)) {
      var index = titleDedupeStart;
      while (usedNames.contains('$name $index')) {
        index += 1;
      }
      name = '$name $index';
    }
    usedNames.add(name);
    result.add(
      SessionCluster(
        sessionIds: cluster.sessionIds,
        title: name,
        topicTerms: cluster.topicTerms,
      ),
    );
  }
  return result;
}

/// 取簇的主题词：组内出现频次最高的 bigram（去掉只出现一次的碎词）。
List<String> _topicTerms(
  List<int> members,
  List<_Features> features,
  List<SessionPreview> sessions,
) {
  if (members.length <= 1) {
    final title = normalizeClusterTitle(sessions[members.first].title);
    return title.isEmpty ? const <String>[] : <String>[title];
  }
  final df = <String, int>{};
  for (final index in members) {
    for (final gram in <String>{
      ...features[index].titleGrams,
      ...features[index].bodyFreq.keys,
    }) {
      df[gram] = (df[gram] ?? 0) + 1;
    }
  }
  final sorted = df.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      if (byCount != 0) return byCount;
      return a.key.compareTo(b.key);
    });
  final minimum = members.length >= 3 ? 2 : 1;
  return <String>[
    for (final entry in sorted)
      if (entry.value >= minimum && entry.key.length >= 2) entry.key,
  ].take(6).toList(growable: false);
}
