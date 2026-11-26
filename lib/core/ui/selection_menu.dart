/// Keepsake（留声）— 自定义文本选择菜单（v0.4.42）。
///
/// 原生选择菜单会混进别的 App 注册的「文本处理」项（问AI / 去七猫看看…），
/// 而且标签是英文（Copy / Share / Select all）。这里换成 App 自己画的菜单：
/// 只有「复制 / 分享 / 全选」，中文标签，顺带把第三方注入项挡在外面。
library;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// 给 `TextField` / `SelectableText` 的 `contextMenuBuilder` 用。
Widget keepsakeContextMenu(BuildContext context, EditableTextState editableTextState) {
  final value = editableTextState.textEditingValue;
  final selection = value.selection;
  final hasSelection = !selection.isCollapsed && selection.isValid;
  final items = <ContextMenuButtonItem>[
    if (hasSelection)
      ContextMenuButtonItem(
        label: '复制',
        onPressed: () {
          editableTextState.copySelection(SelectionChangedCause.toolbar);
          ContextMenuController.removeAny();
        },
      ),
    if (hasSelection)
      ContextMenuButtonItem(
        label: '分享',
        onPressed: () {
          final text = selection.textInside(value.text);
          ContextMenuController.removeAny();
          final trimmed = text.trim();
          if (trimmed.isNotEmpty) {
            SharePlus.instance.share(ShareParams(text: trimmed));
          }
        },
      ),
    ContextMenuButtonItem(
      label: '全选',
      onPressed: () {
        editableTextState.selectAll(SelectionChangedCause.toolbar);
        ContextMenuController.removeAny();
      },
    ),
  ];
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editableTextState.contextMenuAnchors,
    buttonItems: items,
  );
}
