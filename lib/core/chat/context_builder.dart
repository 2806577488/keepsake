/// Keepsake（留声）— 上下文预算裁剪与摘要注入。
///
/// 符号证据（`reports/apk/dart-symbols.md` §2）：`ContextBuilder`、`buildContext`、
/// `contextSummary`、`summaryCacheOf`、`contextKeepRounds`、`keepRounds`、
/// `lastRounds`、`snippetAround`、`setContextBudget`。
///
/// 文案证据（ui-strings.txt §2 / prompts.md §2）：
/// `上下文：最近 `、`上下文：不限制`、`不限制（全部历史）`、
/// `超出窗口的部分压成 ≤600 字摘要`、
/// `【以下是本会话更早对话的压缩摘要，供延续上下文】`。
///
/// 算法（[推断]，由文案/字段名推出）：
/// 1. `keepRounds <= 0` → 不限制，全部历史；
/// 2. 否则从最新往回数 user 消息，保留最近 N 轮（最新一条永远保留）；
/// 3. 被裁掉的更早轮次放到 [ContextResult.droppedTurns]，供 summarizer 压缩成
///    ≤600 字摘要；已有摘要用 [contextSummary] 加前缀后拼进 system 消息。
library;

import '../api/chat_backend.dart' show ChatTurn;

/// 默认 system prompt（prompts.md §1 原文 [确定]）。
const String kContextDefaultSystemPrompt =
    '你是一个乐于助人的 AI 助手。回答准确、简洁、有条理；不确定时如实说明，不要编造。默认使用用户提问的语言回复。';

/// 摘要注入前缀（prompts.md §2 原文 [确定]）。
const String kContextSummaryPrefix = '【以下是本会话更早对话的压缩摘要，供延续上下文】';

/// 默认保留轮数（与 `core/settings.dart` 的 `kDefaultContextKeepRounds` 一致）。
const int kDefaultKeepRounds = 20;

/// 「不限制（全部历史）」。
const int kUnlimitedKeepRounds = 0;

/// 「上下文：最近 N」/「上下文：不限制」文案。
String contextBudgetLabel(int keepRounds) =>
    keepRounds <= 0 ? '上下文：不限制' : '上下文：最近 $keepRounds';

/// 给摘要正文加前缀；已带前缀/为空时原样返回/返回 null。
String? contextSummary(String? summary) {
  final text = (summary ?? '').trim();
  if (text.isEmpty) return null;
  if (text.startsWith(kContextSummaryPrefix)) return text;
  return '$kContextSummaryPrefix\n$text';
}

/// 上下文预算配置。
class ContextBudget {
  const ContextBudget({this.keepRounds = kDefaultKeepRounds, this.maxChars});

  /// 不限制（全部历史）。
  static const ContextBudget unlimited = ContextBudget(
    keepRounds: kUnlimitedKeepRounds,
  );

  /// 保留最近几轮；`<= 0` = 不限制。
  final int keepRounds;

  /// 额外的字符预算（`null` = 不限制；超出时从最旧开始丢）。
  final int? maxChars;

  bool get isUnlimited => keepRounds <= 0;

  /// 「上下文：最近 12」/「上下文：不限制」。
  String get label => contextBudgetLabel(keepRounds);

  /// 「不限制（全部历史）」/「上下文：最近 12」。
  String get description => isUnlimited ? '不限制（全部历史）' : label;

  /// 从 Settings 里的 int / JSON 值解析（`context_keep_rounds`）。
  factory ContextBudget.parse(
    Object? raw, {
    ContextBudget fallback = const ContextBudget(),
  }) {
    if (raw == null) return fallback;
    if (raw is ContextBudget) return raw;
    if (raw is int) {
      return ContextBudget(keepRounds: raw, maxChars: fallback.maxChars);
    }
    if (raw is num) {
      return ContextBudget(
        keepRounds: raw.round(),
        maxChars: fallback.maxChars,
      );
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return fallback;
      if (trimmed == '不限制' || trimmed == '不限制（全部历史）') {
        return const ContextBudget(keepRounds: kUnlimitedKeepRounds);
      }
      final parsed = int.tryParse(trimmed);
      if (parsed != null) {
        return ContextBudget(keepRounds: parsed, maxChars: fallback.maxChars);
      }
    }
    return fallback;
  }

  ContextBudget copyWith({int? keepRounds, int? maxChars}) => ContextBudget(
    keepRounds: keepRounds ?? this.keepRounds,
    maxChars: maxChars ?? this.maxChars,
  );

  @override
  String toString() => 'ContextBudget($label)';
}

/// 裁剪结果。
class ContextResult {
  const ContextResult({
    required this.messages,
    this.system,
    this.injectedSummary,
    this.trimmed = false,
    this.droppedCount = 0,
    this.droppedTurns = const <ChatTurn>[],
    this.summaryUpToDate = true,
  });

  /// 裁剪后的历史（不含 system）。
  final List<ChatTurn> messages;

  /// system 消息（默认/自定义 prompt + 摘要前缀）。
  final ChatTurn? system;

  /// 已加前缀的摘要（注入了才有）。
  final String? injectedSummary;

  /// 是否发生了裁剪。
  final bool trimmed;

  final int droppedCount;

  /// 被裁掉的更早轮次（交给 summarizer 压缩）。
  final List<ChatTurn> droppedTurns;

  /// 摘要是否已覆盖被裁掉的历史。
  final bool summaryUpToDate;

  /// 是否应该调用 summarizer 生成/更新摘要。
  bool get needsSummary => trimmed && !summaryUpToDate;

  /// 可直接传给 `ChatRequest.messages`（system 在前）。
  List<ChatTurn> get all => <ChatTurn>[?system, ...messages];

  int get summaryChars => (injectedSummary ?? '').length;

  @override
  String toString() =>
      'ContextResult(${messages.length} msgs, '
      'dropped: $droppedCount, trimmed: $trimmed)';
}

/// 上下文构建器。
class ContextBuilder {
  const ContextBuilder({
    this.keepRounds = kDefaultKeepRounds,
    this.systemPrompt,
    this.maxChars,
  });

  final int keepRounds;
  final String? systemPrompt;
  final int? maxChars;

  /// 裁剪历史并组装 system 消息。
  ///
  /// - [history]：从旧到新的对话（含最新的 user 轮）；
  /// - [summary]：已有摘要（可带/不带前缀；空则用缓存/不注入）；
  /// - [systemPrompt]：设置页的系统提示词（空则用 [kContextDefaultSystemPrompt]）。
  ContextResult buildContext({
    required List<ChatTurn> history,
    String? summary,
    String? systemPrompt,
    int? keepRounds,
    int? maxChars,
  }) {
    final rounds = keepRounds ?? this.keepRounds;
    final limitChars = maxChars ?? this.maxChars;
    final total = history.length;

    var kept = List<ChatTurn>.of(history);
    final dropped = <ChatTurn>[];
    var trimmed = false;

    // 1) 按轮数裁剪：从最新往回数 user 消息，保留最近 rounds 轮。
    if (rounds > 0 && kept.isNotEmpty) {
      var userCount = 0;
      var start = 0;
      for (var i = kept.length - 1; i >= 0; i--) {
        if (kept[i].isUser) {
          userCount++;
          if (userCount > rounds) {
            start = i + 1;
            break;
          }
        }
      }
      if (start > 0) {
        dropped.addAll(kept.sublist(0, start));
        kept = kept.sublist(start);
        trimmed = true;
      }
    }

    // 2) 字符预算（可选）：从最新往回累加。
    if (limitChars != null && limitChars > 0 && kept.isNotEmpty) {
      var start = kept.length;
      var sum = 0;
      for (var i = kept.length - 1; i >= 0; i--) {
        sum += kept[i].content.length;
        if (sum > limitChars) break;
        start = i;
      }
      if (start == kept.length) start = kept.length - 1; // 至少保留最新一条
      if (start > 0) {
        dropped.insertAll(0, kept.sublist(0, start));
        kept = kept.sublist(start);
        trimmed = true;
      }
    }

    if (kept.isEmpty && history.isNotEmpty) {
      kept = <ChatTurn>[history.last];
      if (history.length > 1) {
        dropped
          ..clear()
          ..addAll(history.sublist(0, history.length - 1));
      }
      trimmed = total > 1;
    }

    // 3) system prompt + 摘要。
    final promptText = (systemPrompt ?? this.systemPrompt ?? '').trim();
    final baseSystem = promptText.isEmpty
        ? kContextDefaultSystemPrompt
        : promptText;
    final summaryText = contextSummary(summary);
    // 聊天页的代码块现在是「通栏出血 + 横向滚动、不换行」：按 12.5 号等宽字体、
    // 通栏可用宽约 391dp（86% 屏宽的 411dp 再扣代码区左右各 12dp 内边距）估算，
    // 一行约 52 个半角字符（中文/全角符号约占 2 格，即约 26 个汉字）。
    // 提前告诉模型，能少很多需要用户横向拖动的情况。
    const String codeLayoutHint =
        '排版约束（重要）：聊天页的代码块横向滚动、不换行；代码每行请控制在 52 个半角字符以内'
        '（约 26 个汉字宽）。超出请主动断行，命令过长就拆成多条命令。';
    final systemWithHint = '$baseSystem\n\n$codeLayoutHint';
    final systemContent = summaryText == null
        ? systemWithHint
        : '$systemWithHint\n\n$summaryText';

    final hasSummary = summaryText != null;
    return ContextResult(
      messages: List<ChatTurn>.unmodifiable(kept),
      system: ChatTurn.system(systemContent),
      injectedSummary: summaryText,
      trimmed: trimmed,
      droppedCount: dropped.length,
      droppedTurns: List<ChatTurn>.unmodifiable(dropped),
      summaryUpToDate: hasSummary || dropped.isEmpty,
    );
  }
}

/// 截断一段文本到 [summaryChars] 左右，尽量落在句号处（UI「+ 摘要」用）。
String snippetAround(String text, {int summaryChars = 600}) {
  final trimmed = text.trim();
  if (trimmed.length <= summaryChars) return trimmed;
  final cut = trimmed.substring(0, summaryChars);
  final dot = cut.lastIndexOf('。');
  if (dot > summaryChars ~/ 2) return cut.substring(0, dot + 1);
  return '$cut…';
}
