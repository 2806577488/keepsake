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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:keepsake/core/brain/brain_service.dart';
import 'package:keepsake/core/characters/card_backfill_task.dart';
import 'package:keepsake/core/import/import_task.dart';
import 'package:keepsake/core/providers.dart';
import 'package:keepsake/core/settings.dart';
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
    return Column(children: rows);
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
