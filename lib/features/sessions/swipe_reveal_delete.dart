/// Keepsake（留声）— 会话列表的「左滑露出删除」行（v0.4.43）。
///
/// 之前用 `Dismissible`：背景红条只是画出来的，松手就弹回去，
/// 那个垃圾桶图标**永远点不到**（用户反馈「像能点，其实点了没反应」）。
///
/// 这里改成会**停住**的滑出：
/// - 左滑范围 0..88dp，松手后吸附到「开/关」；
/// - 滑开后点垃圾桶 → 走外部确认逻辑；点行体 → 只收起，不进入会话；
/// - 快速一甩（velocity < -700）→ 直接弹确认。
library;

import 'package:flutter/material.dart';

/// 可停留的左滑删除行。
class SwipeRevealDelete extends StatefulWidget {
  const SwipeRevealDelete({
    super.key,
    required this.child,
    required this.onDelete,
    this.enabled = true,
    this.revealWidth = 88,
  });

  /// 行内容。
  final Widget child;

  /// 点垃圾桶（或快速一甩）时触发：外部负责「确认 + 删除」。
  final Future<void> Function() onDelete;

  /// 选择态等场景可禁用滑动。
  final bool enabled;

  /// 露出的删除区宽度。
  final double revealWidth;

  @override
  State<SwipeRevealDelete> createState() => _SwipeRevealDeleteState();
}

class _SwipeRevealDeleteState extends State<SwipeRevealDelete> {
  double _offset = 0;

  bool get _open => _offset < 0;

  void _onDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled) return;
    setState(() {
      _offset = (_offset + details.delta.dx).clamp(-widget.revealWidth, 0.0);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (!widget.enabled) return;
    final double velocity = details.primaryVelocity ?? 0;
    if (velocity < -700) {
      // 快速一甩：视为「要删除」，直接弹确认。
      _confirmAndDelete();
      return;
    }
    setState(() {
      _offset = (velocity < -300 || _offset < -widget.revealWidth / 2)
          ? -widget.revealWidth
          : 0;
    });
  }

  void _close() {
    if (_offset != 0) setState(() => _offset = 0);
  }

  Future<void> _confirmAndDelete() async {
    _close();
    await widget.onDelete();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: Container(
            color: scheme.errorContainer,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              tooltip: '删除会话',
              onPressed: _confirmAndDelete,
              icon: Icon(
                Icons.delete_outline,
                color: scheme.onErrorContainer,
              ),
            ),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          // 滑开时点行体只收起，不进入会话；关着时不拦截点击。
          onTap: _open ? _close : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(_offset, 0, 0),
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
