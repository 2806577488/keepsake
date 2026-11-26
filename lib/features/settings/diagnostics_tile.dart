/// Keepsake（留声）— 设置页「导出诊断日志」入口（v0.4.39）。
///
/// 和「导出备份」不同：这里只导**排障信息**（版本/系统/脱敏设置/会话数/库大小），
/// 不含聊天原文与 API Key；出问题时让用户分享这个文件即可。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:keepsake/core/diagnostics.dart';
import 'package:keepsake/core/providers.dart';
import '../../core/ui/toast.dart';

/// 「导出诊断日志」行。
class DiagnosticsTile extends ConsumerStatefulWidget {
  const DiagnosticsTile({super.key});

  @override
  ConsumerState<DiagnosticsTile> createState() => _DiagnosticsTileState();
}

class _DiagnosticsTileState extends ConsumerState<DiagnosticsTile> {
  bool _exporting = false;

  void _toast(String message) {
    showTopToast(context, message);
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final file = await exportDiagnosticsFile(
        db: ref.read(databaseProvider),
        settings: ref.read(settingsProvider),
      );
      if (!mounted) return;
      try {
        await SharePlus.instance.share(
          ShareParams(
            files: <XFile>[XFile(file.path, mimeType: 'text/plain')],
            subject: 'Keepsake 诊断信息',
            text: 'Keepsake 诊断信息（不含聊天原文与 API Key）',
          ),
        );
      } catch (_) {
        // 分享取消/平台不支持：文件已生成，不当作失败。
      }
      if (mounted) _toast('诊断日志已导出');
    } catch (error) {
      if (mounted) _toast('导出诊断日志失败：$error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.bug_report_outlined),
      title: const Text('导出诊断日志'),
      subtitle: const Text('版本 / 系统 / 脱敏设置 / 会话数（不含聊天原文与 Key），出问题时分享给开发者'),
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
