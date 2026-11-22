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
    // 引用标记 `[N]` 必须排在 GFM 的 link / 引用式链接之前：
    // `[10]` 在 CommonMark 里本来就是「引用链接」的写法，排在后面就会被吞成链接，
    // 渲染出裸方括号（v3.3 §1.3 真机 bug）。
    _CitationSyntax(),
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
    this.onCitationTap,
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

  /// 点击引用标记 `[N]` 的回调，参数是方括号里的编号。
  ///
  /// - 为空时**不响应点击**，但 `[N]` 仍然渲染成上标小数字（不能是裸方括号）；
  /// - 非空时编号可点，热区 24×24（v3.3 §1.3），点击后由调用方决定是滚到底部
  ///   的「N 个网页」还是展开引用列表。
  final ValueChanged<int>? onCitationTap;

  /// 本地图片的相对路径基准目录（例如附件缓存目录）；为空则只支持绝对路径/data URI/http(s)。
  final String? imageBasePath;

  @override
  Widget build(BuildContext context) {
    final styleSheet = _keepsakeStyleSheet(context);
    final builders = <String, MarkdownElementBuilder>{
      'pre': _CodeBuilder(),
      kInlineMathTag: _MathBuilder(),
      kCitationTag: _CitationBuilder(onTap: onCitationTap),
    };
    return MarkdownBody(
      data: normalizeMarkdownBold(data),
      selectable: selectable,
      softLineBreak: softLineBreak,
      fitContent: fitContent,
      styleSheet: styleSheet,
      extensionSet: keepsakeMarkdownExtensionSetWithMath,
      builders: builders,
      bulletBuilder: (MarkdownBulletParameters p) =>
          _buildMarkdownBullet(context, p),
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
    this.onCitationTap,
    this.imageBasePath,
  });

  final String data;
  final bool selectable;
  final bool softLineBreak;
  final bool fitContent;
  final void Function(String text, String? href, String title)? onTapLink;
  final ValueChanged<int>? onCitationTap;
  final String? imageBasePath;

  @override
  Widget build(BuildContext context) {
    return KeepsakeMarkdown(
      data: data,
      selectable: selectable,
      softLineBreak: softLineBreak,
      fitContent: fitContent,
      onTapLink: onTapLink,
      onCitationTap: onCitationTap,
      imageBasePath: imageBasePath,
    );
  }
}

// ---------------------------------------------------------------------------
// 引用标记 `[N]`（v3.3 §1.3）
// ---------------------------------------------------------------------------

/// 引用标记的 markdown 元素 tag（[_CitationSyntax] 产出，[_CitationBuilder] 消费）。
const String kCitationTag = 'cite';

/// 引用标记的字号：10（v3.3 §1.3，正文 16 的 62%）。
const double kCitationFontSize = 10;

/// 引用标记的触摸区边长：24（v3.3 §1.3，视觉是小数字，可点区够大）。
///
/// 注意：CSS 用 `::after` 把热区溢出到 18px 外，Flutter 的 `RenderParagraph`
/// 只把命中转给 placeholder 自己的矩形，溢出部分收不到点击 —— 所以这里只能
/// 真的让布局占 24。嫌字间空隙大就改这个常量（16 视觉更紧，热区变小），
/// 不要再在别处写 24。
const double kCitationTouchSize = 24;

/// 把 `[N]`（1–3 位数字）解析成 `<cite>` 元素，交给 [_CitationBuilder] 渲染成上标。
///
/// 为什么必须在这里截住：`[10]` 在 CommonMark 里是「引用式链接」的写法，
/// 不截住就会被链接语法吃掉、渲染成裸方括号（真机 bug：看着像错字，还点不了）。
///
/// 三种必须让路的情况：
/// - `[10](url)`：紧跟 `(` 时是链接文字，返回 false 让给链接语法；
/// - `\[10\]`：前面是反斜杠是转义，用户想看字面方括号；
/// - 行内代码 / 围栏代码：由 CodeSpanSyntax / 代码块先整体吃掉，`[N]` 不会进来。
class _CitationSyntax extends md.InlineSyntax {
  _CitationSyntax() : super(r'\[([0-9]{1,3})\]', startCharacter: 0x5B);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final int end = match.end;
    if (end < parser.source.length && parser.source[end] == '(') return false;
    final int start = match.start;
    if (start > 0 && parser.source[start - 1] == r'\') return false;
    final String digits = match.group(1) ?? '';
    if (digits.isEmpty) return false;
    parser.addNode(md.Element.text(kCitationTag, digits));
    return true;
  }
}

/// 把 `<cite>` 元素渲染成上标小数字（可点）。
class _CitationBuilder extends MarkdownElementBuilder {
  _CitationBuilder({this.onTap});

  /// 点击回调；为空时只渲染上标，不响应点击。
  final ValueChanged<int>? onTap;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final String raw = element.textContent.trim();
    final int? index = int.tryParse(raw);
    if (index == null) return null;
    // 为什么包成 Text.rich：flutter_markdown 0.7 把 inline builder 的返回值当成
    // `Wrap` 的**独立子项**，只有「文本型 widget」（Text / RichText / SelectableText）
    // 才会跟前后文本合并进同一段落；直接返回 GestureDetector 会把数字单独排成一行。
    // 包一层 Text.rich + WidgetSpan，既能被当文本合并，又能带手势。
    final s = KeepsakeSkinColors.of(context);
    final theme = Theme.of(context);
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          WidgetSpan(
            // 为什么 middle + 上移 2：WidgetSpan 没有「上标」对齐方式，
            // middle 让 10px 的数字落在行高中央，再抬 2 贴近 CSS 的 vertical-align: super。
            alignment: PlaceholderAlignment.middle,
            child: Transform.translate(
              offset: const Offset(0, -2),
              // 为什么带尺寸：见 [kCitationTouchSize] 的注释（溢出热区接不到点击）。
              child: SizedBox(
                width: kCitationTouchSize,
                height: kCitationTouchSize,
                child: Center(
                  child: _CitationBadge(
                    index: index,
                    digits: raw,
                    color: s.selectionBar,
                    fontFamily: s.metaFontFamily,
                    radius: s.rCb,
                    pressColor: theme.highlightColor,
                    onTap: onTap,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 引用标记本体：上标小数字 + 按下反馈。
///
/// - 字号 10 / 颜色 `selectionStroke`（token 字段 `selBar`）/ **无下划线**；
/// - 按下反馈走 `--pressed` 语义 = `theme.highlightColor`，不写死灰；
/// - [onTap] 为空时完全不响应点击，但**仍然渲染成上标数字**（不能是裸方括号）。
class _CitationBadge extends StatefulWidget {
  const _CitationBadge({
    required this.index,
    required this.digits,
    required this.color,
    required this.fontFamily,
    required this.radius,
    required this.pressColor,
    this.onTap,
  });

  /// 编号（回调参数）。
  final int index;

  /// 显示的数字（保留模型给的原样，`007` 就显示 `007`）。
  final String digits;

  /// 文字色（`selBar`）。
  final Color color;

  /// 字体族（E 走等宽，A/H 跟主字体，与 .cite 的 `--meta-font` 一致）。
  final String? fontFamily;

  /// 按下高亮块圆角（`rCb`）。
  final BorderRadius radius;

  /// 按下时的底色（`theme.highlightColor`）。
  final Color pressColor;

  /// 点击回调。
  final ValueChanged<int>? onTap;

  @override
  State<_CitationBadge> createState() => _CitationBadgeState();
}

class _CitationBadgeState extends State<_CitationBadge> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    // 为什么 height: 1：10px 字在 1.6 行高里会撑高该行的行盒，
    // 引用标记不该改变正文行距。
    final Widget badge = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: _pressed ? widget.pressColor : Colors.transparent,
        borderRadius: widget.radius,
      ),
      child: Text(
        widget.digits,
        style: TextStyle(
          fontSize: kCitationFontSize,
          height: 1,
          fontWeight: FontWeight.w500,
          color: widget.color,
          fontFamily: widget.fontFamily,
          // v3.3 §1.3：引用标记不做下划线（长段落里太乱）。
          decoration: TextDecoration.none,
        ),
      ),
    );
    final ValueChanged<int>? onTap = widget.onTap;
    // 不可点也必须上标，不能退回裸方括号。
    if (onTap == null) return badge;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(widget.index),
      onTapDown: (TapDownDetails _) => _setPressed(true),
      onTapUp: (TapUpDetails _) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: badge,
    );
  }
}

// ---------------------------------------------------------------------------
// 列表项目符号（v3.3 §1.2：一级 decimal/disc，二级 lower-alpha/circle，三级 lower-roman）
// ---------------------------------------------------------------------------

/// 有序列表编号：1 → a，26 → z，27 → aa（CSS 的 `lower-alpha`）。
String _lowerAlpha(int value) {
  if (value <= 0) return '$value';
  String out = '';
  int n = value;
  while (n > 0) {
    final int rem = (n - 1) % 26;
    out = String.fromCharCode(0x61 + rem) + out;
    n = (n - 1) ~/ 26;
  }
  return out;
}

/// 有序列表编号（小写罗马数字，CSS 的 `lower-roman`，1 → i，4 → iv）。
String _lowerRoman(int value) {
  if (value <= 0 || value > 3999) return '$value';
  const List<int> units = <int>[
    1000,
    900,
    500,
    400,
    100,
    90,
    50,
    40,
    10,
    9,
    5,
    4,
    1,
  ];
  const List<String> symbols = <String>[
    'm',
    'cm',
    'd',
    'cd',
    'c',
    'xc',
    'l',
    'xl',
    'x',
    'ix',
    'v',
    'iv',
    'i',
  ];
  final StringBuffer buffer = StringBuffer();
  int n = value;
  for (int i = 0; i < units.length; i++) {
    while (n >= units[i]) {
      buffer.write(symbols[i]);
      n -= units[i];
    }
  }
  return buffer.toString();
}

/// 列表项目符号：把 flutter_markdown 的默认 decimal / `•` 换成 v3.3 的分层字形。
///
/// 为什么不用 styleSheet：`MarkdownStyleSheet` 只能改 bullet 的字色字号，
/// 编号字符本身由 `_buildBullet` 硬编码成 `1.` 和 `•`；`bulletBuilder` 是
/// 这个版本唯一能改字形的入口（参数带 `nestLevel` 和 `index`）。
Widget _buildMarkdownBullet(
  BuildContext context,
  MarkdownBulletParameters parameters,
) {
  final s = KeepsakeSkinColors.of(context);
  final bool ordered = parameters.style == BulletStyle.orderedList;
  final int number = parameters.index + 1;
  final String label;
  if (ordered) {
    // 省略 break：三级及更深都按 lower-roman 处理（CSS 里 `ol ol ol` 起算。
    switch (parameters.nestLevel) {
      case 0:
        label = '$number.';
      case 1:
        label = '${_lowerAlpha(number)}.';
      default:
        label = '${_lowerRoman(number)}.';
    }
  } else {
    // disc / circle（三级起沿用 circle，AI 极少写到三级无序）。
    label = parameters.nestLevel == 0 ? '•' : '◦';
  }
  return Text(
    label,
    textAlign: ordered ? TextAlign.right : TextAlign.center,
    style: TextStyle(
      fontSize: s.fsBody,
      height: s.lineHeight,
      color: s.c.onV,
      fontFamily: s.metaFontFamily,
    ),
  );
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
  final TextStyle body =
      (base.p ?? const TextStyle()).copyWith(
        fontSize: s.fsBody,
        height: s.lineHeight,
        color: s.c.onS,
      );
  return base.copyWith(
    // 每个块的横向 14 = 气泡内边距 12/14（README §4.3）；纵向只带顶部
    // （底部留白由气泡自己补一次，否则相邻两块的 12 会叠成 24）。
    // 代码块自己不吃这个 padding，直接贴到气泡内缘（通栏出血）。
    pPadding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
    p: body,
    codeblockPadding: EdgeInsets.zero,
    codeblockDecoration: const BoxDecoration(),
    codeblockAlign: WrapAlignment.start,
    blockSpacing: 0,
    // v3.3 §1.2：列表 padding-left 20；bullet 与正文之间留 6。
    listIndent: 20,
    listBulletPadding: const EdgeInsets.only(right: 6),
    listBullet: body.copyWith(color: s.c.onV),
    h1Padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
    h2Padding: const EdgeInsets.fromLTRB(14, 10, 14, 3),
    h3Padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
    tableColumnWidth: const IntrinsicColumnWidth(),
    // ---- v3.3 §1.2 元素样式补齐 ----
    // 粗体 700 / 斜体 italic：fromTheme 里默认值随 Material 走，这里钉死。
    strong: (base.strong ?? const TextStyle()).copyWith(
      fontWeight: FontWeight.w700,
    ),
    em: (base.em ?? const TextStyle()).copyWith(fontStyle: FontStyle.italic),
    // 删除线：line-through + onV（和正文明确区分）。
    del: (base.del ?? const TextStyle()).copyWith(
      color: s.c.onV,
      decoration: TextDecoration.lineThrough,
      decorationColor: s.c.onV,
    ),
    // 链接：selBar + 1px 下划线。Flutter 没有 `text-underline-offset`，
    // 用 1px 的 decorationThickness 让下划线尽量贴近 CSS 的细线观感。
    a: (base.a ?? const TextStyle()).copyWith(
      color: s.selectionBar,
      decoration: TextDecoration.underline,
      decorationColor: s.selectionBar,
      decorationThickness: 1,
    ),
    // 引用块：左侧 2px selBar 竖线，文字 onV，不铺底色（v3.3 §1.2）。
    blockquote: body.copyWith(color: s.c.onV),
    blockquotePadding: const EdgeInsets.fromLTRB(12, 4, 10, 4),
    blockquoteDecoration: BoxDecoration(
      border: Border(
        left: BorderSide(color: s.selectionBar, width: 2),
      ),
    ),
    // 分隔线：1px ov。
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: s.c.ov)),
    ),
  );
}

// ---------------------------------------------------------------------------
// 图片
// ---------------------------------------------------------------------------

/// markdown 块的横向内边距（气泡内缘留白），见 [_keepsakeStyleSheet] 的 pPadding。
const double kMarkdownHorizontalPadding = 14;

/// 图片「max-width: 100%」（v3.3 §1.2）：不撑破气泡。
///
/// 为什么不能只靠 `config.width`：模型给的 `![x](url)` 没有尺寸，
/// Image 会按图片原始像素铺开，宽图直接把气泡撑出屏幕；
/// 这里按屏宽减两侧留白给出上限，Image 自己按比例缩。
Widget _constrainImageWidth(BuildContext context, Widget child) {
  final double maxWidth =
      MediaQuery.sizeOf(context).width - kMarkdownHorizontalPadding * 2;
  return ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth > 0 ? maxWidth : 0),
    child: child,
  );
}

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
      return _constrainImageWidth(
        context,
        ClipRRect(
          borderRadius: s.rCard,
          child: Image.memory(
            data,
            fit: BoxFit.contain,
            width: width,
            height: height,
          ),
        ),
      );
    }
    if (scheme == 'http' || scheme == 'https') {
      return _constrainImageWidth(
        context,
        ClipRRect(
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
    return _constrainImageWidth(
      context,
      ClipRRect(
        borderRadius: s.rCard,
        child: Image.file(
          File(path),
          fit: BoxFit.contain,
          width: width,
          height: height,
          errorBuilder: (_, _, _) => placeholder,
        ),
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
