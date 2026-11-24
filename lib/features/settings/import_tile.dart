/// Keepsake（留声）— 设置页「导入历史对话」入口。
///
/// 依据：`dart-symbols.md`（`features/settings/import_tile.dart`：`ImportHistoryTile`）、
/// `ui-strings.txt` §9（原文文案）、批次 E 冻结的 `core/import/import_task.dart` 契约、
/// `next-steps.md` §2（DeepSeek 导出 ZIP、追加不覆盖、同 id 跳过）。
///
/// 两种入口：
/// 1. 本地 ZIP（file_picker）；
/// 2. DeepSeek 历史记录下载链接（https://deepseek-chat-history-exports-prod.obs...zip?...），
///    点一下直接下载到临时目录再导入；打开时若剪贴板里就是这种链接，优先提示「直接下载并导入」。
///
/// 存储权限被拒（部分 ROM / 旧系统）时**不弹窗**：在行下方显示页面内卡片
/// （`PermissionDeniedCard`，v3.2 §2.4），永久拒绝时按钮换「去设置」。
library;

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:keepsake/core/brain/brain_service.dart';
import 'package:keepsake/core/characters/character_service.dart';
import 'package:keepsake/core/db/database.dart';
import 'package:keepsake/core/import/import_task.dart';
import 'package:keepsake/core/providers.dart';
import 'package:keepsake/core/theme.dart';
import 'package:keepsake/features/settings/permission_card.dart';
import '../../core/ui/toast.dart';

/// 是否是看起来像 DeepSeek 导出 ZIP 的下载链接。
bool _looksLikeExportUrl(String raw) {
  final text = raw.trim();
  if (!text.startsWith('http://') && !text.startsWith('https://')) return false;
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return false;
  final lower = text.toLowerCase();
  return lower.contains('.zip') ||
      lower.contains('deepseek') ||
      lower.contains('chat-history') ||
      lower.contains('export');
}

/// 「导入历史对话」行。
class ImportHistoryTile extends ConsumerStatefulWidget {
  const ImportHistoryTile({super.key});

  @override
  ConsumerState<ImportHistoryTile> createState() => _ImportHistoryTileState();
}

class _ImportHistoryTileState extends ConsumerState<ImportHistoryTile> {
  bool _picking = false;
  bool _downloading = false;
  double? _downloadProgress;

  /// 存储权限被拒时的页内卡片状态（v3.2 §2.4）；null = 不显示卡片。
  _PermissionIssue? _permission;

  /// 判断异常是不是「存储权限被拒」。
  ///
  /// Android 上 SAF 一般不需要存储权限，但部分 ROM / 旧系统选文件仍会抛
  /// `permission_denied` / `Permission denied` / `EACCES`；这几种都按权限问题
  /// 处理，**不弹窗**，改为页面内卡片引导授权。
  static bool _looksLikePermissionError(Object error) {
    final String text = error.toString().toLowerCase();
    return text.contains('permission') ||
        text.contains('denied') ||
        text.contains('eacces');
  }

  /// 主按钮：先请求存储权限；永久拒绝时引导去系统设置。
  Future<void> _onGrantPressed() async {
    final _PermissionIssue? issue = _permission;
    if (issue != null && issue.permanent) {
      await openAppSettings();
      return;
    }
    final PermissionStatus status = await Permission.storage.request();
    if (!mounted) return;
    if (status.isGranted || status.isLimited) {
      setState(() => _permission = null);
      await _import();
      return;
    }
    // 还是拒绝：永久拒绝就把按钮换成「去设置」并补一句说明。
    setState(
      () => _permission = _PermissionIssue(
        permanent: status.isPermanentlyDenied,
      ),
    );
  }

  void _toast(String message) {
    showTopToast(context, message);
  }

  /// 入口：优先识别剪贴板里的下载链接，否则让用户选「本地 ZIP / 下载链接」。
  Future<void> _import() async {
    if (_picking || _downloading) return;
    String? clipboard;
    try {
      clipboard = await Clipboard.getData(Clipboard.kTextPlain).then(
        (data) => data?.text,
      );
    } catch (_) {
      clipboard = null;
    }
    if (!mounted) return;
    final link = (clipboard ?? '').trim();
    if (_looksLikeExportUrl(link)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('发现下载链接'),
          content: Text(
            '剪贴板里是 DeepSeek 的历史记录下载链接：\n${_shortUrl(link)}\n\n'
            '直接下载并导入吗？（只会追加到现有列表，重复的对话自动跳过）',
            style: const TextStyle(height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('改选本地文件'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('下载并导入'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (ok == true) {
        await _importFromLink(link);
      }
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.folder_zip_outlined),
              title: const Text('选本地 ZIP'),
              subtitle: const Text('已经下载到手机里的 DeepSeek 导出包'),
              onTap: () => Navigator.of(sheetContext).pop('file'),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('粘贴下载链接'),
              subtitle: const Text('DeepSeek 历史记录下载链接，自动下载并导入'),
              onTap: () => Navigator.of(sheetContext).pop('link'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'file') {
      await _importFile();
    } else if (choice == 'link') {
      final text = await _askLink();
      if (text == null || !mounted) return;
      await _importFromLink(text);
    }
  }

  String _shortUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final name = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    return '${uri.host}${name.isEmpty ? '' : ' / $name'}';
  }

  /// 弹输入框让用户粘贴链接。
  Future<String?> _askLink() async {
    String? clipboard;
    try {
      clipboard = await Clipboard.getData(Clipboard.kTextPlain).then(
        (data) => data?.text?.trim(),
      );
    } catch (_) {
      clipboard = null;
    }
    final initial = _looksLikeExportUrl(clipboard ?? '') ? clipboard!.trim() : '';
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('从下载链接导入'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '把 DeepSeek 导出页给的下载链接整段粘进来（带 ?Expires=…&Signature=… 的那串）。'
              '链接有时效，过期就回导出页重新复制。',
              style: TextStyle(height: 1.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              minLines: 2,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '下载链接',
                hintText: 'https://deepseek-chat-history-exports-prod.obs...zip?...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('下载并导入'),
          ),
        ],
      ),
    );
    // 退场动画期间 TextField 仍持有 listener，提前 dispose 会红屏；交给 GC。
    return (result == null || result.isEmpty) ? null : result;
  }

  String _fileNameFor(String url) {
    final uri = Uri.tryParse(url);
    final last = uri?.pathSegments.isEmpty ?? true ? '' : uri!.pathSegments.last;
    if (last.toLowerCase().endsWith('.zip')) return last;
    return 'deepseek_data-${DateTime.now().millisecondsSinceEpoch}.zip';
  }

  /// 下载到临时目录（带进度），成功后进入导入确认。
  Future<void> _importFromLink(String url) async {
    if (!_looksLikeExportUrl(url)) {
      _toast('这不是有效的下载链接，请粘贴完整的 http(s) 链接');
      return;
    }
    setState(() {
      _downloading = true;
      _downloadProgress = null;
    });
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${_fileNameFor(url)}');
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 30);
      try {
        final request = await client.getUrl(Uri.parse(url));
        request.headers.set(
          HttpHeaders.userAgentHeader,
          'Keepsake/0.4.2 (Android; import)',
        );
        final response = await request.close();
        if (response.statusCode == 401 || response.statusCode == 403) {
          throw const _DownloadError('下载链接已过期或没有权限，请回 DeepSeek 导出页重新复制链接');
        }
        if (response.statusCode >= 400) {
          throw _DownloadError('下载失败：HTTP ${response.statusCode}');
        }
        final total = response.contentLength;
        final sink = file.openWrite();
        var received = 0;
        try {
          await for (final chunk in response) {
            sink.add(chunk);
            received += chunk.length;
            if (total > 0 && mounted) {
              setState(() => _downloadProgress = received / total);
            }
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        if (received == 0) {
          throw const _DownloadError('下载结果为空，链接可能已过期');
        }
      } finally {
        client.close(force: true);
      }
      if (!mounted) return;
      await _confirmAndStart(file, fromLink: true);
    } on _DownloadError catch (error) {
      if (mounted) _toast(error.message);
    } catch (error) {
      if (mounted) _toast('下载失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _downloadProgress = null;
        });
      }
    }
  }

  /// 本地 ZIP：选文件 → 确认 → 导入。
  Future<void> _importFile() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const <String>['zip'],
      );
      if (picked == null) return;
      final path = picked.path;
      if (path == null || path.isEmpty) {
        _toast('无法识别该文件，请选择 DeepSeek 导出的历史对话 ZIP 文件');
        return;
      }
      if (!mounted) return;
      await _confirmAndStart(File(path));
    } catch (error) {
      if (!mounted) return;
      // 权限被拒：不弹窗，页面内出卡片（v3.2 §2.4）。
      if (_looksLikePermissionError(error)) {
        final PermissionStatus status = await Permission.storage.status;
        if (!mounted) return;
        setState(
          () => _permission = _PermissionIssue(
            permanent: status.isPermanentlyDenied,
          ),
        );
        return;
      }
      _toast('导入失败：$error');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _confirmAndStart(File file, {bool fromLink = false}) async {
    if (!mounted) return;
    final choice = await _askImportMode(fromLink);
    if (choice == null || !mounted) return;
    final db = ref.read(databaseProvider);
    final task = ref.read(importTaskProvider);
    // 角色卡要按「正文」聚类：标题阶段不建卡，等正文导完再按会话内容聚类。
    task.onTitlesDone = null;
    final pending = task.start(file);
    _toast('已开始导入，进度显示在会话列表顶部');
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    unawaited(
      pending.then((_) => _applyCharacterMode(db, choice)).catchError((_) {}),
    );
  }

  /// 询问导入建卡模式（记住上次选择）；取消返回 null。
  Future<_ImportChoice?> _askImportMode(bool fromLink) async {
    final prefs = await SharedPreferences.getInstance();
    var mode = prefs.getString('import_card_mode') ?? 'per';
    final nameController = TextEditingController(text: '导入的角色');
    final result = await showDialog<_ImportChoice>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: const Text('确认导入历史对话？'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${fromLink ? '链接已下载完成。' : ''}'
                  '导入会追加到现有列表，已存在的同一对话自动跳过。'
                  '导入后如何建角色卡？',
                  style: const TextStyle(height: 1.5),
                ),
                const SizedBox(height: 8),
                RadioListTile<String>(
                  value: 'auto',
                  groupValue: mode,
                  onChanged: (value) => setLocal(() => mode = value ?? 'auto'),
                  title: const Text('自动按话题分组'),
                  subtitle: const Text('推荐：同一段关系/话题合成一张卡'),
                ),
                RadioListTile<String>(
                  value: 'single',
                  groupValue: mode,
                  onChanged: (value) => setLocal(() => mode = value ?? 'auto'),
                  title: const Text('全部并到一张角色卡'),
                ),
                if (mode == 'single')
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: '角色卡名字',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                RadioListTile<String>(
                  value: 'per',
                  groupValue: mode,
                  onChanged: (value) => setLocal(() => mode = value ?? 'auto'),
                  title: const Text('每个会话一张（不推荐）'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                _ImportChoice(
                  mode: mode,
                  singleCardName:
                      mode == 'single' ? nameController.text.trim() : null,
                ),
              ),
              child: const Text('确认导入'),
            ),
          ],
        ),
      ),
    );
    // 同上：不立即 dispose。
    if (result != null) {
      await prefs.setString('import_card_mode', result.mode);
    }
    return result;
  }

  /// 导入完成后按模式建卡/绑卡。
  ///
  /// E-05：这里以前整段 `catch (_)` 静默——任何一步失败（聚类慢/模型不可用/写库异常）
  /// 用户都只会看到「N 个会话缺少角色卡」，却不知道发生了什么、该去哪补。
  /// 现在：失败会明确提示，收尾也会再查一次缺卡数并给出「设置 › 数据维护 › 修复会话数据」的入口。
  Future<void> _applyCharacterMode(AppDatabase db, _ImportChoice choice) async {
    final service = CharacterService(db);
    try {
      final ids = await service.unboundSessionIds();
      if (ids.isEmpty) return;
      switch (choice.mode) {
        case 'auto':
          // 高级模式：按话题聚类（默认不用；话题相似 ≠ 同一段关系，容易串台）。
          await service.assignCharactersForSessions(
            ids,
            mode: CharacterImportMode.autoCluster,
          );
        case 'single':
          await service.assignCharactersForSessions(
            ids,
            mode: CharacterImportMode.singleCard,
            singleCardName: choice.singleCardName,
          );
        default:
          // 默认：每个会话独立一张卡 = 每个对话独立记忆域（不串台）。
          for (final id in ids) {
            await service.ensureForSession(id, source: kCharacterSourceImport);
          }
      }
      // 卡名收敛（未命名会话/状态句 → 主题名）+ 把整批历史消化进记忆层
      // （事实 / 情节 / 人格 / 情绪）；后台跑，失败静默。
      await service.renameGenericCards();
      await BrainService(db).consolidateImportedSessions();
    } catch (error) {
      if (mounted) {
        _toast('导入完成，但建角色卡中断了：$error（可去 设置 › 数据维护 补建）');
      }
      return;
    }
    // 收尾校验：确实还有缺卡就明说，别让用户在数据维护页自己发现（E-05）。
    try {
      final remaining = await service.unboundSessionIds();
      if (remaining.isNotEmpty && mounted) {
        _toast(
          '导入完成；还有 ${remaining.length} 个会话没有角色卡，'
          '可在 设置 › 数据维护 › 修复会话数据 一键补建',
        );
      }
    } catch (_) {
      // 校验失败不影响导入结果。
    }
  }

  Future<void> _retry() async {
    try {
      await ref.read(importTaskProvider).retryFailed();
    } catch (error) {
      if (mounted) _toast('重试失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = KeepsakeSkinColors.of(context);
    final progress = ref.watch(importProgressProvider).value;
    final running = progress?.running ?? false;
    final failures = progress != null && !running && progress.hasFailures;

    const idleSubtitle = '选本地 ZIP，或粘贴 DeepSeek 下载链接（重复自动跳过）';
    final subtitle = progress == null
        ? idleSubtitle
        : running
        ? progress.label
        : failures
        ? '有 ${progress.failed} 条没导上'
        : idleSubtitle;

    final busy = running || _picking || _downloading;

    return Column(
      children: [
        ListTile(
          enabled: !running,
          leading: const Icon(Icons.file_upload_outlined),
          title: const Text('导入历史对话'),
          subtitle: Text(
            _downloading
                ? '正在下载${_downloadProgress == null ? '…' : ' ${(_downloadProgress! * 100).toStringAsFixed(0)}%'}'
                : subtitle,
            style: failures
                ? theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  )
                : null,
          ),
          trailing: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : failures
              ? TextButton(onPressed: _retry, child: const Text('重试没导上的'))
              : const Icon(Icons.chevron_right),
          onTap: running ? null : _import,
        ),
        if (_permission != null)
          // 权限被拒：页面内卡片（不是弹窗，v3.2 §2.4）。
          PermissionDeniedCard(
            title: '需要存储权限才能导入',
            description: '从 DeepSeek 导出的对话存在手机里，读取需要授权。',
            permanent: _permission!.permanent,
            onGrant: () => unawaited(_onGrantPressed()),
            onLater: () => setState(() => _permission = null),
          ),
        if (running || _downloading)
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
            child: LinearProgressIndicator(
              value: _downloading
                  ? _downloadProgress
                  : progress?.fraction,
              minHeight: 3,
              borderRadius: s.rPill,
            ),
          ),
      ],
    );
  }
}

class _DownloadError implements Exception {
  const _DownloadError(this.message);
  final String message;
}

/// 存储权限被拒的状态（v3.2 §2.4）。
class _PermissionIssue {
  const _PermissionIssue({this.permanent = false});

  /// 是否是「永久拒绝」（用户选了「不再询问」）：
  /// 主按钮换「去设置」，并补一句「需要到系统设置里开启」。
  final bool permanent;
}

/// 导入时选的建卡模式。
class _ImportChoice {
  const _ImportChoice({required this.mode, this.singleCardName});

  /// `auto` / `single` / `per`。
  final String mode;
  final String? singleCardName;
}
