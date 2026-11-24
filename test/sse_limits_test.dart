/// SSE 长度上限的回归测试（E-26）。
///
/// 背景：SSE 是"服务端想发多长就多长"的协议，解析器按行缓冲、按事件累积；
/// 坏服务端/被劫持的中间层可以用超长行或超大事件把内存吃满。
/// 这里用两个极端输入确认会抛 [SseLimitExceededException]，正常小块不受影响。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:keepsake/core/api/sse.dart';

void main() {
  test('单行超过 256KB 直接中断', () {
    final parser = SseParser();
    final String huge = 'data:${'x' * (sseMaxLineChars + 10)}';
    expect(
      () => parser.add(huge),
      throwsA(isA<SseLimitExceededException>()),
    );
  });

  test('单事件超过 4MB 直接中断', () {
    final parser = SseParser();
    // 每行 250KB（低于单行上限），累计超过 4MB 时应当中断。
    final String line = 'data:${'y' * (250 * 1024)}\n';
    var thrown = false;
    try {
      for (var i = 0; i < 20; i++) {
        parser.add(line);
      }
    } on SseLimitExceededException {
      thrown = true;
    }
    expect(thrown, isTrue);
  });

  test('正常小事件不受影响', () {
    final parser = SseParser();
    parser.add('data: {"a":1}\n\n');
    final events = parser.take();
    expect(events, hasLength(1));
    expect(events.first.data.trim(), '{"a":1}');
  });
}
