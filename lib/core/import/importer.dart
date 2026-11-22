/// Keepsake（留声）— DeepSeek 导出包导入器。
///
/// 职责：
/// 1. [ImportSource.open]：打开 ZIP（流式，见 `zip_reader.dart`），读
///    `manifest.json` 校验 `export_format_version`、读 `chat_session_index.json`
///    建导入计划（标题 / 消息数 / 时间），并建立「会话 JSON / 附件」条目索引。
/// 2. 阶段 A [Importer.writeTitle]：只写会话标题行（会话列表里标题一条条出现，
///    很快；3457 条约几百毫秒）。已存在的会话跳过。
/// 3. 阶段 B [Importer.importBody]：读每会话 JSON → [parseExportSession] →
///    **一个会话一个事务**写 sessions / messages / attachments，图片流式解压到
///    本地目录并回填 MIME / 宽高。已存在正文的会话跳过 → 中断后重跑可续传。
/// 4. 追加不覆盖：同 id 跳过；`INSERT OR IGNORE` 兜底。
///
/// 私有成员命名照逆向符号：`_hasFileBlocks` / `_extractError`（library
/// `@1128013363`，`core/import/importer.dart`）。错误文案照 `ui-strings.txt` §9。
library;

import 'dart:io';

import 'package:drift/drift.dart' show QueryRow, Variable;
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:keepsake/core/chat/blocks.dart';
import 'package:keepsake/core/db/database.dart';

import 'export_session.dart';
import 'zip_reader.dart';

export 'export_session.dart'
    show
        ExportAttachmentInput,
        ExportFormatException,
        ExportFormatReason,
        ExportIndexRow,
        ExportMessageInput,
        ExportSessionInput,
        ImportErrorText,
        buildSessionJson,
        exportBackupName,
        exportFilesDirOf,
        exportFormatVersion,
        exportIndexFileName,
        exportManifestFileName,
        exportSessionsDir,
        jsonOf,
        loadSessionForExport,
        parseExportIndex,
        parseExportSession,
        validateExportFormatVersion;

// ---------------------------------------------------------------------------
// 计划 / 数据源
// ---------------------------------------------------------------------------

/// 导入计划里一条会话的状态。
enum ImportRowStatus {
  /// 还没处理。
  pending,

  /// 已写标题，等补正文。
  title,

  /// 正在补正文。
  working,

  /// 正文已导入（或本地本来就有）。
  done,

  /// 导入失败，可重试。
  failed,

  /// 导出包里没有这个会话的正文（不可重试）。
  missing,
}

/// 导入计划里的一行（`chat_session_index.json` 的一条）。
class ImportPlanRow {
  ImportPlanRow({
    required this.id,
    required this.title,
    required this.messageCount,
    required this.createdAt,
    required this.updatedAt,
    required this.sessionEntry,
  }) : status =
            sessionEntry == null ? ImportRowStatus.missing : ImportRowStatus.pending;

  final String id;
  final String title;

  /// 索引里的消息数（导入后以实际写入数校正）。
  final int messageCount;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// `chat_sessions/<id>.json` 条目；null 表示包里缺正文。
  final ZipEntry? sessionEntry;

  ImportRowStatus status;

  /// 失败原因（中文，可展示）。
  String error = '';

  bool get retryable =>
      status == ImportRowStatus.failed || status == ImportRowStatus.pending;
}

/// 打开的导入源（ZIP + 计划 + 条目索引）。用完 [close]。
class ImportSource {
  ImportSource._({
    required this.file,
    required this.zip,
    required this.rows,
    required this.sessionEntries,
    required this.fileEntries,
    required this.manifest,
  });

  final File file;
  final StreamingZipReader zip;
  final List<ImportPlanRow> rows;

  /// 会话 id → `chat_sessions/<id>.json`。
  final Map<String, ZipEntry> sessionEntries;

  /// ZIP 内附件路径（`.../<fileId>_<name>`）→ 条目。
  final Map<String, ZipEntry> fileEntries;

  /// `manifest.json` 解析结果（可能为空 Map）。
  final Map<String, Object?> manifest;

  /// 打开并校验一个 DeepSeek 导出 ZIP。
  ///
  /// 抛 [ExportFormatException]（中文文案）或 [ZipFormatException]。
  static Future<ImportSource> open(File file, {int maxEntryBytes = 32 * 1024 * 1024}) async {
    final StreamingZipReader zip = await StreamingZipReader.openFile(file);
    try {
      // 1) chat_session_index.json：不是 DeepSeek 导出包 → 「无法识别该文件」。
      final ZipEntry? indexEntry = zip.entry(exportIndexFileName);
      if (indexEntry == null) {
        throw const ExportFormatException(
          ImportErrorText.unrecognized,
          reason: ExportFormatReason.unrecognized,
        );
      }

      // 2) manifest.json → export_format_version（官方导出包必有；缺 → 旧版）。
      final ZipEntry? manifestEntry = zip.entry(exportManifestFileName);
      if (manifestEntry == null) {
        throw const ExportFormatException(
          ImportErrorText.invalidVersion,
          reason: ExportFormatReason.invalidVersion,
        );
      }
      final Object? rawManifest =
          await zip.readJson(manifestEntry, maxBytes: maxEntryBytes);
      final Map<String, Object?> manifest = rawManifest is Map
          ? rawManifest.map((Object? key, Object? value) =>
              MapEntry<String, Object?>(key.toString(), value))
          : const <String, Object?>{};
      validateExportFormatVersion(manifest['export_format_version']);

      // 3) 索引 JSON → 计划。
      final Object? rawIndex = await zip.readJson(indexEntry, maxBytes: maxEntryBytes);
      final List<ExportIndexRow> indexRows = parseExportIndex(rawIndex);
      if (indexRows.isEmpty) {
        throw const ExportFormatException(
          ImportErrorText.unrecognized,
          reason: ExportFormatReason.unrecognized,
        );
      }

      // 4) 条目索引：每会话 JSON + _files/ 附件。
      final RegExp sessionPattern = RegExp(r'^chat_sessions/([^/]+)\.json$');
      final Map<String, ZipEntry> sessionEntries = <String, ZipEntry>{};
      final Map<String, ZipEntry> fileEntries = <String, ZipEntry>{};
      for (final ZipEntry entry in zip.entries) {
        if (entry.isDirectory) continue;
        final String path = entry.path;
        if (!path.startsWith(exportSessionsDir)) continue;
        final RegExpMatch? match = sessionPattern.firstMatch(path);
        if (match != null) {
          sessionEntries[match.group(1)!] = entry;
          continue;
        }
        if (path.contains('_files/')) {
          fileEntries[path] = entry;
        }
      }

      final List<ImportPlanRow> rows = <ImportPlanRow>[
        for (final ExportIndexRow row in indexRows)
          ImportPlanRow(
            id: row.id,
            title: row.title.isEmpty ? '未命名会话' : row.title,
            messageCount: row.messageCount,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            sessionEntry: sessionEntries[row.id],
          ),
      ];

      return ImportSource._(
        file: file,
        zip: zip,
        rows: rows,
        sessionEntries: sessionEntries,
        fileEntries: fileEntries,
        manifest: manifest,
      );
    } catch (_) {
      await zip.close();
      rethrow;
    }
  }

  /// 关闭 ZIP。
  Future<void> close() => zip.close();
}

// ---------------------------------------------------------------------------
// 导入结果 / 数据库模型
// ---------------------------------------------------------------------------

/// 导入统计（UI 直接显示）。
class ImportResult {
  const ImportResult({
    this.totalSessions = 0,
    this.addedSessions = 0,
    this.addedMessages = 0,
    this.addedAttachments = 0,
    this.skippedSessions = 0,
    this.failedSessions = 0,
    this.titlesWritten = 0,
    this.cancelled = false,
    this.fatalError,
    this.errors = const <String, String>{},
  });

  /// 导出包索引里的会话总数。
  final int totalSessions;

  /// 本次新增的会话（有正文写入）。
  final int addedSessions;

  /// 本次写入的消息数。
  final int addedMessages;

  /// 本次写入的附件数。
  final int addedAttachments;

  /// 本地已有正文、跳过的会话数。
  final int skippedSessions;

  /// 失败的会话数（可重试）。
  final int failedSessions;

  /// 阶段 A 新写入的标题数。
  final int titlesWritten;

  final bool cancelled;

  /// 致命错误（不可识别 / 版本不对 / ZIP 损坏），已含中文文案。
  final String? fatalError;

  /// sessionId → 中文错误（失败会话，可重试）。
  final Map<String, String> errors;

  bool get hasNew => addedSessions > 0;

  bool get hasFailures => failedSessions > 0;

  /// 「已新增 N 个对话」/「文件中的对话本地都已存在，没有新增」。
  String get summary {
    if (fatalError != null) return fatalError!;
    if (addedSessions > 0) return '已新增 $addedSessions 个对话';
    return ImportErrorText.nothingNew;
  }

  ImportResult copyWith({
    int? totalSessions,
    int? addedSessions,
    int? addedMessages,
    int? addedAttachments,
    int? skippedSessions,
    int? failedSessions,
    int? titlesWritten,
    bool? cancelled,
    String? fatalError,
    Map<String, String>? errors,
  }) {
    return ImportResult(
      totalSessions: totalSessions ?? this.totalSessions,
      addedSessions: addedSessions ?? this.addedSessions,
      addedMessages: addedMessages ?? this.addedMessages,
      addedAttachments: addedAttachments ?? this.addedAttachments,
      skippedSessions: skippedSessions ?? this.skippedSessions,
      failedSessions: failedSessions ?? this.failedSessions,
      titlesWritten: titlesWritten ?? this.titlesWritten,
      cancelled: cancelled ?? this.cancelled,
      fatalError: fatalError ?? this.fatalError,
      errors: errors ?? this.errors,
    );
  }

  /// 累加另一次结果（重试后合并用）。
  ImportResult merge(ImportResult other) => ImportResult(
        totalSessions: other.totalSessions > 0 ? other.totalSessions : totalSessions,
        addedSessions: addedSessions + other.addedSessions,
        addedMessages: addedMessages + other.addedMessages,
        addedAttachments: addedAttachments + other.addedAttachments,
        skippedSessions: skippedSessions + other.skippedSessions,
        failedSessions: other.failedSessions,
        titlesWritten: titlesWritten + other.titlesWritten,
        cancelled: other.cancelled,
        fatalError: other.fatalError,
        errors: other.errors,
      );
}

/// 解析后的会话（DB 写入前的中间模型）。
class ImportedSession {
  const ImportedSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messageCount,
    required this.currentMessageId,
    required this.rootMessageId,
    required this.searchEnabled,
    required this.messages,
    required this.files,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int messageCount;
  final String? currentMessageId;
  final String? rootMessageId;
  final bool searchEnabled;
  final List<ImportedMessage> messages;
  final List<ImportedFile> files;
}

/// 解析后的消息（DB 写入前的中间模型）。
class ImportedMessage {
  const ImportedMessage({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.createdAt,
    required this.rootMessageId,
    required this.currentMessageId,
    required this.index,
    required this.flags,
    required this.files,
  });

  final String id;
  final String sessionId;
  final String role;

  /// blocks JSON（`encodeBlocks`），UI / context_builder 直接可用。
  final String content;
  final DateTime createdAt;
  final String? rootMessageId;
  final String? currentMessageId;
  final int index;
  final int flags;
  final List<ImportedFile> files;
}

/// 解析后的附件（已落盘）。
class ImportedFile {
  const ImportedFile({
    required this.id,
    required this.sessionId,
    required this.messageId,
    required this.fileName,
    required this.fileSize,
    required this.mime,
    required this.path,
    required this.width,
    required this.height,
    required this.fileId,
    required this.url,
  });

  /// attachments 表主键（`<messageId>:<DeepSeek file id>`，会话内去重）。
  final String id;
  final String sessionId;
  final String? messageId;
  final String fileName;
  final int fileSize;
  final String mime;
  final String path;
  final int? width;
  final int? height;

  /// DeepSeek Files API 的服务端 id（导出包里的 file id）。
  final String? fileId;
  final String? url;
}

// ---------------------------------------------------------------------------
// 导入器
// ---------------------------------------------------------------------------

/// 导入器：持有 DB + 附件目录，提供两阶段导入。
class Importer {
  Importer(this.db, {this.attachmentsRoot, this.maxEntryBytes = 32 * 1024 * 1024});

  final AppDatabase db;

  /// 附件根目录（默认 `getApplicationSupportDirectory()/chat_sessions`）。
  Directory? attachmentsRoot;

  /// 文本条目（会话 JSON）读取上限。
  final int maxEntryBytes;

  Future<Directory> _root() async {
    final Directory? existing = attachmentsRoot;
    if (existing != null) return existing;
    final Directory support = await getApplicationSupportDirectory();
    final Directory root = Directory(p.join(support.path, 'chat_sessions'));
    attachmentsRoot = root;
    return root;
  }

  /// 打开导入源（ZIP 校验 + 计划）。
  Future<ImportSource> open(File file) => ImportSource.open(file, maxEntryBytes: maxEntryBytes);

  /// 会话在本地是否已有正文（messages 行数 > 0）。
  Future<bool> hasBody(String sessionId) async {
    final List<QueryRow> rows = await db
        .customSelect(
          'SELECT 1 AS one FROM messages WHERE session_id = ? LIMIT 1',
          variables: <Variable<Object>>[Variable<String>(sessionId)],
        )
        .get();
    return rows.isNotEmpty;
  }

  /// 阶段 A：写一条会话标题（只写 sessions 行，正文稍后补）。
  ///
  /// 返回 true 表示本次新写入；false 表示会话已存在（跳过）。
  Future<bool> writeTitle(ImportPlanRow row) async {
    final bool exists = await db.hasSession(row.id);
    if (exists) return false;
    await db.customStatement(
      'INSERT OR IGNORE INTO sessions '
      '(id, title, created_at, updated_at, message_count, current_message_id, '
      'root_message_id, flags, sort, search_enabled) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        row.id,
        row.title,
        _seconds(row.createdAt),
        _seconds(row.updatedAt),
        row.messageCount,
        null,
        null,
        0,
        null,
        0,
      ],
    );
    return true;
  }

  /// 阶段 B：导入一条会话正文（含附件落盘 + 一个事务写库）。
  ///
  /// 已存在正文的会话直接跳过（`skipped: true`，返回 0 消息、0 附件）。
  Future<({int messages, int files, bool skipped})> importBody(
    ImportSource source,
    ImportPlanRow row, {
    void Function(int messages, int files)? onFiles,
  }) async {
    if (row.status == ImportRowStatus.done) {
      return (messages: 0, files: 0, skipped: true);
    }
    if (await hasBody(row.id)) {
      row.status = ImportRowStatus.done;
      return (messages: 0, files: 0, skipped: true);
    }
    final ZipEntry? entry = row.sessionEntry;
    if (entry == null) {
      throw const ExportFormatException(
        ImportErrorText.incomplete,
        reason: ExportFormatReason.incomplete,
      );
    }

    final Object? raw = await source.zip.readJson(entry, maxBytes: maxEntryBytes);
    final ExportSessionInput parsed = parseExportSession(raw);
    onFiles?.call(parsed.messages.length, parsed.attachments.length);
    final ImportedSession imported = await _toImported(source, parsed);
    await _writeSession(imported);
    row.status = ImportRowStatus.done;
    return (
      messages: imported.messages.length,
      files: imported.files.length,
      skipped: false,
    );
  }

  /// 把解析结果落成 [ImportedSession]（附件从 ZIP 流式解压到本地目录）。
  Future<ImportedSession> _toImported(
    ImportSource source,
    ExportSessionInput parsed,
  ) async {
    final Directory root = await _root();
    final List<ImportedFile> files = <ImportedFile>[];

    // 1) 附件：按 export_path 从 ZIP 取原件，写到本地 chat_sessions/<sid>_files/。
    for (final ExportMessageInput message in parsed.messages) {
      for (final ExportAttachmentInput attachment in message.attachments) {
        final String? exportPath = attachment.exportPath;
        if (exportPath == null || exportPath.isEmpty) continue;
        final ZipEntry? entry = source.fileEntries[exportPath] ??
            source.fileEntries[exportPath.replaceAll('\\', '/')];
        if (entry == null) continue; // 附件不在包里：忽略（官方导入同样忽略）
        final String safeName = _safeFileName(
            attachment.fileName.isEmpty ? entry.name : attachment.fileName);
        final String key = _safeFileName(attachment.id);
        final Directory dir = Directory(p.join(
          root.path,
          '${parsed.id}_files',
        ));
        final File target = File(p.join(dir.path, '${key}_$safeName'));
        final int size = await source.zip.extractTo(entry, target);
        final String mime = await _mimeOfFile(target, attachment.fileName);
        files.add(ImportedFile(
          id: '${message.id}:${attachment.id}',
          sessionId: parsed.id,
          messageId: message.id,
          fileName: attachment.fileName.isEmpty ? entry.name : attachment.fileName,
          fileSize: size > 0 ? size : attachment.fileSize,
          mime: mime,
          path: target.path,
          width: attachment.width,
          height: attachment.height,
          fileId: attachment.id,
          url: attachment.url,
        ));
      }
    }

    // 2) 消息：blocks 里补上附件引用（图片 / 文件块），再 encodeBlocks。
    final Map<String, List<ImportedFile>> byMessage =
        <String, List<ImportedFile>>{};
    for (final ImportedFile file in files) {
      final String? messageId = file.messageId;
      if (messageId == null) continue;
      byMessage.putIfAbsent(messageId, () => <ImportedFile>[]).add(file);
    }

    final List<ImportedMessage> messages = <ImportedMessage>[];
    for (final ExportMessageInput message in parsed.messages) {
      final List<ImportedFile> messageFiles =
          byMessage[message.id] ?? const <ImportedFile>[];
      final List<ContentBlock> blocks = <ContentBlock>[...message.blocks];
      // 解析层已把 FILE 片段变成附件；这里再把附件引用补成 image/file 块，
      // 使 blocks.toApi / context_builder 能把附件一起带给模型。
      if (!_hasFileBlocks(blocks)) {
        for (final ImportedFile file in messageFiles) {
          if (_looksLikeImage(file.mime, file.fileName)) {
            blocks.add(ContentBlock.image(
              path: file.path,
              fileName: file.fileName,
              mime: file.mime,
              width: file.width,
              height: file.height,
              fileId: file.fileId,
            ));
          } else {
            blocks.add(ContentBlock.file(
              path: file.path,
              fileName: file.fileName,
              mime: file.mime,
              fileId: file.fileId,
            ));
          }
        }
      }
      messages.add(ImportedMessage(
        id: message.id,
        sessionId: parsed.id,
        role: message.role,
        content: encodeBlocks(blocks),
        createdAt: message.createdAt,
        rootMessageId: message.rootMessageId,
        currentMessageId: message.currentMessageId,
        index: message.index,
        flags: message.flags,
        files: messageFiles,
      ));
    }

    return ImportedSession(
      id: parsed.id,
      title: parsed.title.isEmpty ? '未命名会话' : parsed.title,
      createdAt: parsed.createdAt,
      updatedAt: parsed.updatedAt,
      messageCount: messages.length,
      currentMessageId: parsed.currentMessageId,
      rootMessageId: parsed.rootMessageId,
      searchEnabled: parsed.searchEnabled,
      messages: messages,
      files: files,
    );
  }

  /// 一个会话一个事务：sessions + messages + attachments 一起写，成功才算数。
  Future<void> _writeSession(ImportedSession session) async {
    await db.transaction(() async {
      await db.customStatement(
        'INSERT OR IGNORE INTO sessions '
        '(id, title, created_at, updated_at, message_count, current_message_id, '
        'root_message_id, flags, sort, search_enabled) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          session.id,
          session.title,
          _seconds(session.createdAt),
          _seconds(session.updatedAt),
          session.messageCount,
          session.currentMessageId,
          session.rootMessageId,
          0,
          null,
          session.searchEnabled ? 1 : 0,
        ],
      );

      for (final ImportedMessage message in session.messages) {
        await db.customStatement(
          'INSERT OR IGNORE INTO messages '
          '(id, session_id, role, content, created_at, root_message_id, '
          'current_message_id, "index", flags) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
          <Object?>[
            message.id,
            message.sessionId,
            message.role,
            message.content,
            _seconds(message.createdAt),
            message.rootMessageId,
            message.currentMessageId,
            message.index,
            message.flags,
          ],
        );
      }

      for (final ImportedFile file in session.files) {
        await db.customStatement(
          'INSERT OR IGNORE INTO attachments '
          '(id, session_id, message_id, file_name, file_size, mime, path, '
          'width, height, file_id, url) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          <Object?>[
            file.id,
            file.sessionId,
            file.messageId,
            file.fileName,
            file.fileSize,
            file.mime,
            file.path,
            file.width,
            file.height,
            file.fileId,
            file.url,
          ],
        );
      }

      // 修正会话行（标题/时间/消息数/分支指针/联网搜索开关）。
      await db.customStatement(
        'UPDATE sessions SET title = ?, created_at = ?, updated_at = ?, '
        'message_count = ?, current_message_id = ?, root_message_id = ?, '
        'search_enabled = ? WHERE id = ?',
        <Object?>[
          session.title,
          _seconds(session.createdAt),
          _seconds(session.updatedAt),
          session.messageCount,
          session.currentMessageId,
          session.rootMessageId,
          session.searchEnabled ? 1 : 0,
          session.id,
        ],
      );
    });
  }

  /// 读取图片/文件前 64 字节嗅探 MIME（导出包不带 mime）。
  Future<String> _mimeOfFile(File file, String fileName) async {
    List<int> head = const <int>[];
    try {
      final RandomAccessFile raf = await file.open();
      try {
        head = await raf.read(64);
      } finally {
        await raf.close();
      }
    } catch (_) {
      // 忽略：按扩展名兜底。
    }
    final String sniffed = _sniffMime(head);
    if (sniffed.isNotEmpty) return sniffed;
    return lookupMimeType(fileName) ?? 'application/octet-stream';
  }
}

// ---------------------------------------------------------------------------
// 便捷入口（测试 / 简单 UI 用；设置页走 ImportTask 分阶段）
// ---------------------------------------------------------------------------

/// 一条龙导入：打开 ZIP → 写标题 → 补正文（顺序），返回统计。
///
/// [onTitle] / [onBody] 可用于进度显示；[shouldStop] 返回 true 时中止。
Future<ImportResult> importZip(
  AppDatabase db,
  File file, {
  Directory? attachmentsRoot,
  void Function(ImportPlanRow row, int index, int total)? onTitle,
  void Function(ImportPlanRow row, int index, int total)? onBody,
  void Function(ImportPlanRow row, String error)? onError,
  bool Function()? shouldStop,
  int maxEntryBytes = 32 * 1024 * 1024,
}) async {
  final Importer importer =
      Importer(db, attachmentsRoot: attachmentsRoot, maxEntryBytes: maxEntryBytes);
  late final ImportSource source;
  try {
    source = await importer.open(file);
  } catch (error) {
    return ImportResult(fatalError: _extractError(error));
  }

  final Map<String, String> errors = <String, String>{};
  int titlesWritten = 0;
  int addedSessions = 0;
  int addedMessages = 0;
  int addedAttachments = 0;
  int skipped = 0;
  int failed = 0;
  bool cancelled = false;

  try {
    // 阶段 A：标题。
    for (int i = 0; i < source.rows.length; i++) {
      if (shouldStop?.call() ?? false) {
        cancelled = true;
        break;
      }
      final ImportPlanRow row = source.rows[i];
      if (row.status == ImportRowStatus.missing) {
        failed++;
        errors[row.id] = '导出包里没有这个会话的正文';
        onError?.call(row, errors[row.id]!);
        continue;
      }
      if (await importer.hasBody(row.id)) {
        row.status = ImportRowStatus.done;
        skipped++;
        continue;
      }
      final bool wrote = await importer.writeTitle(row);
      if (wrote) titlesWritten++;
      row.status = ImportRowStatus.title;
      onTitle?.call(row, i, source.rows.length);
    }

    // 阶段 B：正文（顺序；失败不影响其它会话）。
    if (!cancelled) {
      for (int i = 0; i < source.rows.length; i++) {
        if (shouldStop?.call() ?? false) {
          cancelled = true;
          break;
        }
        final ImportPlanRow row = source.rows[i];
        if (row.status == ImportRowStatus.done) continue;
        if (row.status == ImportRowStatus.missing) continue;
        row.status = ImportRowStatus.working;
        try {
          final ({int messages, int files, bool skipped}) written =
              await importer.importBody(source, row);
          if (written.skipped) {
            skipped++;
          } else {
            addedSessions++;
            addedMessages += written.messages;
            addedAttachments += written.files;
          }
          onBody?.call(row, i, source.rows.length);
        } catch (error) {
          row.status = ImportRowStatus.failed;
          row.error = _extractError(error);
          failed++;
          errors[row.id] = row.error;
          onError?.call(row, row.error);
        }
      }
    }
  } finally {
    await source.close();
  }

  return ImportResult(
    totalSessions: source.rows.length,
    addedSessions: addedSessions,
    addedMessages: addedMessages,
    addedAttachments: addedAttachments,
    skippedSessions: skipped,
    failedSessions: failed,
    titlesWritten: titlesWritten,
    cancelled: cancelled,
    errors: errors,
  );
}

/// 导入一条已解析的会话（供 ImportTask 单条补正文；已存在正文则跳过）。
Future<void> importSession(
  AppDatabase db,
  ExportSessionInput session, {
  ImportSource? source,
  Directory? attachmentsRoot,
}) async {
  final Importer importer = Importer(db, attachmentsRoot: attachmentsRoot);
  final ImportedSession imported;
  if (source == null) {
    // 没有 ZIP 源：附件只在 blocks 里（不落盘，适合测试 / 由调用方自己准备附件）。
    imported = ImportedSession(
      id: session.id,
      title: session.title,
      createdAt: session.createdAt,
      updatedAt: session.updatedAt,
      messageCount: session.messages.length,
      currentMessageId: session.currentMessageId,
      rootMessageId: session.rootMessageId,
      searchEnabled: session.searchEnabled,
      messages: <ImportedMessage>[
        for (final ExportMessageInput m in session.messages)
          ImportedMessage(
            id: m.id,
            sessionId: session.id,
            role: m.role,
            content: encodeBlocks(m.blocks),
            createdAt: m.createdAt,
            rootMessageId: m.rootMessageId,
            currentMessageId: m.currentMessageId,
            index: m.index,
            flags: m.flags,
            files: const <ImportedFile>[],
          ),
      ],
      files: const <ImportedFile>[],
    );
  } else {
    imported = await importer._toImported(source, session);
  }
  await importer._writeSession(imported);
}

// ---------------------------------------------------------------------------
// 私有工具（符号命名照逆向：_hasFileBlocks / _extractError）
// ---------------------------------------------------------------------------

/// 消息 blocks 里是否已经有附件块（image / file）。
bool _hasFileBlocks(Iterable<ContentBlock> blocks) => blocks.any(
      (ContentBlock block) =>
          block.type == BlockType.image || block.type == BlockType.file,
    );

String importErrorMessage(Object error) => _extractError(error);

String _extractError(Object error) {
  if (error is ExportFormatException) return error.message;
  if (error is ZipFormatException) {
    if (error.message.contains('JSON 解析失败') ||
        error.message.contains('解压长度不符') ||
        error.message.contains('CRC 校验失败')) {
      return ImportErrorText.invalidJson;
    }
    return error.message;
  }
  if (error is FileSystemException) {
    return '导入失败：${error.message}';
  }
  if (error is FormatException) return ImportErrorText.invalidJson;
  return '导入失败：$error';
}

int _seconds(DateTime time) => time.toUtc().millisecondsSinceEpoch ~/ 1000;

String _safeFileName(String input) {
  final String trimmed = input.trim();
  if (trimmed.isEmpty) return 'file';
  return trimmed
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
      .replaceAll('..', '_');
}

bool _looksLikeImage(String mime, String fileName) {
  if (mime.startsWith('image/')) return true;
  final String lower = fileName.toLowerCase();
  return lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.bmp') ||
      lower.endsWith('.avif') ||
      lower.endsWith('.heic') ||
      lower.endsWith('.tif') ||
      lower.endsWith('.tiff');
}

/// MIME 魔数嗅探（与 App 内置导入器同一套魔数）。
String _sniffMime(List<int> bytes) {
  bool startsWith(List<int> magic) {
    if (bytes.length < magic.length) return false;
    for (int i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }

  String ascii(int offset, int length) {
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < length && offset + i < bytes.length; i++) {
      buffer.writeCharCode(bytes[offset + i]);
    }
    return buffer.toString();
  }

  if (startsWith(<int>[0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (startsWith(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'image/png';
  }
  final String head12 = ascii(0, 12);
  if (head12.startsWith('GIF87a') || head12.startsWith('GIF89a')) {
    return 'image/gif';
  }
  if (head12.startsWith('RIFF') && ascii(8, 4) == 'WEBP') return 'image/webp';
  if (startsWith(<int>[0x42, 0x4D])) return 'image/bmp';
  if (startsWith(<int>[0x49, 0x49, 0x2A, 0x00]) ||
      startsWith(<int>[0x4D, 0x4D, 0x00, 0x2A])) {
    return 'image/tiff';
  }
  if (ascii(4, 4) == 'ftyp') {
    final String brand = ascii(8, 4);
    if (brand == 'avif' || brand == 'avis') return 'image/avif';
    if (brand == 'heic' || brand == 'heix' || brand == 'mif1') return 'image/heic';
  }
  if (startsWith(<int>[0x25, 0x50, 0x44, 0x46])) return 'application/pdf';
  return '';
}
