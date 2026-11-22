/// Keepsake（留声）— 全局 Riverpod providers（**契约 C：名字冻结**）。
///
/// 冻结名字（`next-steps.md` §0 契约 C，字符串实证）：
/// `databaseProvider`、`settingsStoreProvider`、`settingsProvider`、
/// `providerStoreProvider`、`providerBookProvider`、`httpClientFactoryProvider`、
/// `sessionsProvider`、`sessionSearchProvider`、`providerModelsProvider`。
///
/// `settingsStoreProvider` / `providerStoreProvider` 必须在 `main.dart` 的
/// `ProviderScope(overrides: [...])` 里 override（产品断言文案见各自定义）。
///
/// **不由本文件定义**（后续批次自己的文件里定义，避免撞名）：
/// - `chatControllerProvider` → `features/chat/chat_controller.dart`（F1）
/// - `importTaskProvider` → `core/import/import_task.dart`（批次 E）
///
/// 本文件同时 re-export 契约层类型，方便其它批次只 `import 'core/providers.dart'`。
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show Listenable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'api/model_list.dart' show fetchProviderModels;
import 'api/provider_models.dart';
import 'db/database.dart';
import 'provider_store.dart';
import 'providers_config.dart';

export 'api/provider_models.dart';
export 'db/database.dart';
export 'provider_store.dart';
export 'providers_config.dart';
export 'settings.dart';

/// HTTP 客户端工厂（便于测试注入 mock；每次调用返回**新的** client，用完要 close）。
typedef HttpClientFactory = http.Client Function();

/// 全局数据库（`keepsake.sqlite`，位于 `getApplicationSupportDirectory()`）。
final Provider<AppDatabase> databaseProvider = Provider<AppDatabase>(
  (Ref ref) {
    final db = AppDatabase();
    ref.onDispose(db.close);
    return db;
  },
  name: 'databaseProvider',
);

/// HTTP 客户端工厂（默认 `http.Client`）。
final Provider<HttpClientFactory> httpClientFactoryProvider =
    Provider<HttpClientFactory>(
  (Ref ref) => http.Client.new,
  name: 'httpClientFactoryProvider',
);

/// 会话列表流（置顶在前，再按 `updated_at` 倒序）。
final StreamProvider<List<Session>> sessionsProvider = StreamProvider<List<Session>>(
  (Ref ref) => ref.watch(databaseProvider).watchSessions(),
  name: 'sessionsProvider',
);

/// 全局搜索（按消息正文 LIKE + 标题命中）；参数是查询串。
///
/// 空查询串直接返回空列表（不发 SQL）。
final sessionSearchProvider = FutureProvider.family<List<SessionSearchHit>, String>(
  (Ref ref, String query) async {
    final q = query.trim();
    if (q.isEmpty) return const <SessionSearchHit>[];
    return ref.watch(databaseProvider).searchSessions(q);
  },
  name: 'sessionSearchProvider',
);

/// 某平台的模型列表（`GET {base}/models`）；参数是 `AiProvider.id`。
///
/// 网络/解析细节走批次 C 的 `fetchProviderModels`（`core/api/model_list.dart`）；
/// 本 provider 只做：平台查找 + 前置校验（产品文案）+ client 生命周期管理。
final providerModelsProvider = FutureProvider.family<List<ProviderModel>, String>(
  (Ref ref, String providerId) async {
    final store = ref.watch(providerStoreProvider);
    final provider = store.byId(providerId);
    if (provider == null) {
      throw StateError('选中的平台不存在了，去设置里重新选一个');
    }
    // Anthropic 协议通常没有 /models；直接回预设候选（[推断] 合理默认）。
    if (provider.kind == ProviderKind.anthropic) {
      return provider.models
          .map((id) => ProviderModel(id: id))
          .toList(growable: false);
    }
    final base = normalizeProviderBase(provider.baseUrl);
    if (base.isEmpty) throw StateError('先填接口地址');
    if (provider.apiKey.trim().isEmpty) throw StateError('先填 API Key');

    final client = ref.watch(httpClientFactoryProvider)();
    try {
      return await fetchProviderModels(
        baseUrl: base,
        apiKey: provider.apiKey.trim(),
        kind: provider.kind,
        client: client,
      );
    } finally {
      client.close();
    }
  },
  name: 'providerModelsProvider',
);

/// 把任意 [Listenable]（如 `ChangeNotifier`）桥接成 Stream。
///
/// Riverpod 3 已移除 `ChangeNotifierProvider`，需要响应式监听 ChangeNotifier 时用这个：
/// ```dart
/// final progressProvider = StreamProvider<ImportProgress>((ref) {
///   final task = ref.watch(importTaskProvider);
///   return changeNotifierStream(task, () => task.progress);
/// });
/// ```
Stream<T> changeNotifierStream<T>(
  Listenable source,
  T Function() read, {
  bool initial = true,
}) {
  StreamController<T>? controller;
  late final StreamController<T> created;
  void onNotify() {
    final c = controller;
    if (c != null && !c.isClosed) c.add(read());
  }

  created = StreamController<T>(
    onListen: () {
      if (initial && !created.isClosed) created.add(read());
      source.addListener(onNotify);
    },
    onCancel: () {
      source.removeListener(onNotify);
      controller = null;
      if (!created.isClosed) created.close();
    },
  );
  controller = created;
  return created.stream;
}