# Keepsake 国内 ROM × Android 版本兼容性审计（2026-11-22）

- 审计对象：`Z:\dsh-restore\keepsake`（Flutter，`applicationId = app.keepsake.chat`，minSdk 24 / targetSdk 36，version 0.4.16+4160）
- 审计方式：只读代码 + 合并后 manifest + 已构建 APK 实测（未改任何代码）
- 输出文件（本次唯一写入）：`docs/compat-audit-2026-11-22.md`

## 一、结论摘要（最重要的 5 条）

1. **图库通道的 `resolveActivity` 预检是最可能的"华为打不开图库"元凶**（高）。`MainActivity.pickImages()` 先用 `resolveActivity()` 判断有没有选择器，但 `AndroidManifest.xml` 的 `<queries>` 里只声明了 `GET_CONTENT / OPEN_DOCUMENT / PROCESS_TEXT`，**没有 `ACTION_PICK_IMAGES` 和 `ACTION_PICK`**。targetSdk 36 处于 Android 11+ 包可见性过滤之下，`resolveActivity` 可以返回 `null`，于是代码直接落到 `NO_GALLERY`（"这台设备没有可用的图库选择器"）——恰好就是当初为了华为才写这条通道的场景。修法小到只加两段 `<queries>` + 把预检降级为"尝试启动 + 捕获 `ActivityNotFoundException`"。
2. **华为/荣耀（无 AOSP Photo Picker）只能单选**（高）。`ACTION_PICK_IMAGES` 分支给了 `EXTRA_PICK_IMAGES_MAX = 9`，但回退的 `ACTION_PICK` 只有单张语义，多选能力在这些机型上凭空消失，且代码没有 `EXTRA_ALLOW_MULTIPLE`。
3. **应用内更新在国内网络 + 厂商安全策略下大概率走不完**（高）。检查更新直连 `https://api.github.com`（DNS 污染频发），安装环节撞华为纯净模式「增强防护」、MIUI/HyperOS 安装验证、ColorOS/vivo 安全检测，而 `installApk` 只负责拉起系统安装器，**没有任何"被拦住了怎么办"的提示**。
4. **只出 arm64 包，32 位机根不上**（高）。CI 固定 `--target-platform android-arm64`；本地联合 APK 的 `armeabi-v7a` 目录里只有 `libdartjni.so` / `libdatastore_shared_counter.so`，**缺 `libflutter.so` / `libapp.so` / `libsqlite3.so`** → 32 位设备即使装上也会启动即崩。目标区间"Android 8–16"里的低端老机（Redmi 7A/9A、老畅享）大多正是 32 位。
5. **后台任务没有前台服务 / 通知 / 唤醒锁**（中，但影响观感最大）。导入、补建角色卡都跑在主 isolate 的普通 `Future` 里，`AndroidManifest.xml` 里没有 `FOREGROUND_SERVICE`、`WAKE_LOCK`、`POST_NOTIFICATIONS`。华为省电、小米神隐、ColorOS/vivo 后台冻结会让任务暂停或被杀；好在设计上可续跑（`resumePending`），**不丢数据，但会"停在那里没人知道"**。

顺带一条好消息：APK 里所有 `.so` 的 `PT_LOAD p_align` 都是 16384 或 65536，**Android 15 的 16 KB page size 这一关已经过了**，不用改。

## 二、逐项审计

### 1. 图库 / 相机

现状：`GalleryPicker.pickImages()`（`lib/core/chat/gallery_picker.dart:22-27`）→ `keepsake/gallery` → `MainActivity.pickImages()`（`MainActivity.kt:94-122`）→ 优先 `ACTION_PICK_IMAGES`（`108`），`resolveActivity` 为 `null` 则回退 `ACTION_PICK`（`114`），都不行报 `NO_GALLERY`（`121`）。相机走 `image_picker`（`lib/features/chat/chat_screen.dart:433-448`）。

各 ROM 已知行为：

- **华为 / 荣耀（EMUI 9–13、HarmonyOS 2/3/4.x）**：没有 AOSP Photo Picker（Android 13 的 `ACTION_PICK_IMAGES` 是 Google 的 MediaProvider 模块能力，无 GMS 的华为不提供）。这条通道因此 100% 走 `ACTION_PICK` 回退。而 `ACTION_PICK` 在华为系上是"厂商图库 + 单张"语义，`ACTION_GET_CONTENT` 在华为反而会打开"图库"选择器（不像 AOSP 那样直落文件管理器）。所以最好的回退顺序是 `PICK_IMAGES → GET_CONTENT(multiple) → PICK`。
- **Android 11+ 包可见性**：这是本项目最容易被忽略的坑。Android 11 起 `queryIntentActivities` / `resolveActivity` 只返回"可见"的应用，未在 `<queries>` 声明的 intent 一律查不到；大量案例是"明明有应用却返回 null"（[案例 1](https://www.volcengine.com/article/3274244)、[案例 2](https://www.volcengine.com/article/3079054)、[案例 3](https://www.volcengine.com/article/2210793)）。当前 manifest 声明了 `GET_CONTENT`（`AndroidManifest.xml:20-22`，给 `file_picker` 用）**却没声明 `PICK_IMAGES` / `PICK`** —— 说明写这份 manifest 时知道 queries 这回事，只是漏了图库这两条，症状正好只出现在图库通道上。
- **鸿蒙 NEXT（HarmonyOS 5.x，Mate 70 起默认）**：**不兼容 Android APK**，`MediaStore.ACTION_PICK_IMAGES` 之类 AOSP Intent 完全不存在（[华为开发者问答](https://developer.huawei.com/consumer/cn/forum/topic/0202182617413976016)、[讨论](https://bbs.itying.com/topic/68f9462c89629100479db4be)）。这是"应用整体不可用"，不是本条通道的问题，见风险表 L4。
- **小米 / Redmi（MIUI 12–14、HyperOS）**：MIUI 图库同时注册 `ACTION_PICK` 与 `ACTION_GET_CONTENT`，两者都能进图库；`PICK_IMAGES` 在 HyperOS（Android 14/15）上由小米自己的 MediaProvider 实现，可用。风险主要在权限（见 §4）与"隐私保护"里的"图片和视频"拦截。
- **OPPO/一加/realme（ColorOS）**：ColorOS 14/15 图库对 `ACTION_PICK` 支持正常；个别版本 `ACTION_GET_CONTENT` 会跳"文件管理 > 图片"。多选在 `EXTRA_ALLOW_MULTIPLE` 下可用。
- **vivo/iQOO（OriginOS）**：与 ColorOS 类似，`ACTION_PICK` 可用；部分 OriginOS 版本对 `EXTRA_ALLOW_MULTIPLE` 只返回第一张（所以多选结果要按 `clipData` 为空兜底，代码 `MainActivity.kt:58-66` 已这么做，属于正确写法）。
- **三星国行**：三者都正常，`PICK_IMAGES` 可用（Android 13+ 官方实现）。

其他代码级问题：

- `copyToCache`（`MainActivity.kt:135-149`）整段一个 `try`：`queryDisplayName` 抛异常（华为/部分 provider 上 `OpenableColumns` 查询会抛 `SecurityException`）或 `openInputStream` 返回 `null` 时，要么图片被静默丢弃，要么返回一个**不存在的路径**。后者会让 Dart 侧 `_addXFile` 里的 `file.length()` 抛异常，而 `_pickImages`（`chat_screen.dart:455-464`）**只 catch `PlatformException`** → 变成未处理异常。
- 文件名直接取 `DISPLAY_NAME` 且"同名覆盖"（`MainActivity.kt:137-143`）：多选两张都叫 `IMG_2024.jpg` 时后一张覆盖前一张；未过滤 `/`、`..`、超长名。
- 选图期间进程被杀（低内存、系统回收）：`pendingGalleryResult` 丢失，Dart 侧 `await` 永不返回，用户回到 App 后**没有任何反馈**（没有 loading 态，也没有超时）。

### 2. 安装 APK（应用内更新）

现状：`installApk`（`MainActivity.kt:188-223`）→ `FileProvider.getUriForFile(this, "$packageName.fileprovider", apk)`（`209`）→ `ACTION_VIEW` + `application/vnd.android.package-archive` + `FLAG_GRANT_READ_URI_PERMISSION`（`210-214`）。`authorities = app.keepsake.chat.fileprovider`（`AndroidManifest.xml:52`）与代码一致 ✅。`res/xml/file_paths.xml:10-15` 覆盖 `external-files-path updates/`、`external-path updates/`、`cache-path /`，与 `update_service.dart:404-418` 的落盘位置（`getExternalStorageDirectory()/updates/`，回退 `getTemporaryDirectory()/updates/`）对得上 ✅。

各 ROM 已知行为（都会"拦"，本项目目前零应对）：

- **华为 / 荣耀**：`HarmonyOS 3.0 起纯净模式默认开启且不可关闭`，其「增强防护」只允许安装通过华为应用市场安全检测的应用；要装第三方 APK 必须手动关掉「设置 > 系统和更新 > 纯净模式 > 增强防护」，或在拦截弹窗里走「安全安装」（人脸/指纹二次验证）([华为开发者问答](https://developer.huawei.com/consumer/cn/forum/topic/0207228430442717398?fid=24)、[FAQ](https://github.com/alipymanbu/Android/blob/master/%e5%ae%98%e7%bd%91%e7%89%88APP%e4%b8%8b%e8%bd%bd/remyapp/%e5%b8%b8%e8%a7%81%e9%97%ae%e9%a2%98%e6%8e%92%e6%9f%a5.md)、[讨论](https://www.pconline.com.cn/ask/171843.html))。用户看到的是一句"此应用来源不可信"，跟我们 App 无任何关联提示。
- **小米 MIUI / HyperOS**：三层拦截——应用级「安装未知应用」开关、手机管家「安装应用时自动扫描/联网校验」、以及「纯净模式」（部分版本叫"安全模式"）；同类拦截还有"风险应用"要求登录小米账号 ([资料 1](https://www.pconline.com.cn/ask/188751.html)、[资料 2](https://www.pconline.com.cn/ask/337620.html))。**离线（断网）安装可降级为本地基础校验**，是个可写进文案的兜底办法。
- **OPPO / vivo**：「安装未知来源应用」授权后仍会弹"安全检测/风险提示"，需要勾选"已了解风险"继续；部分机型默认禁止安装来自"浏览器/文件管理"的包，但 `REQUEST_INSTALL_PACKAGES` + 系统安装器通常可过。
- **三星国行**：相对宽松，`ACTION_MANAGE_UNKNOWN_APP_SOURCES` 跳转正常。

代码级问题：

- 全程只有 `ACTION_VIEW`，没有 `Intent.createChooser` / 没有 `setPackage("com.android.packageinstaller")` 之类的定向；部分 ROM 会弹出"用哪个应用打开"而不是直接进安装器。
- 安装失败（签名不一致 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`、被安全策略拦）时系统只给一句通用错误，**App 侧拿不到也解释不了**。注意 `android/app/build.gradle.kts` 在没有 `key.properties` 时会回退 debug 签名（CI 同理），签名换了就必然覆盖安装失败。
- GitHub Releases 资产只有 `keepsake-<ver>-arm64.apk` 与 `.sha256`；`update_service.dart` 挑了 APK 但**从不校验 sha256**（`_pickApk` 只挑名字，`update_service.dart:363-402`）。国内网络下拿到半截/被劫持的包没有任何防线。

### 3. 后台与自启动

现状：导入任务 `ImportTask`（`lib/core/import/import_task.dart`）是纯 Dart 异步；`resumePending()`（`import_task.dart:247`）在会话列表启动时静默续跑（`sessions_screen.dart:68-72`）；补建角色卡 `CardBackfillTask`（`lib/core/characters/card_backfill_task.dart`）同样是普通 `Future`。**合并后的 manifest 里没有 `FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_DATA_SYNC`、`WAKE_LOCK`，也没有任何 `<service>`**；全项目 `grep Notification` 零命中 —— 也没有 `POST_NOTIFICATIONS`。

各 ROM 已知行为：

- **华为 EMUI/HarmonyOS**：默认"应用启动管理"为自动管理，锁屏后一段时间会清理；「省电模式」+「休眠时保持网络连接」关闭时后台进程基本休眠。
- **小米 MIUI/HyperOS**：「神隐模式」（省电策略）默认标准，长时间后台冻结；还要单独允许"自启动"。
- **OPPO/一加（ColorOS）**、**vivo/iQOO（OriginOS）**：后台冻结 + Doze 限网 + 广播限流，最近任务里划掉即杀。社区实测 ColorOS/HyperOS 上无前台服务的后台任务存活优先级最低（[实测记录](https://atomgit.com/GitCode/madongsiji/issues/45)、[ColorOS 后台机制](https://modules.lsposed.org/module/io.github.yukino1111.colorosbgmanager/)、[ColorOS 耗电管理设置](https://github.com/natfrp/wiki/blob/a1227cd29c0af6d4ba2211b1aa79973b45f74e45/launcher/android-bgtask.md)）。

结论：**数据安全没问题（可续跑），体验有问题**——用户切走 3 分钟回来发现进度条不动、没有任何提示，也不知道"再打开一次会接着跑"。

### 4. 权限模型

- `READ_MEDIA_IMAGES`（`AndroidManifest.xml:8`）**声明了但全项目从不运行时申请**；`READ_MEDIA_VISUAL_USER_SELECTED`、`POST_NOTIFICATIONS` 均未声明。
- 图库通道本身**不需要**读媒体权限（`PICK_IMAGES` / `PICK` 返回的是带授权的 `content://`，`copyToCache` 立即读走），所以现状能跑；但这条多余的声明会在部分 ROM 的"隐私"页显示一个"照片"权限项，用户可能以为我们偷偷读相册。
- Android 14 的"部分照片访问"（`READ_MEDIA_VISUAL_USER_SELECTED`）一旦将来需要直接查 MediaStore（比如做一个自带相册网格），不声明就会**只看到用户选过的那几张**，且三条权限必须一起请求（[官方文档](https://developer.android.google.cn/about/versions/14/changes/partial-photo-video-access)）。
- `permission_handler 11.4.0` 固定版本（`pubspec.yaml:72`，`permission_handler_android 12.1.0`）：Android 13/14 上没有崩溃类问题，但**MIUI 上"拒绝一次"常被报成 `denied` 而非 `permanentlyDenied`**，用户点了还会再弹；反之部分 ColorOS 版本首次拒绝即 `permanentlyDenied`。当前代码只区分"granted / 其它"（`chat_screen.dart:434-438`），两种情况都提示"去系统设置允许"，没有"打开设置"按钮（`permission_handler` 的 `openAppSettings()` 没用上）。
- 录音：`record` 插件自己申请 `RECORD_AUDIO`（`lib/core/voice/recorder.dart:193-210`），失败映射到 `VoiceError.noMicrophonePermission` ✅。华为 HarmonyOS 2/3 上录音权限属于"敏感权限"，首次申请必弹系统框，无特殊坑。

### 5. 分享 / 导出

- 出口 ①`FilePicker.saveFile(bytes:)`（`sessions_screen.dart:480-500`）走 SAF `ACTION_CREATE_DOCUMENT`；`queries` 里已声明 `CREATE_DOCUMENT`（`AndroidManifest.xml:43-47`）✅。各家 DocumentsUI 都在，风险集中在默认目录与"另存为文件名编码"。
- 出口 ②`SharePlus.instance.share`（`sessions_screen.dart:503-516`）走系统分享。**微信不接收 `application/zip`**，所以国内用户最常见的动作（"发我微信"）在分享面板里要么没有微信，要么选了失败。`share_plus` 的 Android 实现（`ShareFileProvider`，合并 manifest 里已注入）在华为/HarmonyOS 4.x 上正常；**纯鸿蒙 NEXT 上没有官方实现**，需要厂商侧 ShareKit 桥接（[华为社区文章](https://developer.huawei.com/consumer/cn/blog/topic/03218245255812334)）。
- 掉到 `_uriLabel`（`sessions_screen.dart:519-534`）时，`content://` 只做 `decodeComponent`，toast 里可能出现一长串 URI 路径而不是"下载/Keepsake"。

### 6. 界面 / 显示

- **字体缩放**：全项目无 `MediaQuery.textScaler` / `clamp` 处理（grep 零命中）。风险点集中在固定高度容器：输入区语音条 `height: 44`（`chat_screen.dart:2763-2779`）、操作行 `tightFor(width:44,height:44)`（`1622-1625`）、语音键 `2484`/`2566`。1.3× 尚可，1.5× 时这些 44dp 容器里的文字/图标有 `RenderFlex overflow` 风险。AppBar 标题是两行 `Column`（`1032-1050`），1.5× 下 56dp 工具条也会挤。
- **深色模式**：跟随系统 + 手动三选（`settings.dart:99`、`settings_screen.dart:280-305`），主题全由 `ColorScheme.fromSeed` 派生（`core/theme.dart:70-120`），没有硬编码色值 → 各家"深色模式"下不会出现白底白字。**这块是本项目做得最好的一环。**
- **挖孔/刘海**：`SafeArea` 用在 5 处页面主体 + 各底部弹窗（`chat_screen.dart:795/1986/2730`、`sessions_screen.dart:705`、`settings_screen.dart:360`），但**没有一处读 `MediaQuery.padding` 做侧边避让**，横屏时刘海侧边可能压住气泡。
- **窄屏 360dp**：气泡 `maxWidth = 86%`（`chat_screen.dart:1597-1603`），附件用 `Wrap`（`2080`、`2636`）→ 不会横向溢出 ✅。
- **大屏/折叠屏**：**没有任何最大宽度约束**。Mate X / Find N 展开态 ~700–800dp 时，气泡能拉到 600dp+，一行字数远超舒适阅读宽度（中文建议 ≤ 40 字/行）。

### 7. 输入 / 键盘

- `windowSoftInputMode="adjustResize"`（`AndroidManifest.xml:38`）+ `Scaffold` 未关 `resizeToAvoidBottomInset`（`chat_screen.dart:1029`）→ 常规路径正确 ✅；底部弹窗自己补了 `viewInsets`（`chat_screen.dart:1294`），是对的写法。
- **targetSdk 36 → Android 15 起强制 edge-to-edge**，`adjustResize` 不再自动缩放窗口（[StackOverflow](https://stackoverflow.com/posts/79364446/revisions)、[说明](https://www.volcengine.com/article/1076175)）。Flutter 3.27+ 走 `WindowInsets` 自行处理，本项目 Flutter 3.50 理论上没问题，**但必须在 Android 15/16 真机上验一次"输入框是否被键盘顶住"**，这是最典型的"代码看起来对、真机就是错"的场景。
- 华为自带输入法、搜狗/百度：风险点是"全屏输入"模式（搜狗"全屏输入"会把键盘高度报到很小）+ 悬浮键盘（`viewInsets` 为 0），两种情况下 Flutter 的 `adjustResize` 都拿不到正确高度，输入框会被盖住。第三方输入法在 Flutter 上还有"首次弹出后高度不刷新"的历史问题（切键盘要重新聚焦才对齐）。

### 8. 网络

- 只允许 HTTPS（`usesCleartextTraffic="false"`，`AndroidManifest.xml:29`），且 `normalizeProviderBase` 会**自动把 `http://` 改写成 `https://`**（`lib/core/api/provider_models.dart:275-293`）→ 国内常见的自建 http 中转、内网地址直接 TLS 失败，用户只会看到"网络错误"。
- **无 GMS 不影响本 App**：全项目没有 Firebase/GMS 依赖；合并 manifest 里唯一的 GMS 痕迹是 `image_picker` 注入的 `ModuleDependencies` 服务，且 `android:enabled="false"`（`merged_manifest:113-125`）→ 华为/荣耀上不会找 GMS ✅。
- **Dart `http` 不读系统 HTTP 代理**：Clash/Quantumult 这类"VPN 模式"（tun）可用；"HTTP 代理模式"下请求不走代理 → 国内用户翻墙习惯差异会变成"只有这个 App 连不上"。
- **检查更新直连 `api.github.com`**（`update_service.dart:110-118`）：大陆网络下该域名 DNS 污染/间歇不可达是常态（[社区 hosts 项目](https://github.com/ittuann/github-ip-hosts)）。20s 超时后会 toast「检查更新失败：请求超时」，用户无从判断是网络问题还是真的没更新。
- **WebView（mermaid）**：`WebViewWidget` 渲染 mermaid（`lib/features/chat/widgets/mermaid_block.dart:297-353`）。华为有系统 WebView（ArkWeb 兼容层），**无 GMS 不影响**；旧版 WebView（未更新的 Android 8 老机，Chrome 60 以下）跑不动 mermaid 的 ES2020 语法 → 渲染失败，但**已优雅降级为代码块 + 错误文案**（`mermaid_block.dart:240-274`）✅。真正的风险是 3.3MB `mermaid.min.js` 在 Redmi 9A 这类低端机上首次渲染卡顿/接近 25s 超时。

### 9. 存储

- SQLite 用 `drift` + `sqlite3_flutter_libs`（`pubspec.yaml:25-29`），库在 app 私有目录 → 华为/小米的存储隔离（分区存储）**不影响** ✅。
- 实测 `build/app/outputs/flutter-apk/app-release.apk` 内 9 个 `.so`，`arm64-v8a` 的 `libsqlite3.so` / `libdartjni.so` / `libdatastore_shared_counter.so` 全部 `p_align = 16384`，`libapp.so` / `libflutter.so` 为 65536 → **16 KB page size 兼容** ✅。
- `sqlite3_flutter_libs` 版本是 `0.6.0+eol`（`pubspec.lock:1181-1188`）——pub 上的 EOL 标记版，功能可用但不再修 bug；`sqlite3` 3.9.1 的 native 库随包走，风险主要在"未来 Android 16 收紧"（见风险表 L5）。
- 导出路径：只走 SAF（`saveFile`）与应用私有目录，**不写 `/sdcard/Download`**，因此不需要 `MANAGE_EXTERNAL_STORAGE`，也不撞华为/小米的"下载目录写入"限制 ✅。

## 三、风险清单

等级：高 = 会让核心功能在目标机型上不可用；中 = 能用但会出错/体验差/需用户自救；低 = 边角或未来风险。
状态：未修 / 部分 / 已处理 / 需真机验证。

| # | 风险项 | 等级 | 涉及文件:行 | 触发机型/版本 | 修法 | 状态 |
|---|---|---|---|---|---|---|
| H1 | `resolveActivity` 预检被包可见性过滤 → 误报"没有图库" | 高 | `MainActivity.kt:102-121`；`AndroidManifest.xml:14-23` | 华为/荣耀（无 Photo Picker）+ 所有 Android 11+ | `<queries>` 补 `android.media.action.PICK_IMAGES`、`android.intent.action.PICK`（`image/*`）、`android.intent.action.GET_CONTENT`（`image/*`）；同时把 `resolveActivity` 从门禁改成提示，直接 `startActivityForResult` 并 catch `ActivityNotFoundException` 逐级回退 | 未修 |
| H2 | 华为回退只有单选，多选能力丢失 | 高 | `MainActivity.kt:113-118` | 华为/荣耀 EMUI 9–13、HarmonyOS 2–4.x | 回退链改成 `PICK_IMAGES → GET_CONTENT(+EXTRA_ALLOW_MULTIPLE) → PICK(+EXTRA_ALLOW_MULTIPLE)`；`ACTION_PICK` 也带上 `EXTRA_ALLOW_MULTIPLE`，靠 `clipData` 判多选（`MainActivity.kt:58-66` 已支持） | 未修 |
| H3 | 更新检查直连 `api.github.com`，国内不可达 | 高 | `lib/core/update/update_service.dart:110-118` | 大陆网络（全部机型） | 多源：GitHub API → 自有域名/镜像（jsDelivr 之类）→ 失败时给"手动下载"URL；超时文案区分"网络"与"无更新"；顺带校验 Release 里的 `.sha256` | 未修 |
| H4 | 安装被厂商安全策略拦截，App 无任何引导 | 高 | `MainActivity.kt:188-223`；`AndroidManifest.xml:11` | 华为纯净模式（HarmonyOS 3+ 默认）、MIUI/HyperOS 安装校验、ColorOS/vivo 安全检测 | 安装前说明 + 失败兜底：①提示"若被拦，去 设置 > 系统和更新 > 纯净模式 关闭增强防护"；②小米提示关"安装应用时自动扫描"；③提供"浏览器下载安装"备选；④签名不一致给出专门文案 | 未修 |
| H5 | 只构建 arm64，32 位机装不上/启动崩 | 高 | `.github/workflows/release.yml`（`--target-platform android-arm64`）；`update_service.dart:363-402` | Redmi 7A/9A、老畅享等 32 位 Android 8–10 机 | 出 arm64 + armeabi-v7a 两个包（或 `--split-per-abi`），Release 同时上传；`_pickApk` 已能按名字挑，只需按 `Build.SUPPORTED_ABIS` 传偏好 | 未修 |
| M1 | 后台导入/补建无前台服务、无通知、无唤醒锁 | 中 | `AndroidManifest.xml`（无 `FOREGROUND_SERVICE`/`WAKE_LOCK`/`POST_NOTIFICATIONS`）；`import_task.dart:247`；`sessions_screen.dart:68-72` | 华为省电、MIUI 神隐、ColorOS/vivo 冻结 | Android 14 起用 `ForegroundService(dataSync)` + 常驻通知显示进度；做不到就加 `wakelock_plus` 并在 UI 明示"切后台可能暂停，回到 App 会自动续跑" | 未修 |
| M2 | 取图缓存一把 catch：查询异常/流为 null 时静默丢图或返回坏路径 | 中 | `MainActivity.kt:134-165`；`chat_screen.dart:455-464` | 华为系图库、部分 provider | `queryDisplayName` 单独 try、失败回落默认名；`openInputStream` 为 null 视为失败不入列表；Dart 侧 `_pickImages` 除 `PlatformException` 外再 catch 通用异常 | 未修 |
| M3 | 用 `DISPLAY_NAME` 当文件名：同名覆盖、未过滤 `..`/超长 | 中 | `MainActivity.kt:135-145` | 多选同源图（连拍/多文件夹） | 加时间戳/UUID 前缀，过滤路径分隔符，长度截断 | 未修 |
| M4 | 相机权限被拒只 toast，无"去设置"入口 | 中 | `chat_screen.dart:433-448` | MIUI/ColorOS（二次拒绝即永久拒绝） | 区分 `permanentlyDenied`，弹"打开设置"按钮（`openAppSettings()`）；相机返回 null 时提示换用相册 | 未修 |
| M5 | 1.3×/1.5× 字体缩放下固定 44dp 容器与双行 AppBar 溢出 | 中 | `chat_screen.dart:1032-1050`、`2763-2779`、`1622-1625`、`2484`、`2566` | 开启"大字体/超大字体"的所有机型（华为/小米老年模式常见） | 关键容器改 `IntrinsicHeight`/`minHeight`，AppBar 双行改单行 + 副标题；对 `textScaler` 设上限（如 1.3）或改用可滚动的紧凑布局 | 需真机验证 |
| M6 | 大屏/折叠屏无最大阅读宽度 | 中 | `chat_screen.dart:1597-1603` | Mate X/Find N/平板展开态 | 气泡加 `min(86% 屏宽, 520dp)`；列表整体居中限宽 | 未修 |
| M7 | 分享 ZIP 到微信失败（微信不收 `application/zip`） | 中 | `sessions_screen.dart:503-516` | 国内全部机型（微信为主） | 默认出口改为"保存到手机"，分享前置提示"微信不支持压缩包，可用文件管理器发送"；或改分享单文件/文本 | 未修 |
| M8 | 自填 `http://` baseUrl 被强改 https；Dart 不读系统 HTTP 代理 | 中 | `lib/core/api/provider_models.dart:275-293` | 用中转/内网/HTTP 代理的用户 | 显式提示"只支持 HTTPS"，或允许 `usesCleartextTraffic` 白名单 + 网络诊断页显示实际请求 URL | 未修 |
| M9 | `READ_MEDIA_IMAGES` 声明了却从不申请；未声明 `READ_MEDIA_VISUAL_USER_SELECTED` | 中 | `AndroidManifest.xml:8-9` | Android 13/14+（全部） | 既然用不到就删掉 `READ_MEDIA_IMAGES`；将来要读相册则三条权限一起申请并处理部分授权 | 未修 |
| M10 | 选图期间进程被杀 → 通道永不返回 | 中 | `MainActivity.kt:36-39`、`94-99`；`gallery_picker.dart:22-27` | 低内存机、系统回收 | Dart 侧加超时（如 90s）+ 回来时提示"上次选图已中断"；或用 `ActivityResultLauncher` 风格的可恢复请求 ID | 未修 |
| M11 | mermaid 首渲染在低端机上卡顿/超时 | 中 | `lib/features/chat/widgets/mermaid_block.dart:297-353`（25s 超时） | Redmi 9A/华为畅享等低端机、旧 WebView | 保留现有降级；加"仅在前台且非低端设备才自动渲染"，长图默认点开再渲染 | 部分（已有降级） |
| M12 | SAF 另存为在华为/小米 DocumentsUI 的差异；`_uriLabel` 显示原始路径 | 中 | `sessions_screen.dart:480-500`、`519-534` | 华为/小米/ColorOS | 成功文案改成固定"已保存到你选择的位置"，不回显 URI；华为上验证默认目录是否为"最近" | 需真机验证 |
| L1 | 缺 `uses-feature camera/mic required=false` | 低 | `AndroidManifest.xml:7,5` | 无摄像头平板/电子墨水设备（应用商店过滤） | 补两条 `<uses-feature ... required="false"/>` | 未修 |
| L2 | `allowBackup` 默认 true，换机/云备份可能只恢复 DB 不恢复附件 | 低 | `AndroidManifest.xml:25-29` | 华为/小米换机助手 | 显式 `android:allowBackup="false"`，或自己做完整导出 | 未修 |
| L3 | 无 `POST_NOTIFICATIONS`、无 `enableOnBackInvokedCallback` | 低 | `AndroidManifest.xml` | Android 13+ 全面屏手势机 | 加通知权限（配合 M1）；开预测性返回 | 未修 |
| L4 | 鸿蒙 NEXT（HarmonyOS 5.x）不兼容 APK | 低（战略级） | 整个 App | Mate 70 / 升级到 5.x 的机型 | 无法用 APK 解决；需 Web 版或元服务，至少在下载页标注"仅支持 HarmonyOS 4.x 及以下" | 需真机验证 |
| L5 | `sqlite3_flutter_libs 0.6.0+eol` 已 EOL | 低 | `pubspec.yaml:28` | 未来 Android 16 收紧 | 关注 drift 官方推荐的替代（native assets 版 sqlite3），升级前先跑 DB 迁移回归 | 需评估 |
| L6 | 横屏 + 键盘 + 大字体组合未覆盖 | 低 | `chat_screen.dart:1029`、`AndroidManifest.xml:36` | 全部（未锁方向） | 真机验一次横屏输入；必要时对聊天页锁竖屏或做横屏专用布局 | 需真机验证 |

统计：**高 5 条、中 12 条、低 6 条**（共 23）。

## 四、已处理（审计中确认没问题、不需要动）

1. **Photo Picker 的降级思路**：自己发 Intent 而不是依赖 `image_picker` 的 `ACTION_GET_CONTENT`，方向完全正确——这是华为场景下唯一能"进图库而不是进文件管理器"的做法。
2. **多选结果的读取**：先读 `clipData`（逐个 item），为空再读 `data`（`MainActivity.kt:58-66`），兼容单/多选与各家返回习惯 ✅。
3. **FileProvider 配置**：authority（`app.keepsake.chat.fileprovider`）与 Kotlin 侧一致；`file_paths.xml` 与 `_updateDir()` 的落盘位置一一对应，`cache-path` 兜底也在 ✅。
4. **安装前的前置检查**：文件存在/可读/`canRequestPackageInstalls()` 三道检查，错误码清晰（`FILE_MISSING`/`FILE_UNREADABLE`/`NEED_PERMISSION`）✅。
5. **64 KB/16 KB 页对齐**：实测所有 `.so` `p_align ≥ 16384`，Android 15/16 的 16 KB page size 不会崩 ✅。
6. **无 GMS 依赖**：唯一 GMS 痕迹是 `image_picker` 注入且 `enabled=false` 的光模块服务；华为/荣耀上不会因为找不到 GMS 而崩 ✅。
7. **不写公共存储**：导出只走 SAF + 私有目录，绕开了分区存储与"下载目录"限制 ✅。
8. **导入可续跑**：`ImportTask` 跳过已导入会话 + `resumePending()` 在列表启动时静默续跑（`sessions_screen.dart:68-72`）→ 后台被杀不丢数据 ✅。
9. **深色模式**：全部颜色由 `ColorScheme` 派生，无硬编码，跟随系统正确 ✅。
10. **mermaid 失败降级**：WebView 缺失/超时/JS 报错都落到代码块 + 文案，不会白屏 ✅。
11. **纯 HTTPS**：`usesCleartextTraffic="false"`，不存在明文泄漏 ✅（代价见 M8）。

## 五、无法在此环境验证，需真机

| 待验证项 | 建议机型/版本 | 验证点 |
|---|---|---|
| 图库通道能否打开厂商图库 | 华为 P30（EMUI 10/Android 10）、荣耀 Magic5（MagicOS 8/Android 14）、Redmi Note 12（HyperOS）、OPPO Reno10（ColorOS 14）、vivo X90（OriginOS 4） | 点"相册"是否直接进图库、是否单选/多选、返回后图片是否真的进了附件 |
| `<queries>` 修复前后的 `resolveActivity` 实际返回值 | 华为 + Android 11/13/14 各一台 | 在 `pickImages` 里打日志确认 null/非 null 的真实分布（这是 H1 的判定依据） |
| Android 15/16 键盘遮挡 | Pixel 8（Android 15/16）或小米 14（HyperOS 2） | 输入框弹出后是否被键盘顶住、`adjustResize` 是否还生效、返回手势与键盘的层叠 |
| 1.3× / 1.5× 大字体 | 华为"字体与显示大小"最大、小米"显示大小/字体"最大 | 输入区、气泡操作行、AppBar、设置页是否有黄黑溢出条 |
| 折叠屏/大屏 | Mate X3 展开、OPPO Find N3 展开、小米平板 6 | 气泡行长、是否有内容贴边 |
| 安装 APK 全过程 | 华为（纯净模式开启）、小米（安装扫描开启）、OPPO/vivo 各一台 | `installApk` 后系统弹什么、拦截后用户能否自己走通、签名不一致时的报错 |
| 后台导入存活 | 华为/小米/OPPO 各一台 | 导入 500 会话时切后台 3/10/30 分钟，回来进度是否继续、是否被杀 |
| WebView 渲染 mermaid | 未更新 WebView 的 Android 8 机（如红米 5 Plus） | 首渲染耗时、是否降到错误文案 |
| 微信分享 ZIP | 任意国内机 | 分享面板里是否有微信、选了之后的行为 |
| HarmonyOS 5.x | Mate 70 / 升级后的 P60 | 是否直接提示"不支持此安装包" |

## 六、建议修复顺序

1. **P0（1–2 天，决定"能不能用"）**
   - H1：`<queries>` + 把 `resolveActivity` 降级为尝试启动。这是最便宜、收益最大的一改。
   - H2：回退链加 `GET_CONTENT` + `EXTRA_ALLOW_MULTIPLE`，恢复华为多选。
2. **P1（2–3 天，决定"能不能升级"）**
   - H4：安装被拦的引导文案（三种 ROM 各一句）；H3：更新检查换源 + 失败给手动下载。
   - H5：出 armeabi-v7a 包并在 Release 里同时上传（`_pickApk` 已有挑包逻辑，改动最小）。
3. **P2（一周内，决定"用起来顺不顺"）**
   - M2 / M3（取图缓存健壮性，顺手就能修完）、M4（权限设置入口）、M1（前台服务或唤醒锁 + 明示"可续跑"）。
4. **P3（排期）**
   - M5 / M6（大字体与大屏）、M7（导出主出口改"保存"）、M8（网络诊断）、M9（权限声明清理），其余低风险项随版本带走。

> 本次审计未修改任何代码；唯一写入的是本报告。所有"修法"均为建议，落地前建议先做 P0 的两处改动再上真机验证表（§五）的第一、二行——那两行决定后面所有图库结论是否还成立。
