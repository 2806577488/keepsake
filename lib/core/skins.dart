/// Keepsake（留声）— 皮肤注册表（UI 规格 v1.1）。
///
/// **加皮肤只需在 [keepsakeSkins] 追加一条 [Skin] 数据，不改任何 UI 逻辑**：
/// 主题（`core/theme.dart`）、设置页「外观」列表、会话列表头像 / 用户气泡 /
/// 发送键 / 多选竖条全部从注册表读数据。
///
/// 结构：
/// - [SkinTokens]：一套皮肤**覆盖**的 token（README §0 的 3 个差异 + 对应前景色
///   + 多选选中底色 / 竖条）；没写的 token 沿用 §1 基线。
/// - [Skin]：`id`（持久化用的稳定字符串）、`name`（设置页显示）、`description`、
///   浅色覆盖 [Skin.light]、可选深色覆盖 [Skin.dark]（README §8：深底上会消失的
///   颜色必须换亮色；没写就用【基线色 + §8 的通用深色分层】）。
/// - [keepsakeSkins]：内置 3 套（A 基线 / E 撞色 / H 深色锚点，README §0）。
/// - [skinById]：按 id 取皮肤；未知 id **回退第一套**，不抛异常（设置可能来自旧版本）。
library;

import 'package:flutter/material.dart';

/// 默认皮肤 id（README §0 的 A 基线）。
const String kDefaultSkinId = 'a';

/// 一套皮肤覆盖的 token。
///
/// 必填的是 README §0 的 3 个差异 token 与它们的前景色；
/// 其余（AI 头像、多选竖条）可选，缺省由 primaryContainer / primary 推导。
@immutable
class SkinTokens {
  const SkinTokens({
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondaryContainer,
    required this.sendButton,
    required this.onSend,
    required this.listAvatar,
    required this.onListAvatar,
    this.aiAvatar,
    this.onAiAvatar,
    this.selectionBar,
    this.sendBorder,
  });

  /// 用户气泡底（README §0 `primaryContainer`）。
  final Color primaryContainer;

  /// 用户气泡前的文字色 / 选中芯片文字色（README §0 `onPrimaryContainer`）。
  final Color onPrimaryContainer;

  /// 多选选中行浅底（README §0：E 更暖 `#FDE8DC`，A/H `#D9F6EC`）。
  final Color secondaryContainer;

  /// 发送键底（README §0 `sendButton`）。
  final Color sendButton;

  /// 发送键前景（README §0 `onSend`）。
  final Color onSend;

  /// 列表行头像底（README §0 `listAvatar`）。
  final Color listAvatar;

  /// 列表行头像前景（README §0 `onListAvatar`）。
  final Color onListAvatar;

  /// 助手头像底；缺省 = [primaryContainer]。
  final Color? aiAvatar;

  /// 助手头像前景；缺省 = [onPrimaryContainer]。
  final Color? onAiAvatar;

  /// 多选选中行的左侧竖条；缺省 = 基线 primary。
  final Color? selectionBar;

  /// FAB 的 1px 描边；缺省 = 基线 `#8CCDBB`（README §7）。
  final Color? sendBorder;

  /// 助手头像实际底色。
  Color get resolvedAiAvatar => aiAvatar ?? primaryContainer;

  /// 助手头像实际前景。
  Color get resolvedOnAiAvatar => onAiAvatar ?? onPrimaryContainer;
}

/// 一套皮肤 = 稳定 id + 显示名 + 该皮肤覆盖的 token。
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

  /// 设置页显示名（README §0：A 基线 / E 撞色 / H 深色锚点）。
  final String name;

  /// 一句话说明（设置页副标题）。
  final String description;

  /// 浅色模式覆盖。
  final SkinTokens light;

  /// 深色模式覆盖；为空表示沿用 [light]（此时只有 §8 的通用深色分层变化）。
  final SkinTokens? dark;

  /// 是否有深色专用值。
  bool get hasDarkOverride => dark != null;

  /// 取当前亮度下实际生效的 token。
  SkinTokens tokensFor(Brightness brightness) =>
      brightness == Brightness.dark ? (dark ?? light) : light;

  /// 设置页色块预览：用户气泡底 / 发送键 / 列表头像（顺序固定，纯数据）。
  List<Color> get swatches => <Color>[
    light.primaryContainer,
    light.sendButton,
    light.listAvatar,
  ];
}

// ---------------------------------------------------------------------------
// 内置皮肤（README §0 / §7；深色见 §8）
// ---------------------------------------------------------------------------

/// A 基线：全屏中高明度，无深色锚点。
const Skin kSkinA = Skin(
  id: 'a',
  name: 'A 基线',
  description: '高明度青绿，最接近默认阅读体验',
  light: SkinTokens(
    primaryContainer: Color(0xFFA0F2DF),
    onPrimaryContainer: Color(0xFF005045),
    secondaryContainer: Color(0xFFD9F6EC),
    sendButton: Color(0xFFA0F2DF),
    onSend: Color(0xFF005045),
    listAvatar: Color(0xFFDEE4E1),
    onListAvatar: Color(0xFF496F66),
    aiAvatar: Color(0xFFA0F2DF),
    onAiAvatar: Color(0xFF005045),
    selectionBar: Color(0xFF046B5C),
    sendBorder: Color(0xFF8CCDBB),
  ),
);

/// E 撞色：人对暖、AI 对冷，发送键暖实心，多选偏暖。
const Skin kSkinE = Skin(
  id: 'e',
  name: 'E 撞色',
  description: '暖色发送键与选中态，冷绿只留给 AI',
  light: SkinTokens(
    primaryContainer: Color(0xFFFFDCC8),
    onPrimaryContainer: Color(0xFF6B2A10),
    secondaryContainer: Color(0xFFFDE8DC),
    sendButton: Color(0xFFD9622B),
    onSend: Color(0xFFFFFFFF),
    listAvatar: Color(0xFFDEE4E1),
    onListAvatar: Color(0xFF496F66),
    aiAvatar: Color(0xFFA0F2DF),
    onAiAvatar: Color(0xFF005045),
    selectionBar: Color(0xFFB4481B),
    sendBorder: Color(0xFFE9A17C),
  ),
);

/// H 深色锚点：头像与发送键压到同族深青 `#1F4A42`，有画面重量。
///
/// README §8：`#1F4A42` 在深底上会消失 → 深色模式换成亮底 `#8FD6C5` / 前景
/// `#062019`（用户气泡仍用 `#A0F2DF`，它在深底上是可读的高亮色块）。
const Skin kSkinH = Skin(
  id: 'h',
  name: 'H 深色锚点',
  description: '深青锚点，头像与发送键更有重量',
  light: SkinTokens(
    primaryContainer: Color(0xFFA0F2DF),
    onPrimaryContainer: Color(0xFF005045),
    secondaryContainer: Color(0xFFD9F6EC),
    sendButton: Color(0xFF1F4A42),
    onSend: Color(0xFFA7E6D5),
    listAvatar: Color(0xFF1F4A42),
    onListAvatar: Color(0xFFA7E6D5),
    aiAvatar: Color(0xFF1F4A42),
    onAiAvatar: Color(0xFFA7E6D5),
    selectionBar: Color(0xFF046B5C),
    sendBorder: Color(0xFF8CCDBB),
  ),
  dark: SkinTokens(
    primaryContainer: Color(0xFFA0F2DF),
    onPrimaryContainer: Color(0xFF005045),
    secondaryContainer: Color(0xFFD9F6EC),
    // §8：深底上换亮色，前景换暗色。
    sendButton: Color(0xFF8FD6C5),
    onSend: Color(0xFF062019),
    listAvatar: Color(0xFF8FD6C5),
    onListAvatar: Color(0xFF062019),
    aiAvatar: Color(0xFF8FD6C5),
    onAiAvatar: Color(0xFF062019),
    selectionBar: Color(0xFF8FD6C5),
    sendBorder: Color(0xFF3F7F73),
  ),
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
