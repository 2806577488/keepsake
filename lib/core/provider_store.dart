/// Keepsake（留声）— AI 平台配置的持久化（列表 + 当前选择 + API Key）。
///
/// **契约 A 的一部分（冻结）**。符号证据（dart-symbols.md / http-api.md §2）：
/// `ProviderStore` / `ProviderBook` / `ProviderBookController` / `ProviderPreset`；
/// `providerFromPreset` / `newProvider` / `setProvider` / `normalizeProviderBase`；
/// SharedPreferences key `ai_providers` [确定]（`tokens-snake.txt`）。
///
/// Riverpod 3 移除了 `ChangeNotifierProvider`，所以 [ProviderBook] 通过
/// [ProviderBookController]（`Notifier`）桥接给 UI；`providerStoreProvider` /
/// `providerBookProvider` 的名字是冻结的（见 `core/providers.dart` 的 re-export）。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/provider_models.dart';

/// 平台配置的不可变快照（UI `ref.watch(providerBookProvider)` 拿它）。
@immutable
class ProviderBook {
  const ProviderBook({
    this.providers = const <AiProvider>[],
    this.currentId,
  });

  final List<AiProvider> providers;

  /// 当前选中的平台 id（可能为 null 或指向已删除的平台）。
  final String? currentId;

  /// 当前选中的平台（不存在则 null）。
  AiProvider? get current {
    final id = currentId;
    if (id == null || id.isEmpty) return null;
    for (final p in providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  bool get isEmpty => providers.isEmpty;

  bool get isNotEmpty => providers.isNotEmpty;

  /// 当前平台是否可用（存在且 base/key/model 齐全）。
  bool get currentReady => current?.isReady ?? false;

  /// 按 id 取平台。
  AiProvider? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final p in providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 按预设 id 取第一个匹配的平台。
  AiProvider? byPreset(String presetId) {
    for (final p in providers) {
      if (p.presetId == presetId) return p;
    }
    return null;
  }

  ProviderBook copyWith({List<AiProvider>? providers, String? currentId, bool clearCurrent = false}) {
    return ProviderBook(
      providers: providers ?? this.providers,
      currentId: clearCurrent ? null : (currentId ?? this.currentId),
    );
  }

  @override
  String toString() => 'ProviderBook(${providers.length} providers, current=$currentId)';
}

/// 平台列表 + 当前选择的持久化（SharedPreferences 单个 JSON，key = `ai_providers`）。
class ProviderStore extends ChangeNotifier {
  ProviderStore._(this._prefs, this._providers, this._currentId);

  /// SharedPreferences key [确定]。
  static const String prefsKey = 'ai_providers';

  final SharedPreferences _prefs;
  List<AiProvider> _providers;
  String? _currentId;

  /// 全部平台（不可变视图）。
  List<AiProvider> get providers => List<AiProvider>.unmodifiable(_providers);

  /// 当前选中的平台 id。
  String? get currentId => _currentId;

  /// 当前选中的平台。
  AiProvider? get current => byId(_currentId);

  /// 不可变快照。
  ProviderBook get book =>
      ProviderBook(providers: List<AiProvider>.unmodifiable(_providers), currentId: _currentId);

  /// 按 id 取平台。
  AiProvider? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final p in _providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 按预设 id 取平台。
  AiProvider? byPreset(String presetId) {
    for (final p in _providers) {
      if (p.presetId == presetId) return p;
    }
    return null;
  }

  /// 从 SharedPreferences 读取；缺省时创建空的（不预置平台，UI 会提示去添加）。
  static Future<ProviderStore> load(SharedPreferences prefs) async {
    var providers = <AiProvider>[];
    String? currentId;
    final raw = prefs.getString(prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          providers = _parseProviders(decoded);
        } else if (decoded is Map) {
          final map = decoded.cast<String, Object?>();
          final list = map['providers'] ?? map['ai_providers'];
          if (list is List) providers = _parseProviders(list);
          final current = map['current'] ?? map['current_id'] ?? map['currentId'];
          if (current is String && current.isNotEmpty) currentId = current;
        }
      } catch (_) {
        providers = <AiProvider>[];
        currentId = null;
      }
    }
    // currentId 必须在列表里，否则视为未选。
    if (currentId != null && !providers.any((p) => p.id == currentId)) {
      currentId = null;
    }
    return ProviderStore._(prefs, providers, currentId);
  }

  static List<AiProvider> _parseProviders(List<Object?> raw) {
    final result = <AiProvider>[];
    for (final item in raw) {
      if (item is Map) {
        try {
          result.add(AiProvider.fromJson(item.cast<String, Object?>()));
        } catch (_) {
          // 跳过坏条目，不让整份配置失效。
        }
      }
    }
    return result;
  }

  /// 新增或替换（按 id）。
  Future<void> upsert(AiProvider provider) async {
    final index = _providers.indexWhere((p) => p.id == provider.id);
    if (index >= 0) {
      _providers[index] = provider;
    } else {
      _providers = <AiProvider>[..._providers, provider];
    }
    _currentId ??= provider.id;
    await _persist();
  }

  /// 符号表同名（`setProvider`）。
  Future<void> setProvider(AiProvider provider) => upsert(provider);

  /// 从预设新建一个平台（自动设为当前）。
  Future<AiProvider> addFromPreset(
    ProviderPreset preset, {
    String? apiKey,
    String? model,
    String? name,
    ProviderKind? kind,
  }) async {
    final provider = providerFromPreset(
      preset,
      apiKey: apiKey,
      model: model,
      name: name,
      kind: kind,
    );
    await upsert(provider);
    await setCurrent(provider.id);
    return provider;
  }

  /// 删除平台（并清理 currentId）。
  Future<void> remove(String id) async {
    _providers = _providers.where((p) => p.id != id).toList(growable: true);
    if (_currentId == id) {
      _currentId = _providers.isEmpty ? null : _providers.first.id;
    }
    await _persist();
  }

  /// 选择当前平台（传 null = 取消选择）。
  Future<void> setCurrent(String? id) async {
    final next = (id == null || id.isEmpty || byId(id) == null) ? null : id;
    if (next == _currentId) return;
    _currentId = next;
    await _persist();
  }

  /// 用 `GET /models` 的结果刷新候选列表（不动当前 model）。
  Future<void> setModels(String providerId, List<ProviderModel> models) async {
    final provider = byId(providerId);
    if (provider == null) return;
    final ids = models.map((m) => m.id).where((e) => e.isNotEmpty).toList(growable: false);
    if (ids.isEmpty) return;
    await upsert(provider.copyWith(models: ids));
  }

  /// 只改某个平台的 API Key。
  Future<void> setApiKey(String providerId, String apiKey) async {
    final provider = byId(providerId);
    if (provider == null) return;
    await upsert(provider.copyWith(apiKey: apiKey));
  }

  /// 只改某个平台的模型。
  Future<void> setModel(String providerId, String model) async {
    final provider = byId(providerId);
    if (provider == null) return;
    await upsert(provider.copyWith(model: model));
  }

  /// 清空全部平台（设置页危险操作）。
  Future<void> clear() async {
    _providers = <AiProvider>[];
    _currentId = null;
    await _persist();
  }

  Future<void> _persist() async {
    notifyListeners();
    try {
      await _prefs.setString(
        prefsKey,
        jsonEncode(<String, Object?>{
          'providers': _providers.map((p) => p.toJson()).toList(growable: false),
          'current': _currentId,
        }),
      );
    } catch (_) {
      // 落盘失败不影响内存态。
    }
  }
}

// ---------------------------------------------------------------------------
// Riverpod 接线（名字冻结：providerStoreProvider / providerBookProvider）
// ---------------------------------------------------------------------------

/// 由 `main()` override 注入。未 override 时抛产品断言文案。
final Provider<ProviderStore> providerStoreProvider = Provider<ProviderStore>(
  (Ref ref) => throw StateError('providerStoreProvider 需要在 ProviderScope 里 override'),
  name: 'providerStoreProvider',
);

/// 平台列表的响应式快照控制器。
class ProviderBookController extends Notifier<ProviderBook> {
  /// 底层 store（含写方法）。
  ProviderStore get store => ref.read(providerStoreProvider);

  @override
  ProviderBook build() {
    final store = ref.watch(providerStoreProvider);
    void onChanged() {
      state = store.book;
    }

    store.addListener(onChanged);
    ref.onDispose(() => store.removeListener(onChanged));
    return store.book;
  }

  Future<void> upsertProvider(AiProvider provider) => store.upsert(provider);

  Future<AiProvider> addFromPreset(
    ProviderPreset preset, {
    String? apiKey,
    String? model,
    String? name,
    ProviderKind? kind,
  }) =>
      store.addFromPreset(preset, apiKey: apiKey, model: model, name: name, kind: kind);

  Future<void> removeProvider(String id) => store.remove(id);

  Future<void> setCurrent(String? id) => store.setCurrent(id);

  Future<void> setModels(String providerId, List<ProviderModel> models) =>
      store.setModels(providerId, models);

  Future<void> setApiKey(String providerId, String apiKey) =>
      store.setApiKey(providerId, apiKey);

  Future<void> setModel(String providerId, String model) =>
      store.setModel(providerId, model);

  Future<void> clear() => store.clear();
}

/// 平台列表快照。
final NotifierProvider<ProviderBookController, ProviderBook> providerBookProvider =
    NotifierProvider<ProviderBookController, ProviderBook>(
  ProviderBookController.new,
  name: 'providerBookProvider',
);
