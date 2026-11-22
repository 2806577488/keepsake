// ==========================================================================
// 摘录文件：lib/features/chat/widgets/markdown_view.dart
// 原文件共 734 行。以下仅为设计师需要看的片段，代码内容原样保留（含原注释）。
// 保留了 _CodeBlock + _CodeBlockState（标题栏 + 复制 + 横向滚动 + 高亮）。
// ==========================================================================


// ---- 摘录 1/1 · 原文件第 585–734 行 ----

/// 代码块：标题栏（语言 + 复制）+ 横向滚动的高亮代码。
///
/// 配色走中性路线：容器底取 [ColorScheme.surfaceContainerHighest]，头部取
/// [ColorScheme.surfaceContainerHigh]；语法高亮深色用 atom-one-dark、
/// 浅色用 atom-one-light（柔和紫/灰令牌，不用刺眼的荧光红）。
/// 长行不换行、不裁剪，交给横向滚动。
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
  Timer? _copiedTimer;
  bool _copied = false;

  @override
  void dispose() {
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
    final isDark = theme.brightness == Brightness.dark;
    // 容器底：浅色直接用中性的 surfaceContainerHighest（不再混 primary，
    // 否则青绿种子色会给代码块染上薄荷绿）；深色再压暗一档，和气泡分层。
    final background = isDark
        ? Color.alphaBlend(Colors.black.withValues(alpha: 0.18), scheme.surfaceContainerHighest)
        : scheme.surfaceContainerHighest;
    // 头部固定用 surfaceContainerHigh，比代码区亮一档，形成「标题栏」层次。
    final headerBackground = scheme.surfaceContainerHigh;
    final borderColor = scheme.outlineVariant.withValues(alpha: 0.6);
    final label = (widget.rawLanguage ?? '').trim();
    // 高亮主题：浅色 atom-one-light、深色 atom-one-dark（柔和紫/灰/青绿令牌，
    // 不是 github 那套刺眼的荧光红）。背景统一交给外层 Container 画，
    // 这里把 root 的背景设成透明，否则 HighlightView 会退回它自带的白底。
    final highlightTheme = Map<String, TextStyle>.of(
      isDark ? atomOneDarkTheme : atomOneLightTheme,
    );
    highlightTheme['root'] = TextStyle(
      color: scheme.onSurface,
      backgroundColor: Colors.transparent,
    );
    const codeStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12.5,
      height: 1.55,
    );

    return Padding(
      // 上下各留 10，和正文之间才有呼吸感。
      padding: const EdgeInsets.only(top: 10, bottom: 10),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 头部固定 34 高：左边语言名，右边图标式复制按钮。
            Container(
              height: 34,
              padding: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(
                color: headerBackground,
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      label.isEmpty ? '代码' : label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 11,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: _copy,
                    tooltip: _copied ? '已复制' : '复制',
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                    color: _copied ? scheme.primary : scheme.onSurfaceVariant,
                    icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded),
                  ),
                ],
              ),
            ),
            // 代码区：横向滚动，长行不再被硬裁掉；等宽 12.5 / 行高 1.55 / 内边距 12。
            Scrollbar(
              thickness: 3,
              radius: const Radius.circular(2),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(12),
                child: widget.language == null
                    ? Text(widget.code, style: codeStyle.copyWith(color: scheme.onSurface))
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
          ],
        ),
      ),
    );
  }
}

// ==========================================================================
// 摘录结束。
// ==========================================================================
