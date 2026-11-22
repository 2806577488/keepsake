/// Keepsake（留声）— 聊天消息的 Markdown 渲染。
///
/// 情报依据：
/// - `dart-symbols.md`：本库（`@1165387135`）私有符号 `_CodeBlock`(+`_CodeBlockState`)、
///   `_CodeBuilder`、`_MathBuilder`、`_MathSyntax`；公开符号 `MarkdownView`、`KeepsakeMarkdown`；
///   扩展集 `keepsakeMarkdownExtensions`（与 theme 同套样式）。
/// - `prompts.md` §4：`$...$` / `$$...$$` 走 flutter_math_fork（KaTeX 字体由该包自带），
///   代码块走 highlight / flutter_highlight，表格/引用/列表由 GFM 扩展提供。
/// - 额外：`mermaid` 代码块交给 [MermaidBlock] 用离屏 WebView 渲染。
///
/// 该文件不依赖任何其它批次（除同批次的 `mermaid_block.dart`），可独立 analyze。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:flutter_math_fork/flutter_math.dart' as tex;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:highlight/languages/all.dart' show allLanguages;
import 'package:keepsake/core/theme.dart'
    show
        KeepsakeSkinColors,
        KeepsakeTheme,
        keepsakeMarkdownExtensionSet,
        keepsakeMarkdownInlineSyntaxes,
        keepsakeMarkdownStyleSheet;
import 'package:markdown/markdown.dart' as md;

import 'mermaid_block.dart';

/// 代码块语言标记：```` ```mermaid ````。
const String kMermaidCodeLanguage = 'mermaid';

/// 数学公式的 markdown 元素 tag（`_MathSyntax` 产出，`_MathBuilder` 消费）。
const String kInlineMathTag = 'math';

/// highlight 支持的语言 + 别名（`highlight.parse` 遇到未知语言会抛 ArgumentError，
/// 所以这里先自己校验一遍，未知语言退化成纯文本而不是崩掉渲染）。
final Set<String> _highlightLanguages = () {
  final names = <String>{};
  allLanguages.forEach((String name, Object? mode) {
    names.add(name.toLowerCase());
    try {
      final aliases = (mode as dynamic).aliases;
      if (aliases is List) {
        for (final alias in aliases) {
          names.add(alias.toString().toLowerCase());
        }
      }
    } catch (_) {
      // Mode 是动态类型，取不到别名就只登记主名。
    }
  });
  return names;
}();

/// 常见写法 → highlight 主名（模型经常写 `js`/`py`/`sh` 这些短名）。
const Map<String, String> _languageAliases = <String, String>{
  'js': 'javascript',
  'jsx': 'javascript',
  'ts': 'typescript',
  'tsx': 'typescript',
  'py': 'python',
  'rb': 'ruby',
  'sh': 'bash',
  'shell': 'bash',
  'zsh': 'bash',
  'yml': 'yaml',
  'md': 'markdown',
  'rs': 'rust',
  'kt': 'kotlin',
  'kts': 'kotlin',
  'cs': 'csharp',
  'c#': 'csharp',
  'c++': 'cpp',
  'cc': 'cpp',
  'h': 'cpp',
  'objc': 'objectivec',
  'golang': 'go',
  'docker': 'dockerfile',
  'html': 'xml',
  'plaintext': 'plaintext',
  'text': 'plaintext',
  'txt': 'plaintext',
  'jsonc': 'json',
};

/// 把模型给的语言标记规范成 highlight 认识的名字；不认识返回 `null`。
///
/// `mermaid` / `mmd` 返回 [kMermaidCodeLanguage]（不是 highlight 语言，由 [MermaidBlock] 处理）。
String? normalizeCodeLanguage(String? raw) {
  final value = raw?.trim().toLowerCase() ?? '';
  if (value.isEmpty) return null;
  // 有时模型写成 `language-dart` / `{.dart}`。
  var name = value;
  if (name.startsWith('language-')) name = name.substring('language-'.length);
  if (name.startsWith('{') && name.endsWith('}')) {
    name = name.substring(1, name.length - 1).trim();
  }
  if (name == 'mermaid' || name == 'mmd') return kMermaidCodeLanguage;
  final mapped = _languageAliases[name] ?? name;
  if (_highlightLanguages.contains(mapped)) return mapped;
  return null;
}

/// Keepsake 实际使用的 markdown 扩展集：`core/theme.dart` 冻结的
/// [keepsakeMarkdownExtensionSet]（GFM：表格/删除线/任务列表/脚注/自动链接）
/// + `core/theme.dart` 预留的 [keepsakeMarkdownInlineSyntaxes] 槽位
/// + 本文件的数学公式语法（`$...$` / `$$...$$`）。
///
/// 注意：`core/theme.dart` 里的 `keepsakeMarkdownExtensions` 是
/// `List<md.BlockSyntax>`（块级语法槽位，目前为空），不是 ExtensionSet，
/// 所以这里组装而不是直接引用。
final md.ExtensionSet keepsakeMarkdownExtensionSetWithMath = md.ExtensionSet(
  keepsakeMarkdownExtensionSet.blockSyntaxes,
  <md.InlineSyntax>[
    ...keepsakeMarkdownExtensionSet.inlineSyntaxes,
    ...keepsakeMarkdownInlineSyntaxes,
    _CjkBoldSyntax(),
    _MathSyntax(),
  ],
);

/// `**加粗**` 的哨兵字符（私用区，正文里不会出现）。
const String _kBoldOpen = '\uE000';
const String _kBoldClose = '\uE001';

/// 解析哨兵包裹的加粗，绕开 CommonMark 的 emphasis 侧翼规则。
///
/// 规则上「汉字 + `**` + 引号/标点」这种组合不算 left-flanking，
/// 例如模型常写的 `针对**“水热胶结、玄府闭塞”这一特定结构**而言`，
/// 结果 `**` 被当成普通字符整段不渲染。哨兵没有侧翼限制，能正常出 strong。
class _CjkBoldSyntax extends md.InlineSyntax {
  _CjkBoldSyntax() : super('$_kBoldOpen([\\s\\S]*?)$_kBoldClose');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(
      md.Element('strong', <md.Node>[md.Text(match.group(1) ?? '')]),
    );
    return true;
  }
}

/// 渲染前把 `**加粗**` 改写成哨兵形式（跳过围栏代码块与行内代码）。
String normalizeMarkdownBold(String data) {
  final buffer = StringBuffer();
  var i = 0;
  var fence = false;
  var tick = false;
  while (i < data.length) {
    if (!tick && data.startsWith('```', i)) {
      fence = !fence;
      buffer.write('```');
      i += 3;
      continue;
    }
    final ch = data[i];
    if (!fence && ch == '`') {
      tick = !tick;
      buffer.write(ch);
      i += 1;
      continue;
    }
    if (!fence && !tick && data.startsWith('**', i)) {
      final end = _findBoldEnd(data, i + 2);
      if (end > i + 2) {
        final inner = data.substring(i + 2, end);
        if (!inner.contains('\n')) {
          buffer
            ..write(_kBoldOpen)
            ..write(inner)
            ..write(_kBoldClose);
          i = end + 2;
          continue;
        }
      }
    }
    buffer.write(ch);
    i += 1;
  }
  return buffer.toString();
}

/// 找配对的收尾 `**`（跳过行内代码）。
int _findBoldEnd(String data, int from) {
  var i = from;
  var tick = false;
  while (i < data.length - 1) {
    final ch = data[i];
    if (ch == '`') tick = !tick;
    if (!tick && ch == '*' && data[i + 1] == '*') return i;
    i += 1;
  }
  return -1;
}

/// 把 markdown 粗略转成纯文本（TTS 朗读、复制、标题摘要都用得上）。
///
/// 不追求完美排版，只保证「代码块不读出反引号、公式不读出美元符号、链接只读文字」。
String keepsakeMarkdownToPlainText(String markdown) {
  var text = markdown;
  // 围栏代码块：保留代码内容（朗读时比丢掉更有用），去掉围栏行。
  text = text.replaceAllMapped(
    RegExp(r'```[^\n]*\n([\s\S]*?)```'),
    (Match m) => '\n${m.group(1) ?? ''}\n',
  );
  // `$$...$$` / `$...$` 公式：去掉定界符。
  text = text.replaceAllMapped(
    RegExp(r'\$\$([\s\S]+?)\$\$'),
    (Match m) => m.group(1) ?? '',
  );
  text = text.replaceAllMapped(
    RegExp(r'\$([^$\n]+?)\$'),
    (Match m) => m.group(1) ?? '',
  );
  // 行内代码。
  text = text.replaceAllMapped(
    RegExp(r'`([^`\n]+?)`'),
    (Match m) => m.group(1) ?? '',
  );
  // 图片 → alt；链接 → 文字。
  text = text.replaceAllMapped(
    RegExp(r'!\[([^\]]*)\]\([^)]*\)'),
    (Match m) => m.group(1) ?? '',
  );
  text = text.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]*\)'),
    (Match m) => m.group(1) ?? '',
  );
  // 标题 / 引用 / 列表符号。
  text = text.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^\s{0,3}>\s?', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^\s{0,3}[-*+]\s+', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^\s{0,3}\d+[.)]\s+', multiLine: true), '');
  // 强调标记与表格分隔线。
  text = text.replaceAllMapped(
    RegExp(r'(\*\*|__)(.*?)\1'),
    (Match m) => m.group(2) ?? '',
  );
  text = text.replaceAllMapped(
    RegExp(r'(?<![\w*])\*(?!\s)(.*?)(?<!\s)\*(?![\w*])'),
    (Match m) => m.group(1) ?? '',
  );
  text = text.replaceAll(
    RegExp(r'^\s*\|?[\s:|-]+\|[\s:|-]*$', multiLine: true),
    '',
  );
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return text.trim();
}

/// 一条消息的 Markdown 渲染主体。
///
/// - 代码块 → [_CodeBlock]（高亮 + 复制按钮；`mermaid` 走 [MermaidBlock]）
/// - `$...$` / `$$...$$` → flutter_math_fork
/// - 表格 / 引用 / 列表 / 图片 → GFM 默认实现 + 与主题统一的样式
/// - 链接点击交给调用方（聊天页用 `url_launcher`/SnackBar）
class KeepsakeMarkdown extends StatelessWidget {
  const KeepsakeMarkdown({
    super.key,
    required this.data,
    this.selectable = true,
    this.softLineBreak = true,
    this.fitContent = false,
    this.onTapLink,
    this.imageBasePath,
  });

  /// markdown 原文（流式输出时可以是半截文档）。
  final String data;

  /// 是否允许选中复制。
  final bool selectable;

  /// 单个换行是否当硬换行（聊天场景必须为 true，模型经常只发 `\n`）。
  final bool softLineBreak;

  /// 内容宽度是否贴合内容（false = 撑满气泡宽度）。
  final bool fitContent;

  /// 点击链接回调；为空时交给 flutter_markdown 默认行为（不跳转）。
  final void Function(String text, String? href, String title)? onTapLink;

  /// 本地图片的相对路径基准目录（例如附件缓存目录）；为空则只支持绝对路径/data URI/http(s)。
  final String? imageBasePath;

  @override
  Widget build(BuildContext context) {
    final styleSheet = _keepsakeStyleSheet(context);
    final builders = <String, MarkdownElementBuilder>{
      'pre': _CodeBuilder(),
      kInlineMathTag: _MathBuilder(),
    };
    return MarkdownBody(
      data: normalizeMarkdownBold(data),
      selectable: selectable,
      softLineBreak: softLineBreak,
      fitContent: fitContent,
      styleSheet: styleSheet,
      extensionSet: keepsakeMarkdownExtensionSetWithMath,
      builders: builders,
      onTapLink: onTapLink,
      sizedImageBuilder: (MarkdownImageConfig config) =>
          _buildImage(context, config, imageBasePath),
    );
  }
}

/// 兼容符号名（`dart-symbols.md` 里 `MarkdownView` 与 `KeepsakeMarkdown` 同库）。
///
/// 只是 [KeepsakeMarkdown] 的薄包装，方便调用方按任一名字使用。
class MarkdownView extends StatelessWidget {
  const MarkdownView({
    super.key,
    required this.data,
    this.selectable = true,
    this.softLineBreak = true,
    this.fitContent = false,
    this.onTapLink,
    this.imageBasePath,
  });

  final String data;
  final bool selectable;
  final bool softLineBreak;
  final bool fitContent;
  final void Function(String text, String? href, String title)? onTapLink;
  final String? imageBasePath;

  @override
  Widget build(BuildContext context) {
    return KeepsakeMarkdown(
      data: data,
      selectable: selectable,
      softLineBreak: softLineBreak,
      fitContent: fitContent,
      onTapLink: onTapLink,
      imageBasePath: imageBasePath,
    );
  }
}

// ---------------------------------------------------------------------------
// 样式
// ---------------------------------------------------------------------------

/// 与主题（`KeepsakeTheme`，Material 3）配套的 markdown 样式。
///
/// 基础样式直接取 `core/theme.dart` 的 [keepsakeMarkdownStyleSheet]（同一套配色与
/// 皮肤 token：正文 fsBody/行高、行内代码、代码块、表格、引用都已按皮肤生成），
/// 本函数只覆盖聊天气泡的排版差异，**不重写一套字号/颜色**：
/// - 气泡本身 padding 归零（设计稿 `MessageBubbleShell`）：横向内边距由
///   每个块自己带，代码块才能「通栏出血」到气泡内缘；
/// - 代码块外观由 [_CodeBlock] 自己画（头部 + 代码区 + 分隔线），这里清掉外层装饰；
/// - 正文行高跟 `s.lineHeight`（A 1.6 / E 1.6 / H 1.55），不再写死。
MarkdownStyleSheet _keepsakeStyleSheet(BuildContext context) {
  final theme = Theme.of(context);
  // 为什么：字号 / 行高 / 圆角只能来自皮肤 token，页面写死会让三套皮肤长得一样。
  final s = KeepsakeSkinColors.of(context);
  final base = keepsakeMarkdownStyleSheet(theme);
  return base.copyWith(
    // 每个块的横向 14 = 气泡内边距 12/14（README §4.3）；纵向只带顶部
    // （底部留白由气泡自己补一次，否则相邻两块的 12 会叠成 24）。
    // 代码块自己不吃这个 padding，直接贴到气泡内缘（通栏出血）。
    pPadding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
    p: (base.p ?? const TextStyle()).copyWith(
      fontSize: s.fsBody,
      height: s.lineHeight,
    ),
    codeblockPadding: EdgeInsets.zero,
    codeblockDecoration: const BoxDecoration(),
    codeblockAlign: WrapAlignment.start,
    blockSpacing: 0,
    listIndent: 22,
    blockquotePadding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
    h1Padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
    h2Padding: const EdgeInsets.fromLTRB(14, 10, 14, 3),
    h3Padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
    tableColumnWidth: const IntrinsicColumnWidth(),
  );
}

// ---------------------------------------------------------------------------
// 图片
// ---------------------------------------------------------------------------

/// markdown 图片统一入口：http(s) / data URI / 本地绝对路径 / 相对 [basePath]。
Widget _buildImage(
  BuildContext context,
  MarkdownImageConfig config,
  String? basePath,
) {
  // 为什么：图片圆角也必须跟皮肤（A 14 / E 6 / H 12），写死 8 换皮肤不会变。
  final s = KeepsakeSkinColors.of(context);
  final alt = (config.alt ?? '').trim();
  final placeholder = _ImagePlaceholder(
    label: alt.isEmpty ? '图片' : alt,
    icon: Icons.broken_image_outlined,
    color: s.c.onV,
  );
  final width = config.width;
  final height = config.height;
  try {
    final uri = config.uri;
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'data') {
      final data = _decodeDataUri(uri.toString());
      if (data == null) return placeholder;
      return ClipRRect(
        borderRadius: s.rCard,
        child: Image.memory(
          data,
          fit: BoxFit.contain,
          width: width,
          height: height,
        ),
      );
    }
    if (scheme == 'http' || scheme == 'https') {
      return ClipRRect(
        borderRadius: s.rCard,
        child: Image.network(
          uri.toString(),
          fit: BoxFit.contain,
          width: width,
          height: height,
          errorBuilder: (_, _, _) => placeholder,
          loadingBuilder:
              (BuildContext context, Widget child, ImageChunkEvent? event) {
                if (event == null) return child;
                return _ImagePlaceholder(
                  label: alt.isEmpty ? '图片' : alt,
                  icon: s.icon(
                    filled: Icons.image_outlined,
                    outlined: Icons.image_outlined,
                  ),
                  color: s.c.onV,
                );
              },
        ),
      );
    }
    // 本地文件：`file://` 或直接给绝对路径（附件缓存路径）。
    var path = scheme == 'file' ? uri.toFilePath() : uri.toString();
    if (scheme.isEmpty &&
        basePath != null &&
        basePath.isNotEmpty &&
        !path.startsWith('/')) {
      path = '$basePath/$path';
    }
    return ClipRRect(
      borderRadius: s.rCard,
      child: Image.file(
        File(path),
        fit: BoxFit.contain,
        width: width,
        height: height,
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  } catch (_) {
    return placeholder;
  }
}

Uint8List? _decodeDataUri(String uri) {
  final comma = uri.indexOf(',');
  if (comma < 0) return null;
  final meta = uri.substring(0, comma);
  final payload = uri.substring(comma + 1);
  try {
    if (meta.contains(';base64')) return base64Decode(payload);
    return utf8.encode(Uri.decodeComponent(payload));
  } catch (_) {
    return null;
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // 为什么：占位框是「卡片」形态，圆角跟 s.rCard，写死 8 换皮肤不变。
    final s = KeepsakeSkinColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: s.rCard,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: color),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 公式（$...$ / $$...$$）
// ---------------------------------------------------------------------------

/// `$...$` / `$$...$$` 的 inline 语法。
///
/// `$$...$$` 会标记 `data-display=block`，由 [_MathBuilder] 决定用 `MathStyle.display`
/// 还是 `MathStyle.text`。代码段（反引号）先于本语法匹配，所以代码里的 `$` 不会被误判。
class _MathSyntax extends md.InlineSyntax {
  _MathSyntax()
    : super(r'\$\$([\s\S]+?)\$\$|\$([^$\n]+?)\$', startCharacter: 0x24);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final isBlock = match.group(1) != null;
    final expression =
        (isBlock ? match.group(1) : match.group(2))?.trim() ?? '';
    if (expression.isEmpty) return false;
    final element = md.Element.text(kInlineMathTag, expression);
    element.attributes['data-display'] = isBlock ? 'block' : 'inline';
    parser.addNode(element);
    return true;
  }
}

/// 把 `<math>` 元素渲染成 flutter_math_fork 的公式。
class _MathBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final expression = (element.attributes['data-tex'] ?? element.textContent)
        .trim();
    if (expression.isEmpty) return null;
    final isBlock = element.attributes['data-display'] == 'block';
    final theme = Theme.of(context);
    // 为什么：公式基线与正文同阶（fsBody / 主要字色），颜色与字号都不写死。
    final s = KeepsakeSkinColors.of(context);
    final baseStyle =
        (preferredStyle ?? theme.textTheme.bodyMedium ?? const TextStyle())
            .copyWith(color: s.c.onS, fontSize: s.fsBody);
    final formula = tex.Math.tex(
      expression,
      mathStyle: isBlock ? tex.MathStyle.display : tex.MathStyle.text,
      textStyle: baseStyle,
      onErrorFallback: (tex.FlutterMathException error) {
        // 公式写错时退化成等宽原文，别把整条消息搞崩。
        return Text(
          isBlock ? '\$\$$expression\$\$' : '\$$expression\$',
          style: baseStyle.copyWith(
            fontFamily: KeepsakeTheme.monoFontFamily,
            color: s.c.errC,
          ),
        );
      },
    );
    if (!isBlock) return formula;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Align(
        alignment: Alignment.center,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: formula,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 代码块
// ---------------------------------------------------------------------------

/// `pre` 元素的构建器：拿到语言标记和代码原文，交给 [_CodeBlock]。
class _CodeBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = element.textContent.replaceFirst(RegExp(r'\n$'), '');
    String? language;
    for (final child in element.children ?? const <md.Node>[]) {
      if (child is md.Element && child.tag == 'code') {
        final className = child.attributes['class'] ?? '';
        final match = RegExp(r'language-([^\s]+)').firstMatch(className);
        if (match != null) language = match.group(1);
        break;
      }
    }
    final normalized = normalizeCodeLanguage(language);
    if (normalized == kMermaidCodeLanguage) {
      return MermaidBlock(code: code.trim());
    }
    if (code.trim().isEmpty) return const SizedBox.shrink();
    return _CodeBlock(code: code, language: normalized, rawLanguage: language);
  }
}

/// 代码块（拍板稿：通栏出血的「卡片」+ 头部 + 分隔线 + 代码区）。
///
/// 结构：头部 34（语言 + 复制）+ 1px 分隔线 + 代码区，整体是一张卡片：
/// - 左右贴到气泡内缘（气泡 padding 归零，横向内边距由正文块自己带），
///   只保留上下 12 的外边距；
/// - 底 [KeepsakeSkinColors.codeBackground]、头部 [KeepsakeSkinColors.codeHeader]、
///   分隔线 [KeepsakeSkinColors.codeDivider]、文字 [KeepsakeSkinColors.codeForeground]；
/// - 圆角 `skin.rCard`（A 14 / E 6 / H 12），描边 `skin.hairlineBorder`
///   （只有 E 非空 = 1px #D8D4CC）；
/// - 代码横向滚动、**不换行**、字号 `fsSub` / 行高 1.7 / monospace；
/// - 语法高亮浅色 atom-one-light（为白底设计）、深色 atom-one-dark；
/// - 复制键视觉 16，热区 44×34，颜色 [ColorScheme.primary]，2s 后复位。
///
/// 符号名照抄 `dart-symbols.md`（`_CodeBlock` / `_CodeBlockState`）。
class _CodeBlock extends StatefulWidget {
  const _CodeBlock({required this.code, this.language, this.rawLanguage});

  /// 代码原文（已去掉末尾换行）。
  final String code;

  /// 规范化后的 highlight 语言；`null` 表示不高亮。
  final String? language;

  /// 模型原始写的语言标记（用于标题栏显示，即使 highlight 不认识）。
  final String? rawLanguage;

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  /// 代码区横向滚动控制器（Scrollbar 需要和 SingleChildScrollView 共用）。
  final ScrollController _hScroll = ScrollController();

  Timer? _copiedTimer;
  bool _copied = false;

  @override
  void dispose() {
    _hScroll.dispose();
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final skin = KeepsakeSkinColors.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final label = (widget.rawLanguage ?? '').trim();
    // 高亮主题：浅色 atom-one-light（这套本来就是为白底设计的）、
    // 深色 atom-one-dark。背景统一交给外层卡片的 codeBackground 画，这里把 root
    // 背景设成透明，否则 HighlightView 会退回它自带的白底。
    final highlightTheme = Map<String, TextStyle>.of(
      isDark ? atomOneDarkTheme : atomOneLightTheme,
    );
    highlightTheme['root'] = TextStyle(
      color: skin.codeForeground,
      backgroundColor: Colors.transparent,
    );
    // 代码字阶：fsSub / 行高 1.7（代码行高固定 1.7，不用正文 1.55~1.6）。
    final codeStyle = TextStyle(
      fontFamily: KeepsakeTheme.monoFontFamily,
      fontSize: skin.fsSub,
      height: 1.7,
      color: skin.codeForeground,
    );

    return Padding(
      // 通栏出血：左右 0（贴气泡内缘），只留上下 12 与正文隔开。
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        // 为什么整块包一层卡片：三套皮肤靠圆角 + 只有 E 的 1px 描边区分代码块形态，
        // 头部/代码区的底色仍各自铺，圆角靠 clip 裁掉，不需要额外 ClipRRect。
        decoration: BoxDecoration(
          color: skin.codeBackground,
          borderRadius: skin.rCard,
          border: skin.hairlineBorder,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 头部 34 高淡青：左边语言名，右边复制键。
            Container(
              height: 34,
              padding: const EdgeInsets.only(left: 14, right: 8),
              color: skin.codeHeader,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      label.isEmpty ? '代码' : label,
                      style: TextStyle(
                        // 为什么：语言名是元信息 —— E 走等宽，A/H 跟主字体。
                        fontFamily: skin.metaFontFamily,
                        fontSize: skin.fsSub,
                        fontWeight: FontWeight.w500,
                        color: skin.c.onV,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: _copy,
                    tooltip: _copied ? '已复制' : '复制',
                    // §6：复制代码按 icons.md「复制」行走 content_copy(_outlined) 18，勾 16。
                    iconSize: _copied ? 16 : 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 34,
                    ),
                    color: scheme.primary,
                    icon: Icon(
                      _copied
                          ? Icons.check
                          : skin.icon(
                              filled: Icons.content_copy,
                              outlined: Icons.content_copy_outlined,
                            ),
                    ),
                  ),
                ],
              ),
            ),
            // 1px 分隔线（拍板稿 codeDiv）。
            Container(height: 1, color: skin.codeDivider),
            // 代码区：底色由外层卡片铺，这里只留内边距 10/14，横向滚动、不换行。
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              child: Scrollbar(
                controller: _hScroll,
                child: SingleChildScrollView(
                  controller: _hScroll,
                  scrollDirection: Axis.horizontal,
                  child: widget.language == null
                      ? Text(
                          widget.code,
                          style: codeStyle,
                          softWrap: false,
                        )
                      : RepaintBoundary(
                          child: HighlightView(
                            widget.code,
                            language: widget.language,
                            theme: highlightTheme,
                            padding: EdgeInsets.zero,
                            textStyle: codeStyle,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
