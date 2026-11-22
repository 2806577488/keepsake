/// Keepsake（留声）— 召回打分的**本地自学习权重**（App 内，纯本地持久化）。
///
/// 思路（与 `dsh-brain` 的学习闭环对齐，但不引入 drift 表、不加依赖）：
/// - 打分是五个特征的加权和：`relevance / salience / recency / topic / affection`；
/// - 每个特征有一个乘性权重，默认 1.0（= 旧行为），**地板 0.5 / 天花板 1.5**；
/// - 一条记忆被召回后：回复里用上了 → 权重按 `lr=0.02` 升；没用上 → 半速降；
/// - 每天再整体 `×0.95` 向 1.0 回落：学到的偏好不会被永久锁死；
/// - 只写一个 JSON 文件 `<应用支持目录>/brain_recall_weights.json`，
///   读写失败一律**静默**（最坏情况就是回到默认权重）。
///
/// 归因口径（与 `recall.dart` 的打分函数一致）：
/// `error = used ? 1 - score : -score`，`components` 用本条候选五个特征的
/// 归一化值 —— 只有「当时确实有信号」的特征才会被更新。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';

import 'brain_types.dart';

/// 权重文件名（放在应用支持目录下，随 App 卸载一起清掉）。
const String kRecallWeightsFileName = 'brain_recall_weights.json';

/// 学习率：每次归因只挪一点点，避免一轮把权重带偏。
const double kRecallLearningRate = 0.02;

/// 未被用上的归因按半速下降（`error < 0` 时的额外系数）。
const double kRecallIgnoredSpeed = 0.5;

/// 每天向 1.0 回落的系数。
const double kRecallWeightDailyDecay = 0.95;

/// 读盘 / 写盘的注入点（单测用假实现，避免依赖 platform channel）。
typedef RecallWeightsReader = Future<String?> Function();
typedef RecallWeightsWriter = Future<void> Function(String raw);

/// 解析出来的一份权重（`parse` 的返回值）。
typedef ParsedRecallWeights = ({Map<String, double> weights, DateTime? updatedAt});

/// 五个特征的乘性权重表。
class RecallWeights {
  RecallWeights({Map<String, double>? initial, DateTime? decayedAt})
      : _values = resolveRecallFeatureWeights(initial),
        _decayedAt = decayedAt ?? DateTime.now();

  /// 全部默认权重（1.0）。
  factory RecallWeights.defaults({DateTime? now}) =>
      RecallWeights(decayedAt: now);

  final Map<String, double> _values;

  /// 上次衰减日（用于「每日 ×0.95」，跨重启也不漏算）。
  DateTime _decayedAt;

  DateTime get decayedAt => _decayedAt;

  /// 只读拷贝（直接传给 `recallTurns` / `selectFacts` / `selectEpisodes`）。
  Map<String, double> get values => Map<String, double>.unmodifiable(_values);

  double weightOf(String feature) =>
      _values[feature] ?? kRecallWeightDefault;

  /// 归因一次召回结果，更新权重。
  ///
  /// - [components]：本条候选五个特征的归一化值（0..1，缺项按 0 处理 = 不更新）；
  /// - [error]：`used ? 1 - score : -score`（正 = 有用，负 = 没用上）；
  /// - [now]：注入点，单测可传固定时间；默认现在。
  void update({
    required Map<String, double> components,
    required double error,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    // 先补做跨天的回落，再学习（顺序固定，单测可复现）。
    applyDailyDecay(at);
    if (error.isNaN || error.isInfinite || error == 0) {
      _decayedAt = at;
      return;
    }
    // 「用上了」全速升；「没用上」（error < 0）半速降。
    final speed = error < 0 ? kRecallIgnoredSpeed : 1.0;
    for (final feature in kRecallFeatures) {
      final component = clamp01(components[feature] ?? 0, 0);
      if (component <= 0) continue;
      final delta = kRecallLearningRate * error * component * speed;
      if (delta == 0 || delta.isNaN) continue;
      _values[feature] = clampRecallWeight(_values[feature]! + delta);
    }
    _decayedAt = at;
  }

  /// 每满一天把权重往 1.0 拉 `×0.95`（只按整天算，同一天多次更新不重复衰减）。
  void applyDailyDecay(DateTime now) {
    final days = now.difference(_decayedAt).inDays;
    if (days <= 0) return;
    final factor = math.pow(kRecallWeightDailyDecay, days).toDouble();
    for (final feature in kRecallFeatures) {
      final value = _values[feature]!;
      _values[feature] = clampRecallWeight(1 + (value - 1) * factor);
    }
    _decayedAt = now;
  }

  /// 序列化成一行 JSON（保留 6 位小数，避免浮点尾巴越滚越长）。
  String encode() => jsonEncode(<String, Object?>{
        'version': 1,
        'updatedAt': _decayedAt.toUtc().toIso8601String(),
        'weights': <String, double>{
          for (final feature in kRecallFeatures)
            feature: double.parse(_values[feature]!.toStringAsFixed(6)),
        },
      });

  @override
  String toString() => 'RecallWeights(${values.toString()})';

  // -------------------------------------------------------------------------
  // 解析 / 读盘 / 写盘
  // -------------------------------------------------------------------------

  /// 解析一段 JSON；**任何损坏都返回 null**（调用方回退到默认权重）。
  static ParsedRecallWeights? parse(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      final rawWeights = decoded['weights'];
      if (rawWeights is! Map) return null;
      final weights = <String, double>{};
      for (final feature in kRecallFeatures) {
        final value = rawWeights[feature];
        if (value is num && !value.isNaN && value.isFinite) {
          weights[feature] = value.toDouble();
        }
      }
      // 一个特征都没解析出来 = 文件结构不认识，按损坏处理。
      if (weights.isEmpty) return null;
      DateTime? updatedAt;
      final rawUpdatedAt = decoded['updatedAt'];
      if (rawUpdatedAt is String) {
        updatedAt = DateTime.tryParse(rawUpdatedAt)?.toLocal();
      }
      return (weights: weights, updatedAt: updatedAt);
    } catch (_) {
      return null;
    }
  }

  /// 从一段 JSON 建权重表：空/损坏 → 默认值；同时补做跨天衰减。
  factory RecallWeights.fromRaw(String? raw, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final parsed = parse(raw);
    final weights = RecallWeights(
      initial: parsed?.weights,
      decayedAt: parsed?.updatedAt ?? at,
    );
    weights.applyDailyDecay(at);
    return weights;
  }

  /// 读 `<应用支持目录>/brain_recall_weights.json`。
  ///
  /// [reader] 只在单测里用；默认走 `getApplicationSupportDirectory`。
  /// 读取失败（含插件不可用、文件不存在）静默回退到默认权重。
  static Future<RecallWeights> load({
    DateTime? now,
    RecallWeightsReader? reader,
  }) async {
    String? raw;
    try {
      raw = await (reader ?? _readFromDisk)();
    } catch (_) {
      raw = null;
    }
    return RecallWeights.fromRaw(raw, now: now);
  }

  /// 写回 JSON 文件；失败静默（下次归因会再写一次）。
  Future<void> save({RecallWeightsWriter? writer}) async {
    try {
      await (writer ?? _writeToDisk)(encode());
    } catch (_) {
      // 静默：绝不让学习影响聊天主链路。
    }
  }

  static Future<String?> _readFromDisk() async {
    final file = await _weightsFile();
    if (file == null) return null;
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  static Future<void> _writeToDisk(String raw) async {
    final file = await _weightsFile();
    if (file == null) return;
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    await file.writeAsString(raw, flush: true);
  }

  static Future<File?> _weightsFile() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}${Platform.pathSeparator}$kRecallWeightsFileName');
    } catch (_) {
      return null;
    }
  }
}
