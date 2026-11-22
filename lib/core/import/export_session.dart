/// Keepsake（留声）— DeepSeek 兼容导出格式的共享模型与（反）序列化。
///
/// 这一层是「导入 / 导出」共用的格式契约：
///
/// - [parseExportSession]：把 DeepSeek 官方导出包里的 `chat_sessions/<id>.json`
///   解析成 [ExportSessionInput]（含消息树 / 分支 / 附件 / `FILE` 片段里的
///   图片 `export_path`）。解析规则与 DeepSeek 官方前端模块 8444 的归一化
///   等价（`_fragmentMessage` / 分支校验 / 时间格式），错误文案照
///   `reports/apk/ui-strings.txt` §9。
/// - [buildSessionJson]：把 [ExportSessionInput] 序列化成 DeepSeek 官方格式的
///   每会话 JSON（消息 id 重编号为整数、`parent_id` / `current_message_id` /
///   `fragments` / `FILE.export_path` 齐全），供 [KeepsakeExporter] 打进 ZIP。
/// - [loadSessionForExport]：从 drift 数据库读出会话 + 消息 + 附件，生成
///   [ExportSessionInput]（消息内容用 `core/chat/blocks.dart` 的 blocks 解码）。
///
/// 版本字段：`export_format_version`（DeepSeek 官方当前为 3，见 [exportFormatVersion]）；
/// 校验函数 [validateExportFormatVersion]，文案：
/// 「文件版本无效，无法导入」/「文件版本过新，请升级后再导入」。
library;

import 'dart:convert';

import 'package:keepsake/core/chat/blocks.dart' hide Attachment;
import 'package:keepsake/core/db/database.dart';

/// DeepSeek 官方导出包当前支持的格式版本（`manifest.json` 的
/// `export_format_version`）。实测导出包为 3。
const int exportFormatVersion = 3;

/// ZIP 内索引文件名（[确定]：libapp.so 字符串 `chat_session_index.json`）。
const String exportIndexFileName = 'chat_session_index.json';

/// ZIP 内清单文件名（`export_format_version` 所在）。
const String exportManifestFileName = 'manifest.json';

/// ZIP 内每会话 JSON 的目录前缀（[确定]：`chat_sessions/`）。
const String exportSessionsDir = 'chat_sessions/';

/// 会话附件目录前缀（[确定]：`chat_sessions/_files/` 片段 + `_N(id)` 拼接）。
String exportFilesDirOf(String sessionId) => '$exportSessionsDir${sessionId}_files/';

/// 导出文件名前缀（[确定]：「Keepsake 导出备份（」）。
const String exportBackupName = 'Keepsake 导出备份';

/// 导入错误的分类（UI 按它决定提示，但 [ExportFormatException.message] 已是中文）。
enum ExportFormatReason {
  /// 选错文件 / 不是 DeepSeek 导出包。
  unrecognized,

  /// 版本太旧 / 缺 `export_format_version`。
  invalidVersion,

  /// 版本比本 App 支持的新。
  newerVersion,

  /// 包不完整（缺会话正文 / 附件 / 字段）。
  incomplete,

  /// 消息分支数据异常。
  invalidBranches,

  /// JSON 损坏。
  invalidJson,
}

/// 可展示的导入格式错误。
class ExportFormatException implements Exception {
  const ExportFormatException(
    this.message, {
    this.reason = ExportFormatReason.incomplete,
    this.cause,
  });

  /// 中文错误文案（可直接 toast）。
  final String message;

  final ExportFormatReason reason;

  /// 底层异常（调试用）。
  final Object? cause;

  @override
  String toString() => message;
}

/// 导入 / 导出文案（照 `ui-strings.txt` §9）。
abstract final class ImportErrorText {
  static const String unrecognized = '无法识别该文件，请选择 DeepSeek 导出的历史对话 ZIP 文件';
  static const String invalidVersion = '文件版本无效，无法导入';
  static const String newerVersion = '文件版本过新，请升级后再导入';
  static const String invalidBranches = '文件中的消息分支已损坏，无法导入';
  static const String incomplete = '文件导入失败，可能是文件格式错误或使用了旧版的导出 ZIP';
  static const String invalidJson = '文件导入失败，可能是文件格式错误或使用了旧版的导出 ZIP';
  static const String nothingNew = '文件中的对话本地都已存在，没有新增';
}

/// 校验 `manifest.json` 里的 `export_format_version`。
void validateExportFormatVersion(Object? value) {
  if (value is num) {
    if (value > exportFormatVersion) {
      throw const ExportFormatException(
        ImportErrorText.newerVersion,
        reason: ExportFormatReason.newerVersion,
      );
    }
    if (value != exportFormatVersion) {
      throw const ExportFormatException(
        ImportErrorText.invalidVersion,
        reason: ExportFormatReason.invalidVersion,
      );
    }
    return;
  }
  throw const ExportFormatException(
    ImportErrorText.invalidVersion,
    reason: ExportFormatReason.invalidVersion,
  );
}

/// 会话附件（DeepSeek `FILE` 片段里的一个文件）。
class ExportAttachmentInput {
  const ExportAttachmentInput({
    required this.id,
    required this.fileName,
    this.fileSize = 0,
    this.mime = '',
    this.isImage = false,
    this.width,
    this.height,
    this.fileId,
    this.url,
    this.exportPath,
    this.localPath,
  });

  /// 文件 id（DeepSeek 导出里的 `files[].id`，也用于 `attachmentByServerId`）。
  final String id;

  /// 原文件名。
  final String fileName;

  final int fileSize;

  /// MIME（导出包里没有，导入时按魔数嗅探 / 导出时按扩展名猜）。
  final String mime;

  final bool isImage;

  final int? width;
  final int? height;

  /// 服务端 id（DeepSeek Files API）；导入时回填 = [id]。
  final String? fileId;

  /// 远程链接（微信图片等；导出包里没有）。
  final String? url;

  /// ZIP 内路径：`chat_sessions/<sessionId>_files/<fileId>_<fileName>`。
  final String? exportPath;

  /// 本地绝对路径（导入写盘后 / 导出读盘前）。
  final String? localPath;

  ExportAttachmentInput copyWith({
    String? id,
    String? fileName,
    int? fileSize,
    String? mime,
    bool? isImage,
    int? width,
    int? height,
    String? fileId,
    String? url,
    String? exportPath,
    String? localPath,
  }) {
    return ExportAttachmentInput(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      mime: mime ?? this.mime,
      isImage: isImage ?? this.isImage,
      width: width ?? this.width,
      height: height ?? this.height,
      fileId: fileId ?? this.fileId,
      url: url ?? this.url,
      exportPath: exportPath ?? this.exportPath,
      localPath: localPath ?? this.localPath,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'file_name': fileName,
        'file_size': fileSize,
        if (mime.isNotEmpty) 'mime': mime,
        'is_image': isImage,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (fileId != null) 'file_id': fileId,
        if (url != null) 'url': url,
        if (exportPath != null) 'export_path': exportPath,
      };

  static ExportAttachmentInput? fromJson(Object? raw) {
    final Map<String, Object?>? map = _asObjectOrNull(raw);
    if (map == null) return null;
    final String id = _asStringOr(map['id'], '');
    if (id.isEmpty) return null;
    return ExportAttachmentInput(
      id: id,
      fileName: _asStringOr(map['file_name'], ''),
      fileSize: _asNonNegativeIntOr(map['file_size'], 0),
      mime: _asStringOr(map['mime'], ''),
      isImage: map['is_image'] == true,
      width: _asIntOrNull(map['width']),
      height: _asIntOrNull(map['height']),
      fileId: _asStringOrNull(map['file_id']),
      url: _asStringOrNull(map['url']),
      exportPath: _asStringOrNull(map['export_path']),
      localPath: _asStringOrNull(map['local_path']),
    );
  }
}

/// 一条消息（DeepSeek 导出格式 ↔ 本地 blocks）。
class ExportMessageInput {
  const ExportMessageInput({
    required this.id,
    required this.role,
    required this.blocks,
    required this.createdAt,
    this.parentId,
    this.rootMessageId,
    this.currentMessageId,
    this.index = 0,
    this.flags = 0,
    this.status = 'done',
    this.thinkingEnabled = false,
    this.searchEnabled = false,
    this.tokenUsage = 0,
    this.attachments = const <ExportAttachmentInput>[],
  });

  /// 本地消息 id（导入时 = `<sessionId>:<DeepSeek 消息 id>`，导出时是 DB 主键）。
  final String id;

  /// 父消息 id；导出时会重编号成整数。
  final String? parentId;

  final String role;

  /// 内容块（`core/chat/blocks.dart`）。
  final List<ContentBlock> blocks;

  final DateTime createdAt;

  /// DB 列 `root_message_id`（= 父节点 / 分支根，见导入侧约定）。
  final String? rootMessageId;

  /// DB 列 `current_message_id`（= 选中的子节点）。
  final String? currentMessageId;

  /// DB 列 `index`（同会话内序号）。
  final int index;

  /// DB 列 `flags`（[MessageFlag]）。
  final int flags;

  /// `done` / `error` / `stopped`（对应 DeepSeek status）。
  final String status;

  final bool thinkingEnabled;
  final bool searchEnabled;
  final int tokenUsage;

  /// 该消息的附件（按 `message_id` 归属）。
  final List<ExportAttachmentInput> attachments;

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  /// 纯文本（blocks 里 text 块拼接；预览 / 搜索用）。
  String get text => blocks
      .where((ContentBlock b) => b.type == BlockType.text)
      .map((ContentBlock b) => b.text ?? '')
      .join('');

  ExportMessageInput copyWith({
    String? id,
    String? parentId,
    String? role,
    List<ContentBlock>? blocks,
    DateTime? createdAt,
    String? rootMessageId,
    String? currentMessageId,
    int? index,
    int? flags,
    String? status,
    bool? thinkingEnabled,
    bool? searchEnabled,
    int? tokenUsage,
    List<ExportAttachmentInput>? attachments,
  }) {
    return ExportMessageInput(
      id: id ?? this.id,
      parentId: parentId ?? this.parentId,
      role: role ?? this.role,
      blocks: blocks ?? this.blocks,
      createdAt: createdAt ?? this.createdAt,
      rootMessageId: rootMessageId ?? this.rootMessageId,
      currentMessageId: currentMessageId ?? this.currentMessageId,
      index: index ?? this.index,
      flags: flags ?? this.flags,
      status: status ?? this.status,
      thinkingEnabled: thinkingEnabled ?? this.thinkingEnabled,
      searchEnabled: searchEnabled ?? this.searchEnabled,
      tokenUsage: tokenUsage ?? this.tokenUsage,
      attachments: attachments ?? this.attachments,
    );
  }
}

/// 一个会话（DeepSeek 导出格式 ↔ 本地 DB）。
class ExportSessionInput {
  const ExportSessionInput({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.messageCount = 0,
    this.currentMessageId,
    this.rootMessageId,
    this.searchEnabled = false,
    this.pinned = false,
    this.messages = const <ExportMessageInput>[],
    this.imagePaths = const <String, String>{},
  });

  /// 会话 id（导入的 DeepSeek 会话保留外部 id）。
  final String id;

  final String title;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// 消息数（导入时以实际写入为准校正；导出时 = [messages].length）。
  final int messageCount;

  /// 选中分支的叶子节点 id。
  final String? currentMessageId;

  /// 分支根 / 链根 id。
  final String? rootMessageId;

  final bool searchEnabled;
  final bool pinned;

  final List<ExportMessageInput> messages;

  /// 图片：ZIP 内 `export_path` → DeepSeek 文件 id（导入时从 ZIP 取原件用）。
  final Map<String, String> imagePaths;

  /// 所有附件（按消息展开）。
  List<ExportAttachmentInput> get attachments => <ExportAttachmentInput>[
        for (final ExportMessageInput m in messages) ...m.attachments,
      ];

  ExportSessionInput copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? messageCount,
    String? currentMessageId,
    String? rootMessageId,
    bool? searchEnabled,
    bool? pinned,
    List<ExportMessageInput>? messages,
    Map<String, String>? imagePaths,
  }) {
    return ExportSessionInput(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messageCount: messageCount ?? this.messageCount,
      currentMessageId: currentMessageId ?? this.currentMessageId,
      rootMessageId: rootMessageId ?? this.rootMessageId,
      searchEnabled: searchEnabled ?? this.searchEnabled,
      pinned: pinned ?? this.pinned,
      messages: messages ?? this.messages,
      imagePaths: imagePaths ?? this.imagePaths,
    );
  }
}

// ---------------------------------------------------------------------------
// 导入：DeepSeek 官方导出 JSON → ExportSessionInput
// ---------------------------------------------------------------------------

/// 解析 `chat_sessions/<id>.json`（DeepSeek 官方导出格式）。
///
/// - 消息树按 `parent_id` 建链；校验分支：id 不重复、父子角色交替、父节点存在、
///   `current_message_id` 可达根（否则「文件中的消息分支已损坏，无法导入」）。
/// - `FILE` 片段里的图片收集到 [ExportSessionInput.imagePaths]
///   （`export_path` → 文件 id），并校验路径前缀 `chat_sessions/<id>_files/`。
/// - 消息 id 会加上 `'<sessionId>:'` 前缀，避免不同会话的 DeepSeek 自增 id 撞 DB 主键。
ExportSessionInput parseExportSession(Object? raw) {
  final Map<String, Object?> map = _asObjectOrNull(raw) ??
      (throw const ExportFormatException(ImportErrorText.incomplete));

  final String sessionId = _pathComponent(_requiredString(map['id']));
  final String title = _asStringOr(map['title'], '');
  final DateTime createdAt = _parseDeepSeekIso(map['inserted_at']);
  final DateTime updatedAt = _parseDeepSeekIso(map['updated_at']);
  final int currentRawId = _requiredNonNegativeInt(map['current_message_id']);

  final List<Object?> rawMessages = map['messages'] is List
      ? map['messages']! as List<Object?>
      : (throw const ExportFormatException(ImportErrorText.incomplete));

  final List<_RawMessage> parsed = <_RawMessage>[];
  final Map<int, _RawMessage> byId = <int, _RawMessage>{};
  for (final Object? rawMessage in rawMessages) {
    final _RawMessage? message = _parseRawMessage(rawMessage);
    if (message == null) continue;
    if (byId.containsKey(message.id)) {
      throw _branchError('消息 id 重复：${message.id}');
    }
    byId[message.id] = message;
    parsed.add(message);
  }

  if (parsed.isEmpty) {
    return ExportSessionInput(
      id: sessionId,
      title: title,
      createdAt: createdAt,
      updatedAt: updatedAt,
      messageCount: 0,
      currentMessageId: null,
      rootMessageId: null,
    );
  }

  // 校验父子关系（角色交替；根必须是 user）。
  for (final _RawMessage message in parsed) {
    if (message.parentId == null) {
      if (message.role != 'user') {
        throw _branchError('根消息不是用户消息');
      }
      continue;
    }
    final _RawMessage? parent = byId[message.parentId];
    if (parent == null) {
      throw _branchError('父消息不存在：${message.parentId}');
    }
    final String expectedParentRole =
        message.role == 'user' ? 'assistant' : 'user';
    if (parent.role != expectedParentRole) {
      throw _branchError('父子角色不交替：${message.id}');
    }
  }

  // 从 current_message_id 往上走到根，沿途记录「选中的子节点」。
  final Map<int, int> selectedChild = <int, int>{};
  _RawMessage? node = byId[currentRawId];
  if (node == null) {
    throw _branchError('当前消息不存在：$currentRawId');
  }
  _RawMessage root = node;
  int guard = 0;
  while (node != null) {
    if (guard++ > parsed.length + 1) {
      throw _branchError('分支成环');
    }
    root = node;
    final int? parentId = node.parentId;
    if (parentId == null) break;
    final _RawMessage? parent = byId[parentId];
    if (parent == null) {
      throw _branchError('父消息不存在：$parentId');
    }
    if (selectedChild.containsKey(parentId)) {
      throw _branchError('当前分支不唯一');
    }
    selectedChild[parentId] = node.id;
    node = parent;
  }
  if (root.role != 'user') {
    throw _branchError('链根不是用户消息');
  }

  // 消息按 DeepSeek id 升序（官方归一化 `messages.toSorted((a,b)=>a.id-b.id)`）。
  final List<_RawMessage> ordered = <_RawMessage>[...parsed]
    ..sort((_RawMessage a, _RawMessage b) => a.id.compareTo(b.id));

  final List<ExportMessageInput> messages = <ExportMessageInput>[];
  final Map<String, String> imagePaths = <String, String>{};
  final String sessionPrefix = '$sessionId:';
  for (int i = 0; i < ordered.length; i++) {
    final _RawMessage raw = ordered[i];
    final List<ContentBlock> blocks = <ContentBlock>[];
    final List<ExportAttachmentInput> attachments = <ExportAttachmentInput>[];
    bool sawThinking = false;
    bool sawSearch = false;

    for (final Map<String, Object?> fragment in raw.fragments) {
      final String type = _asStringOr(fragment['type'], '');
      switch (type) {
        case 'REQUEST':
        case 'RESPONSE':
        case 'TEMPLATE_RESPONSE':
          final String content = _asStringOr(fragment['content'], '');
          if (content.isNotEmpty || raw.role == 'user') {
            blocks.add(ContentBlock.text(content));
          }
        case 'THINK':
          sawThinking = true;
          blocks.add(ContentBlock.thinking(
            _asStringOr(fragment['content'], ''),
            elapsedSeconds: _asDoubleOrNull(fragment['elapsed_secs']),
          ));
        case 'TOOL_SEARCH':
          sawSearch = true;
          final List<Object?> results = fragment['results'] is List
              ? fragment['results']! as List<Object?>
              : const <Object?>[];
          for (final Object? rawResult in results) {
            final Map<String, Object?>? result = _asObjectOrNull(rawResult);
            if (result == null) continue;
            final String url = _asStringOr(result['url'], '');
            if (url.isEmpty) continue;
            blocks.add(ContentBlock.searchResult(
              url: url,
              title: _asStringOr(result['title'], ''),
              snippet: _asStringOr(result['snippet'], ''),
              siteName: _asStringOrNull(result['site_name']),
              publishedAt: _asStringOrNull(result['published_at']),
              tool: true,
            ));
          }
        case 'TOOL_OPEN':
          final String url = _asStringOr(fragment['url'], '');
          if (url.isEmpty) continue;
          sawSearch = true;
          blocks.add(ContentBlock.searchResult(
            url: url,
            title: _asStringOr(fragment['title'], ''),
            snippet: _asStringOr(fragment['snippet'], ''),
            siteName: _asStringOrNull(fragment['site_name']),
            publishedAt: _asStringOrNull(fragment['published_at']),
            tool: true,
          ));
        case 'FILE':
          final List<Object?> files = fragment['files'] is List
              ? fragment['files']! as List<Object?>
              : const <Object?>[];
          for (final Object? rawFile in files) {
            final ExportAttachmentInput? file =
                ExportAttachmentInput.fromJson(rawFile);
            if (file == null) continue;
            final String? exportPath = file.exportPath;
            if (exportPath != null && exportPath.isNotEmpty) {
              final String expectedPrefix = exportFilesDirOf(sessionId);
              if (!exportPath.startsWith(expectedPrefix)) {
                throw const ExportFormatException(ImportErrorText.incomplete);
              }
              if (file.isImage) {
                imagePaths[exportPath] = file.id;
              }
            }
            if (!attachments.any((ExportAttachmentInput a) => a.id == file.id)) {
              attachments.add(file);
            }
          }
        default:
          // TIP / CONTENT_RISK / PARTIAL_FILE_READ / TOOL_FIND / READ_LINK /
          // TOOL_IMAGE_SEARCH 等片段：App 不展示，直接忽略（官方归一化也容错）。
          break;
      }
    }

    final int? selectedChildRawId = selectedChild[raw.id];
    messages.add(ExportMessageInput(
      id: '$sessionPrefix${raw.id}',
      parentId:
          raw.parentId == null ? null : '$sessionPrefix${raw.parentId}',
      rootMessageId:
          raw.parentId == null ? null : '$sessionPrefix${raw.parentId}',
      currentMessageId: selectedChildRawId == null
          ? null
          : '$sessionPrefix$selectedChildRawId',
      role: raw.role,
      blocks: blocks,
      createdAt: raw.insertedAt,
      index: i,
      flags: raw.isError ? MessageFlag.error : 0,
      status: raw.isError ? 'error' : 'done',
      thinkingEnabled: sawThinking,
      searchEnabled: sawSearch,
      tokenUsage: raw.tokenUsage,
      attachments: attachments,
    ));
  }

  // 会话级联网搜索开关：选中链上出现过联网搜索即视为开。
  bool searchEnabled = false;
  for (final _RawMessage raw in ordered) {
    if (raw.role == 'assistant' && raw.searchEnabled) {
      searchEnabled = true;
    }
  }

  return ExportSessionInput(
    id: sessionId,
    title: title,
    createdAt: createdAt,
    updatedAt: updatedAt,
    messageCount: messages.length,
    currentMessageId: '$sessionPrefix$currentRawId',
    rootMessageId: '$sessionPrefix${root.id}',
    searchEnabled: searchEnabled,
    messages: messages,
    imagePaths: imagePaths,
  );
}

class _RawMessage {
  _RawMessage({
    required this.id,
    required this.parentId,
    required this.role,
    required this.insertedAt,
    required this.fragments,
    required this.thinkingEnabled,
    required this.searchEnabled,
    required this.tokenUsage,
    required this.status,
  });

  final int id;
  final int? parentId;
  final String role;
  final DateTime insertedAt;
  final List<Map<String, Object?>> fragments;
  final bool thinkingEnabled;
  final bool searchEnabled;
  final int tokenUsage;
  final String status;

  bool get isError =>
      status == 'FAILED' ||
      status == 'TIMEOUT' ||
      status == 'CONTEXT_LENGTH_EXCEEDED';
}

_RawMessage? _parseRawMessage(Object? raw) {
  final Map<String, Object?>? map = _asObjectOrNull(raw);
  if (map == null) {
    throw const ExportFormatException(ImportErrorText.incomplete);
  }
  final int id = _requiredNonNegativeInt(map['id']);
  final int? parentId = _asNonNegativeIntOrNull(map['parent_id']);
  final String role = _requiredEnum(map['role'], const <String>['USER', 'ASSISTANT']);
  final String status = _asStringOr(map['status'], 'FINISHED');
  const List<String> allowedStatus = <String>[
    'WIP',
    'FINISHED',
    'CONTENT_FILTER',
    'FAILED',
    'INCOMPLETE',
    'CONTEXT_LENGTH_EXCEEDED',
    'TIMEOUT',
  ];
  if (!allowedStatus.contains(status)) {
    throw const ExportFormatException(ImportErrorText.incomplete);
  }
  final DateTime insertedAt = _parseDeepSeekIso(map['inserted_at']);
  final List<Map<String, Object?>> fragments = <Map<String, Object?>>[];
  final Object? rawFragments = map['fragments'];
  if (rawFragments is List) {
    for (final Object? rawFragment in rawFragments) {
      final Map<String, Object?>? fragment = _asObjectOrNull(rawFragment);
      if (fragment == null) continue;
      if (_asStringOr(fragment['type'], '').isEmpty) continue;
      fragments.add(fragment);
    }
  }
  return _RawMessage(
    id: id,
    parentId: parentId,
    role: role == 'USER' ? 'user' : 'assistant',
    insertedAt: insertedAt,
    fragments: fragments,
    thinkingEnabled: map['thinking_enabled'] == true,
    searchEnabled: map['search_enabled'] == true,
    tokenUsage: _asNonNegativeIntOr(map['accumulated_token_usage'], 0),
    status: status,
  );
}

// ---------------------------------------------------------------------------
// 导出：ExportSessionInput → DeepSeek 官方导出 JSON
// ---------------------------------------------------------------------------

/// 把会话序列化成 DeepSeek 官方每会话 JSON。
///
/// 消息 id 会按 `index` 顺序重编号成 1..N（DeepSeek 要求整数 id），
/// `parent_id` 取 [ExportMessageInput.parentId]（缺失时退化成线性链，保证可导入），
/// `current_message_id` 取会话当前叶子（不可映射时取最后一条）。
Map<String, Object?> buildSessionJson(ExportSessionInput session) {
  final List<ExportMessageInput> ordered = <ExportMessageInput>[...session.messages]
    ..sort((ExportMessageInput a, ExportMessageInput b) {
      final int byIndex = a.index.compareTo(b.index);
      if (byIndex != 0) return byIndex;
      return a.createdAt.compareTo(b.createdAt);
    });

  final Map<String, int> idMap = <String, int>{};
  for (int i = 0; i < ordered.length; i++) {
    idMap[ordered[i].id] = i + 1;
  }

  final List<Map<String, Object?>> messages = <Map<String, Object?>>[];
  int previousId = 0;
  for (int i = 0; i < ordered.length; i++) {
    final ExportMessageInput message = ordered[i];
    final int id = i + 1;
    int? parentId = idMap[message.parentId];
    parentId ??= previousId == 0 ? null : previousId;
    messages.add(<String, Object?>{
      'id': id,
      'parent_id': parentId,
      'role': message.isUser ? 'USER' : 'ASSISTANT',
      'status': _deepSeekStatusOf(message),
      'thinking_enabled': message.thinkingEnabled ||
          message.blocks.any((ContentBlock b) => b.type == BlockType.thinking),
      'search_enabled': message.searchEnabled ||
          message.blocks.any((ContentBlock b) =>
              b.type == BlockType.webSearchResult ||
              b.type == BlockType.webSearchToolResult),
      'accumulated_token_usage': message.tokenUsage,
      'inserted_at': _toDeepSeekIso(message.createdAt),
      'fragments': _fragmentMessage(message),
    });
    previousId = id;
  }

  int currentMessageId = idMap[session.currentMessageId] ?? (ordered.isEmpty ? 0 : ordered.length);

  return <String, Object?>{
    'id': session.id,
    'title': session.title,
    'pinned': session.pinned,
    'current_message_id': currentMessageId,
    'inserted_at': _toDeepSeekIso(session.createdAt),
    'updated_at': _toDeepSeekIso(session.updatedAt),
    'messages': messages,
  };
}

String _deepSeekStatusOf(ExportMessageInput message) {
  switch (message.status) {
    case 'error':
      return 'FAILED';
    case 'stopped':
      return 'INCOMPLETE';
    default:
      return (message.flags & MessageFlag.error) != 0 ? 'FAILED' : 'FINISHED';
  }
}

/// blocks → DeepSeek `fragments`（官方导出的消息片断格式）。
///
/// 顺序：FILE（附件）→ 其余片段按 blocks 顺序（text / thinking / 搜索）。
/// 搜索块聚合成一个 `TOOL_SEARCH` 片段（`results` 列表），DeepSeek 与本 App
/// 的导入器都能解析。
List<Map<String, Object?>> _fragmentMessage(ExportMessageInput message) {
  final List<Map<String, Object?>> fragments = <Map<String, Object?>>[];

  if (message.attachments.isNotEmpty) {
    fragments.add(<String, Object?>{
      'type': 'FILE',
      'files': <Map<String, Object?>>[
        for (final ExportAttachmentInput file in message.attachments)
          <String, Object?>{...file.toJson()}
      ],
    });
  }

  final List<Map<String, Object?>> searchResults = <Map<String, Object?>>[];

  for (final ContentBlock block in message.blocks) {
    switch (block.type) {
      case BlockType.text:
        final String text = block.text ?? '';
        fragments.add(<String, Object?>{
          'type': message.isUser ? 'REQUEST' : 'RESPONSE',
          'content': text,
        });
      case BlockType.thinking:
        final String thinking = block.thinking ?? block.text ?? '';
        fragments.add(<String, Object?>{
          'type': 'THINK',
          'content': thinking,
          if (block.elapsedSeconds != null)
            'elapsed_secs': block.elapsedSeconds,
        });
      case BlockType.webSearchResult:
      case BlockType.webSearchToolResult:
        final String url = block.url ?? '';
        if (url.isEmpty) continue;
        searchResults.add(<String, Object?>{
          'url': url,
          'title': block.title ?? '',
          'snippet': block.snippet ?? '',
          if (block.siteName != null) 'site_name': block.siteName,
          if (block.publishedAt != null) 'published_at': block.publishedAt,
        });
      case BlockType.mermaid:
        fragments.add(<String, Object?>{
          'type': message.isUser ? 'REQUEST' : 'RESPONSE',
          'content': '```mermaid\n${block.text ?? ''}\n```',
        });
      case BlockType.code:
        fragments.add(<String, Object?>{
          'type': message.isUser ? 'REQUEST' : 'RESPONSE',
          'content':
              '```${block.language ?? ''}\n${block.text ?? ''}\n```',
        });
      case BlockType.image:
      case BlockType.file:
        // 附件统一走上面的 FILE 片段。
        break;
      case BlockType.unknown:
        final String text = block.text ?? '';
        if (text.isNotEmpty) {
          fragments.add(<String, Object?>{
            'type': message.isUser ? 'REQUEST' : 'RESPONSE',
            'content': text,
          });
        }
    }
  }

  if (searchResults.isNotEmpty) {
    fragments.add(<String, Object?>{
      'type': 'TOOL_SEARCH',
      'queries': const <String>[],
      'results': searchResults,
      'status': 'FINISHED',
    });
  }
  return fragments;
}

// ---------------------------------------------------------------------------
// 从 DB 装载（导出用）
// ---------------------------------------------------------------------------

/// 从数据库读一个会话，转成 [ExportSessionInput]；会话不存在返回 null。
///
/// 附件本地路径在 `attachments.path`；ZIP 内路径 = `chat_sessions/<sessionId>_files/<id>_<fileName>`。
Future<ExportSessionInput?> loadSessionForExport(
  AppDatabase db,
  String sessionId,
) async {
  final Session? session = await db.sessionById(sessionId);
  if (session == null) return null;

  final List<Message> rows = await db.sortedMessages(sessionId);
  final List<Attachment> attachments = await db.attachmentsOfSession(sessionId);
  final Map<String, List<ExportAttachmentInput>> byMessage =
      <String, List<ExportAttachmentInput>>{};
  for (final Attachment attachment in attachments) {
    final String? messageId = attachment.messageId;
    if (messageId == null || messageId.isEmpty) continue;
    final String fileKey = _attachmentFileKey(attachment);
    final ExportAttachmentInput input = ExportAttachmentInput(
      id: fileKey,
      fileName: attachment.fileName,
      fileSize: attachment.fileSize,
      mime: attachment.mime,
      isImage: _looksLikeImage(attachment),
      width: attachment.width,
      height: attachment.height,
      fileId: attachment.fileId,
      url: attachment.url,
      exportPath:
          '${exportFilesDirOf(sessionId)}${fileKey}_${_safeFileName(attachment.fileName)}',
      localPath: attachment.path.isEmpty ? null : attachment.path,
    );
    byMessage.putIfAbsent(messageId, () => <ExportAttachmentInput>[]).add(input);
  }

  final List<ExportMessageInput> messages = <ExportMessageInput>[
    for (int i = 0; i < rows.length; i++)
      ExportMessageInput(
        id: rows[i].id,
        parentId: rows[i].rootMessageId,
        rootMessageId: rows[i].rootMessageId,
        currentMessageId: rows[i].currentMessageId,
        role: rows[i].role,
        blocks: decodeBlocks(rows[i].content),
        createdAt: rows[i].createdAt,
        index: rows[i].index >= 0 ? rows[i].index : i,
        flags: rows[i].flags,
        status: (rows[i].flags & MessageFlag.error) != 0 ? 'error' : 'done',
        attachments: byMessage[rows[i].id] ?? const <ExportAttachmentInput>[],
      ),
  ];

  return ExportSessionInput(
    id: session.id,
    title: session.title,
    createdAt: session.createdAt,
    updatedAt: session.updatedAt,
    messageCount: messages.length,
    currentMessageId: session.currentMessageId,
    rootMessageId: session.rootMessageId,
    searchEnabled: session.searchEnabled,
    messages: messages,
  );
}

/// 附件在 ZIP 内 `_files/` 里的文件名前缀（fileId 优先，其次本地 id）。
String _attachmentFileKey(Attachment attachment) {
  final String? fileId = attachment.fileId;
  if (fileId != null && fileId.isNotEmpty) return _safeFileName(fileId);
  return _safeFileName(attachment.id);
}

bool _looksLikeImage(Attachment attachment) {
  if (attachment.mime.startsWith('image/')) return true;
  final String name = attachment.fileName.toLowerCase();
  return name.endsWith('.png') ||
      name.endsWith('.jpg') ||
      name.endsWith('.jpeg') ||
      name.endsWith('.gif') ||
      name.endsWith('.webp') ||
      name.endsWith('.bmp') ||
      name.endsWith('.avif') ||
      name.endsWith('.tif') ||
      name.endsWith('.tiff');
}

String _safeFileName(String input) => input
    .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
    .replaceAll('../', '_')
    .trim();

// ---------------------------------------------------------------------------
// 时间 / JSON 小工具
// ---------------------------------------------------------------------------

final RegExp _deepSeekIsoPattern =
    RegExp(r'^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d+))?Z$');

/// 解析 DeepSeek 导出里的 ISO 时间（必须是 UTC `...Z`）。
DateTime _parseDeepSeekIso(Object? value) {
  if (value is! String) {
    throw const ExportFormatException(ImportErrorText.incomplete);
  }
  final RegExpMatch? match = _deepSeekIsoPattern.firstMatch(value);
  if (match == null) {
    throw const ExportFormatException(ImportErrorText.incomplete);
  }
  final String millis = (match.group(2) ?? '').padRight(3, '0');
  final String normalized =
      '${match.group(1)}.${millis.substring(0, 3)}Z';
  final DateTime parsed = DateTime.parse(normalized);
  if (!parsed.isUtc) {
    throw const ExportFormatException(ImportErrorText.incomplete);
  }
  return parsed;
}

String _toDeepSeekIso(DateTime time) {
  final String iso = time.toUtc().toIso8601String();
  final int dot = iso.indexOf('.');
  if (dot >= 0) {
    final String fraction = iso.substring(dot + 1);
    final String millis = fraction.padRight(3, '0').substring(0, 3);
    return '${iso.substring(0, dot)}.${millis}Z';
  }
  return iso.endsWith('Z') ? iso : '${iso}Z';
}

Map<String, Object?>? _asObjectOrNull(Object? value) {
  if (value is Map) {
    return value.map((Object? key, Object? value) =>
        MapEntry<String, Object?>(key.toString(), value));
  }
  return null;
}

String _requiredString(Object? value) {
  if (value is String && value.isNotEmpty) return value;
  throw const ExportFormatException(ImportErrorText.incomplete);
}

String _requiredEnum(Object? value, List<String> allowed) {
  if (value is String && allowed.contains(value)) return value;
  throw const ExportFormatException(ImportErrorText.incomplete);
}

int _requiredNonNegativeInt(Object? value) {
  if (value is int && value >= 0) return value;
  if (value is num && value.isFinite && value >= 0) return value.toInt();
  throw const ExportFormatException(ImportErrorText.incomplete);
}

int? _asNonNegativeIntOrNull(Object? value) {
  if (value == null) return null;
  if (value is int && value >= 0) return value;
  if (value is num && value.isFinite && value >= 0) return value.toInt();
  throw const ExportFormatException(ImportErrorText.incomplete);
}

int _asNonNegativeIntOr(Object? value, int fallback) {
  if (value is int && value >= 0) return value;
  if (value is num && value.isFinite && value >= 0) return value.toInt();
  return fallback;
}

int? _asIntOrNull(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite) return value.toInt();
  return null;
}

double? _asDoubleOrNull(Object? value) {
  if (value is num && value.isFinite) return value.toDouble();
  return null;
}

String _asStringOr(Object? value, String fallback) =>
    value is String ? value : fallback;

String? _asStringOrNull(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

/// 会话 id 必须是单一路径段（官方归一化 `U`：非空、无 `/` `\`、不是 `.`/`..`）。
String _pathComponent(String value) {
  if (value.isNotEmpty &&
      !value.contains('/') &&
      !value.contains('\\') &&
      value != '.' &&
      value != '..') {
    return value;
  }
  throw const ExportFormatException(ImportErrorText.incomplete);
}

ExportFormatException _branchError(String detail) => ExportFormatException(
      ImportErrorText.invalidBranches,
      reason: ExportFormatReason.invalidBranches,
      cause: detail,
    );

/// 索引行（`chat_session_index.json` 一条）→ 会话摘要（不强校验，兼容旧包）。
class ExportIndexRow {
  const ExportIndexRow({
    required this.id,
    required this.title,
    required this.messageCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final int messageCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  static ExportIndexRow? fromJson(Object? raw) {
    final Map<String, Object?>? map = _asObjectOrNull(raw);
    if (map == null) return null;
    final Object? rawId = map['id'];
    if (rawId is! String || rawId.isEmpty) return null;
    final String id = rawId;
    if (id.contains('/') || id.contains('\\') || id == '.' || id == '..') {
      return null;
    }
    return ExportIndexRow(
      id: id,
      title: _asStringOr(map['title'], ''),
      messageCount: _asNonNegativeIntOr(map['message_count'], 0),
      createdAt: _parseIndexTime(map['inserted_at']),
      updatedAt: _parseIndexTime(map['updated_at']),
    );
  }

  static DateTime _parseIndexTime(Object? value) {
    if (value is String) {
      final DateTime? parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toUtc();
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
}

/// 索引 JSON（数组；兼容 `{"sessions": [...]}`）→ 行列表。
List<ExportIndexRow> parseExportIndex(Object? raw) {
  final Object? list = raw is List
      ? raw
      : (raw is Map && raw['sessions'] is List ? raw['sessions'] : null);
  if (list is! List) {
    throw const ExportFormatException(
      ImportErrorText.unrecognized,
      reason: ExportFormatReason.unrecognized,
    );
  }
  final List<ExportIndexRow> rows = <ExportIndexRow>[];
  final Set<String> seen = <String>{};
  for (final Object? item in list) {
    final ExportIndexRow? row = ExportIndexRow.fromJson(item);
    if (row == null || !seen.add(row.id)) continue;
    rows.add(row);
  }
  return rows;
}

/// JSON 编码（导出写文件用；与 Dart `jsonEncode` 一致，保留中文不转义）。
String jsonOf(Object? value) => jsonEncode(value);
