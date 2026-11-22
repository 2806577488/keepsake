/// Keepsake（留声）— 无权限页内卡片（v3.2 §2.4）。
///
/// **位置：页面内卡片，不是弹窗**——弹窗会被系统权限框叠住，很难看。
///
/// 几何 / 颜色（v3.2 §2.4）：
/// - 图标：`warn` 20dp，色 `errC`；
/// - 标题：`fsTitle` / `onS`；
/// - 说明：`fsSub` / `onV`，最多两行；
/// - 主按钮「去授权」：`pC` 底 + `onPC` 字，高 36dp，圆角 `rChip`；
/// - 次按钮「稍后」：纯文字，`onV`；
/// - **被永久拒绝时**（选了「不再询问」）：主按钮换成「去设置」，
///   并在说明里补一句「需要到系统设置里开启」。
library;

import 'package:flutter/material.dart';

import 'package:keepsake/core/theme.dart';

/// 权限被拒时显示的页内卡片。
class PermissionDeniedCard extends StatelessWidget {
  const PermissionDeniedCard({
    super.key,
    required this.title,
    required this.description,
    required this.onGrant,
    required this.onLater,
    this.permanent = false,
  });

  /// 标题（「需要存储权限才能导入」）。
  final String title;

  /// 说明（最多两行）。
  final String description;

  /// 是否是「永久拒绝」：主按钮换「去设置」并补一句系统设置说明。
  final bool permanent;

  /// 主按钮：请求授权 / 跳系统设置。
  final VoidCallback onGrant;

  /// 次按钮「稍后」：收起卡片。
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final KeepsakeSkinColors s = KeepsakeSkinColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          // 卡片底走 high 层，描边只有 E 会画（hairlineBorder 自带判断）。
          color: s.c.high,
          borderRadius: s.rCard,
          border: s.hairlineBorder,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.warning_amber_rounded, size: 20, color: s.c.errC),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: s.fsTitle,
                      fontWeight: s.titleWeight,
                      letterSpacing: s.titleLetterSpacing,
                      color: s.c.onS,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    permanent
                        ? '$description 需要到系统设置里开启。'
                        : description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: s.fsSub,
                      color: s.c.onV,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: s.c.pC,
                          foregroundColor: s.c.onPC,
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: s.rChip,
                          ),
                          textStyle: theme.textTheme.labelLarge?.copyWith(
                            fontSize: s.fsSub,
                            fontWeight: s.titleWeight,
                          ),
                        ),
                        onPressed: onGrant,
                        child: Text(permanent ? '去设置' : '去授权'),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: s.c.onV,
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          textStyle: theme.textTheme.labelLarge?.copyWith(
                            fontSize: s.fsSub,
                          ),
                        ),
                        onPressed: onLater,
                        child: const Text('稍后'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
