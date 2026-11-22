/// Keepsake（留声）— Material 3 主题（UI 规格 v2 拍板稿）。
///
/// 结构：
/// - `core/skin_tokens.dart`：**唯一**的色值 / 形态 / 圆角出处（[SkinColors] /
///   [SkinMorph] / [SkinTokens]）。本文件不再出现任何 `Color(0x..)` 字面量。
/// - `core/skins.dart`：皮肤注册表（A 清透 / E 纸感 / H 墨色）。
/// - [KeepsakeSkinColors]：把当前皮肤的 token 以 [ThemeExtension] 挂在主题上；
///   页面统一 `KeepsakeSkinColors.of(context)`，用 `s.m`（形态）/ `s.c`（颜色）/
///   `s.rBubble`（预构造圆角）取，**圆角一律走 token，不自己算**。
/// - [KeepsakeTheme]：字阶、圆角、零阴影。所有尺寸来自 token 层。
///
/// 零阴影：全站 elevation 0，不用 boxShadow；层次靠 surface → low → high → highest。
library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart' show MarkdownStyleSheet;
import 'package:markdown/markdown.dart' as md;

import 'skins.dart';

// ---------------------------------------------------------------------------
// 解析后的皮肤 token（ThemeExtension）
// ---------------------------------------------------------------------------

/// 当前皮肤 + 亮度解析出来的 token。
///
/// 页面只依赖这一个入口：
/// - `s.c` → 颜色（[SkinColors]）
/// - `s.m` → 形态（[SkinMorph]）：圆角数值、字号、行高、字重、图标风格、字体
/// - `s.rBubble` / `s.rCard` / `s.rField` … → 预构造 `BorderRadius`
/// - `s.userBubbleBg` … → v1.1 就有的命名，保留以减少页面改动
@immutable
class KeepsakeSkinColors extends ThemeExtension<KeepsakeSkinColors> {
  const KeepsakeSkinColors({
    required this.skin,
    required this.brightness,
    required this.tokens,
  });

  /// 当前皮肤（设置页展示 / 调试用）。
  final Skin skin;

  /// 当前亮度。
  final Brightness brightness;

  /// 当前皮肤的完整 token。
  final SkinTokens tokens;

  /// 颜色快捷方式。
  SkinColors get c => tokens.colors;

  /// 形态快捷方式。
  SkinMorph get m => tokens.morph;

  // ---- 圆角（页面只能用这些，不许自己 circular）----
  BorderRadius get rBubble => tokens.rBubble;
  BorderRadius get rFab => tokens.rFab;
  BorderRadius get rCard => tokens.rCard;
  BorderRadius get rChip => tokens.rChip;
  BorderRadius get rField => tokens.rField;
  BorderRadius get rSend => tokens.rSend;
  BorderRadius get rCb => tokens.rCb;
  BorderRadius get rRadio => tokens.rRadio;
  BorderRadius get rSheetTop => tokens.rSheetTop;
  BorderRadius get rSheet => tokens.rSheet;
  BorderRadius get rAvatar => tokens.rAvatar;
  BorderRadius get rPill => tokens.rPill;

  // ---- 字号 / 字重 / 行高 ----
  double get fsBar => m.fsBar;
  double get fsTitle => m.fsTitle;
  double get fsBody => m.fsBody;
  double get fsSub => m.fsSub;
  double get lineHeight => m.lineHeight;
  FontWeight get titleWeight => m.titleWeight;
  double get titleLetterSpacing => m.titleLetterSpacing;
  String? get fontFamily => m.fontFamily;
  List<String>? get fontFamilyFallback => m.fontFamilyFallback;

  /// 元信息字体族（E 走等宽）。
  String? get metaFontFamily => m.metaFontFamily;

  /// 图标尺寸 / 是否描边风格。
  double get iconSize => m.iconSize;
  bool get outlined => m.outlined;

  /// 按皮肤选实心 / 描边图标：A/H 走 [filled]，E 走 [outlined]。
  ///
  /// Material 图标没有字重轴，实心与描边是两个不同 glyph，只能在这里换。
  IconData icon({required IconData filled, required IconData outlined}) =>
      m.outlined ? outlined : filled;

  // ---- 颜色（v1.1 命名，方便页面渐进迁移）----
  /// 用户气泡底 / 文字（primaryContainer / onPrimaryContainer）。
  Color get userBubbleBg => c.pC;
  Color get userBubbleFg => c.onPC;

  /// AI 气泡底 / 文字。
  Color get aiBubbleBg => c.aiBg;
  Color get aiBubbleFg => c.aiFg;

  /// 发送键底 / 前景。
  Color get sendBg => c.sendBg;
  Color get sendFg => c.sendFg;

  /// 列表行头像底 / 前景。
  Color get listAvatarBg => c.avBg;
  Color get listAvatarFg => c.avFg;

  /// 助手头像底 / 前景。
  Color get aiAvatarBg => c.aiBg;
  Color get aiAvatarFg => c.aiFg;

  /// 多选选中底色 / 左侧竖条 / 选中行文字色。
  Color get selectionBg => c.selBg;
  Color get selectionBar => c.selBar;
  Color get onSelection => ThemeData.estimateBrightnessForColor(c.selBg) ==
          Brightness.light
      ? c.onS
      : c.onV;

  /// 思考过程条底色。
  Color get usageBar => c.usage;

  /// 代码块：底 / 头 / 分隔线 / 前景。
  Color get codeBackground => c.codeBg;
  Color get codeHeader => c.codeHead;
  Color get codeDivider => c.codeDiv;
  Color get codeForeground => c.codeFg;

  /// 图标色（H 深青）。
  Color get iconColor => c.iconC;

  /// 是否深色。
  bool get isDark => brightness == Brightness.dark;

  /// 卡片 / 气泡 / 输入框的 1px 描边（只有 E 有）。
  ///
  /// 拍板稿 §4.2「卡片描边只有 E 有」：A/H 靠底色分层，返回 null。
  Border? get hairlineBorder => m.cardBorderWidth <= 0
      ? null
      : Border.all(width: m.cardBorderWidth, color: c.ov);

  /// 直接取当前主题的 token（主题里没挂 extension 时按第一套皮肤兜底）。
  static KeepsakeSkinColors of(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final KeepsakeSkinColors? attached =
        theme.extension<KeepsakeSkinColors>();
    if (attached != null) return attached;
    final Skin fallback = keepsakeSkins.first;
    return KeepsakeSkinColors(
      skin: fallback,
      brightness: theme.brightness,
      tokens: fallback.tokensFor(theme.brightness),
    );
  }

  @override
  KeepsakeSkinColors copyWith({
    Skin? skin,
    Brightness? brightness,
    SkinTokens? tokens,
  }) {
    return KeepsakeSkinColors(
      skin: skin ?? this.skin,
      brightness: brightness ?? this.brightness,
      tokens: tokens ?? this.tokens,
    );
  }

  /// 皮肤切换不做颜色插值：半程混色会出现设计稿里没有的颜色。
  @override
  KeepsakeSkinColors lerp(ThemeExtension<KeepsakeSkinColors>? other, double t) {
    if (other is! KeepsakeSkinColors) return this;
    return t < 0.5 ? this : other;
  }
}

// ---------------------------------------------------------------------------
// 主题
// ---------------------------------------------------------------------------

/// Keepsake 的 Material 3 主题。
abstract final class KeepsakeTheme {
  /// 主色种子（M3 派生用）。
  static const Color seedColor = kSeedColor;

  /// 等宽字体族（等宽元信息、代码块）。
  static const String monoFontFamily = kMonoFontFamily;

  /// 页面左右内边距 16。
  static const double pagePadding = kPagePadding;

  /// 顶栏高度 56。
  static const double barHeight = kBarHeight;

  /// 会话行高度 68（三套一致）。
  static const double listRowHeight = kRowHeight;

  /// 设置项高度 64。
  static const double settingsRowHeight = kSettingsRowHeight;

  /// 弹层选项行高度 64。
  static const double sheetRowHeight = kSheetRowHeight;

  /// 列表头像 34。
  static const double listAvatarSize = kListAvatarSize;

  /// 复选框槽位 34，复选框本身 20。
  static const double checkboxSlot = kCheckboxSlot;
  static const double checkboxSize = kCheckboxSize;

  /// FAB 高 56（圆角按皮肤）。
  static const double fabHeight = kFabHeight;

  /// chip 高 32 / 内距 12。
  static const double chipHeight = kChipHeight;
  static const double chipPadH = kChipPadH;

  /// 输入框最小高 48（圆角按皮肤）。
  static const double inputHeight = 48;

  /// 发送键 44（圆角按皮肤）。
  static const double sendSize = kSendSize;

  /// 弹层抓手 / 内距 / 按钮高。
  static const double sheetGrabberW = kSheetGrabberW;
  static const double sheetGrabberH = kSheetGrabberH;
  static const double sheetPadding = kSheetPadding;
  static const double sheetButtonHeight = kSheetButtonHeight;

  /// 通用图标尺寸（页面请用 `s.iconSize`，这是 A/H 之外的兜底值）。
  static const double iconSize = 24;

  /// 动作条（朗读 / 复制 / 重答 / 分支）：图标 15、文字 12、图标↔文字 5、
  /// 项间距 16、左缩进 30（SPEC §4.4）。
  static const double actionIconSize = kActionIconSize;
  static const double actionFontSize = kActionFontSize;
  static const double actionGap = kActionGap;
  static const double actionSpacing = kActionSpacing;
  static const double actionIndent = kActionIndent;

  /// 代码 / 等宽文本样式。
  static TextStyle monoStyle({
    double fontSize = 13,
    FontWeight? fontWeight,
    Color? color,
    double height = 1.7,
  }) => TextStyle(
    fontFamily: monoFontFamily,
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
  );

  /// 浅色主题（默认皮肤）。
  static ThemeData get light => of(Brightness.light);

  /// 深色主题（默认皮肤）。
  static ThemeData get dark => of(Brightness.dark);

  /// 按亮度 + 皮肤 id 构建主题。
  ///
  /// 皮肤 id 来自设置（`Settings.skinId`）；未知 id 由 [skinById] 回退第一套。
  static ThemeData of(Brightness brightness, {String skinId = kDefaultSkinId}) {
    final Skin skin = skinById(skinId);
    final SkinTokens tokens = skin.tokensFor(brightness);
    final SkinColors c = tokens.colors;
    final SkinMorph m = tokens.morph;
    final ColorScheme scheme = schemeFor(tokens, brightness);
    final bool serif = m.fontFamily != null;

    ThemeData base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      // E 纸感：主字体宋体（系统无宋体时按 fallback 链退回，最终退回黑体）。
      // 打包思源宋体子集后：字体族名换成 assets 里声明的 family，删掉 fallback 链。
      fontFamily: m.fontFamily,
      fontFamilyFallback: m.fontFamilyFallback,
    );
    TextTheme textTheme = _textTheme(base.textTheme, m);
    if (serif) {
      textTheme = textTheme.apply(
        fontFamily: m.fontFamily,
        fontFamilyFallback: m.fontFamilyFallback,
      );
    }

    return base.copyWith(
      // 按压反馈（v3.1 拍板）：用 onPrimaryContainer（深色）而不是
      // primaryContainer（浅色）——浅色叠在浅底上几乎看不见。
      // splash 12% / pressed 8%，三套皮肤各自取深色主色。
      splashColor: c.onPC.withValues(alpha: 0.12),
      highlightColor: c.onPC.withValues(alpha: 0.08),
      // 皮肤 token 挂在主题上，页面用 KeepsakeSkinColors.of(context) 取。
      extensions: <ThemeExtension<dynamic>>[
        KeepsakeSkinColors(skin: skin, brightness: brightness, tokens: tokens),
      ],
      textTheme: textTheme,
      scaffoldBackgroundColor: c.surface,
      // ---- 零阴影：全站 0 elevation ----
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.onS,
        toolbarHeight: kBarHeight,
        titleSpacing: 8,
        iconTheme: IconThemeData(size: m.iconSize, color: c.iconC),
        actionsIconTheme: IconThemeData(size: m.iconSize, color: c.iconC),
        // 顶栏标题 fs-bar / title-w。
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: c.onS,
          fontSize: m.fsBar,
          fontWeight: m.titleWeight,
          letterSpacing: m.fsBar * m.titleLSEm,
        ),
      ),
      iconTheme: IconThemeData(size: m.iconSize, color: c.iconC),
      cardTheme: CardThemeData(
        elevation: 0,
        color: c.low,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: tokens.rCard,
          side: _sideFor(tokens),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: c.low,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: tokens.rSheetTop),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 0,
        backgroundColor: c.low,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: c.low,
        showDragHandle: false,
        // 弹层只圆上两角，圆角按皮肤（E = 14）。
        shape: RoundedRectangleBorder(borderRadius: tokens.rSheetTop),
      ),
      popupMenuTheme: PopupMenuThemeData(
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        color: c.low,
        shape: RoundedRectangleBorder(
          borderRadius: tokens.rCard,
          side: _sideFor(tokens),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        backgroundColor: c.pC,
        foregroundColor: c.onPC,
        shape: RoundedRectangleBorder(borderRadius: tokens.rFab),
      ),
      // 输入框：minHeight 48、圆角 r-field（A 胶囊 / E 6 / H 12）。
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.highest,
        isDense: true,
        hintStyle: textTheme.bodyLarge?.copyWith(color: c.onV),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        constraints: const BoxConstraints(minHeight: inputHeight),
        border: OutlineInputBorder(
          borderRadius: tokens.rField,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: tokens.rField,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: tokens.rField,
          borderSide: BorderSide(color: c.selBar, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, kSheetButtonHeight),
          shape: RoundedRectangleBorder(borderRadius: tokens.rCard),
        ),
      ),
      // 复选框：20、圆角 r-cb（A 4 / E 2 / H 3）、未选 2px outline、
      // 选中 sel-bar 实心 + 白勾。
      checkboxTheme: CheckboxThemeData(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: tokens.rCb),
        side: BorderSide(color: c.outline, width: 2),
        fillColor: WidgetStateProperty.resolveWith<Color?>((
          Set<WidgetState> states,
        ) {
          if (states.contains(WidgetState.selected)) return c.selBar;
          return Colors.transparent;
        }),
        checkColor: const WidgetStatePropertyAll<Color>(Colors.white),
      ),
      // 单选：20，外环 2px + 中心点（Material Radio 默认就是环 + 点 + 留白）。
      radioTheme: RadioThemeData(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        fillColor: WidgetStateProperty.resolveWith<Color?>((
          Set<WidgetState> states,
        ) {
          if (states.contains(WidgetState.selected)) return c.selBar;
          return c.outline;
        }),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: tokens.rChip),
        side: BorderSide(color: c.ov),
      ),
      listTileTheme: ListTileThemeData(
        minTileHeight: kSettingsRowHeight,
        contentPadding: const EdgeInsets.symmetric(horizontal: kPagePadding),
        iconColor: c.onV,
        textColor: c.onS,
      ),
      dividerTheme: DividerThemeData(
        color: c.ov,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: tokens.rCard),
      ),
    );
  }

  /// 卡片 / 弹层描边：只有 E（1px `#D8D4CC`）。
  static BorderSide _sideFor(SkinTokens tokens) => tokens.morph.cardBorderWidth <= 0
      ? BorderSide.none
      : BorderSide(
          color: tokens.colors.ov,
          width: tokens.morph.cardBorderWidth,
        );

  /// 由皮肤 token + 亮度生成 ColorScheme。
  static ColorScheme schemeFor(SkinTokens tokens, Brightness brightness) {
    final SkinColors c = tokens.colors;
    final Color onSel = ThemeData.estimateBrightnessForColor(c.selBg) ==
            Brightness.light
        ? c.onS
        : c.onV;
    return ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    ).copyWith(
      primary: c.selBar,
      onPrimary: Colors.white,
      primaryContainer: c.pC,
      onPrimaryContainer: c.onPC,
      secondary: c.selBar,
      secondaryContainer: c.selBg,
      onSecondaryContainer: onSel,
      surface: c.surface,
      onSurface: c.onS,
      surfaceContainerLow: c.low,
      surfaceContainerHigh: c.high,
      surfaceContainerHighest: c.highest,
      onSurfaceVariant: c.onV,
      outline: c.outline,
      outlineVariant: c.ov,
      error: c.errC,
      onError: Colors.white,
      errorContainer: c.errBg,
      onErrorContainer: c.onErrBg,
    );
  }

  /// 字阶（拍板稿 §4.2）：顶栏 fs-bar、列表标题 fs-title、正文 fs-body、
  /// 元信息 fs-sub；行高用皮肤 lh。**全站不低于 12。**
  static TextTheme _textTheme(TextTheme base, SkinMorph m) {
    return base.copyWith(
      // 顶栏标题、空态标题。
      titleLarge: base.titleLarge?.copyWith(
        fontSize: m.fsBar,
        fontWeight: m.titleWeight,
        letterSpacing: m.fsBar * m.titleLSEm,
        height: 28 / 20,
      ),
      // 列表标题 / 弹层标题。
      titleMedium: base.titleMedium?.copyWith(
        fontSize: m.fsTitle,
        fontWeight: m.titleWeight,
        letterSpacing: m.titleLetterSpacing,
        height: 24 / 16,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontSize: m.fsSub + 1,
        fontWeight: FontWeight.w600,
        letterSpacing: (m.fsSub + 1) * m.titleLSEm,
        height: 20 / 14,
      ),
      // 对话正文 / 列表标题的兜底。
      bodyLarge: base.bodyLarge?.copyWith(
        fontSize: m.fsBody,
        fontWeight: FontWeight.w400,
        height: m.lineHeight,
      ),
      // 列表副标题 / 币信息 / 弹层副标题。
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: m.fsSub,
        fontWeight: FontWeight.w400,
        height: 20 / 13,
      ),
      bodySmall: base.bodySmall?.copyWith(
        fontSize: m.fsSub,
        fontWeight: FontWeight.w400,
        height: 20 / 13,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: m.fsSub + 1,
        fontWeight: FontWeight.w600,
        height: 20 / 14,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontSize: m.fsSub,
        fontWeight: FontWeight.w500,
        height: 20 / 13,
      ),
      // 思考过程条、设置副标题、代码行号。
      labelSmall: base.labelSmall?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 16 / 12,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Markdown（`features/chat/widgets/markdown_view.dart` 用）
// ---------------------------------------------------------------------------

/// markdown 扩展集（GFM：表格/删除线/任务列表/脚注）。
md.ExtensionSet get keepsakeMarkdownExtensionSet =>
    md.ExtensionSet.gitHubFlavored;

/// 额外**块级** markdown 语法（传给 `MarkdownBody.blockSyntaxes`）。
final List<md.BlockSyntax> keepsakeMarkdownExtensions = <md.BlockSyntax>[];

/// 额外**行内** markdown 语法（传给 `MarkdownBody.inlineSyntaxes`）。
final List<md.InlineSyntax> keepsakeMarkdownInlineSyntaxes =
    <md.InlineSyntax>[];

/// Keepsake 的 markdown 样式表（正文 / 行内代码 / 代码块都按当前皮肤）。
///
/// 正文 fs-body + lh；代码块用皮肤的 codeBg / codeHead / codeDivider / codeFg。
MarkdownStyleSheet keepsakeMarkdownStyleSheet(ThemeData theme) {
  final base = MarkdownStyleSheet.fromTheme(theme);
  final scheme = theme.colorScheme;
  final KeepsakeSkinColors s =
      theme.extension<KeepsakeSkinColors>() ??
      KeepsakeSkinColors(
        skin: keepsakeSkins.first,
        brightness: theme.brightness,
        tokens: keepsakeSkins.first.light,
      );
  final SkinMorph m = s.m;

  return base.copyWith(
    p: (base.p ?? const TextStyle()).copyWith(
      fontSize: m.fsBody,
      height: m.lineHeight,
      color: scheme.onSurface,
    ),
    a: (base.a ?? const TextStyle()).copyWith(
      color: scheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: scheme.primary.withValues(alpha: 0.6),
    ),
    code: (base.code ?? const TextStyle()).copyWith(
      fontFamily: kMonoFontFamily,
      fontSize: m.fsSub,
      height: 1.7,
      backgroundColor: s.codeHeader,
      color: s.codeForeground,
    ),
    codeblockPadding: const EdgeInsets.all(12),
    codeblockDecoration: BoxDecoration(
      color: s.codeBackground,
      borderRadius: s.rCard,
      border: s.hairlineBorder,
    ),
    blockquote: (base.blockquote ?? const TextStyle()).copyWith(
      color: scheme.onSurfaceVariant,
      fontSize: m.fsBody,
      height: m.lineHeight,
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    blockquoteDecoration: BoxDecoration(
      color: s.codeHeader,
      borderRadius: s.rCard,
      border: Border(
        left: BorderSide(color: scheme.primary.withValues(alpha: 0.6), width: 3),
      ),
    ),
    tableBorder: TableBorder.all(color: s.codeDivider),
    tableCellsPadding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
    tableCellsDecoration: BoxDecoration(color: s.codeHeader),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: s.codeDivider)),
    ),
    listBullet: (base.listBullet ?? const TextStyle()).copyWith(
      color: scheme.onSurfaceVariant,
    ),
  );
}
