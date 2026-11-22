/// Keepsake（留声）— Material 3 主题 + Markdown 样式表。
///
/// 符号证据（dart-symbols.md）：`KeepsakeTheme`、`keepsakeMarkdownExtensions`
/// （与 theme 同库）；`MarkdownStyleSheet.fromTheme` 在符号表里出现（说明样式表从主题派生）。
///
/// 说明：
/// - seed color 在逆向情报里**没有**具体色值证据（字符串表只有 `ColorScheme.fromSeed`、
///   `seed` 之类通用符号）→ 这里的深青绿是**[推断]**，改它不影响任何契约。
/// - 等宽字体族用 `monospace`（字符串表实证 token）→ `KeepsakeTheme.monoFontFamily`。
library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart' show MarkdownStyleSheet;
import 'package:markdown/markdown.dart' as md;

/// Keepsake 的 Material 3 主题。
abstract final class KeepsakeTheme {
  /// 主色种子（**[推断]**：深青绿，「留声」的声波/麦克风意象）。
  static const Color seedColor = Color(0xFF2F6B5F);

  /// 等宽字体族（字符串表实证 token `monospace`）。
  static const String monoFontFamily = 'monospace';

  /// 代码/等宽文本样式。
  static TextStyle monoStyle({double fontSize = 13, FontWeight? fontWeight, Color? color}) =>
      TextStyle(
        fontFamily: monoFontFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: 1.45,
      );

  /// 浅色主题。
  static ThemeData get light => of(Brightness.light);

  /// 深色主题。
  static ThemeData get dark => of(Brightness.dark);

  /// 按亮度构建主题。
  static ThemeData of(Brightness brightness) => _build(brightness);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness);
    final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
    final textTheme = base.textTheme;

    return base.copyWith(
      textTheme: textTheme.copyWith(
        bodyMedium: textTheme.bodyMedium?.copyWith(height: 1.45),
        bodyLarge: textTheme.bodyLarge?.copyWith(height: 1.45),
      ),
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 1,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: scheme.outlineVariant),
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
md.ExtensionSet get keepsakeMarkdownExtensionSet => md.ExtensionSet.gitHubFlavored;

/// 额外**块级** markdown 语法（传给 `MarkdownBody.blockSyntaxes`）。
///
/// 目前为空：公式（`$...$`/`$$...$$`）与 mermaid 围栏由 `MarkdownView` 的
/// `builders` / `_MathSyntax` 处理（F 批次）。签名冻结，需要追加语法时在这里加。
final List<md.BlockSyntax> keepsakeMarkdownExtensions = <md.BlockSyntax>[];

/// 额外**行内** markdown 语法（传给 `MarkdownBody.inlineSyntaxes`）。
///
/// 同上：签名冻结，F 批次的 `_MathSyntax` 可在这里注册。
final List<md.InlineSyntax> keepsakeMarkdownInlineSyntaxes = <md.InlineSyntax>[];

/// Keepsake 的 markdown 样式表（从当前主题派生：代码块、引用、表格统一配色）。
MarkdownStyleSheet keepsakeMarkdownStyleSheet(ThemeData theme) {
  final base = MarkdownStyleSheet.fromTheme(theme);
  final scheme = theme.colorScheme;
  final mono = KeepsakeTheme.monoFontFamily;

  return base.copyWith(
    p: (base.p ?? const TextStyle()).copyWith(height: 1.6),
    a: (base.a ?? const TextStyle()).copyWith(
      color: scheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: scheme.primary.withValues(alpha: 0.6),
    ),
    code: (base.code ?? const TextStyle()).copyWith(
      fontFamily: mono,
      fontSize: 13,
      height: 1.45,
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
      border: Border(left: BorderSide(color: scheme.primary.withValues(alpha: 0.6), width: 3)),
    ),
    tableBorder: TableBorder.all(color: scheme.outlineVariant),
    tableCellsPadding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
    tableCellsDecoration: BoxDecoration(color: scheme.surfaceContainerLow),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: scheme.outlineVariant)),
    ),
    listBullet: (base.listBullet ?? const TextStyle()).copyWith(color: scheme.onSurfaceVariant),
  );
}
