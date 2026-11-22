/// Keepsake（留声）— 设置 → 角色卡管理页。
///
/// 角色卡 = 记忆隔离的边界：记忆/情绪/人格都挂在角色卡上，跨卡不召回。
/// 导入历史对话时默认按话题聚类建卡（规则在 character_clustering.dart）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:keepsake/core/characters/character_service.dart';
import 'package:keepsake/core/db/database.dart';
import 'package:keepsake/core/providers.dart';

/// 设置 → 角色卡。
class CharactersScreen extends ConsumerStatefulWidget {
  const CharactersScreen({super.key});

  @override
  ConsumerState<CharactersScreen> createState() => _CharactersScreenState();
}

class _CharactersScreenState extends ConsumerState<CharactersScreen> {
  late Future<List<CharacterSummary>> _future;

  CharacterService get _service => CharacterService(ref.read(databaseProvider));

  @override
  void initState() {
    super.initState();
    _future = _service.list();
  }

  void _refresh() {
    setState(() => _future = _service.list());
  }

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _create() async {
    final card = await _editDialog();
    if (card == null) return;
    try {
      await _service.create(
        name: card.name,
        description: card.description,
        prompt: card.prompt,
        emoji: card.emoji,
      );
      _toast('已新建角色卡');
      _refresh();
    } catch (error) {
      _toast('新建失败：$error');
    }
  }

  Future<void> _edit(CharacterSummary summary) async {
    final card = await _editDialog(card: summary.card);
    if (card == null) return;
    try {
      await _service.update(
        id: summary.card.id,
        name: card.name,
        description: card.description,
        prompt: card.prompt,
        emoji: card.emoji,
      );
      _toast('已保存');
      _refresh();
    } catch (error) {
      _toast('保存失败：$error');
    }
  }

  Future<void> _delete(CharacterSummary summary) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除角色卡？'),
        content: Text(
          '「${summary.name}」的记忆、情绪、人格会一起清掉。'
          '它的 ${summary.sessionCount} 个会话要怎么处理？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('keep'),
            child: const Text('保留会话'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('delete'),
            child: const Text('连会话一起删'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    try {
      await _service.deleteCharacter(
        summary.card.id,
        deleteSessions: choice == 'delete',
      );
      _toast('已删除');
      _refresh();
    } catch (error) {
      _toast('删除失败：$error');
    }
  }

  /// 清掉没有任何会话的角色卡（连同它的记忆 / 情绪 / 人格）。
  ///
  /// 历史版本删会话时可能只删了会话、没删卡；这里给一个一次性清理入口，
  /// 保证「会话删了 = 记忆清干净」。
  Future<void> _cleanOrphans(List<CharacterSummary> orphans) async {
    if (orphans.isEmpty) return;
    final bool ok = (await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清理孤立角色卡？'),
        content: Text(
          '有 ${orphans.length} 张角色卡已经没有会话了。'
          '清理会同时删掉它们的记忆、情绪和人格，无法恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清理'),
          ),
        ],
      ),
    )) ?? false;
    if (!ok) return;
    var removed = 0;
    for (final summary in orphans) {
      try {
        // deleteCharacter 内部会 _brain.clearAll：记忆/情绪/人格一起清。
        await _service.deleteCharacter(summary.card.id);
        removed++;
      } catch (_) {
        // 单张失败不影响其余。
      }
    }
    _toast('已清理 $removed 张孤立角色卡');
    _refresh();
  }

  Future<void> _merge(CharacterSummary from, List<CharacterSummary> all) async {
    final targets = [
      for (final other in all)
        if (other.card.id != from.card.id) other,
    ];
    if (targets.isEmpty) {
      _toast('没有别的角色卡可以合并');
      return;
    }
    final target = await showDialog<CharacterSummary>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('把「${from.name}」合并到…'),
        children: [
          for (final other in targets)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(other),
              child: Text('${other.emoji} ${other.name}（${other.sessionCount} 个会话）'),
            ),
        ],
      ),
    );
    if (target == null) return;
    try {
      await _service.mergeCharacters(from.card.id, target.card.id);
      _toast('已合并到「${target.name}」');
      _refresh();
    } catch (error) {
      _toast('合并失败：$error');
    }
  }

  /// 返回编辑后的值（新建时无 card）。取消返回 null。
  Future<_CardDraft?> _editDialog({CharacterRow? card}) async {
    final nameController = TextEditingController(text: card?.name ?? '');
    final descController = TextEditingController(text: card?.description ?? '');
    final promptController = TextEditingController(text: card?.prompt ?? '');
    final emojiController = TextEditingController(text: card?.emoji ?? '');
    final result = await showDialog<_CardDraft>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(card == null ? '新建角色卡' : '编辑角色卡'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '名字',
                  hintText: '例如：一起打游戏的她',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emojiController,
                decoration: const InputDecoration(
                  labelText: '头像 emoji',
                  hintText: '🤖',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '简介',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: promptController,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: '人设 prompt（留空自动生成）',
                  border: OutlineInputBorder(),
                ),
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
              _CardDraft(
                name: nameController.text,
                description: descController.text,
                prompt: promptController.text,
                emoji: emojiController.text,
              ),
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    // 退场动画期间不 dispose（否则真机红屏）；交给 GC。
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('角色卡'),
        actions: [
          IconButton(
            tooltip: '新建角色',
            onPressed: _create,
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
        ],
      ),
      body: FutureBuilder<List<CharacterSummary>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('加载失败：${snapshot.error}'),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: _refresh, child: const Text('重试')),
                ],
              ),
            );
          }
          final cards = snapshot.data ?? const <CharacterSummary>[];
          if (cards.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.groups_outlined,
                        size: 56, color: theme.colorScheme.outline),
                    const SizedBox(height: 12),
                    Text('还没有角色卡', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      '导入历史对话时会按话题自动建卡，也可以右上角手动新建。\n'
                      '记忆、情绪、人格按角色隔离，跨角色不会召回。',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          final orphans = <CharacterSummary>[
            for (final summary in cards)
              if (summary.sessionCount == 0) summary,
          ];
          return Column(
            children: [
              if (orphans.isNotEmpty)
                ListTile(
                  leading: Icon(
                    Icons.cleaning_services_outlined,
                    color: theme.colorScheme.error,
                  ),
                  title: Text('清理 ${orphans.length} 张孤立角色卡'),
                  subtitle: const Text('没有对话的角色卡，连同记忆一起清掉'),
                  onTap: () => _cleanOrphans(orphans),
                ),
              if (orphans.isNotEmpty) const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  itemCount: cards.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final summary = cards[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(summary.emoji,
                            style: const TextStyle(fontSize: 20)),
                      ),
                      title: Text(summary.name),
                      subtitle: Text('${summary.sessionCount} 个会话'),
                      onTap: () => _edit(summary),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          switch (value) {
                            case 'edit':
                              _edit(summary);
                            case 'merge':
                              _merge(summary, cards);
                            case 'delete':
                              _delete(summary);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('编辑')),
                          PopupMenuItem(value: 'merge', child: Text('合并到…')),
                          PopupMenuItem(value: 'delete', child: Text('删除')),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CardDraft {
  const _CardDraft({
    required this.name,
    required this.description,
    required this.prompt,
    required this.emoji,
  });

  final String name;
  final String description;
  final String prompt;
  final String emoji;
}
