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
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/chat/attachments.dart' show AttachmentRules;
import '../../core/chat/gallery_picker.dart';
import '../../core/chat/image_util.dart' show imageSizeOf;
import '../../core/providers.dart';
import '../../core/theme.dart' show KeepsakeSchemeX;
import '../../core/usage/usage.dart' show occupancyPercent;
import '../../core/usage/usage_store.dart'
    show SessionUsage, usageStoreProvider;
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

  /// 附件能力/配置校验：未配置或平台不支持时给出明确提示并返回 false。
  bool _attachAllowed() {
    final state = _state;
    final book = ref.read(providerBookProvider);
    final provider = book.byId(state.providerId) ?? book.current;
    if (book.providers.isEmpty) {
      _toast('还没有配置 AI 平台：去「设置 → AI 平台」添加 DeepSeek（官方）并填 API Key');
      return false;
    }
    if (provider == null) {
      _toast('先选一个 AI 平台：点顶部平台名，或去「设置 → AI 平台」选一个');
      return false;
    }
    if (!provider.hasApiKey) {
      _toast('还没填 API Key：去「设置 → AI 平台」补上再试');
      return false;
    }
    if (!state.canAttach && !provider.supportsFiles) {
      _toast(
        kAttachUnsupportedMessage.trim().isEmpty
            ? ' 暂不支持附件（只有 DeepSeek 的 Files API 支持），请改成发文字'
            : kAttachUnsupportedMessage,
      );
      return false;
    }
    return true;
  }

  Future<void> _takePhoto() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (status.isPermanentlyDenied) {
        // MIUI/ColorOS 上「拒绝两次」= 永久拒绝，再点也不会弹系统框（M4）：
        // 给「去设置」和「改为相册」两个出口，而不是只 toast 一句。
        await _showCameraBlockedDialog();
      } else {
        _toast('没有相机权限：再点一次可以重新申请，或在系统设置里允许「相机」');
      }
      return;
    }
    try {
      final XFile? photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 92,
      );
      if (photo == null) {
        // 用户取消、或被系统（省电/权限回收）打断时返回 null：提示改用相册（M4）。
        _toast('没有拿到照片，可以改用「从相册选择」');
        return;
      }
      await _addXFile(photo);
    } catch (error) {
      _toast('拍照失败：$error');
    }
  }

  /// 相机权限被永久拒绝时的弹窗：去系统设置 / 改用相册。
  Future<void> _showCameraBlockedDialog() async {
    final bool? goSettings = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('没有相机权限'),
        content: const Text('系统已经不再弹授权框了。去设置里允许「相机」，或者直接从相册选择图片。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('改为相册'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('去设置'),
          ),
        ],
      ),
    );
    if (goSettings == null || !mounted) return;
    if (goSettings) {
      final opened = await openAppSettings();
      if (!opened && mounted) {
        _toast('打不开系统设置：手动到 设置 > 应用 > Keepsake > 权限 里允许相机');
      }
      return;
    }
    await _pickImages();
  }

  /// 直接用系统图库（原生 `keepsake/gallery` 通道）。
  ///
  /// 不走 image_picker：华为等没有 AOSP Photo Picker 的设备上，它会回退到
  /// 文件管理器（DocumentsUI 的「最近」）。原生侧的回退顺序是
  /// `ACTION_PICK_IMAGES` → `ACTION_GET_CONTENT`（可多选）→ `ACTION_PICK`，
  /// 打开的都是「图库」界面；返回的已经是复制到缓存的本地路径。
  Future<void> _pickImages() async {
    try {
      final List<String> paths = await GalleryPicker.pickImages();
      for (final String path in paths) {
        try {
          await _addXFile(XFile(path));
        } catch (error) {
          // 单张失败不连坐其他张：明确提示，不静默丢（M2）。
          _toast('有一张图片读不出来：$error');
        }
      }
    } on PlatformException catch (error) {
      _toast('打开图库失败：${error.message ?? error.code}');
    } catch (error) {
      // 原生返回的本地路径可能已失效（缓存被系统清掉），XFile.length() 会抛
      // FileSystemException —— 这里必须兜住，否则就是未处理异常（M2）。
      _toast('读取图片失败：$error');
    }
  }

  Future<void> _addXFile(XFile file) async {
    final mime = (file.mimeType ?? '').trim().isEmpty
        ? AttachmentRules.mimeOf(file.name)
        : file.mimeType!;
    final length = await file.length();
    int? width;
    int? height;
    if (mime.startsWith('image/')) {
      try {
        final size = await imageSizeOf(file.path);
        if (size.isValid) {
          width = size.width;
          height = size.height;
        }
      } catch (_) {
        // 读不出尺寸不影响上传。
      }
    }
    final error = await _controller.addAttachment(
      file.path,
      fileName: file.name,
      fileSize: length,
      mime: mime,
      width: width,
      height: height,
    );
    if (error != null) _toast(error);
  }

  /// 选择文件（DocumentsUI，常用目录里的文档/压缩包/音频等）。
  Future<void> _pickFiles() async {
    if (!_attachAllowed()) return;
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: '选择文件',
        type: FileType.any,
      );
      if (files.isEmpty) return;
      for (final file in files) {
        final path = file.path;
        if (path == null || path.isEmpty) {
          _toast('无法读取文件：${file.name}');
          continue;
        }
        int? width;
        int? height;
        final mime = AttachmentRules.mimeOf(file.name);
        if (mime.startsWith('image/')) {
          try {
            final size = await imageSizeOf(path);
            if (size.isValid) {
              width = size.width;
              height = size.height;
            }
          } catch (_) {
            // 读不出尺寸不影响上传。
          }
        }
        final length = await file.length();
        final error = await _controller.addAttachment(
          path,
          fileName: file.name,
          fileSize: length ?? 0,
          mime: mime,
          width: width,
          height: height,
        );
        if (error != null) {
          _toast(error);
          break;
        }
      }
    } catch (error) {
      _toast('选择文件失败：$error');
    }
  }

  // -------------------------------------------------------------------------
  // 按住说话（VoiceHoldController）
  // -------------------------------------------------------------------------

  VoiceHoldController _ensureHold() => _hold ??= _createHold();

  VoiceHoldController _createHold() {
    final controller = VoiceHoldController(
      capabilities: () =>
          _voiceCapabilities() ?? VoiceCapabilities.forProvider(null),
      onText: _insertVoiceText,
      onError: (VoiceError error) => _toast(voiceErrorMessage(error)),
    );
    _holdSub = controller.stateStream.listen((VoiceHoldState state) {
      if (!mounted) return;
      setState(() => _holdState = state);
    });
    return controller;
  }

  /// 当前平台语音能力（未配置返回 null）。
  VoiceCapabilities? _voiceCapabilities() {
    final book = ref.read(providerBookProvider);
    final settings = ref.read(settingsProvider);
    final config = ProviderConfigResolver(
      book: book,
      settings: settings,
    ).resolve();
    if (config == null) return null;
    return VoiceCapabilities.fromProviderConfig(config);
  }

  /// 转写结果回填输入框。
  void _insertVoiceText(String text) {
    if (!mounted) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final current = _input.text;
    final selection = _input.selection;
    if (selection.isValid && selection.start >= 0) {
      final before = current.substring(0, selection.start);
      final after = current.substring(selection.end.clamp(0, current.length));
      _input.text = '$before$trimmed$after';
      _input.selection = TextSelection.collapsed(
        offset: before.length + trimmed.length,
      );
    } else {
      _input.text = current.isEmpty ? trimmed : '$current$trimmed';
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
    }
    setState(() {});
  }

  /// 语音/键盘模式切换。
  void _voice() {
    final next = !_voiceMode;
    setState(() => _voiceMode = next);
    if (next) {
      _inputFocus.unfocus();
    } else {
      _inputFocus.requestFocus();
    }
  }

  /// 按下「按住说话」区（[_onFieldPointerDown]）。
  Future<void> _onFieldPointerDown(PointerDownEvent event) async {
    if (!voicePluginsAvailable || !voiceRecordingAvailable) {
      _toast(VoiceText.unsupportedRecording);
      return;
    }
    final caps = _voiceCapabilities();
    if (caps == null) {
      _toast(VoiceText.notConfigured);
      return;
    }
    if (!voiceSupportsAsr(caps)) {
      _toast(VoiceText.asrUnsupported);
      return;
    }
    await _ensureHold().start();
  }

  /// 松手（[_onFieldPointerUp]）：结束录音并转写（不阻塞手势）。
  void _onFieldPointerUp(PointerUpEvent event) {
    if (_holdState.phase != VoicePhase.recording) return;
    unawaited(_ensureHold().stop());
  }

  /// 手势取消（[_onFieldPointerCancel]）。
  void _onFieldPointerCancel(PointerCancelEvent event) {
    unawaited(_ensureHold().cancel());
  }

  // -------------------------------------------------------------------------
  // 设置类弹窗
  // -------------------------------------------------------------------------

  /// 上下文预算编辑（[_editContextBudget]）。
  ///
  /// 只改**当前会话**（`sessions.context_keep_rounds`），不写全局默认值；
  /// 设置页里的「上下文预算」才是所有会话的默认值。
  Future<void> _editContextBudget() async {
    final current = _state.contextKeepRounds;
    final controller = TextEditingController(
      text: current <= 0 ? '' : '$current',
    );
    var unlimited = current <= 0;
    final saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: const Text('上下文预算（当前会话）'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '超出窗口的部分压成 ≤600 字摘要（旧历史压缩成摘要）',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('不限制（全部历史）'),
                    value: unlimited,
                    onChanged: (bool? value) =>
                        setDialogState(() => unlimited = value ?? false),
                  ),
                  if (!unlimited)
                    TextField(
                      controller: controller,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        labelText: '保留最近 N 轮',
                        helperText: '只影响当前会话，不改设置里的默认值',
                      ),
                    ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
    if (saved != true) {
      controller.dispose();
      return;
    }
    final rounds = unlimited
        ? 0
        : (int.tryParse(controller.text.trim()) ?? current);
    controller.dispose();
    await _controller.setContextKeepRounds(rounds);
    _toast(rounds <= 0 ? '上下文：不限制' : '上下文：最近 $rounds 轮');
  }

  /// 思考强度选择（[_editThinkingLevel]）。
  ///
  /// 只改**当前会话**（`sessions.thinking_level` + `thinking_enabled`），
  /// 不写全局默认值；设置页里的「思考强度」才是所有会话的默认值。
  Future<void> _editThinkingLevel() async {
    final currentLevel = _state.thinkingLevel;
    final picked = await showDialog<ThinkingLevel>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('思考强度（当前会话）'),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final level in ThinkingLevel.values)
                ListTile(
                  leading: Icon(
                    currentLevel == level
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: currentLevel == level
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  title: Text(level.label),
                  subtitle: Text(level.description),
                  onTap: () => Navigator.of(dialogContext).pop(level),
                ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
    if (picked == null) return;
    await _controller.setThinkingLevel(picked);
    _toast('深度思考：开（${picked.label}）');
  }

  /// 平台/模型选择弹窗。
  Future<void> _pickModel() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return _ModelSheet(sessionId: widget.sessionId);
      },
    );
  }

  // -------------------------------------------------------------------------
  // 消息操作
  // -------------------------------------------------------------------------

  Future<void> _copyMessage(ChatMessage message) async {
    final text = message.plainText;
    if (text.isEmpty) {
      _toast('没有可复制的内容');
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    _toast('已复制');
  }

  /// 长按菜单：复制 / 编辑 / 删除 / 重新生成。
  Future<void> _showMessageMenu(ChatMessage message) async {
    final isUser = message.isUser;
    final isAssistant = message.isAssistant;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('复制'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_copyMessage(message));
                },
              ),
              if (isUser)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('编辑'),
                  subtitle: const Text('以这条回复的问题重新生成一版，旧回答会留在分支里'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(_editMessage(message));
                  },
                ),
              if (isAssistant)
                ListTile(
                  leading: const Icon(Icons.refresh_rounded),
                  title: const Text('重新生成'),
                  subtitle: const Text('以这条回复的问题重新生成一版，旧回答会留在分支里'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(_controller.regenerate(message.id));
                  },
                ),
              if (message.hasBranches)
                ListTile(
                  leading: const Icon(Icons.alt_route_rounded),
                  title: const Text('切换分支'),
                  subtitle: Text(
                    '第 ${message.branchIndex} / ${message.branchCount} 个分支',
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(_showBranchPicker(message));
                  },
                ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  '删除',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_confirmDeleteMessage(message));
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editMessage(ChatMessage message) async {
    final controller = TextEditingController(text: message.plainText);
    final next = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('编辑'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 8,
            decoration: const InputDecoration(hintText: '发消息…'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('确认'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (next == null || next.isEmpty) return;
    await _controller.edit(message.id, next);
  }

  Future<void> _confirmDeleteMessage(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('删除这条消息？'),
          content: const Text('这条消息及其之后的所有分支都会被删除，无法恢复。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await _controller.deleteMessage(message.id);
  }

  /// 分支选择弹窗（上一个/下一个分支逐步切换）。
  Future<void> _showBranchPicker(ChatMessage message) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('切换分支'),
          content: Text(
            '当前第 ${message.branchIndex} / ${message.branchCount} 个分支。',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: message.canPrevBranch
                  ? () => Navigator.of(dialogContext).pop(-1)
                  : null,
              child: const Text('上一个分支'),
            ),
            FilledButton(
              onPressed: message.canNextBranch
                  ? () => Navigator.of(dialogContext).pop(1)
                  : null,
              child: const Text('下一个分支'),
            ),
          ],
        );
      },
    );
    if (picked == null) return;
    await _controller.switchBranch(message.id, picked);
    // 切换后滚到该消息所在位置（分支切换可能让链变短）。
    _scheduleFollow();
  }

  /// 打开搜索结果链接。
  Future<void> _openLink(String? href) async {
    final raw = (href ?? '').trim();
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      _toast('无法打开链接：$raw');
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _toast('无法打开链接：$raw');
    } catch (error) {
      _toast('无法打开链接：$raw');
    }
  }

  // -------------------------------------------------------------------------
  // 构建
  // -------------------------------------------------------------------------

  /// 单条消息 → 气泡（符号表 `_buildBubble`）。
  Widget _buildBubble(
    BuildContext context,
    ChatUiState state,
    ChatMessage message,
    int index,
  ) {
    final isLast = index == state.messages.length - 1;
    return _MessageBubble(
      message: message,
      onLongPress: () => unawaited(_showMessageMenu(message)),
      onCopy: () => unawaited(_copyMessage(message)),
      onOpenLink: (String text, String? href, String title) =>
          unawaited(_openLink(href)),
      onPrevBranch: message.canPrevBranch
          ? () => unawaited(_controller.switchBranch(message.id, -1))
          : null,
      onNextBranch: message.canNextBranch
          ? () => unawaited(_controller.switchBranch(message.id, 1))
          : null,
      onRegenerate: message.isAssistant
          ? () => unawaited(_controller.regenerate(message.id))
          : null,
      onToast: _toast,
      showTail: isLast,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatControllerProvider(widget.sessionId));
    final book = ref.watch(providerBookProvider);
    final theme = Theme.of(context);

    // 流式/新消息到达时自动跟随底部。
    ref.listen<ChatUiState>(chatControllerProvider(widget.sessionId), (
      ChatUiState? previous,
      ChatUiState next,
    ) {
      final grew = next.messages.length > (previous?.messages.length ?? 0);
      if (grew || next.streaming) _scheduleFollow();
    });

    final title = state.title.trim().isEmpty
        ? (widget.initialTitle?.trim().isNotEmpty == true
              ? widget.initialTitle!.trim()
              : '未命名会话')
        : state.title.trim();

    final provider = book.byId(state.providerId) ?? book.current;
    final supportsThinking = provider?.supportsThinking ?? false;
    final supportsSearch = provider?.supportsSearch ?? false;
    final last = state.lastMessage;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            _ModelPick(
              providerShort: _providerShort(state.providerName),
              modelLabel: _modelLabel(state.model),
              onTap: () => unawaited(_pickModel()),
            ),
          ],
        ),
        actions: <Widget>[
          if (state.branchCount > 1 && last != null)
            _BranchSwitcher(
              branchIndex: last.branchIndex,
              branchCount: last.branchCount,
              onPrev: last.canPrevBranch
                  ? () => unawaited(_controller.switchBranch(last.id, -1))
                  : null,
              onNext: last.canNextBranch
                  ? () => unawaited(_controller.switchBranch(last.id, 1))
                  : null,
            ),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (String value) {
              if (value == 'settings') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsScreen(),
                  ),
                );
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(value: 'settings', child: Text('设置')),
            ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          // 用量条在 AppBar 下方、消息区之上、左对齐；设计建议「占用 < 80%
          // 时不出现」，只在接近上下文上限或出错时才占一条位置。
          _SessionUsageGate(
            sessionId: state.sessionId,
            hasError: (state.error ?? '').trim().isNotEmpty,
          ),
          _ErrorBanner(
            message: state.error,
            onRetry: () => unawaited(_controller.retry()),
            onDismiss: _controller.dismissError,
          ),
          if (state.uploading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: Stack(
              children: <Widget>[
                Positioned.fill(child: _buildMessageList(state)),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _autoFollow,
                    builder:
                        (BuildContext context, bool autoFollow, Widget? child) {
                          if (autoFollow || state.messages.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return _ArrowButton(
                            icon: Icons.keyboard_arrow_down_rounded,
                            tooltip: '滚动到底',
                            onPressed: _jumpToBottom,
                          );
                        },
                  ),
                ),
              ],
            ),
          ),
          _PendingChips(
            attachments: state.pendingAttachments,
            uploading: state.uploading,
            onRemove: _controller.removeAttachment,
          ),
          _ComposerTools(
            searchEnabled: state.searchEnabled,
            // 芯片显示**当前生效值**（会话覆盖 ?? 全局默认），不是全局默认值本身。
            thinkingEnabled: state.thinkingEnabled,
            thinkingLevel: state.thinkingLevel,
            contextKeepRounds: state.contextKeepRounds,
            supportsSearch: supportsSearch,
            supportsThinking: supportsThinking,
            onToggleSearch: () =>
                unawaited(_controller.setSearchEnabled(!state.searchEnabled)),
            onToggleThinking: () => unawaited(
              _controller.setThinkingEnabled(!state.thinkingEnabled),
            ),
            onEditThinkingLevel: () => unawaited(_editThinkingLevel()),
            onEditContextBudget: () => unawaited(_editContextBudget()),
          ),
          _InputBar(
            controller: _input,
            focusNode: _inputFocus,
            streaming: state.streaming,
            sending: _sending,
            canSend:
                _input.text.trim().isNotEmpty ||
                state.pendingAttachments.isNotEmpty,
            canAttach: state.canAttach,
            voiceMode: _voiceMode,
            holdState: _holdState,
            onSend: () => unawaited(_send()),
            onStop: () => unawaited(_stop()),
            onPickFiles: () => unawaited(_showAttachMenu()),
            onVoiceToggle: _voice,
            onPointerDown: (PointerDownEvent event) =>
                unawaited(_onFieldPointerDown(event)),
            onPointerUp: _onFieldPointerUp,
            onPointerCancel: _onFieldPointerCancel,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(ChatUiState state) {
    if (state.loading && state.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.messages.isEmpty) {
      return _EmptyChat(
        // 设计稿 B1：建议项只是「预填」，点了不直接发出去。
        onSuggestion: (String text) {
          _input.text = text;
          _input.selection = TextSelection.collapsed(
            offset: _input.text.length,
          );
          _inputFocus.requestFocus();
        },
      );
    }
    final from = _windowFrom(state.messages.length);
    final hasEarlier = from > 0;
    final listCount = state.messages.length - from + (hasEarlier ? 1 : 0);
    // M6：大屏/折叠屏上整条消息流居中并限宽 720，
    // 不让内容从屏幕左缘一直铺到右缘（中文一行 40 字左右的舒适阅读宽度）。
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ScrollablePositionedList.builder(
          itemCount: listCount,
          itemScrollController: _itemScrollController,
          itemPositionsListener: _itemPositions,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          itemBuilder: (BuildContext context, int index) {
            if (hasEarlier && index == 0) {
              return _EarlierMessagesButton(onTap: () => _loadEarlier(from));
            }
            final messageIndex = from + index - (hasEarlier ? 1 : 0);
            final message = state.messages[messageIndex];
            return KeyedSubtree(
              key: ValueKey<String>(message.id),
              child: _buildBubble(context, state, message, messageIndex),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 私有 widget（名字照 `dart-symbols.md`）
// ---------------------------------------------------------------------------

/// AppBar 上的「平台 · 模型」选择入口。
class _ModelPick extends StatelessWidget {
  const _ModelPick({
    required this.providerShort,
    required this.modelLabel,
    required this.onTap,
  });

  final String providerShort;
  final String modelLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              child: Text(
                '$providerShort · $modelLabel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                ),
              ),
            ),
            Icon(Icons.expand_more_rounded, size: 14, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}

/// 平台/模型选择面板（底部弹窗内容）。
class _ModelSheet extends ConsumerStatefulWidget {
  const _ModelSheet({required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<_ModelSheet> createState() => _ModelSheetState();
}

class _ModelSheetState extends ConsumerState<_ModelSheet> {
  late final TextEditingController _customModel;

  @override
  void initState() {
    super.initState();
    _customModel = TextEditingController();
  }

  @override
  void dispose() {
    _customModel.dispose();
    super.dispose();
  }

  ChatController get _controller =>
      ref.read(chatControllerProvider(widget.sessionId).notifier);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = ref.watch(providerBookProvider);
    final state = ref.watch(chatControllerProvider(widget.sessionId));
    final current = book.byId(state.providerId) ?? book.current;
    final modelsAsync = current == null
        ? null
        : ref.watch(providerModelsProvider(current.id));
    final candidates = <String>{
      if (current != null) ...current.models,
      if (current != null && current.model.trim().isNotEmpty) current.model,
      ...?modelsAsync?.asData?.value.map((ProviderModel model) => model.id),
    }.where((String id) => id.trim().isNotEmpty).toList(growable: false);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: <Widget>[
            Text('平台与模型（当前会话）', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (book.providers.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '还没有配置 AI 平台，去设置里添加一个',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final provider in book.providers)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  provider.id == current?.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: provider.id == current?.id
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                title: Text(provider.name),
                subtitle: Text(
                  provider.isReady
                      ? '${provider.protocolLabel} · ${provider.model.isEmpty ? '未选模型' : provider.model}'
                      : '还没填 API Key',
                ),
                onTap: () => unawaited(_controller.setProvider(provider.id)),
              ),
            const Divider(height: 20),
            Text('模型', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              '填好后会从 /models 拉真实列表，聊天页可再切换',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (modelsAsync != null)
              modelsAsync.when(
                data: (List<ProviderModel> models) {
                  if (models.isEmpty && candidates.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('这个平台没返回模型列表，手动填一个吧'),
                    );
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (final model in candidates)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            model == state.model
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: model == state.model
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          title: Text(
                            model,
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                          onTap: () async {
                            await _controller.setModel(model);
                            if (context.mounted) Navigator.of(context).pop();
                          },
                        ),
                    ],
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                error: (Object error, StackTrace stack) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '$error',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _customModel,
              decoration: InputDecoration(
                labelText: '默认模型',
                hintText: state.model.isEmpty ? '先填一个模型名' : state.model,
              ),
              style: const TextStyle(fontFamily: 'monospace'),
              onSubmitted: (String value) async {
                if (value.trim().isEmpty) return;
                await _controller.setModel(value.trim());
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () async {
                final value = _customModel.text.trim();
                if (value.isEmpty) {
                  Navigator.of(context).pop();
                  return;
                }
                await _controller.setModel(value);
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 气泡：角色、markdown 正文、思考过程、搜索来源、附件、操作行。
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

    final showStreamStatus =
        !isUser &&
        message.streaming &&
        message.text.trim().isEmpty &&
        message.thinking.trim().isEmpty;
    final showBody =
        message.text.trim().isNotEmpty ||
        (!isUser && message.blocks.isNotEmpty);
    final hasFooter =
        message.isAssistant &&
        (message.plainText.isNotEmpty || message.streaming || message.error);
    final hasBranches = message.hasBranches;

    // 气泡内 padding 归零（设计稿 MessageBubbleShell）：横向 10 的内边距交给
    // 每个子项自己带，代码块才能「通栏出血」贴到气泡内缘（Container 不吃负 margin）。
    final bubble = GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: radius,
          border: message.error
              ? Border.all(color: scheme.error.withValues(alpha: 0.6))
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (!isUser && message.thinking.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                child: _ThinkingPanel(
                  thinking: message.thinking,
                  seconds: message.thinkingSeconds,
                  streaming: message.thinkingNow,
                ),
              ),
            if (showStreamStatus)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                child: _StreamStatus(searching: message.searchingNow),
              ),
            if (showBody)
              DefaultTextStyle.merge(
                style: TextStyle(color: textColor),
                child: isUser
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                        child: SelectableText(
                          message.plainText,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: textColor,
                            height: 1.6,
                          ),
                        ),
                      )
                    : _AssistantBody(message: message, onOpenLink: onOpenLink),
              ),
            if (message.attachments.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  10,
                  showBody || showStreamStatus ? 8 : 10,
                  10,
                  0,
                ),
                child: _MessageAttachments(
                  attachments: message.attachments,
                  onToast: onToast,
                ),
              ),
            if (message.searchSources.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: _SearchSourcesView(
                  sources: message.searchSources,
                  onOpen: (String url) => onOpenLink(url, url, ''),
                ),
              ),
            if (message.error)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.error_outline, size: 13, color: scheme.error),
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
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                child: SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: scheme.primary,
                  ),
                ),
              ),
            // 底部统一留白（正文块的段落只带顶部间距，避免上下叠成双倍）。
            const SizedBox(height: 10),
          ],
        ),
      ),
    );

    // 助手气泡外侧保留 ✦ 头像（设计稿 B2：头像在气泡外，气泡内不带名字）。
    final bubbleColumn = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: <Widget>[
          ConstrainedBox(
            constraints: BoxConstraints(
              // 气泡最大宽 = min(86% 屏宽, 520)（M6）：窄屏仍是 86%，
              // 折叠屏/平板展开态封到 520，避免一行排下 60+ 个汉字。
              maxWidth: math.min(MediaQuery.sizeOf(context).width * 0.86, 520),
              minWidth: showStreamStatus ? 144 : 0,
            ),
            child: bubble,
          ),
          if (hasFooter)
            Padding(
              // 操作行左缘与气泡对齐；单键 44×44、间距 0（设计稿组件 §3）。
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (message.plainText.isNotEmpty)
                    SpeakButton(
                      text: message.plainText,
                      onToast: onToast,
                      iconSize: 18,
                    ),
                  IconButton(
                    onPressed: onCopy,
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
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
    );

    return Padding(
      padding: EdgeInsets.only(top: 6, bottom: showTail ? 6 : 2),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!isUser)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 2),
              child: _AssistantAvatar(),
            ),
          Flexible(child: bubbleColumn),
        ],
      ),
    );
  }
}

/// 助手头像：气泡外侧的 ✦ 圆标（设计稿 B2：头像在气泡外，气泡内不带名字）。
class _AssistantAvatar extends StatelessWidget {
  const _AssistantAvatar();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.auto_awesome, size: 15, color: scheme.primary),
    );
  }
}

/// assistant 正文：markdown 渲染（代码块/公式/mermaid）。
///
/// 超长正文（老会话/导入历史常见）先按纯文本渲染——Markdown 全量解析在
/// 27k 字级别会让一帧耗时数秒，直接触发 ANR（实测 9.9s/帧）。
/// 用户点「展开完整排版」再走 Markdown。
class _AssistantBody extends StatefulWidget {
  const _AssistantBody({required this.message, required this.onOpenLink});

  final ChatMessage message;
  final void Function(String text, String? href, String title) onOpenLink;

  /// 超过这个字数先纯文本渲染。
  static const int plainTextThreshold = 12000;

  @override
  State<_AssistantBody> createState() => _AssistantBodyState();
}

class _AssistantBodyState extends State<_AssistantBody> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final text = widget.message.text.trim();
    if (text.isEmpty) {
      // 只有附件/搜索结果的回答。
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    if (!_expanded && text.length > _AssistantBody.plainTextThreshold) {
      // 气泡内 padding 归零后，这里自己补回 10 的横向内边距。
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SelectableText(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: () => setState(() => _expanded = true),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.expand_more_rounded,
                      size: 15,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '展开完整排版（${(text.length / 1000).toStringAsFixed(1)}k 字）',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    return KeepsakeMarkdown(
      data: text,
      selectable: true,
      onTapLink: widget.onOpenLink,
    );
  }
}

/// 窗口列表顶部的「加载更早消息」。
class _EarlierMessagesButton extends StatelessWidget {
  const _EarlierMessagesButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: TextButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.expand_less_rounded, size: 16),
          label: Text('加载更早消息', style: theme.textTheme.labelMedium),
        ),
      ),
    );
  }
}

/// 可折叠的思考过程（「思考过程」+ 耗时）。
class _ThinkingPanel extends StatefulWidget {
  const _ThinkingPanel({
    required this.thinking,
    this.seconds,
    this.streaming = false,
  });

  final String thinking;
  final double? seconds;
  final bool streaming;

  @override
  State<_ThinkingPanel> createState() => _ThinkingPanelState();
}

class _ThinkingPanelState extends State<_ThinkingPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final seconds = widget.seconds ?? 0;
    final label = widget.streaming
        ? '思考过程（进行中）'
        : seconds > 0
        ? '思考过程（${seconds.toStringAsFixed(1)}s）'
        : '思考过程';
    // 设计稿 B4：`surfaceContainerHighest @ 50%` 底 + 圆角 8；
    // 折叠条 44 高（左 chevron、右「展开 / 收起」），展开体左侧 2px primary 竖线。
    final background = scheme.surfaceContainerHighest.withValues(alpha: 0.5);
    final expanded = _expanded;
    final radius = BorderRadius.vertical(
      top: const Radius.circular(8),
      bottom: Radius.circular(expanded ? 0 : 8),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Material(
          color: background,
          borderRadius: radius,
          child: InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: radius,
            child: ConstrainedBox(
              // M5：折叠条用 minHeight 而不是固定 44 —— 大字体下文字变高时
              // 容器跟着长，不会挤出黄黑溢出条。
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: <Widget>[
                    Icon(
                      expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (widget.streaming)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(strokeWidth: 1.4),
                        ),
                      ),
                    Text(
                      expanded ? '收起' : '展开',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (expanded)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: background,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(8),
              ),
              border: Border(left: BorderSide(color: scheme.primary, width: 2)),
            ),
            child: SelectableText(
              widget.thinking.trim(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
      ],
    );
  }
}

/// 「正在思考…」/「正在联网搜索」状态行。
class _StreamStatus extends StatelessWidget {
  const _StreamStatus({this.searching = false});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 1.6),
        ),
        const SizedBox(width: 8),
        Text(
          searching ? '正在联网搜索' : '正在思考…',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 联网搜索来源列表。
class _SearchSourcesView extends StatelessWidget {
  const _SearchSourcesView({required this.sources, required this.onOpen});

  final List<ChatSearchSource> sources;
  final void Function(String url) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // 官方样式：正文底下只留一个「N 个网页」小胶囊，点开再看完整列表。
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: () => _showSourcesSheet(context),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.travel_explore_rounded,
                size: 14,
                color: scheme.primary,
              ),
              const SizedBox(width: 5),
              Text(
                '${sources.length} 个网页',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 点开胶囊：从底部弹出完整来源列表。
  void _showSourcesSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final scheme = theme.colorScheme;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.travel_explore_rounded,
                        size: 16,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '搜索结果（${sources.length}）',
                        style: theme.textTheme.titleSmall,
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: sources.length,
                    itemBuilder: (_, index) {
                      final source = sources[index];
                      final snippet = (source.snippet ?? '').trim();
                      return ListTile(
                        dense: true,
                        title: Text(
                          source.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.primary,
                          ),
                        ),
                        subtitle: snippet.isEmpty
                            ? null
                            : Text(
                                snippet,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                        trailing: Icon(
                          Icons.open_in_new_rounded,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          onOpen(source.url);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 消息附件区（图片缩略图 / 文件卡片）。
class _MessageAttachments extends StatelessWidget {
  const _MessageAttachments({required this.attachments, required this.onToast});

  final List<ChatAttachmentView> attachments;
  final void Function(String message) onToast;

  @override
  Widget build(BuildContext context) {
    final images = attachments
        .where((ChatAttachmentView a) => a.isImage)
        .toList(growable: false);
    final files = attachments
        .where((ChatAttachmentView a) => !a.isImage)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (images.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final image in images)
                _AttachmentView(attachment: image, size: 96, onToast: onToast),
            ],
          ),
        for (final file in files)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _AttachmentView(
              attachment: file,
              size: 40,
              showName: true,
              onToast: onToast,
            ),
          ),
      ],
    );
  }
}

/// 附件预览（图片缩略图 / 文件卡片；[_AttachmentViewState] 处理加载失败与上传态）。
class _AttachmentView extends StatefulWidget {
  const _AttachmentView({
    required this.attachment,
    this.size = 64,
    this.showName = false,
    this.onRemove,
    this.onToast,
  });

  final ChatAttachmentView attachment;
  final double size;
  final bool showName;
  final VoidCallback? onRemove;
  final void Function(String message)? onToast;

  @override
  State<_AttachmentView> createState() => _AttachmentViewState();
}

class _AttachmentViewState extends State<_AttachmentView> {
  bool _failed = false;

  bool get _uploading => widget.attachment.uploading;

  bool get _failedUpload => widget.attachment.failed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final attachment = widget.attachment;
    final isImage = attachment.isImage;

    Widget content;
    if (isImage && !_failed && attachment.path.isNotEmpty) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(attachment.path),
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          errorBuilder:
              (BuildContext context, Object error, StackTrace? stack) {
                if (mounted) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && !_failed) setState(() => _failed = true);
                  });
                }
                return _fileCard(context, attachment, compact: true);
              },
        ),
      );
    } else {
      content = _fileCard(context, attachment, compact: widget.size <= 48);
    }

    final stacked = Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        content,
        if (_uploading)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: scheme.scrim.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
        if (_failedUpload)
          Positioned(
            right: 2,
            top: 2,
            child: Icon(Icons.error_rounded, size: 16, color: scheme.error),
          ),
        if (widget.onRemove != null)
          Positioned(
            right: -6,
            top: -6,
            child: InkWell(
              onTap: widget.onRemove,
              customBorder: const CircleBorder(),
              child: CircleAvatar(
                radius: 9,
                backgroundColor: scheme.surfaceContainerHighest,
                child: Icon(
                  Icons.close_rounded,
                  size: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );

    return Padding(padding: const EdgeInsets.all(3), child: stacked);
  }
}

/// 文件大小格式化（[_fmtSize]：`1.4MB` / `820KB`）。
String _fmtSize(int bytes) => AttachmentRules.formatSize(bytes);

/// 文件卡片（[_fileCard]：图标 + 文件名 + 大小）。
Widget _fileCard(
  BuildContext context,
  ChatAttachmentView attachment, {
  bool compact = false,
}) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final icon = _iconForFileName(attachment.fileName);
  final size = _fmtSize(attachment.fileSize);
  if (compact) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 24, color: scheme.onSurfaceVariant),
    );
  }
  return Container(
    constraints: const BoxConstraints(maxWidth: 260),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 20, color: scheme.primary),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                attachment.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium,
              ),
              if (size.isNotEmpty)
                Text(
                  size,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

IconData _iconForFileName(String fileName) {
  final ext = AttachmentRules.extensionOf(fileName);
  switch (ext) {
    case 'pdf':
      return Icons.picture_as_pdf_outlined;
    case 'doc':
    case 'docx':
      return Icons.description_outlined;
    case 'xls':
    case 'xlsx':
    case 'csv':
      return Icons.table_chart_outlined;
    case 'ppt':
    case 'pptx':
      return Icons.slideshow_outlined;
    case 'zip':
    case 'gz':
      return Icons.folder_zip_outlined;
    case 'mp3':
    case 'wav':
    case 'm4a':
      return Icons.audiotrack_outlined;
    case 'mp4':
    case 'mov':
      return Icons.movie_outlined;
    case 'dart':
    case 'js':
    case 'ts':
    case 'py':
    case 'java':
    case 'kt':
    case 'go':
    case 'rs':
    case 'c':
    case 'cpp':
    case 'cs':
    case 'rb':
    case 'php':
    case 'swift':
    case 'sql':
    case 'sh':
    case 'html':
    case 'css':
    case 'json':
    case 'yaml':
    case 'yml':
    case 'xml':
    case 'md':
      return Icons.code_rounded;
    default:
      return Icons.insert_drive_file_outlined;
  }
}

/// 空态（[_EmptyChat]）：「问点什么」。
class _EmptyChat extends StatelessWidget {
  const _EmptyChat({this.onSuggestion});

  final void Function(String text)? onSuggestion;

  static const List<String> _suggestions = <String>[
    '帮我把下面这段话润色一下：',
    '用三句话解释一下量子纠缠',
    '帮我写一个 Python 脚本，批量重命名文件',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 设计稿 B1：大麦克风 + 「问点什么」+ 一行说明 + 3 条建议（静默列表）。
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.mic_none_rounded,
                size: 30,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '问点什么',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '打字，或按住麦克风说话',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // 建议项是静默列表（不是与输入框同形的胶囊），点击只预填、不发送。
                  for (final suggestion in _suggestions)
                    _SuggestionRow(
                      text: suggestion,
                      onTap: onSuggestion == null
                          ? null
                          : () => onSuggestion!(suggestion),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '从「设置 › 数据」导入 DeepSeek 导出包',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 空态里的一条建议：静默列表行（左文案 + 右 chevron），点击只预填输入框。
class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.text, this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 工具行（[_ComposerTools]）：联网搜索 / 深度思考 / 思考强度 / 上下文预算 / 添加附件。
class _ComposerTools extends StatelessWidget {
  const _ComposerTools({
    required this.searchEnabled,
    required this.thinkingEnabled,
    required this.thinkingLevel,
    required this.contextKeepRounds,
    required this.supportsSearch,
    required this.supportsThinking,
    required this.onToggleSearch,
    required this.onToggleThinking,
    required this.onEditThinkingLevel,
    required this.onEditContextBudget,
  });

  final bool searchEnabled;
  final bool thinkingEnabled;
  final ThinkingLevel thinkingLevel;
  final int contextKeepRounds;
  final bool supportsSearch;
  final bool supportsThinking;
  final VoidCallback onToggleSearch;
  final VoidCallback onToggleThinking;
  final VoidCallback onEditThinkingLevel;
  final VoidCallback onEditContextBudget;

  @override
  Widget build(BuildContext context) {
    // M5：芯片行不再固定 44 高，改由 chip 的 minHeight 决定整体高度。
    // 横向滚动仍保留（芯片多时不会挤成两行）。
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
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
            tooltip: supportsThinking ? '支持深度思考（长按选择思考强度）' : ' 不支持深度思考',
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
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool disabled;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = disabled
        ? scheme.onSurfaceVariant.withValues(alpha: 0.5)
        : selected
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
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
          // M5：minHeight 而不是固定 44 —— 大字体下 chip 跟着长高，不会溢出。
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? scheme.selectedBorder : scheme.outlineVariant,
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

/// 待发送附件 chips（[_PendingChips]）。
class _PendingChips extends StatelessWidget {
  const _PendingChips({
    required this.attachments,
    required this.uploading,
    required this.onRemove,
  });

  final List<ChatAttachmentView> attachments;
  final bool uploading;
  final void Function(String id) onRemove;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(left: 10, right: 10, top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (uploading)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.6),
                  ),
                  const SizedBox(width: 6),
                  Text('正在上传附件…', style: theme.textTheme.labelSmall),
                ],
              ),
            ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final attachment in attachments)
                _AttachmentView(
                  attachment: attachment,
                  size: 52,
                  onRemove: () => onRemove(attachment.id),
                  showName: false,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 输入栏（[_InputBar] + [_InputBarState]）：输入框 / 按住说话 / 发送 / 停止。
class _InputBar extends StatefulWidget {
  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.streaming,
    required this.sending,
    required this.canSend,
    required this.canAttach,
    required this.voiceMode,
    required this.holdState,
    required this.onSend,
    required this.onStop,
    required this.onPickFiles,
    required this.onVoiceToggle,
    required this.onPointerDown,
    required this.onPointerUp,
    required this.onPointerCancel,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool streaming;
  final bool sending;
  final bool canSend;
  final bool canAttach;
  final bool voiceMode;
  final VoiceHoldState holdState;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onPickFiles;
  final VoidCallback onVoiceToggle;
  final void Function(PointerDownEvent event) onPointerDown;
  final void Function(PointerUpEvent event) onPointerUp;
  final void Function(PointerCancelEvent event) onPointerCancel;

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(_InputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChanged);
      widget.focusNode.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() {
    if (!mounted) return;
    setState(() => _focused = widget.focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final recording = widget.holdState.phase == VoicePhase.recording;
    final transcribing = widget.holdState.phase == VoicePhase.transcribing;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            IconButton(
              onPressed: widget.voiceMode ? null : widget.onPickFiles,
              tooltip: '添加附件',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.add_circle_outline_rounded,
                color: widget.canAttach
                    ? scheme.onSurfaceVariant
                    : scheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
            ),
            Expanded(
              child: widget.voiceMode
                  ? Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: widget.onPointerDown,
                      onPointerUp: widget.onPointerUp,
                      onPointerCancel: widget.onPointerCancel,
                      child: Container(
                        // M5：语音条用 minHeight 44（触达下限）而不是固定高，
                        // 大字体下文字能撑高容器而不溢出。
                        constraints: const BoxConstraints(minHeight: 44),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: recording
                              ? scheme.errorContainer
                              : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: recording
                                ? scheme.error
                                : scheme.outlineVariant,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (transcribing)
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.8,
                                ),
                              )
                            else
                              Icon(
                                recording
                                    ? Icons.mic_rounded
                                    : Icons.mic_none_rounded,
                                size: 18,
                                color: recording
                                    ? scheme.onErrorContainer
                                    : scheme.onSurfaceVariant,
                              ),
                            const SizedBox(width: 6),
                            Text(
                              widget.holdState.phase == VoicePhase.idle
                                  ? VoiceText.holdToTalk
                                  : widget.holdState.hintText,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: recording
                                    ? scheme.onErrorContainer
                                    : scheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : TextField(
                      controller: widget.controller,
                      focusNode: widget.focusNode,
                      minLines: 1,
                      maxLines: 6,
                      textInputAction: TextInputAction.newline,
                      style: theme.textTheme.bodyMedium,
                      decoration: InputDecoration(
                        hintText: '发消息…',
                        isDense: true,
                        filled: true,
                        fillColor: scheme.surfaceContainerHighest,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: _focused
                                ? scheme.primary
                                : scheme.outlineVariant,
                            width: 1.2,
                          ),
                        ),
                      ),
                    ),
            ),
            IconButton(
              onPressed: widget.onVoiceToggle,
              tooltip: widget.voiceMode ? '切换键盘' : VoiceText.voice,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                widget.voiceMode
                    ? Icons.keyboard_alt_outlined
                    : Icons.mic_none_rounded,
                color: widget.voiceMode
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 2),
            _SendStopButton(
              streaming: widget.streaming,
              sending: widget.sending,
              canSend: widget.canSend,
              onSend: widget.onSend,
              onStop: widget.onStop,
            ),
          ],
        ),
      ),
    );
  }
}

/// 发送/停止按钮。
class _SendStopButton extends StatelessWidget {
  const _SendStopButton({
    required this.streaming,
    required this.sending,
    required this.canSend,
    required this.onSend,
    required this.onStop,
  });

  final bool streaming;
  final bool sending;
  final bool canSend;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (streaming) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: IconButton.filled(
          onPressed: onStop,
          tooltip: '停止',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
          style: IconButton.styleFrom(backgroundColor: scheme.errorContainer),
          icon: Icon(Icons.stop_rounded, color: scheme.onErrorContainer),
        ),
      );
    }
    final enabled = canSend && !sending;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: IconButton.filled(
        onPressed: enabled ? onSend : null,
        tooltip: '发送',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        icon: sending
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.arrow_upward_rounded),
      ),
    );
  }
}

/// 分支导航（[_BranchSwitcher]）：上一个 / 下一个分支。
class _BranchSwitcher extends StatelessWidget {
  const _BranchSwitcher({
    required this.branchIndex,
    required this.branchCount,
    this.onPrev,
    this.onNext,
  });

  final int branchIndex;
  final int branchCount;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _ArrowButton(
          icon: Icons.chevron_left_rounded,
          tooltip: '上一个分支',
          onPressed: onPrev,
          dense: true,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            '$branchIndex/$branchCount',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        _ArrowButton(
          icon: Icons.chevron_right_rounded,
          tooltip: '下一个分支',
          onPressed: onNext,
          dense: true,
        ),
      ],
    );
  }
}

/// 重新生成按钮（[_RegenerateButton]）。
class _RegenerateButton extends StatelessWidget {
  const _RegenerateButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: onPressed,
      iconSize: 18,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      tooltip: '以这条回复的问题重新生成一版，旧回答会留在分支里',
      icon: Icon(Icons.refresh_rounded, color: scheme.onSurfaceVariant),
    );
  }
}

/// 小圆角方向按钮（[_ArrowButton]：分支导航 / 滚动到底）。
class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.dense = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final button = Material(
      color: scheme.surfaceContainerHigh,
      shape: const CircleBorder(),
      elevation: dense ? 0 : 2,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: dense ? 26 : 36,
          height: dense ? 26 : 36,
          child: Icon(
            icon,
            size: dense ? 18 : 20,
            color: enabled
                ? scheme.onSurfaceVariant
                : scheme.onSurfaceVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
    final text = tooltip;
    return text == null ? button : Tooltip(message: text, child: button);
  }
}

/// 用量条闸门（设计稿 B2 / B6）：占用率 < 80% 且没有出错时整条不出现。
///
/// 用量条组件本身在 `session_usage_bar.dart`（不在本批次改动范围），这里只做
/// 「要不要出现」的判断：读取中 / 无数据都不占位；读取失败或本轮出错要显示。
class _SessionUsageGate extends ConsumerWidget {
  const _SessionUsageGate({required this.sessionId, required this.hasError});

  /// 当前会话 id；空字符串时整条不渲染。
  final String sessionId;

  /// 本轮是否出错（出错时显示，让用户看到真实占用量）。
  final bool hasError;

  /// 出现阈值：占用率低于它就不显示（设计建议 80%）。
  static const double _showThreshold = 80;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (sessionId.isEmpty) return const SizedBox.shrink();
    final contextWindow = ref.watch(settingsProvider).contextWindowTokens;
    final storeAsync = ref.watch(usageStoreProvider);
    // 读取失败：交给用量条自己显示失败态（图标转红）。
    if (storeAsync.hasError) return SessionUsageBar(sessionId: sessionId);
    final store = storeAsync.value;
    if (store == null) return const SizedBox.shrink();
    return StreamBuilder<SessionUsage>(
      stream: store.sessionChanges(sessionId),
      initialData: store.sessionUsage(sessionId),
      builder: (BuildContext context, AsyncSnapshot<SessionUsage> snapshot) {
        final usage = snapshot.data ?? store.sessionUsage(sessionId);
        final percent = occupancyPercent(
          promptTokens: usage.lastPromptTokens,
          contextWindowTokens: contextWindow,
        );
        // 还没请求过（无数据）：不显示，别拿一行「—」占位置。
        if (percent == null) return const SizedBox.shrink();
        if (!hasError && percent < _showThreshold) {
          return const SizedBox.shrink();
        }
        return SessionUsageBar(sessionId: sessionId);
      },
    );
  }
}

/// 错误条（[_ErrorBanner]）：错误文案 + 重试 + 关闭。
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.onRetry,
    required this.onDismiss,
  });

  final String? message;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final text = message?.trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.error_outline_rounded,
              size: 16,
              color: scheme.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: scheme.onErrorContainer,
                visualDensity: VisualDensity.compact,
                textStyle: theme.textTheme.labelMedium,
              ),
              child: const Text('重试'),
            ),
            IconButton(
              onPressed: onDismiss,
              tooltip: '关闭',
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              icon: Icon(Icons.close_rounded, color: scheme.onErrorContainer),
            ),
          ],
        ),
      ),
    );
  }
}
