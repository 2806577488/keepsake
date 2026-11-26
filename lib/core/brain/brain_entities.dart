/// App 内「自带大脑」的**实体层**（v0.4.35，移植自 dsh-brain 的 `entities.js`）。
///
/// 为什么需要：记忆层是「关于用户」「关于我」两条平铺的线，张三的主诉、李四的处方
/// 全混在 user 侧事实里，换个会话就接不上"上次那个患者"。
///
/// 这一层把**对象**抽出来（患者/客户/项目/宠物），带名字、别名、时间线。
///
/// **抽取策略：宁缺毋滥。** 中文没分隔符，硬抽会把「今天」「这个」当人名，所以只认
/// 明确信号：身份前缀（`患者张三`）、敬称后缀（`张三先生`）、以及已有实体的名字在本轮出现。
/// 抽不出来就不建档案——宁可漏，也不建错。
///
/// 这个文件只有**纯函数**（无 DB、无网络），所以能直接单测；写库逻辑在
/// `brain_entities_store.dart`。
library;

import 'dart:convert';

/// 实体类型（按身份前缀推断）。
const Map<String, String> kEntityKindByPrefix = <String, String>{
  '患者': 'patient',
  '病人': 'patient',
  '病号': 'patient',
  '客户': 'client',
  '来访者': 'client',
  '案主': 'client',
  '项目': 'project',
  '宠物': 'pet',
};

/// 结构化字段白名单（睡眠期巩固用；白名单外的 kind 一律落「备注」）。
const List<String> kEntityFactKinds = <String>[
  '主诉',
  '症状',
  '辨证',
  '治法',
  '处方',
  '医嘱',
  '复诊',
  '检查',
  '过敏',
  '备注',
];

/// 敬称（多字敬称可以剥离；单字「姐/哥」是代号的一部分，保留）。
const List<String> _honorifics = <String>[
  '先生', '女士', '老师', '阿姨', '叔叔', '伯伯', '婶婶', '大姐', '大哥', '哥', '姐',
];

/// 明显不是名字的词。
const Set<String> _notNames = <String>{
  '今天', '明天', '昨天', '上午', '下午', '晚上', '这个', '那个', '现在', '刚才',
  '情况', '问题', '时候', '样子', '地方', '东西', '病历', '处方', '复诊', '随访',
};

/// 名字里不该出现的常用字（动词/代词/虚词）。
const String _stopNameChars =
    '的了在是我你他她它们这那今明昨上下上来去说问讲要会能想把被给和与就都也很还不没个之其所以因为但如果已经过着到从对为以时候情况问题复诊随访';

/// 常见姓氏（只用于 2 字以上名字的首字校验）。
const String _surnames =
    '王李张刘陈杨黄赵吴周徐孙马朱胡郭何高林罗郑梁谢宋唐许韩冯邓曹彭曾肖田董袁潘于蒋蔡余杜叶程苏魏吕丁任沈姚卢姜崔钟谭陆汪范金石廖贾夏韦付方白邹孟熊秦邱江尹薛闫段雷侯龙史陶黎贺顾毛郝龚邵万钱严覃武戴莫孔向汤';

/// 复姓（3 字名只在这些前缀下启用）。
const List<String> _compoundSurnames = <String>[
  '欧阳', '司马', '诸葛', '上官', '东方', '独孤', '南宫', '西门', '夏侯', '皇甫',
  '尉迟', '公孙', '长孙', '宇文', '司徒', '令狐', '慕容', '端木', '百里', '东郭',
];

/// 名字长度上限（汉字/字母都算一个字符）。
const int _maxNameChars = 12;

/// 把文本压成一行（用于事实/片段展示）。
String flattenText(String? text, {int maxChars = 120}) {
  final flat = (text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.length <= maxChars) return flat;
  return '${flat.substring(0, maxChars - 1)}…';
}

/// 去掉名字末尾的敬称（只去多字敬称）。
String stripHonorific(String name) {
  var value = name.trim();
  for (final honorific in _honorifics) {
    if (honorific.length < 2) continue;
    if (value.length > honorific.length && value.endsWith(honorific)) {
      value = value.substring(0, value.length - honorific.length);
      break;
    }
  }
  return value;
}

bool _isCleanName(String candidate) {
  if (candidate.isEmpty) return false;
  for (final char in candidate.split('')) {
    if (_stopNameChars.contains(char)) return false;
  }
  return !_notNames.contains(candidate);
}

/// 从一段连续字符里挑一个像名字的片段。
///
/// 中文没分隔符，`患者张三主诉咳嗽` 取 3 字会变成「张三主」；所以**优先 2 字**
/// （姓 + 单名，多数情况），3 字只在复姓或「姓 + 多字敬称」（王先生）时启用。
/// 好处是**同一个人每次都会被截成同样的名字**，档案不会裂。
String pickEntityName(String raw, {bool requireSurname = true}) {
  final text = raw;
  if (text.isEmpty) return '';

  if (requireSurname) {
    // 1) 姓 + 多字敬称：王先生 / 李女士
    for (final honorific in _honorifics) {
      if (honorific.length < 2) continue;
      if (_surnames.contains(text[0]) && text.startsWith(honorific, 1)) {
        return text.substring(0, 1 + honorific.length);
      }
    }
    // 2) 复姓 + 单名：欧阳明
    for (final compound in _compoundSurnames) {
      if (!text.startsWith(compound)) continue;
      if (text.length < compound.length + 1) continue;
      final candidate = text.substring(0, compound.length + 1);
      if (_isCleanName(candidate)) return candidate;
    }
    // 3) 姓 + 单名：张三
    if (text.length >= 2 && _surnames.contains(text[0])) {
      final candidate = text.substring(0, 2);
      if (_isCleanName(candidate)) return candidate;
    }
    // 4) 单字兜底（如「患者王…」）
    return _isCleanName(text[0]) ? text[0] : '';
  }

  // 项目/宠物：2 字优先，其次 3 字，再退单字。
  for (final length in <int>[2, 3]) {
    if (text.length >= length) {
      final candidate = text.substring(0, length);
      if (_isCleanName(candidate)) return candidate;
    }
  }
  return _isCleanName(text[0]) ? text[0] : '';
}

/// 一个候选对象（抽取结果）。
class EntityCandidate {
  const EntityCandidate({required this.kind, required this.name});

  /// `patient` / `client` / `project` / `pet` / `person`。
  final String kind;

  final String name;

  @override
  String toString() => '$kind:$name';
}

/// 从一句话里抽候选对象（规则；只认明确信号）。
List<EntityCandidate> extractEntityCandidates(String text) {
  final source = text;
  if (source.trim().isEmpty) return const <EntityCandidate>[];
  final found = <String, EntityCandidate>{};

  void add(String kind, String name) {
    final clean = name.replaceAll(RegExp(r'\s+'), '').trim();
    if (clean.isEmpty || clean.length > _maxNameChars) return;
    if (_notNames.contains(clean)) return;
    if (RegExp(r'^[\d.]+$').hasMatch(clean)) return;
    final key = '$kind:$clean';
    found.putIfAbsent(key, () => EntityCandidate(kind: kind, name: clean));
  }

  // 1) 身份前缀：患者张三 / 病人：李姐 / 客户王先生
  final prefixPattern = RegExp(
    r'(患者|病人|病号|客户|来访者|案主|项目|宠物)\s*[:：]?\s*([\u4e00-\u9fa5A-Za-z][\u4e00-\u9fa5A-Za-z0-9]{1,11})',
  );
  for (final match in prefixPattern.allMatches(source)) {
    final kind = kEntityKindByPrefix[match.group(1)] ?? 'person';
    final requireSurname =
        kind == 'patient' || kind == 'client' || kind == 'person';
    final name = pickEntityName(match.group(2) ?? '', requireSurname: requireSurname);
    if (name.isNotEmpty) add(kind, name);
  }

  // 2) 敬称后缀：张三先生 / 李姐（前缀已抓到的会去重）
  const prefixChars = '患者病人号客户来访案主项目宠物';
  final suffixPattern =
      RegExp(r'([\u4e00-\u9fa5]{2,3})(先生|女士|老师|阿姨|叔叔|伯伯|婶婶|大姐|大哥)');
  for (final match in suffixPattern.allMatches(source)) {
    final candidate = match.group(1) ?? '';
    if (candidate.isEmpty) continue;
    final start = match.start;
    // 紧跟身份前缀、或本身以身份字开头（「客户王先生」）时交给规则 1，
    // 否则会被抽成「户王」「客户王」这种假名字。
    if (prefixChars.contains(candidate[0])) continue;
    if (start > 0 && prefixChars.contains(source[start - 1])) continue;
    add('person', candidate);
  }

  return found.values.toList(growable: false);
}

/// 实体名归一化（比较/去重用）：去空白与包裹引号，小写。
String normalizeEntityName(String name) => name
    .replaceAll(RegExp(r'\s+'), '')
    .replaceAll(RegExp(r'''[「」“”'"《》()（）]'''), '')
    .trim()
    .toLowerCase();

/// 类型的中文名（渲染用）。
String kindLabelOf(String kind) {
  switch (kind) {
    case 'patient':
      return '患者';
    case 'client':
      return '客户';
    case 'project':
      return '项目';
    case 'pet':
      return '宠物';
    default:
      return '对象';
  }
}

/// 注入用的对象档案视图（由 store 装配，渲染只认这个）。
class EntityProfileView {
  const EntityProfileView({
    required this.name,
    required this.kindLabel,
    this.facts = const <EntityFactView>[],
    this.turns = const <EntityTurnView>[],
  });

  final String name;
  final String kindLabel;
  final List<EntityFactView> facts;
  final List<EntityTurnView> turns;
}

class EntityFactView {
  const EntityFactView({required this.kind, required this.text, this.at});

  final String kind;
  final String text;
  final String? at;
}

class EntityTurnView {
  const EntityTurnView({required this.text, this.at});

  final String text;
  final String? at;
}

/// 相关对象（激活扩散；渲染用）。
class EntityRelatedView {
  const EntityRelatedView({required this.name, this.reason});

  final String name;
  final String? reason;
}

String _shortDate(String? at) {
  if (at == null || at.length < 10) return '';
  return '${at.substring(5, 10)} ';
}

/// 渲染「当前对象」注入段（纯函数）。
String renderEntitySection(
  List<EntityProfileView> profiles, {
  int maxChars = 400,
  int turnLimit = 3,
  List<EntityRelatedView> related = const <EntityRelatedView>[],
}) {
  if (profiles.isEmpty) return '';
  final lines = <String>[];
  for (final profile in profiles.take(3)) {
    lines.add('【当前对象 · ${profile.name}（${profile.kindLabel}）】');
    for (final fact in profile.facts.take(6)) {
      lines.add('- ${_shortDate(fact.at)}${flattenText(fact.text, maxChars: 80)}');
    }
    for (final turn in profile.turns.take(turnLimit)) {
      lines.add('- ${_shortDate(turn.at)}聊到：${flattenText(turn.text, maxChars: 70)}');
    }
    lines.add('');
  }
  if (related.isNotEmpty) {
    lines.add('【相关对象】');
    for (final item in related.take(3)) {
      final reason = item.reason == null ? '' : '（${item.reason}）';
      lines.add('- ${item.name}$reason');
    }
  }
  final text = lines.join('\n').trim();
  if (text.length <= maxChars) return text;
  return '${text.substring(0, maxChars - 1)}…';
}

// ---------------------------------------------------------------------------
// 睡眠期结构化巩固：抽取 prompt + 解析（纯函数；模型调用由上层负责）
// ---------------------------------------------------------------------------

/// 结构化抽取的 system prompt。
const String kEntityExtractPrompt =
    '你在后台整理一段医患/客户对话里的对象要点。给你若干轮对话和一份已知对象名单。\n'
    '只输出一个 JSON 对象，不要 Markdown：\n'
    '{"entities":[{"name":"张三","facts":[{"kind":"主诉","text":"咳嗽三天，夜间加重"},{"kind":"处方","text":"止嗽散加减"}]}]}\n'
    'kind 只能取：主诉 / 症状 / 辨证 / 治法 / 处方 / 医嘱 / 复诊 / 检查 / 过敏 / 备注。\n'
    '要求：只写对话里明确出现的信息；每条 ≤ 40 字；不确定就不写；\n'
    'name 必须来自给定名单；没有可整理的返回 {"entities":[]}。';

/// 一轮对话（抽取用）。
class ExtractTurn {
  const ExtractTurn({required this.user, required this.assistant});

  final String user;
  final String assistant;
}

/// 组装结构化抽取的 messages。
({String system, String user}) buildEntityExtractMessages({
  List<ExtractTurn> turns = const <ExtractTurn>[],
  List<String> names = const <String>[],
}) {
  final body = <String>[
    '已知对象：${names.join('、')}',
    '',
    '对话：',
  ];
  final take = turns.take(12).toList(growable: false);
  for (var index = 0; index < take.length; index++) {
    body.add(
      '${index + 1}. 用户：${flattenText(take[index].user, maxChars: 300)}\n'
      '   助手：${flattenText(take[index].assistant, maxChars: 300)}',
    );
  }
  return (system: kEntityExtractPrompt, user: body.join('\n'));
}

/// 抽取结果里的一个字段。
class ExtractedFact {
  const ExtractedFact({required this.kind, required this.text});

  final String kind;
  final String text;
}

/// 抽取结果里的一个对象。
class ExtractedEntity {
  const ExtractedEntity({required this.name, required this.facts});

  final String name;
  final List<ExtractedFact> facts;
}
/// 解析模型返回的抽取 JSON（失败返回空列表，绝不抛）。
List<ExtractedEntity> parseEntityExtraction(String? text) {
  final raw = (text ?? '').replaceAll(RegExp(r'```[a-zA-Z]*\n?'), '');
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) return const <ExtractedEntity>[];
  Object? decoded;
  try {
    decoded = jsonDecode(raw.substring(start, end + 1));
  } catch (_) {
    return const <ExtractedEntity>[];
  }
  if (decoded is! Map) return const <ExtractedEntity>[];
  final rawEntities = decoded['entities'];
  if (rawEntities is! List) return const <ExtractedEntity>[];
  final out = <ExtractedEntity>[];
  for (final item in rawEntities) {
    if (item is! Map) continue;
    final name = (item['name'] ?? '').toString().trim();
    if (name.isEmpty) continue;
    final rawFacts = item['facts'];
    if (rawFacts is! List) continue;
    final facts = <ExtractedFact>[];
    for (final fact in rawFacts) {
      if (fact is! Map) continue;
      final kindRaw = (fact['kind'] ?? '').toString().trim();
      final kind = kEntityFactKinds.contains(kindRaw) ? kindRaw : '备注';
      final factText = flattenText((fact['text'] ?? '').toString(), maxChars: 120);
      if (factText.isEmpty) continue;
      facts.add(ExtractedFact(kind: kind, text: factText));
      if (facts.length >= 8) break;
    }
    if (facts.isNotEmpty) out.add(ExtractedEntity(name: name, facts: facts));
  }
  return out;
}
