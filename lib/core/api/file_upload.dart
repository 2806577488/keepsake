/// Keepsake（留声）— 文件上传（Files API）。
///
/// 协议证据（`reports/apk/http-api.md` §5）：`POST {base}/files`、
/// `multipart/form-data`、字段 `file` / `purpose`、响应取 `id` →
/// 作为消息里的 `file_id`；文案「上传返回里没有文件 id：」「上传失败：」
/// 「正在上传附件…」「附件上传失败」。
///
/// 符号证据（`dart-symbols.md` §2）：`uploadFile`、`uploadAttachment`、
/// `FileUploader`、`UploadedFile`、`filesUrl`、`file_id`。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:http/http.dart' as http;

import '../chat/attachments.dart';
import 'chat_backend.dart'
    show ApiError, ApiErrorKind, apiErrorFromStatus, extractApiErrorDetail;
import 'provider_models.dart';

/// 上传失败前缀（ui-strings §3 原文片段）。
const String kUploadFailedPrefix = '上传失败：';

/// 附件上传失败前缀。
const String kAttachmentUploadFailedPrefix = '附件上传失败：';

/// 上传返回缺 id（http-api.md §5 原文 [确定]）。
const String kMissingFileIdPrefix = '上传返回里没有文件 id：';

/// 上传超时（大文件默认 120s）。
const Duration kDefaultUploadTimeout = Duration(seconds: 120);

/// Files API 的 `purpose` 字段（官方枚举只有三个值）。
///
/// 官方「Files API › Upload a File」
/// （https://api-docs.deepseek.com/guides/files_api#upload-a-file）：
/// `purpose` 必填，枚举为 `user_data` / `text_recognition` /
/// `rich_layout_recognition`。旧实现写的 `assistant` 不在枚举内，
/// `POST /files` 会直接 400。
///
/// - 图片、纯文本、表格、电子书 → `user_data`；
/// - PDF / Word / PPT → `text_recognition`（只取文字）或
///   `rich_layout_recognition`（保留版面插图）；用 `user_data` 传文档会 400。
///   见 https://api-docs.deepseek.com/guides/document_parsing#purposes
const String kDefaultUploadPurpose = 'user_data';

/// 文档（PDF/Word/PPT）的解析 purpose：只取文字。
const String kTextRecognitionPurpose = 'text_recognition';

/// 按扩展名/MIME 选 `purpose`（官方要求文档必须走 `text_recognition`）。
String uploadPurposeFor({String? fileName, String? mime}) {
  const documentExtensions = <String>{'pdf', 'doc', 'docx', 'ppt', 'pptx'};
  if (documentExtensions.contains(AttachmentRules.extensionOf(fileName ?? ''))) {
    return kTextRecognitionPurpose;
  }
  final mimeLower = (mime ?? '').trim().toLowerCase();
  if (mimeLower == 'application/pdf' ||
      mimeLower == 'application/msword' ||
      mimeLower == 'application/vnd.ms-powerpoint' ||
      mimeLower.contains('wordprocessingml') ||
      mimeLower.contains('presentationml')) {
    return kTextRecognitionPurpose;
  }
  return kDefaultUploadPurpose;
}

/// Files API 上传需要 Anthropic beta 头（字符串表原文 `files-api-2025-04-14`）。
const String kFilesApiBetaHeader = 'anthropic-beta';
const String kFilesApiBetaValue = 'files-api-2025-04-14';

/// `{base}/files`。
String filesUrlOf(String baseUrl) {
  final base = normalizeProviderBase(baseUrl);
  if (base.toLowerCase().endsWith('/files')) return base;
  return '$base/files';
}

/// 上传成功后的文件信息。
class UploadedFile {
  const UploadedFile({
    required this.id,
    this.fileName,
    this.mime,
    this.bytes,
    this.purpose,
  });

  /// Files API 返回的服务端 id（消息里的 `file_id`）。
  final String id;

  final String? fileName;
  final String? mime;
  final int? bytes;
  final String? purpose;

  factory UploadedFile.fromJson(
    Object? decoded, {
    String? fileName,
    String? mime,
  }) {
    if (decoded is Map) {
      final map = Map<String, Object?>.from(decoded);
      final id = (map['id'] ?? map['file_id'] ?? map['fileId'] ?? '').toString();
      // Anthropic Files API: {"id":"file_...","filename":"...","mime_type":"..."}
      return UploadedFile(
        id: id.trim(),
        fileName: (map['filename'] ?? map['name'] ?? fileName)?.toString(),
        mime: (map['mime_type'] ?? map['mime'] ?? mime)?.toString(),
        bytes: map['bytes'] is num ? (map['bytes'] as num).round() : null,
        purpose: map['purpose']?.toString(),
      );
    }
    if (decoded is String) {
      return UploadedFile(id: decoded.trim(), fileName: fileName, mime: mime);
    }
    return const UploadedFile(id: '');
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'filename': ?fileName,
        'mime_type': ?mime,
        'bytes': ?bytes,
        'purpose': ?purpose,
      };

  bool get isValid => id.trim().isNotEmpty;

  @override
  String toString() => 'UploadedFile($id)';
}

/// 可复用的上传器（持有自己的 http.Client 工厂）。
class FileUploader {
  FileUploader({
    required this.baseUrl,
    required this.apiKey,
    http.Client Function()? clientFactory,
    Duration? timeout,
  })  : _clientFactory = clientFactory ?? http.Client.new,
        timeout = timeout ?? kDefaultUploadTimeout;

  /// 平台接口地址。
  final String baseUrl;

  /// API Key（只存本机）。
  final String apiKey;

  final http.Client Function() _clientFactory;
  final Duration timeout;

  http.Client? _activeClient;
  bool _disposed = false;

  /// `POST {base}/files`。
  String get filesUrl => filesUrlOf(baseUrl);

  /// 上传本地文件（[purpose] 为 null 时按文件类型自动选）。
  Future<UploadedFile> upload({
    required String path,
    required String fileName,
    String? purpose,
    String? mime,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      throw ApiError(
        AttachmentRules.missingFileMessage(path),
        kind: ApiErrorKind.parse,
      );
    }
    final fileSize = await file.length();
    final sizeError = AttachmentRules.validate(
      fileName: fileName,
      fileSize: fileSize,
      mime: mime ?? AttachmentRules.mimeOf(fileName),
    );
    if (sizeError != null) {
      throw ApiError(sizeError, kind: ApiErrorKind.parse);
    }
    final bytes = await file.readAsBytes();
    return uploadBytes(
      bytes: bytes,
      fileName: fileName,
      purpose: purpose,
      mime: mime,
    );
  }

  /// 上传内存字节（[purpose] 为 null 时按文件类型自动选）。
  Future<UploadedFile> uploadBytes({
    required List<int> bytes,
    required String fileName,
    String? purpose,
    String? mime,
  }) async {
    if (_disposed) throw ApiError.cancelled();
    final effectivePurpose =
        purpose ?? uploadPurposeFor(fileName: fileName, mime: mime);
    final uri = Uri.tryParse(filesUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw ApiError(
        '$kUploadFailedPrefix接口地址无效（$baseUrl）',
        kind: ApiErrorKind.parse,
      );
    }

    final client = _clientFactory();
    _activeClient = client;
    try {
      // 官方要求 `purpose` 必须在 `file` 之前（http.MultipartRequest 先写
      // fields、后加 files，顺序正好正确，别把 files 提前）。
      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(_headers())
        ..fields['purpose'] = effectivePurpose;
      final contentType =
          mime == null || mime.trim().isEmpty ? null : MediaType.parse(mime);
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName,
          contentType: contentType,
        ),
      );

      final streamed = await client.send(request).timeout(timeout);
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        final mapped = apiErrorFromStatus(streamed.statusCode, body);
        throw ApiError(
          '$kUploadFailedPrefix${mapped.message}',
          statusCode: streamed.statusCode,
          body: body,
          cause: mapped,
          kind: mapped.kind,
        );
      }
      final uploaded = _parseUploaded(body, fileName: fileName, mime: mime);
      if (!uploaded.isValid) {
        throw ApiError(
          '$kMissingFileIdPrefix${_snippet(body)}',
          statusCode: streamed.statusCode,
          body: body,
          kind: ApiErrorKind.parse,
        );
      }
      return uploaded;
    } on TimeoutException catch (error) {
      throw ApiError(
        '$kUploadFailedPrefix${ApiError.timeout(error).message}',
        cause: error,
        kind: ApiErrorKind.timeout,
      );
    } on http.ClientException catch (error) {
      throw ApiError(
        '$kUploadFailedPrefix${ApiError.network(error).message}',
        cause: error,
        kind: ApiErrorKind.network,
      );
    } on ApiError {
      rethrow;
    } catch (error) {
      throw ApiError(
        '$kUploadFailedPrefix${extractApiErrorDetail(error.toString()) ?? error}',
        cause: error,
        kind: ApiErrorKind.unknown,
      );
    } finally {
      if (identical(_activeClient, client)) _activeClient = null;
      client.close();
    }
  }

  /// 上传附件并返回带 `file_id` 的新附件对象（[purpose] 为 null 时自动选）。
  Future<Attachment> uploadAttachment(
    Attachment attachment, {
    String? purpose,
  }) async {
    try {
      final uploaded = await upload(
        path: attachment.path,
        fileName: attachment.fileName,
        purpose: purpose,
        mime: attachment.mime,
      );
      return attachment.copyWith(fileId: uploaded.id);
    } on ApiError catch (error) {
      throw ApiError(
        '$kAttachmentUploadFailedPrefix${error.message}',
        statusCode: error.statusCode,
        body: error.body,
        cause: error,
        kind: error.kind,
      );
    }
  }

  void dispose() {
    _disposed = true;
    final client = _activeClient;
    _activeClient = null;
    client?.close();
  }

  Map<String, String> _headers() {
    final headers = <String, String>{
      'accept': 'application/json',
    };
    final key = apiKey.trim();
    if (key.isNotEmpty) {
      headers['authorization'] = 'Bearer $key';
      headers['x-api-key'] = key;
      headers['anthropic-version'] = '2023-06-01';
    }
    // Files API 的 beta 头（字符串表原文值）。
    headers[kFilesApiBetaHeader] = kFilesApiBetaValue;
    return headers;
  }

  UploadedFile _parseUploaded(
    String body, {
    String? fileName,
    String? mime,
  }) {
    if (body.trim().isEmpty) {
      return UploadedFile(id: '', fileName: fileName, mime: mime);
    }
    try {
      final decoded = jsonDecode(body);
      return UploadedFile.fromJson(decoded, fileName: fileName, mime: mime);
    } catch (_) {
      return UploadedFile(id: '', fileName: fileName, mime: mime);
    }
  }

  String _snippet(String body) {
    final text = body.trim();
    if (text.isEmpty) return '（空响应）';
    return text.length > 300 ? '${text.substring(0, 300)}…' : text;
  }
}

/// 上传本地文件（一次性调用；[purpose] 为 null 时按文件类型自动选）。
Future<UploadedFile> uploadFile({
  required String baseUrl,
  required String apiKey,
  required String path,
  String? fileName,
  String? mime,
  String? purpose,
  http.Client? client,
  Duration? timeout,
}) async {
  final name = fileName ?? AttachmentRules.fileNameOf(path);
  final uploader = FileUploader(
    baseUrl: baseUrl,
    apiKey: apiKey,
    timeout: timeout,
    clientFactory: client == null ? null : () => client,
  );
  try {
    return await uploader.upload(
      path: path,
      fileName: name,
      purpose: purpose,
      mime: mime,
    );
  } finally {
    if (client == null) uploader.dispose();
  }
}

/// 上传附件，返回 Files API 的 `file_id`（失败抛 [ApiError]）。
///
/// [purpose] 为 null 时按附件类型自动选（PDF/Word/PPT → `text_recognition`，
/// 其余 → `user_data`），见 [uploadPurposeFor]。
Future<String> uploadAttachment(
  Attachment attachment, {
  required String baseUrl,
  required String apiKey,
  http.Client? client,
  String? purpose,
  Duration? timeout,
}) async {
  final uploader = FileUploader(
    baseUrl: baseUrl,
    apiKey: apiKey,
    timeout: timeout,
    clientFactory: client == null ? null : () => client,
  );
  try {
    final uploaded = await uploader.upload(
      path: attachment.path,
      fileName: attachment.fileName,
      purpose: purpose,
      mime: attachment.mime,
    );
    return uploaded.id;
  } on ApiError catch (error) {
    // 不重复叠前缀（错误在上层可能已经带过一次）。
    final message = error.message.startsWith(kAttachmentUploadFailedPrefix)
        ? error.message
        : '$kAttachmentUploadFailedPrefix${error.message}';
    throw ApiError(
      message,
      statusCode: error.statusCode,
      body: error.body,
      cause: error,
      kind: error.kind,
    );
  } finally {
    if (client == null) uploader.dispose();
  }
}
