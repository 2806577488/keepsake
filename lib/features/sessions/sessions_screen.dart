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
///   点进聊天页，⋮ 菜单 = 重命名 / 置顶 / 删除会话；左滑删除（带确认）。
///   v3.3 §2.2：「补建角色卡」「清理孤立角色卡」这类**影响所有会话**的批量修复
///   已整体搬到「设置 › 数据维护」，会话列表的多选菜单里不再出现。
/// - 搜索态：全局搜索结果（消息正文命中 + 所属会话标题），空态「没有找到包含「q」的内容」。
/// - 空态：「点右下角「新对话」开始，或从设置里导入 DeepSeek 的导出包」。
/// - FAB：「新对话」（先 `createSession` 再进 `ChatScreen`）。
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:keepsake/core/brain/brain_service.dart';
import 'package:keepsake/core/characters/character_service.dart';
import 'package:keepsake/core/chat/blocks.dart';
import 'package:keepsake/core/export/exporter.dart';
import 'package:keepsake/core/import/import_task.dart';
import 'package:keepsake/core/providers.dart';
import 'package:keepsake/core/skin_tokens.dart'
    show kFabLineColor, kSelectionBarWidth;
import 'package:keepsake/core/theme.dart';
import 'package:keepsake/core/usage/usage_store.dart';
import 'package:keepsake/features/chat/chat_screen.dart';
import 'swipe_reveal_delete.dart';
import 'package:keepsake/features/sessions/delete_task.dart';
import 'package:keepsake/features/sessions/sessions_providers.dart';
import 'package:keepsake/features/settings/settings_screen.dart';
import '../../core/ui/toast.dart';

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

  /// 已确认删除、但后台任务还没删完的会话 id。
  ///
  /// 用于「乐观删除」：确认后列表里立刻消失，不等数据库删完
  /// （v3.1 §2.2 要求「被删除的会话从列表移除，不等后台完成」）。
  final Set<String> _pendingDeleteIds = <String>{};

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
      // 新会话继承设置页「对话默认 › 联网搜索」：`sessions.search_enabled` 非空、
      // DDL 默认 `false`，不显式写就会变成「关」，聊天页也不会再回落全局默认。
      final id = await db.createSession(
        searchEnabled: ref.read(settingsProvider).searchEnabled,
      );
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

  // 「为缺少角色卡的会话补建」已搬到「设置 › 数据维护」（v3.3 §2.2）：
  // 补建是影响**所有会话**的批量数据修复，不是当前会话的操作。这里不再保留
  // 任何入口；逻辑与进度在 features/settings/data_maintenance_section.dart，
  // 底层仍是全局 cardBackfillProvider。

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

  /// 删除选中的会话：确认一次 → **交给后台任务**（不受界面状态影响）。
  ///
  /// 用户点了「删除」就必须删完：他之后退出全选、离开列表、进聊天页，
  /// 都不该中断删除。所以这里不 await 删除结果，而是启动
  /// [deleteTaskProvider]（进度在「设置 → 后台任务」里看）。
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

    // 角色卡 id 先收集好（后台任务里清理孤儿卡要用）。
    final Set<String> characterIds = <String>{
      for (final session in allSessions)
        if (ids.contains(session.id) &&
            (session.characterId ?? '').isNotEmpty)
          session.characterId!,
    };

    // 后台已经有删除任务在跑：这一次不会接单（`start` 会直接返回 0），
    // 所以不能再提示「已开始删除」——那是在骗用户（E-28）。
    if (ref.read(deleteTaskProvider).running) {
      _toast('正在删除会话，请稍候再试');
      return;
    }

    // 乐观删除：列表里立刻隐藏，再交给后台任务慢慢删。
    setState(() => _pendingDeleteIds.addAll(ids));
    // 确认即交给后台任务：立刻退出多选，删除在后台跑完。
    _exitSelection();
    _toast('已开始删除 $count 个会话，进度见「设置 → 后台任务」');
    unawaited(
      ref
          .read(deleteTaskProvider.notifier)
          .start(ids: ids, characterIds: characterIds.toList(growable: false))
          .then((int removed) {
            if (!mounted) return;
            setState(() => _pendingDeleteIds.removeAll(ids));
            ref.invalidate(sessionsProvider);
            // removed == 0 只可能是事务回滚（要么全删、要么全不删），
            // 不能说成「已删除 0 个」，要给明确的失败出口。
            _toast(removed == 0 ? '删除失败：没有删掉任何会话，已整体回滚' : '已删除 $removed 个会话');
          }),
    );
  }

  /// 「导出」：先选出口（存到手机 / 分享），再生成选中会话的 ZIP。
  ///
  /// M7：出口顺序固定「存到手机」在前 —— 微信不接收 `application/zip`，
  /// 国内用户最常见的「发我微信」在分享面板里要么没有微信、要么发了失败，
  /// 所以默认动作改成先落盘，再用文件管理器发送。
  Future<void> _exportSelected() async {
    if (_selectedIds.isEmpty || _exporting) return;
    final s = KeepsakeSkinColors.of(context);
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
              subtitle: const Text('选一个目录保存 ZIP（如下载目录）· 推荐'),
              onTap: () => Navigator.of(sheetContext).pop('save'),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('分享'),
              subtitle: const Text('调系统分享面板；微信不支持 ZIP，建议先用「存到手机」'),
              onTap: () => Navigator.of(sheetContext).pop('share'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                s.icon(filled: Icons.close, outlined: Icons.close),
              ),
              title: const Text('取消'),
              onTap: () => Navigator.of(sheetContext).pop(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || mode == null) return;

    // 分享前先提示一次，并允许当场改成「存到手机」。
    String? choice = mode;
    if (choice == 'share') {
      choice = await _confirmZipShare();
      if (!mounted || choice == null) return;
    }

    final ExportResult? result = await _buildSubsetZip(ids);
    if (result == null || !mounted) return;
    if (choice == 'share') {
      await _shareSubsetZip(result);
    } else {
      await _saveSubsetZipToDevice(result);
    }
  }

  /// 分享 ZIP 前的提示（M7）。返回 `'share'`（继续分享）/ `'save'`（改成存到手机）/ null。
  Future<String?> _confirmZipShare() {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('分享 ZIP'),
        content: const Text(
          '微信不支持压缩包，可先保存再用文件管理器发送。'
          'QQ / 邮箱 / 网盘一般能直接接收。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('save'),
            child: const Text('改为存到手机'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('share'),
            child: const Text('仍要分享'),
          ),
        ],
      ),
    );
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
      // M12：SAF 返回的 content:// 是内部 id，回显只有噪音；
      // 只有真拿到 file:// 路径时才显示具体位置。
      final String? label = _uriLabel(uri);
      _toast(label == null ? '已保存到你选择的位置' : '已保存到 $label');
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

  /// `file_picker` 返回的 Uri → 可读路径；解析不出可读位置时返回 null（M12）。
  ///
  /// Android 上 SAF 的 `saveFile` 回的是 `content://com.android.providers.*/...`，
  /// 那是内部 id，直接回显只会给用户一长串 `content%3A%2F%2F...` —— 不如说
  /// 「已保存到你选择的位置」。只有真拿到 `file://` 时才显示具体路径。
  static String? _uriLabel(Uri uri) {
    if (uri.scheme != 'file') return null;
    try {
      return uri.toFilePath();
    } catch (_) {
      // 非法 file:// URI（Windows 上偶见于 URI 编码异常）：同样退回固定文案。
      return null;
    }
  }

  Future<void> _showSessionActions(Session session) async {
    final pinned = isSessionPinned(session);
    final s = KeepsakeSkinColors.of(context);
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
                _sessionSubtitle(session.updatedAt, session.messageCount),
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
                s.icon(
                  filled: Icons.delete_outline,
                  outlined: Icons.delete_outline,
                ),
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
    }
  }

  void _toast(String message) {
    showTopToast(context, message);
  }

  // -------------------------------------------------------------------------
  // 时间
  // -------------------------------------------------------------------------

  /// 会话行副标题（设计稿 A1：`N 轮 · 今天 10:41`）。
  ///
  /// 轮数按消息条数折半估算（一问一答算一轮，至少 1 轮）：列表只拿到条数，
  /// 为了精确轮数再查一次库不划算；时间用 [ _clockLabel ] 的「今天/昨天 HH:mm」。
  String _sessionSubtitle(DateTime updatedAt, int messageCount) {
    final rounds = (messageCount / 2).ceil();
    return '${rounds < 1 ? 1 : rounds} 轮 · ${_clockLabel(updatedAt)}';
  }

  /// 今天/昨天 HH:mm，更早给「M月d日」。
  String _clockLabel(DateTime time) {
    final local = time.toLocal();
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(local.year, local.month, local.day))
        .inDays;
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    if (days <= 0) return '今天 $hour:$minute';
    if (days == 1) return '昨天 $hour:$minute';
    return '${local.month}月${local.day}日';
  }

  // -------------------------------------------------------------------------
  // 构建
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 皮肤 token 入口：只有这一份 UI，A/E/H 靠 token 变形（拍板稿 §1）。
    final s = KeepsakeSkinColors.of(context);
    // 多选顶栏的「全选」在会话还没加载完时必须是禁用态（v3.2 §2.5），
    // 所以这里同时保留 AsyncValue 本体，而不只是取 .value。
    final AsyncValue<List<Session>> sessionsAsync = ref.watch(
      orderedSessionsProvider,
    );
    final sessions = sessionsAsync.value ?? const <Session>[];
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: _searching ? 0 : null,
        // 顶栏图标统一跟皮肤：尺寸 s.iconSize（H = 26）、颜色 s.iconColor（H 深青）。
        leading: _searching
            ? IconButton(
                tooltip: '返回',
                icon: Icon(
                  s.icon(filled: Icons.arrow_back, outlined: Icons.arrow_back),
                  size: s.iconSize,
                  color: s.iconColor,
                ),
                onPressed: _closeSearch,
              )
            : _selecting
            ? IconButton(
                tooltip: '退出多选',
                icon: Icon(
                  s.icon(filled: Icons.close, outlined: Icons.close),
                  size: s.iconSize,
                  color: s.iconColor,
                ),
                onPressed: _exitSelection,
              )
            : IconButton(
                tooltip: '多选（删除 / 导出）',
                icon: Icon(
                  s.icon(filled: Icons.checklist, outlined: Icons.checklist),
                  size: s.iconSize,
                  color: s.iconColor,
                ),
                onPressed: _enterSelection,
              ),
        title: _searching
            ? _buildSearchField(theme, s)
            : _selecting
            // 多选顶栏「已选 N」20/600（README §4.6）。
            ? Text(
                '已选 ${_selectedIds.length}',
                style: theme.textTheme.titleLarge,
              )
            // 列表顶栏标题 20/600（README §4.1）。
            : Text('留声', style: theme.textTheme.titleLarge),
        actions: _searching
            ? [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    tooltip: '清空',
                    // §6：清空用 Material 图标；尺寸/颜色跟皮肤。
                    icon: Icon(
                      s.icon(filled: Icons.close, outlined: Icons.close),
                      size: s.iconSize,
                      color: s.iconColor,
                    ),
                    onPressed: () {
                      _searchController.clear();
                      _onSearchChanged('');
                      _searchFocus.requestFocus();
                    },
                  ),
              ]
            : _selecting
            ? _buildSelectionActions(
                sessions,
                loading: sessionsAsync.isLoading,
              )
            : [
                IconButton(
                  tooltip: '搜索',
                  icon: Icon(
                    s.icon(filled: Icons.search, outlined: Icons.search),
                    size: s.iconSize,
                    color: s.iconColor,
                  ),
                  onPressed: _openSearch,
                ),
                IconButton(
                  tooltip: '设置',
                  icon: Icon(
                    s.icon(
                      filled: Icons.settings,
                      outlined: Icons.settings_outlined,
                    ),
                    size: s.iconSize,
                    color: s.iconColor,
                  ),
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
            const _DeleteProgressBanner(),
            Expanded(
              child: _searching
                  ? const _SearchResults()
                  : _buildSessionList(theme),
            ),
          ],
        ),
      ),
      // FAB：高 56 / 圆角按皮肤 rFab / 实心零描边 / 无投影（README §4.1、§7）。
      floatingActionButton: _searching || _selecting
          ? null
          : _NewSessionFab(creating: _creating, onTap: _newSession),
    );
  }

  /// 选择态的 AppBar 按钮：全选/全不选、导出、删除（README §4.6、§6）。
  ///
  /// [loading] 为 true（会话列表还在首屏加载）时，全选按钮**禁用**：
  /// 图标 `onV` @38%、不可点（v3.2 §2.5）。这一格只用于全选按钮，不动列表项。
  List<Widget> _buildSelectionActions(
    List<Session> sessions, {
    required bool loading,
  }) {
    final s = KeepsakeSkinColors.of(context);
    final allSelected =
        sessions.isNotEmpty && _selectedIds.length == sessions.length;
    final empty = _selectedIds.isEmpty;
    return <Widget>[
      IconButton(
        tooltip: loading ? '正在加载会话…' : (allSelected ? '全不选' : '全选'),
        // §6：多选全选 `Icons.select_all`；加载中/禁用态图标 onV @38%。
        icon: Icon(
          allSelected ? Icons.deselect : Icons.select_all,
          size: s.iconSize,
          color: loading
              ? s.c.onV.withValues(alpha: 0.38)
              : s.iconColor,
        ),
        onPressed: loading ? null : () => _toggleSelectAll(sessions),
      ),
      IconButton(
        tooltip: '导出选中',
        // §6：多选导出按 icons.md 的「导出 / 打开」行取 open_in_new；尺寸/颜色跟皮肤。
        icon: _exporting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                s.icon(
                  filled: Icons.open_in_new,
                  outlined: Icons.open_in_new,
                ),
                size: s.iconSize,
                color: s.iconColor,
              ),
        onPressed: empty || _exporting ? null : _exportSelected,
      ),
      IconButton(
        tooltip: '删除选中',
        // §6：多选删除 `Icons.delete_outline`，色 #BA1A1A（scheme.error）。
        icon: Icon(
          s.icon(filled: Icons.delete_outline, outlined: Icons.delete_outline),
          size: s.iconSize,
          color: empty
              ? Theme.of(context).colorScheme.error.withValues(alpha: 0.4)
              : Theme.of(context).colorScheme.error,
        ),
        onPressed: empty ? null : () => _deleteSelected(sessions),
      ),
    ];
  }

  /// 搜索输入框：圆角跟皮肤 rField（A 胶囊 / E 6 / H 12）、min 高 48（拍板稿 §2）。
  Widget _buildSearchField(ThemeData theme, KeepsakeSkinColors s) {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocus,
      autofocus: true,
      // 光标：selBar、宽 2dp（v3.2 §2.1，整站输入框统一）。
      cursorColor: s.c.selBar,
      cursorWidth: 2,
      textInputAction: TextInputAction.search,
      onChanged: _onSearchChanged,
      decoration: InputDecoration(
        hintText: '搜索标题或聊天内容',
        // 走 inputDecorationTheme 的 filled/highest 底，只按皮肤换成 rField 圆角。
        border: OutlineInputBorder(
          borderRadius: s.rField,
          borderSide: BorderSide.none,
        ),
        constraints: const BoxConstraints(minHeight: KeepsakeTheme.inputHeight),
        hintStyle: theme.textTheme.bodyLarge?.copyWith(color: s.c.onV),
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
      data: (allSessions) {
        // 乐观删除：已确认删除的会话立刻从列表隐藏，等后台任务删完。
        final sessions = <Session>[
          for (final session in allSessions)
            if (!_pendingDeleteIds.contains(session.id)) session,
        ];
        if (sessions.isEmpty) {
          return const _EmptyState();
        }
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 88),
          itemCount: sessions.length,
          // 分割线通栏 1px（README §1 outlineVariant）；行高由 _SessionRow 固定 68。
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) => _buildSessionTile(sessions[index]),
        );
      },
    );
  }

  Widget _buildSessionTile(Session session) {
    final pinned = isSessionPinned(session);
    final selected = _selecting && _selectedIds.contains(session.id);
    // v0.4.43：左滑露出删除，滑开后停住、垃圾桶可直接点（带确认）。
    return SwipeRevealDelete(
      // 选择态禁用左滑删除，避免误操作。
      enabled: !_selecting,
      onDelete: () async {
        if (await _confirmDelete(session)) {
          await _deleteSession(session);
        }
      },
      // 行：高 68 / 左右 16 / gap 12 / 头像 34（README §4.1）；
      // 多选态几何完全一致，复选框放在 34 槽位里（§4.6、§5）。
      child: _SessionRow(
        title: sessionDisplayTitle(session),
        subtitle: _sessionSubtitle(session.updatedAt, session.messageCount),
        pinned: pinned,
        selecting: _selecting,
        selected: selected,
        onToggleSelected: () => _toggleSelected(session.id),
        onMore: _selecting ? null : () => _showSessionActions(session),
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

/// 会话行（README §4.1、§4.6、§5）。
///
/// 普通态与多选态**几何完全一致**：行高 68、左右 16、gap 12、左侧占位 34。
/// 多选时 34 槽位里居中放 20 的复选框（§5 规则 2），标题/副标题位置不变；
/// 选中只改底色 + 左缘 2px 竖条（§5 规则 1），竖条用 Positioned 覆盖，
/// 不占布局宽度，所以文字不会左右跳。
class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.title,
    required this.subtitle,
    required this.pinned,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleSelected,
    this.onMore,
  });

  final String title;
  final String subtitle;
  final bool pinned;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleSelected;

  /// 更多（多选态为 null，位置由 trailing 占位自然收起，不影响左侧几何）。
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final skin = KeepsakeSkinColors.of(context);
    return Material(
      color: selected ? skin.selectionBg : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(
          // 行高 68（README §4.1、§4.6、§5 规则 3）。
          height: KeepsakeTheme.listRowHeight,
          child: Stack(
            children: <Widget>[
              // 选中竖条：宽度走 `kSelectionBarWidth`（当前 2dp；规范与设计稿对
              // 2 / 3dp 仍有分歧，见 docs/audit-triage-2026-11-24.md E-16，定稿后
              // 只改常量这一处）。用 Positioned 覆盖在左内边距上，不占布局宽度。
              if (selected)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: kSelectionBarWidth,
                    color: skin.selectionBar,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: KeepsakeTheme.pagePadding,
                ),
                child: Row(
                  children: <Widget>[
                    // 34 槽位：头像 / 复选框占位一致（§5 规则 2）。
                    SizedBox(
                      width: KeepsakeTheme.checkboxSlot,
                      height: KeepsakeTheme.checkboxSlot,
                      child: selecting
                          ? Center(
                              child: SizedBox(
                                width: KeepsakeTheme.checkboxSize,
                                height: KeepsakeTheme.checkboxSize,
                                child: Checkbox(
                                  value: selected,
                                  onChanged: (_) => onToggleSelected(),
                                  // 圆角与选中色都由 checkboxTheme 给，页面不写圆角。
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            )
                          : _SessionAvatar(pinned: pinned),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          // 标题：字号 / 字重 / 字距全按皮肤（A w600、E/H w700）。
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  fontSize: skin.fsTitle,
                                  fontWeight: skin.titleWeight,
                                  letterSpacing: skin.titleLetterSpacing,
                                  color: selected
                                      ? skin.onSelection
                                      : skin.c.onS,
                                ),
                          ),
                          // 标题↔元信息间距 5（拍板稿 §1 定稿，原为 2）。
                          const SizedBox(height: 5),
                          // 元信息：fsSub + E 走等宽（A/H metaFontFamily 为 null 不设）。
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  fontSize: skin.fsSub,
                                  fontFamily: skin.metaFontFamily,
                                  color: selected
                                      ? skin.onSelection
                                      : skin.c.onV,
                                ),
                          ),
                        ],
                      ),
                    ),
                    if (onMore != null)
                      IconButton(
                        tooltip: '更多',
                        // 更多图标 18（§4.1）。
                        iconSize: 18,
                        icon: Icon(
                          skin.icon(
                            filled: Icons.more_vert,
                            outlined: Icons.more_vert,
                          ),
                          color: skin.c.onV,
                        ),
                        onPressed: onMore,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 会话行头像（34 / 字 15）：圆角跟皮肤 rAvatar（E = 0 方角，A/H = 17 正圆）；
/// 置顶用 primaryContainer 底，其余用皮肤 `listAvatar` 底（README §4.1 + §0）。
class _SessionAvatar extends StatelessWidget {
  const _SessionAvatar({required this.pinned});

  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final skin = KeepsakeSkinColors.of(context);
    return Container(
      width: KeepsakeTheme.listAvatarSize,
      height: KeepsakeTheme.listAvatarSize,
      decoration: BoxDecoration(
        color: pinned ? scheme.primaryContainer : skin.listAvatarBg,
        // 形状跟皮肤：不再写死 BoxShape.circle，靠 rAvatar 变形。
        borderRadius: skin.rAvatar,
      ),
      child: Icon(
        pinned ? Icons.push_pin : Icons.chat_bubble_outline,
        size: 18,
        color: pinned ? scheme.onPrimaryContainer : skin.listAvatarFg,
      ),
    );
  }
}

/// 新对话按钮（README §4.1、§7）：高 56、左右 20、圆角按皮肤 rFab、
/// `pC` 实心 + **1px `kFabLineColor` 描边**（v3.5 定稿，零阴影下描边是唯一层级手段）、无投影。
class _NewSessionFab extends StatelessWidget {
  const _NewSessionFab({required this.creating, required this.onTap});

  final bool creating;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = KeepsakeSkinColors.of(context);
    return GestureDetector(
      onTap: creating ? null : onTap,
      child: Container(
        height: KeepsakeTheme.fabHeight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: skin.c.pC,
          borderRadius: skin.rFab,
          // v3.5：补回 1px 描边（设计库 `--fab-line` = #8CCDBB）。
          border: Border.all(color: kFabLineColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (creating)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: skin.c.onPC,
                ),
              )
            else
              // 图标尺寸跟皮肤（H = 26），色 onPC。
              Icon(
                skin.icon(filled: Icons.add, outlined: Icons.add),
                size: skin.iconSize,
                color: skin.c.onPC,
              ),
            const SizedBox(width: 8),
            Text(
              '新对话',
              style: TextStyle(
                // 字号 / 字重跟皮肤（A fsBody 15 w600、H fsBody 16 w700）。
                fontSize: skin.fsBody,
                fontWeight: skin.titleWeight,
                color: skin.c.onPC,
              ),
            ),
          ],
        ),
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
    final skin = KeepsakeSkinColors.of(context);
    final subtitle = progress.currentTitle;
    // 导入横幅当卡片处理：rCard + hairlineBorder（只有 E 会画 1px 描边）。
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Container(
        decoration: BoxDecoration(
          color: skin.c.high,
          borderRadius: skin.rCard,
          border: skin.hairlineBorder,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      showFailures
                          ? '有 ${progress.failed} 条没导上'
                          : progress.label,
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
                      icon: Icon(
                        skin.icon(filled: Icons.close, outlined: Icons.close),
                        size: skin.iconSize,
                        color: skin.iconColor,
                      ),
                      onPressed: () => setState(() => _dismissed = true),
                    ),
                ],
              ),
              if (showRunning)
                LinearProgressIndicator(
                  value: progress.fraction,
                  minHeight: 3,
                  // 进度条两端圆角走皮肤 rPill，页面不写死数值。
                  borderRadius: skin.rPill,
                ),
              if (showRunning && subtitle != null && subtitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: skin.c.onV,
                    ),
                  ),
                ),
              // M1（轻量版）：没有前台服务，国产 ROM 会把后台任务冻结/杀掉；
              // 这里明示「可续跑」，避免用户以为进度卡死、反复杀 App 重开。
              if (showRunning)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '切到后台可能被系统暂停，回到 App 会自动续跑',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: skin.c.onV,
                    ),
                  ),
                ),
            ],
          ),
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
    showTopToast(context, message);
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

  /// 命中行做成卡片：rCard + hairlineBorder（只有 E 会画 1px 描边，A/H 无线）。
  Widget _hitCard(BuildContext context, Widget child) {
    final skin = KeepsakeSkinColors.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: skin.rCard,
        border: skin.hairlineBorder,
      ),
      child: child,
    );
  }

  Widget _buildHit(BuildContext context, SessionSearchHit hit, String query) {
    final theme = Theme.of(context);
    final skin = KeepsakeSkinColors.of(context);
    final sessionTitle = hit.sessionTitle.trim().isEmpty
        ? '未命名会话'
        : hit.sessionTitle.trim();

    // 会话标题命中（`searchSessions` 里 messageId == '' 的条目）。
    if (hit.isTitleHit) {
      return _hitCard(
        context,
        ListTile(
          leading: const Icon(Icons.title),
          title: Text(
            sessionTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '标题匹配 · ${_relativeTime(hit.sessionUpdatedAt)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: skin.c.onV),
          ),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => ChatScreen(
                sessionId: hit.sessionId,
                initialTitle: sessionTitle,
              ),
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
    return _hitCard(
      context,
      ListTile(
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
          style: theme.textTheme.bodySmall?.copyWith(color: skin.c.onV),
        ),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) =>
                ChatScreen(sessionId: hit.sessionId, initialTitle: sessionTitle),
          ),
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
    final skin = KeepsakeSkinColors.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        // 空态容器：rCard + hairlineBorder（只有 E 会画 1px 描边）。
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          decoration: BoxDecoration(
            borderRadius: skin.rCard,
            border: skin.hairlineBorder,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // mark 64 + 图标尺寸跟皮肤（H = 26）。
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: skin.c.highest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.forum_outlined,
                  size: skin.iconSize,
                  color: skin.c.iconC,
                ),
              ),
              const SizedBox(height: 16),
              // 标题 20/600（README §4.2）。
              Text('还没有会话', style: theme.textTheme.titleLarge),
              // 说明 14（README §4.2），与标题间距 4。
              const SizedBox(height: 4),
              Text(
                '点右下角「新对话」开始，或从设置里导入 DeepSeek 的导出包',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 14,
                  color: skin.c.onV,
                ),
              ),
              // 只保留右下角 FAB 一个「新对话」入口（空态按钮曾与 FAB 重复）。
            ],
          ),
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
    final skin = KeepsakeSkinColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 错误态图标尺寸跟皮肤。
            Icon(
              Icons.error_outline,
              size: skin.iconSize,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text('加载失败', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: skin.c.onV),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

/// 批量删除的顶部临时进度条（v3.1 §2.2）。
///
/// - 高 40dp 通栏、文字 `fs-sub`、2dp 进度条用 `selectionStroke`；
/// - 「收起」后变成 28dp 的窄条，点按可展开；
/// - 进度一旦跑完，本 banner 自动消失（设置页的后台任务入口也同步消失）。
class _DeleteProgressBanner extends ConsumerStatefulWidget {
  const _DeleteProgressBanner();

  @override
  ConsumerState<_DeleteProgressBanner> createState() =>
      _DeleteProgressBannerState();
}

class _DeleteProgressBannerState extends ConsumerState<_DeleteProgressBanner> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final DeleteTaskState task = ref.watch(deleteTaskProvider);
    if (!task.running) {
      if (_collapsed) {
        // 任务结束时恢复展开：下次删除直接显示进度条。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _collapsed) setState(() => _collapsed = false);
        });
      }
      return const SizedBox.shrink();
    }
    final s = KeepsakeSkinColors.of(context);
    final theme = Theme.of(context);
    if (_collapsed) {
      return InkWell(
        onTap: () => setState(() => _collapsed = false),
        child: Container(
          height: 28,
          alignment: Alignment.center,
          color: s.c.low,
          child: Text(
            '正在删除会话 ${task.done} / ${task.total}（点按展开）',
            style: theme.textTheme.labelSmall?.copyWith(color: s.c.onV),
          ),
        ),
      );
    }
    return Container(
      height: 40,
      color: s.c.low,
      padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '正在删除会话  ${task.done} / ${task.total}',
                  style: theme.textTheme.bodySmall?.copyWith(color: s.c.onV),
                ),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: s.rPill,
                  child: LinearProgressIndicator(
                    value: task.fraction,
                    minHeight: 2,
                    backgroundColor: s.c.ov,
                    color: s.c.selBar,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _collapsed = true),
            child: const Text('收起'),
          ),
        ],
      ),
    );
  }
}


