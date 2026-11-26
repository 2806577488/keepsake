/// Keepsake（留声）— 设置页「用量」分区（总计 / 每个对话的占用 / 账户余额 / 上下文窗口）。
///
/// 分区内容（顺序与 `settings_screen.dart` 一致）：
/// 1. `TotalUsageTile`（`usage_total_tile.dart`）：全局累计 + 重置；
/// 2. `PerSessionUsageTile`：进入 `SessionUsageScreen` 查看每个对话的占用；
/// 3. `BalanceTile`：DeepSeek 官方余额（剩余/已用/剩余率），进入 `BalanceScreen` 看明细；
/// 4. `ContextWindowTile`：模型上下文窗口（默认 128000，范围 1k–1M）。
///
/// 余额只支持 DeepSeek 官方预设；其它平台点击给提示。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:keepsake/core/providers.dart';
import 'package:keepsake/core/usage/balance_store.dart';
import 'package:keepsake/core/usage/usage_store.dart';
import '../../core/ui/toast.dart';
import 'package:keepsake/features/settings/balance_screen.dart';
import 'package:keepsake/features/settings/session_usage_screen.dart';

/// 「每个对话的占用」行：点开进入按会话列表。
class PerSessionUsageTile extends ConsumerWidget {
  const PerSessionUsageTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(sessionsProvider);
    final storeAsync = ref.watch(usageStoreProvider);
    final sessions = sessionsAsync.value;
    final store = storeAsync.value;

    final String subtitle;
    if (sessions == null || store == null) {
      subtitle = '正在读取…';
    } else {
      final count = sessions
          .where((session) => store.sessionUsage(session.id).isNotEmpty)
          .length;
      subtitle = count > 0 ? '$count 个对话有用量' : '还没有对话用量';
    }

    return ListTile(
      leading: const Icon(Icons.forum_outlined),
      title: const Text('每个对话的占用'),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const SessionUsageScreen()),
      ),
    );
  }
}

/// 「账户余额」行：DeepSeek 官方余额（剩余 / 已用 / 剩余率）。
///
/// v0.4.38：进入设置页时，快照超过 [BalanceSnapshot.staleAfter]（或从未查过）就自动刷新一次。
/// 以前只在明细页首次打开且无快照时才请求，用户看到的余额可能一直是旧值。
class BalanceTile extends ConsumerStatefulWidget {
  const BalanceTile({super.key});

  @override
  ConsumerState<BalanceTile> createState() => _BalanceTileState();
}

class _BalanceTileState extends ConsumerState<BalanceTile> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshIfStale());
    });
  }

  Future<void> _refreshIfStale() async {
    if (!mounted) return;
    final snapshot = ref.read(balanceProvider).value;
    if (snapshot != null && !snapshot.isStale()) return;
    try {
      await ref.read(balanceProvider.notifier).refresh();
    } catch (_) {
      // 设置页静默：余额拉不到不该弹错误（明细页里再给原因）。
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = ref.watch(providerBookProvider).current;
    final snapshot = ref.watch(balanceProvider).value;
    return ListTile(
      leading: const Icon(Icons.account_balance_wallet_outlined),
      title: const Text('账户余额'),
      subtitle: Text(_summary(snapshot)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _open(context, ref, provider),
    );
  }

  String _summary(BalanceSnapshot? snapshot) {
    if (snapshot == null || !snapshot.hasData) {
      return '剩余 — · 已用 — · 剩余率 —';
    }
    final rate = snapshot.remainingRate;
    final percent = rate == null ? '—' : '${rate.toStringAsFixed(0)}%';
    return '剩余 ${formatAmount(snapshot.current, snapshot.currency)} · '
        '已用 ${formatAmount(snapshot.used, snapshot.currency)} · '
        '剩余率 $percent';
  }

  void _open(BuildContext context, WidgetRef ref, AiProvider? provider) {
    if (provider == null ||
        provider.baseUrl.trim().isEmpty ||
        !provider.hasApiKey) {
      _toast(context, '先配置 AI 平台和 API Key');
      return;
    }
    if (!supportsBalanceQuery(provider)) {
      _toast(context, '当前平台不支持余额查询（仅 DeepSeek 官方支持）');
      return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const BalanceScreen()));
  }
}

/// 「上下文窗口」行：点击弹输入框修改（用于计算对话占用率）。
class ContextWindowTile extends ConsumerWidget {
  const ContextWindowTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return ListTile(
      leading: const Icon(Icons.straighten),
      title: const Text('上下文窗口'),
      subtitle: Text(
        '${formatContextWindow(settings.contextWindowTokens)}（用于计算对话占用率）',
      ),
      onTap: () => unawaited(_edit(context, ref)),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<int>(
      context: context,
      builder: (_) => _ContextWindowDialog(
        initialTokens: ref.read(settingsProvider).contextWindowTokens,
      ),
    );
    if (result == null) return;
    await ref.read(settingsProvider.notifier).setContextWindowTokens(result);
  }
}

/// 上下文窗口输入弹窗。
///
/// 单独做成 StatefulWidget，让 TextEditingController 随弹窗一起销毁；
/// 若在 `showDialog` 返回后立刻 dispose，退场动画期间 TextField 仍引用它，
/// Flutter 会报 `_dependents.isEmpty` 断言。
class _ContextWindowDialog extends StatefulWidget {
  const _ContextWindowDialog({required this.initialTokens});

  final int initialTokens;

  @override
  State<_ContextWindowDialog> createState() => _ContextWindowDialogState();
}

class _ContextWindowDialogState extends State<_ContextWindowDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.initialTokens}');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed == null ||
        parsed < kMinContextWindowTokens ||
        parsed > kMaxContextWindowTokens) {
      setState(() {
        _error =
            '请输入 $kMinContextWindowTokens–'
            '$kMaxContextWindowTokens 之间的整数';
      });
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('上下文窗口'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '上下文窗口 tokens',
              helperText:
                  '范围 $kMinContextWindowTokens–$kMaxContextWindowTokens（1K–1M）',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          Text(
            '用于计算对话页「占用率」：最近一次 prompt tokens ÷ 该值。',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}

/// 上下文窗口文案：`128K` / `1.5K` / `1M`。
String formatContextWindow(int tokens) {
  if (tokens >= 1000000 && tokens % 1000000 == 0) {
    return '${tokens ~/ 1000000}M';
  }
  if (tokens >= 1000) {
    final thousands = tokens / 1000;
    final text = thousands.toStringAsFixed(1);
    return '${text.endsWith('.0') ? text.substring(0, text.length - 2) : text}K';
  }
  return '$tokens';
}

/// 轻提示：统一走顶部浮层（SPEC §4.9「提示统一挪到顶部」），不用 SnackBar。
void _toast(BuildContext context, String message) {
  showTopToast(context, message);
}
