/// Keepsake（留声）— 应用内更新（数据源：GitHub Releases）。
///
/// 发布仓库是**构建专库** `2806577488/keepsake-build`（源码库 `keepsake` 不再
/// 带任何 CI 构建规则），Release 资产命名约定见构建库的 `RELEASE.md`。
///
/// 链路：
/// 1. **检查**：依次尝试 [UpdateService.releaseApiUrls]（`api.github.com` →
///    `gh-proxy.com` 镜像）的 `releases/latest`，读 `tag_name` / `body` /
///    `assets[].browser_download_url`，与 `package_info_plus` 报告的当前版本做
///    语义化比较；全部源都失败时抛带 `manualUrl` 的错误，让用户能「在浏览器打开」；
/// 2. **挑包**（分 ABI）：按 `Build.SUPPORTED_ABIS` 选 `-arm64.apk` / `-arm.apk`，
///    对不上再退 `-universal.apk`；
/// 3. **差分更新**（可选，失败自动回退全量）：读了补丁元数据 `-patches.json` 后，
///    找 `from=当前版本`、ABI 匹配、且 `fromSha256` 与本机已安装 APK 一致的补丁，
///    下载补丁 → 原生 `applyPatch` 合并（`BsPatch.kt`，纯 Java/Kotlin 的 bspatch）
///    → 用元数据里的 `target_sha256` 校验新包；
/// 4. **下载**：流式写入外部存储 `updates/`（拿不到就退到临时目录），带进度回调；
/// 5. **安装**：走 Kotlin 侧 MethodChannel `keepsake/update` 的 `installApk`
///    （`Intent(ACTION_VIEW) + FileProvider`），安装前检查「允许安装未知来源应用」；
///    被厂商安全策略拦住时按 `Build.MANUFACTURER` 给中文引导（H4）。
///
/// 为什么差分不是「zip 条目差分」：APK 的 v2/v3 签名覆盖整个文件字节，
/// 重新打包不可能逐字节复现，客户端也没有私钥重签 → 装不上。所以必须「逐字节
/// 重建新 APK」（bsdiff 语义），见 `android/.../BsPatch.kt` 顶部注释。
///
/// 失败语义（显式）：所有失败都抛 [UpdateException]（消息可直接展示）；
/// 缺少安装权限单独抛 [NeedInstallPermission]，由调用方引导去系统设置。
/// 本文件不做静默 catch —— 连「不要打扰用户」的静默检查也只吞掉异常的展示，
/// 真实原因仍通过 debugPrint 打出来。差分路径的任何失败都**只**降级到全量下载，
/// 绝不把没校验过的包交给安装器。
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
    this.patch,
    this.patches = const <PatchAsset>[],
    this.patchMetadataUrl,
  });

  /// 当前安装版本（`0.4.20`）。
  final String current;

  /// 远端最新版本（tag 去掉 v 前缀，如 `0.4.21`）。
  final String latest;

  /// Release 说明原文（`body`，Markdown）。
  final String notes;

  /// 原始 tag（如 `v0.4.21`）。
  final String tagName;

  /// 最新 Release 里按本机 ABI 挑中的 APK 附件；没有 APK 时为 null。
  final ApkAsset? apk;

  /// 本次更新可用的差分补丁（已按 ABI / from / fromSha256 筛过）；不可用时为 null。
  final PatchAsset? patch;

  /// Release 里全部补丁附件（未筛，去掉元数据后不可用的也在里面）。
  final List<PatchAsset> patches;

  /// 补丁元数据 json 的下载地址（`keepsake-<ver>-patches.json`）；没有时为 null。
  final String? patchMetadataUrl;

  /// 是否有比当前版本更新的版本。
  bool get hasUpdate => UpdateService.isNewer(latest, current);

  /// 下载地址（没有附件时为 null）。
  String? get apkUrl => apk?.url;

  /// 差分补丁下载地址（没有可用补丁时为 null）。
  String? get patchUrl => patch?.url;

  /// 差分补丁自身的 sha256（没有可用补丁时为 null）。
  String? get patchSha256 => patch?.patchSha256;

  /// 这个补丁要求本机装的是哪个版本（没有可用补丁时为 null）。
  String? get patchFrom => patch?.fromVersion;

  /// 走差分更新时预计要下载的字节数；没有补丁时为 0。
  int get patchDownloadSize => patch?.size ?? 0;

  @override
  String toString() =>
      'UpdateInfo(current=$current, latest=$latest, hasUpdate=$hasUpdate, '
      'apk=${apk?.name}, patch=${patch?.name})';
}

/// Release 里的差分补丁附件（`keepsake-<from>-to-<to>-<abi>.patch`）。
///
/// sha256 来自配套的 `keepsake-<ver>-patches.json`（补丁本身不带校验值）；
/// 缺少 `targetSha256` 的补丁一律视为**不可用**——合并出来的包无法校验，
/// 宁可全量下载也不装。
class PatchAsset {
  const PatchAsset({
    required this.name,
    required this.url,
    required this.size,
    required this.fromVersion,
    required this.toVersion,
    required this.abi,
    this.patchSha256,
    this.fromSha256,
    this.targetSha256,
  });

  /// 附件名（`keepsake-0.4.20-to-0.4.21-arm64.patch`）。
  final String name;

  /// `browser_download_url`。
  final String url;

  /// 补丁字节数；GitHub 未给出时为 0。
  final int size;

  /// 补丁要求的本机版本（`0.4.20`）。
  final String fromVersion;

  /// 补丁产出的版本（`0.4.21`）。
  final String toVersion;

  /// 补丁对应的 ABI（`arm64` / `arm`）。
  final String abi;

  /// 补丁文件自身的 sha256。
  final String? patchSha256;

  /// 补丁要求「已安装 APK」的 sha256（用于确认补丁和本机是同一次构建）。
  final String? fromSha256;

  /// 合并后新 APK 的 sha256（**必填**才算可用）。
  final String? targetSha256;

  /// 元数据齐全（有目标 sha256）才允许拿来合并。
  bool get isVerified => (targetSha256 ?? '').trim().length == 64;

  /// 把元数据（来自 `-patches.json`）并进来，返回补全后的副本。
  PatchAsset withMetadata({
    String? patchSha256,
    String? fromSha256,
    String? targetSha256,
  }) {
    return PatchAsset(
      name: name,
      url: url,
      size: size,
      fromVersion: fromVersion,
      toVersion: toVersion,
      abi: abi,
      patchSha256: patchSha256 ?? this.patchSha256,
      fromSha256: fromSha256 ?? this.fromSha256,
      targetSha256: targetSha256 ?? this.targetSha256,
    );
  }

  @override
  String toString() =>
      'PatchAsset($name, from=$fromVersion, to=$toVersion, abi=$abi, '
      'size=$size, verified=$isVerified)';
}

/// GitHub Releases 更新服务（纯静态入口，便于测试注入 mock client）。
abstract final class UpdateService {
  /// 发布仓库：**构建专库**（源码库 `2806577488/keepsake` 已不再承载任何
  /// 构建/发布规则，见构建库 RELEASE.md）。
  static const String repoSlug = '2806577488/keepsake-build';

  /// 源码仓库 slug（仅用于日志/文档引用，更新链路不读它）。
  static const String sourceRepoSlug = '2806577488/keepsake';

  /// Release 页（手动下载兜底）。H3/H4 失败对话框的「在浏览器打开」都用它。
  static const String manualUrl =
      'https://github.com/2806577488/keepsake-build/releases/latest';

  /// 依次尝试的更新源（H3）。
  ///
  /// 大陆网络下 `api.github.com` 的 DNS 污染/间歇不可达是常态，所以：
  /// 1. 官方 API；
  /// 2. `gh-proxy.com` 镜像（不可用时请求直接失败 → 自动跳过，不影响官方源）。
  /// 由前到后逐个尝试，任一成功即用结果；全部失败才报错并带 [manualUrl]。
  static const List<String> releaseApiUrls = <String>[
    'https://api.github.com/repos/2806577488/keepsake-build/releases/latest',
    'https://gh-proxy.com/https://api.github.com/'
        'repos/2806577488/keepsake-build/releases/latest',
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

  /// 本机 ABI（只查一次：运行期不会变）。
  static List<String>? _cachedAbis;

  /// 已安装 APK 的 sha256（只算一次：装新版本后进程会重启）。
  static String? _cachedInstalledSha;

  /// 差分合并阶段的进度回调（原生 `patchProgress` 推回来时转发到这里）。
  static void Function(int done, int total)? _patchProgress;

  /// 双向通道的回调标记：只装一次。
  static bool _progressHandlerInstalled = false;

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
    // 先拿本机 ABI：挑包和挑补丁都要它，拿不到就退化成「优先通用包」。
    final abiToken = await _abiToken();
    final client = httpClient ?? http.Client();
    final owned = httpClient == null;
    final failures = <String>[];
    try {
      for (final endpoint in releaseApiUrls) {
        try {
          final info = await _fetchRelease(
            client,
            endpoint,
            timeout: timeout,
            current: current,
            abiToken: abiToken,
          );
          // 补丁元数据是「锦上添花」：拉不到就只是没有差分，不影响检查结果。
          return await _attachPatchState(
            info,
            client,
            timeout: timeout,
            abiToken: abiToken,
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
    required String abiToken,
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
    return _parse(
      Map<String, Object?>.from(decoded),
      current,
      abiToken: abiToken,
    );
  }

  /// 语义化比较：`latest` 比 `base` 新时返回 true（忽略 v 前缀与非数字后缀）。
  static bool isNewer(String latest, String base) =>
      _compareVersions(latest, base) > 0;

  /// 比较两个版本号：前者新返回 1，相同返回 0，旧返回 -1。
  static int compareVersions(String a, String b) => _compareVersions(a, b);

  /// 更新到 [info] 对应的版本：**优先差分补丁**，任何一步失败自动回退完整包。
  ///
  /// 进度语义：
  /// - 下载阶段走 [onProgress]（已下载字节数, 总字节数；总长未知时为 -1）；
  /// - 合并阶段由原生把 `patchProgress` 推回来，也转成 [onProgress]
  ///   （已合并字节数, 新包总字节数）；
  /// - [onStage] 只用于 UI 文案（「正在下载差分补丁…」等），可传 null。
  ///
  /// 返回可直接交给 [installApk] 的 APK 文件。**唯一**的失败出口是完整包下载
  /// 也失败（抛 [UpdateException]）；差分链路的任何错误都只降级、不报错。
  static Future<File> update(
    UpdateInfo info, {
    http.Client? httpClient,
    void Function(int received, int total)? onProgress,
    void Function(String stage)? onStage,
    Duration timeout = defaultTimeout,
  }) async {
    final patch = info.patch;
    if (patch != null) {
      try {
        return await _downloadAndApplyPatch(
          info,
          patch,
          httpClient: httpClient,
          onProgress: onProgress,
          onStage: onStage,
          timeout: timeout,
        );
      } on UpdateException catch (error) {
        // 保底：差分没走通就下完整包，不能把用户卡在错误上。
        debugPrint('差分更新没走通：${error.message}；回退完整包');
        onStage?.call('差分更新没走通，改为下载完整安装包…');
      } catch (error) {
        debugPrint('差分更新异常：$error；回退完整包');
        onStage?.call('差分更新没走通，改为下载完整安装包…');
      }
    }
    return download(
      info,
      httpClient: httpClient,
      onProgress: onProgress,
      timeout: timeout,
    );
  }

  /// 下载补丁 → 原生合并 → 校验新包。任何环节失败都抛 [UpdateException]，
  /// 由 [update] 捕获后回退完整包。
  static Future<File> _downloadAndApplyPatch(
    UpdateInfo info,
    PatchAsset patch, {
    http.Client? httpClient,
    void Function(int received, int total)? onProgress,
    void Function(String stage)? onStage,
    Duration timeout = defaultTimeout,
  }) async {
    final targetSha = patch.targetSha256?.trim() ?? '';
    if (targetSha.length != 64) {
      // 没有目标校验值就不合并：宁可全量下载，也不装没法验证的包。
      throw const UpdateException('差分更新不可用：补丁缺少新包 sha256');
    }
    final dir = await _updateDir();
    onStage?.call('正在下载差分补丁…');
    final patchFile = await _streamToFile(
      url: patch.url,
      fileName: _safeFileName(
        patch.name,
        fallbackVersion: info.latest,
        suffix: 'patch',
      ),
      label: '差分补丁',
      onProgress: onProgress,
      timeout: timeout,
      httpClient: httpClient,
    );

    try {
      onStage?.call('正在合并安装包…');
      // 合并进度由原生回推；复用同一个 onProgress 语义。
      _ensureProgressHandler();
      _patchProgress = onProgress;
      final String? path;
      try {
        path = await _channel.invokeMethod<String>('applyPatch', <String, Object?>{
          'patch': patchFile.absolute.path,
          'outDir': dir.path,
          'outName': 'keepsake-${info.latest}-${patch.abi}.apk',
          'patchSha256': patch.patchSha256 ?? '',
          'fromSha256': patch.fromSha256 ?? '',
          'targetSha256': targetSha,
        });
      } on MissingPluginException {
        throw const UpdateException('差分更新不可用：原生通道不可用');
      } on PlatformException catch (error) {
        throw UpdateException('差分合并失败：${error.message ?? error.code}');
      } finally {
        _patchProgress = null;
      }
      final newPath = (path ?? '').trim();
      if (newPath.isEmpty) {
        throw const UpdateException('差分合并失败：原生没有返回新包路径');
      }
      final file = File(newPath);
      if (!await file.exists()) {
        throw UpdateException('差分合并失败：新包没有落盘（$newPath）');
      }
      final length = await file.length();
      if (length <= 0) {
        throw UpdateException('差分合并失败：新包是空文件（$newPath）');
      }
      onStage?.call('合并完成，正在打开安装器…');
      return file;
    } finally {
      _patchProgress = null;
      // 补丁只对「这一版 → 下一版」有效，用完删掉，别在用户存储里堆着。
      try {
        if (await patchFile.exists()) await patchFile.delete();
      } catch (error) {
        debugPrint('清理补丁文件失败：$error');
      }
    }
  }

  /// 流式下载完整 APK 到本地，返回落盘文件。
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
    return _streamToFile(
      url: asset.url,
      fileName: _safeFileName(asset.name, fallbackVersion: info.latest),
      label: '安装包',
      onProgress: onProgress,
      timeout: timeout,
      httpClient: httpClient,
    );
  }

  /// 把一个远程文件流式写到 `updates/` 下（完整 APK 与差分补丁共用）。
  static Future<File> _streamToFile({
    required String url,
    required String fileName,
    required String label,
    http.Client? httpClient,
    void Function(int received, int total)? onProgress,
    Duration timeout = defaultTimeout,
  }) async {
    final client = httpClient ?? http.Client();
    final owned = httpClient == null;
    File? target;
    IOSink? sink;
    try {
      final request = http.Request('GET', Uri.parse(url))
        ..headers['User-Agent'] = userAgent;
      // 连接/首包超时；后续分块读取由调用方的进度条体现，不再卡总时长。
      final response = await client.send(request).timeout(timeout);
      if (response.statusCode != 200) {
        throw UpdateException('下载$label失败：HTTP ${response.statusCode}');
      }

      final dir = await _updateDir();
      target = File(p.join(dir.path, fileName));
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
        // 半截文件绝不能拿去安装或合并，显式报错并删掉。
        throw UpdateException('下载$label失败：文件不完整（$length/$total 字节）');
      }
      return target;
    } on UpdateException {
      rethrow;
    } on TimeoutException {
      throw UpdateException('下载$label失败：连接超时');
    } on http.ClientException catch (error) {
      throw UpdateException('下载$label失败：网络错误（${error.message}）');
    } on FileSystemException catch (error) {
      throw UpdateException('下载$label失败：写入文件出错（${error.message}）');
    } catch (error) {
      if (error is UpdateException || error is NeedInstallPermission) rethrow;
      throw UpdateException('下载$label失败：$error');
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
            debugPrint('清理不完整文件失败：$error');
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

  /// 本机支持的 ABI 列表（按优先级，`arm64-v8a` / `armeabi-v7a` …）。
  ///
  /// 没有 `device_info_plus` 依赖，走原生通道的 `supportedAbis`（见 MainActivity.kt）。
  /// 拿不到就返回空列表 —— 调用方退化到「优先通用包」，don't 猜。
  static Future<List<String>> supportedAbis({bool refresh = false}) async {
    final cached = _cachedAbis;
    if (!refresh && cached != null) return cached;
    if (!Platform.isAndroid) {
      _cachedAbis = const <String>[];
      return _cachedAbis!;
    }
    List<String> abis;
    try {
      final value = await _channel.invokeMethod<List<Object?>>('supportedAbis');
      abis = <String>[
        for (final item in value ?? const <Object?>[])
          if (item != null && item.toString().trim().isNotEmpty)
            item.toString().trim(),
      ];
    } on MissingPluginException {
      debugPrint('取 ABI 失败：原生通道不可用');
      abis = const <String>[];
    } on PlatformException catch (error) {
      debugPrint('取 ABI 失败：${error.message ?? error.code}');
      abis = const <String>[];
    }
    _cachedAbis = abis;
    return abis;
  }

  /// 把 `Build.SUPPORTED_ABIS` 收敛成发布资产里的 ABI 名（`arm64` / `arm`）。
  ///
  /// 其它架构（x86/x86_64、riscv64）我们不出包 → 返回空串，调用方退通用包。
  static String abiTokenOf(List<String> abis) {
    for (final raw in abis) {
      final abi = raw.toLowerCase();
      if (abi == 'arm64-v8a' || abi == 'aarch64') return 'arm64';
      if (abi == 'armeabi-v7a' || abi == 'armeabi') return 'arm';
    }
    return '';
  }

  /// 已安装 APK 的 sha256（原生算）；拿不到返回 null（不阻塞更新）。
  static Future<String?> installedApkSha256({bool refresh = false}) async {
    if (!Platform.isAndroid) return null;
    if (!refresh && _cachedInstalledSha != null) return _cachedInstalledSha;
    try {
      final value = await _channel.invokeMethod<String>('installedApkSha256');
      final sha = (value ?? '').trim().toLowerCase();
      if (sha.length != 64) return null;
      _cachedInstalledSha = sha;
      return sha;
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      debugPrint('读已安装 APK 的 sha256 失败：${error.message ?? error.code}');
      return null;
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

  static UpdateInfo _parse(
    Map<String, Object?> map,
    String current, {
    required String abiToken,
  }) {
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
      apk: _pickApk(map['assets'], abiToken),
      patches: _pickPatches(map['assets']),
      patchMetadataUrl: _pickPatchMetadataUrl(map['assets']),
    );
  }

  /// 从 `assets[]` 里挑 APK：**按本机 ABI 优先**，对不上再退通用包。
  ///
  /// 资产命名约定（构建库 RELEASE.md）：
  /// `keepsake-<ver>-arm64.apk`、`keepsake-<ver>-arm.apk`；
  /// 老版本可能只有 `keepsake-<ver>-universal.apk`。
  static ApkAsset? _pickApk(Object? rawAssets, String abiToken) {
    final candidates = _apkCandidates(rawAssets);
    if (candidates.isEmpty) return null;

    Map<String, Object?>? chosen;
    switch (abiToken) {
      case 'arm64':
        chosen = _firstAssetNamed(candidates, _isArm64Apk);
      case 'arm':
        chosen = _firstAssetNamed(candidates, _isArmApk);
      default:
        // ABI 不清楚（拿不到 SUPPORTED_ABIS）：通用包最保险，别猜架构。
        chosen = _firstAssetNamed(candidates, _isUniversalApk);
    }
    // 退路：本机 ABI 的包不存在 → 通用包 → arm64 → 任意非 x86。
    chosen ??= _firstAssetNamed(candidates, _isUniversalApk);
    chosen ??= _firstAssetNamed(candidates, _isArm64Apk);
    chosen ??= _firstAssetNamed(
      candidates,
      (name) => !name.contains('x86') && !name.contains('armeabi'),
    );
    chosen ??= candidates.first;

    final sizeRaw = chosen['size'];
    final size = sizeRaw is num ? sizeRaw.toInt() : int.tryParse('$sizeRaw') ?? 0;
    return ApkAsset(
      name: (chosen['name'] ?? 'keepsake.apk').toString(),
      url: (chosen['browser_download_url'] ?? '').toString(),
      size: size < 0 ? 0 : size,
    );
  }

  /// 所有 APK 附件（名字统一转小写，便于按 ABI 匹配）。
  static List<Map<String, Object?>> _apkCandidates(Object? rawAssets) {
    if (rawAssets is! List) return const <Map<String, Object?>>[];
    final out = <Map<String, Object?>>[];
    for (final item in rawAssets) {
      if (item is! Map) continue;
      final asset = Map<String, Object?>.from(item);
      final name = (asset['name'] ?? '').toString().toLowerCase();
      final url = (asset['browser_download_url'] ?? '').toString();
      if (!name.endsWith('.apk') || url.isEmpty) continue;
      out.add(asset);
    }
    return out;
  }

  static Map<String, Object?>? _firstAssetNamed(
    List<Map<String, Object?>> candidates,
    bool Function(String lowerName) test,
  ) {
    for (final asset in candidates) {
      final name = (asset['name'] ?? '').toString().toLowerCase();
      if (test(name)) return asset;
    }
    return null;
  }

  /// `keepsake-0.4.21-arm64.apk`。
  static bool _isArm64Apk(String lowerName) =>
      lowerName.contains('arm64') || lowerName.contains('aarch64');

  /// `keepsake-0.4.21-arm.apk`（32 位；不能把 arm64 包当成它）。
  static bool _isArmApk(String lowerName) =>
      !_isArm64Apk(lowerName) &&
      !_isUniversalApk(lowerName) &&
      (lowerName.contains('armeabi') ||
          RegExp(r'[-_]arm\.apk$').hasMatch(lowerName) ||
          RegExp(r'[-_]arm[-_.]').hasMatch(lowerName));

  /// `keepsake-0.4.19-universal.apk`（老版本的合并包）。
  static bool _isUniversalApk(String lowerName) =>
      lowerName.contains('universal');

  /// 补丁名约定：`keepsake-<from>-to-<to>-<abi>.patch`。
  static final RegExp _patchNamePattern =
      RegExp(r'^keepsake-(.+)-to-(.+)-(arm64|arm)\.patch$');

  /// 从 `assets[]` 里收差分补丁（此时还没有 sha256，要靠元数据 json 补）。
  static List<PatchAsset> _pickPatches(Object? rawAssets) {
    if (rawAssets is! List) return const <PatchAsset>[];
    final out = <PatchAsset>[];
    for (final item in rawAssets) {
      if (item is! Map) continue;
      final asset = Map<String, Object?>.from(item);
      final name = (asset['name'] ?? '').toString().trim();
      final url = (asset['browser_download_url'] ?? '').toString();
      if (!name.toLowerCase().endsWith('.patch') || url.isEmpty) continue;
      final match = _patchNamePattern.firstMatch(name);
      if (match == null) {
        debugPrint('忽略名字不符合约定的补丁附件：$name');
        continue;
      }
      final sizeRaw = asset['size'];
      final size = sizeRaw is num ? sizeRaw.toInt() : int.tryParse('$sizeRaw') ?? 0;
      out.add(
        PatchAsset(
          name: name,
          url: url,
          size: size < 0 ? 0 : size,
          fromVersion: _normalize(match.group(1) ?? ''),
          toVersion: _normalize(match.group(2) ?? ''),
          abi: match.group(3) ?? '',
        ),
      );
    }
    return out;
  }

  /// 补丁元数据 json 的下载地址（`keepsake-<ver>-patches.json`）。
  static String? _pickPatchMetadataUrl(Object? rawAssets) {
    if (rawAssets is! List) return null;
    for (final item in rawAssets) {
      if (item is! Map) continue;
      final asset = Map<String, Object?>.from(item);
      final name = (asset['name'] ?? '').toString().toLowerCase();
      final url = (asset['browser_download_url'] ?? '').toString();
      if (!name.endsWith('-patches.json') || url.isEmpty) continue;
      return url;
    }
    return null;
  }

  /// 本机 ABI 的资产标记；原生通道不可用时返回空串（不猜）。
  static Future<String> _abiToken() async {
    try {
      return abiTokenOf(await supportedAbis());
    } catch (error) {
      debugPrint('取 ABI 失败：$error');
      return '';
    }
  }

  /// 拉补丁元数据 + 读已安装 APK 的 sha256，决定这次能不能走差分。
  ///
  /// 任何一步失败都只把 `patch` 置空（降级成全量下载），**不**让检查更新失败。
  static Future<UpdateInfo> _attachPatchState(
    UpdateInfo info,
    http.Client client, {
    required Duration timeout,
    required String abiToken,
    required String current,
  }) async {
    if (!info.hasUpdate || info.patches.isEmpty) return info;
    var patches = info.patches;
    final metaUrl = info.patchMetadataUrl;
    if (metaUrl == null) {
      debugPrint('本次 Release 没有补丁元数据 json，跳过差分更新');
      return info;
    }
    try {
      final response = await client
          .get(Uri.parse(metaUrl), headers: _headers)
          .timeout(timeout);
      if (response.statusCode != 200) {
        debugPrint('补丁元数据不可用：HTTP ${response.statusCode}，跳过差分更新');
        return info;
      }
      patches = _mergePatchMetadata(
        patches,
        jsonDecode(utf8.decode(response.bodyBytes)),
      );
    } catch (error) {
      debugPrint('拉补丁元数据失败：$error，跳过差分更新');
      return info;
    }
    final installedSha = await installedApkSha256();
    final chosen = _selectPatch(
      patches,
      abiToken: abiToken,
      current: current,
      latest: info.latest,
      installedSha: installedSha,
    );
    debugPrint(
      '差分补丁：候选 ${patches.length} 个，选中 ${chosen?.name ?? '无'}'
      '（abi=$abiToken, from=$current, 本机 sha=${installedSha?.substring(0, 12) ?? '未知'}）',
    );
    return UpdateInfo(
      current: info.current,
      latest: info.latest,
      notes: info.notes,
      tagName: info.tagName,
      apk: info.apk,
      patch: chosen,
      patches: patches,
      patchMetadataUrl: info.patchMetadataUrl,
    );
  }

  /// 把 `-patches.json` 里的 sha256 并进补丁列表（按附件名对应）。
  static List<PatchAsset> _mergePatchMetadata(
    List<PatchAsset> patches,
    Object? decoded,
  ) {
    if (decoded is! Map) return patches;
    final list = decoded['patches'];
    if (list is! List) return patches;
    final byName = <String, Map<String, Object?>>{};
    for (final item in list) {
      if (item is! Map) continue;
      final entry = Map<String, Object?>.from(item);
      final name = (entry['name'] ?? '').toString().trim();
      if (name.isNotEmpty) byName[name] = entry;
    }
    final out = <PatchAsset>[];
    for (final patch in patches) {
      final entry = byName[patch.name];
      if (entry == null) {
        out.add(patch);
        continue;
      }
      String? shaOf(String key) {
        final value = (entry[key] ?? '').toString().trim().toLowerCase();
        return value.length == 64 ? value : null;
      }

      out.add(
        patch.withMetadata(
          patchSha256: shaOf('patch_sha256'),
          fromSha256: shaOf('from_sha256'),
          targetSha256: shaOf('target_sha256'),
        ),
      );
    }
    return out;
  }

  /// 选出唯一可用的补丁：ABI 对、from 是当前版本、to 是最新版、校验值齐全。
  static PatchAsset? _selectPatch(
    List<PatchAsset> patches, {
    required String abiToken,
    required String current,
    required String latest,
    required String? installedSha,
  }) {
    if (abiToken.isEmpty) {
      debugPrint('拿不到本机 ABI，跳过差分更新');
      return null;
    }
    for (final patch in patches) {
      if (!patch.isVerified) continue;
      if (patch.abi != abiToken) continue;
      if (patch.fromVersion != current) continue;
      if (patch.toVersion != latest) continue;
      final fromSha = (patch.fromSha256 ?? '').toLowerCase();
      if (installedSha != null && fromSha.isNotEmpty && fromSha != installedSha) {
        // 本机装的可能不是同一份构建（例如用户自己重签过）→ 这个补丁不能用。
        debugPrint('补丁 ${patch.name} 的 fromSha256 与本机不一致，跳过');
        continue;
      }
      return patch;
    }
    return null;
  }

  /// 装一次双向通道回调：原生 `patchProgress` → [UpdateService._patchProgress]。
  static void _ensureProgressHandler() {
    if (_progressHandlerInstalled) return;
    _progressHandlerInstalled = true;
    // setMethodCallHandler 返回 void（不是 Future），直接装即可。
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'patchProgress') return null;
      final args = call.arguments;
      if (args is Map) {
        final done = (args['done'] as num?)?.toInt() ?? 0;
        final total = (args['total'] as num?)?.toInt() ?? 0;
        _patchProgress?.call(done, total);
      }
      return null;
    });
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
  ///
  /// [suffix] 是期望扩展名：完整包 `apk`，差分补丁 `patch`。
  static String _safeFileName(
    String raw, {
    required String fallbackVersion,
    String suffix = 'apk',
  }) {
    var name = raw.trim();
    final slash = name.lastIndexOf(RegExp(r'[/\\]'));
    if (slash >= 0) name = name.substring(slash + 1);
    name = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (name.isEmpty || !name.toLowerCase().endsWith('.$suffix')) {
      name = 'keepsake-$fallbackVersion.$suffix';
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
