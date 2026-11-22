/// Keepsake（留声）— 应用内更新（数据源：GitHub Releases）。
///
/// 链路：
/// 1. **检查**：依次尝试 [UpdateService.releaseApiUrls]（`api.github.com` →
///    `gh-proxy.com` 镜像）的 `releases/latest`，读 `tag_name` / `body` /
///    `assets[].browser_download_url`（挑 `.apk`），与 `package_info_plus`
///    报告的当前版本做语义化比较；全部源都失败时抛带 `manualUrl` 的错误，
///    让用户能「在浏览器打开」Release 页；
/// 2. **下载**：流式写入外部存储 `updates/`（拿不到就退到临时目录），带进度回调；
/// 3. **安装**：走 Kotlin 侧 MethodChannel `keepsake/update` 的 `installApk`
///    （`Intent(ACTION_VIEW) + FileProvider`），安装前检查「允许安装未知来源应用」；
///    被厂商安全策略拦住时按 `Build.MANUFACTURER` 给中文引导（H4）。
///
/// 失败语义（显式）：所有失败都抛 [UpdateException]（消息可直接展示）；
/// 缺少安装权限单独抛 [NeedInstallPermission]，由调用方引导去系统设置。
/// 本文件不做静默 catch —— 连「不要打扰用户」的静默检查也只吞掉异常的展示，
/// 真实原因仍通过 debugPrint 打出来。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 更新相关的可展示错误。
class UpdateException implements Exception {
  const UpdateException(this.message, {this.manualUrl});

  /// 已经带好中文前缀，可直接 `_toast(error.message)`。
  final String message;

  /// 可选的「手动下载」地址（Release 页）。
  ///
  /// 只有「自动链路确实走不通」时才带（H3：所有源都失败、H4：安装被厂商拦截），
  /// 调用方的失败对话框据此多给一个「在浏览器打开」按钮。
  final String? manualUrl;

  @override
  String toString() => message;
}

/// 没有「安装未知来源应用」权限：调用方应打开系统设置引导用户。
class NeedInstallPermission implements Exception {
  const NeedInstallPermission(this.message, {this.manualUrl});

  final String message;

  /// 同 [UpdateException.manualUrl]：给「在浏览器打开下载页」兜底。
  final String? manualUrl;

  @override
  String toString() => message;
}

/// 单个更新源不可用（超时/网络/403/响应异常）：换下一个源再试。
class _EndpointFailure implements Exception {
  const _EndpointFailure(this.reason);

  final String reason;
}

/// 明确的服务端语义（如 404「还没发 Release」）：换源也没用，直接失败。
class _DefinitiveFailure implements Exception {
  const _DefinitiveFailure(this.message);

  final String message;
}

/// Release 里挑中的 APK 附件。
class ApkAsset {
  const ApkAsset({
    required this.name,
    required this.url,
    required this.size,
  });

  /// 附件名（`assets[].name`），用作本地文件名。
  final String name;

  /// `browser_download_url`，公开仓库可直接下。
  final String url;

  /// 字节数；GitHub 未给出时为 0。
  final int size;
}

/// 一次更新检查的结果。
class UpdateInfo {
  const UpdateInfo({
    required this.current,
    required this.latest,
    required this.notes,
    required this.tagName,
    this.apk,
  });

  /// 当前安装版本（`0.4.14`）。
  final String current;

  /// 远端最新版本（tag 去掉 v 前缀，如 `0.4.15`）。
  final String latest;

  /// Release 说明原文（`body`，Markdown）。
  final String notes;

  /// 原始 tag（如 `v0.4.15`）。
  final String tagName;

  /// 最新 Release 里的 arm64/通用 APK 附件；没有 APK 时为 null。
  final ApkAsset? apk;

  /// 是否有比当前版本更新的版本。
  bool get hasUpdate => UpdateService.isNewer(latest, current);

  /// 下载地址（没有附件时为 null）。
  String? get apkUrl => apk?.url;

  @override
  String toString() =>
      'UpdateInfo(current=$current, latest=$latest, hasUpdate=$hasUpdate, '
      'apk=${apk?.name})';
}

/// GitHub Releases 更新服务（纯静态入口，便于测试注入 mock client）。
abstract final class UpdateService {
  /// 仓库 slug（公开仓库，匿名读 API 即可）。
  static const String repoSlug = '2806577488/keepsake';

  /// Release 页（手动下载兜底）。H3/H4 失败对话框的「在浏览器打开」都用它。
  static const String manualUrl =
      'https://github.com/2806577488/keepsake/releases/latest';

  /// 依次尝试的更新源（H3）。
  ///
  /// 大陆网络下 `api.github.com` 的 DNS 污染/间歇不可达是常态，所以：
  /// 1. 官方 API；
  /// 2. `gh-proxy.com` 镜像（不可用时请求直接失败 → 自动跳过，不影响官方源）。
  /// 由前到后逐个尝试，任一成功即用结果；全部失败才报错并带 [manualUrl]。
  static const List<String> releaseApiUrls = <String>[
    'https://api.github.com/repos/2806577488/keepsake/releases/latest',
    'https://gh-proxy.com/https://api.github.com/'
        'repos/2806577488/keepsake/releases/latest',
  ];

  /// 最新 Release 接口（第一个源；保留给日志与测试用）。
  static final Uri latestReleaseUri = Uri.parse(releaseApiUrls.first);

  /// GitHub API 强制要求 User-Agent，缺了会 403。
  static const String userAgent = 'keepsake-updater';

  /// 元数据请求默认超时（下载不限总时长，只用连接超时）。
  static const Duration defaultTimeout = Duration(seconds: 20);

  /// 安装用的原生通道。
  static const MethodChannel _channel = MethodChannel('keepsake/update');

  static const Map<String, String> _headers = <String, String>{
    'User-Agent': userAgent,
    'Accept': 'application/vnd.github+json',
  };

  static String? _cachedCurrent;

  /// 当前版本（只在首次调用时读 `PackageInfo`）。
  static Future<String> currentVersion({bool refresh = false}) async {
    final cached = _cachedCurrent;
    if (!refresh && cached != null) return cached;
    try {
      final info = await PackageInfo.fromPlatform();
      final version = _normalize(info.version);
      if (version.isEmpty) {
        throw const UpdateException('检查更新失败：本机版本号为空');
      }
      _cachedCurrent = version;
      return version;
    } on UpdateException {
      rethrow;
    } catch (error) {
      throw UpdateException('检查更新失败：读取本机版本失败（$error）');
    }
  }

  /// 检查是否有新版本。
  ///
  /// [httpClient] 为空时内部创建并关闭；传入时由调用方负责关闭。
  ///
  /// 换源策略（H3）：按 [releaseApiUrls] 顺序尝试，单源超时/网络错误/403/响应异常
  /// 都只算「这个源不可用」，自动换下一个；全部失败后抛带 [manualUrl] 的
  /// [UpdateException]，调用方据此给「在浏览器打开下载页」。
  static Future<UpdateInfo> check({
    http.Client? httpClient,
    Duration timeout = defaultTimeout,
  }) async {
    final current = await currentVersion(refresh: true);
    final client = httpClient ?? http.Client();
    final owned = httpClient == null;
    final failures = <String>[];
    try {
      for (final endpoint in releaseApiUrls) {
        try {
          return await _fetchRelease(
            client,
            endpoint,
            timeout: timeout,
            current: current,
          );
        } on _DefinitiveFailure catch (error) {
          // 服务端语义明确（如 404 还没有 Release）：换镜像也一样。
          throw UpdateException(error.message);
        } on _EndpointFailure catch (error) {
          failures.add(error.reason);
          debugPrint('更新源不可用（$endpoint）：${error.reason}，回退到下一个源');
        }
      }
      throw UpdateException(
        '检查更新失败：连不上 GitHub（${failures.join('；')}）。'
        '可以在浏览器打开下载页查看最新版本。',
        manualUrl: manualUrl,
      );
    } finally {
      if (owned) client.close();
    }
  }

  /// 请求单个更新源并解析成 [UpdateInfo]。
  ///
  /// 失败分两类：网络/限流/响应异常 → [_EndpointFailure]（可换源）；
  /// 404 → [_DefinitiveFailure]（换源无意义）。
  static Future<UpdateInfo> _fetchRelease(
    http.Client client,
    String endpoint, {
    required Duration timeout,
    required String current,
  }) async {
    final http.Response response;
    try {
      response = await client
          .get(Uri.parse(endpoint), headers: _headers)
          .timeout(timeout);
    } on TimeoutException {
      throw const _EndpointFailure('请求超时');
    } on http.ClientException catch (error) {
      throw _EndpointFailure('网络错误（${error.message}）');
    } catch (error) {
      throw _EndpointFailure('$error');
    }

    if (response.statusCode == 404) {
      throw const _DefinitiveFailure('检查更新失败：仓库还没有发布任何 Release');
    }
    if (response.statusCode == 403) {
      // GitHub 对匿名请求限流（60 次/小时）在国内 IP 上很常见；镜像可能仍是通的。
      throw const _EndpointFailure('接口被限流（HTTP 403）');
    }
    if (response.statusCode != 200) {
      throw _EndpointFailure('HTTP ${response.statusCode}');
    }

    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (error) {
      // 镜像返回 HTML 错误页时会走到这里，属于「这个源坏了」而不是「没有更新」。
      throw const _EndpointFailure('响应不是有效 JSON');
    }
    if (decoded is! Map) {
      throw const _EndpointFailure('响应格式不正确');
    }
    return _parse(Map<String, Object?>.from(decoded), current);
  }

  /// 语义化比较：`latest` 比 `base` 新时返回 true（忽略 v 前缀与非数字后缀）。
  static bool isNewer(String latest, String base) =>
      _compareVersions(latest, base) > 0;

  /// 比较两个版本号：前者新返回 1，相同返回 0，旧返回 -1。
  static int compareVersions(String a, String b) => _compareVersions(a, b);

  /// 流式下载 APK 到本地，返回落盘文件。
  ///
  /// [onProgress] 每收到一块就回调（已下载字节数, 总字节数；总长度未知时为 -1）。
  static Future<File> download(
    UpdateInfo info, {
    http.Client? httpClient,
    void Function(int received, int total)? onProgress,
    Duration timeout = defaultTimeout,
  }) async {
    final asset = info.apk;
    if (asset == null) {
      throw const UpdateException('下载失败：这个版本没有提供 APK 安装包');
    }
    final client = httpClient ?? http.Client();
    final owned = httpClient == null;
    File? target;
    IOSink? sink;
    try {
      final request = http.Request('GET', Uri.parse(asset.url))
        ..headers['User-Agent'] = userAgent;
      // 连接/首包超时；后续分块读取由调用方的进度条体现，不再卡总时长。
      final response = await client.send(request).timeout(timeout);
      if (response.statusCode != 200) {
        throw UpdateException('下载失败：HTTP ${response.statusCode}');
      }

      final dir = await _updateDir();
      final name = _safeFileName(asset.name, fallbackVersion: info.latest);
      target = File(p.join(dir.path, name));
      if (await target.exists()) {
        await target.delete();
      }
      sink = target.openWrite();
      final total = response.contentLength ?? -1;
      var received = 0;
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      final length = await target.length();
      if (total > 0 && length != total) {
        // 半截文件绝不能拿去安装，显式报错并删掉。
        throw UpdateException('下载失败：文件不完整（$length/$total 字节）');
      }
      return target;
    } on UpdateException {
      rethrow;
    } on TimeoutException {
      throw const UpdateException('下载失败：连接超时');
    } on http.ClientException catch (error) {
      throw UpdateException('下载失败：网络错误（${error.message}）');
    } on FileSystemException catch (error) {
      throw UpdateException('下载失败：写入文件出错（${error.message}）');
    } catch (error) {
      if (error is UpdateException || error is NeedInstallPermission) rethrow;
      throw UpdateException('下载失败：$error');
    } finally {
      if (sink != null) {
        // 中途失败：关掉句柄，再删掉半截文件（删失败也不该盖住原始错误）。
        try {
          await sink.close();
        } catch (error) {
          debugPrint('关闭下载文件句柄失败：$error');
        }
        final broken = target;
        if (broken != null) {
          try {
            if (await broken.exists()) await broken.delete();
          } catch (error) {
            debugPrint('清理不完整安装包失败：$error');
          }
        }
      }
      if (owned) client.close();
    }
  }

  /// 是否允许安装未知来源应用（Android 8.0+ 需要用户授权；更低版本恒为 true）。
  static Future<bool> canInstallPackages() async {
    if (!Platform.isAndroid) return false;
    try {
      final allowed = await _channel.invokeMethod<bool>('canInstallPackages');
      return allowed ?? false;
    } on MissingPluginException {
      throw const UpdateException('检查安装权限失败：原生通道不可用');
    } on PlatformException catch (error) {
      throw UpdateException('检查安装权限失败：${error.message ?? error.code}');
    }
  }

  /// 打开系统「允许安装未知来源应用」设置页。
  static Future<void> openInstallSettings() async {
    if (!Platform.isAndroid) {
      throw const UpdateException('只有 Android 支持应用内安装');
    }
    try {
      await _channel.invokeMethod<void>('openInstallSettings');
    } on MissingPluginException {
      throw const UpdateException('打开设置失败：原生通道不可用');
    } on PlatformException catch (error) {
      throw UpdateException('打开设置失败：${error.message ?? error.code}');
    }
  }

  /// 调用系统安装器打开 [path]。
  ///
  /// 会先确认文件存在、再确认安装权限；缺权限抛 [NeedInstallPermission]。
  /// 安装器被厂商安全策略拦住（H4）时，抛带厂商中文引导与 [manualUrl] 的
  /// [UpdateException]/[NeedInstallPermission]，调用方给「去设置」和「在浏览器打开」。
  static Future<void> installApk(String path) async {
    if (!Platform.isAndroid) {
      throw const UpdateException('只有 Android 支持应用内安装');
    }
    final file = File(path);
    if (!await file.exists()) {
      throw UpdateException(
        '安装失败：安装包不存在（$path）',
        manualUrl: manualUrl,
      );
    }
    if (!await canInstallPackages()) {
      final hint = await installBlockedHint();
      throw NeedInstallPermission(
        '安装失败：还没有允许「安装未知来源应用」。$hint',
        manualUrl: manualUrl,
      );
    }
    try {
      await _channel.invokeMethod<void>('installApk', <String, Object?>{
        'path': file.absolute.path,
      });
    } on MissingPluginException {
      throw const UpdateException('安装失败：原生通道不可用', manualUrl: manualUrl);
    } on PlatformException catch (error) {
      final hint = await installBlockedHint();
      // INSTALL_FAILED：安装器打不开/被安全策略拦；NEED_PERMISSION：授权在拉起后被收回。
      throw UpdateException(
        '安装失败：${error.message ?? error.code}。$hint',
        manualUrl: manualUrl,
      );
    }
  }

  /// 设备厂商（`Build.MANUFACTURER`，小写）；原生通道不可用时返回空串。
  ///
  /// 没有 `device_info_plus` 依赖，所以走已有的 `keepsake/update` 通道
  /// 里新增的 `deviceManufacturer` 方法（见 MainActivity.kt）。
  static Future<String> deviceManufacturer() async {
    if (!Platform.isAndroid) return '';
    try {
      final value = await _channel.invokeMethod<String>('deviceManufacturer');
      return (value ?? '').trim().toLowerCase();
    } on MissingPluginException {
      return '';
    } on PlatformException {
      return '';
    }
  }

  /// H4：安装被拦时的厂商中文引导（一句一条，可直接拼进错误消息）。
  ///
  /// 依据 `Build.MANUFACTURER`：华为/荣耀、小米/Redmi、OPPO/vivo/一加/realme，
  /// 其余走通用文案。只给「去哪关什么」，不假装能替用户关掉。
  static Future<String> installBlockedHint() async {
    final vendor = await deviceManufacturer();
    if (vendor.contains('huawei') || vendor.contains('honor')) {
      return '华为/荣耀：去 设置 > 系统和更新 > 纯净模式，关闭「增强防护」后重试。';
    }
    if (vendor.contains('xiaomi') ||
        vendor.contains('redmi') ||
        vendor.contains('poco')) {
      return '小米/Redmi：在应用设置里关闭「安装应用时自动扫描 / 联网校验」，'
          '必要时断网安装。';
    }
    if (vendor.contains('oppo') ||
        vendor.contains('vivo') ||
        vendor.contains('realme') ||
        vendor.contains('oneplus')) {
      return 'OPPO/vivo：安全检测提示里选「继续安装」（可能要勾选「已了解风险」）。';
    }
    return '若系统提示「来源不可信 / 安全检测」，到设置里允许本应用安装未知应用，'
        '或改用浏览器下载安装。';
  }

  // ---------------------------------------------------------------------------
  // 内部实现
  // ---------------------------------------------------------------------------

  static UpdateInfo _parse(Map<String, Object?> map, String current) {
    final tag = (map['tag_name'] ?? '').toString().trim();
    if (tag.isEmpty) {
      throw const UpdateException('检查更新失败：Release 缺少 tag_name');
    }
    final latest = _normalize(tag);
    if (latest.isEmpty) {
      throw UpdateException('检查更新失败：tag 无法解析为版本号（$tag）');
    }
    return UpdateInfo(
      current: current,
      latest: latest,
      notes: (map['body'] ?? '').toString(),
      tagName: tag,
      apk: _pickApk(map['assets']),
    );
  }

  /// 从 `assets[]` 里挑 APK（优先 arm64 / 通用，排除明显非本机的架构）。
  static ApkAsset? _pickApk(Object? rawAssets) {
    if (rawAssets is! List) return null;
    final candidates = <Map<String, Object?>>[];
    for (final item in rawAssets) {
      if (item is! Map) continue;
      final asset = Map<String, Object?>.from(item);
      final name = (asset['name'] ?? '').toString();
      final url = (asset['browser_download_url'] ?? '').toString();
      if (!name.toLowerCase().endsWith('.apk')) continue;
      if (url.isEmpty) continue;
      candidates.add(asset);
    }
    if (candidates.isEmpty) return null;

    Map<String, Object?>? chosen;
    for (final asset in candidates) {
      final name = (asset['name'] ?? '').toString().toLowerCase();
      if (name.contains('arm64') || name.contains('aarch64')) {
        chosen = asset;
        break;
      }
    }
    chosen ??= candidates.firstWhere(
      (asset) {
        final name = (asset['name'] ?? '').toString().toLowerCase();
        return !name.contains('armeabi') && !name.contains('x86');
      },
      orElse: () => candidates.first,
    );

    final sizeRaw = chosen['size'];
    final size = sizeRaw is num
        ? sizeRaw.toInt()
        : int.tryParse('$sizeRaw') ?? 0;
    return ApkAsset(
      name: (chosen['name'] ?? 'keepsake.apk').toString(),
      url: (chosen['browser_download_url'] ?? '').toString(),
      size: size < 0 ? 0 : size,
    );
  }

  /// 下载目录：优先外部存储 `files/updates`，拿不到就临时目录 `updates`。
  static Future<Directory> _updateDir() async {
    Directory base;
    if (Platform.isAndroid) {
      final external = await getExternalStorageDirectory();
      base = external ?? await getTemporaryDirectory();
    } else {
      base = await getTemporaryDirectory();
    }
    final dir = Directory(p.join(base.path, 'updates'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 附件名只保留 basename，去掉路径分隔符与可疑字符，兜底用版本号命名。
  static String _safeFileName(String raw, {required String fallbackVersion}) {
    var name = raw.trim();
    final slash = name.lastIndexOf(RegExp(r'[/\\]'));
    if (slash >= 0) name = name.substring(slash + 1);
    name = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (name.isEmpty || !name.toLowerCase().endsWith('.apk')) {
      name = 'keepsake-$fallbackVersion-arm64.apk';
    }
    return name;
  }

  /// 去掉 v 前缀 / 构建号后缀前的清洗。
  static String _normalize(String raw) {
    var value = raw.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      value = value.substring(1);
    }
    final buildIndex = value.indexOf('+');
    if (buildIndex >= 0) value = value.substring(0, buildIndex);
    return value.trim();
  }

  static int _compareVersions(String a, String b) {
    final left = _segments(a);
    final right = _segments(b);
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) return l < r ? -1 : 1;
    }
    return 0;
  }

  /// 拆成数字段：`v0.4.15-beta` → [0, 4, 15]。
  static List<int> _segments(String raw) {
    var value = _normalize(raw);
    // 预发布/元数据后缀（-beta、_rc1）不参与比较。
    value = value.split(RegExp(r'[-_]')).first;
    if (value.isEmpty) return const <int>[];
    return value
        .split('.')
        .map((part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList(growable: false);
  }
}
