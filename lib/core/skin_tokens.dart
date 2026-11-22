/// Keepsake（留声）— 皮肤 Token 层（UI 规格 v2 拍板稿）。
///
/// **本文件是工程里唯一允许出现 `Color(0x..)` 与 `BorderRadius.circular(..)`
/// 字面量的地方**，其余页面必须从这里取（`KeepsakeSkinColors.of(context)`）。
/// 验收：`grep -rn "0xFF" lib/ | grep -v skin_tokens.dart` 为空。
///
/// 结构：
/// - [SkinColors]：一套皮肤的全部颜色（拍板稿 §4.1 全表），浅色 3 套 + 深色 3 套。
/// - [SkinMorph]：一套皮肤的**形态**（圆角 / 字号 / 字重 / 行高 / 图标 / 字体），
///   拍板稿 §4.2。三套皮肤的差异全在这里，不在页面里 `switch (skinId)`。
/// - [SkinTokens]：颜色 + 形态 = 一套皮肤的全部 token，并暴露**预构造圆角**，
///   页面用 `tokens.rBubble` 而不是 `BorderRadius.circular(16)`。
/// - 各套尺寸常量（行高 68 / chip 32 / 抓手 36×4 …）：三套一致，做顶层 const。
///
/// 深色：本轮设计稿只给浅色三套（设计师回应 §6「深色模式需要独立设计一轮」），
/// 这里保留 v1.1 的深色分层，避免深色模式下整屏同色；深色不参与本轮验收。
library;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// 三套一致的结构常量（拍板稿 §1 / §2）
// ---------------------------------------------------------------------------

/// 列表行高 68（三套一致，拍板稿 §1）。
const double kRowHeight = 68;

/// 列表左右内边距 16。
const double kPagePadding = 16;

/// 列表头像 34（拍板稿 §1：E 也是 34，只是方角）。
const double kListAvatarSize = 34;

/// 复选框 / 单选按钮外框 20（SPEC §4.7）。
const double kCheckboxSize = 20;

/// 复选框槽位 34（与头像同宽，多选态文字不位移）。
const double kCheckboxSlot = 34;

/// 当前行竖条 2px（拍板稿 §1）。
const double kSelectionBarWidth = 2;

/// chip 高 32 / 左右内距 12 / 图标 15 / 文字 12（拍板稿 §1、SPEC §4.8）。
const double kChipHeight = 32;
const double kChipPadH = 12;
const double kChipIconSize = 15;
const double kChipFontSize = 12;

/// 动作条（朗读 / 复制 / 重答 / 分支）：图标 15、文字 12、图标↔文字 5、项间距 16。
const double kActionIconSize = 15;
const double kActionFontSize = 12;
const double kActionGap = 5;
const double kActionSpacing = 16;
const double kActionIndent = 30;

/// 发送键 44、FAB 高 56（SPEC §4.5）。
const double kSendSize = 44;
const double kFabHeight = 56;

/// 顶栏 56（SPEC §4.1）。
const double kBarHeight = 56;

/// 底部弹层：抓手 36×4、内边距 20、按钮高 38（SPEC §4.6）。
const double kSheetGrabberW = 36;
const double kSheetGrabberH = 4;
const double kSheetPadding = 20;
const double kSheetButtonHeight = 38;

/// 设置项 64 / 弹层选项行 64。
const double kSettingsRowHeight = 64;
const double kSheetRowHeight = 64;

/// 等宽字体族（等宽元信息、代码块）。
const String kMonoFontFamily = 'monospace';

/// E 纸感的主字体与兜底（拍板稿 §3：思源宋体子集打包前先靠系统宋体）。
///
/// **现状**：Android 很多机型没有宋体，`SimSun` 兜底不保证命中，
/// 未打包字体的机型上 E 会退回系统黑体，只剩颜色/圆角差异。
/// E 纸感的主字体：打包的思源宋体子集（`assets/fonts/KeepsakeSerif-subset.otf`）。
///
/// 为什么不像 A/H 用系统字体：国产机型不一定有衬线体，而写死 `'Songti SC'`
/// 或 `'serif'` 回退时还会把「（官方）」这类字符渲染成乱码。打包字体后
/// E 在所有机型上都是同一套宋体，观感才稳定。
const String kSerifFontFamily = 'KeepsakeSerif';
const List<String> kSerifFontFallback = <String>[
  'Noto Serif CJK SC',
  'Source Han Serif SC',
  'SimSun',
];

/// seed 主色（v1.1 基线，M3 派生用）。
const Color kSeedColor = Color(0xFF2F6B5F);

// ---------------------------------------------------------------------------
// 图标风格
// ---------------------------------------------------------------------------

/// 图标风格：A/H 实心（filled），E 描边（outlined）。
enum IconMood { filled, outlined }

// ---------------------------------------------------------------------------
// 颜色 token
// ---------------------------------------------------------------------------

/// 一套皮肤的全部颜色（拍板稿 §4.1）。
@immutable
class SkinColors {
  const SkinColors({
    required this.surface,
    required this.low,
    required this.high,
    required this.highest,
    required this.usage,
    required this.ov,
    required this.outline,
    required this.onS,
    required this.onV,
    required this.pC,
    required this.onPC,
    required this.sendBg,
    required this.sendFg,
    required this.aiBg,
    required this.aiFg,
    required this.avBg,
    required this.avFg,
    required this.errC,
    required this.errBg,
    required this.onErrBg,
    required this.iconC,
    required this.selBg,
    required this.selBar,
    required this.codeBg,
    required this.codeHead,
    required this.codeDiv,
    required this.codeFg,
  });

  /// 页面底。
  final Color surface;

  /// 一级容器（surfaceContainerLow）。
  final Color low;

  /// 二级容器（surfaceContainerHigh）。
  final Color high;

  /// 三级容器（surfaceContainerHighest）。
  final Color highest;

  /// 思考过程条底色。
  final Color usage;

  /// 分割线 / 卡片描边色（outlineVariant）。
  final Color ov;

  /// 外框 / 未选控件描边（outline）。
  final Color outline;

  /// 主文字。
  final Color onS;

  /// 次要文字 / 元信息。
  final Color onV;

  /// 用户气泡底（primaryContainer）。
  final Color pC;

  /// 用户气泡文字（onPrimaryContainer）。
  final Color onPC;

  /// 发送键底。
  final Color sendBg;

  /// 发送键前景。
  final Color sendFg;

  /// AI 气泡底。
  final Color aiBg;

  /// AI 气泡文字。
  final Color aiFg;

  /// 列表头像底。
  final Color avBg;

  /// 列表头像前景。
  final Color avFg;

  /// 错误色 / 错误容器 / 容器前景。
  final Color errC;
  final Color errBg;
  final Color onErrBg;

  /// 图标色（H 用深青）。
  final Color iconC;

  /// 多选选中底色 / 选中竖条。
  final Color selBg;
  final Color selBar;

  /// 代码块：底 / 头 / 分隔线 / 文字。
  final Color codeBg;
  final Color codeHead;
  final Color codeDiv;
  final Color codeFg;

  /// A 清透。
  static const SkinColors a = SkinColors(
    surface: Color(0xFFF5FBF7),
    low: Color(0xFFEFF5F2),
    high: Color(0xFFE3EAE6),
    highest: Color(0xFFDEE4E1),
    usage: Color(0xFFE9EFEC),
    ov: Color(0xFFCAD1CD),
    outline: Color(0xFF7C8B86),
    onS: Color(0xFF191C1B),
    onV: Color(0xFF496F66),
    pC: Color(0xFFA0F2DF),
    onPC: Color(0xFF005045),
    sendBg: Color(0xFFA0F2DF),
    sendFg: Color(0xFF005045),
    aiBg: Color(0xFFA0F2DF),
    aiFg: Color(0xFF005045),
    avBg: Color(0xFFDEE4E1),
    avFg: Color(0xFF496F66),
    errC: Color(0xFFBA1A1A),
    errBg: Color(0xFFFFDAD6),
    onErrBg: Color(0xFF410002),
    iconC: Color(0xFF191C1B),
    selBg: Color(0xFFD9F6EC),
    selBar: Color(0xFF046B5C),
    codeBg: Color(0xFFFFFFFF),
    codeHead: Color(0xFFE7F3EF),
    codeDiv: Color(0xFFD5EAE3),
    codeFg: Color(0xFF161B1A),
  );

  /// E 纸感。
  static const SkinColors e = SkinColors(
    surface: Color(0xFFFDFCF9),
    low: Color(0xFFF1EDE4),
    high: Color(0xFFE8E2D6),
    highest: Color(0xFFDEE4E1),
    usage: Color(0xFFF1EDE4),
    ov: Color(0xFFD8D4CC),
    outline: Color(0xFF7C8B86),
    onS: Color(0xFF1A1A18),
    onV: Color(0xFF5C5A54),
    pC: Color(0xFFF2D9C4),
    onPC: Color(0xFF5A2E14),
    sendBg: Color(0xFFB4481B),
    sendFg: Color(0xFFFFFFFF),
    aiBg: Color(0xFFA0F2DF),
    aiFg: Color(0xFF005045),
    avBg: Color(0xFFDEE4E1),
    avFg: Color(0xFF496F66),
    errC: Color(0xFFBA1A1A),
    errBg: Color(0xFFFFDAD6),
    onErrBg: Color(0xFF410002),
    iconC: Color(0xFF191C1B),
    selBg: Color(0xFFF0E4D6),
    selBar: Color(0xFFB4481B),
    codeBg: Color(0xFFF1EDE4),
    codeHead: Color(0xFFE8E2D6),
    codeDiv: Color(0xFFD8D4CC),
    codeFg: Color(0xFF1A1A18),
  );

  /// H 墨色。
  static const SkinColors h = SkinColors(
    surface: Color(0xFFF5FBF7),
    low: Color(0xFFEFF5F2),
    high: Color(0xFFE3EAE6),
    highest: Color(0xFFDEE4E1),
    usage: Color(0xFFE9EFEC),
    ov: Color(0xFFCAD1CD),
    outline: Color(0xFF7C8B86),
    onS: Color(0xFF191C1B),
    onV: Color(0xFF496F66),
    pC: Color(0xFFA0F2DF),
    onPC: Color(0xFF005045),
    sendBg: Color(0xFF1F4A42),
    sendFg: Color(0xFFA7E6D5),
    aiBg: Color(0xFF1F4A42),
    aiFg: Color(0xFFA7E6D5),
    avBg: Color(0xFF1F4A42),
    avFg: Color(0xFFA7E6D5),
    errC: Color(0xFFBA1A1A),
    errBg: Color(0xFFFFDAD6),
    onErrBg: Color(0xFF410002),
    iconC: Color(0xFF1F4A42),
    selBg: Color(0xFFD9F6EC),
    selBar: Color(0xFF046B5C),
    codeBg: Color(0xFF1F4A42),
    codeHead: Color(0xFF173832),
    codeDiv: Color(0xFF2A5A50),
    codeFg: Color(0xFFA7E6D5),
  );

  // ---- 深色（本轮不验收，沿用 v1.1 分层 + 深底上会消失的锚点换亮色）----

  /// A 深色。
  static const SkinColors aDark = SkinColors(
    surface: Color(0xFF101614),
    low: Color(0xFF161D1A),
    high: Color(0xFF1C2421),
    highest: Color(0xFF232C28),
    usage: Color(0xFF1C2421),
    ov: Color(0xFF3A4A45),
    outline: Color(0xFF7F948E),
    onS: Color(0xFFE6EFEA),
    onV: Color(0xFFA3C1B7),
    pC: Color(0xFFA0F2DF),
    onPC: Color(0xFF005045),
    sendBg: Color(0xFFA0F2DF),
    sendFg: Color(0xFF005045),
    aiBg: Color(0xFFA0F2DF),
    aiFg: Color(0xFF005045),
    avBg: Color(0xFF8CCDBB),
    avFg: Color(0xFF062019),
    errC: Color(0xFFFFB4AB),
    errBg: Color(0xFF93000A),
    onErrBg: Color(0xFFFFDAD6),
    iconC: Color(0xFFE6EFEA),
    selBg: Color(0xFF043C34),
    selBar: Color(0xFF8CCDBB),
    codeBg: Color(0xFF161D1A),
    codeHead: Color(0xFF22302B),
    codeDiv: Color(0xFF2E3D37),
    codeFg: Color(0xFFE6EFEA),
  );

  /// E 深色。
  static const SkinColors eDark = SkinColors(
    surface: Color(0xFF151310),
    low: Color(0xFF1D1A16),
    high: Color(0xFF26221D),
    highest: Color(0xFF2F2A24),
    usage: Color(0xFF26221D),
    ov: Color(0xFF4A443C),
    outline: Color(0xFF948C80),
    onS: Color(0xFFF2EDE4),
    onV: Color(0xFFC4BAAB),
    pC: Color(0xFFF2D9C4),
    onPC: Color(0xFF5A2E14),
    sendBg: Color(0xFFB4481B),
    sendFg: Color(0xFFFFFFFF),
    aiBg: Color(0xFFA0F2DF),
    aiFg: Color(0xFF005045),
    avBg: Color(0xFF8CCDBB),
    avFg: Color(0xFF062019),
    errC: Color(0xFFFFB4AB),
    errBg: Color(0xFF93000A),
    onErrBg: Color(0xFFFFDAD6),
    iconC: Color(0xFFF2EDE4),
    selBg: Color(0xFF3A2A1E),
    selBar: Color(0xFFE9A17C),
    codeBg: Color(0xFF1D1A16),
    codeHead: Color(0xFF26221D),
    codeDiv: Color(0xFF3A342C),
    codeFg: Color(0xFFF2EDE4),
  );

  /// H 深色：深青在深底上会消失 → 换亮青。
  static const SkinColors hDark = SkinColors(
    surface: Color(0xFF101614),
    low: Color(0xFF161D1A),
    high: Color(0xFF1C2421),
    highest: Color(0xFF232C28),
    usage: Color(0xFF1C2421),
    ov: Color(0xFF3A4A45),
    outline: Color(0xFF7F948E),
    onS: Color(0xFFE6EFEA),
    onV: Color(0xFFA3C1B7),
    pC: Color(0xFFA0F2DF),
    onPC: Color(0xFF005045),
    sendBg: Color(0xFF8FD6C5),
    sendFg: Color(0xFF062019),
    aiBg: Color(0xFF8FD6C5),
    aiFg: Color(0xFF062019),
    avBg: Color(0xFF8FD6C5),
    avFg: Color(0xFF062019),
    errC: Color(0xFFFFB4AB),
    errBg: Color(0xFF93000A),
    onErrBg: Color(0xFFFFDAD6),
    iconC: Color(0xFF8FD6C5),
    selBg: Color(0xFF043C34),
    selBar: Color(0xFF8FD6C5),
    codeBg: Color(0xFF16201D),
    codeHead: Color(0xFF1E2C28),
    codeDiv: Color(0xFF2A3A35),
    codeFg: Color(0xFFA7E6D5),
  );
}

// ---------------------------------------------------------------------------
// 形态 token
// ---------------------------------------------------------------------------

/// 一套皮肤的形态（拍板稿 §4.2）。**三套的差异全部在这里。**
@immutable
class SkinMorph {
  const SkinMorph({
    required this.rBubble,
    required this.rFab,
    required this.rCard,
    required this.rSheet,
    required this.rChip,
    required this.rField,
    required this.rSend,
    required this.rCb,
    required this.rRadio,
    required this.fsBar,
    required this.fsTitle,
    required this.fsBody,
    required this.fsSub,
    required this.lineHeight,
    required this.titleWeight,
    required this.titleLSEm,
    required this.iconSize,
    required this.iconMood,
    required this.avatarRadius,
    required this.cardBorderWidth,
    required this.fontFamily,
    this.fontFamilyFallback,
    this.monoForMeta = false,
  });

  /// 圆角（dp）。`999` = 胶囊 / 圆。
  final double rBubble;
  final double rFab;
  final double rCard;
  final double rSheet;
  final double rChip;
  final double rField;
  final double rSend;
  final double rCb;
  final double rRadio;

  /// 字号（dp）：顶栏 / 列表标题 / 正文 / 元信息。
  final double fsBar;
  final double fsTitle;
  final double fsBody;
  final double fsSub;

  /// 正文行高倍数。
  final double lineHeight;

  /// 标题字重。
  final FontWeight titleWeight;

  /// 标题字距（em）。Flutter 的 `letterSpacing` 是 dp，用 [titleLetterSpacing] 换算。
  final double titleLSEm;

  /// 图标尺寸与风格。
  final double iconSize;
  final IconMood iconMood;

  /// 列表头像圆角：A/H 17（正圆），E 0（方角）。
  final double avatarRadius;

  /// 卡片描边宽：只有 E 是 1。
  final double cardBorderWidth;

  /// 主字体（E = 宋体；A/H 为 null = 系统默认）。
  final String? fontFamily;

  /// 主字体兜底链。
  final List<String>? fontFamilyFallback;

  /// 元信息是否走等宽（E 是：时间 / 轮数保留等宽）。
  final bool monoForMeta;

  /// 实际 `letterSpacing`（dp）。
  double get titleLetterSpacing => fsTitle * titleLSEm;

  /// 元信息字体族：E 走等宽，其余跟主字体。
  String? get metaFontFamily => monoForMeta ? kMonoFontFamily : fontFamily;

  /// 是否描边风格（E）。
  bool get outlined => iconMood == IconMood.outlined;

  /// A 清透：大圆角 + 胶囊、系统无衬线、实心 24。
  static const SkinMorph a = SkinMorph(
    rBubble: 16,
    rFab: 16,
    rCard: 14,
    rSheet: 24,
    rChip: 999,
    rField: 999,
    rSend: 999,
    rCb: 4,
    rRadio: 999,
    fsBar: 20,
    fsTitle: 16,
    fsBody: 15,
    fsSub: 13,
    lineHeight: 1.6,
    titleWeight: FontWeight.w600,
    titleLSEm: 0,
    iconSize: 24,
    iconMood: IconMood.filled,
    avatarRadius: 17,
    cardBorderWidth: 0,
    fontFamily: null,
  );

  /// E 纸感：小圆角（8/6/4）、宋体、描边 24、1px 卡片描边、等宽元信息。
  static const SkinMorph e = SkinMorph(
    rBubble: 8,
    rFab: 6,
    rCard: 6,
    rSheet: 14,
    rChip: 3,
    rField: 6,
    rSend: 8,
    rCb: 2,
    rRadio: 999,
    fsBar: 20,
    fsTitle: 16,
    fsBody: 16,
    fsSub: 13,
    lineHeight: 1.6,
    titleWeight: FontWeight.w700,
    titleLSEm: 0.01,
    iconSize: 24,
    iconMood: IconMood.outlined,
    avatarRadius: 0,
    cardBorderWidth: 1,
    fontFamily: kSerifFontFamily,
    fontFamilyFallback: kSerifFontFallback,
    monoForMeta: true,
  );

  /// H 墨色：中圆角偏方、字重 700、图标 26、字号 +1（仅 fsBar / fsBody）。
  static const SkinMorph h = SkinMorph(
    rBubble: 14,
    rFab: 14,
    rCard: 12,
    rSheet: 24,
    rChip: 8,
    rField: 12,
    rSend: 14,
    rCb: 3,
    rRadio: 999,
    fsBar: 22,
    fsTitle: 16,
    fsBody: 16,
    fsSub: 13,
    lineHeight: 1.55,
    titleWeight: FontWeight.w700,
    titleLSEm: 0.005,
    iconSize: 26,
    iconMood: IconMood.filled,
    avatarRadius: 17,
    cardBorderWidth: 0,
    fontFamily: null,
  );
}

// ---------------------------------------------------------------------------
// 一套皮肤 = 颜色 + 形态
// ---------------------------------------------------------------------------

/// 一套皮肤的全部 token。
///
/// 圆角一律用这里的 getter（`tokens.rBubble`），页面里不要写
/// `BorderRadius.circular(..)`；这样换皮肤时形态才真的会变。
@immutable
class SkinTokens {
  const SkinTokens({required this.colors, required this.morph});

  /// 颜色。
  final SkinColors colors;

  /// 形态。
  final SkinMorph morph;

  /// 气泡 / FAB / 卡片 / chip / 输入框 / 发送键 / 复选框圆角。
  BorderRadius get rBubble => _all(morph.rBubble);
  BorderRadius get rFab => _all(morph.rFab);
  BorderRadius get rCard => _all(morph.rCard);
  BorderRadius get rChip => _all(morph.rChip);
  BorderRadius get rField => _all(morph.rField);
  BorderRadius get rSend => _all(morph.rSend);
  BorderRadius get rCb => _all(morph.rCb);
  BorderRadius get rRadio => _all(morph.rRadio);

  /// 列表头像圆角（A/H 17 正圆，E 0 方角）。
  BorderRadius get rAvatar => _all(morph.avatarRadius);

  /// 弹层四角圆角（对话框）。
  BorderRadius get rSheet => _all(morph.rSheet);

  /// 弹层顶圆角（只圆上两角）。
  BorderRadius get rSheetTop => BorderRadius.vertical(
    top: Radius.circular(morph.rSheet),
  );

  /// 抓手 / 胶囊（999）。
  BorderRadius get rPill => _all(999);

  /// 直角。
  static const BorderRadius rNone = BorderRadius.zero;

  static BorderRadius _all(double value) => BorderRadius.all(
    Radius.circular(value),
  );

  /// A 清透。
  static const SkinTokens a = SkinTokens(colors: SkinColors.a, morph: SkinMorph.a);

  /// E 纸感。
  static const SkinTokens e = SkinTokens(colors: SkinColors.e, morph: SkinMorph.e);

  /// H 墨色。
  static const SkinTokens h = SkinTokens(colors: SkinColors.h, morph: SkinMorph.h);

  /// 深色对应套（本轮不验收）。
  static const SkinTokens aDark = SkinTokens(
    colors: SkinColors.aDark,
    morph: SkinMorph.a,
  );
  static const SkinTokens eDark = SkinTokens(
    colors: SkinColors.eDark,
    morph: SkinMorph.e,
  );
  static const SkinTokens hDark = SkinTokens(
    colors: SkinColors.hDark,
    morph: SkinMorph.h,
  );
}
