/// Keepsake（留声）— 设置 → 用量 →「账户余额」明细页。
///
/// 明细：官方余额（total_balance）、赠送/充值余额、可用状态、刷新时间；
/// 以及按基线计算的整体已用费用、整体剩余费用、剩余率。
/// 底部「刷新余额」重新请求 DeepSeek 官方 `/user/balance`。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:keepsake/core/usage/balance_client.dart';
import 'package:keepsake/core/usage/balance_store.dart';
import '../../core/ui/toast.dart';

/// 「账户余额」明细页面。
class BalanceScreen extends ConsumerStatefulWidget {
  const BalanceScreen({super.key});

  @override
  ConsumerState<BalanceScreen> createState() => _BalanceScreenState();
}

class _BalanceScreenState extends ConsumerState<BalanceScreen> {
  bool _refreshing = false;

  /// 本次刷新失败的可读文案（刷新成功后清空）。
  String? _lastError;

  @override
  void initState() {
    super.initState();
    // 第一次打开且从未成功查询过时，自动查一次（已有快照则不请求）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_autoLoad());
    });
  }

  Future<void> _autoLoad() async {
    try {
      final store = await ref.read(balanceStoreProvider.future);
      if (!mounted) return;
      final snapshot = store.snapshot;
      // v0.4.38：进页面就刷新——只有 60 秒内的快照才算新鲜；以前是"有快照就不查"。
      if (snapshot != null && !snapshot.isStale()) return;
      await _refresh();
    } catch (_) {
      // 存储读取失败：不自动请求，用户可手动刷新。
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _lastError = null;
    });
    try {
      await ref.read(balanceProvider.notifier).refresh();
    } catch (error) {
      if (mounted) {
        final message = balanceErrorText(error);
        setState(() => _lastError = message);
        _toast(message);
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _toast(String message) {
    showTopToast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(balanceProvider);
    final snapshot = async.value;
    final buildError = async.error;
    final error =
        _lastError ??
        (buildError == null ? null : balanceErrorText(buildError));

    return Scaffold(
      appBar: AppBar(title: const Text('账户余额')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (snapshot != null && snapshot.hasData)
            _BalanceCard(snapshot: snapshot),
          if (error != null) ...[
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        error,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (snapshot == null && error == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                '还没有余额数据，点下面的「刷新余额」查询。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            label: const Text('刷新余额'),
          ),
          const SizedBox(height: 12),
          Text(
            '余额来自 DeepSeek 官方接口；整体已用 = 基线余额 − 当前余额，'
            '充值会自动计入基线。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.snapshot});

  final BalanceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = snapshot.currency;
    final rate = snapshot.remainingRate;
    final rateText = rate == null ? '—' : '${rate.toStringAsFixed(0)}%';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'DeepSeek 官方余额',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '刷新时间 ${_formatTime(snapshot.updatedAt)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Divider(height: 24),
            _DetailRow(
              label: '官方余额',
              value: formatAmount(snapshot.current, currency),
            ),
            _DetailRow(
              label: '赠送余额',
              value: formatAmount(snapshot.granted, currency),
            ),
            _DetailRow(
              label: '充值余额',
              value: formatAmount(snapshot.toppedUp, currency),
            ),
            _DetailRow(
              label: '账户状态',
              value: snapshot.isAvailable ? '可用' : '不可用',
            ),
            const Divider(height: 24),
            _DetailRow(
              label: '整体已用费用',
              value: formatAmount(snapshot.used, currency),
              emphasized: true,
            ),
            _DetailRow(
              label: '整体剩余费用',
              value: formatAmount(snapshot.current, currency),
              emphasized: true,
            ),
            _DetailRow(label: '剩余率', value: rateText, emphasized: true),
            const SizedBox(height: 8),
            Text(
              '基线余额 ${formatAmount(snapshot.baseline, currency)}'
              '（首次获取时记录，充值会自动计入基线）',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = emphasized
        ? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)
        : theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(value, style: style),
        ],
      ),
    );
  }
}

/// 余额错误文案（[BalanceException] 已是可读文案，其它错误补前缀）。
String balanceErrorText(Object error) =>
    error is BalanceException ? error.message : '余额获取失败：$error';

String _formatTime(DateTime? time) {
  if (time == null) return '—';
  final local = time.isUtc ? time.toLocal() : time;
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
