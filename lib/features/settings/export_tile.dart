/// Keepsake（留声）— 设置页「导出备份」入口。
///
/// 依据：`dart-symbols.md`（`features/settings/export_tile.dart`：
/// `ExportBackupTile` + 私有 `_ExportBackupTileState` / `_export`）、
/// `ui-strings.txt` §10（原文文案）、批次 E 冻结的 `core/export/exporter.dart` 契约。
///
/// 流程：`exportToFile(db)` → 临时目录里生成 DeepSeek 兼容 ZIP
/// （文件名「Keepsake 导出备份（<日期>）」）→ `share_plus` 分享 → toast「已导出 N 个对话」。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:keepsake/core/export/exporter.dart';
import 'package:keepsake/core/providers.dart';

/// 「导出备份」行。
class ExportBackupTile extends ConsumerStatefulWidget {
  const ExportBackupTile({super.key});

  @override
  ConsumerState<ExportBackupTile> createState() => _ExportBackupTileState();
}

class _ExportBackupTileState extends ConsumerState<ExportBackupTile> {
  bool _exporting = false;

  void _toast(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  /// 导出全部会话为 ZIP 并唤起分享。
  Future<void> _export() async {
    if (_exporting) return;
    final db = ref.read(databaseProvider);
    try {
      final sessions = await db.allSessions();
      if (sessions.isEmpty) {
        _toast('还没有会话可以导出');
        return;
      }
    } catch (error) {
      _toast('导出失败：$error');
      return;
    }
    if (!mounted) return;
    setState(() => _exporting = true);
    try {
      final result = await exportToFile(db);
      if (!mounted) return;
      try {
        await SharePlus.instance.share(
          ShareParams(
            files: <XFile>[XFile(result.path, mimeType: 'application/zip')],
            subject: result.fileName,
            text: result.fileName,
          ),
        );
      } catch (_) {
        // 分享取消/平台不支持时不算导出失败，至少告诉用户文件已生成。
      }
      if (mounted) _toast('已导出 ${result.sessions} 个对话');
    } catch (error) {
      if (mounted) _toast('导出失败：$error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.file_download_outlined),
      title: const Text('导出备份'),
      subtitle: const Text('把本机全部会话导成 ZIP（含图片原件，格式与 DeepSeek 导出一致）'),
      trailing: _exporting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      onTap: _exporting ? null : _export,
    );
  }
}
