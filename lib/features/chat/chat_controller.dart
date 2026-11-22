/// Keepsake（留声）— 聊天核心状态机（`ChatController` + 不可变 `ChatUiState`）。
///
/// 情报依据（`next-steps.md` §2 chat_controller、`dart-symbols.md` §3、
/// `db-schema.md` §2、`prompts.md` §2）：本库（`@1161350130`）的私有方法名是
/// `_send` `_runCompletion` `_applyEvent` `_handleNonBlockEvent` `_resolveProvider`
/// `_providerProblem` `_persistFinal` `_regenerate` `_replaceAssistant` `_refreshChain`
/// `_rowById` `_notify` `_toUi` 与 `get:_db`，消息是**树**（`root_message_id` /
/// `current_message_id`），重新生成 = 新建分支（旧回答保留，可切上一个/下一个分支）。
///
/// 消息树语义（与 `core/db/database.dart` 的 `branchesOf` 一致）：
/// - `messages.root_message_id` = **父消息 id**（根消息为 null）；
///   同一父下的多条消息就是同一问题的多个分支（`branchesOf(parentId)`）。
/// - `messages.current_message_id` = 该消息**当前选中的子节点**（叶子为 null）。
/// - `sessions.current_message_id` = 当前分支的叶子；沿 `current_message_id`
///   向下走即「当前可见链」；从叶子沿 `root_message_id` 向上回溯即可重建整条链。
/// - `messages.index` = 写入顺序（同一父的兄弟按它升序，越新越靠后）。
///
/// 跨批次依赖（批次 A/B/C）都在本文件末尾「依赖适配区」集中调用，
/// 其它批次改签名时只需要改那一段。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/chat_backend.dart';
import '../../core/api/file_upload.dart';
import '../../core/brain/brain_service.dart';
import '../../core/brain/brain_store.dart';
import '../../core/brain/brain_types.dart';
import '../../core/characters/character_service.dart';
import '../../core/chat/attachments.dart' as attachments;
import '../../core/chat/blocks.dart' as blk;
import '../../core/chat/context_builder.dart';
import '../../core/chat/summarizer.dart';
import '../../core/import/import_task.dart';
import '../../core/providers.dart';
import '../../core/usage/usage_store.dart';

// ---------------------------------------------------------------------------
// 常量
// ---------------------------------------------------------------------------

/// 消息角色（DB `messages.role` 字符串原文）。
abstract final class ChatRole {
  static const String user = 'user';
  static const String assistant = 'assistant';
  static const String system = 'system';
}

/// 连接中断固定文案（ui-strings §11；具体哪一句由 `sse.dart` 抛的 `ApiError.message` 决定）。
const String kConnectionLostMessage = '连接中断，没有收到结束标记';

/// 附件不支持时的固定提示（ui-strings §2 原文，前置空格也照抄）。
const String kAttachUnsupportedMessage =
    ' 暂不支持附件（只有 DeepSeek 的 Files API 支持），请改成发文字';

/// 上传失败前缀（ui-strings §3）。
const String kUploadFailedPrefix = '上传失败：';

const Uuid _uuid = Uuid();

// ---------------------------------------------------------------------------
// 视图模型（不可变）
// ---------------------------------------------------------------------------

/// 消息附件（草稿或已挂到消息上的）状态。
enum ChatAttachmentStatus {
  /// 待上传 / 上传中。
  uploading,

  /// 就绪（本地文件存在；或有服务端 fileId）。
  ready,

  /// 上传失败。
  failed,
}

/// 一条附件的 UI 视图。
@immutable
class ChatAttachmentView {
  const ChatAttachmentView({
    required this.id,
    required this.fileName,
    this.fileSize = 0,
    this.mime = '',
    this.path = '',
    this.width,
    this.height,
    this.fileId,
    this.url,
    this.status = ChatAttachmentStatus.ready,
    this.error,
  });

  final String id;
  final String fileName;
  final int fileSize;
  final String mime;
  final String path;
  final int? width;
  final int? height;
  final String? fileId;
  final String? url;
  final ChatAttachmentStatus status;
  final String? error;

  bool get isImage =>
      mime.toLowerCase().startsWith('image/') ||
      attachments.AttachmentRules.imageExtensions.contains(
        attachments.AttachmentRules.extensionOf(fileName),
      );

  bool get uploaded => fileId != null && fileId!.trim().isNotEmpty;

  bool get uploading => status == ChatAttachmentStatus.uploading;

  bool get failed => status == ChatAttachmentStatus.failed;

  /// `1.4MB` 之类。
  String get displaySize => attachments.AttachmentRules.formatSize(fileSize);

  /// 转成批次 C 的附件模型（上传 / 落库 / 发请求都用它）。
  attachments.Attachment toAttachment({String? sessionId, String? messageId}) =>
      attachments.Attachment(
        id: id,
        sessionId: sessionId,
        messageId: messageId,
        fileName: fileName,
        fileSize: fileSize,
        mime: mime,
        path: path,
        width: width,
        height: height,
        fileId: fileId,
        url: url,
      );

  ChatAttachmentView copyWith({
    String? id,
    String? fileName,
    int? fileSize,
    String? mime,
    String? path,
    int? width,
    int? height,
    String? fileId,
    String? url,
    ChatAttachmentStatus? status,
    String? error,
  }) => ChatAttachmentView(
    id: id ?? this.id,
    fileName: fileName ?? this.fileName,
    fileSize: fileSize ?? this.fileSize,
    mime: mime ?? this.mime,
    path: path ?? this.path,
    width: width ?? this.width,
    height: height ?? this.height,
    fileId: fileId ?? this.fileId,
    url: url ?? this.url,
    status: status ?? this.status,
    error: error ?? this.error,
  );

  @override
  String toString() => 'ChatAttachmentView($id, $fileName, $status)';
}

/// 一条联网搜索来源（`web_search_tool_result` 里的一条）。
@immutable
class ChatSearchSource {
  const ChatSearchSource({
    required this.url,
    this.title,
    this.snippet,
    this.siteName,
    this.publishedAt,
  });

  final String url;
  final String? title;
  final String? snippet;
  final String? siteName;
  final String? publishedAt;

  /// 展示标题：标题 > 站点名 > 域名 > url。
  String get displayTitle {
    final value = (title ?? '').trim();
    if (value.isNotEmpty) return value;
    final site = (siteName ?? '').trim();
    if (site.isNotEmpty) return site;
    final host = Uri.tryParse(url)?.host ?? '';
    return host.isEmpty ? url : host;
  }

  @override
  String toString() => 'ChatSearchSource($url)';
}

/// 一条消息的 UI 视图（含分支位置与流式状态）。
@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.createdAt,
    this.text = '',
    this.thinking = '',
    this.thinkingSeconds,
    this.blocks = const <blk.ContentBlock>[],
    this.attachments = const <ChatAttachmentView>[],
    this.searchSources = const <ChatSearchSource>[],
    this.flags = 0,
    this.streaming = false,
    this.thinkingNow = false,
    this.searchingNow = false,
    this.branchIndex = 1,
    this.branchCount = 1,
    this.isLeaf = false,
  });

  final String id;
  final String role;
  final DateTime createdAt;

  /// markdown 正文（assistant 消息的 text 块合并；user 消息的纯文字）。
  final String text;

  /// 思考过程（可折叠）。
  final String thinking;

  /// 思考耗时（秒）。
  final double? thinkingSeconds;

  /// 完整内容块（正文 / 思考 / 搜索 / 图片 / 文件 / mermaid）。
  final List<blk.ContentBlock> blocks;

  /// 消息附件（图片/文件）。
  final List<ChatAttachmentView> attachments;

  /// 联网搜索来源。
  final List<ChatSearchSource> searchSources;

  /// DB 位域（[MessageFlag]）。
  final int flags;

  /// 正在流式生成（显示光标/转圈）。
  final bool streaming;

  /// 这一条正在思考。
  final bool thinkingNow;

  /// 这一条正在联网搜索。
  final bool searchingNow;

  /// 当前是第几个分支（1 基）。
  final int branchIndex;

  /// 兄弟分支总数。
  final int branchCount;

  /// 是否是当前分支的叶子。
  final bool isLeaf;

  bool get isUser => role == ChatRole.user;

  bool get isAssistant => role == ChatRole.assistant;

  bool get isSystem => role == ChatRole.system;

  /// 出过错（`MessageFlag.error`）。
  bool get error => (flags & MessageFlag.error) != 0;

  /// 是否有多分支可切换。
  bool get hasBranches => branchCount > 1;

  bool get canPrevBranch => branchIndex > 1;

  bool get canNextBranch => branchIndex < branchCount;

  bool get isEmpty =>
      text.trim().isEmpty && thinking.trim().isEmpty && blocks.isEmpty;

  /// 供「复制 / 朗读」用的纯文本。
  String get plainText {
    final parts = <String>[];
    if (text.trim().isNotEmpty) parts.add(text.trim());
    for (final block in blocks) {
      if (block.type == blk.BlockType.text ||
          block.type == blk.BlockType.code) {
        final value = block.plainText;
        if (value.isNotEmpty && !parts.contains(value)) parts.add(value);
      }
    }
    return parts.join('\n\n').trim();
  }

  ChatMessage copyWith({
    String? id,
    String? role,
    DateTime? createdAt,
    String? text,
    String? thinking,
    double? thinkingSeconds,
    List<blk.ContentBlock>? blocks,
    List<ChatAttachmentView>? attachments,
    List<ChatSearchSource>? searchSources,
    int? flags,
    bool? streaming,
    bool? thinkingNow,
    bool? searchingNow,
    int? branchIndex,
    int? branchCount,
    bool? isLeaf,
  }) => ChatMessage(
    id: id ?? this.id,
    role: role ?? this.role,
    createdAt: createdAt ?? this.createdAt,
    text: text ?? this.text,
    thinking: thinking ?? this.thinking,
    thinkingSeconds: thinkingSeconds ?? this.thinkingSeconds,
    blocks: blocks ?? this.blocks,
    attachments: attachments ?? this.attachments,
    searchSources: searchSources ?? this.searchSources,
    flags: flags ?? this.flags,
    streaming: streaming ?? this.streaming,
    thinkingNow: thinkingNow ?? this.thinkingNow,
    searchingNow: searchingNow ?? this.searchingNow,
    branchIndex: branchIndex ?? this.branchIndex,
    branchCount: branchCount ?? this.branchCount,
    isLeaf: isLeaf ?? this.isLeaf,
  );

  @override
  String toString() => 'ChatMessage($id, $role, ${text.length} chars)';
}

/// 聊天页不可变视图态（UI 只依赖它）。
@immutable
class ChatUiState {
  const ChatUiState({
    this.sessionId = '',
    this.title = '',
    this.messages = const <ChatMessage>[],
    this.loading = true,
    this.streaming = false,
    this.thinking = false,
    this.thinkingText = '',
    this.searching = false,
    this.searchSources = const <ChatSearchSource>[],
    this.error,
    this.usage = UsageTotals.empty,
    this.providerId = '',
    this.providerName = '',
    this.model = '',
    this.branchIndex = 1,
    this.branchCount = 1,
    this.pendingAttachments = const <ChatAttachmentView>[],
    this.uploading = false,
    this.canAttach = false,
    this.searchEnabled = false,
    this.thinkingEnabled = false,
    this.thinkingLevel = ThinkingLevel.medium,
    this.contextKeepRounds = kDefaultContextKeepRounds,
    this.streamingMessageId,
  });

  /// 会话 id。
  final String sessionId;

  /// 会话标题（AppBar）。
  final String title;

  /// 当前分支的可见消息链（root → leaf）。
  final List<ChatMessage> messages;

  /// 首次加载中。
  final bool loading;

  /// 正在流式生成。
  final bool streaming;

  /// 正在思考（`thinking_delta` 期间）。
  final bool thinking;

  /// 本次流式累计的思考文本（可折叠展示）。
  final String thinkingText;

  /// 正在联网搜索（`web_search_tool_result` running）。
  final bool searching;

  /// 本次请求已拿到的搜索来源。
  final List<ChatSearchSource> searchSources;

  /// 错误条文案（非空时展示可关闭的错误条 / 重试）。
  final String? error;

  /// 本次（或上一条完成的）请求用量。
  final UsageTotals usage;

  /// 当前平台 id（会话级优先，其次设置）。
  final String providerId;

  /// 当前平台显示名。
  final String providerName;

  /// 当前模型。
  final String model;

  /// 最后一条消息的分支位置（1 基）。
  final int branchIndex;

  /// 最后一条消息的兄弟分支总数。
  final int branchCount;

  /// 待发送附件（草稿）。
  final List<ChatAttachmentView> pendingAttachments;

  /// 附件上传中。
  final bool uploading;

  /// 当前平台是否支持附件上传（只有 DeepSeek Files API 支持）。
  final bool canAttach;

  /// 会话级联网搜索开关。
  final bool searchEnabled;

  /// 当前**生效**的深度思考开关（会话覆盖 ?? 全局默认）。
  ///
  /// 聊天页 chip 显示它；全局设置里的 `thinkingEnabled` 只是新会话的默认值。
  final bool thinkingEnabled;

  /// 当前**生效**的思考强度（会话覆盖 ?? 全局默认）。
  final ThinkingLevel thinkingLevel;

  /// 当前**生效**的上下文预算（会话覆盖 ?? 全局默认；`<= 0` = 不限制）。
  final int contextKeepRounds;

  /// 正在流式生成的那条消息 id（UI 用于滚动/定位）。
  final String? streamingMessageId;

  /// 是否可以发送/停止（UI 发送按钮状态）。
  bool get busy => streaming;

  /// 是否为空会话（显示空态「问点什么」）。
  bool get isEmpty => messages.isEmpty && !streaming;

  /// 是否能在当前状态下发送。
  bool get canSend => !streaming && !uploading;

  /// 最后一条消息。
  ChatMessage? get lastMessage => messages.isEmpty ? null : messages.last;

  /// 最后一条 assistant 消息。
  ChatMessage? get lastAssistant {
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].isAssistant) return messages[i];
    }
    return null;
  }

  /// 最后一条 user 消息。
  ChatMessage? get lastUser {
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].isUser) return messages[i];
    }
    return null;
  }

  /// 是否能切上一个/下一个分支（最后一条消息）。
  bool get canPrevBranch => branchIndex > 1;

  bool get canNextBranch => branchIndex < branchCount;

  ChatUiState copyWith({
    String? sessionId,
    String? title,
    List<ChatMessage>? messages,
    bool? loading,
    bool? streaming,
    bool? thinking,
    String? thinkingText,
    bool? searching,
    List<ChatSearchSource>? searchSources,
    Object? error = _sentinel,
    UsageTotals? usage,
    String? providerId,
    String? providerName,
    String? model,
    int? branchIndex,
    int? branchCount,
    List<ChatAttachmentView>? pendingAttachments,
    bool? uploading,
    bool? canAttach,
    bool? searchEnabled,
    bool? thinkingEnabled,
    ThinkingLevel? thinkingLevel,
    int? contextKeepRounds,
    Object? streamingMessageId = _sentinel,
  }) => ChatUiState(
    sessionId: sessionId ?? this.sessionId,
    title: title ?? this.title,
    messages: messages ?? this.messages,
    loading: loading ?? this.loading,
    streaming: streaming ?? this.streaming,
    thinking: thinking ?? this.thinking,
    thinkingText: thinkingText ?? this.thinkingText,
    searching: searching ?? this.searching,
    searchSources: searchSources ?? this.searchSources,
    error: identical(error, _sentinel) ? this.error : error as String?,
    usage: usage ?? this.usage,
    providerId: providerId ?? this.providerId,
    providerName: providerName ?? this.providerName,
    model: model ?? this.model,
    branchIndex: branchIndex ?? this.branchIndex,
    branchCount: branchCount ?? this.branchCount,
    pendingAttachments: pendingAttachments ?? this.pendingAttachments,
    uploading: uploading ?? this.uploading,
    canAttach: canAttach ?? this.canAttach,
    searchEnabled: searchEnabled ?? this.searchEnabled,
    thinkingEnabled: thinkingEnabled ?? this.thinkingEnabled,
    thinkingLevel: thinkingLevel ?? this.thinkingLevel,
    contextKeepRounds: contextKeepRounds ?? this.contextKeepRounds,
    streamingMessageId: identical(streamingMessageId, _sentinel)
        ? this.streamingMessageId
        : streamingMessageId as String?,
  );

  @override
  String toString() =>
      'ChatUiState($sessionId, ${messages.length} msgs, '
      'streaming=$streaming, thinking=$thinking, searching=$searching, '
      'error=$error, provider=$providerName/$model, branch=$branchIndex/$branchCount)';
}

const Object _sentinel = Object();

// ---------------------------------------------------------------------------
// Provider（定义在 chat_controller.dart，名字由 `next-steps.md` 契约 C 冻结）
// ---------------------------------------------------------------------------

/// 聊天控制器 provider：按会话 id（`String`）分家。
///
/// `ChatController([String? sessionId])` 的可选位置参数让它同时能喂给
/// `NotifierProvider.family`（arg = sessionId）和普通 `NotifierProvider`
/// （此时由 `ChatScreen` 调 `open(sessionId)` 绑定）。
final chatControllerProvider = NotifierProvider.autoDispose
    .family<ChatController, ChatUiState, String>(
      ChatController.new,
      name: 'chatControllerProvider',
    );

// ---------------------------------------------------------------------------
// ChatController
// ---------------------------------------------------------------------------

/// 聊天状态机。
///
/// 公开 API（UI 用）：
/// - [send] / [regenerate] / [stop] / [edit] / [switchBranch] / [deleteMessage] / [retry]
/// - [setProvider] / [setModel] / [setSearchEnabled] / [setThinkingEnabled]
/// - [addAttachment] / [removeAttachment] / [clearAttachments]
/// - [dismissError] / [refresh] / [open]
class ChatController extends Notifier<ChatUiState> {
  ChatController([this.sessionId]);

  /// family 传进来的会话 id（也可为空，由 [open] 绑定）。
  final String? sessionId;

  // --- DB / 缓存 ---
  String _sessionId = '';
  String _title = '';
  List<Message> _allRows = const <Message>[];
  List<Message> _chain = const <Message>[];
  Map<String, List<ChatAttachmentView>> _attachmentsByMessage = const {};
  bool _loaded = false;
  bool _disposed = false;

  // --- 会话级选择（「平台与模型（当前会话）」）---
  String? _providerOverrideId;
  String? _modelOverride;
  bool _searchEnabled = false;

  /// 会话级搜索状态（`sessions.search_enabled`）。null = 还没读到会话行。
  /// 有这个值时，全局设置变化（例如改思考强度）不得覆盖它。
  bool? _sessionSearchEnabled;

  /// 会话级「深度思考」覆盖值（`sessions.thinking_enabled`）。
  ///
  /// `null` = 未覆盖，用全局设置里的默认值 [Settings.thinkingEnabled]。
  /// **聊天页只写会话覆盖，不写全局设置**。
  bool? _sessionThinkingEnabled;

  /// 会话级「思考强度」覆盖值（`sessions.thinking_level`，存 `wireName`）。
  ThinkingLevel? _sessionThinkingLevel;

  /// 会话级上下文预算覆盖值（`sessions.context_keep_rounds`）。
  int? _sessionContextRounds;

  /// **生效**的深度思考开关（会话覆盖 ?? 默认，且平台要支持深度思考）。
  bool _thinkingEnabled = false;

  // --- 流式状态 ---
  StreamSubscription<ChatEvent>? _sub;
  ChatBackend? _backend;
  bool _streaming = false;
  bool _finalizing = false;
  bool _searchRunning = false;
  String? _streamingId;
  final StringBuffer _streamText = StringBuffer();
  final StringBuffer _streamThinking = StringBuffer();
  final List<blk.ContentBlock> _streamBlocks = <blk.ContentBlock>[];
  List<ChatSearchSource> _streamSources = const <ChatSearchSource>[];
  List<CitationMark> _streamCitations = const <CitationMark>[];
  DateTime? _thinkingStartedAt;
  UsageTotals _usage = UsageTotals.empty;
  UsageDelta _usageDelta = UsageDelta.zero;
  ApiError? _pendingError;

  /// 落库占位文案用：失败时把真实错误（401/402/429… 的中文文案）写进消息，
  /// 不要一律写成「连接中断」。
  String? _finalErrorText;
  bool _stopped = false;
  Timer? _notifyTimer;

  /// 流代次：每次 `_runCompletion` +1，「停止」后旧订阅的迟到事件/回调一律丢弃。
  int _streamToken = 0;

  /// DB（符号表 `get:_db`）。
  AppDatabase get _db => ref.read(databaseProvider);

  // -------------------------------------------------------------------------
  // build / dispose
  // -------------------------------------------------------------------------

  @override
  ChatUiState build() {
    _sessionId = sessionId ?? _sessionId;
    ref.onDispose(_onDispose);
    // 平台列表 / 设置变化后（例如用户刚在设置里加完平台、填完 Key），
    // 已打开的会话也要立刻反映到 UI（表头平台名、附件能力位）。
    ref.listen(providerBookProvider, (_, _) => _syncProviderState());
    ref.listen(settingsProvider, (_, _) => _syncProviderState());
    final settings = ref.read(settingsProvider);
    final provider = _resolveProvider();
    _thinkingEnabled = _effectiveThinking(provider);
    _searchEnabled = _sessionSearchEnabled ?? settings.searchEnabled;
    if (_sessionId.isNotEmpty) {
      // build 里不能直接 await；排到微任务里加载，避免阻塞首帧。
      unawaited(Future<void>.microtask(_refreshChain));
    }
    return ChatUiState(
      sessionId: _sessionId,
      loading: _sessionId.isNotEmpty,
      providerId: provider?.id ?? '',
      providerName: provider?.name ?? '',
      model: _currentModel(provider, settings),
      canAttach: provider?.supportsFiles ?? false,
      searchEnabled: _searchEnabled,
      thinkingEnabled: _thinkingEnabled,
      thinkingLevel: _effectiveThinkingLevel,
      contextKeepRounds: _effectiveContextRounds,
    );
  }

  /// 平台/设置变化时刷新与平台相关的状态（不重载消息链）。
  void _syncProviderState() {
    if (_disposed) return;
    final provider = _resolveProvider();
    final settings = ref.read(settingsProvider);
    final name = provider?.name ?? '';
    final id = provider?.id ?? '';
    final model = _currentModel(provider, settings);
    final canAttach = provider?.supportsFiles ?? false;
    // 会话覆盖优先：设置页改默认值不会覆盖当前会话里已经选过的值
    // （`_sessionThinkingEnabled` 为 null 时才回落到全局默认）。
    _thinkingEnabled = _effectiveThinking(provider);
    // 会话级搜索状态优先：改思考强度/平台等全局设置时不能把会话里的开关翻回去。
    final settingsSearch = settings.searchEnabled;
    _searchEnabled = _sessionSearchEnabled ?? settingsSearch;
    final thinkingLevel = _effectiveThinkingLevel;
    final contextRounds = _effectiveContextRounds;
    final current = state;
    if (current.providerId == id &&
        current.providerName == name &&
        current.model == model &&
        current.canAttach == canAttach &&
        current.searchEnabled == _searchEnabled &&
        current.thinkingEnabled == _thinkingEnabled &&
        current.thinkingLevel == thinkingLevel &&
        current.contextKeepRounds == contextRounds) {
      return;
    }
    state = current.copyWith(
      providerId: id,
      providerName: name,
      model: model,
      canAttach: canAttach,
      searchEnabled: _searchEnabled,
      thinkingEnabled: _thinkingEnabled,
      thinkingLevel: thinkingLevel,
      contextKeepRounds: contextRounds,
    );
  }

  void _onDispose() {
    _disposed = true;
    _streamToken++;
    _notifyTimer?.cancel();
    _notifyTimer = null;
    final sub = _sub;
    _sub = null;
    if (sub != null) unawaited(sub.cancel());
    _backend?.dispose();
    _backend = null;
  }

  /// 绑定会话（非 family 接线的兜底入口）。
  Future<void> open(String id) async {
    if (id.isEmpty || id == _sessionId) {
      if (_sessionId.isNotEmpty) await _refreshChain();
      return;
    }
    _sessionId = id;
    _loaded = false;
    _providerOverrideId = null;
    _modelOverride = null;
    // 换会话：先清掉上一个会话的覆盖值，等 `_refreshChain` 读到本会话的行。
    _sessionSearchEnabled = null;
    _sessionThinkingEnabled = null;
    _sessionThinkingLevel = null;
    _sessionContextRounds = null;
    _thinkingEnabled = _effectiveThinking(_resolveProvider());
    state = ChatUiState(
      sessionId: id,
      loading: true,
      thinkingEnabled: _thinkingEnabled,
      thinkingLevel: _effectiveThinkingLevel,
      contextKeepRounds: _effectiveContextRounds,
    );
    await _refreshChain();
  }

  // -------------------------------------------------------------------------
  // 公开动作
  // -------------------------------------------------------------------------

  /// 发送一条消息（可带待发送附件）。
  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (_streaming) return;
    if (_sessionId.isEmpty) return;
    if (trimmed.isEmpty && state.pendingAttachments.isEmpty) return;
    await _send(trimmed);
  }

  /// 重新生成：**新建分支**，旧回答留在分支里。
  ///
  /// [messageId] 为要重新生成的 assistant 消息；为空则重生成最后一条回答。
  Future<void> regenerate([String? messageId]) => _regenerate(messageId);

  /// 出错后重试：最后一条是 assistant 就重生成，是 user 就补一个回答。
  Future<void> retry() async {
    if (_streaming || _chain.isEmpty) return;
    final last = _chain.last;
    if (last.role == ChatRole.assistant) {
      await _regenerate(last.id);
    } else {
      await _startAssistantReply(parentId: last.id);
    }
  }

  /// 「停止」：取消在飞请求，把已经收到的内容落库。
  ///
  /// 注意：`StreamSubscription.cancel()` 在某些传输实现里要等远端的收尾 future，
  /// **不能 await**（否则「停止」按钮会一直转圈）。这里只发起取消并立即落库，
  /// 之后到达的事件由 `_stopped` 守卫丢弃。
  Future<void> stop() async {
    if (!_streaming) return;
    _stopped = true;
    _streamToken++; // 让旧订阅的后续回调全部失效
    final backend = _backend;
    _backend = null;
    if (backend != null) {
      // 先同步置位 `_cancelled`（这样底层 SSE 断流异常会被静默吞掉），
      // 再发起取消；不 await，避免「停止」按钮等网络收尾而卡住。
      unawaited(backend.cancel().catchError((Object _) {}));
      backend.dispose();
    }
    // 注意：这里**不** cancel 流订阅。async* 生成器被取消时若正卡在
    // 「等下一块数据」上，`cancel()` 的 future 可能永远不完成（UI 会卡在
    // 「停止」上），而且迟到的断流异常会变成未捕获错误。让底层流自然结束，
    // 让底层流自然结束，事件由 `_streamToken` / `_stopped` 守卫丢弃即可。
    await _persistFinal(cancelled: true);
    // 用户主动停止不是错误：清掉可能残留的错误条。
    state = state.copyWith(error: null);
  }

  /// 编辑并重发一条 user 消息（新建分支，旧的一轮保留可切换）。
  Future<void> edit(String messageId, String newText) async {
    if (_streaming) return;
    final row = _rowById(messageId);
    if (row == null || row.role != ChatRole.user) return;
    final text = newText.trim();
    if (text.isEmpty) return;
    final parentId = row.rootMessageId;
    final newId = _uuid.v4();
    final content = blk.encodeBlocks(<blk.ContentBlock>[
      blk.ContentBlock.text(text),
    ]);
    await _db.addMessage(
      id: newId,
      sessionId: _sessionId,
      role: ChatRole.user,
      content: content,
      rootMessageId: (parentId == null || parentId.isEmpty) ? null : parentId,
      index: _nextIndex(),
    );
    await _pointParentTo(parentId, newId);
    await _db.setSessionCurrentMessage(_sessionId, newId);
    await _refreshChain();
    await _startAssistantReply(parentId: newId);
  }

  /// 切换分支（[delta] = -1 上一个 / +1 下一个）。
  Future<void> switchBranch(String messageId, int delta) async {
    if (_streaming || delta == 0) return;
    final row = _rowById(messageId);
    if (row == null) return;
    final siblings = _siblingsOf(row);
    if (siblings.length < 2) return;
    final current = siblings.indexWhere((s) => s.id == row.id);
    if (current < 0) return;
    final next = current + delta;
    if (next < 0 || next >= siblings.length) return;
    final chosen = siblings[next];
    await _pointParentTo(row.rootMessageId, chosen.id);
    // 从新选中的节点顺着 current_message_id 找到新的叶子。
    var leaf = chosen;
    final guard = <String>{leaf.id};
    while (true) {
      final childId = leaf.currentMessageId;
      if (childId == null || childId.isEmpty) break;
      final child = _rowById(childId);
      if (child == null || !guard.add(child.id)) break;
      leaf = child;
    }
    await _db.setSessionCurrentMessage(_sessionId, leaf.id);
    await _refreshChain();
  }

  /// 删除一条消息（连同它的所有后续分支）。
  Future<void> deleteMessage(String messageId) async {
    if (_streaming) return;
    final row = _rowById(messageId);
    if (row == null) return;
    final doomed = _descendantIds(messageId);
    final parentId = row.rootMessageId;
    if (parentId != null && parentId.isNotEmpty) {
      final remaining = _siblingsOf(row)
          .where((s) => !doomed.contains(s.id))
          .toList(growable: false);
      await _setCurrentChild(
        parentId,
        remaining.isEmpty ? null : remaining.last.id,
      );
    }
    for (final id in doomed) {
      await _db.deleteMessage(id);
    }
    await _refreshChain();
    // 会话叶子可能指向被删掉的节点：回退到当前链尾。
    final session = await _db.sessionById(_sessionId);
    final leafId = session?.currentMessageId;
    if (leafId == null || _rowById(leafId) == null) {
      final nextLeaf = _chain.isEmpty ? null : _chain.last.id;
      await _db.setSessionCurrentMessage(_sessionId, nextLeaf);
      await _refreshChain();
    }
  }

  /// 切换当前会话的平台（会话级，不改全局设置）。
  Future<void> setProvider(String? providerId) async {
    _providerOverrideId = (providerId == null || providerId.isEmpty)
        ? null
        : providerId;
    final provider = _resolveProvider();
    // 换平台后重新算生效的思考开关（会话覆盖仍优先，只是要再过一次能力位）。
    _thinkingEnabled = _effectiveThinking(provider);
    state = state.copyWith(
      providerId: provider?.id ?? '',
      providerName: provider?.name ?? '',
      model: _currentModel(provider, ref.read(settingsProvider)),
      canAttach: provider?.supportsFiles ?? false,
      searchEnabled: _searchEnabled && (provider?.supportsSearch ?? false),
      thinkingEnabled: _thinkingEnabled,
      thinkingLevel: _effectiveThinkingLevel,
      contextKeepRounds: _effectiveContextRounds,
    );
  }

  /// 切换当前模型（会话级）。
  Future<void> setModel(String model) async {
    _modelOverride = model.trim().isEmpty ? null : model.trim();
    state = state.copyWith(model: _modelOverride ?? state.model);
  }

  /// 会话级联网搜索开关（落 `sessions.search_enabled`）。
  Future<void> setSearchEnabled(bool enabled) async {
    final provider = _resolveProvider();
    final next = enabled && (provider?.supportsSearch ?? false);
    _searchEnabled = next;
    _sessionSearchEnabled = next;
    state = state.copyWith(searchEnabled: next);
    if (_sessionId.isNotEmpty) {
      await _db.setSessionSearchEnabled(_sessionId, next);
    }
  }

  /// 深度思考开关（**会话级覆盖**，写 `sessions.thinking_enabled`）。
  ///
  /// 聊天页只改当前会话；全局设置里的值只作为新会话的默认值，设置页仍然读写它。
  Future<void> setThinkingEnabled(bool enabled) async {
    final provider = _resolveProvider();
    _sessionThinkingEnabled = enabled && (provider?.supportsThinking ?? false);
    _publishEffective(force: true);
    if (_sessionId.isNotEmpty) {
      await _db.setSessionThinkingEnabled(_sessionId, _sessionThinkingEnabled);
    }
  }

  /// 思考强度（**会话级覆盖**，写 `sessions.thinking_level`）。
  ///
  /// 选档位 = 在当前会话打开深度思考（老行为），但同样只写会话，不改全局默认值。
  Future<void> setThinkingLevel(ThinkingLevel level) async {
    _sessionThinkingLevel = level;
    final provider = _resolveProvider();
    if (provider?.supportsThinking ?? false) _sessionThinkingEnabled = true;
    _publishEffective(force: true);
    if (_sessionId.isNotEmpty) {
      await _db.setSessionThinkingLevel(_sessionId, level.wireName);
      if (_sessionThinkingEnabled == true) {
        await _db.setSessionThinkingEnabled(_sessionId, true);
      }
    }
  }

  /// 上下文预算（**会话级覆盖**，写 `sessions.context_keep_rounds`；
  /// `<= 0` = 不限制）。
  Future<void> setContextKeepRounds(int rounds) async {
    _sessionContextRounds = rounds < 0 ? 0 : rounds;
    _publishEffective(force: true);
    if (_sessionId.isNotEmpty) {
      await _db.setSessionContextKeepRounds(_sessionId, _sessionContextRounds);
    }
  }

  /// 清空当前会话的全部覆盖值（三列写 `NULL`），回落到全局默认。
  ///
  /// 「恢复默认」入口用；聊天页暂时没有这个按钮，但语义已经在这里准备好。
  Future<void> resetSessionOverrides() async {
    _sessionThinkingEnabled = null;
    _sessionThinkingLevel = null;
    _sessionContextRounds = null;
    _publishEffective(force: true);
    if (_sessionId.isNotEmpty) {
      await _db.setSessionThinkingEnabled(_sessionId, null);
      await _db.setSessionThinkingLevel(_sessionId, null);
      await _db.setSessionContextKeepRounds(_sessionId, null);
    }
  }

  /// 添加一个待发送附件（本地文件路径）。返回错误文案（成功返回 null）。
  Future<String?> addAttachment(
    String path, {
    String? fileName,
    int? fileSize,
    String? mime,
    int? width,
    int? height,
  }) async {
    if (path.trim().isEmpty) {
      return attachments.AttachmentRules.missingFileMessage(path);
    }
    final name = fileName ?? attachments.AttachmentRules.fileNameOf(path);
    final size = fileSize ?? 0;
    final ruleError = attachments.AttachmentRules.validate(
      fileName: name,
      fileSize: size,
      mime: mime,
    );
    if (ruleError != null) return ruleError;
    if (state.pendingAttachments.length >=
        attachments.AttachmentRules.maxPerMessage) {
      return attachments.AttachmentRules.tooManyMessage;
    }
    if (state.pendingAttachments.any((a) => a.path == path)) return null;
    final view = ChatAttachmentView(
      id: _uuid.v4(),
      fileName: name,
      fileSize: size,
      mime: mime ?? attachments.AttachmentRules.mimeOf(name),
      path: path,
      width: width,
      height: height,
    );
    state = state.copyWith(
      pendingAttachments: <ChatAttachmentView>[
        ...state.pendingAttachments,
        view,
      ],
    );
    return null;
  }

  /// 移除一个待发送附件。
  void removeAttachment(String id) {
    state = state.copyWith(
      pendingAttachments: state.pendingAttachments
          .where((a) => a.id != id)
          .toList(growable: false),
    );
  }

  /// 清空待发送附件。
  void clearAttachments() =>
      state = state.copyWith(pendingAttachments: const <ChatAttachmentView>[]);

  /// 关闭错误条。
  void dismissError() => state = state.copyWith(error: null);

  /// 刷新消息树（外部导入/切换分支后调用）。
  Future<void> refresh() => _refreshChain();

  // -------------------------------------------------------------------------
  // 发送 / 生成
  // -------------------------------------------------------------------------

  /// `send` 的实际实现（符号表 `_send`）。
  Future<void> _send(String text) async {
    final provider = _resolveProvider();
    final problem = _providerProblem(provider);
    if (problem != null) {
      state = state.copyWith(error: problem);
      return;
    }
    if (_sessionId.isEmpty || provider == null) return;
    state = state.copyWith(error: null);

    // 1) 待发送附件先上传（DeepSeek Files API）。
    List<ChatAttachmentView> uploaded;
    try {
      uploaded = await _uploadPending(provider);
    } on _UploadAbort catch (abort) {
      state = state.copyWith(uploading: false, error: abort.message);
      await _refreshChain();
      return;
    }
    if (_disposed) return;

    // 2) 会话标题：第一条用户消息自动命名。
    if (_title.trim().isEmpty) {
      _title = _titleFrom(text);
      await _db.renameSession(_sessionId, _title);
    }

    // 3) 落 user 消息（父 = 当前叶子）。
    final parentId = _chain.isEmpty ? null : _chain.last.id;
    final userId = _uuid.v4();
    final userBlocks = <blk.ContentBlock>[
      if (text.isNotEmpty) blk.ContentBlock.text(text),
      for (final attachment in uploaded)
        blk.ContentBlock.fromAttachment(attachment.toAttachment()),
    ];
    await _db.addMessage(
      id: userId,
      sessionId: _sessionId,
      role: ChatRole.user,
      content: blk.encodeBlocks(userBlocks),
      rootMessageId: parentId,
      index: _nextIndex(),
    );
    await _pointParentTo(parentId, userId);
    await _db.setSessionCurrentMessage(_sessionId, userId);
    // 附件落库（带 messageId，便于导出/重发）。
    for (final attachment in uploaded) {
      final entity = attachment.toAttachment(
        sessionId: _sessionId,
        messageId: userId,
      );
      await _db.upsertAttachment(
        id: entity.id,
        sessionId: _sessionId,
        messageId: userId,
        fileName: entity.fileName,
        fileSize: entity.fileSize,
        mime: entity.mime,
        path: entity.path,
        width: entity.width,
        height: entity.height,
        fileId: entity.fileId,
        url: entity.url,
      );
    }
    state = state.copyWith(
      pendingAttachments: const <ChatAttachmentView>[],
      error: null,
    );
    await _refreshChain();

    // 4) 建 assistant 占位并开始流式生成。
    await _startAssistantReply(parentId: userId);
  }

  /// 新建一条 assistant 占位消息并跑一次 completion。
  Future<void> _startAssistantReply({required String parentId}) async {
    final assistantId = _uuid.v4();
    await _db.addMessage(
      id: assistantId,
      sessionId: _sessionId,
      role: ChatRole.assistant,
      content: '',
      rootMessageId: parentId,
      index: _nextIndex(),
    );
    await _pointParentTo(parentId, assistantId);
    await _db.setSessionCurrentMessage(_sessionId, assistantId);
    await _refreshChain();
    await _runCompletion(assistantId: assistantId, parentId: parentId);
  }

  /// 真正发请求、处理流式事件（符号表 `_runCompletion`）。
  Future<void> _runCompletion({
    required String assistantId,
    required String parentId,
  }) async {
    final provider = _resolveProvider();
    final problem = _providerProblem(provider);
    if (provider == null || problem != null) {
      await _db.deleteMessage(assistantId);
      state = state.copyWith(error: problem ?? '还没有配置 AI 平台，去设置里添加一个');
      await _refreshChain();
      return;
    }

    final settings = ref.read(settingsProvider);
    final model = _currentModel(provider, settings);
    // 重置流式缓冲。
    _streamText.clear();
    _streamThinking.clear();
    _streamBlocks.clear();
    _streamSources = const <ChatSearchSource>[];
    _thinkingStartedAt = null;
    _searchRunning = false;
    _usage = UsageTotals.empty;
    _usageDelta = UsageDelta.zero;
    _pendingError = null;
    _finalErrorText = null;
    _stopped = false;
    _finalizing = false;
    _streaming = true;
    _streamingId = assistantId;

    final backend = _createBackend(provider);
    _backend = backend;

    try {
      final request = await _buildRequest(
        backend: backend,
        provider: provider,
        model: model,
        settings: settings,
        upToMessageId: parentId,
      );
      state = state.copyWith(
        streaming: true,
        streamingMessageId: assistantId,
        thinking: false,
        thinkingText: '',
        searching: false,
        searchSources: const <ChatSearchSource>[],
        error: null,
        providerId: provider.id,
        providerName: provider.name,
        model: model,
      );
      _notify();
      final stream = backend.streamChat(request);
      final token = ++_streamToken;
      _sub = stream.listen(
        (ChatEvent event) {
          if (token != _streamToken) return;
          _applyEvent(event);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (token != _streamToken) return;
          unawaited(_onStreamError(error, stackTrace));
        },
        onDone: () {
          if (token != _streamToken) return;
          unawaited(_onStreamDone());
        },
        cancelOnError: false,
      );
    } catch (error) {
      _pendingError = error is ApiError ? error : null;
      final message = _errorMessageOf(error);
      _finalErrorText = message;
      state = state.copyWith(error: message);
      await _persistFinal(error: true);
    }
  }

  /// 组装一次请求（上下文裁剪 + 摘要注入 + 附件）。
  Future<ChatRequest> _buildRequest({
    required ChatBackend backend,
    required AiProvider provider,
    required String model,
    required Settings settings,
    required String upToMessageId,
  }) async {
    // 只带到 parentId 为止的链（不含正在生成的 assistant 占位）。
    final historyRows = _buildChain(_allRows, upToMessageId);
    final history = <ChatTurn>[];
    final historyIds = <String>[];
    for (final row in historyRows) {
      if (row.role == ChatRole.system) continue;
      final blocks = blk.decodeBlocks(row.content);
      final content = blk.blocksToApi(blocks);
      if (content.trim().isEmpty) continue;
      history.add(
        ChatTurn(
          role: row.role,
          content: content,
          // 带 tools 的多轮请求必须回传历史轮的 reasoning_content，
          // 否则官方返回 400；思考原文直接取落库的 thinking block。
          reasoningContent: row.role == ChatRole.assistant
              ? blk.thinkingTextOf(blocks)
              : null,
        ),
      );
      historyIds.add(row.id);
    }

    // 摘要缓存（batch C summarizer 的 store 适配）。
    final store = _summaryStore();
    String? summary;
    try {
      final cached = await store.cacheOf(_sessionId);
      final text = cached?.text.trim() ?? '';
      summary = text.isEmpty ? null : text;
    } catch (_) {
      summary = null;
    }

    var context = ContextBuilder(
      keepRounds: _effectiveContextRounds,
      systemPrompt: settings.resolvedSystemPrompt,
    ).buildContext(history: history, summary: summary);

    // 超窗：把被裁掉的旧历史压成 ≤600 字摘要（prompts.md §2）。
    if (context.needsSummary && context.droppedTurns.isNotEmpty) {
      try {
        final record = await ensureSummary(
          store: store,
          sessionId: _sessionId,
          olderTurns: context.droppedTurns,
          existingSummary: context.injectedSummary,
          backend: backend,
        );
        final nextSummary = record.summary.trim();
        if (nextSummary.isNotEmpty) {
          summary = nextSummary;
          context = ContextBuilder(
            keepRounds: settings.contextKeepRounds,
            systemPrompt: settings.resolvedSystemPrompt,
          ).buildContext(history: history, summary: summary);
        }
      } catch (_) {
        // 摘要失败不影响本次请求（旧摘要/不注入摘要都能继续）。
      }
    }

    final turnAttachments = <attachments.Attachment>[
      for (final view
          in _attachmentsByMessage[upToMessageId] ??
              const <ChatAttachmentView>[])
        if (view.uploaded)
          view.toAttachment(sessionId: _sessionId, messageId: upToMessageId),
    ];

    // ---- 自带大脑：人格/情绪 + 工作记忆召回（失败静默，退化成普通聊天）----
    // 顺序：默认 system（含摘要）→ 人格/情绪 → 相关回忆；超预算时优先砍回忆。
    var systemContent = context.system?.content ?? settings.resolvedSystemPrompt;
    // 旧轮次被裁掉时告诉模型「更早的还在长期记忆里」，避免它以为对话从最近开始。
    if (context.droppedCount > 0 && !systemContent.contains('已存入长期记忆')) {
      systemContent =
          '$systemContent\n\n【更早的 ${context.droppedCount} 轮对话已存入长期记忆，需要时可检索】';
    }
    try {
      // 角色卡：情绪 / 人格 / 记忆只读写当前会话绑定的角色（没有就按需建默认卡）。
      final character = await CharacterService(ref.read(databaseProvider))
          .ensureForSession(_sessionId);
      final injection = await ref
          .read(brainServiceProvider)
          .buildInjection(
            config: _brainConfig(settings),
            characterId: character.id,
            sessionId: _sessionId,
            currentInput: _lastUserTextOf(history),
            recentUserTexts: _recentUserTextsOf(history, 2),
            recentMessageIds: _recentMessageIdsOf(
              historyIds,
              context.messages.length,
            ),
            baseSystemChars: systemContent.length,
          );
      if (!injection.isEmpty) {
        systemContent = '$systemContent\n\n${injection.text}';
      }
    } catch (_) {
      // 大脑不可用时不影响对话：用原来的 system prompt。
    }

    return ChatRequest(
      provider: provider,
      messages: context.messages,
      systemPrompt: systemContent,
      model: model,
      thinking: _thinkingEnabled && provider.supportsThinking,
      thinkingLevel: _effectiveThinkingLevel.label,
      search: _searchEnabled && provider.supportsSearch,
      attachments: turnAttachments,
    );
  }

  /// 设置 → 大脑配置（只搬三个开关；细项用 `BrainConfig` 默认值）。
  BrainConfig _brainConfig(Settings settings) => BrainConfig(
        memoryEnabled: settings.memoryEnabled,
        moodEnabled: settings.moodEnabled,
        personaEnabled: settings.personaEnabled,
      );

  /// 历史里最后一条 user 文本（本轮输入）。
  String _lastUserTextOf(List<ChatTurn> history) {
    for (var i = history.length - 1; i >= 0; i--) {
      if (history[i].isUser) return history[i].content;
    }
    return '';
  }

  /// 历史里最近 [count] 条 user 文本（不含最后一条 = 本轮输入）。
  List<String> _recentUserTextsOf(List<ChatTurn> history, int count) {
    final users = <String>[
      for (final turn in history)
        if (turn.isUser) turn.content,
    ];
    if (users.length <= 1) return const <String>[];
    final previous = users.sublist(0, users.length - 1);
    if (previous.length <= count) return previous;
    return previous.sublist(previous.length - count);
  }

  /// 本轮上下文里保留的消息 id（这些不再参与召回，避免和上下文重复）。
  Set<String> _recentMessageIdsOf(List<String> historyIds, int keptCount) {
    if (historyIds.isEmpty || keptCount <= 0) return const <String>{};
    final start = historyIds.length - keptCount;
    final from = start < 0 ? 0 : start;
    return historyIds.sublist(from).toSet();
  }

  /// 流式事件入口（符号表 `_applyEvent`）：文本/思考增量在这里，其余转给
  /// [_handleNonBlockEvent]。
  void _applyEvent(ChatEvent event) {
    // 「停止」已发出（或正在收尾）后到达的事件一律丢弃。
    if (_stopped || _finalizing) return;
    switch (event) {
      case TextDelta(:final String text):
        if (text.isEmpty) return;
        _streamText.write(text);
        _scheduleNotify();
      case ThinkingDelta(:final String text):
        if (text.isEmpty) return;
        _streamThinking.write(text);
        _thinkingStartedAt ??= DateTime.now();
        _scheduleNotify();
      default:
        _handleNonBlockEvent(event);
    }
  }

  /// 非文本块事件：usage / 联网搜索 / done / failure（符号表 `_handleNonBlockEvent`）。
  void _handleNonBlockEvent(ChatEvent event) {
    if (_stopped || _finalizing) return;
    if (event is Usage) {
      _usageDelta = _usageDelta + event.usage;
      _recomputeUsage();
      _scheduleNotify();
      return;
    }
    if (event is ToolResult) {
      _searchRunning = event.running;
      if (event.running) {
        _scheduleNotify();
        return;
      }
      final sources = <ChatSearchSource>[..._streamSources];
      for (final source in event.sources) {
        final url = source.url.trim();
        if (url.isEmpty) continue;
        if (sources.any((s) => s.url == url)) continue;
        sources.add(
          ChatSearchSource(
            url: url,
            title: source.title,
            snippet: source.snippet,
            siteName: source.siteName,
            publishedAt: source.publishedAt,
          ),
        );
        _streamBlocks.add(
          blk.ContentBlock.searchResult(
            url: url,
            title: source.title,
            snippet: source.snippet,
            siteName: source.siteName,
            publishedAt: source.publishedAt,
            tool: true,
            toolName: event.tool,
          ),
        );
      }
      _streamSources = List<ChatSearchSource>.unmodifiable(sources);
      if (event.citations.isNotEmpty) {
        final marks = <CitationMark>[..._streamCitations];
        for (final mark in event.citations) {
          if (marks.any((m) => m.url == mark.url && m.end == mark.end)) continue;
          marks.add(mark);
        }
        _streamCitations = List<CitationMark>.unmodifiable(marks);
      }
      if (event.text.trim().isNotEmpty && sources.isEmpty) {
        // 只有正文没有来源时，保留一段文本块，避免搜索结果丢失。
        _streamBlocks.add(blk.ContentBlock.text(event.text.trim()));
      }
      _scheduleNotify();
      return;
    }
    if (event is Done) {
      // 结束标记；收尾统一走 onDone。
      return;
    }
    if (event is Failure) {
      _pendingError = event.error;
      _scheduleNotify();
    }
  }

  Future<void> _onStreamError(Object error, StackTrace stackTrace) async {
    if (_finalizing || _stopped) return;
    if (error is ApiError) {
      _pendingError = error;
      if (error.isCancelled) {
        await _persistFinal(cancelled: true);
        return;
      }
    }
    final message = _errorMessageOf(error);
    _finalErrorText = message;
    state = state.copyWith(error: message);
    await _persistFinal(error: true);
  }

  Future<void> _onStreamDone() async {
    if (_finalizing || _stopped) return;
    final error = _pendingError;
    if (error != null && !error.isCancelled) {
      final message = _errorMessageOf(error);
      _finalErrorText = message;
      state = state.copyWith(error: message);
      await _persistFinal(error: true);
      return;
    }
    await _persistFinal(cancelled: _stopped || (error?.isCancelled ?? false));
  }

  /// 把本次流式结果落库（符号表 `_persistFinal`）。
  Future<void> _persistFinal({
    bool error = false,
    bool cancelled = false,
  }) async {
    if (_finalizing) return;
    _finalizing = true;
    _streaming = false;
    _searchRunning = false;
    final assistantId = _streamingId;
    final text = _streamText.toString().trim();
    final markedText = _applyCitationMarkers(text);
    final thinking = _streamThinking.toString().trim();
    final elapsed = _thinkingStartedAt == null
        ? null
        : DateTime.now().difference(_thinkingStartedAt!).inMilliseconds /
              1000.0;
    final contentBlocks = <blk.ContentBlock>[
      if (thinking.isNotEmpty)
        blk.ContentBlock.thinking(thinking, elapsedSeconds: elapsed),
      if (markedText.isNotEmpty) blk.ContentBlock.text(markedText),
      ..._streamBlocks,
    ];

    // 用量统计（成功/失败都记，token 已经消耗了）。
    if (_usageDelta.isNotEmpty) {
      _recomputeUsage();
      unawaited(_recordUsage(_usageDelta));
    }

    final flags = error ? MessageFlag.error : 0;
    if (assistantId != null) {
      if (contentBlocks.isEmpty && !error) {
        // 一个字都没收到（例如立刻停止）：不留空消息。
        await _db.deleteMessage(assistantId);
      } else if (contentBlocks.isEmpty && error) {
        await _replaceAssistant(assistantId, <blk.ContentBlock>[
          blk.ContentBlock.text(_finalErrorText ?? kConnectionLostMessage),
        ], flags: MessageFlag.error);
      } else {
        await _replaceAssistant(assistantId, contentBlocks, flags: flags);
      }
    }

    // 重置流式字段。
    _streamingId = null;
    _streamText.clear();
    _streamThinking.clear();
    _streamBlocks.clear();
    _streamSources = const <ChatSearchSource>[];
    _streamCitations = const <CitationMark>[];
    _thinkingStartedAt = null;
    _pendingError = null;
    _finalErrorText = null;
    _finalizing = false;
    _sub = null;
    final backend = _backend;
    _backend = null;
    backend?.dispose();
    if (_disposed) return;
    await _refreshChain();
    // 后台消化（情绪 / 人格 / 事实 / episode）：静默、不阻塞 UI。
    if (assistantId != null) {
      unawaited(_brainObserveTurn(assistantId, hadError: error));
    }
  }

  /// 在正文引用位置插入 `[n]` 角标（对应官方「[5][7]」样式），编号按来源顺序。
  ///
  /// 从后往前插，避免前面的插入把后面的下标推偏。
  String _applyCitationMarkers(String text) {
    if (text.isEmpty || _streamCitations.isEmpty) return text;
    final order = <String, int>{};
    for (final source in _streamSources) {
      order.putIfAbsent(source.url, () => order.length + 1);
    }
    for (final mark in _streamCitations) {
      order.putIfAbsent(mark.url, () => order.length + 1);
    }
    final marks = _streamCitations
        .where((m) => m.end > 0 && m.end <= text.length)
        .toList()
      ..sort((a, b) => b.end.compareTo(a.end));
    var out = text;
    var lastEnd = -1;
    for (final mark in marks) {
      if (mark.end == lastEnd) continue;
      lastEnd = mark.end;
      out = out.replaceRange(
        mark.end,
        mark.end,
        ' [${order[mark.url] ?? 1}]',
      );
    }
    return out;
  }

  /// 一轮落库后把原文交给大脑整理（失败静默）。
  ///
  /// 用户文本取 assistant 的父消息（同一轮 user）；助手文本取刚落库的 assistant。
  /// 错误/空回复不抽 self 侧事实，但仍会更新情绪（用户那句是真的）。
  Future<void> _brainObserveTurn(
    String assistantId, {
    bool hadError = false,
  }) async {
    try {
      if (_disposed || _sessionId.isEmpty) return;
      final settings = ref.read(settingsProvider);
      final config = _brainConfig(settings);
      if (!config.anyEnabled) return;
      final assistantRow = _rowById(assistantId);
      if (assistantRow == null) return;
      final parent = _rowById(assistantRow.rootMessageId);
      if (parent == null || parent.role != ChatRole.user) return;
      final userText = BrainStore.messageText(parent.content);
      if (userText.isEmpty) return;
      final assistantText =
          hadError ? '' : BrainStore.messageText(assistantRow.content);
      final character = await CharacterService(ref.read(databaseProvider))
          .ensureForSession(_sessionId);
      await ref.read(brainServiceProvider).observeTurn(
            config: config,
            characterId: character.id,
            sessionId: _sessionId,
            turnMessageIds: <String>[parent.id, assistantId],
            userText: userText,
            assistantText: assistantText,
          );
    } catch (_) {
      // 后台整理失败不影响聊天。
    }
  }

  /// 把 assistant 消息的内容替换掉（符号表 `_replaceAssistant`）。
  Future<void> _replaceAssistant(
    String assistantId,
    List<blk.ContentBlock> contentBlocks, {
    int flags = 0,
  }) async {
    final content = blk.encodeBlocks(contentBlocks);
    await _db.updateMessage(assistantId, content: content, flags: flags);
    // 同步内存缓存，避免必须等 DB 重读。
    _allRows = <Message>[
      for (final row in _allRows)
        if (row.id == assistantId)
          Message(
            id: row.id,
            sessionId: row.sessionId,
            role: row.role,
            content: content,
            createdAt: row.createdAt,
            rootMessageId: row.rootMessageId,
            currentMessageId: row.currentMessageId,
            index: row.index,
            flags: flags,
          )
        else
          row,
    ];
  }

  /// 重新生成（符号表 `_regenerate`）：新建分支而不是覆盖旧回答。
  Future<void> _regenerate(String? messageId) async {
    if (_streaming || _sessionId.isEmpty) return;
    final target = messageId == null
        ? _lastAssistantRow()
        : _rowById(messageId);
    if (target == null) return;
    if (target.role != ChatRole.assistant) {
      // 传进来的是一条 user 消息：它没有回答就补一个回答，有回答就重生成那个回答。
      final child = _rowById(target.currentMessageId);
      if (child != null && child.role == ChatRole.assistant) {
        return _regenerate(child.id);
      }
      await _startAssistantReply(parentId: target.id);
      return;
    }
    final parentId = target.rootMessageId ?? '';
    final assistantId = _uuid.v4();
    final index = _nextIndex();
    await _db.addMessage(
      id: assistantId,
      sessionId: _sessionId,
      role: ChatRole.assistant,
      content: '',
      rootMessageId: parentId.isEmpty ? null : parentId,
      index: index,
    );
    await _pointParentTo(parentId, assistantId);
    await _db.setSessionCurrentMessage(_sessionId, assistantId);
    await _refreshChain();
    await _runCompletion(assistantId: assistantId, parentId: parentId);
  }

  // -------------------------------------------------------------------------
  // 消息树 / 状态转换
  // -------------------------------------------------------------------------

  /// 从 DB 重读整棵树，重建当前分支链（符号表 `_refreshChain`）。
  Future<void> _refreshChain() async {
    if (_sessionId.isEmpty || _disposed) return;
    try {
      final session = await _db.sessionById(_sessionId);
      var rows = await _db.messagesOf(_sessionId);
      if (rows.isEmpty) {
        // 导入被中断（进程被杀 / ANR）的会话：打开时优先补这一条正文，再重读。
        final bool imported = await ref
            .read(importTaskProvider)
            .ensureSessionImported(_sessionId);
        if (imported) rows = await _db.messagesOf(_sessionId);
      }
      final attachmentRows = await _db.attachmentsOfSession(_sessionId);
      if (_disposed) return;
      _title = session?.title ?? _title;
      _allRows = rows;
      _attachmentsByMessage = _groupAttachments(attachmentRows);
      if (!_loaded) {
        _loaded = true;
        final settings = ref.read(settingsProvider);
        _sessionSearchEnabled = session?.searchEnabled;
        _searchEnabled = _sessionSearchEnabled ?? settings.searchEnabled;
        // 读会话级覆盖值（列值为 NULL = 未覆盖，回落到全局设置里的默认值）。
        // 注意：这里只“读”，全局设置的变化不会反过来写这些字段。
        _sessionThinkingEnabled = session?.thinkingEnabled;
        _sessionThinkingLevel = ThinkingLevel.tryParse(session?.thinkingLevel);
        _sessionContextRounds = session?.contextKeepRounds;
        final provider = _resolveProvider();
        _thinkingEnabled = _effectiveThinking(provider);
      }
      final leafId = _validLeaf(session?.currentMessageId, rows);
      _chain = _buildChain(rows, leafId);
      _notify();
    } catch (error) {
      if (_disposed) return;
      state = state.copyWith(loading: false, error: '数据加载失败：$error');
    }
  }

  /// 行数据 → UI 视图（符号表 `_toUi`）。
  List<ChatMessage> _toUi() {
    final rows = _chain;
    if (rows.isEmpty) return const <ChatMessage>[];
    final result = <ChatMessage>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final siblings = _siblingsOf(row);
      final branchIndex = math.max(
        1,
        siblings.indexWhere((s) => s.id == row.id) + 1,
      );
      final isStreamingRow = _streaming && row.id == _streamingId;
      final decoded = blk.decodeBlocks(row.content);
      final contentBlocks = <blk.ContentBlock>[...decoded];
      final text = _textOfBlocks(decoded);
      final thinkingBlock = _firstThinking(decoded);
      var thinking = thinkingBlock?.plainText ?? '';
      var thinkingSeconds = thinkingBlock?.elapsedSeconds;
      var searchSources = _sourcesOf(decoded);
      var liveText = text;

      if (isStreamingRow) {
        // 流式中的这一条用内存缓冲覆盖 DB 里的空内容。
        final streamedText = _streamText.toString();
        final streamedThinking = _streamThinking.toString().trim();
        if (streamedThinking.isNotEmpty) thinking = streamedThinking;
        if (streamedText.trim().isNotEmpty) {
          contentBlocks.removeWhere((b) => b.type == blk.BlockType.text);
          contentBlocks.add(blk.ContentBlock.text(streamedText));
          liveText = streamedText;
        }
        if (_streamSources.isNotEmpty) searchSources = _streamSources;
        if (_thinkingStartedAt != null) {
          thinkingSeconds =
              DateTime.now().difference(_thinkingStartedAt!).inMilliseconds /
              1000.0;
        }
      }

      result.add(
        ChatMessage(
          id: row.id,
          role: row.role,
          createdAt: row.createdAt,
          text: liveText,
          thinking: thinking,
          thinkingSeconds: thinkingSeconds,
          blocks: contentBlocks,
          attachments:
              _attachmentsByMessage[row.id] ?? const <ChatAttachmentView>[],
          searchSources: searchSources,
          flags: row.flags,
          streaming: isStreamingRow,
          thinkingNow:
              isStreamingRow &&
              _streamThinking.isNotEmpty &&
              _streamText.isEmpty,
          searchingNow: isStreamingRow && _searchRunning,
          branchIndex: branchIndex,
          branchCount: siblings.length,
          isLeaf: i == rows.length - 1,
        ),
      );
    }
    return List<ChatMessage>.unmodifiable(result);
  }

  /// 把当前内存状态发布成新的 `ChatUiState`（符号表 `_notify`）。
  void _notify() {
    _notifyTimer?.cancel();
    _notifyTimer = null;
    if (_disposed) return;
    final settings = ref.read(settingsProvider);
    final provider = _resolveProvider();
    final messages = _toUi();
    final last = messages.isEmpty ? null : messages.last;
    state = state.copyWith(
      sessionId: _sessionId,
      title: _title,
      messages: messages,
      loading: false,
      streaming: _streaming,
      thinking: _streaming && _streamThinking.isNotEmpty,
      thinkingText: _streamThinking.toString(),
      searching: _streaming && _searchRunning,
      searchSources: _streamSources,
      usage: _usage,
      providerId: provider?.id ?? '',
      providerName: provider?.name ?? '',
      model: _currentModel(provider, settings),
      branchIndex: last?.branchIndex ?? 1,
      branchCount: last?.branchCount ?? 1,
      canAttach: provider?.supportsFiles ?? false,
      searchEnabled: _searchEnabled && (provider?.supportsSearch ?? false),
      thinkingEnabled: _thinkingEnabled,
      thinkingLevel: _effectiveThinkingLevel,
      contextKeepRounds: _effectiveContextRounds,
      streamingMessageId: _streamingId,
    );
  }

  /// 流式高频回调的合并通知（60ms 一次，避免每 token 重建整页）。
  void _scheduleNotify() {
    if (_disposed || _notifyTimer != null) return;
    _notifyTimer = Timer(const Duration(milliseconds: 60), () {
      _notifyTimer = null;
      if (!_disposed) _notify();
    });
  }

  // -------------------------------------------------------------------------
  // 树工具
  // -------------------------------------------------------------------------

  /// 按 id 取行（符号表 `_rowById`）。
  Message? _rowById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final row in _allRows) {
      if (row.id == id) return row;
    }
    return null;
  }

  Message? _lastAssistantRow() {
    for (var i = _chain.length - 1; i >= 0; i--) {
      if (_chain[i].role == ChatRole.assistant) return _chain[i];
    }
    return null;
  }

  /// 下一个写入序号（同一会话内递增）。
  int _nextIndex() {
    var max = -1;
    for (final row in _allRows) {
      if (row.index > max) max = row.index;
    }
    return max + 1;
  }

  /// 同父兄弟（按 `index` 升序）。
  List<Message> _siblingsOf(Message row) {
    final parent = row.rootMessageId ?? '';
    final siblings = <Message>[
      for (final candidate in _allRows)
        if ((candidate.rootMessageId ?? '') == parent) candidate,
    ]..sort((a, b) => a.index.compareTo(b.index));
    return siblings;
  }

  /// 从 [leafId] 沿 `root_message_id`（父指针）回溯出 root → leaf 的链。
  List<Message> _buildChain(List<Message> rows, String? leafId) {
    if (rows.isEmpty) return const <Message>[];
    final byId = <String, Message>{for (final row in rows) row.id: row};
    var current = leafId == null ? null : byId[leafId];
    current ??= rows.last;
    final chain = <Message>[current];
    final guard = <String>{current.id};
    while (true) {
      final parentId = current!.rootMessageId;
      if (parentId == null || parentId.isEmpty) break;
      final parent = byId[parentId];
      if (parent == null || !guard.add(parent.id)) break;
      chain.insert(0, parent);
      current = parent;
    }
    return List<Message>.unmodifiable(chain);
  }

  /// 校验会话叶子：不存在/失效时退回「最后写入的那条」。
  String? _validLeaf(String? leafId, List<Message> rows) {
    if (rows.isEmpty) return null;
    if (leafId != null &&
        leafId.isNotEmpty &&
        rows.any((row) => row.id == leafId)) {
      return leafId;
    }
    return rows.last.id;
  }

  /// [messageId] 及其所有后代 id（删除子树用）。
  Set<String> _descendantIds(String messageId) {
    final result = <String>{messageId};
    var changed = true;
    while (changed) {
      changed = false;
      for (final row in _allRows) {
        final parent = row.rootMessageId ?? '';
        if (parent.isNotEmpty &&
            result.contains(parent) &&
            result.add(row.id)) {
          changed = true;
        }
      }
    }
    return result;
  }

  /// 设置父消息的 `current_message_id`（父为空则什么都不做）。
  Future<void> _pointParentTo(String? parentId, String childId) =>
      _setCurrentChild(parentId, childId);

  /// 设置某条消息的当前子节点（[childId] 为 null 表示叶子）。
  Future<void> _setCurrentChild(String? messageId, String? childId) async {
    if (messageId == null || messageId.isEmpty) return;
    if (childId == null) {
      await _db.updateMessageRow(
        MessagesCompanion(
          id: Value<String>(messageId),
          currentMessageId: const Value<String?>(null),
        ),
      );
      return;
    }
    await _db.updateMessage(messageId, currentMessageId: childId);
  }

  Future<void> _recordUsage(UsageDelta delta) async {
    try {
      final store = await ref.read(usageStoreProvider.future);
      // 全局累计（账号总共消耗）。
      await store.record(delta);
      // 当前会话累计（对话界面的「当前对话」统计）+ 最近一次 prompt tokens。
      final sessionId = _sessionId;
      if (sessionId.isNotEmpty) {
        await store.recordSession(
          sessionId,
          delta,
          promptTokens: delta.inputTokens,
        );
      }
    } catch (_) {
      // 统计写入失败不影响聊天。
    }
  }

  void _recomputeUsage() {
    _usage = UsageTotals(
      inputTokens: _usageDelta.inputTokens,
      outputTokens: _usageDelta.outputTokens,
      cacheReadInputTokens: _usageDelta.cacheReadInputTokens,
      cacheCreationInputTokens: _usageDelta.cacheCreationInputTokens,
      requests: _usageDelta.isEmpty ? 0 : 1,
    );
  }

  /// 附件行按 messageId 归组（草稿没有 messageId，不会出现在这里）。
  Map<String, List<ChatAttachmentView>> _groupAttachments(
    List<Attachment> rows,
  ) {
    final grouped = <String, List<ChatAttachmentView>>{};
    for (final row in rows) {
      final messageId = row.messageId;
      if (messageId == null || messageId.isEmpty) continue;
      grouped
          .putIfAbsent(messageId, () => <ChatAttachmentView>[])
          .add(
            ChatAttachmentView(
              id: row.id,
              fileName: row.fileName,
              fileSize: row.fileSize,
              mime: row.mime,
              path: row.path,
              width: row.width,
              height: row.height,
              fileId: row.fileId,
              url: row.url,
            ),
          );
    }
    return grouped;
  }

  // -------------------------------------------------------------------------
  // 平台 / 模型 / 上下文
  // -------------------------------------------------------------------------

  /// 生效的深度思考开关：会话覆盖 ?? 全局默认，且平台必须支持深度思考。
  ///
  /// 全局设置里的 [Settings.thinkingEnabled] 只是新会话的默认值；当前会话一旦
  /// 有覆盖值（`sessions.thinking_enabled` 非空），设置页改默认值不会影响它。
  bool _effectiveThinking(AiProvider? provider) {
    final override = _sessionThinkingEnabled;
    final base = override ?? ref.read(settingsProvider).thinkingEnabled;
    return base && (provider?.supportsThinking ?? false);
  }

  /// 生效的思考强度：会话覆盖（`sessions.thinking_level`）→ 全局默认。
  ThinkingLevel get _effectiveThinkingLevel =>
      _sessionThinkingLevel ?? ref.read(settingsProvider).thinkingLevel;

  /// 生效的上下文预算：会话覆盖（`sessions.context_keep_rounds`）→ 全局默认。
  int get _effectiveContextRounds =>
      _sessionContextRounds ?? ref.read(settingsProvider).contextKeepRounds;

  /// 把生效值同步进 `ChatUiState`（芯片显示的就是这些值）。
  void _publishEffective({bool force = false}) {
    if (_disposed) return;
    final thinkingEnabled = _effectiveThinking(_resolveProvider());
    _thinkingEnabled = thinkingEnabled;
    final thinkingLevel = _effectiveThinkingLevel;
    final contextRounds = _effectiveContextRounds;
    final current = state;
    if (!force &&
        current.thinkingEnabled == thinkingEnabled &&
        current.thinkingLevel == thinkingLevel &&
        current.contextKeepRounds == contextRounds) {
      return;
    }
    state = current.copyWith(
      thinkingEnabled: thinkingEnabled,
      thinkingLevel: thinkingLevel,
      contextKeepRounds: contextRounds,
    );
  }

  /// 解析当前平台：会话级覆盖 → 设置 → 全局当前（符号表 `_resolveProvider`）。
  AiProvider? _resolveProvider() {
    final book = ref.read(providerBookProvider);
    final settings = ref.read(settingsProvider);
    final overrideId = _providerOverrideId;
    if (overrideId != null && overrideId.isNotEmpty) {
      final provider = book.byId(overrideId);
      if (provider != null) return provider;
    }
    final settingsId = settings.providerId.trim();
    if (settingsId.isNotEmpty) {
      final provider = book.byId(settingsId);
      if (provider != null) return provider;
    }
    return book.current;
  }

  /// 平台是否可用；返回可直接展示的中文问题（符号表 `_providerProblem`）。
  String? _providerProblem(AiProvider? provider) {
    if (provider == null) {
      final book = ref.read(providerBookProvider);
      if (book.isEmpty) return '还没有配置 AI 平台，去设置里添加一个';
      return '选中的平台不存在了，去设置里重新选一个';
    }
    if (!provider.hasBaseUrl) return '先填接口地址';
    if (!provider.hasApiKey) return 'API Key 无效或未填写';
    if (!provider.hasModel && (_modelOverride?.trim().isEmpty ?? true)) {
      return '先填一个模型名';
    }
    return null;
  }

  /// 当前模型：会话级覆盖 → 平台自己 → 设置默认 → `deepseek-flash`。
  String _currentModel(AiProvider? provider, Settings settings) {
    final override = _modelOverride?.trim() ?? '';
    if (override.isNotEmpty) return override;
    final fromProvider = provider?.model.trim() ?? '';
    if (fromProvider.isNotEmpty) return fromProvider;
    final fromSettings = settings.defaultModel.trim();
    if (fromSettings.isNotEmpty) return fromSettings;
    return kDefaultModelName;
  }

  /// 从第一条用户消息生成会话标题。
  String _titleFrom(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return '未命名会话';
    return normalized.length <= 24
        ? normalized
        : '${normalized.substring(0, 24)}…';
  }

  // -------------------------------------------------------------------------
  // 附件上传
  // -------------------------------------------------------------------------

  /// 上传所有待发送附件；失败抛 [_UploadAbort]（UI 显示错误并保留草稿）。
  Future<List<ChatAttachmentView>> _uploadPending(AiProvider provider) async {
    final pending = state.pendingAttachments;
    if (pending.isEmpty) return const <ChatAttachmentView>[];
    if (!provider.supportsFiles) {
      throw const _UploadAbort(kAttachUnsupportedMessage);
    }
    if (state.uploading) return pending;
    state = state.copyWith(uploading: true, error: null);

    final client = ref.read(httpClientFactoryProvider)();
    final uploaded = <ChatAttachmentView>[];
    try {
      for (final view in pending) {
        if (view.uploaded) {
          uploaded.add(view);
          continue;
        }
        state = state.copyWith(
          pendingAttachments: <ChatAttachmentView>[
            for (final item in state.pendingAttachments)
              item.id == view.id
                  ? item.copyWith(status: ChatAttachmentStatus.uploading)
                  : item,
          ],
        );
        try {
          final fileId = await uploadAttachment(
            view.toAttachment(sessionId: _sessionId),
            baseUrl: provider.effectiveBaseUrl,
            apiKey: provider.apiKey,
            client: client,
          );
          final ready = view.copyWith(
            status: ChatAttachmentStatus.ready,
            fileId: fileId,
          );
          uploaded.add(ready);
          state = state.copyWith(
            pendingAttachments: <ChatAttachmentView>[
              for (final item in state.pendingAttachments)
                item.id == view.id ? ready : item,
            ],
          );
        } catch (error) {
          final failed = view.copyWith(
            status: ChatAttachmentStatus.failed,
            error: _errorMessageOf(error),
          );
          state = state.copyWith(
            pendingAttachments: <ChatAttachmentView>[
              for (final item in state.pendingAttachments)
                item.id == view.id ? failed : item,
            ],
          );
          throw _UploadAbort('$kUploadFailedPrefix${_errorMessageOf(error)}');
        }
      }
      return uploaded;
    } finally {
      client.close();
      state = state.copyWith(uploading: false);
    }
  }

  // -------------------------------------------------------------------------
  // 依赖适配区（批次 C 的 API 集中在这里；签名变化只改这一段）
  // -------------------------------------------------------------------------

  /// 建后端（`core/api/chat_backend.dart` 的 `chatBackendFor`）。
  ChatBackend _createBackend(AiProvider provider) {
    final factory = ref.read(httpClientFactoryProvider);
    return chatBackendFor(
      provider,
      clientFactory: factory,
      timeout: const Duration(seconds: 120),
    );
  }

  /// 摘要缓存 store 适配：
  /// `core/chat/summarizer.dart` 的 `DbSummaryCache.fromRows` ↔ drift 的 `summary_caches`。
  SummaryCacheStore _summaryStore() => DbSummaryCache.fromRows(
    loadRow: (String sessionId) => _db.summaryCacheOf(sessionId),
    saveRow: (String sessionId, String contextSummary, int summaryChars) =>
        _db.saveSummaryCache(
          sessionId: sessionId,
          contextSummary: contextSummary,
          summaryChars: summaryChars,
        ),
  );

  /// 从 blocks 里拼 assistant 正文。
  String _textOfBlocks(List<blk.ContentBlock> contentBlocks) {
    final parts = <String>[];
    for (final block in contentBlocks) {
      if (block.type == blk.BlockType.text) {
        final value = block.plainText;
        if (value.isNotEmpty) parts.add(value);
      } else if (block.type == blk.BlockType.mermaid) {
        final value = block.plainText;
        if (value.isNotEmpty) parts.add('```mermaid\n$value\n```');
      }
    }
    return parts.join('\n\n').trim();
  }

  blk.ContentBlock? _firstThinking(List<blk.ContentBlock> contentBlocks) {
    for (final block in contentBlocks) {
      if (block.type == blk.BlockType.thinking) return block;
    }
    return null;
  }

  /// 从内容块里恢复联网搜索来源。
  List<ChatSearchSource> _sourcesOf(List<blk.ContentBlock> contentBlocks) {
    final result = <ChatSearchSource>[];
    for (final block in contentBlocks) {
      if (!block.isSearch) continue;
      final url = (block.url ?? '').trim();
      if (url.isEmpty) continue;
      if (result.any((s) => s.url == url)) continue;
      result.add(
        ChatSearchSource(
          url: url,
          title: block.title,
          snippet: block.snippet,
          siteName: block.siteName,
          publishedAt: block.publishedAt,
        ),
      );
    }
    return result;
  }

  /// 统一错误文案（`ApiError.message` 优先，去掉 Dart 的 `Exception: ` 前缀）。
  String _errorMessageOf(Object error) {
    if (error is ApiError) {
      final message = error.message.trim();
      return message.isEmpty ? kConnectionLostMessage : message;
    }
    final text = error.toString().trim();
    if (text.isEmpty) return '网络错误，请检查网络后重试';
    if (text.startsWith('StateError: ')) {
      return text.substring('StateError: '.length);
    }
    if (text.startsWith('Exception: ')) {
      return text.substring('Exception: '.length);
    }
    return text;
  }
}

/// 附件上传失败时用于中断发送的内部异常。
class _UploadAbort implements Exception {
  const _UploadAbort(this.message);

  final String message;
}
