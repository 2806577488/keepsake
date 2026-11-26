/// Keepsake（留声）— 历史消息的「交替规范化」（v0.4.39 修复）。
///
/// ## 为什么需要
///
/// 账号型传输（DeepSeek 的 Messages 接口）要求消息**严格 user/assistant 交替**，
/// 否则直接返回 400：`an assistant message must follow a user message`。
///
/// 而 `_buildRequest` 会跳过"内容为空"的 assistant 消息（中断/失败的回答），
/// 于是历史里可能出现连续两条 user；超窗裁剪也可能从 assistant 中间开始。
///
/// 这里在**发请求前**做一次兜底：
/// 1. 开头的 assistant 丢掉（请求必须以 user 开始）；
/// 2. 相邻同角色合并（user 拼接正文；assistant 保留较长的一条）。
library;

import '../api/chat_backend.dart';

/// 把历史整理成严格交替的消息序列。
List<ChatTurn> normalizeHistoryAlternation(List<ChatTurn> turns) {
  final out = <ChatTurn>[];
  for (final turn in turns) {
    if (out.isEmpty) {
      // 第一条必须是 user；开头的 assistant 通常是裁窗/失败留下的孤儿。
      if (turn.isUser) out.add(turn);
      continue;
    }
    final last = out.last;
    if (last.isUser == turn.isUser) {
      if (turn.isUser) {
        // 连续两条 user：拼起来，别丢内容。
        out[out.length - 1] = ChatTurn(
          role: turn.role,
          content: '${last.content}\n\n${turn.content}',
        );
      } else if (turn.content.length > last.content.length) {
        // 连续两条 assistant：保留较长的一条（通常是完整的那次）。
        out[out.length - 1] = turn;
      }
    } else {
      out.add(turn);
    }
  }
  return List<ChatTurn>.unmodifiable(out);
}
