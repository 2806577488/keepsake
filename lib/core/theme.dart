/// Keepsake（留声）— Material 3 主题（UI 规格 v1.1）+ Markdown 样式表。
///
/// 结构（README v1.1）：
/// - [KeepsakeColors]：**基线 token**（§1 全表）。浅色底、主色、代码块、深色分层（§8）。
/// - `core/skins.dart`：皮肤注册表（A 基线 / E 撞色 / H 深色锚点）。三套皮肤只覆盖
///   README §0 的 3 个 token + 前景色，其余沿用基线。
/// - [KeepsakeSkinColors]：把「基线 + 皮肤覆盖 + 亮度」解析成一组可直接用的颜色，
///   以 [ThemeExtension] 挂在主题上；组件用 `KeepsakeSkinColors.of(context)` 取，
///   **不在 UI 里 `switch (skinId)`**（加皮肤只改注册表数据）。
/// - [KeepsakeTheme]：字阶（§2）、圆角（§3）、零阴影（§1 阴影全 0）都在这里定。
///
/// 说明：
/// - seed color 仍为 `#2F6B5F`（README §1「主色由 seed 推导」）。
/// - 零阴影：所有 Surface 组件 elevation 0，全站不用 boxShadow。
library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart' show MarkdownStyleSheet;
import 'package:markdown/markdown.dart' as md;

import 'skins.dart';

// ---------------------------------------------------------------------------
// 基线 token（README §1）
// ---------------------------------------------------------------------------

/// 与皮肤无关的基线色（README §1「Token 全表」+ §8「深色」）。
abstract final class KeepsakeColors {
  // ---- 浅色底 ----
  static const Color surface = Color(0xFFF5FBF7);
  static const Color surfaceContainerLow = Color(0xFFEFF5F2);
  static const Color surfaceContainerHigh = Color(0xFFE3EAE6);
  static const Color surfaceContainerHighest = Color(0xFFDEE4E1);
  static const Color usageBar = Color(0xFFE9EFEC);
  static const Color outlineVariant = Color(0xFFCAD1CD);
  static const Color outline = Color(0xFF7C8B86);
  static const Color onSurface = Color(0xFF191C1B);
  static const Color onSurfaceVariant = Color(0xFF496F66);
  static const Color error = Color(0xFFBA1A1A);

  // ---- 主色（seed `#2F6B5F` 推导） ----
  static const Color primary = Color(0xFF046B5C);

  // ---- 代码块 ----
  static const Color codeBackground = Color(0xFFFFFFFF);
  static const Color codeHeader = Color(0xFFE7F3EF);
  static const Color codeDivider = Color(0xFFD5EAE3);
  static const Color codeForeground = Color(0xFF161B1A);

  // ---- FAB 描边（README §7） ----
  static const Color fabBorder = Color(0xFF8CCDBB);

  // ---- 深色分层（README §8：明度差保持 8% 以上） ----
  static const Color darkSurface = Color(0xFF101614);
  static const Color darkSurfaceContainerLow = Color(0xFF161D1A);
  static const Color darkSurfaceContainerHigh = Color(0xFF1C2421);
  static const Color darkSurfaceContainerHighest = Color(0xFF232C28);
  static const Color darkOutlineVariant = Color(0xFF3A4A45);
  static const Color darkOutline = Color(0xFF7F948E);
  static const Color darkOnSurface = Color(0xFFE6EFEA);
  static const Color darkOnSurfaceVariant = Color(0xFFA3C1B7);
  static const Color darkUsageBar = Color(0xFF1C2421);
  static const Color darkCodeBackground = Color(0xFF161D1A);
  static const Color darkCodeHeader = Color(0xFF22302B);
  static const Color darkCodeDivider = Color(0xFF2E3D37);
}

// ---------------------------------------------------------------------------
// 解析后的皮肤颜色（ThemeExtension）
// ---------------------------------------------------------------------------

/// 当前皮肤 + 亮度解析出来的一组颜色。
///
/// 组件只需要 `KeepsakeSkinColors.of(context)`，不关心是哪一套皮肤：
/// 用户气泡、发送键、列表头像、助手头像、多选选中、思考条、代码块。
@immutable
class KeepsakeSkinColors extends ThemeExtension<KeepsakeSkinColors> {
  const KeepsakeSkinColors({
    required this.skin,
    required this.brightness,
    required this.userBubbleBg,
    required this.userBubbleFg,
    required this.sendBg,
    required this.sendFg,
    required this.listAvatarBg,
    required this.listAvatarFg,
    required this.aiAvatarBg,
    required this.aiAvatarFg,
    required this.selectionBg,
    required this.selectionBar,
    required this.onSelection,
    required this.fabBorder,
    required this.usageBar,
    required this.codeBackground,
    required this.codeHeader,
    required this.codeDivider,
    required this.codeForeground,
  });

  /// 当前皮肤（设置页展示 / 调试用）。
  final Skin skin;

  /// 当前亮度。
  final Brightness brightness;

  /// 用户气泡底 / 前景（README §0 `primaryContainer` / `onPrimaryContainer`）。
  final Color userBubbleBg;
  final Color userBubbleFg;

  /// 发送键底 / 前景（README §0 `sendButton` / `onSend`）。
  final Color sendBg;
  final Color sendFg;

  /// 列表行头像底 / 前景（README §0 `listAvatar` / `onListAvatar`）。
  final Color listAvatarBg;
  final Color listAvatarFg;

  /// 助手头像底 / 前景。
  final Color aiAvatarBg;
  final Color aiAvatarFg;

  /// 多选选中行底色 / 左侧 2px 竖条 / 选中行文字色。
  final Color selectionBg;
  final Color selectionBar;
  final Color onSelection;

  /// FAB 1px 描边（README §7 `#8CCDBB`）。
  final Color fabBorder;

  /// 思考过程条底色（README §1 `usageBar`）。
  final Color usageBar;

  /// 代码块：白纸 / 头部 / 分隔线 / 前景（README §1、§4.3）。
  final Color codeBackground;
  final Color codeHeader;
  final Color codeDivider;
  final Color codeForeground;

  /// 是否深色。
  bool get isDark => brightness == Brightness.dark;

  /// 直接取当前主题的皮肤颜色（主题里没挂 extension 时按第一套皮肤兜底）。
  static KeepsakeSkinColors of(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final KeepsakeSkinColors? attached =
        theme.extension<KeepsakeSkinColors>();
    if (attached != null) return attached;
    final Skin fallback = keepsakeSkins.first;
    return resolve(fallback, theme.brightness, KeepsakeTheme.schemeFor(fallback, theme.brightness));
  }

  /// 由皮肤 + 亮度 + ColorScheme 解析（纯函数，方便单测）。
  static KeepsakeSkinColors resolve(
    Skin skin,
    Brightness brightness,
    ColorScheme scheme,
  ) {
    final bool dark = brightness == Brightness.dark;
    final SkinTokens t = skin.tokensFor(brightness);
    // 选中行：底色是皮肤给的浅色块，文字必须跟着底色走（深色模式下不能还写亮字）。
    final Color onSelection =
        ThemeData.estimateBrightnessForColor(t.secondaryContainer) ==
            Brightness.light
        ? KeepsakeColors.onSurface
        : KeepsakeColors.darkOnSurface;
    return KeepsakeSkinColors(
      skin: skin,
      brightness: brightness,
      userBubbleBg: t.primaryContainer,
      userBubbleFg: t.onPrimaryContainer,
      sendBg: t.sendButton,
      sendFg: t.onSend,
      listAvatarBg: t.listAvatar,
      listAvatarFg: t.onListAvatar,
      aiAvatarBg: t.resolvedAiAvatar,
      aiAvatarFg: t.resolvedOnAiAvatar,
      selectionBg: t.secondaryContainer,
      selectionBar: t.selectionBar ?? KeepsakeColors.primary,
      onSelection: onSelection,
      fabBorder: t.sendBorder ?? KeepsakeColors.fabBorder,
      usageBar: dark ? KeepsakeColors.darkUsageBar : KeepsakeColors.usageBar,
      codeBackground: dark
          ? KeepsakeColors.darkCodeBackground
          : KeepsakeColors.codeBackground,
      codeHeader: dark
          ? KeepsakeColors.darkCodeHeader
          : KeepsakeColors.codeHeader,
      codeDivider: dark
          ? KeepsakeColors.darkCodeDivider
          : KeepsakeColors.codeDivider,
      codeForeground: dark
          ? KeepsakeColors.darkOnSurface
          : KeepsakeColors.codeForeground,
    );
  }

  @override
  KeepsakeSkinColors copyWith({
    Skin? skin,
    Brightness? brightness,
    Color? userBubbleBg,
    Color? userBubbleFg,
    Color? sendBg,
    Color? sendFg,
    Color? listAvatarBg,
    Color? listAvatarFg,
    Color? aiAvatarBg,
    Color? aiAvatarFg,
    Color? selectionBg,
    Color? selectionBar,
    Color? onSelection,
    Color? fabBorder,
    Color? usageBar,
    Color? codeBackground,
    Color? codeHeader,
    Color? codeDivider,
    Color? codeForeground,
  }) {
    return KeepsakeSkinColors(
      skin: skin ?? this.skin,
      brightness: brightness ?? this.brightness,
      userBubbleBg: userBubbleBg ?? this.userBubbleBg,
      userBubbleFg: userBubbleFg ?? this.userBubbleFg,
      sendBg: sendBg ?? this.sendBg,
      sendFg: sendFg ?? this.sendFg,
      listAvatarBg: listAvatarBg ?? this.listAvatarBg,
      listAvatarFg: listAvatarFg ?? this.listAvatarFg,
      aiAvatarBg: aiAvatarBg ?? this.aiAvatarBg,
      aiAvatarFg: aiAvatarFg ?? this.aiAvatarFg,
      selectionBg: selectionBg ?? this.selectionBg,
      selectionBar: selectionBar ?? this.selectionBar,
      onSelection: onSelection ?? this.onSelection,
      fabBorder: fabBorder ?? this.fabBorder,
      usageBar: usageBar ?? this.usageBar,
      codeBackground: codeBackground ?? this.codeBackground,
      codeHeader: codeHeader ?? this.codeHeader,
      codeDivider: codeDivider ?? this.codeDivider,
      codeForeground: codeForeground ?? this.codeForeground,
    );
  }

  @override
  KeepsakeSkinColors lerp(ThemeExtension<KeepsakeSkinColors>? other, double t) {
    if (other is! KeepsakeSkinColors) return this;
    return KeepsakeSkinColors(
      skin: t < 0.5 ? skin : other.skin,
      brightness: t < 0.5 ? brightness : other.brightness,
      userBubbleBg: Color.lerp(userBubbleBg, other.userBubbleBg, t)!,
      userBubbleFg: Color.lerp(userBubbleFg, other.userBubbleFg, t)!,
      sendBg: Color.lerp(sendBg, other.sendBg, t)!,
      sendFg: Color.lerp(sendFg, other.sendFg, t)!,
      listAvatarBg: Color.lerp(listAvatarBg, other.listAvatarBg, t)!,
      listAvatarFg: Color.lerp(listAvatarFg, other.listAvatarFg, t)!,
      aiAvatarBg: Color.lerp(aiAvatarBg, other.aiAvatarBg, t)!,
      aiAvatarFg: Color.lerp(aiAvatarFg, other.aiAvatarFg, t)!,
      selectionBg: Color.lerp(selectionBg, other.selectionBg, t)!,
      selectionBar: Color.lerp(selectionBar, other.selectionBar, t)!,
      onSelection: Color.lerp(onSelection, other.onSelection, t)!,
      fabBorder: Color.lerp(fabBorder, other.fabBorder, t)!,
      usageBar: Color.lerp(usageBar, other.usageBar, t)!,
      codeBackground: Color.lerp(codeBackground, other.codeBackground, t)!,
      codeHeader: Color.lerp(codeHeader, other.codeHeader, t)!,
      codeDivider: Color.lerp(codeDivider, other.codeDivider, t)!,
      codeForeground: Color.lerp(codeForeground, other.codeForeground, t)!,
    );
  }
}

/// 设计稿新增的颜色派生（保留旧 API 名字；值改为 README §1 的固定值）。
///
/// - [codeHeader]：代码块头部 `#E7F3EF`（深色 `#22302B`）；
/// - [codeDivider]：头部与代码区的 1px 分隔线 `#D5EAE3`（深色 `#2E3D37`）；
/// - [usageBarBg]：思考过程条底色 `#E9EFEC`（深色 `#1C2421`）；
/// - [selectedBorder]：芯片描边过渡色（选中态用透明占位，见 §4.4）。
extension KeepsakeSchemeX on ColorScheme {
  /// 是否深色主题。
  bool get _isDark => brightness == Brightness.dark;

  /// 代码块头部底色（README §1 `codeHeader`）。
  Color get codeHeader =>
      _isDark ? KeepsakeColors.darkCodeHeader : KeepsakeColors.codeHeader;

  /// 代码块头部分隔线（README §1 `codeDivider`）。
  Color get codeDivider =>
      _isDark ? KeepsakeColors.darkCodeDivider : KeepsakeColors.codeDivider;

  /// 思考过程条底色（README §1 `usageBar`）。
  Color get usageBarBg =>
      _isDark ? KeepsakeColors.darkUsageBar : KeepsakeColors.usageBar;

  /// 选中芯片 / 选中项描边的过渡色（默认 40% primary）。
  Color get selectedBorder => primary.withValues(alpha: 0.4);
}

// ---------------------------------------------------------------------------
// 主题
// ---------------------------------------------------------------------------

/// Keepsake 的 Material 3 主题。
abstract final class KeepsakeTheme {
  /// 主色种子（README §1：`ColorScheme.fromSeed(#2F6B5F)`）。
  static const Color seedColor = Color(0xFF2F6B5F);

  /// 等宽字体族（字符串表实证 token `monospace`）。
  static const String monoFontFamily = 'monospace';

  /// 页面左右内边距（README §3：16）。
  static const double pagePadding = 16;

  /// 顶栏高度（README §4.1：56）。
  static const double barHeight = 56;

  /// 会话行 / 多选行高度（README §4.1、§4.6、§5 规则 3：68）。
  static const double listRowHeight = 68;

  /// 设置项高度（README §3：64）。
  static const double settingsRowHeight = 64;

  /// 弹层选项行高度（README §4.5：64）。
  static const double sheetRowHeight = 64;

  /// 列表头像直径（README §4.1：34）。
  static const double listAvatarSize = 34;

  /// 复选框槽位（README §5 规则 2：34）与复选框本身（§4.6：20）。
  static const double checkboxSlot = 34;
  static const double checkboxSize = 20;

  /// FAB 高度 / 圆角（README §4.1：56 / 16）。
  static const double fabHeight = 56;
  static const double fabRadius = 16;

  /// 芯片行高 / 圆角（README §4.4：32 / 16），输入框高 / 圆角（48 / 24）。
  static const double chipHeight = 32;
  static const double chipRadius = 16;
  static const double inputHeight = 48;
  static const double inputRadius = 24;

  /// 发送键（README §4.4：44 / 22）。
  static const double sendSize = 44;
  static const double sendRadius = 22;

  /// 气泡圆角（README §3：大角 18 / 贴角 4）与弹层顶圆角（28）。
  static const double bubbleRadius = 18;
  static const double bubbleTailRadius = 4;
  static const double sheetTopRadius = 28;

  /// 卡片 / 建议项圆角（README §3：14）。
  static const double cardRadius = 14;

  /// 图标统一 24（README §6）；特殊尺寸见 §6 表（发送 20、复制 18、勾 16）。
  static const double iconSize = 24;

  /// 代码/等宽文本样式。
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
  /// 皮肤 id 来自设置（`Settings.skinId`）；未知 id 由 [skinById] 回退第一套，
  /// 所以加皮肤只需要往 [keepsakeSkins] 里追加数据。
  static ThemeData of(Brightness brightness, {String skinId = kDefaultSkinId}) {
    final Skin skin = skinById(skinId);
    final ColorScheme scheme = schemeFor(skin, brightness);
    final KeepsakeSkinColors colors = KeepsakeSkinColors.resolve(
      skin,
      brightness,
      scheme,
    );
    final ThemeData base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
    );
    final TextTheme textTheme = _textTheme(base.textTheme);

    return base.copyWith(
      // 皮肤颜色挂在主题上，页面用 KeepsakeSkinColors.of(context) 取。
      extensions: <ThemeExtension<dynamic>>[colors],
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      // ---- 零阴影：全站 0 elevation ----
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        // 顶栏 56（README §4.1），左右图标 48 触达（§3：触摸区 ≥48）。
        toolbarHeight: barHeight,
        titleSpacing: 8,
        iconTheme: IconThemeData(size: iconSize, color: scheme.onSurface),
        actionsIconTheme: IconThemeData(
          size: iconSize,
          color: scheme.onSurface,
        ),
        // 顶栏标题 20/600（README §2 titleLarge、§4.1）。
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(sheetTopRadius),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 0,
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: scheme.surfaceContainerLow,
        showDragHandle: false,
        // 弹层顶部圆角 28（README §3、§4.5）。
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(sheetTopRadius),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(fabRadius),
        ),
      ),
      // 输入框 48 高 / 圆角 24 / surfaceContainerHighest 底 / 15 号字（§4.4）。
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        isDense: true,
        hintStyle: textTheme.bodyLarge?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        constraints: const BoxConstraints(minHeight: inputHeight),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(sheetTopRadius),
          ),
        ),
      ),
      // 复选框：框 20 圆 6、未选 2px outline、选中 primary + 白勾（README §4.6）。
      checkboxTheme: CheckboxThemeData(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(color: scheme.outline, width: 2),
        fillColor: WidgetStateProperty.resolveWith<Color?>((
          Set<WidgetState> states,
        ) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary;
          }
          return Colors.transparent;
        }),
        checkColor: const WidgetStatePropertyAll<Color>(Colors.white),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(chipRadius),
        ),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      // 设置项 64 高（README §3），左右 16。
      listTileTheme: ListTileThemeData(
        minTileHeight: settingsRowHeight,
        contentPadding: const EdgeInsets.symmetric(horizontal: pagePadding),
        iconColor: scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
        textColor: scheme.onSurface,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
      ),
    );
  }

  /// 由「基线 token + 皮肤覆盖 + 亮度」生成 ColorScheme。
  static ColorScheme schemeFor(Skin skin, Brightness brightness) {
    final bool dark = brightness == Brightness.dark;
    final SkinTokens t = skin.tokensFor(brightness);
    final Color onSelection =
        ThemeData.estimateBrightnessForColor(t.secondaryContainer) ==
            Brightness.light
        ? KeepsakeColors.onSurface
        : KeepsakeColors.darkOnSurface;
    return ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    ).copyWith(
      primary: KeepsakeColors.primary,
      onPrimary: Colors.white,
      primaryContainer: t.primaryContainer,
      onPrimaryContainer: t.onPrimaryContainer,
      secondary: KeepsakeColors.primary,
      secondaryContainer: t.secondaryContainer,
      onSecondaryContainer: onSelection,
      surface: dark ? KeepsakeColors.darkSurface : KeepsakeColors.surface,
      onSurface: dark ? KeepsakeColors.darkOnSurface : KeepsakeColors.onSurface,
      onSurfaceVariant: dark
          ? KeepsakeColors.darkOnSurfaceVariant
          : KeepsakeColors.onSurfaceVariant,
      surfaceContainerLow: dark
          ? KeepsakeColors.darkSurfaceContainerLow
          : KeepsakeColors.surfaceContainerLow,
      surfaceContainerHigh: dark
          ? KeepsakeColors.darkSurfaceContainerHigh
          : KeepsakeColors.surfaceContainerHigh,
      surfaceContainerHighest: dark
          ? KeepsakeColors.darkSurfaceContainerHighest
          : KeepsakeColors.surfaceContainerHighest,
      outline: dark ? KeepsakeColors.darkOutline : KeepsakeColors.outline,
      outlineVariant: dark
          ? KeepsakeColors.darkOutlineVariant
          : KeepsakeColors.outlineVariant,
      error: KeepsakeColors.error,
      onError: Colors.white,
    );
  }

  /// 字阶（README §2）：titleLarge 20/600/28、bodyLarge 15/400/24、
  /// bodyMedium 13/400/20、labelSmall 12/400/16；**全站不低于 12**。
  static TextTheme _textTheme(TextTheme base) {
    return base.copyWith(
      // 顶栏标题、弹层标题、空态标题。
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 28 / 20,
      ),
      // 弹层选项名称 16/600（README §4.5）。
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 24 / 16,
      ),
      // 次要标题（仍未覆盖的位置）不低于 14/600。
      titleSmall: base.titleSmall?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 20 / 14,
      ),
      // 对话正文、列表标题（600 由调用点指定）、输入框。
      bodyLarge: base.bodyLarge?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 24 / 15,
      ),
      // 列表副标题、芯片、弹层副标题。
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 20 / 13,
      ),
      // 旧的 bodySmall 用法（说明文字）抬到 13，避免出现 <12 的字。
      bodySmall: base.bodySmall?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 20 / 13,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 20 / 14,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontSize: 13,
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
// Markdown（F 批次 `features/chat/widgets/markdown_view.dart` 用）
// ---------------------------------------------------------------------------

/// markdown 扩展集（GFM：表格/删除线/任务列表/脚注）。
///
/// 用法：`MarkdownBody(extensionSet: keepsakeMarkdownExtensionSet, ...)`。
md.ExtensionSet get keepsakeMarkdownExtensionSet =>
    md.ExtensionSet.gitHubFlavored;

/// 额外**块级** markdown 语法（传给 `MarkdownBody.blockSyntaxes`）。
///
/// 目前为空：公式（`$...$`/`$$...$$`）与 mermaid 围栏由 `MarkdownView` 的
/// `builders` / `_MathSyntax` 处理。签名冻结，需要追加语法时在这里加。
final List<md.BlockSyntax> keepsakeMarkdownExtensions = <md.BlockSyntax>[];

/// 额外**行内** markdown 语法（传给 `MarkdownBody.inlineSyntaxes`）。
///
/// 同上：签名冻结，`_MathSyntax` 可在这里注册。
final List<md.InlineSyntax> keepsakeMarkdownInlineSyntaxes =
    <md.InlineSyntax>[];

/// Keepsake 的 markdown 样式表（从当前主题派生：代码块、引用、表格统一配色）。
///
/// 字阶按 README §2：正文 15/1.6（气泡里由调用点再确认）、行内代码 13。
MarkdownStyleSheet keepsakeMarkdownStyleSheet(ThemeData theme) {
  final base = MarkdownStyleSheet.fromTheme(theme);
  final scheme = theme.colorScheme;
  final mono = KeepsakeTheme.monoFontFamily;

  return base.copyWith(
    p: (base.p ?? const TextStyle()).copyWith(fontSize: 15, height: 1.6),
    a: (base.a ?? const TextStyle()).copyWith(
      color: scheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: scheme.primary.withValues(alpha: 0.6),
    ),
    code: (base.code ?? const TextStyle()).copyWith(
      fontFamily: mono,
      fontSize: 13,
      height: 1.7,
      backgroundColor: scheme.surfaceContainerHighest,
      color: scheme.onSurface,
    ),
    codeblockPadding: const EdgeInsets.all(12),
    codeblockDecoration: BoxDecoration(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    blockquote: (base.blockquote ?? const TextStyle()).copyWith(
      color: scheme.onSurfaceVariant,
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    blockquoteDecoration: BoxDecoration(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
      border: Border(
        left: BorderSide(
          color: scheme.primary.withValues(alpha: 0.6),
          width: 3,
        ),
      ),
    ),
    tableBorder: TableBorder.all(color: scheme.outlineVariant),
    tableCellsPadding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
    tableCellsDecoration: BoxDecoration(color: scheme.surfaceContainerLow),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: scheme.outlineVariant)),
    ),
    listBullet: (base.listBullet ?? const TextStyle()).copyWith(
      color: scheme.onSurfaceVariant,
    ),
  );
}
