/// Keepsake（留声）— 应用入口。
///
/// 启动顺序（契约 C）：`WidgetsFlutterBinding` → `SharedPreferences.getInstance()` →
/// `SettingsStore.load` / `ProviderStore.load` →
/// `runApp(ProviderScope(overrides: [...]))`。
///
/// **必须** override `settingsStoreProvider` / `providerStoreProvider`，否则 app 自己的断言
/// 会在运行期抛出（`core/settings.dart` / `core/provider_store.dart` 里的产品文案）。
///
/// UI 归属（批次 F2）：`KeepsakeApp` 是 `MaterialApp`（主题用基座 `KeepsakeTheme`，
/// `themeMode` 跟随设置），首页 = `SessionsScreen`（会话列表）。无路由表（`next-steps.md` §0）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/providers.dart';
import 'core/theme.dart';
import 'features/sessions/sessions_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final settingsStore = await SettingsStore.load(prefs);
  final providerStore = await ProviderStore.load(prefs);

  runApp(
    ProviderScope(
      overrides: [
        // 契约 C：这两个 provider 必须在根 ProviderScope 里 override。
        settingsStoreProvider.overrideWithValue(settingsStore),
        providerStoreProvider.overrideWithValue(providerStore),
      ],
      child: const KeepsakeApp(),
    ),
  );
}

/// 应用根 widget。
class KeepsakeApp extends ConsumerWidget {
  const KeepsakeApp({super.key});

  /// 系统字体缩放的允许上限（M5）。
  ///
  /// 华为「超大字体」、小米「显示大小最大」会把 textScale 推到 1.5～2.0，
  /// 聊天页的 44dp 触达容器与双行 AppBar 在这种倍数下必然溢出；
  /// 夹到 1.3 仍尊重用户「放大」的意图，又保证布局不被压碎。
  static const double maxTextScale = 1.3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 主题跟随设置（深浅色 / 系统）。
    final settings = ref.watch(settingsProvider);

    return MaterialApp(
      title: 'Keepsake（留声）',
      debugShowCheckedModeBanner: false,
      theme: KeepsakeTheme.light,
      darkTheme: KeepsakeTheme.dark,
      themeMode: settings.themeMode,
      // M5：全应用统一夹住 textScaler（TextScaler.clamp 对线性/非线性缩放都成立）。
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(maxScaleFactor: maxTextScale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const SessionsScreen(),
    );
  }
}
