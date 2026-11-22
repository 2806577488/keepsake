/// Keepsake（留声）— 设置页「AI 平台」分区。
///
/// 依据：`dart-symbols.md`（`features/settings/provider_section.dart`：
/// `ProviderSection` / `ProviderEditSheet` + 私有 `_ProviderEditSheetState`、
/// `_applyPreset` / `_edit` / `_save` + `set:_name`/`set:_base`/`set:_key`/`set:_kind`/
/// `set:_model`/`set:_reasoning`/`set:_search`/`set:_thinking`）、
/// `http-api.md` §2（13 个预设 + base_url + 模型候选 + 能力位）、`ui-strings.txt` §5（原文文案）。
///
/// 交互：
/// - 平台列表：点行 = 编辑，行首圆点 = 设为「当前平台」（`provider_store`），行尾 = 删除；
/// - 「添加平台」→ 底部弹窗 `ProviderEditSheet`：预设下拉（13 个）+ 名称 / 接口地址 /
///   API Key / 模型 + 「从 /models 拉取」候选 + 协议（DeepSeek 双协议 / 自定义 Anthropic）；
/// - 文案原文：「只存本机；直连该平台官方接口，不经过中转」
///   「还没有配置平台。点下面的按钮添加一个，Key 只存在本机，直连官方接口。」「未配置」「未填 Key」。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:keepsake/core/providers.dart';

/// 「AI 平台」分区：平台列表 + 当前平台选择 + 新增/编辑/删除入口。
class ProviderSection extends ConsumerWidget {
  const ProviderSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final book = ref.watch(providerBookProvider);
    final providers = book.providers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (providers.isEmpty)
          Card(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '还没有配置平台。点下面的按钮添加一个，Key 只存在本机，直连官方接口。',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _edit(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('添加平台'),
                  ),
                ],
              ),
            ),
          )
        else ...[
          for (final provider in providers)
            _ProviderTile(
              provider: provider,
              isCurrent: provider.id == book.currentId,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _edit(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('添加平台'),
              ),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            '只存本机；直连该平台官方接口，不经过中转',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// 打开「添加/编辑平台」弹窗。
void _edit(BuildContext context, WidgetRef ref, {AiProvider? provider}) {
  ProviderEditSheet.show(context, provider: provider);
}

/// 单个平台行。
class _ProviderTile extends ConsumerWidget {
  const _ProviderTile({required this.provider, required this.isCurrent});

  final AiProvider provider;
  final bool isCurrent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = <String>[
      if (provider.hasBaseUrl) provider.baseUrl else '未配置',
      if (!provider.hasApiKey) '未填 Key',
      if (provider.hasModel) provider.model,
    ];
    return ListTile(
      leading: IconButton(
        tooltip: isCurrent ? '当前平台' : '设为当前平台',
        icon: Icon(
          isCurrent ? Icons.check_circle : Icons.radio_button_unchecked,
          color: isCurrent
              ? theme.colorScheme.primary
              : theme.colorScheme.outline,
        ),
        onPressed: () =>
            ref.read(providerBookProvider.notifier).setCurrent(provider.id),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              provider.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            provider.protocolLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      subtitle: Text(
        status.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: provider.hasApiKey && provider.hasBaseUrl
              ? theme.colorScheme.onSurfaceVariant
              : theme.colorScheme.error,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '编辑平台',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _edit(context, ref, provider: provider),
          ),
          IconButton(
            tooltip: '删除平台',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmRemove(context, ref),
          ),
        ],
      ),
      onTap: () => _edit(context, ref, provider: provider),
    );
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除平台'),
        content: Text('「${provider.name}」的 Key 和配置会从本机删除，无法恢复。'),
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
    if (confirmed == true) {
      await ref.read(providerBookProvider.notifier).removeProvider(provider.id);
    }
  }
}

/// 添加 / 编辑平台的底部弹窗。
///
/// `provider == null` 时为新增（默认 DeepSeek 官方预设），否则编辑该平台。
class ProviderEditSheet extends ConsumerStatefulWidget {
  const ProviderEditSheet({super.key, this.provider});

  final AiProvider? provider;

  /// 以底部弹窗形式打开。
  static Future<void> show(BuildContext context, {AiProvider? provider}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => ProviderEditSheet(provider: provider),
    );
  }

  @override
  ConsumerState<ProviderEditSheet> createState() => _ProviderEditSheetState();
}

class _ProviderEditSheetState extends ConsumerState<ProviderEditSheet> {
  late final TextEditingController _name;
  late final TextEditingController _base;
  late final TextEditingController _key;
  late final TextEditingController _model;

  late ProviderPreset _preset;
  late ProviderKind _kind;
  late List<String> _models;

  String? _savedId;
  bool _busy = false;
  bool _obscureKey = true;

  bool get _isEditing => widget.provider != null;

  @override
  void initState() {
    super.initState();
    final provider = widget.provider;
    _savedId = provider?.id;
    _preset =
        provider?.preset ??
        (provider?.kind == ProviderKind.anthropic
            ? presetById(presetCustomAnthropicId)!
            : deepSeekPreset);
    _kind = provider?.kind ?? _preset.kind;
    _models = List<String>.of(provider?.models ?? _preset.models);
    _name = TextEditingController(text: provider?.name ?? _preset.name);
    _base = TextEditingController(text: provider?.baseUrl ?? _preset.baseUrl);
    _key = TextEditingController(text: provider?.apiKey ?? '');
    _model = TextEditingController(
      text: provider?.model ?? _preset.defaultModel,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _base.dispose();
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // 预设
  // -------------------------------------------------------------------------

  void _applyPreset(ProviderPreset preset) {
    setState(() {
      _preset = preset;
      _kind = preset.kind;
      _models = List<String>.of(preset.models);
      if (_name.text.trim().isEmpty || !_isEditing) {
        _name.text = preset.name;
      }
      _base.text = preset.baseUrl;
      if (preset.defaultModel.isNotEmpty) _model.text = preset.defaultModel;
    });
  }

  // -------------------------------------------------------------------------
  // 保存 / 拉取模型
  // -------------------------------------------------------------------------

  /// 校验并写库；`requireModel == false` 时允许模型留空（拉 `/models` 用）。
  Future<AiProvider?> _save({required bool requireModel}) async {
    final base = normalizeProviderBase(_base.text);
    final key = _key.text.trim();
    final model = _model.text.trim();
    final name = _name.text.trim();
    if (base.isEmpty) {
      _toast('先填接口地址');
      return null;
    }
    if (key.isEmpty) {
      _toast('先填 API Key');
      return null;
    }
    if (requireModel && model.isEmpty) {
      _toast('先填一个模型名');
      return null;
    }

    final AiProvider draft;
    if (widget.provider != null) {
      draft = widget.provider!.copyWith(
        name: name.isEmpty ? _preset.name : name,
        baseUrl: base,
        apiKey: key,
        model: model,
        kind: _kind,
        models: _models,
      );
    } else {
      // 新增：第一次保存后记住 id，避免「拉取模型 → 再保存」重复插入一条平台。
      final id = _savedId ?? newProviderId();
      draft = providerFromPreset(
        _preset,
        apiKey: key,
        model: model,
        name: name.isEmpty ? _preset.name : name,
        kind: _kind,
      ).copyWith(id: id, baseUrl: base, models: _models);
    }

    await ref.read(providerBookProvider.notifier).upsertProvider(draft);
    // 第一个平台自动设为当前平台。
    final book = ref.read(providerBookProvider);
    if (book.currentId == null) {
      await ref.read(providerBookProvider.notifier).setCurrent(draft.id);
    }
    if (mounted) setState(() => _savedId = draft.id);
    return draft;
  }

  Future<void> _saveAndClose() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final saved = await _save(requireModel: true);
      if (saved != null && mounted) {
        _toast('已保存「${saved.name}」');
        Navigator.of(context).pop();
      }
    } catch (error) {
      _toast('保存失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pullModels() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final saved = await _save(requireModel: false);
      if (saved == null) return;
      final fetched = await ref.read(providerModelsProvider(saved.id).future);
      if (!mounted) return;
      final ids = <String>[
        for (final item in fetched)
          if (item.id.trim().isNotEmpty) item.id.trim(),
      ];
      setState(() {
        if (ids.isNotEmpty) {
          _models = ids;
          if (_model.text.trim().isEmpty) _model.text = ids.first;
        }
      });
      _toast(ids.isEmpty ? '这个平台没有返回模型列表' : '已拉取 ${ids.length} 个模型');
    } catch (error) {
      _toast('拉取模型失败：${_errorText(error)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 产品文案在 `StateError.message` 里（如「模型列表请求失败：HTTP 401」）。
  static String _errorText(Object error) {
    if (error is StateError) return error.message;
    return '$error';
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
    final showProtocolPicker = _preset.hasAnthropicProtocol;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isEditing ? '编辑平台' : '添加 AI 平台',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<ProviderPreset>(
              initialValue: _preset,
              decoration: const InputDecoration(
                labelText: '预设',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final preset in providerPresets)
                  DropdownMenuItem<ProviderPreset>(
                    value: preset,
                    child: Text(
                      preset.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (preset) {
                      if (preset != null) _applyPreset(preset);
                    },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '平台',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _base,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '接口地址（含版本号）',
                hintText: '例如 https://api.siliconflow.cn/v1',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _key,
              obscureText: _obscureKey,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'API Key',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _obscureKey ? '显示' : '隐藏',
                  icon: Icon(
                    _obscureKey ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _model,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: '模型',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '填好后会从 /models 拉真实列表，聊天页可再切换',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : _pullModels,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_download_outlined),
                  label: const Text('从 /models 拉取'),
                ),
              ],
            ),
            if (_models.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final candidate in _models)
                      ChoiceChip(
                        label: Text(
                          candidate,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        selected: _model.text.trim() == candidate,
                        onSelected: _busy
                            ? null
                            : (_) => setState(() {
                                _model.text = candidate;
                              }),
                      ),
                  ],
                ),
              ),
            if (showProtocolPicker) ...[
              const SizedBox(height: 4),
              Text('协议', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<ProviderKind>(
                segments: const [
                  ButtonSegment<ProviderKind>(
                    value: ProviderKind.openai,
                    label: Text('OpenAI 兼容'),
                  ),
                  ButtonSegment<ProviderKind>(
                    value: ProviderKind.anthropic,
                    label: Text('Anthropic 兼容'),
                  ),
                ],
                selected: <ProviderKind>{_kind},
                onSelectionChanged: _busy
                    ? null
                    : (selection) => setState(() => _kind = selection.first),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _saveAndClose,
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
