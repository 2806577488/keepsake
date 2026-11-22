/// Keepsake（留声）— 导出备份（DeepSeek 兼容 ZIP）。
///
/// 把本机全部会话导出成与 DeepSeek 官方导出包结构一致的 ZIP：
///
/// ```text
/// manifest.json                     {"export_format_version": 3}
/// chat_session_index.json           [{id,title,pinned,message_count,inserted_at,updated_at}]
/// chat_sessions/<session_id>.json   每会话（消息树 / 分支 / fragments，见 export_session.dart）
/// chat_sessions/<session_id>_files/<file_id>_<name>   图片 / 附件原件
/// ```
///
/// 文件名：`Keepsake 导出备份（<日期>）.zip`（[exportFileName]）。
/// 写到临时目录（`getTemporaryDirectory()`，或调用方指定 [outDir]）后返回路径 +
/// 元信息；**分享由 UI 批次用 share_plus 完成**，这里不碰平台通道。
///
/// 私有成员命名照逆向符号：`_jsonOf` / `_sessionRe` / `_writeSession`
/// （library `@1147407313`，`core/export/exporter.dart`）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:keepsake/core/db/database.dart';

import '../import/export_session.dart';

export '../import/export_session.dart'
    show
        ExportAttachmentInput,
        ExportFormatException,
        ExportFormatReason,
        ExportMessageInput,
        ExportSessionInput,
        buildSessionJson,
        exportBackupName,
        exportFilesDirOf,
        exportFormatVersion,
        exportIndexFileName,
        exportManifestFileName,
        jsonOf,
        loadSessionForExport;

/// 导出结果：临时 ZIP 路径 + 统计。
class ExportResult {
  const ExportResult({
    required this.path,
    required this.fileName,
    required this.sessions,
    required this.messages,
    required this.attachments,
    required this.bytes,
  });

  /// ZIP 绝对路径（临时目录）。
  final String path;

  /// 展示用文件名：`Keepsake 导出备份（2026-11-21）.zip`。
  final String fileName;

  final int sessions;
  final int messages;
  final int attachments;

  /// ZIP 字节数。
  final int bytes;

  /// 分享 / 打开用。
  File get file => File(path);

  bool get isEmpty => sessions == 0;

  /// 「已导出 N 个对话」。
  String get summary => '已导出 $sessions 个对话';
}

/// 导出失败文案（照 `ui-strings.txt` §10）。
abstract final class ExportErrorText {
  static const String noSessions = '还没有会话可以导出';
  static const String failed = '导出失败：';

  /// 选区导出时一个都没选中。
  static const String noSelection = '没有选中任何会话';
}

/// 导出文件名：`Keepsake 导出备份（<日期>）`。
///
/// 日期用本地时间 `yyyy-MM-dd`（文件名里带 `（` 是产品文案的一部分）。
String exportFileName([DateTime? at]) {
  final DateTime time = at ?? DateTime.now();
  final String date = '${_pad(time.year, 4)}-${_pad(time.month, 2)}-${_pad(time.day, 2)}';
  return '$exportBackupName（$date）';
}

/// 把数据库里的全部会话导出成 DeepSeek 兼容 ZIP。
///
/// - [outDir]：输出目录，默认 `getTemporaryDirectory()`。
/// - [at]：文件名里的日期（测试可固定）。
/// - [onProgress]：每写完一个会话回调 `(done, total)`，UI 可显示进度。
///
/// 返回 [ExportResult]；没有会话时抛 [ExportFormatException]（「还没有会话可以导出」）。
Future<ExportResult> exportToFile(
  AppDatabase db, {
  Directory? outDir,
  DateTime? at,
  void Function(int done, int total)? onProgress,
}) async {
  final List<Session> sessions = await db.allSessions();
  if (sessions.isEmpty) {
    throw const ExportFormatException(
      ExportErrorText.noSessions,
      reason: ExportFormatReason.incomplete,
    );
  }

  final Directory directory = outDir ?? await getTemporaryDirectory();
  if (!directory.existsSync()) {
    await directory.create(recursive: true);
  }
  final String baseName = exportFileName(at);
  File file = File(p.join(directory.path, '$baseName.zip'));
  int suffix = 2;
  while (file.existsSync() && suffix < 100) {
    file = File(p.join(directory.path, '$baseName（$suffix）.zip'));
    suffix++;
  }

  final ExporterImporter exporter = ExporterImporter(db);
  try {
    return await exporter._writeZip(
      sessions,
      file,
      at: at,
      onProgress: onProgress,
    );
  } catch (_) {
    // 失败时删掉半成品 ZIP（别让用户分享到一个坏包）。
    try {
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // 忽略清理失败。
    }
    rethrow;
  }
}

/// 选区导出的文件名：`Keepsake-导出-20261122-3个会话`（不含 `.zip`）。
///
/// 日期用本地时间 `yyyyMMdd`（与整库导出的 `（2026-11-22）` 区分开，
/// 便于用户一眼看出是「选中的几个会话」而不是整库备份）。
String subsetExportFileName(int sessionCount, [DateTime? at]) {
  final DateTime time = at ?? DateTime.now();
  final String date = '${_pad(time.year, 4)}${_pad(time.month, 2)}${_pad(time.day, 2)}';
  final int count = sessionCount < 0 ? 0 : sessionCount;
  return 'Keepsake-导出-$date-$count个会话';
}

/// 只导出**选中的会话**（按 session id 子集）成 DeepSeek 兼容 ZIP。
///
/// 与 [exportToFile] 完全同一套包结构（`manifest.json` /
/// `chat_session_index.json` / `chat_sessions/<id>.json` / `<id>_files/`），
/// 只是会话列表换成调用方给的那几条；ZIP 写到临时目录，文件名见
/// [subsetExportFileName]（重名时追加 `（2）`、`（3）`…）。
///
/// - [sessionIds]：要导出的会话 id（去重；不存在 / 已删除的会被跳过）。
/// - 全部 id 都不存在、或一个都没传时抛 [ExportFormatException]。
Future<ExportResult> exportSubsetToFile(
  AppDatabase db,
  List<String> sessionIds, {
  Directory? outDir,
  DateTime? at,
  void Function(int done, int total)? onProgress,
}) async {
  // Set 保持插入顺序（LinkedHashSet），导出顺序 = 用户看到的顺序。
  final List<String> ids = <String>[
    for (final String id in sessionIds.toSet())
      if (id.isNotEmpty) id,
  ];
  if (ids.isEmpty) {
    throw const ExportFormatException(
      ExportErrorText.noSelection,
      reason: ExportFormatReason.incomplete,
    );
  }

  final List<Session> sessions = <Session>[];
  for (final String id in ids) {
    final Session? session = await db.sessionById(id);
    if (session != null) sessions.add(session);
  }
  if (sessions.isEmpty) {
    throw const ExportFormatException(
      ExportErrorText.noSessions,
      reason: ExportFormatReason.incomplete,
    );
  }

  final Directory directory = outDir ?? await getTemporaryDirectory();
  if (!directory.existsSync()) {
    await directory.create(recursive: true);
  }
  final String baseName = subsetExportFileName(sessions.length, at);
  File file = File(p.join(directory.path, '$baseName.zip'));
  int suffix = 2;
  while (file.existsSync() && suffix < 100) {
    file = File(p.join(directory.path, '$baseName（$suffix）.zip'));
    suffix++;
  }

  final ExporterImporter exporter = ExporterImporter(db);
  try {
    return await exporter._writeZip(
      sessions,
      file,
      at: at,
      onProgress: onProgress,
    );
  } catch (_) {
    // 失败时删掉半成品 ZIP（别让用户分享/保存到一个坏包）。
    try {
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // 忽略清理失败。
    }
    rethrow;
  }
}

/// 导出服务（符号 `ExporterImporter`）。
class ExporterImporter {
  ExporterImporter(this.db);

  final AppDatabase db;

  /// 名称对照：`exportFileName`。
  String exportFileName([DateTime? at]) => _exportFileNameOf(at);

  /// 名称对照：`exportToFile`。
  Future<ExportResult> export({
    Directory? outDir,
    DateTime? at,
    void Function(int done, int total)? onProgress,
  }) =>
      exportToFile(db, outDir: outDir, at: at, onProgress: onProgress);

  /// 是否有可导出的会话。
  Future<bool> hasExportableSessions() async => (await db.allSessions()).isNotEmpty;

  Future<ExportResult> _writeZip(
    List<Session> sessions,
    File file, {
    DateTime? at,
    void Function(int done, int total)? onProgress,
  }) async {
    final ZipFileEncoder encoder = ZipFileEncoder();
    int messages = 0;
    int attachments = 0;

    // 先序列化索引与会话 JSON（内存里做，图片文件流式加进 ZIP）。
    final List<Map<String, Object?>> indexRows = <Map<String, Object?>>[];
    final List<({String entryPath, String json})> sessionFiles =
        <({String entryPath, String json})>[];
    final List<({String entryPath, File file})> attachmentFiles =
        <({String entryPath, File file})>[];

    for (int i = 0; i < sessions.length; i++) {
      final Session session = sessions[i];
      final ExportSessionInput? input = await loadSessionForExport(db, session.id);
      if (input == null) continue;
      final ({String entryPath, String json})? sessionFile = _writeSession(input);
      if (sessionFile == null) continue;

      indexRows.add(<String, Object?>{
        'id': input.id,
        'title': input.title,
        'pinned': input.pinned,
        'message_count': input.messages.length,
        'inserted_at': _isoOf(input.createdAt),
        'updated_at': _isoOf(input.updatedAt),
      });
      sessionFiles.add(sessionFile);
      messages += input.messages.length;

      final Set<String> usedPaths = <String>{};
      for (final ExportAttachmentInput attachment in input.attachments) {
        final String? exportPath = attachment.exportPath;
        final String? localPath = attachment.localPath;
        if (exportPath == null || exportPath.isEmpty) continue;
        if (localPath == null || localPath.isEmpty) continue;
        if (!usedPaths.add(exportPath)) continue;
        final File original = File(localPath);
        if (!original.existsSync()) continue;
        attachmentFiles.add((entryPath: exportPath, file: original));
        attachments++;
      }
      onProgress?.call(i + 1, sessions.length);
    }

    encoder.create(file.path, level: ZipFileEncoder.gzip);
    try {
      // manifest.json：导出格式版本。
      encoder.addArchiveFile(ArchiveFile.string(
        exportManifestFileName,
        _jsonOf(<String, Object?>{
          'export_format_version': exportFormatVersion,
          'generated_by': 'Keepsake',
        }),
      ));

      // chat_session_index.json：会话索引。
      encoder.addArchiveFile(ArchiveFile.string(
        exportIndexFileName,
        _jsonOf(indexRows),
      ));

      // 每会话 JSON。
      for (final ({String entryPath, String json}) item in sessionFiles) {
        encoder.addArchiveFile(ArchiveFile.string(item.entryPath, item.json));
      }

      // 附件原件（图片 STORE，与 DeepSeek 官方导出一致）。
      for (final ({String entryPath, File file}) item in attachmentFiles) {
        await encoder.addFile(item.file, item.entryPath, ZipFileEncoder.store);
      }
    } finally {
      await encoder.close();
    }

    final int bytes = await file.length();
    return ExportResult(
      path: file.path,
      fileName: p.basename(file.path),
      sessions: indexRows.length,
      messages: messages,
      attachments: attachments,
      bytes: bytes,
    );
  }
}

// ---------------------------------------------------------------------------
// 私有工具（符号命名照逆向：_jsonOf / _sessionRe / _writeSession）
// ---------------------------------------------------------------------------

/// 每会话 JSON 的包内路径正则（`chat_sessions/<id>.json`）。
final RegExp _sessionRe = RegExp(r'^chat_sessions/([^/]+)\.json$');

/// JSON 编码（保留中文，不转义）。
String _jsonOf(Object? value) => jsonEncode(value);

/// 生成一条会话的 ZIP 条目（路径 + JSON）；id 不是合法路径段时返回 null。
({String entryPath, String json})? _writeSession(ExportSessionInput session) {
  final String entryPath = '$exportSessionsDir${session.id}.json';
  if (_sessionRe.firstMatch(entryPath) == null) return null;
  return (entryPath: entryPath, json: _jsonOf(buildSessionJson(session)));
}

String _exportFileNameOf([DateTime? at]) => exportFileName(at);

String _isoOf(DateTime time) {
  final String iso = time.toUtc().toIso8601String();
  final int dot = iso.indexOf('.');
  if (dot >= 0) {
    final String fraction = iso.substring(dot + 1);
    final String millis = fraction.padRight(3, '0').substring(0, 3);
    return '${iso.substring(0, dot)}.${millis}Z';
  }
  return iso.endsWith('Z') ? iso : '${iso}Z';
}

String _pad(int value, int width) => value.toString().padLeft(width, '0');
