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
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/providers.dart';
import 'core/skin_tokens.dart';
import 'core/theme.dart';
import 'features/sessions/sessions_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final settingsStore = await SettingsStore.load(prefs);
  final providerStore = await ProviderStore.load(prefs);

  // E 纸感皮肤用打包的思源宋体（2.5MB OTF，见 `pubspec.yaml` 的 fonts）。
  //
  // Flutter 的 asset 字体是「首次用到这个字体族」时才异步加载并解析整份
  // 字体文件。如果等到用户点开聊天页才触发，聊天页首帧要等字体解析完成，
  // 真机上这个等待超过系统 5s 无响应阈值就会弹 ANR——现象正是「冷启动后
  // 第一次进聊天卡死、再进就正常」（第二次字形已缓存）。
  //
  // 所以在 runApp 之前就把它加载好：E 用户冷启动多花一两百毫秒，
  // 换来之后所有页面同步可用，聊天页不再有首帧等待。
  if (settingsStore.value.skinId == 'e') {
    await _preloadSerifFont();
  }

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

/// 预加载 E 皮肤的主字体（[kSerifFontFamily]）。
///
/// 失败不阻塞启动：字体缺失时 Flutter 会退回系统字体，可读但没衬线。
Future<void> _preloadSerifFont() async {
  try {
    final loader = FontLoader(kSerifFontFamily);
    loader.addFont(rootBundle.load('assets/fonts/KeepsakeSerif-subset.otf'));
    await loader.load();
  } catch (_) {
    // 忽略：退回系统字体，不影响启动。
  }
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
    // 主题跟随设置（深浅色 / 系统）；皮肤 id 来自设置（注册表未知 id 自动回退）。
    final settings = ref.watch(settingsProvider);

    return MaterialApp(
      title: 'Keepsake（留声）',
      debugShowCheckedModeBanner: false,
      theme: KeepsakeTheme.of(Brightness.light, skinId: settings.skinId),
      darkTheme: KeepsakeTheme.of(Brightness.dark, skinId: settings.skinId),
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
