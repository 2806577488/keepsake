/// Keepsake（留声）— Mermaid 图表块（离屏 WebView 渲染 + flutter_svg 显示）。
///
/// 情报依据（`prompts.md` §3 / `dart-symbols.md` `@1168116921`）：
/// - 离屏 `webview_flutter` 加载 `assets/web/mermaid.html`；
/// - JS 通道名固定 **`KeepsakeMermaidBridge`**；
/// - Dart → JS：`window.__keepsakeRender(id, code)`；
/// - JS → Dart：`{ "id": <id>, "svg": "..." }` 或 `{ "id": <id>, "error": "..." }`；
/// - JS 侧已经做掉「style 内联 + marker 展开 + 去 foreignObject」（`mermaid_bridge.js`），
///   Dart 侧只负责用 `flutter_svg` 画返回的 SVG 字符串；
/// - 失败 / 超时 → 回退代码块 + 文案「Mermaid 图表显示失败」。
///
/// 设计要点：
/// - 渲染结果按 mermaid 源码缓存（`_svgCache` / `_failureCache`），滚动重建不会重复跑 WebView；
/// - 所有 WebView 渲染串行（`_renderLock`），避免同时创建多个 3.3MB 的 mermaid 运行环境；
/// - 隐藏的 WebView 只有 1×1 像素且几乎全透明，渲染完立刻销毁。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:keepsake/core/theme.dart';

// ---------------------------------------------------------------------------
// 桥接协议（公开，供测试与其它模块复用）
// ---------------------------------------------------------------------------

/// `mermaid.html` 资源路径（`pubspec.yaml` 里以 `assets/web/` 目录声明）。
const String kMermaidPageAsset = 'assets/web/mermaid.html';

/// `mermaid.min.js` 资源路径（`loadFlutterAsset` 失败时用于内联兜底）。
const String kMermaidJsAsset = 'assets/web/mermaid.min.js';

/// `mermaid_bridge.js` 资源路径（同上）。
const String kMermaidBridgeJsAsset = 'assets/web/mermaid_bridge.js';

/// 渲染失败时展示的固定文案（ui-strings §13 原文）。
const String kMermaidErrorText = 'Mermaid 图表显示失败';

/// JS 侧渲染入口名（`window.__keepsakeRender`）。
const String kMermaidRenderFunction = '__keepsakeRender';

/// Dart ↔ JS 的桥接常量与协议解析。
///
/// JS 侧（`assets/web/mermaid_bridge.js`）用
/// `window.KeepsakeMermaidBridge.postMessage(JSON.stringify({id, svg|error}))` 回传。
class KeepsakeMermaidBridge {
  const KeepsakeMermaidBridge._();

  /// JavaScriptChannel 名称（字符串表实证，勿改）。
  static const String channelName = 'KeepsakeMermaidBridge';

  /// 调用 `window.__keepsakeRender(id, code)` 的脚本。
  ///
  /// 用 `jsonEncode` 生成字面量，代码里的引号/换行/反斜杠都不用自己转义。
  static String renderScript(String id, String code) =>
      'window.$kMermaidRenderFunction(${jsonEncode(id)}, ${jsonEncode(code)});';

  /// 解析 JS 回传的 JSON；无法解析返回 `null`（例如通道里混进别的东西）。
  static MermaidRenderReply? decode(String message) {
    final raw = message.trim();
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = decoded.cast<String, Object?>();
      final id = (map['id'] ?? '').toString();
      final svg = map['svg']?.toString();
      final error = map['error']?.toString();
      if (svg != null && svg.trim().isNotEmpty) {
        return MermaidRenderReply(id: id, svg: svg);
      }
      return MermaidRenderReply(
        id: id,
        error: (error == null || error.trim().isEmpty) ? kMermaidErrorText : error,
      );
    } catch (_) {
      return null;
    }
  }

  /// 探测页面是否就绪的脚本（返回 `"ready"` / `"wait"`）。
  static const String readyProbeScript =
      'typeof window.$kMermaidRenderFunction === "function" ? "ready" : "wait"';
}

/// JS → Dart 的一次渲染回执。
@immutable
class MermaidRenderReply {
  const MermaidRenderReply({required this.id, this.svg, this.error});

  /// 本次渲染的 id（`window.__keepsakeRender(id, code)` 传下去的那个）。
  final String id;

  /// 成功时的 SVG 字符串（`mermaid_bridge.js` 已做完 style 内联 / marker 展开）。
  final String? svg;

  /// 失败原因（JS 原文或 [kMermaidErrorText]）。
  final String? error;

  /// 是否成功。
  bool get ok => svg != null && svg!.trim().isNotEmpty;

  @override
  String toString() => 'MermaidRenderReply($id, ${ok ? 'svg=${svg!.length}B' : 'error=$error'})';
}

// ---------------------------------------------------------------------------
// 进程级缓存与串行锁
// ---------------------------------------------------------------------------

/// mermaid 源码 → SVG 字符串。
final Map<String, String> _svgCache = <String, String>{};

/// mermaid 源码 → 失败原因（避免每次滚动都重试坏图）。
final Map<String, String> _failureCache = <String, String>{};

/// 串行化 WebView 渲染：同一时刻只跑一个离屏 WebView。
Future<void> _renderLock = Future<void>.value();

/// 资源文本只读一次（内联兜底路径用）。
Future<String>? _mermaidJsOnce;
Future<String>? _bridgeJsOnce;

Future<String> _assetText(String path) => rootBundle.loadString(path);

/// 把 [action] 排进 `_renderLock` 队列，保证 WebView 渲染互斥。
Future<T> _serialized<T>(Future<T> Function() action) async {
  final previous = _renderLock;
  final current = Completer<void>();
  _renderLock = current.future;
  await previous;
  try {
    return await action();
  } finally {
    if (!current.isCompleted) current.complete();
  }
}

/// 清掉某个源码的失败缓存（UI「重试」用）。
void resetMermaidCache([String? code]) {
  if (code == null) {
    _svgCache.clear();
    _failureCache.clear();
  } else {
    _failureCache.remove(code);
    _svgCache.remove(code);
  }
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// 一个 Mermaid 图表块。
///
/// 放在 `markdown_view.dart` 的 `_CodeBuilder` 里：```` ```mermaid ```` 代码块 →
/// 默认只显示源码 + 一行「渲染图表」按钮（M11：低端机上首次渲染 3.3MB
/// mermaid.min.js 会卡顿/超时，不能自动跑）；用户点按钮才起隐藏 WebView，
/// 成功后用 `flutter_svg` 画并写进进程级缓存，之后（含滚动重建）直接显示图。
/// 失败/超时回退成代码块 + 「Mermaid 图表显示失败」。
class MermaidBlock extends StatefulWidget {
  const MermaidBlock({super.key, required this.code});

  /// mermaid 源码（已 trim）。
  final String code;

  @override
  State<MermaidBlock> createState() => _MermaidBlockState();
}

class _MermaidBlockState extends State<MermaidBlock> {
  /// 隐藏 WebView 的控制器；为空表示当前没有在渲染。
  WebViewController? _controller;

  /// 渲染成功后的 SVG。
  String? _svg;

  /// 失败原因（非空时显示回退代码块）。
  String? _error;

  /// 正在渲染。
  bool _loading = false;

  /// 等待 JS 回执的 completer。
  Completer<MermaidRenderReply>? _pending;

  /// 当前等待中的 id（忽略迟到的旧回执）。
  String? _pendingId;

  /// 每次渲染的唯一 id（`keepsake-mermaid-<id>` 的 id 部分）。
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    // M11：不自动渲染，只查缓存（已渲染过的直接显示图）。
    _readCache();
  }

  @override
  void didUpdateWidget(MermaidBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code) {
      _svg = null;
      _error = null;
      _loading = false;
      _readCache();
    }
  }

  @override
  void dispose() {
    final pending = _pending;
    _pending = null;
    _pendingId = null;
    _controller = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(StateError('Mermaid 渲染被取消'));
    }
    super.dispose();
  }

  /// 只读缓存：命中成功缓存直接显示图；命中失败缓存显示降级块。
  ///
  /// M11：未命中**不**自动渲染——低端机上首次加载 mermaid.min.js 会卡住
  /// 聊天列表，改成用户点「渲染图表」后才真正起 WebView。
  void _readCache() {
    final normalized = widget.code.trim();
    if (normalized.isEmpty) {
      _error = kMermaidErrorText;
      return;
    }
    final cached = _svgCache[normalized];
    if (cached != null) {
      _svg = cached;
      return;
    }
    final failed = _failureCache[normalized];
    if (failed != null) {
      _error = failed;
    }
  }

  /// 用户点「渲染图表」/「重试渲染」：显式开始一次渲染。
  void _startRender() {
    if (_loading) return;
    final normalized = widget.code.trim();
    if (normalized.isEmpty) return;
    setState(() {
      _error = null;
      _svg = null;
      _loading = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_render());
    });
  }

  /// 真正渲染：串行执行，结果写缓存并刷新 UI。
  Future<void> _render() async {
    final normalized = widget.code.trim();
    if (!mounted || normalized.isEmpty) return;
    setState(() => _loading = true);
    try {
      final svg = await _serialized<String>(() => _renderWithWebView(normalized));
      if (!mounted) return;
      _svgCache[normalized] = svg;
      _failureCache.remove(normalized);
      _apply(svg: svg);
    } on TimeoutException {
      _failureCache[normalized] = '$kMermaidErrorText（渲染超时）';
      if (mounted) _apply(error: '$kMermaidErrorText（渲染超时）');
    } catch (error) {
      final message = error is MermaidRenderException ? error.message : '$error';
      _failureCache[normalized] = message;
      if (mounted) _apply(error: message);
    } finally {
      _disposeController();
    }
  }

  /// 应用渲染结果（成功/失败都走这里，保证状态一致）。
  void _apply({String? svg, String? error}) {
    if (!mounted) return;
    setState(() {
      _svg = svg;
      _error = error;
      _loading = false;
    });
  }

  /// 结束渲染后立刻释放 WebView（长会话里不堆平台视图）。
  void _disposeController() {
    if (_controller == null) return;
    if (mounted) {
      setState(() => _controller = null);
    } else {
      _controller = null;
    }
  }

  /// 建一个隐藏 WebView，加载 mermaid 页面，调用 JS 渲染，等回执。
  Future<String> _renderWithWebView(String code) async {
    final controller = await _ensureController();
    await _waitUntilReady(controller);
    final reply = await _callRender(controller, code);
    if (!reply.ok) {
      throw MermaidRenderException(reply.error ?? kMermaidErrorText);
    }
    final svg = reply.svg!;
    // JS 已经保证有 viewBox（没有就 getBBox 兜底）；这里只做兜底补齐。
    return _normalizeSvg(svg);
  }

  /// 创建（或复用）隐藏 WebView 控制器，并把页面加载完。
  Future<WebViewController> _ensureController() async {
    final existing = _controller;
    if (existing != null) return existing;
    final WebViewController controller;
    try {
      controller = WebViewController();
    } catch (error) {
      throw MermaidRenderException('$kMermaidErrorText（当前环境不支持 WebView：$error）');
    }
    try {
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setBackgroundColor(const Color(0x00000000));
      await controller.addJavaScriptChannel(
        KeepsakeMermaidBridge.channelName,
        onMessageReceived: _onJsMessage,
      );
      if (!mounted) throw MermaidRenderException('Mermaid 渲染被取消');
      setState(() => _controller = controller);
      // 等平台视图真正挂上（WebView 需要 attach 之后才会执行 JS）。
      await WidgetsBinding.instance.endOfFrame;
      await _tryRenderPage(controller);
      return controller;
    } catch (error) {
      _disposeController();
      if (error is MermaidRenderException) rethrow;
      throw MermaidRenderException('$kMermaidErrorText（$error）');
    }
  }

  /// 加载页面：优先 `loadFlutterAsset`（相对路径的 script 能正常解析），
  /// 资源未声明时退化成「把 html + 两个 js 内联成一个文档」。
  Future<void> _tryRenderPage(WebViewController controller) async {
    try {
      await controller.loadFlutterAsset(kMermaidPageAsset);
      return;
    } catch (_) {
      // assets 没声明 / 平台不支持 asset 加载：走内联兜底。
    }
    final page = await _assetText(kMermaidPageAsset);
    final mermaidJs = await (_mermaidJsOnce ??= _assetText(kMermaidJsAsset));
    final bridgeJs = await (_bridgeJsOnce ??= _assetText(kMermaidBridgeJsAsset));
    final inlined = _inlinePage(page, mermaidJs, bridgeJs);
    await controller.loadHtmlString(inlined, baseUrl: 'about:blank');
  }

  /// 把 `<script src="...">` 换成内联脚本（`</script` 必须转义，否则文档被截断）。
  String _inlinePage(String page, String mermaidJs, String bridgeJs) {
    var html = page;
    html = html.replaceFirst(
      RegExp(r'<script\s+src="mermaid\.min\.js"\s*>\s*</script>'),
      '<script>${_escapeScript(mermaidJs)}</script>',
    );
    html = html.replaceFirst(
      RegExp(r'<script\s+src="mermaid_bridge\.js"\s*>\s*</script>'),
      '<script>${_escapeScript(bridgeJs)}</script>',
    );
    return html;
  }

  String _escapeScript(String js) => js.replaceAll('</script', r'<\/script');

  /// 轮询 `typeof window.__keepsakeRender`，直到页面脚本就绪或超时。
  Future<void> _waitUntilReady(WebViewController controller) async {
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(deadline)) {
      if (!mounted) throw MermaidRenderException('Mermaid 渲染被取消');
      try {
        final result =
            await controller.runJavaScriptReturningResult(KeepsakeMermaidBridge.readyProbeScript);
        if (result.toString().contains('ready')) return;
      } catch (_) {
        // 页面还在导航中，继续等。
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    throw TimeoutException('mermaid 页面加载超时', const Duration(seconds: 25));
  }

  /// 调用 `window.__keepsakeRender(id, code)` 并等待 JS 回执。
  Future<MermaidRenderReply> _callRender(WebViewController controller, String code) async {
    _attempt += 1;
    final id = 'm$_attempt-${DateTime.now().microsecondsSinceEpoch}';
    final completer = Completer<MermaidRenderReply>();
    _pending = completer;
    _pendingId = id;
    try {
      await controller.runJavaScript(KeepsakeMermaidBridge.renderScript(id, code));
      return await completer.future.timeout(const Duration(seconds: 15));
    } finally {
      _pending = null;
      _pendingId = null;
    }
  }

  /// JS 通道回调：只接受「当前等待中 id」的回执。
  void _onJsMessage(JavaScriptMessage message) {
    final reply = KeepsakeMermaidBridge.decode(message.message);
    if (reply == null) return;
    final pending = _pending;
    if (pending == null || pending.isCompleted) return;
    final expected = _pendingId;
    if (expected != null && reply.id.isNotEmpty && reply.id != expected) return;
    pending.complete(reply);
  }

  /// SVG 兜底：确保 `<svg>` 有 viewBox、宽高是纯数字（flutter_svg 更稳）。
  String _normalizeSvg(String svg) {
    var out = svg.trim();
    if (!out.startsWith('<')) {
      throw const MermaidRenderException(kMermaidErrorText);
    }
    var viewBox = _parseViewBox(out);
    if (viewBox == null) {
      // 没有 viewBox：从 width/height 属性拼一个。
      final width = _parseLength(_svgAttr(out, 'width'));
      final height = _parseLength(_svgAttr(out, 'height'));
      if (width != null && height != null && width > 0 && height > 0) {
        viewBox = Rect.fromLTWH(0, 0, width, height);
        out = _setSvgAttr(out, 'viewBox', '0 0 ${_formatNumber(width)} ${_formatNumber(height)}');
      }
    }
    if (viewBox == null || viewBox.width <= 0 || viewBox.height <= 0) {
      throw const MermaidRenderException(kMermaidErrorText);
    }
    out = _setSvgAttr(out, 'width', _formatNumber(viewBox.width));
    out = _setSvgAttr(out, 'height', _formatNumber(viewBox.height));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = KeepsakeSkinColors.of(context);

    Widget content;
    if (_svg != null) {
      content = _buildDiagram(context, _svg!);
    } else if (_error != null) {
      content = _buildFallback(context, _error!);
    } else if (!_loading) {
      // M11：默认只显示源码 + 「渲染图表」按钮，不自动起 WebView。
      content = _buildPrompt(context);
    } else {
      content = Container(
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: s.rCard,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              'Mermaid 图表渲染中…',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final controller = _controller;
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: <Widget>[
        content,
        // 隐藏的离屏 WebView：1×1 且几乎透明，仅用于跑 mermaid.min.js。
        if (controller != null)
          Positioned(
            right: 0,
            top: 0,
            width: 1,
            height: 1,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.02,
                child: WebViewWidget(controller: controller),
              ),
            ),
          ),
      ],
    );
  }

  /// 用 flutter_svg 画返回的 SVG（按 viewBox 宽高比自适应宽度）。
  Widget _buildDiagram(BuildContext context, String svg) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = KeepsakeSkinColors.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final viewBox = _parseViewBox(svg);
        final size = _measure(constraints, viewBox);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: s.rCard,
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Center(
              child: SvgPicture.string(
                svg,
                width: size.width,
                height: size.height,
                fit: BoxFit.contain,
                placeholderBuilder: (_) => SizedBox(
                  width: size.width,
                  height: size.height,
                  child: const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                errorBuilder: (_, _, _) => _fallbackCode(context, kMermaidErrorText),
              ),
            ),
          ),
        );
      },
    );
  }

  /// M11：未渲染时的默认态 —— 源码 + 一行「渲染图表」按钮。
  ///
  /// 低端机（Redmi 9A 等）首次加载 3.3MB mermaid.min.js 会卡住列表，
  /// 所以不自动渲染；用户主动点按钮才创建 WebView。
  Widget _buildPrompt(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = KeepsakeSkinColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: s.rCard,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 4, 0),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.account_tree_outlined,
                    size: 15,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Mermaid 图表',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _startRender,
                    icon: const Icon(Icons.auto_awesome, size: 16),
                    label: const Text('渲染图表'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: theme.textTheme.labelMedium,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  widget.code.trim(),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 失败/超时回退：标题 + 「Mermaid 图表显示失败」+ 原始代码块 + 重试。
  Widget _buildFallback(BuildContext context, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _fallbackCode(context, message),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                resetMermaidCache(widget.code.trim());
                setState(() {
                  _error = null;
                  _svg = null;
                  _loading = false;
                });
                _startRender();
              },
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('重试渲染'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 回退代码块（标题栏 + 原始 mermaid 源码）。
  Widget _fallbackCode(BuildContext context, String message) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = KeepsakeSkinColors.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Color.alphaBlend(scheme.error.withValues(alpha: 0.05), scheme.surface),
        borderRadius: s.rCard,
        border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
            color: scheme.error.withValues(alpha: 0.06),
            child: Row(
              children: <Widget>[
                Icon(Icons.account_tree_outlined, size: 15, color: scheme.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    kMermaidErrorText,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (message.trim().isNotEmpty && message.trim() != kMermaidErrorText)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      message.trim(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(
                    widget.code.trim(),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 渲染阶段的内部异常（不污染业务错误类型）。
class MermaidRenderException implements Exception {
  const MermaidRenderException(this.message);

  final String message;

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// SVG 小工具（符号名照 `dart-symbols.md`：_parseViewBox / _parseLength /
// _setSvgAttr / _svgAttr / _measure / _formatNumber）
// ---------------------------------------------------------------------------

/// 从 `<svg>` 开始标签里读 `viewBox`；没有/非法返回 `null`。
Rect? _parseViewBox(String svg) {
  final raw = _svgAttr(svg, 'viewBox');
  if (raw == null || raw.trim().isEmpty) return null;
  final parts = raw
      .trim()
      .split(RegExp(r'[\s,]+'))
      .map(_parseLength)
      .whereType<double>()
      .toList(growable: false);
  if (parts.length != 4) return null;
  final width = parts[2];
  final height = parts[3];
  if (width <= 0 || height <= 0) return null;
  return Rect.fromLTWH(parts[0], parts[1], width, height);
}

/// 解析 SVG/CSS 长度：`120`、`120px`、`12.5pt`、`100%`（百分比返回 `null`，无法当绝对长度）。
double? _parseLength(String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return null;
  if (value.endsWith('%')) return null;
  final match = RegExp(r'^(-?\d+(?:\.\d+)?)').firstMatch(value);
  if (match == null) return null;
  return double.tryParse(match.group(1) ?? '');
}

/// 读 `<svg>` 开始标签的属性。
String? _svgAttr(String svg, String name) {
  final start = svg.indexOf('<svg');
  if (start < 0) return null;
  final end = svg.indexOf('>', start);
  final header = end < 0 ? svg.substring(start) : svg.substring(start, end + 1);
  final match = RegExp('$name\\s*=\\s*"([^"]*)"').firstMatch(header) ??
      RegExp("$name\\s*=\\s*'([^']*)'").firstMatch(header);
  return match?.group(1);
}

/// 设置 `<svg>` 开始标签的属性（存在则替换，不存在则插入）。
String _setSvgAttr(String svg, String name, String value) {
  final start = svg.indexOf('<svg');
  if (start < 0) return svg;
  final end = svg.indexOf('>', start);
  if (end < 0) return svg;
  final header = svg.substring(start, end);
  final pattern = RegExp('$name\\s*=\\s*"[^"]*"');
  final replacement = '$name="${value.replaceAll('"', '&quot;')}"';
  final updatedHeader =
      pattern.hasMatch(header) ? header.replaceFirst(pattern, replacement) : '$header $replacement';
  return svg.replaceRange(start, end, updatedHeader);
}

/// 按容器宽度和 viewBox 宽高比算显示尺寸（限制最大高度，避免超长图占满屏）。
Size _measure(BoxConstraints constraints, Rect? viewBox) {
  final available = constraints.maxWidth.isFinite && constraints.maxWidth > 0
      ? constraints.maxWidth
      : 360.0;
  final vbWidth = viewBox?.width ?? 640;
  final vbHeight = viewBox?.height ?? 360;
  if (vbWidth <= 0 || vbHeight <= 0) {
    return Size(available, 240);
  }
  var width = available;
  var height = width * vbHeight / vbWidth;
  const maxHeight = 520.0;
  const minHeight = 80.0;
  if (height > maxHeight) {
    height = maxHeight;
    width = height * vbWidth / vbHeight;
  }
  if (height < minHeight) height = minHeight;
  return Size(width, height);
}

/// 数字格式化：去掉多余的小数零（`120.0` → `120`）。
String _formatNumber(double value) {
  if (value.isNaN || value.isInfinite) return '0';
  final rounded = value.roundToDouble();
  if ((value - rounded).abs() < 0.001) return rounded.toInt().toString();
  return value.toStringAsFixed(2);
}
