// ==========================================================================
// 摘录文件：lib/features/chat/chat_screen.dart
// 原文件共 3025 行。以下仅为设计师需要看的片段，代码内容原样保留（含原注释）。
// 保留了：文件头说明 + 附件选择，_MessageBubble（气泡结构），_ComposerTools/_ToolChip（工具芯片）。
// ==========================================================================


// ---- 摘录 1/3 · 原文件第 1–400 行 ----

/// Keepsake（留声）— 聊天页。
///
/// 情报依据：`next-steps.md` §2 chat_screen（私有 widget / 方法名必须照抄）、
/// `dart-symbols.md` `@1162155074`、`ui-strings.txt` §2/§3。
///
/// 结构（自上而下）：
/// - `AppBar`：会话标题 + [_ModelPick]（平台与模型，当前会话）+ 分支导航 + 更多菜单
/// - [_ErrorBanner]：错误条（重试 / 关闭）
/// - 消息列表：`ScrollablePositionedList`（[_scrollToIndex] / [_jumpToBottom]），
///   每条消息 = [_MessageBubble]，最后一条 assistant 带 [_BranchSwitcher] + [_RegenerateButton]
/// - 空态：[_EmptyChat]（「问点什么」）
/// - 附件草稿：[_PendingChips]（[_AttachmentView]）
/// - 工具行：[_ComposerTools]（[_ToolChip]：联网搜索 / 深度思考 / 思考强度 / 上下文预算 / 添加附件）
/// - 输入栏：[_InputBar]（发送/停止、按住说话）
///
/// 语音：点麦克风切到「按住说话」区，pointerDown → 录音、pointerUp → 转写回填
/// （[_onFieldPointerDown] / [_onFieldPointerUp] / [_onFieldPointerCancel]）。
library;

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/chat/attachments.dart' show AttachmentRules;
import '../../core/chat/image_util.dart' show imageSizeOf;
import '../../core/providers.dart';
import '../../core/voice/voice_error.dart'
    show VoiceError, VoiceText, voiceErrorMessage;
import '../../core/voice/voice_guards.dart';
import '../../core/voice/voice_hold.dart';
import '../settings/settings_screen.dart';
import 'chat_controller.dart';
import 'session_usage_bar.dart';
import 'voice_button.dart';
import 'widgets/markdown_view.dart';

/// 聊天页（从会话列表进入；[sessionId] 必须已存在）。
///
/// ```dart
/// Navigator.of(context).push(MaterialPageRoute(
///   builder: (_) => ChatScreen(sessionId: id, initialTitle: '未命名会话'),
/// ));
/// ```
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.sessionId, this.initialTitle});

  /// 会话 id（由会话列表先 `createSession` 得到）。
  final String sessionId;

  /// 首帧占位标题（DB 读出来后以 DB 为准）。
  final String? initialTitle;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositions = ItemPositionsListener.create();

  /// 是否自动跟随最新消息（用户往上翻时暂停）。
  final ValueNotifier<bool> _autoFollow = ValueNotifier<bool>(true);

  VoiceHoldController? _hold;
  StreamSubscription<VoiceHoldState>? _holdSub;
  VoiceHoldState _holdState = const VoiceHoldState();

  /// 输入栏是否处于「按住说话」模式。
  bool _voiceMode = false;

  /// 是否正在发送（防止连点）。
  bool _sending = false;

  /// 已调度的滚动任务（合并同一帧的多次滚动请求）。
  bool _scrollScheduled = false;

  /// 消息窗口起点（-1 = 未初始化 → 只渲染最近 [_windowSize] 条）。
  ///
  /// 老会话（导入历史动辄几十条、正文几百 KB）一次性构建全部气泡会让
  /// UI 线程卡死数秒（实测 9.9s/帧并触发 ANR），所以只渲染尾部窗口，
  /// 向上翻时按「加载更早」分批把窗口前移。
  int _windowStart = -1;

  static const int _windowSize = 12;
  static const int _windowStep = 24;

  int _windowFrom(int count) {
    final from = _windowStart < 0 ? count - _windowSize : _windowStart;
    return from.clamp(0, count);
  }

  /// 消息下标 → 列表下标（窗口前移后列表第 0 项是「加载更早」）。
  int _listIndex(int from, int messageIndex) {
    final hasEarlier = from > 0;
    return messageIndex - from + (hasEarlier ? 1 : 0);
  }
  ChatController get _controller =>
      ref.read(chatControllerProvider(widget.sessionId).notifier);

  ChatUiState get _state => ref.read(chatControllerProvider(widget.sessionId));

  @override
  void initState() {
    super.initState();
    _itemPositions.itemPositions.addListener(_onPositionsChanged);
    _input.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _itemPositions.itemPositions.removeListener(_onPositionsChanged);
    _input.removeListener(_onInputChanged);
    _autoFollow.dispose();
    final hold = _hold;
    _hold = null;
    if (hold != null) unawaited(hold.dispose());
    unawaited(_holdSub?.cancel());
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // 小工具（符号表方法名）
  // -------------------------------------------------------------------------

  /// 轻提示（SnackBar）。
  void _toast(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  /// 平台简称（AppBar 副标题用）：`DeepSeek（官方）` → `DeepSeek`。
  String _providerShort(String name) {
    var text = name.trim();
    if (text.isEmpty) return '未配置';
    const brackets = <String>['（', '('];
    for (final mark in brackets) {
      final index = text.indexOf(mark);
      if (index > 0) text = text.substring(0, index);
    }
    return text.trim().isEmpty ? name : text.trim();
  }

  /// 模型短名：`deepseek-ai/DeepSeek-V3.2` → `DeepSeek-V3.2`。
  String _modelLabel(String model) {
    final text = model.trim();
    if (text.isEmpty) return '未选模型';
    final slash = text.lastIndexOf('/');
    return slash >= 0 && slash < text.length - 1
        ? text.substring(slash + 1)
        : text;
  }

  // -------------------------------------------------------------------------
  // 滚动
  // -------------------------------------------------------------------------

  void _onPositionsChanged() {
    final positions = _itemPositions.itemPositions.value;
    if (positions.isEmpty) return;
    var maxIndex = -1;
    for (final position in positions) {
      if (position.index > maxIndex) maxIndex = position.index;
    }
    final count = _state.messages.length;
    final from = _windowFrom(count);
    final listCount = count - from + (from > 0 ? 1 : 0);
    final atBottom = listCount == 0 || maxIndex >= listCount - 1;
    if (_autoFollow.value != atBottom) _autoFollow.value = atBottom;
  }

  void _onInputChanged() {
    if (mounted) setState(() {});
  }

  /// 滚到指定消息（[_scrollToIndex]）。参数是消息下标，内部换算成窗口列表下标。
  void _scrollToIndex(int index, {bool animate = true}) {
    final count = _state.messages.length;
    if (count <= 0) return;
    final target = index.clamp(0, count - 1);
    var from = _windowFrom(count);
    if (target < from) {
      // 目标在窗口之前：先把窗口前移，再在下一帧跳过去。
      setState(() => _windowStart = (target - 2).clamp(0, count));
      from = _windowFrom(count);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_itemScrollController.isAttached) return;
        _itemScrollController.jumpTo(
          index: _listIndex(from, target),
          alignment: 1,
        );
      });
      return;
    }
    if (!_itemScrollController.isAttached) return;
    final listIndex = _listIndex(from, target);
    if (animate) {
      _itemScrollController.scrollTo(
        index: listIndex,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: 1,
      );
    } else {
      _itemScrollController.jumpTo(index: listIndex, alignment: 1);
    }
  }

  /// 滚到底（[_jumpToBottom]）。
  void _jumpToBottom({bool animate = true}) {
    _autoFollow.value = true;
    final count = _state.messages.length;
    if (count == 0) return;
    _scrollToIndex(count - 1, animate: animate);
  }

  /// 「加载更早」：窗口前移一段，并保持当前首条消息在屏幕顶部的视觉位置。
  void _loadEarlier(int from) {
    final count = _state.messages.length;
    if (from <= 0) return;
    final next = (from - _windowStep).clamp(0, count);
    final anchor = from;
    setState(() => _windowStart = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_itemScrollController.isAttached) return;
      _itemScrollController.jumpTo(
        index: _listIndex(_windowFrom(count), anchor),
        alignment: 0,
      );
    });
  }

  /// 流式跟随的最小间隔：token 每一帧都到，但滚动不能每一帧都锚一次。
  static const Duration _followInterval = Duration(milliseconds: 150);

  DateTime _lastFollowAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 流式跟随：节流 + 短动画贴底。
  ///
  /// 以前每个 token 都 `jumpTo(index: 最后一条, alignment: 1)`，把最后一条消息的
  /// 底边硬钉到视口底边；而流式时这条消息的高度每一帧都在增长，等于每帧重新锚定
  /// 一次，输出区（连同下方输入栏）就会持续上下跳。现在：
  /// 1) 最多每 150ms 触发一次；
  /// 2) 用 120ms 的短动画贴底，而不是瞬时跳；
  /// 3) 用户上滑把 `_autoFollow` 置 false 后完全不跟随。
  void _scheduleFollow() {
    final now = DateTime.now();
    final wait = _followInterval - now.difference(_lastFollowAt);
    if (wait > Duration.zero) {
      if (_scrollScheduled) return;
      _scrollScheduled = true;
      Timer(wait, () {
        _scrollScheduled = false;
        if (!mounted || !_autoFollow.value) return;
        _lastFollowAt = DateTime.now();
        _followBottomSmooth();
      });
      return;
    }
    _lastFollowAt = now;
    _followBottomSmooth();
  }

  /// 平滑贴到列表底部（只被 [_scheduleFollow] 与「回到底部」按钮共用）。
  void _followBottomSmooth() {
    if (!mounted || !_itemScrollController.isAttached) return;
    final count = _state.messages.length;
    if (count <= 0) return;
    final from = _windowFrom(count);
    _itemScrollController.scrollTo(
      index: _listIndex(from, count - 1),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      alignment: 1,
    );
  }

  // -------------------------------------------------------------------------
  // 发送 / 附件
  // -------------------------------------------------------------------------

  Future<void> _send() async {
    if (_sending) return;
    final state = _state;
    final text = _input.text;
    if (text.trim().isEmpty && state.pendingAttachments.isEmpty) return;
    if (state.streaming) return;
    final before = state.messages.length;
    setState(() => _sending = true);
    _input.clear();
    _autoFollow.value = true;
    try {
      await _controller.send(text);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    if (!mounted) return;
    // 发送没成功（例如未配置平台）：把文字还给输入框，别让用户白打一遍。
    if (_state.messages.length == before && text.trim().isNotEmpty) {
      _input.text = text;
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
    }
  }

  Future<void> _stop() async {
    await _controller.stop();
    _toast('已停止');
  }

  /// 附件入口：底部菜单「图片 / 文件」。
  Future<void> _showAttachMenu() async {
    if (!_attachAllowed()) return;
    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: Icon(
                Icons.photo_library_outlined,
                color: theme.colorScheme.primary,
              ),
              title: const Text('图片'),
              subtitle: const Text('拍照，或从相册选择'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_showImageMenu());
              },
            ),
            ListTile(
              leading: Icon(
                Icons.folder_open_outlined,
                color: theme.colorScheme.primary,
              ),
              title: const Text('文件'),
              subtitle: const Text('从常用文件目录里选文档、压缩包、音频等'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_pickFiles());
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 图片入口：拍照 / 相册。
  Future<void> _showImageMenu() async {
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('拍照'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;
    if (source == ImageSource.camera) {
      await _takePhoto();
    } else {
      await _pickImages();
    }
  }

// ---- 摘录 2/3 · 原文件第 1448–1669 行 ----

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.onLongPress,
    required this.onCopy,
    required this.onOpenLink,
    required this.onToast,
    this.onPrevBranch,
    this.onNextBranch,
    this.onRegenerate,
    this.showTail = false,
  });

  final ChatMessage message;
  final VoidCallback onLongPress;
  final VoidCallback onCopy;
  final void Function(String text, String? href, String title) onOpenLink;
  final void Function(String message) onToast;
  final VoidCallback? onPrevBranch;
  final VoidCallback? onNextBranch;
  final VoidCallback? onRegenerate;
  final bool showTail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isUser = message.isUser;
    final bubbleColor = isUser
        ? scheme.primaryContainer
        : scheme.surfaceContainerLow;
    final textColor = isUser ? scheme.onPrimaryContainer : scheme.onSurface;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isUser ? 16 : 4),
      bottomRight: Radius.circular(isUser ? 4 : 16),
    );

    final body = isUser
        ? SelectableText(
            message.plainText,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: textColor,
              height: 1.5,
            ),
          )
        : _AssistantBody(message: message, onOpenLink: onOpenLink);

    final hasFooter =
        message.isAssistant &&
        (message.plainText.isNotEmpty || message.streaming || message.error);
    final hasBranches = message.hasBranches;

    return Padding(
      padding: EdgeInsets.only(top: 6, bottom: showTail ? 6 : 2),
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: isUser
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (!isUser)
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 6),
                  child: CircleAvatar(
                    radius: 12,
                    backgroundColor: scheme.primaryContainer,
                    child: Icon(
                      Icons.auto_awesome,
                      size: 13,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              Flexible(
                child: GestureDetector(
                  onLongPress: onLongPress,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * 0.86,
                    ),
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: radius,
                      border: message.error
                          ? Border.all(
                              color: scheme.error.withValues(alpha: 0.6),
                            )
                          : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (!isUser && message.thinking.trim().isNotEmpty)
                          _ThinkingPanel(
                            thinking: message.thinking,
                            seconds: message.thinkingSeconds,
                            streaming: message.thinkingNow,
                          ),
                        if (!isUser &&
                            message.streaming &&
                            message.text.trim().isEmpty &&
                            message.thinking.trim().isEmpty)
                          _StreamStatus(searching: message.searchingNow),
                        if (message.text.trim().isNotEmpty ||
                            (!isUser && message.blocks.isNotEmpty))
                          DefaultTextStyle.merge(
                            style: TextStyle(color: textColor),
                            child: body,
                          ),
                        if (message.attachments.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(
                              top: message.text.trim().isEmpty ? 2 : 8,
                            ),
                            child: _MessageAttachments(
                              attachments: message.attachments,
                              onToast: onToast,
                            ),
                          ),
                        if (message.searchSources.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: _SearchSourcesView(
                              sources: message.searchSources,
                              onOpen: (String url) => onOpenLink(url, url, ''),
                            ),
                          ),
                        if (message.error)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(
                                  Icons.error_outline,
                                  size: 13,
                                  color: scheme.error,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '这条回答中断了',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.error,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (message.streaming && message.text.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.6,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (hasFooter)
            Padding(
              padding: const EdgeInsets.only(left: 30, top: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (message.plainText.isNotEmpty)
                    SpeakButton(
                      text: message.plainText,
                      onToast: onToast,
                      iconSize: 16,
                    ),
                  IconButton(
                    onPressed: onCopy,
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                    padding: const EdgeInsets.all(2),
                    tooltip: '复制',
                    icon: Icon(
                      Icons.copy_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (onRegenerate != null)
                    _RegenerateButton(
                      onPressed: message.streaming ? null : onRegenerate,
                    ),
                  if (hasBranches)
                    _BranchSwitcher(
                      branchIndex: message.branchIndex,
                      branchCount: message.branchCount,
                      onPrev: onPrevBranch,
                      onNext: onNextBranch,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---- 摘录 3/3 · 原文件第 2359–2526 行 ----

/// 工具行（[_ComposerTools]）：联网搜索 / 深度思考 / 思考强度 / 上下文预算 / 添加附件。
class _ComposerTools extends StatelessWidget {
  const _ComposerTools({
    required this.searchEnabled,
    required this.thinkingEnabled,
    required this.thinkingLevel,
    required this.contextKeepRounds,
    required this.supportsSearch,
    required this.supportsThinking,
    required this.canAttach,
    required this.onToggleSearch,
    required this.onToggleThinking,
    required this.onEditThinkingLevel,
    required this.onEditContextBudget,
    required this.onPickFiles,
  });

  final bool searchEnabled;
  final bool thinkingEnabled;
  final ThinkingLevel thinkingLevel;
  final int contextKeepRounds;
  final bool supportsSearch;
  final bool supportsThinking;
  final bool canAttach;
  final VoidCallback onToggleSearch;
  final VoidCallback onToggleThinking;
  final VoidCallback onEditThinkingLevel;
  final VoidCallback onEditContextBudget;
  final VoidCallback onPickFiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: <Widget>[
          _ToolChip(
            label: supportsSearch
                ? (searchEnabled ? '联网搜索：开' : '联网搜索：关')
                : ' 不支持联网搜索',
            icon: Icons.travel_explore_rounded,
            selected: supportsSearch && searchEnabled,
            disabled: !supportsSearch,
            onTap: onToggleSearch,
            tooltip: supportsSearch ? '支持联网搜索（DeepSeek 扩展）' : ' 不支持联网搜索',
          ),
          _ToolChip(
            label: supportsThinking
                ? (thinkingEnabled
                      ? '深度思考：开（${thinkingLevel.label}）'
                      : '深度思考：关')
                : ' 不支持深度思考',
            icon: Icons.psychology_outlined,
            selected: supportsThinking && thinkingEnabled,
            disabled: !supportsThinking,
            onTap: onToggleThinking,
            onLongPress: supportsThinking ? onEditThinkingLevel : null,
            tooltip: supportsThinking
                ? '支持深度思考（长按选择思考强度）'
                : ' 不支持深度思考',
          ),
          _ToolChip(
            label: contextKeepRounds <= 0
                ? '上下文：不限制'
                : '上下文：最近 $contextKeepRounds 轮',
            icon: Icons.straighten_rounded,
            selected: false,
            onTap: onEditContextBudget,
            tooltip: '超出窗口的部分压成 ≤600 字摘要',
          ),
          _ToolChip(
            label: '添加附件',
            icon: canAttach
                ? Icons.attach_file_rounded
                : Icons.attach_file_rounded,
            selected: false,
            disabled: false,
            onTap: onPickFiles,
            tooltip: canAttach
                ? '添加附件'
                : ' 暂不支持附件（只有 DeepSeek 的 Files API 支持），请改成发文字',
            tint: canAttach
                ? null
                : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }
}

/// 单个工具 chip（[_ToolChip]）。
class _ToolChip extends StatelessWidget {
  const _ToolChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.disabled = false,
    this.tooltip,
    this.tint,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool disabled;
  final String? tooltip;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground =
        tint ??
        (disabled
            ? scheme.onSurfaceVariant.withValues(alpha: 0.5)
            : selected
            ? scheme.onPrimaryContainer
            : scheme.onSurfaceVariant);
    final background = selected
        ? scheme.primaryContainer
        : scheme.surfaceContainerLow;
    final chip = Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: disabled ? null : onTap,
        onLongPress: disabled ? null : onLongPress,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.4)
                  : scheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 13, color: foreground),
              const SizedBox(width: 4),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: foreground,
                  fontWeight: selected ? FontWeight.w600 : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final text = tooltip;
    return text == null ? chip : Tooltip(message: text, child: chip);
  }
}

// ==========================================================================
// 摘录结束。
// ==========================================================================
