/// Keepsake（留声）— 旧对话摘要（≤600 字）与摘要缓存。
///
/// prompt 原文（prompts.md §2 [确定]）：
/// - system：`你是对话历史压缩器。…只输出摘要正文，不要任何开场白。`
/// - 首次：`\n请输出这段对话的要点摘要（600字以内）。`
/// - 增量：`\n请把新增对话合并进已有摘要，输出更新后的完整摘要（600字以内）。`
/// - 片段：`对话记录： `、`已有摘要： `、`\n新增对话： `
///
/// 符号证据（`dart-symbols.md` §2）：`DbSummaryCache`、`SummaryCache`、
/// `SummaryRecord`、`SummaryCacheStore`、`ErrorSummary`、`ensureSummary`、
/// `saveSummaryCache`、`summarize`；DB 表 `summary_caches` 列
/// `context_summary` / `summary` / `summary_chars` / `updated_at`。
library;

import '../api/chat_backend.dart';
import 'context_builder.dart' show kContextSummaryPrefix;

/// 摘要器 system prompt（prompts.md §2 原文 [确定]）。
const String kSummarySystemPrompt =
    '你是对话历史压缩器。把给出的旧对话压缩成中文要点摘要，保留：用户的目标与偏好、已确认的事实与结论、重要决定、未完成事项。省略寒暄与冗余细节。只输出摘要正文，不要任何开场白。';

/// 首次摘要请求后缀（原文含前导 `\n`）。
const String kSummaryRequestSuffix = '\n请输出这段对话的要点摘要（600字以内）。';

/// 增量合并请求后缀（原文含前导 `\n`）。
const String kSummaryMergeSuffix =
    '\n请把新增对话合并进已有摘要，输出更新后的完整摘要（600字以内）。';

/// 对话记录前缀（原文带尾随空格）。
const String kSummaryDialogPrefix = '对话记录： ';

/// 已有摘要前缀（原文带尾随空格）。
const String kSummaryExistingPrefix = '已有摘要： ';

/// 新增对话前缀（原文含前导 `\n`，带尾随空格）。
const String kSummaryNewDialogPrefix = '\n新增对话： ';

/// 摘要长度上限（「600字以内」）。
const int kSummaryMaxChars = 600;

/// 送进摘要器的对话最多多少字符（避免摘要请求本身超窗）。
const int kSummaryDialogMaxChars = 12000;

/// 生成摘要失败。
class ErrorSummary implements Exception {
  const ErrorSummary(this.message, {this.cause, this.sessionId});

  final String message;
  final Object? cause;
  final String? sessionId;

  @override
  String toString() => message;
}

/// 摘要结果。
class SummaryRecord {
  const SummaryRecord({
    required this.sessionId,
    required this.summary,
    required this.summaryChars,
    this.updatedAt,
    this.coveredTurns = 0,
    this.cached = false,
  });

  const SummaryRecord.empty(this.sessionId)
      : summary = '',
        summaryChars = 0,
        updatedAt = null,
        coveredTurns = 0,
        cached = false;

  final String sessionId;
  final String summary;
  final int summaryChars;
  final DateTime? updatedAt;

  /// 摘要覆盖的「更早轮次」数量（用于缓存命中判断）。
  final int coveredTurns;

  /// 是否直接复用缓存（没有调用模型）。
  final bool cached;

  bool get isEmpty => summary.trim().isEmpty;

  bool get isNotEmpty => !isEmpty;

  SummaryRecord copyWith({
    String? sessionId,
    String? summary,
    int? summaryChars,
    DateTime? updatedAt,
    int? coveredTurns,
    bool? cached,
  }) =>
      SummaryRecord(
        sessionId: sessionId ?? this.sessionId,
        summary: summary ?? this.summary,
        summaryChars: summaryChars ?? this.summaryChars,
        updatedAt: updatedAt ?? this.updatedAt,
        coveredTurns: coveredTurns ?? this.coveredTurns,
        cached: cached ?? this.cached,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'session_id': sessionId,
        'summary': summary,
        'summary_chars': summaryChars,
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
        'covered_turns': coveredTurns,
        'cached': cached,
      };

  @override
  String toString() =>
      'SummaryRecord($sessionId, ${summary.length} chars, cached: $cached)';
}

/// 摘要缓存（对应 DB `summary_caches` 一行）。
class SummaryCache {
  const SummaryCache({
    this.sessionId = '',
    this.contextSummary = '',
    this.summary = '',
    this.summaryChars = 0,
    this.updatedAt,
    this.coveredTurns = 0,
  });

  final String sessionId;

  /// 截断上下文用的摘要（DB 列 `context_summary`）。
  final String contextSummary;

  /// 摘要正文（DB 列 `summary`，冗余字段）。
  final String summary;

  /// 摘要字符数（计入上下文预算）。
  final int summaryChars;

  final DateTime? updatedAt;

  /// 覆盖的更早轮次数（内存/JSON 扩展字段）。
  final int coveredTurns;

  bool get isEmpty =>
      contextSummary.trim().isEmpty && summary.trim().isEmpty;

  bool get isNotEmpty => !isEmpty;

  /// 优先 `context_summary`，退回 `summary`。
  String get text {
    final context = contextSummary.trim();
    return context.isEmpty ? summary.trim() : context;
  }

  SummaryRecord toRecord({bool cached = true}) => SummaryRecord(
        sessionId: sessionId,
        summary: text,
        summaryChars: summaryChars > 0 ? summaryChars : text.length,
        updatedAt: updatedAt,
        coveredTurns: coveredTurns,
        cached: cached,
      );

  factory SummaryCache.fromJson(Map<String, Object?> json) {
    final contextSummary =
        (json['context_summary'] ?? json['contextSummary'] ?? '').toString();
    final summary = (json['summary'] ?? '').toString();
    final text = contextSummary.trim().isEmpty ? summary : contextSummary;
    return SummaryCache(
      sessionId: (json['session_id'] ?? json['sessionId'] ?? '').toString(),
      contextSummary: contextSummary,
      summary: summary,
      summaryChars: _intOf(json['summary_chars'] ?? json['summaryChars']) ??
          text.length,
      updatedAt: _dateTimeOf(json['updated_at'] ?? json['updatedAt']),
      coveredTurns: _intOf(json['covered_turns'] ?? json['coveredTurns']) ?? 0,
    );
  }

  factory SummaryCache.fromRecord(SummaryRecord record) => SummaryCache(
        sessionId: record.sessionId,
        contextSummary: record.summary,
        summary: record.summary,
        summaryChars: record.summaryChars,
        updatedAt: record.updatedAt,
        coveredTurns: record.coveredTurns,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'session_id': sessionId,
        'context_summary': contextSummary,
        'summary': summary,
        'summary_chars': summaryChars,
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
        'covered_turns': coveredTurns,
      };

  SummaryCache copyWith({
    String? sessionId,
    String? contextSummary,
    String? summary,
    int? summaryChars,
    DateTime? updatedAt,
    int? coveredTurns,
  }) =>
      SummaryCache(
        sessionId: sessionId ?? this.sessionId,
        contextSummary: contextSummary ?? this.contextSummary,
        summary: summary ?? this.summary,
        summaryChars: summaryChars ?? this.summaryChars,
        updatedAt: updatedAt ?? this.updatedAt,
        coveredTurns: coveredTurns ?? this.coveredTurns,
      );

  @override
  String toString() =>
      'SummaryCache($sessionId, $summaryChars chars)';
}

/// 摘要缓存的持久化接口。
abstract interface class SummaryCacheStore {
  Future<SummaryCache?> cacheOf(String sessionId);

  Future<void> save(SummaryCache cache);
}

/// DB 摘要缓存（用回调接 `AppDatabase.summaryCacheOf` / `saveSummaryCache`）。
///
/// 这样 `core/chat` 不反向依赖 `core/db/database.dart`：
/// ```dart
/// DbSummaryCache.fromRows(
///   loadRow: (id) => db.summaryCacheOf(id),
///   saveRow: (id, contextSummary, chars) => db.saveSummaryCache(
///     sessionId: id,
///     contextSummary: contextSummary,
///     summaryChars: chars,
///   ),
/// )
/// ```
class DbSummaryCache implements SummaryCacheStore {
  DbSummaryCache({
    required this.load,
    required this.saveCache,
  });

  /// 从 DB 行（drift `SummaryCaches`）构造；回调返回 Object 行即可。
  factory DbSummaryCache.fromRows({
    required Future<Object?> Function(String sessionId) loadRow,
    required Future<void> Function(String sessionId, String contextSummary, int summaryChars)
        saveRow,
  }) =>
      DbSummaryCache(
        load: (sessionId) async {
          final row = await loadRow(sessionId);
          if (row == null) return null;
          if (row is Map) {
            return SummaryCache.fromJson(Map<String, Object?>.from(row));
          }
          return _cacheFromRow(row);
        },
        saveCache: (cache) => saveRow(
          cache.sessionId,
          cache.contextSummary.isEmpty ? cache.summary : cache.contextSummary,
          cache.summaryChars,
        ),
      );

  /// 读取回调（接 `AppDatabase.summaryCacheOf`）。
  final Future<SummaryCache?> Function(String sessionId) load;

  /// 写入回调（接 `AppDatabase.saveSummaryCache`）。
  final Future<void> Function(SummaryCache cache) saveCache;

  @override
  Future<SummaryCache?> cacheOf(String sessionId) => load(sessionId);

  @override
  Future<void> save(SummaryCache cache) => saveCache(cache);

  static SummaryCache _cacheFromRow(Object row) {
    final dynamic r = row;
    return SummaryCache(
      sessionId: (r.sessionId ?? r.session_id ?? '').toString(),
      contextSummary: (r.contextSummary ?? r.context_summary ?? '').toString(),
      summary: (r.summary ?? '').toString(),
      summaryChars: _intOf(r.summaryChars ?? r.summary_chars) ?? 0,
      updatedAt: _dateTimeOf(r.updatedAt ?? r.updated_at),
    );
  }
}

/// 读取摘要缓存（符号表 `summaryCacheOf`）。
Future<SummaryCache?> summaryCacheOf(
  SummaryCacheStore store,
  String sessionId,
) =>
    store.cacheOf(sessionId);

/// 写入摘要缓存（符号表 `saveSummaryCache`）。
Future<void> saveSummaryCache(
  SummaryCacheStore store,
  SummaryCache cache,
) =>
    store.save(cache);

/// 调当前 provider 生成 ≤[maxChars] 字摘要（已有摘要则做增量合并）。
Future<String> summarize({
  required ChatBackend backend,
  String? existingSummary,
  required List<ChatTurn> newTurns,
  int maxChars = kSummaryMaxChars,
}) async {
  final dialog = formatSummaryDialog(newTurns);
  if (dialog.trim().isEmpty) {
    throw const ErrorSummary('没有可摘要的对话记录');
  }
  final existing = (existingSummary ?? '').trim();
  final userContent = existing.isEmpty
      ? '$kSummaryDialogPrefix$dialog$kSummaryRequestSuffix'
      : '$kSummaryExistingPrefix$existing'
          '$kSummaryNewDialogPrefix$dialog'
          '$kSummaryMergeSuffix';

  final request = ChatRequest(
    provider: backend.provider,
    messages: <ChatTurn>[ChatTurn.user(userContent)],
    systemPrompt: kSummarySystemPrompt,
    thinking: false,
    maxTokens: maxChars * 2,
  );

  final buffer = StringBuffer();
  await for (final event in backend.streamChat(request)) {
    if (event is TextDelta) {
      buffer.write(event.text);
    } else if (event is Failure) {
      throw ErrorSummary(event.error.message);
    } else if (event is Done) {
      break;
    }
  }
  final summary = clampSummary(buffer.toString(), maxChars: maxChars);
  if (summary.isEmpty) {
    throw const ErrorSummary('摘要生成失败：模型没有返回内容');
  }
  return summary;
}

/// 把「更早轮次」格式化成摘要器可读的对话记录。
String formatSummaryDialog(
  Iterable<ChatTurn> turns, {
  int maxChars = kSummaryDialogMaxChars,
}) {
  final lines = <String>[];
  for (final turn in turns) {
    final content = turn.content.trim();
    if (content.isEmpty) continue;
    final label = turn.isAssistant ? '助手' : (turn.isSystem ? '系统' : '用户');
    lines.add('$label：$content');
  }
  var text = lines.join('\n\n');
  if (text.length > maxChars) {
    // 摘要更早的历史，保留靠后的部分（更接近当前上下文）。
    text = text.substring(text.length - maxChars);
    final firstBreak = text.indexOf('\n\n');
    if (firstBreak >= 0 && firstBreak < 200) {
      text = text.substring(firstBreak + 2);
    }
  }
  return text;
}

/// 截断到 [maxChars] 字，尽量在句末断开。
String clampSummary(String raw, {int maxChars = kSummaryMaxChars}) {
  final trimmed = raw.trim();
  if (trimmed.length <= maxChars) return trimmed;
  final cut = trimmed.substring(0, maxChars);
  for (final mark in const <String>['。', '！', '？', '\n']) {
    final index = cut.lastIndexOf(mark);
    if (index >= maxChars ~/ 2) return cut.substring(0, index + 1).trim();
  }
  return '$cut…';
}

/// 确保拿到一份可用摘要。
///
/// 逻辑：
/// 1. 有 DB/内存缓存且覆盖轮次数足够 → 直接复用（不调模型）；
/// 2. 更早轮次太少（< [minTurns]）→ 不调模型，返回已有摘要/空记录；
/// 3. 否则调 [summarize]（有旧摘要则增量合并），写回缓存。
Future<SummaryRecord> ensureSummary({
  required SummaryCacheStore store,
  required String sessionId,
  required List<ChatTurn> olderTurns,
  String? existingSummary,
  ChatBackend? backend,
  int minTurns = 2,
  int maxChars = kSummaryMaxChars,
  bool force = false,
}) async {
  final turns = List<ChatTurn>.of(olderTurns);
  SummaryCache? cached;
  try {
    cached = await store.cacheOf(sessionId);
  } catch (_) {
    cached = null; // 缓存读失败不应阻塞对话。
  }

  final explicit = (existingSummary ?? '').trim();
  final cachedText =
      explicit.isNotEmpty ? explicit : (cached?.text ?? '');
  final hasCached = cachedText.isNotEmpty;

  if (!force) {
    if (turns.length < minTurns) {
      return SummaryRecord(
        sessionId: sessionId,
        summary: hasCached ? cachedText : '',
        summaryChars: cachedText.length,
        updatedAt: cached?.updatedAt,
        coveredTurns: cached?.coveredTurns ?? 0,
        cached: hasCached,
      );
    }
    if (cached != null &&
        hasCached &&
        cached.coveredTurns >= turns.length) {
      return cached.toRecord(cached: true);
    }
  }

  if (backend == null) {
    // 未配置平台/无法调用模型：只能复用已有摘要。
    return SummaryRecord(
      sessionId: sessionId,
      summary: hasCached ? cachedText : '',
      summaryChars: cachedText.length,
      updatedAt: cached?.updatedAt,
      coveredTurns: cached?.coveredTurns ?? 0,
      cached: hasCached,
    );
  }

  final summary = await summarize(
    backend: backend,
    existingSummary: hasCached ? cachedText : null,
    newTurns: turns,
    maxChars: maxChars,
  );
  final record = SummaryRecord(
    sessionId: sessionId,
    summary: summary,
    summaryChars: summary.length,
    updatedAt: DateTime.now(),
    coveredTurns: turns.length,
    cached: false,
  );
  try {
    await store.save(SummaryCache.fromRecord(record));
  } catch (_) {
    // 写缓存失败不影响本次对话（下次重算）。
  }
  return record;
}

/// 摘要文本是否已经带上注入前缀（context_builder 用）。
bool hasSummaryPrefix(String summary) =>
    summary.trim().startsWith(kContextSummaryPrefix);

DateTime? _dateTimeOf(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is int) {
    // drift 的 dateTime 列默认存秒/毫秒，两种都容错。
    if (value > 100000000000) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value > 1000000000) {
      return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    }
    return null;
  }
  if (value is String) {
    final text = value.trim();
    if (text.isEmpty) return null;
    final parsed = DateTime.tryParse(text);
    if (parsed != null) return parsed;
    final number = int.tryParse(text);
    if (number != null) return _dateTimeOf(number);
  }
  return null;
}

int? _intOf(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) {
    final text = value.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text) ?? double.tryParse(text)?.round();
  }
  return null;
}
