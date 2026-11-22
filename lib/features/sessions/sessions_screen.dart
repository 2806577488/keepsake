/// Keepsake（留声）— 会话列表页（首页）。
///
/// 依据：`reports/apk/dart-symbols.md`（`features/sessions/sessions_screen.dart` 的私有符号：
/// `_SessionsScreenState` / `_SearchResults` / `_EmptyState` / `_ErrorState` /
/// `_confirmDelete` / `_newSession` / `_openSession` / `_relativeTime`）、
/// `ui-strings.txt` §1（全部原文文案）、`db-schema.md`（sessions 列 / 搜索 SQL）、
/// `next-steps.md` §2（空态文案、点击进入 `ChatScreen`）。
///
/// 页面结构：
/// - AppBar：「留声」+ 多选 / 搜索 / 设置入口；搜索态把标题换成输入框（hint「搜索标题或聊天内容」）。
/// - 多选态（左上角 checklist 按钮或长按某行进入）：标题「已选 N」，leading 关闭退出，
///   actions = 全选/全不选 / 导出 / 删除；每行 leading 换成 Checkbox，隐藏「更多」、禁用左滑删除；
///   删除 = 确认一次后逐条级联删除（`deleteSession` + `usageStore.resetSession` + 孤儿角色卡清理）；
///   导出 = 底部弹窗二选一（存到手机 / 分享），只打包选中的会话。
/// - 顶部：导入进度条（`importTaskProvider` / `importProgressProvider`，批次 E），
///   完成后自动消失并 toast「已新增 N 个对话」；有失败时保留「有 N 条没导上」+「重试没导上的」。
/// - 列表：按 `updated_at` 倒序（置顶优先），行 = 标题 / 相对时间 / 消息数；
///   点进聊天页，⋮ 菜单 = 重命名 / 置顶 / 删除会话 / 补建角色卡；左滑删除（带确认）。
/// - 搜索态：全局搜索结果（消息正文命中 + 所属会话标题），空态「没有找到包含「q」的内容」。
/// - 空态：「点右下角「新对话」开始，或从设置里导入 DeepSeek 的导出包」。
/// - FAB：「新对话」（先 `createSession` 再进 `ChatScreen`）。
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:keepsake/core/brain/brain_service.dart';
import 'package:keepsake/core/characters/card_backfill_task.dart';
import 'package:keepsake/core/characters/character_service.dart';
import 'package:keepsake/core/chat/blocks.dart';
import 'package:keepsake/core/export/exporter.dart';
import 'package:keepsake/core/import/import_task.dart';
import 'package:keepsake/core/providers.dart';
import 'package:keepsake/core/usage/usage_store.dart';
import 'package:keepsake/features/chat/chat_screen.dart';
import 'package:keepsake/features/sessions/sessions_providers.dart';
import 'package:keepsake/features/settings/settings_screen.dart';

/// 会话列表首页。
class SessionsScreen extends ConsumerStatefulWidget {
  const SessionsScreen({super.key});

  @override
  ConsumerState<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends ConsumerState<SessionsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  bool _searching = false;
  bool _creating = false;

  /// 是否处在「列表内多选」状态（左上角按钮进入）。
  bool _selecting = false;

  /// 选中的会话 id（退出选择态时清空）。
  final Set<String> _selectedIds = <String>{};

  /// 选区导出中（防止重复点「导出」）。
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    // 启动后静默补一次：角色卡名收敛 + 把已导入但还没整理的历史消化进记忆层。
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapBrain());
    // 上次导入没跑完（进程被杀 / ANR）→ 从持久化的 ZIP 断点续跑。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(importTaskProvider).resumePending();
    });
  }

  /// 幂等：已有情节的会话跳过、卡名已是主题名则不动。
  Future<void> _bootstrapBrain() async {
    try {
      final db = ref.read(databaseProvider);
      await CharacterService(db).renameGenericCards();
      await BrainService(db).consolidateImportedSessions();
    } catch (_) {
      // 整理失败不影响会话列表。
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // 搜索
  // -------------------------------------------------------------------------

  void _openSearch() {
    setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _searchController.clear();
    ref.read(sessionSearchQueryProvider.notifier).clear();
    _searchFocus.unfocus();
    if (_searching) setState(() => _searching = false);
  }

  void _onSearchChanged(String value) {
    ref.read(sessionSearchQueryProvider.notifier).setQuery(value);
  }

  // -------------------------------------------------------------------------
  // 会话操作
  // -------------------------------------------------------------------------

  Future<void> _newSession() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final db = ref.read(databaseProvider);
      final id = await db.createSession();
      if (!mounted) return;
      await _openSession(id, initialTitle: '未命名会话');
    } catch (error) {
      if (mounted) _toast('新建会话失败：$error');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _openSession(String sessionId, {String? initialTitle}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            ChatScreen(sessionId: sessionId, initialTitle: initialTitle),
      ),
    );
  }

  Future<void> _renameSession(Session session) async {
    final controller = TextEditingController(text: session.title);
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: '标题'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || !mounted) return;
    if (title.isEmpty) {
      _toast('标题不能为空');
      return;
    }
    try {
      await ref.read(databaseProvider).renameSession(session.id, title);
    } catch (error) {
      if (mounted) _toast('重命名失败：$error');
    }
  }

  Future<void> _togglePin(Session session) async {
    final pinned = isSessionPinned(session);
    try {
      await ref
          .read(databaseProvider)
          .setSessionFlag(session.id, SessionFlag.pinned, enabled: !pinned);
      if (mounted) _toast(pinned ? '已取消置顶' : '已置顶');
    } catch (error) {
      if (mounted) _toast('置顶失败：$error');
    }
  }

  /// 删除确认（文案照 ui-strings：「删除会话」「」及其消息会被删除，无法恢复。」）。
  Future<bool> _confirmDelete(Session session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除会话'),
        content: Text('「${sessionDisplayTitle(session)}」及其消息会被删除，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _deleteSession(Session session) async {
    try {
      await ref.read(databaseProvider).deleteSession(session.id);
      // 清掉该会话的单会话用量键（usage_session_<id>），避免残留。
      try {
        final store = await ref.read(usageStoreProvider.future);
        await store.resetSession(session.id);
      } catch (_) {
        // 用量清理失败不影响删会话。
      }
      if (mounted) _toast('已删除会话');
    } catch (error) {
      if (mounted) _toast('删除失败：$error');
    }
  }

  /// 为缺少角色卡的会话补建（逐条让出事件循环，可随时关页面中断；重跑会跳过已有卡的会话）。
  Future<void> _backfillCards() async {
    final sessions = ref.read(orderedSessionsProvider).value ?? const <Session>[];
    final missing = <Session>[
      for (final session in sessions)
        if ((session.characterId ?? '').isEmpty) session,
    ];
    if (missing.isEmpty) {
      _toast('所有会话都已经有角色卡');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('补建角色卡'),
        content: Text('有 ${missing.length} 个会话还没有角色卡，现在按会话内容逐个补建？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('开始补建'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // 只提示一次；补建过程不再逐条弹 toast（进度改在设置页「后台任务」看）。
    _toast('正在补建角色卡（共 ${missing.length} 个），完成前可以继续操作');
    // 交给全局后台任务：切到设置页也能看到「正在补建角色卡：done / total」。
    final task = ref.read(cardBackfillProvider.notifier);
    final CardBackfillResult result;
    try {
      result = await task.run(missing);
    } catch (error) {
      if (mounted) _toast('补建失败：$error');
      return;
    }
    if (!mounted) return;
    ref.invalidate(sessionsProvider);
    _toast(result.message);
  }

  // -------------------------------------------------------------------------
  // 列表内多选（删除 / 导出）
  // -------------------------------------------------------------------------

  /// 进入选择态（长按某行时顺带选中它）。
  void _enterSelection([Session? seed]) {
    if (_searching) return;
    final sessions =
        ref.read(orderedSessionsProvider).value ?? const <Session>[];
    if (seed == null && sessions.isEmpty) {
      _toast('还没有会话');
      return;
    }
    setState(() {
      _selecting = true;
      _selectedIds.clear();
      if (seed != null) _selectedIds.add(seed.id);
    });
  }

  /// 退出选择态并清空选中集合。
  void _exitSelection() {
    if (!_selecting && _selectedIds.isEmpty) return;
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(String sessionId) {
    setState(() {
      if (!_selectedIds.remove(sessionId)) _selectedIds.add(sessionId);
    });
  }

  /// 全选 / 全不选。
  void _toggleSelectAll(List<Session> sessions) {
    setState(() {
      final bool allSelected =
          sessions.isNotEmpty && _selectedIds.length == sessions.length;
      if (allSelected) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(sessions.map((session) => session.id));
      }
    });
  }

  /// 删除选中的会话：确认一次 → 逐条级联删除（每 8 条让出事件循环）→ 清理孤儿角色卡。
  Future<void> _deleteSelected(List<Session> allSessions) async {
    if (_selectedIds.isEmpty) return;
    final List<String> ids = _selectedIds.toList(growable: false);
    final int count = ids.length;
    final bool confirmed = (await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除会话'),
        content: Text('删除选中的 $count 个会话？无法恢复'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('删除 $count 个'),
          ),
        ],
      ),
    )) ?? false;
    if (!confirmed || !mounted) return;

    final db = ref.read(databaseProvider);
    final Set<String> characterIds = <String>{
      for (final session in allSessions)
        if (ids.contains(session.id) &&
            (session.characterId ?? '').isNotEmpty)
          session.characterId!,
    };
    UsageStore? store;
    try {
      store = await ref.read(usageStoreProvider.future);
    } catch (_) {
      // 用量清理失败不影响删会话。
    }

    var removed = 0;
    var handled = 0;
    for (final String id in ids) {
      try {
        await db.deleteSession(id);
        removed++;
      } catch (_) {
        // 单条失败不影响其余会话。
      }
      try {
        await store?.resetSession(id);
      } catch (_) {
        // 同上。
      }
      handled++;
      if (handled % 8 == 0) {
        // 让出事件循环：一次删几百条时界面不会卡住。
        await Future<void>.delayed(Duration.zero);
      }
    }

    // 孤儿角色卡：删完后没有会话再引用的就清掉（读库里的最新数据，不用列表缓存）。
    try {
      final List<Session> remaining = await db.allSessions();
      final Set<String> stillUsed = <String>{
        for (final session in remaining)
          if ((session.characterId ?? '').isNotEmpty) session.characterId!,
      };
      for (final String characterId in characterIds) {
        if (stillUsed.contains(characterId)) continue;
        try {
          await db.deleteCharacter(characterId);
        } catch (_) {
          // 角色卡清理失败不影响删会话。
        }
      }
    } catch (_) {
      // 同上。
    }

    if (!mounted) return;
    ref.invalidate(sessionsProvider);
    _exitSelection();
    _toast('已删除 $removed 个会话');
  }

  /// 「导出」：先选出口（存到手机 / 分享），再生成选中会话的 ZIP。
  Future<void> _exportSelected() async {
    if (_selectedIds.isEmpty || _exporting) return;
    final List<String> ids = _selectedIds.toList(growable: false);
    final String? mode = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('存到手机'),
              subtitle: const Text('选一个目录保存 ZIP（如下载目录）'),
              onTap: () => Navigator.of(sheetContext).pop('save'),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('分享'),
              subtitle: const Text('调系统分享面板发给其他 App'),
              onTap: () => Navigator.of(sheetContext).pop('share'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('取消'),
              onTap: () => Navigator.of(sheetContext).pop(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || mode == null) return;

    final ExportResult? result = await _buildSubsetZip(ids);
    if (result == null || !mounted) return;
    if (mode == 'share') {
      await _shareSubsetZip(result);
    } else {
      await _saveSubsetZipToDevice(result);
    }
  }

  /// 生成选中会话的 ZIP（临时目录）；失败 toast 并返回 null。
  Future<ExportResult?> _buildSubsetZip(List<String> ids) async {
    setState(() => _exporting = true);
    try {
      _toast('正在导出 ${ids.length} 个会话…');
      return await exportSubsetToFile(ref.read(databaseProvider), ids);
    } catch (error) {
      if (mounted) _toast('导出失败：$error');
      return null;
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// 出口 ①：`file_picker` 的 `saveFile` 让用户选保存位置（系统「另存为」面板）。
  Future<void> _saveSubsetZipToDevice(ExportResult result) async {
    try {
      // file_picker 13 的 saveFile 是「传 bytes 由平台写盘」（不是传路径拷贝），
      // 所以这里把生成的 ZIP 读成字节再交给系统保存。
      final bytes = await result.file.readAsBytes();
      final Uri? uri = await FilePicker.saveFile(
        fileName: result.fileName,
        bytes: bytes,
        mimeType: 'application/zip',
        dialogTitle: '保存导出的会话',
      );
      if (!mounted) return;
      if (uri == null) {
        _toast('已取消保存');
        return;
      }
      _toast('已保存到 ${_uriLabel(uri)}');
    } catch (error) {
      if (mounted) _toast('保存失败：$error');
    }
  }

  /// 出口 ②：`share_plus` 系统分享面板。
  Future<void> _shareSubsetZip(ExportResult result) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(result.path, mimeType: 'application/zip')],
          subject: result.fileName,
          text: result.fileName,
        ),
      );
      if (mounted) _toast('已导出 ${result.sessions} 个会话');
    } catch (error) {
      if (mounted) _toast('分享失败：$error');
    }
  }

  /// `file_picker` 返回的 Uri → 可读路径（Android 可能是 `content://`，退化成解码后的 path）。
  static String _uriLabel(Uri uri) {
    if (uri.scheme == 'file') {
      try {
        return uri.toFilePath();
      } catch (_) {
        // 落到下面的通用分支。
      }
    }
    final String path = uri.path;
    if (path.isEmpty) return uri.toString();
    try {
      return Uri.decodeComponent(path);
    } catch (_) {
      return path;
    }
  }

  Future<void> _showSessionActions(Session session) async {
    final pinned = isSessionPinned(session);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                sessionDisplayTitle(session),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${_relativeTime(session.updatedAt)} · ${session.messageCount} 个对话',
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('重命名'),
              onTap: () => Navigator.of(sheetContext).pop('rename'),
            ),
            ListTile(
              leading: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(pinned ? '取消置顶' : '置顶'),
              onTap: () => Navigator.of(sheetContext).pop('pin'),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(sheetContext).colorScheme.error,
              ),
              title: Text(
                '删除会话',
                style: TextStyle(
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
              ),
              onTap: () => Navigator.of(sheetContext).pop('delete'),
            ),
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('为缺少角色卡的会话补建'),
              onTap: () => Navigator.of(sheetContext).pop('backfill'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'rename':
        await _renameSession(session);
      case 'pin':
        await _togglePin(session);
      case 'delete':
        if (await _confirmDelete(session)) await _deleteSession(session);
      case 'backfill':
        await _backfillCards();
    }
  }

  void _toast(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  // -------------------------------------------------------------------------
  // 时间
  // -------------------------------------------------------------------------

  /// 相对时间（ui-strings §1 原文：`刚刚` / ` 分钟前` / ` 小时前` / ` 天前`）。
  String _relativeTime(DateTime updatedAt) {
    final now = DateTime.now();
    final time = updatedAt.isUtc ? updatedAt.toLocal() : updatedAt;
    final diff = now.difference(time);
    if (diff.isNegative || diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    if (time.year == now.year) return '${time.month} 月 ${time.day} 日';
    return '${time.year} 年 ${time.month} 月 ${time.day} 日';
  }

  // -------------------------------------------------------------------------
  // 构建
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessions =
        ref.watch(orderedSessionsProvider).value ?? const <Session>[];
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: _searching ? 0 : null,
        leading: _searching
            ? IconButton(
                tooltip: '返回',
                icon: const Icon(Icons.arrow_back),
                onPressed: _closeSearch,
              )
            : _selecting
            ? IconButton(
                tooltip: '退出多选',
                icon: const Icon(Icons.close),
                onPressed: _exitSelection,
              )
            : IconButton(
                tooltip: '多选（删除 / 导出）',
                icon: const Icon(Icons.checklist_rounded),
                onPressed: _enterSelection,
              ),
        title: _searching
            ? _buildSearchField(theme)
            : _selecting
            ? Text('已选 ${_selectedIds.length}')
            : const Text('留声'),
        actions: _searching
            ? [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    tooltip: '清空',
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      _onSearchChanged('');
                      _searchFocus.requestFocus();
                    },
                  ),
              ]
            : _selecting
            ? _buildSelectionActions(sessions)
            : [
                IconButton(
                  tooltip: '搜索',
                  icon: const Icon(Icons.search),
                  onPressed: _openSearch,
                ),
                IconButton(
                  tooltip: '设置',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsScreen(),
                    ),
                  ),
                ),
              ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const _ImportProgressBanner(),
            Expanded(
              child: _searching
                  ? const _SearchResults()
                  : _buildSessionList(theme),
            ),
          ],
        ),
      ),
      floatingActionButton: _searching || _selecting
          ? null
          : FloatingActionButton.extended(
              onPressed: _creating ? null : _newSession,
              icon: _creating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_comment_outlined),
              label: const Text('新对话'),
            ),
    );
  }

  /// 选择态的 AppBar 按钮：全选/全不选、导出、删除。
  List<Widget> _buildSelectionActions(List<Session> sessions) {
    final allSelected =
        sessions.isNotEmpty && _selectedIds.length == sessions.length;
    final empty = _selectedIds.isEmpty;
    return <Widget>[
      IconButton(
        tooltip: allSelected ? '全不选' : '全选',
        icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
        onPressed: () => _toggleSelectAll(sessions),
      ),
      IconButton(
        tooltip: '导出选中',
        icon: _exporting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.ios_share),
        onPressed: empty || _exporting ? null : _exportSelected,
      ),
      IconButton(
        tooltip: '删除选中',
        icon: Icon(
          Icons.delete_outline,
          color: empty ? null : Theme.of(context).colorScheme.error,
        ),
        onPressed: empty ? null : () => _deleteSelected(sessions),
      ),
    ];
  }

  Widget _buildSearchField(ThemeData theme) {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocus,
      autofocus: true,
      textInputAction: TextInputAction.search,
      onChanged: _onSearchChanged,
      decoration: InputDecoration(
        hintText: '搜索标题或聊天内容',
        border: InputBorder.none,
        hintStyle: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      style: theme.textTheme.bodyLarge,
    );
  }

  Widget _buildSessionList(ThemeData theme) {
    final sessionsAsync = ref.watch(orderedSessionsProvider);
    return sessionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorState(
        message: '$error',
        onRetry: () => ref.invalidate(sessionsProvider),
      ),
      data: (sessions) {
        if (sessions.isEmpty) {
          return const _EmptyState();
        }
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 88),
          itemCount: sessions.length,
          separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
          itemBuilder: (context, index) =>
              _buildSessionTile(theme, sessions[index]),
        );
      },
    );
  }

  Widget _buildSessionTile(ThemeData theme, Session session) {
    final pinned = isSessionPinned(session);
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final selected = _selecting && _selectedIds.contains(session.id);
    return Dismissible(
      key: ValueKey<String>('session-${session.id}'),
      // 选择态禁用左滑删除，避免误操作。
      direction: _selecting
          ? DismissDirection.none
          : DismissDirection.endToStart,
      background: Container(
        color: theme.colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(
          Icons.delete_outline,
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
      confirmDismiss: (_) => _confirmDelete(session),
      onDismissed: (_) => _deleteSession(session),
      child: ListTile(
        selected: selected,
        leading: _selecting
            ? Checkbox(
                value: selected,
                onChanged: (_) => _toggleSelected(session.id),
              )
            : CircleAvatar(
                backgroundColor: pinned
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                child: Icon(
                  pinned ? Icons.push_pin : Icons.chat_bubble_outline,
                  size: 20,
                  color: pinned
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
        title: Text(
          sessionDisplayTitle(session),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: titleStyle,
        ),
        subtitle: Text(
          '${_relativeTime(session.updatedAt)} · ${session.messageCount} 个对话',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        // 选择态隐藏「更多」，避免和勾选操作抢点击。
        trailing: _selecting
            ? null
            : IconButton(
                tooltip: '更多',
                icon: const Icon(Icons.more_vert),
                onPressed: () => _showSessionActions(session),
              ),
        onTap: () {
          if (_selecting) {
            _toggleSelected(session.id);
            return;
          }
          // 导入进行中点某条会话：立刻把它插到正文导入队列最前面。
          try {
            final progress = ref.watch(importProgressProvider).value;
            if (progress?.running == true) {
              ref.read(importTaskProvider).priority(session.id);
            }
          } catch (_) {
            // 插队失败不影响打开会话。
          }
          _openSession(
            session.id,
            initialTitle: sessionDisplayTitle(session),
          );
        },
        onLongPress: () {
          if (_selecting) {
            _toggleSelected(session.id);
            return;
          }
          // 长按进入选择态并选中该行（原「更多」菜单仍可从 ⋮ 打开）。
          _enterSelection(session);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 导入进度条（会话列表顶部）
// ---------------------------------------------------------------------------

/// 顶部导入进度条：进度来自批次 E 的 `importProgressProvider`。
///
/// - 运行中：`正在导入…` / `正在导入 N / M` + 进度条 + 「取消」；
/// - 完成且无失败：toast `已新增 N 个对话` 后自动消失；
/// - 有失败：保留「有 N 条没导上」+「重试没导上的」（ui-strings §9 原文）。
class _ImportProgressBanner extends ConsumerStatefulWidget {
  const _ImportProgressBanner();

  @override
  ConsumerState<_ImportProgressBanner> createState() =>
      _ImportProgressBannerState();
}

class _ImportProgressBannerState extends ConsumerState<_ImportProgressBanner> {
  bool _dismissed = false;
  ImportPhase? _lastPhase;

  @override
  Widget build(BuildContext context) {
    // toast 只在阶段切换时提示一次（不做 setState，避免在 build 期触发重建）。
    ref.listen<AsyncValue<ImportProgress>>(importProgressProvider, (
      previous,
      next,
    ) {
      final progress = next.value;
      if (progress == null) return;
      final previousProgress = previous?.value;
      // 导入任务写库不经过列表的 drift 流，需要主动让列表失效，
      // 否则导入完成后列表还是旧的（真机验证过的 bug：要杀 App 重开才看到会话）。
      final previousTitles = previousProgress?.titlesWritten ?? 0;
      final titleBatch = progress.titlesWritten - previousTitles;
      final phaseChanged = progress.phase != previousProgress?.phase;
      if (progress.phase == ImportPhase.done ||
          progress.phase == ImportPhase.failed ||
          progress.phase == ImportPhase.cancelled ||
          titleBatch >= 24 ||
          (phaseChanged && progress.phase == ImportPhase.bodies)) {
        ref.invalidate(sessionsProvider);
      }
      final previousPhase = previous?.value?.phase;
      if (progress.phase != previousPhase &&
          (progress.phase == ImportPhase.done ||
              progress.phase == ImportPhase.failed ||
              progress.phase == ImportPhase.cancelled)) {
        _toast(progress.label);
      }
    });

    final progress = ref.watch(importProgressProvider).value;
    if (progress == null) return const SizedBox.shrink();

    // 新的导入开始时，清掉上一次「关闭」状态。
    if (progress.phase != _lastPhase) {
      _lastPhase = progress.phase;
      if (progress.running) _dismissed = false;
    }

    final showFailures =
        !progress.running && progress.hasFailures && !_dismissed;
    final showRunning = progress.running;
    if (!showRunning && !showFailures) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final subtitle = progress.currentTitle;
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    showFailures ? '有 ${progress.failed} 条没导上' : progress.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (showFailures)
                  TextButton(
                    onPressed: _retryFailed,
                    child: const Text('重试没导上的'),
                  )
                else
                  TextButton(onPressed: _cancel, child: const Text('取消')),
                // 运行中不给「关闭」（进度条应一直可见，取消请用左侧按钮）。
                if (showFailures)
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => setState(() => _dismissed = true),
                  ),
              ],
            ),
            if (showRunning)
              LinearProgressIndicator(
                value: progress.fraction,
                minHeight: 3,
                borderRadius: BorderRadius.circular(2),
              ),
            if (showRunning && subtitle != null && subtitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _cancel() async {
    ref.read(importTaskProvider).cancel();
  }

  Future<void> _retryFailed() async {
    try {
      await ref.read(importTaskProvider).retryFailed();
    } catch (error) {
      _toast('重试失败：$error');
    }
  }

  void _toast(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }
}

// ---------------------------------------------------------------------------
// 全局搜索结果
// ---------------------------------------------------------------------------

class _SearchResults extends ConsumerWidget {
  const _SearchResults();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final query = ref.watch(sessionSearchQueryProvider).trim();
    if (query.isEmpty) {
      return Center(
        child: Text(
          '搜索标题或聊天内容',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final resultsAsync = ref.watch(sessionSearchResultsProvider);
    return resultsAsync.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('搜索失败：$error', textAlign: TextAlign.center),
        ),
      ),
      data: (hits) {
        if (hits.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '没有找到包含「$query」的内容',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 88),
          itemCount: hits.length + 1,
          separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  '搜索结果',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              );
            }
            final hit = hits[index - 1];
            return _buildHit(context, hit, query);
          },
        );
      },
    );
  }

  Widget _buildHit(BuildContext context, SessionSearchHit hit, String query) {
    final theme = Theme.of(context);
    final sessionTitle = hit.sessionTitle.trim().isEmpty
        ? '未命名会话'
        : hit.sessionTitle.trim();

    // 会话标题命中（`searchSessions` 里 messageId == '' 的条目）。
    if (hit.isTitleHit) {
      return ListTile(
        leading: const Icon(Icons.title),
        title: Text(sessionTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '标题匹配 · ${_relativeTime(hit.sessionUpdatedAt)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => ChatScreen(
              sessionId: hit.sessionId,
              initialTitle: sessionTitle,
            ),
          ),
        ),
      );
    }

    final titleMatched = sessionTitle.toLowerCase().contains(
      query.toLowerCase(),
    );
    final meta = StringBuffer();
    if (titleMatched) meta.write('标题匹配 · ');
    meta
      ..write(sessionTitle)
      ..write(' · ')
      ..write(_relativeTime(hit.createdAt));
    return ListTile(
      leading: const Icon(Icons.chat_bubble_outline),
      title: Text(
        _snippet(hit.content),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        meta.toString(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              ChatScreen(sessionId: hit.sessionId, initialTitle: sessionTitle),
        ),
      ),
    );
  }

  /// 命中片段：把 blocks JSON 解成可读文字（text / thinking / 搜索标题 / 附件名），
  /// 压平空白并截断到 120 字。
  static String _snippet(String content) {
    final flat = _plainText(content);
    if (flat.isEmpty) return '（空消息）';
    if (flat.length <= 120) return flat;
    return '${flat.substring(0, 120)}…';
  }

  static String _plainText(String content) {
    final buffer = StringBuffer();
    for (final block in decodeBlocks(content)) {
      final text = switch (block.type) {
        BlockType.text || BlockType.code || BlockType.mermaid => block.text,
        BlockType.thinking => block.thinking ?? block.text,
        BlockType.webSearchResult || BlockType.webSearchToolResult =>
          block.title ?? block.snippet ?? block.url,
        BlockType.image => '[图片]${block.fileName ?? ''}',
        BlockType.file => '[文件]${block.fileName ?? ''}',
        BlockType.unknown => block.text,
      };
      if (text != null && text.trim().isNotEmpty) {
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(text);
      }
    }
    final joined = buffer.isEmpty ? content : buffer.toString();
    return joined.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _relativeTime(DateTime updatedAt) {
    final now = DateTime.now();
    final time = updatedAt.isUtc ? updatedAt.toLocal() : updatedAt;
    final diff = now.difference(time);
    if (diff.isNegative || diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    if (time.year == now.year) return '${time.month} 月 ${time.day} 日';
    return '${time.year} 年 ${time.month} 月 ${time.day} 日';
  }
}

// ---------------------------------------------------------------------------
// 空态 / 错误态
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.forum_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text('还没有会话', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '点右下角「新对话」开始，或从设置里导入 DeepSeek 的导出包',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            // 只保留右下角 FAB 一个「新对话」入口（空态按钮曾与 FAB 重复）。
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text('加载失败', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}


