/// Keepsake（留声）— 情绪层（零模型、纯规则 + EMA 平滑 + 时间衰减）。
///
/// 语义对齐 `dsh-brain` 的 `applyMoodRules` / `applyMoodDecay`（`src/mood.js`）：
/// - 每轮先做**时间衰减**（距上次更新超过 2 小时按比例向基线回归，深夜额外压低）；
/// - 再按关键词 / 标点 / 长度更新 valence（心情值）/ energy（精力）/ affection（好感）；
/// - 更新量按 EMA 系数平滑，避免一句话把心情拉到极端；
/// - 由数值推出一句「当前心情」，供 system prompt 注入（只描述，不报数值）。
///
/// 只有助手自己的一行状态（`mood_state id=1`），外加一条轨迹 `mood_history`。
library;

import 'brain_types.dart';
import 'signals.dart';

/// 基线：所有衰减都朝这里回归。
const double kMoodBaselineValence = 0.58;
const double kMoodBaselineEnergy = 0.60;
const double kMoodBaselineAffection = 0.45;

/// 距上次更新超过多少分钟开始衰减。
const int kMoodDecayMinutes = 120;

/// EMA 平滑系数（每轮最多走 35% 的差值）。
const double kMoodEmaAlpha = 0.35;

/// `mood_history` 最多保留多少条。
const int kMoodHistoryLimit = 200;

/// 当前情绪状态（`mood_state` 一行）。
class MoodState {
  const MoodState({
    required this.name,
    required this.valence,
    required this.affection,
    required this.energy,
    required this.updatedAt,
  });

  /// 初始状态：平静 + 基线数值。
  factory MoodState.initial([DateTime? now]) => MoodState(
        name: '平静',
        valence: kMoodBaselineValence,
        affection: kMoodBaselineAffection,
        energy: kMoodBaselineEnergy,
        updatedAt: now ?? DateTime.now(),
      );

  /// 一句短状态（「平静」「专注」「心疼」…）。
  final String name;

  /// 0..1 心情值。
  final double valence;

  /// 0..1 对用户的好感度。
  final double affection;

  /// 0..1 精力。
  final double energy;

  final DateTime updatedAt;

  MoodState copyWith({
    String? name,
    double? valence,
    double? affection,
    double? energy,
    DateTime? updatedAt,
  }) =>
      MoodState(
        name: name ?? this.name,
        valence: valence ?? this.valence,
        affection: affection ?? this.affection,
        energy: energy ?? this.energy,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  String toString() =>
      'MoodState($name, v=${valence.toStringAsFixed(2)}, '
      'a=${affection.toStringAsFixed(2)}, e=${energy.toStringAsFixed(2)})';
}

/// 一轮情绪更新的结果。
class MoodUpdate {
  const MoodUpdate({
    required this.state,
    required this.reason,
    required this.signals,
  });

  final MoodState state;

  /// 落 `mood_history.reason` 的短串（`tired+joy`）。
  final String reason;

  final UserSignals signals;
}

/// 时间衰减（纯函数，便于单测）。
MoodState applyMoodDecay(
  MoodState current, {
  DateTime? now,
  int decayMinutes = kMoodDecayMinutes,
}) {
  final at = now ?? DateTime.now();
  final elapsedMinutes = at.difference(current.updatedAt).inMinutes;
  if (elapsedMinutes < decayMinutes) return current;

  // 越久没说话，回归越多（最多 60%）。
  final ratio = (0.15 + (elapsedMinutes / decayMinutes - 1) * 0.1).clamp(0.0, 0.6);
  var valence = current.valence + (kMoodBaselineValence - current.valence) * ratio;
  var energy = current.energy + (kMoodBaselineEnergy - current.energy) * ratio;
  var affection =
      current.affection + (kMoodBaselineAffection - current.affection) * ratio;

  // 深夜 0–6 点：精力与心情再压低一点。
  final hour = at.hour;
  if (hour >= 0 && hour < 6) {
    energy -= 0.05;
    valence -= 0.02;
  }
  return current.copyWith(
    valence: clamp01(valence),
    energy: clamp01(energy),
    affection: clamp01(affection),
    updatedAt: at,
  );
}

/// 由数值 + 信号推出「一句状态」。
String selfStatus({
  required double valence,
  required double energy,
  required double affection,
  UserSignals? signals,
}) {
  if (signals?.frustrated == true) return '谨慎';
  if (signals?.sad == true) return '心疼';
  if (signals?.tired == true) return '心疼';
  if (signals?.thanks == true) {
    return energy > 0.55 ? '轻松' : '被夸得有点不好意思';
  }
  if (signals?.question == true || signals?.work == true) return '专注';
  if (energy <= 0.35) return '疲惫';
  if (valence >= 0.72 && affection >= 0.6) return '愉快';
  if (valence <= 0.4) return '低落';
  return '平静';
}

/// 一轮情绪更新（先衰减、再按规则算目标值、最后 EMA 平滑）。
MoodUpdate applyMoodTurn(
  MoodState current, {
  required String userText,
  String assistantText = '',
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final decayed = applyMoodDecay(current, now: at);
  final signals = analyzeUserText(userText);

  var valence = decayed.valence;
  var energy = decayed.energy;
  var affection = decayed.affection;

  // ---- 目标值（规则增量）----
  if (signals.tired) {
    energy -= 0.12;
    valence -= 0.03;
  }
  if (signals.frustrated) {
    valence -= 0.10;
    energy -= 0.03;
  }
  if (signals.sad) valence -= 0.08;
  if (signals.joy) {
    valence += 0.08;
    energy += 0.03;
  }
  if (signals.thanks) {
    valence += 0.04;
    energy += 0.01;
    affection += 0.06;
  }
  if (signals.question) energy -= 0.01;
  if (signals.longInput) energy -= 0.02;
  if (signals.humor) valence += 0.02;
  if (signals.affection) affection += 0.05;

  // 感叹号连用：情绪波动更明显（方向交给信号决定）。
  final exclamation = RegExp(r'[!！]{2,}').hasMatch(userText);
  if (exclamation) {
    if (signals.joy || signals.thanks) {
      valence += 0.02;
    } else if (signals.frustrated || signals.sad) {
      valence -= 0.02;
    }
  }

  // 什么都没识别到：向基线轻轻回归（休息）。
  if (signals.isNeutral) {
    valence += (kMoodBaselineValence - valence) * 0.05;
    energy += (kMoodBaselineEnergy - energy) * 0.05;
    affection += (kMoodBaselineAffection - affection) * 0.02;
  }

  // 助手回了很长的内容：自己也会累一点。
  if (assistantText.length > 220) energy -= 0.02;

  // ---- EMA 平滑（每轮走 35%，不会一句话就翻脸）----
  valence = decayed.valence + (valence - decayed.valence) * kMoodEmaAlpha;
  energy = decayed.energy + (energy - decayed.energy) * kMoodEmaAlpha;
  affection = decayed.affection + (affection - decayed.affection) * kMoodEmaAlpha;

  final next = MoodState(
    name: selfStatus(
      valence: clamp01(valence),
      energy: clamp01(energy),
      affection: clamp01(affection),
      signals: signals,
    ),
    valence: clamp01(valence),
    affection: clamp01(affection),
    energy: clamp01(energy),
    updatedAt: at,
  );

  final reasons = <String>[...signals.ids];
  if (decayed.updatedAt != current.updatedAt &&
      at.difference(current.updatedAt).inMinutes >= kMoodDecayMinutes) {
    reasons.add('decay');
  }
  return MoodUpdate(
    state: next,
    reason: reasons.isEmpty ? 'resting' : reasons.join('+'),
    signals: signals,
  );
}

/// 把 0..1 的数值收成中文描述（不暴露具体数值）。
String describeLevel(double value, String low, String mid, String high) {
  if (value >= 0.68) return high;
  if (value <= 0.36) return low;
  return mid;
}

/// 生成注入用的一句话：`当前心情：专注（心情平稳、精力尚可）。`
String describeMood(MoodState state) {
  final valence = describeLevel(state.valence, '心情偏低落', '心情平稳', '心情不错');
  final energy = describeLevel(state.energy, '精力偏低', '精力尚可', '精力不错');
  return '当前心情：${state.name}（$valence、$energy）。';
}
