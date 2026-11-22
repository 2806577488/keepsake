/// Keepsake（留声）— 人格层（从对话里统计表达倾向，按天向基线回归）。
///
/// 语义对齐 `dsh-brain` 的 `collectTraits` / `describeTraits` / `applyTraitRegression`
/// （`src/persona.js`）：
/// - user 侧：直接度 / 节奏 / 幽默 / 细节度；
/// - self 侧：温和度 / 直接度 / 俏皮 / 主动性；
/// - 每轮按规则小幅变化（有上下限），每轮先按「距上次更新的小时数」向基线回归；
/// - 注入时只给一句「表达倾向」，不报数值。
library;

import 'brain_types.dart';
import 'signals.dart';

/// user 侧倾向键。
const List<String> kUserTraitKeys = <String>[
  'directness',
  'pace',
  'humor',
  'detail',
];

/// self 侧倾向键。
const List<String> kSelfTraitKeys = <String>[
  'warmth',
  'directness',
  'playfulness',
  'proactivity',
];

/// 默认基线。
const Map<String, double> kDefaultUserBaseline = <String, double>{
  'directness': 0.5,
  'pace': 0.5,
  'humor': 0.4,
  'detail': 0.5,
};

const Map<String, double> kDefaultSelfBaseline = <String, double>{
  'warmth': 0.6,
  'directness': 0.55,
  'playfulness': 0.4,
  'proactivity': 0.5,
};

/// 下限：被凶 / 被冷落也不会归零。
const Map<String, double> kUserTraitFloor = <String, double>{
  'directness': 0.05,
  'pace': 0.05,
  'humor': 0.05,
  'detail': 0.05,
};

const Map<String, double> kSelfTraitFloor = <String, double>{
  'warmth': 0.12,
  'directness': 0.1,
  'playfulness': 0.08,
  'proactivity': 0.08,
};

/// user 侧每天回归基线的比例（用户画像应该相对稳定）。
const double kUserRegressionPerDay = 0.15;

/// self 侧每天回归基线的比例。
const double kSelfRegressionPerDay = 0.25;

/// 距上次更新不足多少小时不回归。
const int kTraitRegressionMinHours = 6;

/// 两侧倾向快照。
class PersonaTraits {
  const PersonaTraits({
    required this.user,
    required this.self,
    this.userUpdatedAt,
    this.selfUpdatedAt,
  });

  /// 基线快照（首次使用时）。
  factory PersonaTraits.baseline([DateTime? now]) {
    final at = now ?? DateTime.now();
    return PersonaTraits(
      user: Map<String, double>.of(kDefaultUserBaseline),
      self: Map<String, double>.of(kDefaultSelfBaseline),
      userUpdatedAt: at,
      selfUpdatedAt: at,
    );
  }

  final Map<String, double> user;
  final Map<String, double> self;
  final DateTime? userUpdatedAt;
  final DateTime? selfUpdatedAt;

  double userValue(String key) => user[key] ?? kDefaultUserBaseline[key] ?? 0.5;

  double selfValue(String key) => self[key] ?? kDefaultSelfBaseline[key] ?? 0.5;

  PersonaTraits copyWith({
    Map<String, double>? user,
    Map<String, double>? self,
    DateTime? userUpdatedAt,
    DateTime? selfUpdatedAt,
  }) =>
      PersonaTraits(
        user: user ?? this.user,
        self: self ?? this.self,
        userUpdatedAt: userUpdatedAt ?? this.userUpdatedAt,
        selfUpdatedAt: selfUpdatedAt ?? this.selfUpdatedAt,
      );

  @override
  String toString() => 'PersonaTraits(user=$user, self=$self)';
}

/// 一轮收集的结果。
class PersonaUpdate {
  const PersonaUpdate({required this.traits, required this.reasons});

  final PersonaTraits traits;
  final List<String> reasons;

  bool get changed => reasons.isNotEmpty;
}

/// 有下限地夹到 0..1。
Map<String, double> clampTraits(
  Map<String, double> traits,
  Map<String, double> floor,
) {
  final next = <String, double>{};
  for (final key in floor.keys) {
    final value = traits[key] ?? floor[key] ?? 0.5;
    final clamped = clamp01(value);
    next[key] = clamped < floor[key]! ? floor[key]! : clamped;
  }
  return next;
}

/// 按「距上次更新的小时数」向基线回归（不足 6 小时不回归）。
Map<String, double> applyTraitRegression(
  Map<String, double> traits,
  Map<String, double> baseline,
  DateTime? updatedAt, {
  DateTime? now,
  double regressionPerDay = 0.25,
  Map<String, double>? floor,
}) {
  final at = now ?? DateTime.now();
  final clamped =
      clampTraits(traits, floor ?? const <String, double>{});
  if (updatedAt == null) return clamped;
  final elapsedHours = at.difference(updatedAt).inMinutes / 60.0;
  if (elapsedHours < kTraitRegressionMinHours) return clamped;
  final fraction =
      (elapsedHours / 24 * regressionPerDay).clamp(0.0, 0.6);
  if (fraction <= 0) return clamped;
  final next = <String, double>{};
  for (final key in clamped.keys) {
    final target = baseline[key] ?? clamped[key]!;
    next[key] = clamped[key]! + (target - clamped[key]!) * fraction;
  }
  return clampTraits(next, floor ?? const <String, double>{});
}

/// 收集一轮对话对两侧倾向的影响（先回归、再小幅更新）。
PersonaUpdate collectTraits(
  PersonaTraits current, {
  required String userText,
  String assistantText = '',
  DateTime? now,
  Map<String, double>? baselineUser,
  Map<String, double>? baselineSelf,
}) {
  final at = now ?? DateTime.now();
  final reasons = <String>[];

  final userBase = baselineUser ?? kDefaultUserBaseline;
  final selfBase = baselineSelf ?? kDefaultSelfBaseline;
  final regressedUser = applyTraitRegression(
    current.user,
    userBase,
    current.userUpdatedAt,
    now: at,
    regressionPerDay: kUserRegressionPerDay,
    floor: kUserTraitFloor,
  );
  final regressedSelf = applyTraitRegression(
    current.self,
    selfBase,
    current.selfUpdatedAt,
    now: at,
    regressionPerDay: kSelfRegressionPerDay,
    floor: kSelfTraitFloor,
  );

  final user = Map<String, double>.of(regressedUser);
  final self = Map<String, double>.of(regressedSelf);
  final signals = analyzeUserText(userText);

  // ---- user 侧：从表达方式读沟通风格 ----
  if (userText.length > 120) {
    user['detail'] = (user['detail'] ?? 0.5) + 0.04;
    user['pace'] = (user['pace'] ?? 0.5) - 0.02;
    reasons.add('user-long');
  }
  if (userText.isNotEmpty && userText.length < 25) {
    user['directness'] = (user['directness'] ?? 0.5) + 0.02;
    user['pace'] = (user['pace'] ?? 0.5) + 0.02;
    reasons.add('user-short');
  }
  if (signals.directStyle) {
    user['directness'] = (user['directness'] ?? 0.5) + 0.05;
    user['detail'] = (user['detail'] ?? 0.5) - 0.04;
    user['pace'] = (user['pace'] ?? 0.5) + 0.03;
    reasons.add('user-wants-direct');
  }
  if (signals.detailStyle) {
    user['detail'] = (user['detail'] ?? 0.5) + 0.05;
    user['pace'] = (user['pace'] ?? 0.5) - 0.02;
    reasons.add('user-wants-detail');
  }
  if (signals.humor) {
    user['humor'] = (user['humor'] ?? 0.4) + 0.04;
    reasons.add('user-humor');
  }
  if (signals.question) {
    user['detail'] = (user['detail'] ?? 0.5) + 0.02;
  }
  if (userText.contains('；') ||
      userText.contains(';') ||
      RegExp(r'\d').hasMatch(userText)) {
    user['detail'] = (user['detail'] ?? 0.5) + 0.02;
  }

  // ---- self 侧：从互动方式读自己的倾向 ----
  if (signals.thanks) {
    self['warmth'] = (self['warmth'] ?? 0.6) + 0.04;
    self['playfulness'] = (self['playfulness'] ?? 0.4) + 0.02;
    reasons.add('self-praised');
  }
  if (signals.frustrated) {
    self['warmth'] = (self['warmth'] ?? 0.6) - 0.03;
    self['directness'] = (self['directness'] ?? 0.55) + 0.03;
    self['proactivity'] = (self['proactivity'] ?? 0.5) + 0.02;
    reasons.add('self-user-frustrated');
  }
  if (signals.tired || signals.sad) {
    self['warmth'] = (self['warmth'] ?? 0.6) + 0.03;
    self['proactivity'] = (self['proactivity'] ?? 0.5) + 0.03;
    reasons.add('self-care');
  }
  if (signals.joy) {
    self['playfulness'] = (self['playfulness'] ?? 0.4) + 0.03;
    self['warmth'] = (self['warmth'] ?? 0.6) + 0.02;
    reasons.add('self-shared-joy');
  }
  if (signals.question || signals.work) {
    self['proactivity'] = (self['proactivity'] ?? 0.5) + 0.02;
    self['directness'] = (self['directness'] ?? 0.55) + 0.01;
    reasons.add('self-answering');
  }
  if (signals.shortInput) {
    self['proactivity'] = (self['proactivity'] ?? 0.5) + 0.01;
    reasons.add('self-user-brief');
  }
  if (assistantText.length > 220) {
    self['directness'] = (self['directness'] ?? 0.55) - 0.01;
  }

  return PersonaUpdate(
    traits: PersonaTraits(
      user: clampTraits(user, kUserTraitFloor),
      self: clampTraits(self, kSelfTraitFloor),
      userUpdatedAt: at,
      selfUpdatedAt: at,
    ),
    reasons: reasons,
  );
}

/// 生成注入用的一句「表达倾向」（self 侧，最多两句）。
String describeSelfTendency(PersonaTraits traits) {
  final warmth = traits.selfValue('warmth');
  final directness = traits.selfValue('directness');
  final playfulness = traits.selfValue('playfulness');
  final proactivity = traits.selfValue('proactivity');

  final parts = <String>[];
  if (warmth >= 0.7) {
    parts.add('你的语气自然地偏温和、关心用户');
  } else if (warmth <= 0.4) {
    parts.add('你最近语气偏克制、就事论事');
  } else {
    parts.add('你的语气保持温和但不过度');
  }
  parts.add(
    directness >= 0.62 ? '你倾向直接给结论，少铺垫' : '你倾向先解释再给结论',
  );
  if (playfulness >= 0.6) parts.add('可以适度开玩笑');
  if (proactivity >= 0.6) parts.add('你会主动补一句下一步或提醒');

  return '表达倾向：${parts.join('；')}。';
}

/// 生成注入用的「用户沟通偏好」（一句，可选）。
String describeUserPreference(PersonaTraits traits) {
  final parts = <String>[];
  final directness = traits.userValue('directness');
  final pacing = traits.userValue('pace');
  final humor = traits.userValue('humor');
  final detail = traits.userValue('detail');
  if (directness >= 0.62) parts.add('用户喜欢直接、少绕弯的回答');
  if (pacing >= 0.62) parts.add('用户节奏偏快，先给结论');
  if (humor >= 0.6) parts.add('用户吃玩笑');
  if (detail >= 0.62) parts.add('用户愿意看细节');
  if (parts.isEmpty) return '';
  return '用户沟通偏好：${parts.join('；')}。';
}
