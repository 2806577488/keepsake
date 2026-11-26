/// Keepsake（留声）— 诊断包：把排障需要的信息导成一段文本。
///
/// 给用户"出问题能给你材料"用：版本、系统、脱敏后的设置、会话数、库大小。
/// **绝不包含 API Key、聊天原文、记忆内容**——只写"有没有配"和计数。
library;

import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'db/database.dart';
import 'settings.dart';

/// 生成诊断文本（只组装内容，不落盘；纯函数便于测试覆盖格式）。
Future<String> buildDiagnosticsText({
  required AppDatabase db,
  required Settings settings,
}) async {
  final buffer = StringBuffer()
    ..writeln('Keepsake 诊断信息')
    ..writeln('生成时间：${DateTime.now().toIso8601String()}')
    ..writeln();

  try {
    final info = await PackageInfo.fromPlatform();
    buffer
      ..writeln('版本：${info.version} (${info.buildNumber})')
      ..writeln('包名：${info.packageName}');
  } catch (_) {
    buffer.writeln('版本：读取失败');
  }

  buffer
    ..writeln('系统：${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
    ..writeln();

  buffer
    ..writeln('设置（脱敏，不含 Key）：')
    ..writeln('  平台：${settings.providerId.isEmpty ? '未配置' : settings.providerId}')
    ..writeln('  模型：${settings.defaultModel}')
    ..writeln(
      '  思考：${settings.thinkingEnabled ? '开' : '关'} / '
      '${settings.thinkingLevel.wireName}',
    )
    ..writeln('  联网：${settings.searchEnabled ? '开' : '关'}')
    ..writeln(
      '  记忆/情绪/人格：${_on(settings.memoryEnabled)}/'
      '${_on(settings.moodEnabled)}/${_on(settings.personaEnabled)}',
    )
    ..writeln(
      '  实体字段抽取：'
      '${settings.entityExtractEveryRounds <= 0 ? '关' : '每 ${settings.entityExtractEveryRounds} 轮'}',
    )
    ..writeln(
      '  上下文：'
      '${settings.contextKeepRounds <= 0 ? '不限制' : '最近 ${settings.contextKeepRounds} 轮'}',
    )
    ..writeln();

  try {
    final sessions = await db.allSessions();
    buffer.writeln('会话数：${sessions.length}');
  } catch (_) {
    buffer.writeln('会话数：读取失败');
  }

  try {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}keepsake.sqlite');
    if (file.existsSync()) {
      final sizeKb = file.lengthSync() / 1024;
      buffer.writeln(
        '数据库：${file.path}（${sizeKb.toStringAsFixed(1)} KB）',
      );
    }
  } catch (_) {
    // 路径读不到就跳过，不影响其它信息。
  }

  return buffer.toString();
}

String _on(bool value) => value ? '开' : '关';

/// 写进临时目录并返回文件（分享用）。
Future<File> exportDiagnosticsFile({
  required AppDatabase db,
  required Settings settings,
}) async {
  final text = await buildDiagnosticsText(db: db, settings: settings);
  final dir = await getTemporaryDirectory();
  final file = File(
    '${dir.path}${Platform.pathSeparator}'
    'keepsake-diagnostics-${DateTime.now().millisecondsSinceEpoch}.txt',
  );
  await file.writeAsString(text);
  return file;
}
