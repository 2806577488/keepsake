/// Keepsake（留声）— 皮肤注册表（UI 规格 v2 拍板稿）。
///
/// **加皮肤只需在 [keepsakeSkins] 追加一条 [Skin] 数据，不改任何 UI 逻辑**：
/// 主题（`core/theme.dart`）、设置页「外观」列表、会话列表、聊天气泡、
/// 发送键、FAB、弹层全部从注册表读 token。
///
/// 结构：
/// - [SkinTokens]（`core/skin_tokens.dart`）：一套皮肤的颜色 [SkinColors] +
///   形态 [SkinMorph]，并暴露预构造圆角。**所有色值与圆角只有那一个出处。**
/// - [Skin]：`id`（持久化稳定字符串）、`name` / `description`（设置页显示）、
///   浅色 [Skin.light]、可选深色 [Skin.dark]。
/// - [keepsakeSkins]：内置 3 套（A 清透 / E 纸感 / H 墨色）。
/// - [skinById]：按 id 取皮肤；未知 id **回退第一套**，不抛异常（设置可能来自旧版本）。
library;

import 'package:flutter/material.dart';

import 'skin_tokens.dart';

export 'skin_tokens.dart';

/// 默认皮肤 id（A 清透）。
const String kDefaultSkinId = 'a';

/// 一套皮肤 = 稳定 id + 显示名 + 浅/深两套 token。
@immutable
class Skin {
  const Skin({
    required this.id,
    required this.name,
    required this.description,
    required this.light,
    this.dark,
  });

  /// 持久化 id（`settings.skin_id`），只允许小写字母/数字/短横线。
  final String id;

  /// 设置页显示名（拍板稿：A 清透 / E 纸感 / H 墨色）。
  final String name;

  /// 一句话说明（设置页副标题）。
  final String description;

  /// 浅色 token（设计稿只给了浅色）。
  final SkinTokens light;

  /// 深色 token；为空表示沿用 [light]。
  final SkinTokens? dark;

  /// 是否有深色专用值。
  bool get hasDarkOverride => dark != null;

  /// 取当前亮度下实际生效的 token。
  SkinTokens tokensFor(Brightness brightness) =>
      brightness == Brightness.dark ? (dark ?? light) : light;

  /// 设置页色块预览：用户气泡底 / 发送键 / 列表头像（顺序固定，纯数据）。
  List<Color> get swatches => <Color>[
    light.colors.pC,
    light.colors.sendBg,
    light.colors.avBg,
  ];
}

// ---------------------------------------------------------------------------
// 内置皮肤（拍板稿 §4）
// ---------------------------------------------------------------------------

/// A 清透：大圆角 + 胶囊，系统无衬线，实心 24 图标。
const Skin kSkinA = Skin(
  id: 'a',
  name: 'A 清透',
  description: '大圆角胶囊，轻薄通透，最接近默认阅读体验',
  light: SkinTokens.a,
  dark: SkinTokens.aDark,
);

/// E 纸感：小圆角 8/6/4，宋体正文，描边 24 图标，卡片 1px 描边。
const Skin kSkinE = Skin(
  id: 'e',
  name: 'E 纸感',
  description: '宋体纸面，小圆角与细描边，像一页信纸',
  light: SkinTokens.e,
  dark: SkinTokens.eDark,
);

/// H 墨色：中圆角偏方，字重 700，图标 26，深青块面。
const Skin kSkinH = Skin(
  id: 'h',
  name: 'H 墨色',
  description: '深青块面与粗标题，三套里最「重」的一套',
  light: SkinTokens.h,
  dark: SkinTokens.hDark,
);

/// 内置皮肤注册表（顺序 = 设置页显示顺序）。
///
/// **加第 4 套皮肤：在这里追加一条 [Skin]，别改 UI。**
const List<Skin> keepsakeSkins = <Skin>[kSkinA, kSkinE, kSkinH];

/// 按 id 取皮肤；未知 / 空 id 回退第一套（不抛异常）。
Skin skinById(String? id) {
  final key = (id ?? '').trim().toLowerCase();
  if (key.isEmpty) return keepsakeSkins.first;
  for (final skin in keepsakeSkins) {
    if (skin.id == key) return skin;
  }
  return keepsakeSkins.first;
}

/// 当前 id 是否在注册表里（设置页判断「未知 id 回退」用）。
bool hasSkin(String? id) {
  final key = (id ?? '').trim().toLowerCase();
  return keepsakeSkins.any((Skin skin) => skin.id == key);
}
