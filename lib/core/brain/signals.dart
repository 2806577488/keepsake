/// Keepsake（留声）— 对话里的「信号」识别（纯规则、零模型、可解释）。
///
/// 情绪层和人格层都从同一套信号里读：情绪看「用户此刻怎么样」，
/// 人格看「用户习惯怎么表达」。这里只做识别，不做任何状态更新。
library;

/// 一轮用户输入里识别出的信号。
class UserSignals {
  const UserSignals({
    required this.ids,
    this.tired = false,
    this.frustrated = false,
    this.sad = false,
    this.joy = false,
    this.thanks = false,
    this.question = false,
    this.work = false,
    this.longInput = false,
    this.shortInput = false,
    this.affection = false,
    this.directStyle = false,
    this.detailStyle = false,
    this.humor = false,
  });

  /// 命中的信号名（落库/调试用，稳定的小写英文）。
  final List<String> ids;

  final bool tired;
  final bool frustrated;
  final bool sad;
  final bool joy;
  final bool thanks;
  final bool question;
  final bool work;
  final bool longInput;
  final bool shortInput;

  /// 「喜欢你 / 谢谢你陪我」这类关系信号。
  final bool affection;

  /// 「直接说 / 简单点 / 别废话」。
  final bool directStyle;

  /// 「详细点 / 展开说说 / 为什么」。
  final bool detailStyle;

  /// 玩笑 / 表情。
  final bool humor;

  bool get isNeutral => ids.isEmpty;

  @override
  String toString() => 'UserSignals(${ids.join('+')})';
}

/// 情绪类关键词（用户状态）。
const List<String> kTiredWords = <String>[
  '累',
  '困',
  '熬夜',
  '加班',
  '没睡',
  '疲惫',
  '忙死',
  '好忙',
  '喘口气',
  '顶不住',
];

const List<String> kFrustratedWords = <String>[
  '烦',
  '气死',
  '崩溃',
  '无语',
  '郁闷',
  '难顶',
  '受不了',
  '又错了',
  '搞不定',
  '失败',
  '吐了',
  '服了',
];

const List<String> kSadWords = <String>[
  '难过',
  '难受',
  '想哭',
  '哭',
  '失落',
  '伤心',
  '焦虑',
  'emo',
  '孤单',
  '委屈',
];

const List<String> kJoyWords = <String>[
  '开心',
  '高兴',
  '太好了',
  '爽',
  '哈哈',
  '笑死',
  '棒',
  '不错',
  '舒服',
  '兴奋',
  '好耶',
];

const List<String> kThanksWords = <String>[
  '谢谢',
  '感谢',
  '辛苦',
  '多谢',
  'thx',
  'thanks',
];

const List<String> kWorkWords = <String>[
  '代码',
  '项目',
  '编译',
  '构建',
  '测试',
  '报错',
  '部署',
  '接口',
  '需求',
  '打包',
];

const List<String> kAffectionWords = <String>[
  '喜欢你',
  '爱你',
  '想你',
  '陪我',
  '你在真好',
  '舍不得',
];

const List<String> kDirectWords = <String>[
  '直接说',
  '简单点',
  '简短点',
  '别废话',
  '说重点',
  '就告诉我',
];

const List<String> kDetailWords = <String>[
  '详细点',
  '展开说说',
  '为什么',
  '怎么实现',
  '说说思路',
];

const List<String> kHumorWords = <String>[
  '哈哈',
  '😂',
  '笑死',
  '好玩',
  '有趣',
  '开玩笑',
];

bool _containsAny(String text, List<String> words) {
  for (final word in words) {
    if (text.contains(word)) return true;
  }
  return false;
}

/// 识别一轮用户输入（纯函数；同一文本多次调用结果一致）。
UserSignals analyzeUserText(String text) {
  final value = text.trim();
  final lower = value.toLowerCase();
  final ids = <String>[];

  final tired = _containsAny(value, kTiredWords);
  if (tired) ids.add('tired');
  final frustrated = _containsAny(value, kFrustratedWords);
  if (frustrated) ids.add('frustrated');
  final sad = _containsAny(value, kSadWords);
  if (sad) ids.add('sad');
  final joy = _containsAny(value, kJoyWords);
  if (joy) ids.add('joy');
  final thanks = _containsAny(lower, kThanksWords);
  if (thanks) ids.add('thanks');
  final work = _containsAny(value, kWorkWords);
  if (work) ids.add('work');
  final affection = _containsAny(value, kAffectionWords);
  if (affection) ids.add('affection');
  final humor = _containsAny(lower, kHumorWords);
  if (humor) ids.add('humor');
  final directStyle = _containsAny(value, kDirectWords);
  if (directStyle) ids.add('direct');
  final detailStyle = _containsAny(value, kDetailWords);
  if (detailStyle) ids.add('detail');

  // 问句：问号结尾，或以「吗/呢/嘛」收尾，或含疑问词。
  final question = RegExp(r'[?？]\s*$').hasMatch(value) ||
      RegExp(r'(?:吗|呢|嘛|么)\s*$').hasMatch(value) ||
      value.contains('怎么') ||
      value.contains('为什么') ||
      value.contains('如何') ||
      value.contains('是不是');
  if (question) ids.add('question');

  final longInput = value.length >= 120;
  if (longInput) ids.add('long');
  final shortInput = value.isNotEmpty && value.length <= 12;
  if (shortInput) ids.add('short');

  return UserSignals(
    ids: List<String>.unmodifiable(ids),
    tired: tired,
    frustrated: frustrated,
    sad: sad,
    joy: joy,
    thanks: thanks,
    question: question,
    work: work,
    longInput: longInput,
    shortInput: shortInput,
    affection: affection,
    directStyle: directStyle,
    detailStyle: detailStyle,
    humor: humor,
  );
}
