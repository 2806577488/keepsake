# 更新链路「下载 / 校验慢」定位与修复（2026-11-26）

现象：0.4.29/0.4.30 → 0.4.31 的更新，检查要转一会儿，下载 31MB 常常要几分钟，
而且**进度到 100% 之后还会停住几秒**（那一段就是「校验」）。

结论：链路本身没错，慢在四处**串行**和一处**没有后备源**。下面每条都带实测数据
（2026-11-26，Windows 机器直连 GitHub + 镜像各测三轮）。

## 1. 实测

> **测量环境**：开发机开着 Clash（Mihomo TUN，出口 13.250.46.111）。也就是说下面
> 所有数字都是**走代理**的结果，国内用户直连只会更差，不会更好；两个镜像前缀也
> 是在这条链路上验证可用性，不代表用户端速度。
> 另外同一地址两次测出 91KB/s 和 1.6MB/s，是代理换了节点 —— 这恰好说明
> 「没有后备源、只认一个地址」有多脆。

| 请求 | 结果 |
| --- | --- |
| `GET api.github.com/.../releases/latest` | **HTTP 403**（`13.250.46.111` 匿名限流），ttfb 0.17–0.74s |
| 同上走 `gh-proxy.com` | HTTP 200，ttfb 0.75s |
| `GET .../keepsake-0.4.31-arm64.apk.sha256`（92 字节） | **ttfb 3.17s** |
| 同一文件走 `gh-proxy.com` | ttfb 0.49s |
| `GET .../keepsake-0.4.31-arm64.apk`（31.2MB）直连 | 91KB/s ~ 1.6MB/s（随节点抖动；慢的一轮 34s 才下 3MB） |
| 同上走 `gh-proxy.com` | 130KB/s ~ 1.1MB/s |
| 同上走 `ghfast.top` | 506KB/s |
| 同上走 `ghproxy.net` | TLS 直接失败（**不能**当兜底源） |
| 本地 SHA256 一个 31.2MB 的 APK | 620ms（桌面；手机上通常 1.5–2.5s） |

差分补丁是现成的：`keepsake-0.4.30-to-0.4.31-arm64.patch` 只有 **1.25MB**
（= 完整包的 1/25），`-patches.json` 里 `from_sha256` 齐全。

## 2. 根因

1. **资产没有镜像兜底。** `releaseApiUrls` 有 `gh-proxy.com`，但
   `browser_download_url` 是直连 github.com → 302 → objects.githubusercontent.com。
   国内直连这一段经常几十 KB/s，31MB 就是 5 分钟起；代理节点抖起来也一样。
   **这是下载慢的主因。**
2. **校验文件串行在下载之后。** `.sha256` 只有 90 字节，却要走完整重定向链
   （实测 3.17s），而且用的是 20s 的下载超时：真拉不到就静默跳过校验，白等。
   **这是「100% 之后卡几秒」的主因。**
3. **每一步都新建 `http.Client`。** check → patches.json → .sha256 → APK 四跳
   四次 DNS + TCP + TLS（单跳 TLS ≈ 0.2s，跨主机重定向还要再来一次）。
4. **慢源不会自己让路。** 只有「总超时」，一个 100KB/s 的源能拖着用户等满全程，
   中途慢下来也不会换。
5. **检查阶段多算一次 31MB 的哈希。** `check()` 为了筛差分补丁，会先算本机已安装
   APK 的 sha256（读满 31MB），而原生 `applyPatch` **本来就会再校验一次**
   `from_sha256`，等于同一件事做了两遍。
6. **进度回调每 8KB 一次。** 31MB ≈ 4000 次回调，每次都改 ValueNotifier、
   重建进度条与文案，CPU 被拖着，滚动手感也差。

## 3. 改动（`lib/core/update/update_service.dart` + `BsPatch.kt`）

| 改动 | 位置 | 解决 |
| --- | --- | --- |
| 资产候选源：上次跑通的源 → 直连 → `gh-proxy.com` / `ghfast.top` | `assetMirrorPrefixes` / `_assetCandidates` | 根因 1 |
| 首字节 6s / 断流 8s / 跑够 10s 仍低于 200KB/s 就换源 | `firstByteTimeout` / `stallTimeout` / `slowGrace` / `minBytesPerSecond` | 根因 4 |
| 「所有源都只是慢」时放宽限速再试直连一次（不让慢网用户更新不了） | `_SourceFailure.slow` + `_streamToFile` | 根因 4 的反面 |
| 记住上次成功的源，第二次更新直接走快的 | `_preferredAssetPrefix` | 根因 1 |
| `.sha256` 与下载**并行**发车，下载完只剩本地哈希 | `download()` | 根因 2 |
| 小文件单独 8s 超时，且同样走镜像 | `metaTimeout` / `_fetchChecksum` | 根因 2 |
| 全进程复用 `http.Client`（连接池） | `_shared` | 根因 3 |
| check 记住上次成功的接口，下次先试它 | `_lastGoodEndpoint` | 根因 3 |
| 接口超时 20s → 12s（两个源串行最坏 40s → 24s） | `defaultTimeout` | 根因 3 |
| 本机 APK 哈希与 patches.json **并行** | `_attachPatchState` | 根因 5 |
| 进度回调节流到 120ms 一次，并在结尾补一次 100% | `progressInterval` / `_streamFrom` | 根因 6 |
| 校验阶段给 UI 文案「正在校验安装包…」 | `download()` 的 `onStage` | 体感 |
| 原生哈希 64KB 堆数组 → 1MB direct `ByteBuffer` + `FileChannel` | `BsPatch.sha256` | 根因 2 的尾巴 |

## 4. 预期

| 场景 | 改前 | 改后 |
| --- | --- | --- |
| 检查更新（官方源 403） | 0.74s + patches.json + 31MB 哈希 | 记住镜像源，哈希与元数据并行 |
| 下载 31MB（大陆直连几十 KB/s） | 5 分钟+ 且不会换源 | 6s 没首字节 / 10s 太慢就换镜像 |
| 进度 100% → 安装器弹出 | +3.2s（串行拉 .sha256）+ 本地哈希 | 只剩本地哈希（并发已吃掉 3.2s） |
| 下载期间的 UI 重建 | ≈4000 次 | ≈下载秒数 × 8 |
| 能走差分时 | 1.25MB | 1.25MB（不变，但失败才回退全量） |

## 5. 怎么验证

```bash
# 真机上更新一次，看这几行：
adb logcat -s flutter:V | findstr /c:"资产源不可用" /c:"差分补丁" /c:"跳过校验"
```

- 正常情况下**不该**出现「资产源不可用」；出现就说明该源确实不可用，换了下一个。
- 应该看到「差分补丁：候选 2 个，选中 keepsake-0.4.30-to-0.4.31-arm64.patch」。
- 不该再看到「没有可用的 sha256 校验值，跳过安装包校验」（那说明校验附件两次都没拉到）。

## 6. 没做的事（以及为什么）

- **不并发抢首包**：多个候选同时发请求能让首字节更快，但代码复杂度大增（要暂停/
  取消多个流），收益只有几百毫秒，先不做。
- **不给 `.patch` 单独做断点续传**：补丁 1.25MB，换源重下比续传逻辑便宜。
- **没有引入纯 Dart SHA256**：会上新依赖，而且原生哈希走 ARMv8 SHA256 指令，
  Dart 侧不会更快。
