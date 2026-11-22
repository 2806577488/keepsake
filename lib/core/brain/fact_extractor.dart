/// Keepsake（留声）— 规则版「事实抽取」与「情节摘要」。
///
/// 语义对齐 DSH 插件 `dsh-brain` 的 `extractUserFacts` / `extractSelfFacts`
/// （`src/memory.js`），但**不复用 JS**，全部纯 Dart：
/// - user 侧（关于用户）：名字 / 身份 / 偏好 / 在做的事 / 约定 / 带时间的事件 / 沟通风格；
/// - self 侧（关于助手自己）：承诺 / 记下的关系事项。
///
/// 规则抽取天然有漏召（例如隐喻、长句里的隐含偏好），这是已知限制，
/// 但好处是零模型、零网络、可解释、速度稳定。
library;

import 'brain_types.dart';
import 'signals.dart';

/// 事实类型对应的初始权重（与 dsh-brain 的 `KIND_WEIGHT` 同量级）。
const Map<String, double> kFactKindWeight = <String, double>{
  'profile': 0.9,
  'promise': 0.85,
  'project': 0.8,
  'preference': 0.74,
  'style': 0.72,
  'event': 0.62,
  'memory': 0.72,
  'relation': 0.65,
  'other': 0.5,
};

final RegExp _fillerPrefix = RegExp(
  r'^(?:其实|其实呢|而且|然后|不过|但是|可是|所以|对了|那个|就是|还有|另外|反正|总之|好吧|话说|嗯+|哦+|唉)[，,、\s]*',
);
final RegExp _tailParticles = RegExp(r'[了啊呀呢吧哦哈啦嘛诶]+$');
final RegExp _quotes = RegExp(r'[「」“”"''\x27]');
final RegExp _whitespace = RegExp(r'\s+');

/// 把一段文本拆成「分句」（先按句末标点，再按逗号/分号）。
List<String> splitClauses(String text) {
  final result = <String>[];
  for (final sentence in text.split(RegExp(r'[。！？!?\n\r]+'))) {
    for (final piece in sentence.split(RegExp(r'[；;，,]'))) {
      final clause = piece.trim();
      if (clause.isNotEmpty) result.add(clause);
    }
  }
  return result;
}

/// 问句 / 反问句不能抽成事实。
bool looksLikeQuestion(String clause) {
  if (RegExp(r'[?？]\s*$').hasMatch(clause)) return true;
  if (RegExp(r'(?:吗|么|呢|嘛)\s*$').hasMatch(clause)) return true;
  if (RegExp(r'^(?:你|您)').hasMatch(clause)) return true;
  return false;
}

/// user 侧：把第一人称改写成「用户」视角。
String toUserVoice(String clause) {
  var value = clause.replaceFirst(_fillerPrefix, '').trim();
  value = value.replaceFirst(RegExp(r'^我(?!们)'), '用户');
  value = value.replaceFirst(RegExp('^俺'), '用户');
  if (!value.startsWith('用户')) value = '用户$value';
  value = value.replaceFirst(_tailParticles, '').trim();
  return value.replaceAll(_quotes, '').replaceAll(_whitespace, ' ').trim();
}

/// self 侧：保持助手第一人称（「我答应…」），去掉语气词。
String toSelfVoice(String clause) {
  var value = clause.replaceFirst(_fillerPrefix, '').trim();
  value = value.replaceFirst(_tailParticles, '').trim();
  return value.replaceAll(_quotes, '').replaceAll(_whitespace, ' ').trim();
}

/// 截断并压平一条事实文本（超长用 `…` 收尾）。
String trimFactText(String text, {int maxChars = kFactTextMaxChars}) {
  final flat = text.replaceAll(_whitespace, ' ').trim();
  if (flat.isEmpty) return '';
  if (flat.length <= maxChars) return flat;
  return '${flat.substring(0, maxChars - 1)}…';
}

/// 从用户文本里抽 user 侧事实（纯规则）。
List<FactCandidate> extractUserFacts(String text) {
  final facts = <FactCandidate>[];
  final seen = <String>{};
  for (final clause in splitClauses(text)) {
    final raw = clause.trim();
    if (raw.length < 4 || raw.length > 80 || looksLikeQuestion(raw)) continue;
    FactCandidate? fact;

    // profile：名字 / 身份。
    final nameMatch = RegExp(
      r'(?:^我(?:的名字)?(?:叫|是叫)|^叫我|^我名字(?:叫|是))\s*[「“"]?([\u4e00-\u9fa5A-Za-z0-9_·]{1,12})',
    ).firstMatch(raw);
    if (nameMatch != null) {
      final name = nameMatch.group(1)!.replaceAll(RegExp(r'[」”"]'), '');
      if (name.isNotEmpty) {
        fact = FactCandidate(
          text: '用户叫$name',
          kind: 'profile',
          weight: 0.92,
        );
      }
    }
    if (fact == null) {
      final occupation = RegExp(
        r'(?:主播|程序员|学生|设计师|老师|工程师|上班族|自由职业|写代码的|up主|UP主|博主)',
      ).firstMatch(raw);
      if (occupation != null && raw.startsWith('我是')) {
        fact = FactCandidate(
          text: '用户是${occupation.group(0)}',
          kind: 'profile',
          weight: 0.88,
        );
      }
    }
    // style：沟通习惯。
    if (fact == null &&
        RegExp(r'(?:直接说|简单点|简短点|别废话|说重点|详细点|展开说说|不要太长)')
            .hasMatch(raw)) {
      final short = RegExp(r'(?:直接说|简单点|简短点|别废话|说重点)').hasMatch(raw);
      fact = FactCandidate(
        text: short ? '用户偏好直接、简短的回答' : '用户希望回答更详细',
        kind: 'style',
        weight: 0.72,
      );
    }
    // preference：喜欢 / 讨厌（排除「喜欢你」这类关系表达）。
    if (fact == null &&
        RegExp(r'(?:喜欢|讨厌|偏爱|受不了|爱吃|爱喝|不爱|最喜欢|不太喜欢|不喜欢)')
            .hasMatch(raw) &&
        raw.startsWith('我') &&
        !RegExp(r'(?:喜欢|爱)(?:你|您)').hasMatch(raw)) {
      fact = FactCandidate(
        text: toUserVoice(raw),
        kind: 'preference',
        weight: 0.74,
      );
    }
    // project：正在做的事。
    if (fact == null &&
        (RegExp(
          r'(?:^|，)?我(?:最近|这几天|这阵子|目前|一直|这两天)?在(?:做|忙|准备|写|搞|弄|开发|学|练|赶)',
        ).hasMatch(raw) ||
            RegExp(r'^我(?:最近|这几天|这阵子|目前|这两天)').hasMatch(raw))) {
      fact = FactCandidate(
        text: toUserVoice(raw),
        kind: 'project',
        weight: 0.82,
      );
    }
    // promise：答应 / 约好。
    if (fact == null &&
        raw.startsWith('我') &&
        RegExp(r'(?:答应|约好|说好|保证|承诺|发誓)').hasMatch(raw)) {
      fact = FactCandidate(
        text: toUserVoice(raw),
        kind: 'promise',
        weight: 0.86,
      );
    }
    // event：带时间的具体事件。
    if (fact == null &&
        RegExp(r'(?:今天|昨天|明天|后天|周末|今晚|下周|下个月|待会儿|一会|月底|年底)')
            .hasMatch(raw) &&
        RegExp(r'(?:面试|考试|开会|会议|直播|生日|搬家|出差|旅行|发布|上线|体检|答辩|汇报|加班|聚餐)')
            .hasMatch(raw)) {
      fact = FactCandidate(
        text: toUserVoice(raw),
        kind: 'event',
        weight: 0.62,
      );
    }
    if (fact == null) continue;
    final key = normalizeForMatch(fact.text);
    if (key.isEmpty || !seen.add(key)) continue;
    facts.add(fact);
  }
  return facts;
}

/// 从助手文本里抽 self 侧事实（纯规则，最多 3 条）。
List<FactCandidate> extractSelfFacts(String text) {
  final facts = <FactCandidate>[];
  for (final clause in splitClauses(text)) {
    final raw = clause.trim();
    if (raw.length < 4 || raw.length > 80) continue;
    if (RegExp(r'我(?:答应|保证|承诺|会记住|记下了|记着|记住)').hasMatch(raw)) {
      facts.add(
        FactCandidate(text: toSelfVoice(raw), kind: 'promise', weight: 0.8),
      );
      continue;
    }
    if (RegExp(r'(?:我记得你|记得你说过|你上次说过)').hasMatch(raw)) {
      facts.add(
        FactCandidate(text: toSelfVoice(raw), kind: 'memory', weight: 0.72),
      );
      continue;
    }
    if (RegExp(r'(?:我们|咱俩)(?:已经|又|一起)').hasMatch(raw) &&
        RegExp(r'(?:聊|做|弄|完成|开始)').hasMatch(raw)) {
      facts.add(
        FactCandidate(text: toSelfVoice(raw), kind: 'relation', weight: 0.6),
      );
    }
  }
  return facts.take(3).toList(growable: false);
}

/// 从文本里抽用户名字（profile 展示用）。
String? extractUserName(String text) {
  final match = RegExp(
    r'我(?:的名字)?叫\s*[「“"]?([\u4e00-\u9fa5A-Za-z0-9_·]{1,12})',
  ).firstMatch(text);
  if (match == null) return null;
  final name = match.group(1)!.replaceAll(RegExp(r'[」”"]'), '');
  return name.isEmpty ? null : name;
}

/// 取一句话里的「主句」：第一个长度足够的成分句。
String mainClause(String text, {int maxChars = 90}) {
  for (final clause in splitClauses(text)) {
    final raw = clause.trim();
    if (raw.length >= 4) {
      return raw.length <= maxChars ? raw : '${raw.substring(0, maxChars)}…';
    }
  }
  final flat = text.trim();
  if (flat.length <= maxChars) return flat;
  return '${flat.substring(0, maxChars)}…';
}

/// 取助手回应的首句（用于 episode 的「助手首句」）。
String firstSentence(String text, {int maxChars = 90}) {
  final flat = text.trim();
  if (flat.isEmpty) return '';
  final match = RegExp(r'^[^\n。！？!?]{0,200}').firstMatch(flat);
  final sentence = (match?.group(0) ?? flat).trim();
  if (sentence.length <= maxChars) return sentence;
  return '${sentence.substring(0, maxChars)}…';
}

/// 生成一条 episode 摘要：`user 主句 + assistant 首句`，`≤ maxChars` 字。
///
/// 空助手文本（用户中途停止）时只保留用户主句。
String summarizeEpisode({
  required String userText,
  String assistantText = '',
  int maxChars = kEpisodeSummaryMaxChars,
}) {
  final user = mainClause(userText);
  final assistant = firstSentence(assistantText);
  var summary = assistant.isEmpty ? user : '$user；$assistant';
  summary = summary.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (summary.length <= maxChars) return summary;
  final cut = summary.substring(0, maxChars);
  final dot = cut.lastIndexOf('。');
  if (dot > maxChars ~/ 2) return cut.substring(0, dot + 1);
  return '${cut.substring(0, maxChars - 1)}…';
}

/// episode 的重要度：个人信息 / 情绪 / 约定 / 反复提及会加分。
double episodeSalience({
  required UserSignals signals,
  required String userText,
}) {
  var salience = 0.45;
  if (signals.affection) salience += 0.15;
  if (signals.joy || signals.frustrated || signals.sad) salience += 0.1;
  if (RegExp(r'(?:我叫|我是|答应|约好|记住|别忘|重要)').hasMatch(userText)) {
    salience += 0.12;
  }
  if (userText.length >= 120) salience += 0.05;
  return clamp01(salience);
}
