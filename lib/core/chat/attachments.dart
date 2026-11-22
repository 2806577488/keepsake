/// Keepsake（留声）— 附件模型与规则。
///
/// 符号证据（`reports/apk/dart-symbols.md` §2、`db-schema.md` §2）：
/// `Attachment`、`AttachmentRules`、`attachmentsOfSession`、`allowedExtensions`、
/// `maxBytesFor`、`isImage`、`attachments` 表列
/// `file_name / file_size / mime / path / width / height / file_id / url`。
///
/// 文案证据（ui-strings.txt §3）：`一条消息最多 50 个附件`、`文件太大：`、
/// `MB，上限 `、`不支持这种文件类型：`、`文件不见了：`、`附件`、`图片`、`文件`。
library;

import 'dart:io';

/// 一条本地附件（图片/文件）。
///
/// 字段与 drift `attachments` 表一一对应（`toDbJson` 用 snake_case）。
class Attachment {
  const Attachment({
    required this.id,
    this.sessionId,
    this.messageId,
    required this.fileName,
    this.fileSize = 0,
    this.mime = '',
    this.path = '',
    this.width,
    this.height,
    this.fileId,
    this.url,
  });

  /// 本地 id（uuid v4）。
  final String id;

  /// 所属会话 id。
  final String? sessionId;

  /// 所属消息 id（草稿态可为 null）。
  final String? messageId;

  /// 原文件名（导出 ZIP 里保留）。
  final String fileName;

  /// 字节数。
  final int fileSize;

  /// MIME 类型（未知时为空串，按扩展名推断）。
  final String mime;

  /// 本地缓存路径。
  final String path;

  /// 图片宽度（图片才有）。
  final int? width;

  /// 图片高度（图片才有）。
  final int? height;

  /// DeepSeek / Anthropic Files API 返回的服务端 id（上传后才有）。
  final String? fileId;

  /// 远程链接（导入/分享场景）。
  final String? url;

  /// 是否为图片（MIME 优先，其次扩展名）。
  bool get isImage => AttachmentRules.isImageFile(fileName, mime: mime);

  bool get hasLocalFile => path.trim().isNotEmpty;

  bool get hasRemoteUrl => url != null && url!.trim().isNotEmpty;

  bool get isUploaded => fileId != null && fileId!.trim().isNotEmpty;

  /// 扩展名（不含点，小写）。
  String get extension => AttachmentRules.extensionOf(fileName);

  /// 长边像素（非图片为 0）。
  int get longEdge {
    final w = width ?? 0;
    final h = height ?? 0;
    return w > h ? w : h;
  }

  bool get hasDimensions => (width ?? 0) > 0 && (height ?? 0) > 0;

  /// 人类可读大小（如 `1.4MB`）。
  String get displaySize => AttachmentRules.formatSize(fileSize);

  /// 本地文件是否仍然存在（导出/上传前检查；文案「文件不见了：」）。
  bool get fileExists {
    if (!hasLocalFile) return false;
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  Attachment copyWith({
    String? id,
    String? sessionId,
    String? messageId,
    String? fileName,
    int? fileSize,
    String? mime,
    String? path,
    int? width,
    int? height,
    String? fileId,
    String? url,
  }) =>
      Attachment(
        id: id ?? this.id,
        sessionId: sessionId ?? this.sessionId,
        messageId: messageId ?? this.messageId,
        fileName: fileName ?? this.fileName,
        fileSize: fileSize ?? this.fileSize,
        mime: mime ?? this.mime,
        path: path ?? this.path,
        width: width ?? this.width,
        height: height ?? this.height,
        fileId: fileId ?? this.fileId,
        url: url ?? this.url,
      );

  /// DB / JSON 形状（snake_case，与 attachments 表列名一致）。
  Map<String, Object?> toDbJson() => <String, Object?>{
        'id': id,
        if (sessionId != null) 'session_id': sessionId,
        if (messageId != null) 'message_id': messageId,
        'file_name': fileName,
        'file_size': fileSize,
        'mime': mime,
        'path': path,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (fileId != null) 'file_id': fileId,
        if (url != null) 'url': url,
      };

  /// 与 [toDbJson] 相同（导出/导入 JSON 也统一 snake_case）。
  Map<String, Object?> toJson() => toDbJson();

  factory Attachment.fromDbJson(Map<String, Object?> json) {
    final fileName =
        _stringOf(json['file_name']) ?? _stringOf(json['fileName']) ?? '附件';
    return Attachment(
      id: _stringOf(json['id']) ?? fileName,
      sessionId: _stringOf(json['session_id']) ?? _stringOf(json['sessionId']),
      messageId:
          _stringOf(json['message_id']) ?? _stringOf(json['messageId']),
      fileName: fileName,
      fileSize: _intOf(json['file_size']) ??
          _intOf(json['fileSize']) ??
          _intOf(json['size']) ??
          0,
      mime: _stringOf(json['mime']) ??
          _stringOf(json['content_type']) ??
          AttachmentRules.mimeOf(fileName),
      path: _stringOf(json['path']) ?? _stringOf(json['local_path']) ?? '',
      width: _intOf(json['width']),
      height: _intOf(json['height']),
      fileId: _stringOf(json['file_id']) ?? _stringOf(json['fileId']),
      url: _stringOf(json['url']),
    );
  }

  factory Attachment.fromJson(Map<String, Object?> json) =>
      Attachment.fromDbJson(json);

  /// 从 drift 数据行（`Attachments`）构造；用 dynamic 读取，避免反向依赖 DB 层。
  factory Attachment.fromRow(Object row) {
    final dynamic r = row;
    final fileName = _stringOf(r.fileName) ?? _stringOf(r.file_name) ?? '附件';
    return Attachment(
      id: _stringOf(r.id) ?? fileName,
      sessionId: _stringOf(r.sessionId) ?? _stringOf(r.session_id),
      messageId: _stringOf(r.messageId) ?? _stringOf(r.message_id),
      fileName: fileName,
      fileSize: _intOf(r.fileSize) ?? _intOf(r.file_size) ?? 0,
      mime: _stringOf(r.mime) ?? AttachmentRules.mimeOf(fileName),
      path: _stringOf(r.path) ?? '',
      width: _intOf(r.width),
      height: _intOf(r.height),
      fileId: _stringOf(r.fileId) ?? _stringOf(r.file_id),
      url: _stringOf(r.url),
    );
  }

  /// 本地文件新建附件（id 由调用方/工具生成，避免这里依赖 uuid 包）。
  factory Attachment.local({
    required String path,
    String? id,
    String? fileName,
    int? fileSize,
    String? mime,
    int? width,
    int? height,
    String? sessionId,
    String? messageId,
  }) {
    final name = fileName ?? AttachmentRules.fileNameOf(path);
    return Attachment(
      id: id ?? '${DateTime.now().microsecondsSinceEpoch}-$name',
      sessionId: sessionId,
      messageId: messageId,
      fileName: name,
      fileSize: fileSize ?? 0,
      mime: mime ?? AttachmentRules.mimeOf(name),
      path: path,
      width: width,
      height: height,
    );
  }

  @override
  String toString() => 'Attachment($id, $fileName, $fileSize B)';
}

/// 附件规则：单条消息上限、大小上限、类型白名单。
class AttachmentRules {
  const AttachmentRules._();

  /// 一条消息最多 50 个附件（ui-strings §3 原文 [确定]）。
  static const int maxPerMessage = 50;

  /// 单文件字节上限（[推断]，字符串表只给了「MB，上限 」片段）。
  static const int maxFileBytes = 20 * 1024 * 1024;

  /// 图片字节上限（[推断]）。
  static const int maxImageBytes = 20 * 1024 * 1024;

  /// 文案（ui-strings §3 原文）。
  static const String tooManyMessage = '一条消息最多 50 个附件';
  static const String unsupportedTypePrefix = '不支持这种文件类型：';
  static const String tooLargePrefix = '文件太大：';
  static const String missingFilePrefix = '文件不见了：';

  /// 图片扩展名。
  static const Set<String> imageExtensions = <String>{
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'bmp',
    'heic',
    'heif',
    'avif',
  };

  /// 允许的扩展名白名单（图片 + 常见文档 + 代码/文本）。
  static const Set<String> allowedExtensions = <String>{
    // 图片
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'bmp',
    'heic',
    'heif',
    // 文档
    'pdf',
    'txt',
    'md',
    'markdown',
    'csv',
    'json',
    'xml',
    'yaml',
    'yml',
    'log',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'epub',
    // 代码/配置
    'dart',
    'js',
    'ts',
    'jsx',
    'tsx',
    'py',
    'java',
    'kt',
    'kts',
    'go',
    'rs',
    'c',
    'h',
    'cpp',
    'hpp',
    'cs',
    'rb',
    'php',
    'swift',
    'sql',
    'sh',
    'bat',
    'ps1',
    'html',
    'htm',
    'css',
    'scss',
    'toml',
    'ini',
    'conf',
  };

  /// 允许的 MIME 前缀（扩展名不认识时兜底）。
  static const List<String> allowedMimePrefixes = <String>[
    'image/',
    'text/',
    'audio/',
    'video/',
    'application/pdf',
    'application/json',
    'application/xml',
    'application/zip',
    'application/gzip',
    'application/msword',
    'application/vnd.openxmlformats-officedocument',
    'application/vnd.ms-excel',
    'application/vnd.ms-powerpoint',
    'application/vnd.oasis.opendocument',
    'application/octet-stream',
  ];

  /// 扩展名（不含点，小写）。
  static String extensionOf(String fileName) {
    final name = fileName.trim();
    final slash = name.lastIndexOf('/');
    final backslash = name.lastIndexOf(r'\');
    final base = name.substring((slash > backslash ? slash : backslash) + 1);
    final dot = base.lastIndexOf('.');
    if (dot <= 0 || dot == base.length - 1) return '';
    return base.substring(dot + 1).toLowerCase();
  }

  /// 从路径取文件名。
  static String fileNameOf(String path) {
    final slash = path.lastIndexOf('/');
    final backslash = path.lastIndexOf(r'\');
    return path.substring((slash > backslash ? slash : backslash) + 1);
  }

  static bool isImageMime(String? mime) =>
      (mime ?? '').toLowerCase().trim().startsWith('image/');

  static bool isImageFile(String fileName, {String? mime}) {
    if (isImageMime(mime)) return true;
    return imageExtensions.contains(extensionOf(fileName));
  }

  /// 按 MIME/扩展名猜 MIME。
  static String mimeOf(String fileName) {
    const map = <String, String>{
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'bmp': 'image/bmp',
      'heic': 'image/heic',
      'heif': 'image/heif',
      'pdf': 'application/pdf',
      'txt': 'text/plain',
      'md': 'text/markdown',
      'markdown': 'text/markdown',
      'csv': 'text/csv',
      'json': 'application/json',
      'xml': 'application/xml',
      'yaml': 'text/yaml',
      'yml': 'text/yaml',
      'html': 'text/html',
      'htm': 'text/html',
      'css': 'text/css',
      'js': 'text/javascript',
      'ts': 'text/typescript',
      'dart': 'text/x-dart',
      'py': 'text/x-python',
      'java': 'text/x-java',
      'zip': 'application/zip',
    };
    return map[extensionOf(fileName)] ?? 'application/octet-stream';
  }

  /// 校验一个待添加附件；合法返回 `null`，否则返回可直接展示的中文文案。
  static String? validate({
    required String fileName,
    required int fileSize,
    String? mime,
  }) {
    final limit = maxBytesFor(mime, fileName: fileName);
    if (fileSize > limit) return tooLargeMessage(fileSize, limit: limit);
    final ext = extensionOf(fileName);
    final knownExt = allowedExtensions.contains(ext);
    final knownMime = allowedMimePrefixes.any(
      (prefix) => (mime ?? '').toLowerCase().trim().startsWith(prefix),
    );
    if (!knownExt && !knownMime) return unsupportedMessage(fileName);
    return null;
  }

  /// 校验 [Attachment] 实例（大小未知时跳过大小检查）。
  static String? validateAttachment(Attachment attachment) => validate(
        fileName: attachment.fileName,
        fileSize: attachment.fileSize,
        mime: attachment.mime,
      );

  /// 批量校验：返回第一个错误文案。
  static String? validateAll(Iterable<Attachment> attachments) {
    if (attachments.length > maxPerMessage) return tooManyMessage;
    for (final attachment in attachments) {
      final error = validateAttachment(attachment);
      if (error != null) return error;
    }
    return null;
  }

  /// 追加时可用的剩余名额。
  static int remainingSlots(int currentCount) {
    final left = maxPerMessage - currentCount;
    return left < 0 ? 0 : left;
  }

  /// 单个附件的字节上限（图片走图片上限）。
  static int maxBytesFor(String? mime, {String? fileName}) {
    if (isImageMime(mime) ||
        (mime == null || mime.trim().isEmpty) ||
        isImageFile(fileName ?? '', mime: mime)) {
      return isImageMime(mime) || isImageFile(fileName ?? '', mime: mime)
          ? maxImageBytes
          : maxFileBytes;
    }
    return maxFileBytes;
  }

  /// `文件太大：3.2MB，上限 20MB`。
  static String tooLargeMessage(int fileSize, {int limit = maxFileBytes}) =>
      '$tooLargePrefix${formatMb(fileSize)}MB，上限 ${formatMb(limit)}MB';

  /// `不支持这种文件类型：foo.exe`。
  static String unsupportedMessage(String fileName) =>
      '$unsupportedTypePrefix$fileName';

  /// `文件不见了：/path/to/a.png`。
  static String missingFileMessage(String path) => '$missingFilePrefix$path';

  /// 已上传/待上传文案（ui-strings §3）。
  static const String uploadingMessage = '正在上传附件…';

  /// 「已压缩 1.2MB」片段（ui-strings §3 `已压缩 `）。
  static String compressedMessage(int fileSize) =>
      '已压缩 ${formatSize(fileSize)}';

  /// 字节数 → `1.4MB` / `820KB`（不四舍五入到 0）。
  static String formatSize(int bytes) {
    if (bytes <= 0) return '0B';
    const kb = 1024;
    const mb = 1024 * 1024;
    const gb = 1024 * 1024 * 1024;
    if (bytes >= gb) return '${_trimFixed(bytes / gb)}GB';
    if (bytes >= mb) return '${_trimFixed(bytes / mb)}MB';
    if (bytes >= kb) return '${_trimFixed(bytes / kb)}KB';
    return '${bytes}B';
  }

  /// 字节数 → `3.2`（用于「MB，上限 」文案）。
  static String formatMb(int bytes) {
    if (bytes <= 0) return '0';
    final mb = bytes / (1024 * 1024);
    return _trimFixed(mb < 0.1 ? 0.1 : mb);
  }

  static String _trimFixed(double value) {
    final text = value.toStringAsFixed(1);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }
}

/// 读取会话的附件（`db.attachmentsOfSession(sessionId)`）。
///
/// DB 层是批次 B 的文件（drift `Attachments` 行），这里用 dynamic 读取以避免
/// core/chat 反向依赖 database.dart（也便于单测注入假对象）。
Future<List<Attachment>> attachmentsOfSession(
  Object database,
  String sessionId,
) async {
  final dynamic db = database;
  final rows = await db.attachmentsOfSession(sessionId) as List<Object?>;
  return attachmentsFromRows(rows);
}

/// drift 行 / Map 列表 → [Attachment] 列表（导入导出也可复用）。
List<Attachment> attachmentsFromRows(Iterable<Object?> rows) {
  final result = <Attachment>[];
  for (final row in rows) {
    if (row == null) continue;
    if (row is Map) {
      result.add(Attachment.fromDbJson(Map<String, Object?>.from(row)));
    } else {
      result.add(Attachment.fromRow(row));
    }
  }
  return result;
}

String? _stringOf(Object? value) {
  if (value == null) return null;
  if (value is String) {
    return value.isEmpty ? null : value;
  }
  final text = value.toString();
  return text.isEmpty ? null : text;
}

int? _intOf(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return int.tryParse(trimmed) ?? double.tryParse(trimmed)?.round();
  }
  return null;
}
