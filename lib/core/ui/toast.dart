/// Keepsake（留声）— 顶部轻提示（toast）。
///
/// 为什么不用 SnackBar：`ScaffoldMessenger` 的 SnackBar 只能贴在 Scaffold 底部，
/// 而聊天页底部正好是输入栏 + 工具芯片 —— 弹出来就盖住用户正在看/正在点的地方
/// （截图里「思考：开（中）」直接糊在输入框上，红色框就是用户画的）。这里改用
/// `Overlay` 画一条**顶部浮层**：
///
/// - 位置：状态栏 + AppBar 下方 8dp，任何页面都不会压到输入区；
/// - 不拦手势（`IgnorePointer`）：出现/消失时都不影响输入、滚动、点按；
/// - 同屏只留一条：新提示先移除旧的，不会叠成一摞；
/// - 2 秒自动消失，120ms 淡入 + 8dp 上浮（与设计库 SPEC §4.9 一致）。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';

/// 当前正在显示的提示（全局只保留一条）。
OverlayEntry? _entry;
Timer? _timer;

/// 在**顶部**显示一条轻提示，默认 [duration] 后自动消失。
///
/// 没有 Overlay（比如页面刚 pop 掉）时静默返回 —— 提示失败不该再抛异常。
void showTopToast(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 2),
}) {
  final String text = message.trim();
  if (text.isEmpty) return;
  final OverlayState? overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  dismissTopToast();
  final OverlayEntry entry = OverlayEntry(
    builder: (BuildContext overlayContext) => _TopToast(message: text),
  );
  _entry = entry;
  overlay.insert(entry);
  _timer = Timer(duration, dismissTopToast);
}

/// 立刻收掉当前提示（新提示出现前、或页面销毁时用）。
void dismissTopToast() {
  _timer?.cancel();
  _timer = null;
  final OverlayEntry? entry = _entry;
  _entry = null;
  if (entry != null && entry.mounted) {
    entry.remove();
  }
}

/// 提示本体：顶部居中、黑底白字（M3 `inverseSurface`）、圆角走皮肤 token。
class _TopToast extends StatelessWidget {
  const _TopToast({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final KeepsakeSkinColors skin = KeepsakeSkinColors.of(context);
    // 顶部留白 = 状态栏 + AppBar(56) + 8。用 MediaQuery 的 padding 而不是写死
    // 24，刘海/挖孔机型才不会把提示压到状态栏里。
    final double top = MediaQuery.paddingOf(context).top + 64;
    return Positioned(
      top: top,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          builder: (BuildContext context, double value, Widget? child) {
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 8 * (1 - value)),
                child: child,
              ),
            );
          },
          child: Align(
            alignment: Alignment.topCenter,
            child: Semantics(
              liveRegion: true,
              label: message,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Material(
                  color: scheme.inverseSurface,
                  elevation: 0,
                  borderRadius: skin.rCard,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Text(
                      message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 14,
                        color: scheme.onInverseSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
