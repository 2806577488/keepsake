/// Keepsake（留声）— Server-Sent Events 解析。
///
/// 协议证据（`reports/apk/http-api.md` §4）：`text/event-stream`、`data:`、
/// `data: `、`[DONE]`、`content-type`、`chunked`、`keep-alive`；
/// 断流文案：`连接中断，没有收到结束标记`（OpenAI `[DONE]`）/
/// `连接中断，没有收到结束事件`（Anthropic `message_stop`）。
///
/// 符号证据（`dart-symbols.md` §2）：`SseEvent`、`SseParser`、`parseSse`。
///
/// 实现要点：
/// - 按行解析（`\n` / `\r\n` / `\r` 都算换行），跨 chunk 的半行会缓冲；
/// - `:` 开头的注释行（keep-alive）忽略，`data: keep-alive` 默认也忽略；
/// - 多行 `data:` 用 `\n` 拼接后分发；
/// - 字节流用 `Utf8Decoder` 增量解码，UTF-8 多字节字符跨 chunk 不会乱码；
/// - 流干净结束但没见到结束标记 → 抛 [SseInterruptedException]
///   （client 层转成 `ApiError`，消息就是上面的固定文案）。
library;

import 'dart:async';
import 'dart:convert';

/// `Content-Type` 期望值。
const String sseContentType = 'text/event-stream';

/// SSE data 行前缀。
const String sseDataPrefix = 'data:';

/// OpenAI 流结束标记。
const String sseDoneMarker = '[DONE]';

/// keep-alive 心跳内容。
const String sseKeepAlive = 'keep-alive';

/// OpenAI 断流文案（http-api.md §4 原文 [确定]）。
const String sseInterruptedMessage = '连接中断，没有收到结束标记';

/// Anthropic 断流文案（http-api.md §4 原文 [确定]）。
const String sseInterruptedEventMessage = '连接中断，没有收到结束事件';

/// Anthropic 结束事件名。
const String sseEventMessageStop = 'message_stop';

/// 单行长度上限（字符）：256KB。
///
/// 为什么要上限：SSE 是"服务端想发多长就多长"的协议，解析器按行缓冲、
/// 按事件累积。一个只会发超长行/超大事件的坏服务端（或被劫持的中间层）
/// 可以把内存吃满直到进程被杀。正常模型的增量 JSON 每行只有几百字节到几 KB。
const int sseMaxLineChars = 256 * 1024;

/// 单事件长度上限（字符）：4MB。
///
/// 一个事件 = 若干 `data:` 行拼起来；4MB 已经远大于任何正常增量片段
/// （连整段代码块一次性下发也就几十 KB）。
const int sseMaxEventChars = 4 * 1024 * 1024;

/// SSE 事件。
class SseEvent {
  const SseEvent({this.event, this.data = '', this.id, this.retry});

  /// `event:` 字段（未出现时为 null，默认事件类型是 `message`）。
  final String? event;

  /// `data:` 拼好的正文（多行已用 `\n` 连接）。
  final String data;

  /// `id:` 字段。
  final String? id;

  /// `retry:` 字段（毫秒）。
  final int? retry;

  /// 是否 OpenAI `[DONE]`。
  bool get isDone => data.trim() == sseDoneMarker;

  /// 是否心跳（`data: keep-alive` 或空 data 注释）。
  bool get isKeepAlive =>
      data.trim().toLowerCase() == sseKeepAlive ||
      (data.isEmpty && event == null);

  /// data 是 JSON 对象时返回 Map，否则 null。
  Map<String, Object?>? get json {
    final decoded = decodedJson;
    return decoded is Map ? Map<String, Object?>.from(decoded) : null;
  }

  /// data 解析后的 JSON（对象/数组/null）。
  Object? get decodedJson {
    final trimmed = data.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return null;
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() =>
      'SseEvent(${event ?? 'message'}, ${data.length} chars)';
}

/// 事件终结判定（返回 true 表示流已正常结束）。
typedef SseTerminator = bool Function(SseEvent event);

/// 逐块喂入、按行产出事件的 SSE 解析器。
class SseParser {
  SseParser({
    SseTerminator? isTerminator,
    this.interruptedMessage = sseInterruptedMessage,
    this.emitKeepAlives = false,
  }) : isTerminator = isTerminator ?? _defaultTerminator;

  /// 默认：OpenAI `[DONE]`。
  static bool _defaultTerminator(SseEvent event) => event.isDone;

  /// 结束判定。
  final SseTerminator isTerminator;

  /// 断流文案（默认 OpenAI）。
  final String interruptedMessage;

  /// 是否把心跳事件也吐出来（默认过滤）。
  final bool emitKeepAlives;

  final List<SseEvent> _out = <SseEvent>[];
  final StringBuffer _line = StringBuffer();
  final List<String> _dataLines = <String>[];
  String? _eventName;
  String? _id;
  int? _retry;
  bool _terminated = false;
  bool _lastWasCr = false;
  int _eventCount = 0;

  /// 当前事件已累积的 `data:` 字符数（用于单事件上限）。
  int _dataChars = 0;

  /// 是否已收到结束标记。
  bool get isTerminated => _terminated;

  /// 已产出的业务事件数（不含心跳）。
  int get eventCount => _eventCount;

  /// 取出并清空已解析事件。
  List<SseEvent> take() {
    if (_out.isEmpty) return const <SseEvent>[];
    final events = List<SseEvent>.of(_out);
    _out.clear();
    return events;
  }

  /// 喂入一段已解码文本（可跨任意 chunk 边界）。
  void add(String chunk) {
    if (chunk.isEmpty || _terminated) return;
    for (var i = 0; i < chunk.length; i++) {
      final char = chunk[i];
      if (char == '\r') {
        _finishLine();
        _lastWasCr = true;
        continue;
      }
      if (char == '\n') {
        if (_lastWasCr) {
          // `\r\n`：上一轮已经把行结束了。
          _lastWasCr = false;
          continue;
        }
        _finishLine();
        continue;
      }
      _lastWasCr = false;
      _line.write(char);
      // 单行上限：坏服务端发一行超长数据时不把内存吃满（E-26）。
      if (_line.length > sseMaxLineChars) {
        _line.clear();
        throw const SseLimitExceededException(
          '流式数据异常：单行超过 256KB，已中断',
        );
      }
    }
  }

  /// 流结束时调用：把没有换行结尾的最后一行/事件冲出来。
  void flush() {
    if (_line.isNotEmpty) _finishLine();
    _dispatch();
  }

  void _finishLine() {
    final line = _line.toString();
    _line.clear();
    if (line.isEmpty) {
      // 空行 = 一个事件结束。
      _dispatch();
      return;
    }
    if (line.startsWith(':')) return; // 注释 / keep-alive

    var field = line;
    var value = '';
    final colon = line.indexOf(':');
    if (colon >= 0) {
      field = line.substring(0, colon);
      value = line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);
    }

    switch (field) {
      case 'data':
        // 单事件上限：多行 data 累加，超过 4MB 直接中断（E-26）。
        _dataChars += value.length;
        if (_dataChars > sseMaxEventChars) {
          _dataLines.clear();
          _dataChars = 0;
          throw const SseLimitExceededException(
            '流式数据异常：单事件超过 4MB，已中断',
          );
        }
        _dataLines.add(value);
      case 'event':
        _eventName = value.isEmpty ? null : value;
      case 'id':
        _id = value;
      case 'retry':
        _retry = int.tryParse(value);
      default:
        // 未知字段忽略（规范要求忽略）。
        break;
    }
  }

  void _dispatch() {
    if (_dataLines.isEmpty && _eventName == null) return;
    final data = _dataLines.join('\n');
    final event = SseEvent(
      event: _eventName,
      data: data,
      id: _id,
      retry: _retry,
    );
    _dataLines.clear();
    _dataChars = 0;
    _eventName = null;
    _id = null;
    _retry = null;

    if (event.isKeepAlive && !emitKeepAlives) return;
    _eventCount++;
    _out.add(event);
    if (isTerminator(event)) _terminated = true;
  }
}

/// `SseParser` 的别名（符号表两个名字都存在）。
typedef SseClient = SseParser;

/// 断流异常；client 层会转成 `ApiError`。
class SseInterruptedException implements Exception {
  const SseInterruptedException(this.message);

  /// 「连接中断，没有收到结束标记」/「连接中断，没有收到结束事件」。
  final String message;

  @override
  String toString() => message;
}

/// 流式数据超过长度上限（单行 256KB / 单事件 4MB）。
///
/// 与断流异常分开：这是"服务端/中间层在发畸形数据"，不是网络断流；
/// client 层统一按普通错误展示，文案里已写明原因与上限（E-26）。
class SseLimitExceededException implements Exception {
  const SseLimitExceededException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// OpenAI 结束判定：`data: [DONE]`。
bool isOpenAiTerminator(SseEvent event) => event.isDone;

/// Anthropic 结束判定：`event: message_stop`。
bool isAnthropicTerminator(SseEvent event) =>
    event.event == sseEventMessageStop || event.isDone;

/// 把 HTTP 字节流解析成 SSE 事件流。
///
/// [isTerminator] 默认 OpenAI `[DONE]`；Anthropic 传 [isAnthropicTerminator]，
/// 同时把 [interruptedMessage] 传 [sseInterruptedEventMessage]。
/// 流在结束标记之前干净断开时抛出 [SseInterruptedException]。
Stream<SseEvent> parseSse(
  Stream<List<int>> body, {
  SseTerminator? isTerminator,
  String interruptedMessage = sseInterruptedMessage,
  bool emitKeepAlives = false,
}) async* {
  final parser = SseParser(
    isTerminator: isTerminator,
    interruptedMessage: interruptedMessage,
    emitKeepAlives: emitKeepAlives,
  );
  final decoder = const Utf8Decoder(allowMalformed: true)
      .startChunkedConversion(_ParserTextSink(parser));

  await for (final chunk in body) {
    decoder.add(chunk);
    for (final event in parser.take()) {
      yield event;
    }
    if (parser.isTerminated) return;
  }

  decoder.close();
  for (final event in parser.take()) {
    yield event;
  }
  if (parser.isTerminated) return;

  // 没有换行结尾的最后一个事件。
  parser.flush();
  for (final event in parser.take()) {
    yield event;
  }
  if (parser.isTerminated) return;

  throw SseInterruptedException(interruptedMessage);
}

/// 把解码后的文本喂给 [SseParser] 的 Sink。
class _ParserTextSink implements Sink<String> {
  _ParserTextSink(this._parser);

  final SseParser _parser;

  @override
  void add(String data) => _parser.add(data);

  @override
  void close() {
    _parser.flush();
  }
}
