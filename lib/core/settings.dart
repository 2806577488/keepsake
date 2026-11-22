/// Keepsake（留声）— 本机设置（SharedPreferences 持久化）。
///
/// **契约 A 的一部分（冻结）**。符号证据（dart-symbols.md）：
/// `Settings` / `SettingsStore` / `SettingsController` / `createSettings`；
/// 持久化 JSON 的 key 证据（tokens-snake）：`system_prompt`、`context_keep_rounds`、
/// `thinking_level`、`provider_id`、`search_enabled`、`ai_providers`、`theme`。
///
/// 读：`ref.watch(settingsProvider)` → `Settings`（不可变）。
/// 写：`ref.read(settingsProvider.notifier).setXxx(...)`（内部走 `SettingsStore.update`）。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/provider_models.dart' show kDefaultModelName;

/// 默认 system prompt（prompts.md §1 原文 [确定]）。
const String kDefaultSystemPrompt =
    '你是一个乐于助人的 AI 助手。回答准确、简洁、有条理；不确定时如实说明，不要编造。默认使用用户提问的语言回复。';

/// 上下文预算默认值（[推断]：保留最近 20 轮）。
const int kDefaultContextKeepRounds = 20;

/// 模型上下文窗口默认值（用于计算「本会话占用率」，可在设置 → 用量里改）。
const int kDefaultContextWindowTokens = 128000;

/// 上下文窗口允许范围（1k–1M，设置页校验用）。
const int kMinContextWindowTokens = 1000;
const int kMaxContextWindowTokens = 1000000;

/// 思考强度档位（ui-strings §2 原文标签：高/中/低 [确定]）。
enum ThinkingLevel {
  low('low', '低'),
  medium('medium', '中'),
  high('high', '高');

  const ThinkingLevel(this.wireName, this.label);

  /// 持久化字符串。
  final String wireName;

  /// UI 标签（`高`/`中`/`低`）。
  final String label;

  /// 更详细的档位说明（ui-strings §2 [确定]）。
  String get description => switch (this) {
    ThinkingLevel.low => '更快、更省，适合日常问答',
    ThinkingLevel.medium => '默认，平衡速度与推理',
    ThinkingLevel.high => '给更多思考预算，适合难题/写作',
  };

  static ThinkingLevel parse(
    Object? raw, {
    ThinkingLevel fallback = ThinkingLevel.medium,
  }) {
    if (raw is ThinkingLevel) return raw;
    final value = raw?.toString().trim().toLowerCase() ?? '';
    return switch (value) {
      'low' || '低' => ThinkingLevel.low,
      'medium' || '中' || 'mid' => ThinkingLevel.medium,
      'high' || '高' => ThinkingLevel.high,
      _ => fallback,
    };
  }

  /// 从持久化字符串还原档位；**空串 / 未知值返回 null**。
  ///
  /// 与 [parse] 的区别：`null` 表示「没有会话级覆盖」，由调用方回落到全局
  /// 设置里的默认档位（[Settings.thinkingLevel]）。会话覆盖列
  /// `sessions.thinking_level` 为空时就走这条路。
  static ThinkingLevel? tryParse(Object? raw) {
    if (raw is ThinkingLevel) return raw;
    final value = raw?.toString().trim().toLowerCase() ?? '';
    return switch (value) {
      'low' || '低' => ThinkingLevel.low,
      'medium' || '中' || 'mid' => ThinkingLevel.medium,
      'high' || '高' => ThinkingLevel.high,
      _ => null,
    };
  }
}

/// 全局设置（不可变）。
@immutable
class Settings {
  const Settings({
    this.systemPrompt = '',
    this.contextKeepRounds = kDefaultContextKeepRounds,
    this.contextWindowTokens = kDefaultContextWindowTokens,
    this.providerId = '',
    this.defaultModel = kDefaultModelName,
    this.thinkingLevel = ThinkingLevel.medium,
    this.thinkingEnabled = false,
    this.searchEnabled = false,
    this.themeMode = ThemeMode.system,
    this.ttsSpeed = 1.0,
    this.ttsVoice = '',
    this.memoryEnabled = true,
    this.moodEnabled = true,
    this.personaEnabled = true,
  });

  const Settings.defaults() : this();

  /// 系统提示词；空串表示用 [kDefaultSystemPrompt]（UI「留空则使用默认提示词」）。
  final String systemPrompt;

  /// 上下文预算：保留最近 N 轮；`<= 0` 表示「不限制（全部历史）」。
  final int contextKeepRounds;

  /// 模型上下文窗口（tokens），用于计算对话页「占用率」。
  final int contextWindowTokens;

  /// 当前选中的 AI 平台 id；空串 = 未选。
  final String providerId;

  /// 默认模型（聊天页可再切换）。
  final String defaultModel;

  /// 思考强度档位。
  final ThinkingLevel thinkingLevel;

  /// 深度思考总开关默认值。
  final bool thinkingEnabled;

  /// 联网搜索默认值。
  final bool searchEnabled;

  /// 深浅色。
  final ThemeMode themeMode;

  /// TTS 语速（[推断] 0.5–2.0）。
  final double ttsSpeed;

  /// TTS 音色（`voice_id`，[推断]）。
  final String ttsVoice;

  /// 记忆与回忆（App 内自带大脑；关掉后退化成普通聊天，也不做后台整理）。
  final bool memoryEnabled;

  /// 情绪（注入「当前心情」，并按轮更新）。
  final bool moodEnabled;

  /// 人格（注入「表达倾向」，并统计倾向）。
  final bool personaEnabled;

  /// 大脑是否至少有开关打开。
  bool get brainAnyEnabled => memoryEnabled || moodEnabled || personaEnabled;

  /// 实际生效的 system prompt。
  String get resolvedSystemPrompt {
    final trimmed = systemPrompt.trim();
    return trimmed.isEmpty ? kDefaultSystemPrompt : trimmed;
  }

  /// 是否「不限制（全部历史）」。
  bool get contextUnlimited => contextKeepRounds <= 0;

  bool get isDark => themeMode == ThemeMode.dark;

  Settings copyWith({
    String? systemPrompt,
    int? contextKeepRounds,
    int? contextWindowTokens,
    String? providerId,
    String? defaultModel,
    ThinkingLevel? thinkingLevel,
    bool? thinkingEnabled,
    bool? searchEnabled,
    ThemeMode? themeMode,
    double? ttsSpeed,
    String? ttsVoice,
    bool? memoryEnabled,
    bool? moodEnabled,
    bool? personaEnabled,
  }) {
    return Settings(
      systemPrompt: systemPrompt ?? this.systemPrompt,
      contextKeepRounds: contextKeepRounds ?? this.contextKeepRounds,
      contextWindowTokens: contextWindowTokens ?? this.contextWindowTokens,
      providerId: providerId ?? this.providerId,
      defaultModel: defaultModel ?? this.defaultModel,
      thinkingLevel: thinkingLevel ?? this.thinkingLevel,
      thinkingEnabled: thinkingEnabled ?? this.thinkingEnabled,
      searchEnabled: searchEnabled ?? this.searchEnabled,
      themeMode: themeMode ?? this.themeMode,
      ttsSpeed: ttsSpeed ?? this.ttsSpeed,
      ttsVoice: ttsVoice ?? this.ttsVoice,
      memoryEnabled: memoryEnabled ?? this.memoryEnabled,
      moodEnabled: moodEnabled ?? this.moodEnabled,
      personaEnabled: personaEnabled ?? this.personaEnabled,
    );
  }

  /// 持久化 JSON（snake_case，与旧版本数据兼容）。
  Map<String, Object?> toJson() => <String, Object?>{
    'system_prompt': systemPrompt,
    'context_keep_rounds': contextKeepRounds,
    'context_window_tokens': contextWindowTokens,
    'provider_id': providerId,
    'default_model': defaultModel,
    'thinking_level': thinkingLevel.wireName,
    'thinking_enabled': thinkingEnabled,
    'search_enabled': searchEnabled,
    'theme': themeMode.name,
    'tts_speed': ttsSpeed,
    'voice_id': ttsVoice,
    'memory_enabled': memoryEnabled,
    'mood_enabled': moodEnabled,
    'persona_enabled': personaEnabled,
  };

  /// 容错解析：缺字段用默认值；snake/camel 都接受。
  factory Settings.fromJson(Map<String, Object?> json) {
    return Settings(
      systemPrompt: _str(json, 'system_prompt', 'systemPrompt') ?? '',
      contextKeepRounds:
          _int(json, 'context_keep_rounds', 'contextKeepRounds') ??
          kDefaultContextKeepRounds,
      contextWindowTokens: _contextWindowTokens(
        _int(json, 'context_window_tokens', 'contextWindowTokens'),
      ),
      providerId: _str(json, 'provider_id', 'providerId') ?? '',
      defaultModel:
          _str(json, 'default_model', 'defaultModel') ?? kDefaultModelName,
      thinkingLevel: ThinkingLevel.parse(
        _str(json, 'thinking_level', 'thinkingLevel'),
      ),
      thinkingEnabled:
          _bool(json, 'thinking_enabled', 'thinkingEnabled') ?? false,
      searchEnabled: _bool(json, 'search_enabled', 'searchEnabled') ?? false,
      themeMode: _themeMode(_str(json, 'theme', 'theme_mode', 'themeMode')),
      ttsSpeed: _double(json, 'tts_speed', 'ttsSpeed') ?? 1.0,
      ttsVoice: _str(json, 'voice_id', 'voiceId', 'tts_voice') ?? '',
      memoryEnabled: _bool(json, 'memory_enabled', 'memoryEnabled') ?? true,
      moodEnabled: _bool(json, 'mood_enabled', 'moodEnabled') ?? true,
      personaEnabled: _bool(json, 'persona_enabled', 'personaEnabled') ?? true,
    );
  }

  /// 兼容符号 `createSettings`：从 JSON/空值构造。
  static Settings createSettings([Map<String, Object?>? json]) =>
      json == null ? const Settings() : Settings.fromJson(json);

  @override
  bool operator ==(Object other) =>
      other is Settings &&
      other.systemPrompt == systemPrompt &&
      other.contextKeepRounds == contextKeepRounds &&
      other.contextWindowTokens == contextWindowTokens &&
      other.providerId == providerId &&
      other.defaultModel == defaultModel &&
      other.thinkingLevel == thinkingLevel &&
      other.thinkingEnabled == thinkingEnabled &&
      other.searchEnabled == searchEnabled &&
      other.themeMode == themeMode &&
      other.ttsSpeed == ttsSpeed &&
      other.ttsVoice == ttsVoice &&
      other.memoryEnabled == memoryEnabled &&
      other.moodEnabled == moodEnabled &&
      other.personaEnabled == personaEnabled;

  @override
  int get hashCode => Object.hash(
    systemPrompt,
    contextKeepRounds,
    contextWindowTokens,
    providerId,
    defaultModel,
    thinkingLevel,
    thinkingEnabled,
    searchEnabled,
    themeMode,
    ttsSpeed,
    ttsVoice,
    memoryEnabled,
    moodEnabled,
    personaEnabled,
  );

  @override
  String toString() =>
      'Settings(provider=$providerId, model=$defaultModel, '
      'rounds=$contextKeepRounds, window=$contextWindowTokens, '
      'thinking=${thinkingLevel.wireName}, search=$searchEnabled, '
      'theme=${themeMode.name}, brain='
      '${memoryEnabled ? 'm' : '-'}${moodEnabled ? 'o' : '-'}'
      '${personaEnabled ? 'p' : '-'})';
}

// ---------------------------------------------------------------------------
// Store（ChangeNotifier，由 main.dart 注入 ProviderScope override）
// ---------------------------------------------------------------------------

/// 设置持久化：SharedPreferences 里的一个 JSON 字符串（key = `settings`）。
///
/// `main()` 里先 `await SettingsStore.load(prefs)`，再用
/// `settingsStoreProvider.overrideWithValue(store)` 注入，因此
/// `settingsStoreProvider` 不需要异步。
class SettingsStore extends ChangeNotifier {
  SettingsStore._(this._prefs, this._value);

  /// SharedPreferences 里的 key。
  static const String prefsKey = 'settings';

  final SharedPreferences _prefs;
  Settings _value;

  /// 当前设置快照。
  Settings get value => _value;

  /// 别名（部分旧代码用 `settings`）。
  Settings get settings => _value;

  /// 从 SharedPreferences 读取（损坏数据回退默认值，不抛异常）。
  static Future<SettingsStore> load(SharedPreferences prefs) async {
    Settings parsed = const Settings();
    final raw = prefs.getString(prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          parsed = Settings.fromJson(decoded.cast<String, Object?>());
        }
      } catch (_) {
        // 设置项损坏时使用默认值，不让应用起不来。
        parsed = const Settings();
      }
    }
    return SettingsStore._(prefs, parsed);
  }

  /// 写入并通知监听者（幂等；只有内容变化才落盘）。
  Future<void> update(Settings next) async {
    if (next == _value) {
      // 内容没变也要保证监听者不抖动，直接返回。
      return;
    }
    _value = next;
    notifyListeners();
    try {
      await _prefs.setString(prefsKey, jsonEncode(next.toJson()));
    } catch (_) {
      // 落盘失败不影响内存态（下次再写）。
    }
  }

  /// 便捷：在现有值上打补丁。
  Future<void> patch({
    String? systemPrompt,
    int? contextKeepRounds,
    int? contextWindowTokens,
    String? providerId,
    String? defaultModel,
    ThinkingLevel? thinkingLevel,
    bool? thinkingEnabled,
    bool? searchEnabled,
    ThemeMode? themeMode,
    double? ttsSpeed,
    String? ttsVoice,
    bool? memoryEnabled,
    bool? moodEnabled,
    bool? personaEnabled,
  }) => update(
    _value.copyWith(
      systemPrompt: systemPrompt,
      contextKeepRounds: contextKeepRounds,
      contextWindowTokens: contextWindowTokens,
      providerId: providerId,
      defaultModel: defaultModel,
      thinkingLevel: thinkingLevel,
      thinkingEnabled: thinkingEnabled,
      searchEnabled: searchEnabled,
      themeMode: themeMode,
      ttsSpeed: ttsSpeed,
      ttsVoice: ttsVoice,
      memoryEnabled: memoryEnabled,
      moodEnabled: moodEnabled,
      personaEnabled: personaEnabled,
    ),
  );

  /// 复位（设置页「重置」）。不重置 AI 平台列表（那在 ProviderStore 里）。
  Future<void> reset() => update(const Settings());
}

// ---------------------------------------------------------------------------
// Riverpod 接线（名字冻结：settingsStoreProvider / settingsProvider）
// ---------------------------------------------------------------------------

/// 由 `main()` override 注入。未 override 时抛产品断言文案。
final Provider<SettingsStore> settingsStoreProvider = Provider<SettingsStore>(
  (Ref ref) =>
      throw StateError('settingsStoreProvider 需要在 ProviderScope 里 override'),
  name: 'settingsStoreProvider',
);

/// 设置控制器：`ref.watch(settingsProvider)` → `Settings`。
///
/// Riverpod 3 已移除 `ChangeNotifierProvider`，所以用 `Notifier` 桥接
/// [SettingsStore]（监听 ChangeNotifier 后同步 `state`）。
class SettingsController extends Notifier<Settings> {
  /// 底层 store（改完自动持久化）。
  SettingsStore get store => ref.read(settingsStoreProvider);

  @override
  Settings build() {
    final store = ref.watch(settingsStoreProvider);
    void onChanged() {
      // 通过 provider 的 state 广播；此时 build 已结束，赋值安全。
      state = store.value;
    }

    store.addListener(onChanged);
    ref.onDispose(() => store.removeListener(onChanged));
    return store.value;
  }

  /// 整包替换。
  Future<void> save(Settings next) => store.update(next);

  Future<void> setSystemPrompt(String value) =>
      store.patch(systemPrompt: value);

  Future<void> setContextKeepRounds(int rounds) =>
      store.patch(contextKeepRounds: rounds < 0 ? 0 : rounds);

  /// 设置模型上下文窗口（限额 1k–1M；超范围截断到边界）。
  Future<void> setContextWindowTokens(int tokens) {
    final clamped = tokens.clamp(
      kMinContextWindowTokens,
      kMaxContextWindowTokens,
    );
    return store.patch(contextWindowTokens: clamped);
  }

  Future<void> setProviderId(String? id) => store.patch(providerId: id ?? '');

  Future<void> setDefaultModel(String model) =>
      store.patch(defaultModel: model);

  Future<void> setThinkingLevel(ThinkingLevel level) =>
      store.patch(thinkingLevel: level);

  Future<void> setThinkingEnabled(bool enabled) =>
      store.patch(thinkingEnabled: enabled);

  Future<void> setSearchEnabled(bool enabled) =>
      store.patch(searchEnabled: enabled);

  Future<void> setThemeMode(ThemeMode mode) => store.patch(themeMode: mode);

  Future<void> setTtsSpeed(double speed) => store.patch(ttsSpeed: speed);

  Future<void> setTtsVoice(String voice) => store.patch(ttsVoice: voice);

  /// 记忆与回忆开关。
  Future<void> setMemoryEnabled(bool enabled) =>
      store.patch(memoryEnabled: enabled);

  /// 情绪开关。
  Future<void> setMoodEnabled(bool enabled) => store.patch(moodEnabled: enabled);

  /// 人格开关。
  Future<void> setPersonaEnabled(bool enabled) =>
      store.patch(personaEnabled: enabled);

  Future<void> reset() => store.reset();
}

/// 设置快照（不可变；`ref.watch` 它即可）。
final NotifierProvider<SettingsController, Settings> settingsProvider =
    NotifierProvider<SettingsController, Settings>(
      SettingsController.new,
      name: 'settingsProvider',
    );

// ---------------------------------------------------------------------------
// 内部 JSON 解析小工具
// ---------------------------------------------------------------------------

String? _str(
  Map<String, Object?> json,
  String key, [
  String? alt,
  String? alt2,
]) {
  for (final k in <String?>[key, alt, alt2]) {
    if (k == null) continue;
    final value = json[k];
    if (value == null) continue;
    final text = value.toString();
    if (text.isNotEmpty) return text;
  }
  return null;
}

int? _int(Map<String, Object?> json, String key, [String? alt]) {
  for (final k in <String?>[key, alt]) {
    if (k == null) continue;
    final value = json[k];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
  }
  return null;
}

double? _double(Map<String, Object?> json, String key, [String? alt]) {
  for (final k in <String?>[key, alt]) {
    if (k == null) continue;
    final value = json[k];
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
  }
  return null;
}

bool? _bool(Map<String, Object?> json, String key, [String? alt]) {
  for (final k in <String?>[key, alt]) {
    if (k == null) continue;
    final value = json[k];
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final v = value.toLowerCase().trim();
      if (v == 'true' || v == '1') return true;
      if (v == 'false' || v == '0') return false;
    }
  }
  return null;
}

/// 上下文窗口解析：缺失/非法值用默认值，越界值截断到 1k–1M。
int _contextWindowTokens(int? raw) {
  if (raw == null || raw <= 0) return kDefaultContextWindowTokens;
  return raw.clamp(kMinContextWindowTokens, kMaxContextWindowTokens);
}

ThemeMode _themeMode(String? raw) => switch (raw?.trim().toLowerCase()) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};
