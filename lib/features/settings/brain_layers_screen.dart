import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:keepsake/core/brain/brain_character.dart';
import 'package:keepsake/core/brain/brain_entities.dart';
import 'package:keepsake/core/brain/brain_entities_store.dart';
import 'package:keepsake/core/providers.dart';
import 'package:keepsake/core/theme.dart';

/// 「大脑分层」查看页（v0.4.36）。
///
/// App 里对应 dsh-brain 的命令：
/// - `/brain who` → 角色定义 + 版本历史（这里是「我是谁」区）；
/// - `/brain patient` → 实体档案列表 + 单个对象的要点/最近聊到。
///
/// 只读：不让用户手改模型写出的定义（改了就分不清"长成的"和"被编辑过的"）。
/// 要改人设走角色卡的「人设」字段；要清空重来走删除版本（后续入口）。
class BrainLayersScreen extends ConsumerStatefulWidget {
  const BrainLayersScreen({super.key});

  @override
  ConsumerState<BrainLayersScreen> createState() => _BrainLayersScreenState();
}

class _BrainLayersScreenState extends ConsumerState<BrainLayersScreen> {
  List<CharacterRow> _cards = const <CharacterRow>[];
  String? _selectedId;
  CharacterRow? _card;
  List<CharacterVersionRow> _versions = const <CharacterVersionRow>[];
  List<EntityRow> _entities = const <EntityRow>[];
  bool _loading = true;

  AppDatabase get _db => ref.read(databaseProvider);

  @override
  void initState() {
    super.initState();
    _loadCards();
  }

  Future<void> _loadCards() async {
    try {
      final cards = await _db.allCharacters();
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _selectedId = _selectedId ?? (cards.isEmpty ? null : cards.first.id);
        _loading = false;
      });
      if (_selectedId != null) await _loadLayer(_selectedId!);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadLayer(String characterId) async {
    try {
      final definitionStore = CharacterDefinitionStore(_db);
      final entityStore = BrainEntityStore(_db);
      final card = await definitionStore.get(characterId);
      final versions = await definitionStore.versions(characterId, limit: 10);
      final entities = await entityStore.listForCharacter(characterId);
      if (!mounted) return;
      setState(() {
        _card = card;
        _versions = versions;
        _entities = entities;
      });
    } catch (_) {
      // 读失败保持空态
    }
  }

  /// 弹层内容宽度：按屏幕收窄（360dp 手机上固定 460 会横向溢出）。
  double _dialogWidth(BuildContext context, {double max = 460}) {
    final available = MediaQuery.sizeOf(context).width - 56;
    if (available < 240) return 240;
    return available > max ? max : available;
  }

  Future<void> _showEntity(EntityRow entity) async {
    final store = BrainEntityStore(_db);
    EntityProfileView? profile;
    try {
      profile = await store.profile(
        characterId: entity.characterId,
        entityId: entity.id,
        factLimit: 12,
        turnLimit: 6,
      );
    } catch (_) {
      profile = null;
    }
    if (!mounted) return;
    final s = KeepsakeSkinColors.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: s.rSheet),
        title: Text('${entity.name}（${kindLabelOf(entity.kind)}）'),
        content: SizedBox(
          width: _dialogWidth(dialogContext),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.6,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (profile == null || profile.facts.isEmpty)
                    const Text('还没有整理出要点。聊到之后后台会自动补。')
                  else
                    for (final fact in profile.facts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('· [${fact.kind}] ${fact.text}'),
                      ),
                  if (profile != null && profile.turns.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      '最近聊到',
                      style: Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                    for (final turn in profile.turns)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('· ${turn.text}'),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(64, KeepsakeTheme.sheetButtonHeight),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _showVersions() async {
    final s = KeepsakeSkinColors.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: s.rSheet),
        title: const Text('版本历史'),
        content: SizedBox(
          width: _dialogWidth(dialogContext),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.6,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_versions.isEmpty) const Text('还没有写过版本。'),
                  for (final version in _versions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'v${version.version} · ${version.reason} · '
                        '${version.createdAt.toString().substring(0, 16)}\n'
                        '${version.definition}',
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(64, KeepsakeTheme.sheetButtonHeight),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = KeepsakeSkinColors.of(context);
    final theme = Theme.of(context);
    final card = _card;
    final definition = (card?.definition ?? '').trim();
    return Scaffold(
      appBar: AppBar(title: const Text('大脑分层')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  if (_cards.length > 1)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final item in _cards)
                            ChoiceChip(
                              label: Text(item.name),
                              selected: item.id == _selectedId,
                              onSelected: (_) {
                                setState(() => _selectedId = item.id);
                                _loadLayer(item.id);
                              },
                            ),
                        ],
                      ),
                    ),
                  _sectionTitle('角色 · 我是谁', theme),
                  if (definition.isEmpty)
                    const ListTile(
                      leading: Icon(Icons.person_search_outlined),
                      title: Text('还没写过'),
                      subtitle: Text('再聊几轮（或第一次后台整理后）会自动写第一版'),
                    )
                  else ...[
                    ListTile(
                      leading: const Icon(Icons.badge_outlined),
                      title: Text('v${card!.definitionVersion} 的定义'),
                      subtitle: Text(
                        '${card.definitionSource == 'fallback' ? '规则兜底' : '模型写的'} · '
                        '点开看版本历史',
                      ),
                      onTap: _showVersions,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        definition,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: s.c.onV,
                        ),
                      ),
                    ),
                  ],
                  _sectionTitle('实体 · 说到谁', theme),
                  if (_entities.isEmpty)
                    const ListTile(
                      leading: Icon(Icons.pets_outlined),
                      title: Text('还没有对象档案'),
                      subtitle: Text('对话里出现「患者某某」「客户某某」这类明确称呼时会自动建'),
                    )
                  else
                    for (final entity in _entities)
                      ListTile(
                        leading: Icon(_iconOf(entity.kind)),
                        title: Text(entity.name),
                        subtitle: Text(kindLabelOf(entity.kind)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showEntity(entity),
                      ),
                  _sectionTitle('规范 · 我是怎么答的', theme),
                  ListTile(
                    leading: const Icon(Icons.policy_outlined),
                    title: const Text('专业规范'),
                    subtitle: Text(
                      _specialtyPreview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
      ),
    );
  }

  String get _specialtyPreview {
    final text = ref.read(settingsProvider).specialtyRules.trim();
    return text.isEmpty ? '还没写（设置 → 对话默认里可编辑）' : text;
  }

  Widget _sectionTitle(String text, ThemeData theme) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      );

  IconData _iconOf(String kind) {
    switch (kind) {
      case 'patient':
        return Icons.local_hospital_outlined;
      case 'client':
        return Icons.business_center_outlined;
      case 'project':
        return Icons.folder_outlined;
      case 'pet':
        return Icons.pets_outlined;
      default:
        return Icons.person_outline;
    }
  }
}
