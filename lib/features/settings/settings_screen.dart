/// Keepsake（留声）— 设置页。
///
/// 依据：`dart-symbols.md`（`features/settings/settings_screen.dart`：
/// `SettingsScreen` / `_SettingsScreenState` / `_AboutTile` / `_AboutTileState` /
/// `_SectionTitle` / `_system`）、`ui-strings.txt` §5/§8（全部原文文案）、
/// `next-steps.md` §2。
///
/// 分区（自上而下）：
/// 1. **AI 平台**：`ProviderSection`（增删改 / 预设 / `/models` / 当前平台）；
/// 2. **对话默认**：系统提示词、上下文预算、思考强度、深度思考、联网搜索；
/// 3. **用量**：`TotalUsageTile`（全局累计 + 重置）、`PerSessionUsageTile`
///    （每个对话的占用）、`BalanceTile`（DeepSeek 官方余额）、`ContextWindowTile`
///    （模型上下文窗口，用于计算对话占用率）；
/// 4. **外观**：主题（跟随系统 / 浅色 / 深色，`Settings.themeMode`）；
/// 5. **后台任务**：导入进度（`importProgressProvider`）+ 补建角色卡进度
///    （`cardBackfillProvider`），只显示不启动；
/// 6. **数据**：「数据全部存在本机」+ 导入历史对话 + 导出备份；
/// 7. **关于**：`Keepsake（留声）` + 版本号（package_info_plus）。
///
/// 对话页只保留「本会话」用量条（`features/chat/session_usage_bar.dart`），
/// 不再出现全局总计条。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:keepsake/core/brain/brain_service.dart';
import 'package:keepsake/core/characters/card_backfill_task.dart';
import 'package:keepsake/core/import/import_task.dart';
import 'package:keepsake/core/providers.dart';
import 'package:keepsake/core/settings.dart';
import 'package:keepsake/core/update/update_service.dart';
import 'package:keepsake/features/settings/export_tile.dart';
import 'package:keepsake/features/settings/import_tile.dart';
import 'package:keepsake/features/settings/characters_screen.dart';
import 'package:keepsake/features/settings/provider_section.dart';
import 'package:keepsake/features/settings/usage_section.dart';
import 'package:keepsake/features/settings/usage_total_tile.dart';

/// 设置页。
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // -------------------------------------------------------------------------
  // 系统提示词
  // -------------------------------------------------------------------------

  Future<void> _system() async {
    final settings = ref.read(settingsProvider);
    final controller = TextEditingController(text: settings.systemPrompt);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('系统提示词'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: '留空则使用默认提示词',
              border: OutlineInputBorder(),
            ),
          ),
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
    // 不在这里 dispose：对话框退场动画期间 TextField 仍挂着 listener，
    // 提前 dispose 会触发 framework 断言（真机红屏）。控制器很小，交给 GC。
    if (result == null || !mounted) return;
    await ref.read(settingsProvider.notifier).setSystemPrompt(result);
    _toast(result.isEmpty ? '已恢复默认提示词' : '系统提示词已保存');
  }

  // -------------------------------------------------------------------------
  // 上下文预算
  // -------------------------------------------------------------------------

  Future<void> _contextBudget() async {
    final settings = ref.read(settingsProvider);
    final current = settings.contextKeepRounds;
    final controller = TextEditingController(
      text: current > 0 ? '$current' : '',
    );
    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('上下文预算'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '保留最近 N 轮',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (value) =>
                  Navigator.of(dialogContext).pop(_parseRounds(value)),
            ),
            const SizedBox(height: 8),
            Text(
              '填 0 表示不限制（全部历史）',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_parseRounds(controller.text)),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    // 同上：退场动画期间不 dispose。
    if (result == null || !mounted) return;
    await ref.read(settingsProvider.notifier).setContextKeepRounds(result);
  }

  static int _parseRounds(String raw) {
    final parsed = int.tryParse(raw.trim()) ?? 0;
    return parsed < 0 ? 0 : parsed;
  }

  // -------------------------------------------------------------------------
  // 清空记忆数据（危险操作）
  // -------------------------------------------------------------------------

  Future<void> _clearMemory() async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空记忆数据'),
        content: const Text(
          '会清空整理出的记忆、情绪、人格数据，'
          '聊天原文全部保留（对话记录不受影响）。此操作不可撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(brainServiceProvider).clearAll();
      _toast('记忆数据已清空');
    } catch (error) {
      _toast('清空失败：$error');
    }
  }

  // -------------------------------------------------------------------------
  // 思考强度
  // -------------------------------------------------------------------------

  Future<void> _thinkingLevel() async {
    final settings = ref.read(settingsProvider);
    final level = await showDialog<ThinkingLevel>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('思考强度'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(ThinkingLevel.low),
            child: _optionRow(
              dialogContext,
              ThinkingLevel.low,
              settings.thinkingLevel == ThinkingLevel.low,
              '更快、更省，适合日常问答',
            ),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.of(dialogContext).pop(ThinkingLevel.medium),
            child: _optionRow(
              dialogContext,
              ThinkingLevel.medium,
              settings.thinkingLevel == ThinkingLevel.medium,
              '默认，平衡速度与推理',
            ),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.of(dialogContext).pop(ThinkingLevel.high),
            child: _optionRow(
              dialogContext,
              ThinkingLevel.high,
              settings.thinkingLevel == ThinkingLevel.high,
              '给更多思考预算，适合难题/写作',
            ),
          ),
        ],
      ),
    );
    if (level == null || !mounted) return;
    await ref.read(settingsProvider.notifier).setThinkingLevel(level);
  }

  Widget _optionRow(
    BuildContext context,
    ThinkingLevel level,
    bool selected,
    String description,
  ) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          selected ? Icons.check_circle : Icons.circle_outlined,
          size: 20,
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outline,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(level.label, style: theme.textTheme.bodyLarge),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // 主题
  // -------------------------------------------------------------------------

  Future<void> _themeMode() async {
    final settings = ref.read(settingsProvider);
    final mode = await showDialog<ThemeMode>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('主题'),
        children: [
          _themeOption(
            dialogContext,
            ThemeMode.system,
            '跟随系统',
            settings.themeMode == ThemeMode.system,
          ),
          _themeOption(
            dialogContext,
            ThemeMode.light,
            '浅色',
            settings.themeMode == ThemeMode.light,
          ),
          _themeOption(
            dialogContext,
            ThemeMode.dark,
            '深色',
            settings.themeMode == ThemeMode.dark,
          ),
        ],
      ),
    );
    if (mode == null || !mounted) return;
    await ref.read(settingsProvider.notifier).setThemeMode(mode);
  }

  Widget _themeOption(
    BuildContext context,
    ThemeMode value,
    String label,
    bool selected,
  ) {
    final theme = Theme.of(context);
    return SimpleDialogOption(
      onPressed: () => Navigator.of(context).pop(value),
      child: Row(
        children: [
          Icon(
            selected ? Icons.check_circle : Icons.circle_outlined,
            size: 20,
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
          ),
          const SizedBox(width: 12),
          Text(label, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
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
  // 构建
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final rounds = settings.contextKeepRounds;
    final contextLabel = rounds > 0 ? '上下文：最近 $rounds 轮' : '上下文：不限制';
    final promptPreview = settings.systemPrompt.trim();

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const _SectionTitle('AI 平台'),
            const ProviderSection(),

            const _SectionTitle('对话默认'),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('系统提示词'),
              subtitle: Text(
                promptPreview.isEmpty ? '留空则使用默认提示词' : promptPreview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: _system,
            ),
            ListTile(
              leading: const Icon(Icons.compress),
              title: const Text('上下文预算'),
              subtitle: Text(contextLabel),
              onTap: _contextBudget,
            ),
            ListTile(
              leading: const Icon(Icons.psychology_outlined),
              title: const Text('思考强度'),
              subtitle: Text(settings.thinkingLevel.label),
              onTap: _thinkingLevel,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.lightbulb_outline),
              title: const Text('深度思考'),
              subtitle: const Text('支持深度思考'),
              value: settings.thinkingEnabled,
              onChanged: (value) =>
                  ref.read(settingsProvider.notifier).setThinkingEnabled(value),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.travel_explore),
              title: const Text('联网搜索'),
              subtitle: const Text('支持联网搜索（DeepSeek 扩展）'),
              value: settings.searchEnabled,
              onChanged: (value) =>
                  ref.read(settingsProvider.notifier).setSearchEnabled(value),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.auto_awesome_outlined),
              title: const Text('记忆与回忆'),
              subtitle: const Text('整理对话要点，回答时自动召回相关旧内容'),
              value: settings.memoryEnabled,
              onChanged: (value) =>
                  ref.read(settingsProvider.notifier).setMemoryEnabled(value),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.sentiment_satisfied_alt_outlined),
              title: const Text('情绪'),
              subtitle: const Text('让回答带上当前心情（纯本地推断）'),
              value: settings.moodEnabled,
              onChanged: (value) =>
                  ref.read(settingsProvider.notifier).setMoodEnabled(value),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.psychology_alt_outlined),
              title: const Text('人格'),
              subtitle: const Text('从相处中形成表达倾向'),
              value: settings.personaEnabled,
              onChanged: (value) =>
                  ref.read(settingsProvider.notifier).setPersonaEnabled(value),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_sweep_outlined,
                color: theme.colorScheme.error,
              ),
              title: Text(
                '清空记忆数据',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              subtitle: const Text('只清整理出的记忆，聊天原文全部保留'),
              onTap: _clearMemory,
            ),

            const _SectionTitle('用量'),
            const TotalUsageTile(),
            const PerSessionUsageTile(),
            const BalanceTile(),
            const ContextWindowTile(),

            const _SectionTitle('后台任务'),
            const _BackgroundTasksSection(),

            const _SectionTitle('外观'),
            ListTile(
              leading: const Icon(Icons.brightness_6_outlined),
              title: const Text('主题'),
              subtitle: Text(switch (settings.themeMode) {
                ThemeMode.light => '浅色',
                ThemeMode.dark => '深色',
                ThemeMode.system => '跟随系统',
              }),
              onTap: _themeMode,
            ),

            const _SectionTitle('数据'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                '数据全部存在本机',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.people_alt_outlined),
              title: const Text('角色卡'),
              subtitle: const Text('按角色隔离记忆、情绪、人格；导入时可按话题自动建卡'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CharactersScreen(),
                ),
              ),
            ),
            const ImportHistoryTile(),
            const ExportBackupTile(),

            const _SectionTitle('关于'),
            const _UpdateTile(),
            const _AboutTile(),
          ],
        ),
      ),
    );
  }
}

/// 「后台任务」区块：导入进度 + 补建角色卡进度。
///
/// - 导入：watch 现有 `importProgressProvider`（`ImportTask`），显示
///   `ImportProgress.label` + `fraction` 进度条（跑完且没失败时整行隐藏）；
/// - 补建角色卡：watch `cardBackfillProvider`（`CardBackfillTask`），
///   跑的时候显示「正在补建角色卡：done / total」+ 进度条，不跑时不显示该行。
///
/// 两条任务都可能由别的页面启动（导入在设置页 / 列表顶部，补建在会话列表），
/// 这里只负责显示，不提供启动按钮。
class _BackgroundTasksSection extends ConsumerWidget {
  const _BackgroundTasksSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ImportProgress? progress = ref.watch(importProgressProvider).value;
    final CardBackfillProgress backfill = ref.watch(cardBackfillProvider);

    final List<Widget> rows = <Widget>[];
    if (progress != null && (progress.running || progress.hasFailures)) {
      rows.add(
        ListTile(
          leading: Icon(
            progress.running
                ? Icons.cloud_download_outlined
                : Icons.error_outline,
            color: progress.running ? null : theme.colorScheme.error,
          ),
          title: Text(
            progress.running ? progress.label : '有 ${progress.failed} 条没导上',
          ),
          subtitle: progress.running
              ? _ProgressBar(
                  fraction: progress.fraction,
                  caption: progress.currentTitle,
                )
              : null,
        ),
      );
    }
    if (backfill.running) {
      rows.add(
        ListTile(
          leading: const Icon(Icons.badge_outlined),
          title: Text(backfill.label),
          subtitle: _ProgressBar(fraction: backfill.fraction),
        ),
      );
    }

    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Text(
          '没有正在运行的后台任务',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    // M1（轻量版）：没有前台服务，国产 ROM 会冻结/杀掉后台任务；明示可续跑，
    // 避免用户以为卡死（进度条不动 ≠ 数据丢了）。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ...rows,
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text(
            '切到后台可能被系统暂停，回到 App 会自动续跑',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// 一行细进度条 + 可选说明文字（当前导入的会话标题）。
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.fraction, this.caption});

  final double? fraction;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = caption;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: fraction,
          minHeight: 3,
          borderRadius: BorderRadius.circular(2),
        ),
        if (text != null && text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// 分区标题（`_SectionTitle`，符号表精确）。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 「关于」行：应用名 + 版本号 + 数据位置说明。
class _AboutTile extends StatefulWidget {
  const _AboutTile();

  @override
  State<_AboutTile> createState() => _AboutTileState();
}

class _AboutTileState extends State<_AboutTile> {
  String? _version;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      final build = info.buildNumber.trim();
      setState(() {
        _version = build.isEmpty ? info.version : '${info.version}（$build）';
      });
    } catch (_) {
      // 取不到版本号（桌面/测试环境）时静默降级。
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final version = _version;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(
          Icons.album_outlined,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
      title: const Text('Keepsake（留声）'),
      subtitle: Text(version == null ? '数据全部存在本机' : '版本 $version · 数据全部存在本机'),
    );
  }
}

/// 「检查更新」行：显示当前版本；检查到新版本时右侧点亮红点（不弹窗打扰）。
///
/// 点击 → 检查 → 有新版弹对话框（版本号 + 发布说明尾部几行）→「下载并安装」→
/// 下载进度对话框 → 交给系统安装器。没有更新时 toast「已是最新版本」。
class _UpdateTile extends StatefulWidget {
  const _UpdateTile();

  @override
  State<_UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends State<_UpdateTile> {
  /// 当前安装版本（读不到时为 null，行内显示占位文案）。
  String? _current;

  /// 已确认可用的新版本；为空表示没有更新。
  UpdateInfo? _pending;

  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// 首帧后：先拿本机版本号，再做一次静默检查（只点亮红点）。
  Future<void> _bootstrap() async {
    try {
      final current = await UpdateService.currentVersion();
      if (mounted) setState(() => _current = current);
    } on UpdateException catch (error) {
      // 读不到版本不该打断设置页，但原因要留痕。
      debugPrint('读取本机版本失败：${error.message}');
    }
    await _check(silent: true);
  }

  Future<void> _check({required bool silent}) async {
    if (_checking || !mounted) return;
    setState(() => _checking = true);
    try {
      final info = await UpdateService.check();
      if (!mounted) return;
      setState(() {
        _current = info.current;
        _pending = info.hasUpdate ? info : null;
      });
      if (silent) return;
      if (!info.hasUpdate) {
        _toast('已是最新版本');
        return;
      }
      await _confirm(info);
    } on UpdateException catch (error) {
      debugPrint('检查更新失败（silent=$silent）：${error.message}');
      // H3：不再只 toast 一句「请求超时」——失败对话框里给「在浏览器打开」。
      if (!silent && mounted) {
        await _showFailureDialog(error.message, manualUrl: error.manualUrl);
      }
    } catch (error) {
      debugPrint('检查更新异常（silent=$silent）：$error');
      if (!silent && mounted) {
        await _showFailureDialog('检查更新失败：$error');
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  /// 失败对话框：文案 + 「在浏览器打开」（H3/H4 兜底）。
  ///
  /// [manualUrl] 为空时退回 [UpdateService.manualUrl]（Release 页）；
  /// 这样下载阶段的网络失败也能落到手动下载。
  Future<void> _showFailureDialog(String message, {String? manualUrl}) async {
    if (!mounted) return;
    final String url = manualUrl ?? UpdateService.manualUrl;
    final bool? open = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('更新没有走通'),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('知道了'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('在浏览器打开'),
          ),
        ],
      ),
    );
    if (open == true) await _openInBrowser(url);
  }

  /// 用系统浏览器打开 [url]；没有可用浏览器时明确提示（不静默失败）。
  Future<void> _openInBrowser(String url) async {
    try {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) _toast('没有可用的浏览器，请手动打开：$url');
    } catch (error) {
      if (mounted) _toast('打开浏览器失败：$error');
    }
  }

  /// 有新版时的确认对话框：版本号 + 发布说明尾部几行。
  Future<void> _confirm(UpdateInfo info) async {
    final notes = _tailLines(info.notes);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: Text('发现新版本 ${info.latest}'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前版本 ${info.current}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: SingleChildScrollView(
                      child: Text(
                        notes,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                ],
                if (info.apkUrl == null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '这个版本没有附带 APK，请到 Release 页面手动下载。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('稍后'),
            ),
            FilledButton(
              onPressed: info.apkUrl == null
                  ? null
                  : () => Navigator.of(dialogContext).pop(true),
              child: const Text('下载并安装'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    await _downloadAndInstall(info);
  }

  /// 下载（进度对话框）→ 打开系统安装器；缺权限时跳系统设置。
  Future<void> _downloadAndInstall(UpdateInfo info) async {
    if (info.apkUrl == null) {
      _toast('这个版本没有 APK 安装包');
      return;
    }
    // 进度对话框的值：fraction 为 null 表示总长度未知（转圈）。
    final fraction = ValueNotifier<double?>(0);
    final status = ValueNotifier<String>('准备下载…');
    final navigator = Navigator.of(context, rootNavigator: true);

    // 不 await：先让对话框挂上去，再靠 navigator.pop 收起。
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('下载更新'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ValueListenableBuilder<double?>(
                valueListenable: fraction,
                builder: (context, value, child) => LinearProgressIndicator(
                  value: value,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<String>(
                valueListenable: status,
                builder: (context, value, child) => Text(
                  value,
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          actions: const <Widget>[],
        ),
      ),
    );

    var closed = false;
    void closeProgress() {
      if (closed) return;
      closed = true;
      navigator.pop();
    }

    try {
      final file = await UpdateService.download(
        info,
        onProgress: (received, total) {
          if (total > 0) {
            fraction.value = (received / total).clamp(0.0, 1.0);
            status.value =
                '已下载 ${_size(received)} / ${_size(total)}'
                '（${(received * 100 / total).toStringAsFixed(0)}%）';
          } else {
            fraction.value = null;
            status.value = '已下载 ${_size(received)}';
          }
        },
      );
      status.value = '下载完成，正在打开安装器…';
      closeProgress();
      await UpdateService.installApk(file.path);
      if (mounted) _toast('已打开系统安装器，按提示完成安装');
    } on NeedInstallPermission catch (error) {
      closeProgress();
      // H4：安装被拦时不再只 toast 一句 —— 按厂商讲清关在哪，再给两个出口。
      final String? action = await _showInstallBlockedDialog(error.message);
      if (action == 'settings') {
        await UpdateService.openInstallSettings();
      } else if (action == 'browser') {
        await _openInBrowser(error.manualUrl ?? UpdateService.manualUrl);
      }
    } on UpdateException catch (error) {
      closeProgress();
      await _showFailureDialog(error.message, manualUrl: error.manualUrl);
    } catch (error) {
      closeProgress();
      await _showFailureDialog('下载更新失败：$error');
    } finally {
      // 退场动画期间 ValueListenableBuilder 仍挂着监听，这里不 dispose（交给 GC），
      // 与上面 TextEditingController 的处理保持一致。
      closeProgress();
    }
  }

  /// 安装被拦（H4）：按厂商说明关什么，再给「去设置 / 在浏览器打开」。
  /// 返回 `'settings'` / `'browser'` / null（取消）。
  Future<String?> _showInstallBlockedDialog(String message) async {
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('安装被系统拦住了'),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('settings'),
            child: const Text('去设置'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('browser'),
            child: const Text('在浏览器打开'),
          ),
        ],
      ),
    );
  }

  void _toast(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  /// 发布说明只取尾部若干行（原文通常是「新功能 → 修复 → 校验」）。
  static String _tailLines(String notes, {int maxLines = 8}) {
    final lines = notes
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((line) => line.trimRight())
        .toList();
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    if (lines.isEmpty) return '';
    final start = lines.length > maxLines ? lines.length - maxLines : 0;
    return lines.sublist(start).join('\n');
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = _current;
    final pending = _pending;
    final subtitle = current == null
        ? '正在读取当前版本…'
        : (pending != null ? '发现新版本 ${pending.latest}' : '当前版本 $current');

    return ListTile(
      leading: const Icon(Icons.system_update_alt),
      title: const Text('检查更新'),
      subtitle: Text(subtitle),
      trailing: _checking
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : pending != null
          ? Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: theme.colorScheme.error,
                shape: BoxShape.circle,
              ),
            )
          : const Icon(Icons.chevron_right),
      onTap: _checking ? null : () => _check(silent: false),
    );
  }
}

