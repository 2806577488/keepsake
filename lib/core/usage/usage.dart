/// Keepsake（留声）— token 用量统计模型与解析。
///
/// 符号证据（`reports/apk/dart-symbols.md` §2 / §4）：
/// `UsageDelta`、`UsageTotals`、`parseUsage`、`usage_totals`、
/// `accumulated_token_usage`、`token_usage`、`prompt_tokens`、`completion_tokens`、
/// `input_tokens`、`output_tokens`、`cache_read_input_tokens`、
/// `cache_creation_input_tokens`、`requests`。
///
/// 设计：OpenAI 风格（`prompt_tokens`/`completion_tokens`）与 Anthropic 风格
/// （`input_tokens`/`output_tokens`）在解析时统一归一化成 input/output；
/// 写回 JSON 时两种 key 都写，方便旧数据/统计页面互操作。
library;

import 'dart:convert';

/// 单次请求（或流式响应中的一段）的 token 增量。
class UsageDelta {
  const UsageDelta({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheReadInputTokens = 0,
    this.cacheCreationInputTokens = 0,
  });

  /// 输入 token（OpenAI 的 `prompt_tokens` 归一化到这里）。
  final int inputTokens;

  /// 输出 token（OpenAI 的 `completion_tokens` 归一化到这里）。
  final int outputTokens;

  /// 命中缓存的输入 token（`cache_read_input_tokens`）。
  final int cacheReadInputTokens;

  /// 写入缓存的输入 token（`cache_creation_input_tokens`）。
  final int cacheCreationInputTokens;

  static const UsageDelta zero = UsageDelta();

  factory UsageDelta.fromJson(Map<String, Object?> json) => UsageDelta(
    inputTokens:
        _intOf(json['input_tokens']) ?? _intOf(json['prompt_tokens']) ?? 0,
    outputTokens:
        _intOf(json['output_tokens']) ?? _intOf(json['completion_tokens']) ?? 0,
    cacheReadInputTokens:
        _intOf(json['cache_read_input_tokens']) ??
        _intOf(json['cache_read']) ??
        0,
    cacheCreationInputTokens: _intOf(json['cache_creation_input_tokens']) ?? 0,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'input_tokens': inputTokens,
    'output_tokens': outputTokens,
    'cache_read_input_tokens': cacheReadInputTokens,
    'cache_creation_input_tokens': cacheCreationInputTokens,
  };

  bool get isEmpty =>
      inputTokens <= 0 &&
      outputTokens <= 0 &&
      cacheReadInputTokens <= 0 &&
      cacheCreationInputTokens <= 0;

  bool get isNotEmpty => !isEmpty;

  int get totalTokens => inputTokens + outputTokens;

  UsageDelta operator +(UsageDelta other) => UsageDelta(
    inputTokens: inputTokens + other.inputTokens,
    outputTokens: outputTokens + other.outputTokens,
    cacheReadInputTokens: cacheReadInputTokens + other.cacheReadInputTokens,
    cacheCreationInputTokens:
        cacheCreationInputTokens + other.cacheCreationInputTokens,
  );

  /// 转成累计值（不增加请求数）。
  UsageTotals toTotals() => UsageTotals(
    inputTokens: inputTokens,
    outputTokens: outputTokens,
    cacheReadInputTokens: cacheReadInputTokens,
    cacheCreationInputTokens: cacheCreationInputTokens,
  );

  @override
  String toString() =>
      'UsageDelta(in: $inputTokens, out: $outputTokens, '
      'cacheRead: $cacheReadInputTokens, cacheCreate: $cacheCreationInputTokens)';
}

/// 累计用量（`usage_totals`）。
class UsageTotals {
  const UsageTotals({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheReadInputTokens = 0,
    this.cacheCreationInputTokens = 0,
    this.requests = 0,
  });

  final int inputTokens;
  final int outputTokens;
  final int cacheReadInputTokens;
  final int cacheCreationInputTokens;

  /// 请求次数（每次成功完成的对话 +1）。
  final int requests;

  static const UsageTotals empty = UsageTotals();

  /// 字符串表里出现过的另一个字段名（DB/JSON 兼容）。
  int get promptTokens => inputTokens;

  /// 字符串表里出现过的另一个字段名（DB/JSON 兼容）。
  int get completionTokens => outputTokens;

  int get totalTokens => inputTokens + outputTokens;

  int get cacheTokens => cacheReadInputTokens + cacheCreationInputTokens;

  /// 缓存命中率（0..1）。
  ///
  /// 分母**必须按供应商口径分开算**（2026-11-24 实测发现旧公式让 DeepSeek 的数字凭
  /// 空矮一截）：
  /// - OpenAI / DeepSeek：`prompt_tokens` **已包含**命中部分（实测 DeepSeek 一次
  ///   521 prompt / 384 hit → 命中率 74%），分母就是 `inputTokens`；
  /// - Anthropic：`input_tokens` **不含**缓存读/写，分母要加回来。
  /// 判别方式：Anthropic 会报 `cache_creation_input_tokens`；OpenAI 兼容接口没有这个
  /// 字段（DeepSeek 只有 `prompt_cache_hit_tokens` / cached_tokens）。
  double get cacheHitRate {
    final int read = cacheReadInputTokens;
    if (read <= 0) return 0;
    final int base;
    if (cacheCreationInputTokens > 0) {
      base = inputTokens + read + cacheCreationInputTokens;
    } else {
      base = inputTokens > 0 ? inputTokens : read;
    }
    if (base <= 0) return 0;
    final rate = read / base;
    if (rate.isNaN || rate.isInfinite) return 0;
    return rate.clamp(0.0, 1.0).toDouble();
  }

  bool get isEmpty =>
      inputTokens <= 0 &&
      outputTokens <= 0 &&
      cacheReadInputTokens <= 0 &&
      cacheCreationInputTokens <= 0 &&
      requests <= 0;

  bool get isNotEmpty => !isEmpty;

  /// 累加一次增量；默认同时把请求数 +1（流式响应即使没有 usage 也算一次请求）。
  UsageTotals add(UsageDelta delta, {bool countRequest = true}) => UsageTotals(
    inputTokens: inputTokens + delta.inputTokens,
    outputTokens: outputTokens + delta.outputTokens,
    cacheReadInputTokens: cacheReadInputTokens + delta.cacheReadInputTokens,
    cacheCreationInputTokens:
        cacheCreationInputTokens + delta.cacheCreationInputTokens,
    requests: requests + (countRequest ? 1 : 0),
  );

  UsageTotals merge(UsageTotals other) => UsageTotals(
    inputTokens: inputTokens + other.inputTokens,
    outputTokens: outputTokens + other.outputTokens,
    cacheReadInputTokens: cacheReadInputTokens + other.cacheReadInputTokens,
    cacheCreationInputTokens:
        cacheCreationInputTokens + other.cacheCreationInputTokens,
    requests: requests + other.requests,
  );

  UsageTotals copyWith({
    int? inputTokens,
    int? outputTokens,
    int? cacheReadInputTokens,
    int? cacheCreationInputTokens,
    int? requests,
  }) => UsageTotals(
    inputTokens: inputTokens ?? this.inputTokens,
    outputTokens: outputTokens ?? this.outputTokens,
    cacheReadInputTokens: cacheReadInputTokens ?? this.cacheReadInputTokens,
    cacheCreationInputTokens:
        cacheCreationInputTokens ?? this.cacheCreationInputTokens,
    requests: requests ?? this.requests,
  );

  /// 容错解析：接受累计 JSON、`usage_totals` / `accumulated_token_usage`
  /// 包裹、以及 `prompt_tokens`/`completion_tokens` 旧 key。
  factory UsageTotals.fromJson(Map<String, Object?>? json) {
    if (json == null || json.isEmpty) return empty;
    var source = json;
    final nested =
        json['usage_totals'] ??
        json['accumulated_token_usage'] ??
        json['usage'];
    if (nested is Map) {
      source = Map<String, Object?>.from(nested);
    } else if (nested is String && nested.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(nested);
        if (decoded is Map) source = Map<String, Object?>.from(decoded);
      } catch (_) {
        // 忽略坏数据，走下面的字段解析。
      }
    }
    final input =
        _intOf(source['input_tokens']) ??
        _intOf(source['prompt_tokens']) ??
        _intOf(source['accumulated_input_tokens']);
    final output =
        _intOf(source['output_tokens']) ??
        _intOf(source['completion_tokens']) ??
        _intOf(source['accumulated_output_tokens']);
    return UsageTotals(
      inputTokens: _clampInt(input),
      outputTokens: _clampInt(output),
      cacheReadInputTokens: _clampInt(
        _intOf(source['cache_read_input_tokens']) ??
            _intOf(source['cache_read']),
      ),
      cacheCreationInputTokens: _clampInt(
        _intOf(source['cache_creation_input_tokens']),
      ),
      requests: _clampInt(
        _intOf(source['requests']) ??
            _intOf(source['request_count']) ??
            _intOf(source['count']),
      ),
    );
  }

  /// 从 SharedPreferences 里的 JSON 字符串解析（坏数据返回 [empty]）。
  static UsageTotals fromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return empty;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return UsageTotals.fromJson(Map<String, Object?>.from(decoded));
      }
    } catch (_) {
      // 忽略坏数据。
    }
    return empty;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'input_tokens': inputTokens,
    'output_tokens': outputTokens,
    'cache_read_input_tokens': cacheReadInputTokens,
    'cache_creation_input_tokens': cacheCreationInputTokens,
    // 兼容旧字段名（字符串表实证这两个 key 也存在）。
    'prompt_tokens': inputTokens,
    'completion_tokens': outputTokens,
    'requests': requests,
  };

  @override
  String toString() =>
      'UsageTotals(in: $inputTokens, out: $outputTokens, '
      'cacheRead: $cacheReadInputTokens, requests: $requests)';
}

/// 从任意响应 JSON 里解析 token 增量。
///
/// 支持：
/// - OpenAI SSE：`{"choices":[],"usage":{"prompt_tokens":...}}`
/// - Anthropic `message_start`：`{"message":{"usage":{"input_tokens":...}}}`
/// - Anthropic `message_delta`：`{"usage":{"output_tokens":...}}`
/// - OpenAI `prompt_tokens_details.cached_tokens`
///
/// 没有任何 token 字段时返回 `null`（不要用 0 增量污染累计值）。
UsageDelta? parseUsage(Map<String, Object?>? json) {
  if (json == null || json.isEmpty) return null;
  var source = json;

  // 直接包一层 usage。
  final usage = json['usage'];
  if (usage is Map) {
    source = Map<String, Object?>.from(usage);
  } else {
    // Anthropic message_start: {"type":"message_start","message":{"usage":{...}}}
    final message = json['message'];
    if (message is Map) {
      final messageMap = Map<String, Object?>.from(message);
      final messageUsage = messageMap['usage'];
      if (messageUsage is Map) {
        source = Map<String, Object?>.from(messageUsage);
      } else if (messageMap.containsKey('input_tokens')) {
        source = messageMap;
      }
    }
  }

  final input =
      _intOf(source['input_tokens']) ?? _intOf(source['prompt_tokens']);
  final output =
      _intOf(source['output_tokens']) ?? _intOf(source['completion_tokens']);
  var cacheRead =
      _intOf(source['cache_read_input_tokens']) ??
      _intOf(source['cache_read']) ??
      0;
  final cacheCreation = _intOf(source['cache_creation_input_tokens']) ?? 0;

  if (cacheRead <= 0) {
    final details = source['prompt_tokens_details'];
    if (details is Map) {
      cacheRead = _intOf(details['cached_tokens']) ?? 0;
    }
  }
  // DeepSeek 的 OpenAI 兼容接口在 usage 顶层直接给命中数（`prompt_cache_hit_tokens`）；
  // 有的版本没有 `prompt_tokens_details`，不读这个字段命中率会一直是 0。
  if (cacheRead <= 0) {
    cacheRead = _intOf(source['prompt_cache_hit_tokens']) ?? 0;
  }

  if (input == null && output == null && cacheRead <= 0 && cacheCreation <= 0) {
    return null;
  }
  return UsageDelta(
    inputTokens: _clampInt(input),
    outputTokens: _clampInt(output),
    cacheReadInputTokens: _clampInt(cacheRead),
    cacheCreationInputTokens: _clampInt(cacheCreation),
  );
}

/// 大数字缩写（统计页「 亿 / 万 」文案）：`12345` → `1.2万`。
String formatCompactCount(int value) {
  if (value <= 0) return '$value';
  if (value >= 100000000) return '${_trimFixed(value / 100000000)}亿';
  if (value >= 10000) return '${_trimFixed(value / 10000)}万';
  return '$value';
}

/// 上下文占用率（百分比数值）：最近一次请求的 prompt tokens ÷ 上下文窗口 × 100。
///
/// 无数据（`promptTokens <= 0` 或窗口非法）返回 `null`；**不截断**，超过 100% 照实返回。
double? occupancyPercent({
  required int promptTokens,
  required int contextWindowTokens,
}) {
  if (promptTokens <= 0 || contextWindowTokens <= 0) return null;
  final percent = promptTokens / contextWindowTokens * 100;
  if (percent.isNaN || percent.isInfinite) return null;
  return percent;
}

/// 「占用 X%」里的百分比文案；无数据显示 `—`（整数，全应用同一口径）。
String formatOccupancyPercent({
  required int promptTokens,
  required int contextWindowTokens,
}) {
  final percent = occupancyPercent(
    promptTokens: promptTokens,
    contextWindowTokens: contextWindowTokens,
  );
  if (percent == null) return '—';
  return '${percent.toStringAsFixed(0)}%';
}

/// 「缓存命中 Y%」文案；空态显示 `—`（整数，全应用同一口径）。
String formatCacheHitPercent(UsageTotals totals) {
  if (totals.isEmpty) return '—';
  return '${(totals.cacheHitRate * 100).toStringAsFixed(0)}%';
}

String _trimFixed(double value) {
  final text = value.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

int? _intOf(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return int.tryParse(trimmed) ?? double.tryParse(trimmed)?.round();
  }
  return null;
}

int _clampInt(int? value) {
  final number = value ?? 0;
  return number < 0 ? 0 : number;
}
