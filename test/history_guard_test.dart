import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepsake/core/api/chat_backend.dart';
import 'package:keepsake/core/chat/history_guard.dart';

/// 历史交替规范化单测（v0.4.40 修复 400「an assistant message must follow a user message」）。
///
/// 这个 bug 的现场：上一轮助手回答中断（content 为空），`_buildRequest` 会把空消息
/// 跳掉，于是历史里出现「user, user」，账号型 Messages 传输直接 400。
/// 下面既有定点用例，也有**属性测试**（随机序列），保证同类问题不会再混过去。
void main() {
  ChatTurn user(String text) => ChatTurn.user(text);
  ChatTurn assistant(String text) => ChatTurn.assistant(text);

  test('现场复现：空 assistant 被跳过后剩下连续两条 user', () {
    // 模拟 _buildRequest：先过滤空内容，再做规范化。
    final rows = <ChatTurn>[
      user('第一句问题'),
      assistant(''), // 中断的回答：content 为空 → 请求里被跳过
      user('第二句问题'),
    ];
    final filtered = rows.where((turn) => turn.content.trim().isNotEmpty).toList();
    final out = normalizeHistoryAlternation(filtered);
    expect(out.length, 1);
    expect(out.first.isUser, true);
    expect(out.first.content.contains('第一句问题'), true);
    expect(out.first.content.contains('第二句问题'), true);
  });

  test('开头的 assistant 被丢掉（请求必须以 user 开始）', () {
    final out = normalizeHistoryAlternation(<ChatTurn>[
      assistant('孤儿回答'),
      user('问题'),
      assistant('回答'),
    ]);
    expect(out.length, 2);
    expect(out.first.isUser, true);
  });

  test('连续两条 assistant 保留较长的一条', () {
    final out = normalizeHistoryAlternation(<ChatTurn>[
      user('问题'),
      assistant('短'),
      assistant('这是一段更长的完整回答'),
    ]);
    expect(out.length, 2);
    expect(out.last.content.contains('完整回答'), true);
  });

  test('正常交替原样保留', () {
    final input = <ChatTurn>[
      user('q1'),
      assistant('a1'),
      user('q2'),
      assistant('a2'),
    ];
    final out = normalizeHistoryAlternation(input);
    expect(out.length, 4);
    expect(
      out.map((turn) => turn.isUser).toList(),
      <bool>[true, false, true, false],
    );
  });

  test('空列表返回空', () {
    expect(normalizeHistoryAlternation(const <ChatTurn>[]), isEmpty);
  });

  test('属性测试：任意序列规范化后都严格交替、以 user 开头、user 内容不丢', () {
    final random = Random(42);
    for (var round = 0; round < 300; round++) {
      final length = random.nextInt(14);
      final turns = <ChatTurn>[];
      for (var i = 0; i < length; i++) {
        final text = '消息$i';
        turns.add(random.nextBool() ? user(text) : assistant(text));
      }
      final out = normalizeHistoryAlternation(turns);
      final reason = 'round=$round input='
          '${turns.map((turn) => turn.isUser ? 'U' : 'A').join()}';
      if (out.isNotEmpty) {
        expect(out.first.isUser, true, reason: '首条必须是 user：$reason');
        for (var i = 1; i < out.length; i++) {
          expect(
            out[i].isUser,
            !out[i - 1].isUser,
            reason: '必须严格交替：$reason',
          );
        }
      }
      // user 内容一条都不能丢（合并后应包含原文本）。
      final merged = out
          .where((turn) => turn.isUser)
          .map((turn) => turn.content)
          .join('\n');
      for (final turn in turns.where((turn) => turn.isUser)) {
        expect(merged.contains(turn.content), true, reason: '内容丢失：$reason');
      }
    }
  });
}
