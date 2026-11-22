// ASR（语音识别）客户端。
//
// 端点：`asrUrlOf(baseUrl)` = `{base}/audio/transcriptions`（OpenAI Whisper 风格）。
// 请求：multipart/form-data，字段 `file`（WAV 字节，audio/wav）+ `model`（默认 whisper-1，
// 可覆盖；DeepSeek 的 ASR 模型名没有字符串证据，故用 Whisper 惯例值）。
// 响应：JSON，取 `text` 字段。
//
// 只有 DeepSeek 平台声明 supportsAsr：其它平台直接抛
// 「语音识别接口不存在：当前平台可能不支持 ASR（目前只有 DeepSeek 提供）」。
//
// 错误全部转成 VoiceError，UI 用 `voiceErrorMessage(e)` 展示。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:keepsake/core/voice/voice_error.dart';
import 'package:keepsake/core/voice/voice_guards.dart';

/// ASR 路径后缀（推断，OpenAI Whisper 习惯）。
const String asrPathSuffix = '/audio/transcriptions';

/// 默认 ASR 模型名（Whisper 惯用值，可被调用方覆盖）。
const String defaultAsrModel = 'whisper-1';

/// 推断的 ASR 端点。
String asrUrlOf(String baseUrl) {
  return '${normalizeVoiceBaseUrl(baseUrl)}$asrPathSuffix';
}

/// 语音识别客户端。
class AsrClient {
  AsrClient({
    http.Client? client,
    this.timeout = const Duration(seconds: 60),
  }) : _injectedClient = client;

  final http.Client? _injectedClient;

  /// 单次请求超时。
  final Duration timeout;
  http.Client? _ownedClient;

  http.Client get _http => _injectedClient ?? (_ownedClient ??= http.Client());

  /// 把 WAV 字节转写成文本。
  ///
  /// [caps] 来自 `VoiceCapabilities.forProvider(provider)`。
  /// 返回去掉首尾空白后的识别文本；空文本、无 text 字段、解析失败都抛 VoiceError。
  Future<String> transcribe({
    required VoiceCapabilities caps,
    required Uint8List wav,
    String? model,
    String? language,
    String filename = 'keepsake_rec.wav',
  }) async {
    final baseUrl = caps.baseUrl?.trim() ?? '';
    final apiKey = caps.apiKey?.trim() ?? '';
    if (baseUrl.isEmpty || apiKey.isEmpty) {
      throw const VoiceError.notConfigured();
    }
    if (!voiceSupportsAsr(caps)) {
      throw const VoiceError.asrUnsupported();
    }
    if (wav.isEmpty) {
      throw const VoiceError.recordingEmpty();
    }
    final uri = Uri.tryParse(asrUrlOf(baseUrl));
    if (uri == null || uri.host.isEmpty) {
      throw const VoiceError.notConfigured();
    }

    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..headers['Accept'] = 'application/json'
      ..fields['model'] = _nonEmpty(model) ?? defaultAsrModel;
    final languageCode = _nonEmpty(language);
    if (languageCode != null) {
      request.fields['language'] = languageCode;
    }
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        wav,
        filename: filename,
        contentType: http.MediaType('audio', 'wav'),
      ),
    );

    try {
      final streamed = await _http.send(request).timeout(timeout);
      final status = streamed.statusCode;
      final bodyBytes = await streamed.stream.toBytes().timeout(timeout);
      return _decodeResponse(status, bodyBytes);
    } on VoiceError {
      rethrow;
    } on TimeoutException catch (error) {
      throw VoiceError.network(cause: error);
    } on http.ClientException catch (error) {
      throw VoiceError.network(cause: error);
    } on SocketException catch (error) {
      throw VoiceError.network(cause: error);
    } catch (error) {
      throw VoiceError.wrap(
        error,
        kind: VoiceErrorKind.asrBadResponse,
        message: '${VoiceText.serviceErrorPrefix}$error',
      );
    }
  }

  /// 关闭内部创建的 HTTP client（注入的 client 由调用方管理）。
  void close() {
    _ownedClient?.close();
    _ownedClient = null;
  }

  String _decodeResponse(int status, Uint8List bodyBytes) {
    if (status == 404 || status == 405 || status == 501) {
      // 端点不存在 → 平台不支持 ASR
      throw const VoiceError.asrUnsupported();
    }
    if (status < 200 || status >= 300) {
      throw VoiceError(
        VoiceErrorKind.asrBadResponse,
        '${VoiceText.responseErrorPrefix}${VoiceError.httpDetail(status)}',
        statusCode: status,
      );
    }

    final body = utf8.decode(bodyBytes, allowMalformed: true).trim();
    if (body.isEmpty) {
      throw const VoiceError.asrEmptyResponse();
    }

    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      decoded = null;
    }
    if (decoded == null) {
      // Whisper 兼容服务偶尔直接回纯文本；明确是 JSON 片段则按解析失败处理。
      if (body.startsWith('{') || body.startsWith('[')) {
        throw const VoiceError.asrBadResponse();
      }
      if (body.isEmpty) throw const VoiceError.asrNoSpeech();
      return body;
    }
    if (decoded is String) {
      final text = decoded.trim();
      if (text.isEmpty) throw const VoiceError.asrNoSpeech();
      return text;
    }
    if (decoded is! Map) {
      throw const VoiceError.asrBadResponse();
    }
    final textValue = decoded['text'];
    if (textValue is! String) {
      throw const VoiceError.asrNoText();
    }
    final text = textValue.trim();
    if (text.isEmpty) {
      throw const VoiceError.asrNoSpeech();
    }
    return text;
  }
}

String? _nonEmpty(String? value) {
  final text = value?.trim() ?? '';
  return text.isEmpty ? null : text;
}
