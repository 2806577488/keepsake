/// Keepsake（留声）— 「用其他应用打开」的文件入口（v0.4.44）。
///
/// Manifest 声明了 VIEW + 常见文档/文本 MIME；原生把收到的文件复制到
/// `cacheDir/incoming/` 后，通过 `keepsake/intents` 通道推给 Dart：
/// - 冷启动：Dart 调 `takePending` 取（原生先把文件缓存住）；
/// - 已在前台：原生直接 `opened` 推过来。
///
/// Dart 侧收到后统一「建新会话 + 把文件挂成待发送附件」，
/// 解析交给 Files API（`text_recognition`），App 不做本地解析。
library;

import 'package:flutter/services.dart';

/// 收到的文件（本地路径 + 原始文件名 + MIME）。
class OpenWithFile {
  const OpenWithFile({
    required this.path,
    required this.name,
    required this.mime,
  });

  final String path;
  final String name;

  /// 可能为空串（provider 没给类型时）。
  final String mime;

  @override
  String toString() => 'OpenWithFile($name, $path)';
}

const MethodChannel _channel = MethodChannel('keepsake/intents');

/// 冷启动时取走原生缓存的待处理文件（没有则返回 null）。
Future<OpenWithFile?> takePendingOpen() async {
  try {
    final map = await _channel.invokeMapMethod<String, String>('takePending');
    return _fromMap(map);
  } catch (_) {
    // 原生通道不可用（如桌面测试环境）：当作没有待处理文件。
    return null;
  }
}

/// 监听前台时「用其他应用打开」的文件。
void listenOpenWith(void Function(OpenWithFile file) onFile) {
  _channel.setMethodCallHandler((MethodCall call) async {
    if (call.method != 'opened') return null;
    final file = _fromMap(call.arguments);
    if (file != null) onFile(file);
    return null;
  });
}

OpenWithFile? _fromMap(Object? raw) {
  if (raw is! Map) return null;
  final path = (raw['path'] ?? '').toString();
  if (path.isEmpty) return null;
  return OpenWithFile(
    path: path,
    name: (raw['name'] ?? '').toString().isEmpty
        ? '文件'
        : (raw['name'] ?? '').toString(),
    mime: (raw['mime'] ?? '').toString(),
  );
}
