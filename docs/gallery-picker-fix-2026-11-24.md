# 相册（图库）问题根治：从"修 Intent"改成"自带相册 + 自带编辑"（2026-11-24）

## 一、问题

用户反馈：点「从相册选择」打开的是**文件管理器**，不是图库；已经改过好几个版本
（0.4.1x → 0.4.26 之间反复调 Intent 顺序、`resolveActivity` 预检、`<queries>`），
现象依旧。

## 二、根因（为什么"调 Intent"这条路走不通）

前几个版本的思路一直是"把 Intent 调对"：

1. `ACTION_PICK_IMAGES`（Android 13+ Photo Picker）→ 2. `ACTION_GET_CONTENT`（可多选）
→ 3. `ACTION_PICK`（老式相册）。

每次失败都在下一版里加一条回退、补一段 `<queries>`、去掉 `resolveActivity` 门禁。
但这些改动都改变不了一个事实：**隐式 Intent 的最终落点由 ROM 决定，App 说了不算。**

具体有三层原因，任何一层都足以让"点相册进文件管理器"复现：

- **`ACTION_GET_CONTENT` 是"取内容"语义，不是"看图"语义。** 图库和文件管理器都会
  注册它；国产 ROM（华为 `com.huawei.hidisk`、部分 ColorOS/OriginOS 的 FileManager）
  往往把 `image/*` 也声明成可处理。系统按"默认应用 / 上次的选择"直接拉起其中一个。
  用户之前如果选过"文件管理 → 总是"，之后每次都会进文件管理器，代码怎么排都不会变。
- **`ACTION_PICK` 才是"相册语义"**，但它在部分 ROM 上被厂商图库实现成"单选 + 可能
  强制裁剪"，所以历史上被排到了 `GET_CONTENT` 后面 —— 于是先踩进了文件管理器。
- **Android 11+ 的包可见性**会让"有没有图库"这件事查不准（`resolveActivity` 返回
  null），所以代码里连"定向启动"都做不了，只能发隐式 Intent 让系统去选。

结论：只要还是"发一个隐式 Intent 让系统挑界面"，就永远有 ROM 能把它接到文件管理器。
**唯一能保证"点相册看到照片"的做法，是相册界面由 App 自己画。**

## 三、改法：App 内相册（微信式）+ App 内编辑

### 1. 数据层：直接读 MediaStore

新增原生通道 `keepsake/media`（`MediaLibrary.kt` + `MainActivity.kt` 里的分派）：

| 方法 | 作用 |
|---|---|
| `access` | `full` / `partial` / `none`（Android 14「部分照片访问」= `partial`） |
| `request` | 申请 `READ_MEDIA_IMAGES`（13+）/ `READ_EXTERNAL_STORAGE`（≤12）；14+ 同时申请 `READ_MEDIA_VISUAL_USER_SELECTED`，系统才会给「全部允许 / 选择照片 / 不允许」 |
| `list` | `{offset, limit, bucketId?}` → 一页图片（`path` / `name` / `size` / `dateAdded`），`LIMIT/OFFSET` 下推给 MediaStore |
| `buckets` | 相册分类（相机、截图、微信…）：按时间倒序扫一遍归组，第一张即封面 |

只读图片，不读视频/音频；查询全部在后台线程，不在主线程卡顿。

### 2. 界面层：微信式相册

`lib/features/chat/gallery/gallery_page.dart`（全屏页）

- 顶部：`✕` / 胶囊标题（`图片和视频 ▾`，选中目录后变成目录名）；
- 分类面板：微信式**右侧抽屉**（从右滑出、盖住 86%，左边留一条网格做底），
  每行「名称 (张数)」、当前项右侧打勾；目录名做了中文化映射
  （`Camera→相机`、`Screenshots→截屏`、`WeiXin→微信`、`Download→下载`），
  `DCIM` / `Pictures` / `QQ` / `知乎` 这类原样保留 —— 微信里也是原样；
- 网格：4 列方形缩略图（`cacheWidth: 360` 控制解码内存）、按天分组小标题
  （今天 / 昨天 / 11月22日）、选中项右上角 1…N 序号、再点取消、长按看大图；
- 底部：`预览(n)` / `发送(n)`；
- 状态：授权引导（允许访问照片 / 去设置授权 / 用系统图库选）、空相册、读取失败重试、
  滚动到底自动加载下一页（每页 60 张）。

> 和微信的**刻意**差异：① 底部没有「原图」开关 —— 我们选中的本来就是原图，落盘后按原图
> 上传，不存在"压缩 / 原图"二选一；② 分类里没有「所有视频」「我的收藏」—— 本 App 的相册
> 只取图片，视频走「文件」入口；③ 顶部没有搜索框。其余（分类抽屉、名称 (张数)、当前项
> 打勾、日期分组、序号多选、预览、发送(n)）都和微信一致。

`lib/features/chat/gallery/gallery_preview_page.dart`（全屏预览）

- 黑底大图、左右翻页、顶部 `n/N`；
- 底部：`编辑` / `勾选` / `完成(n)`；返回到相册时把**预览里改过的选择**带回去。

### 3. 编辑：App 内裁剪 / 旋转 / 镜像

`lib/features/chat/gallery/image_editor_page.dart`

- 只在预览页进入（微信也是这样）；
- 旋转/镜像"烘焙"进 `ui.Image`，裁剪框始终面对一张正图，坐标映射不会错；
- 保存为 PNG（长边上限 2560），落到 `getApplicationSupportDirectory()/edited/`；
- 编辑后的图**自动选中**，完成时直接用私有目录里的新文件（不再复制一次）。

### 4. 系统图库：降级为兜底，且"永不落到文件管理器"

`android/.../GalleryTargets.kt`（新增）：先用 `PackageManager` 把"文件管理器/文档选择器"
识别出来并**整体排除**：

- `ACTION_OPEN_DOCUMENT(image/*)` 的响应者 = 文档选择器；
- `ACTION_GET_CONTENT(*/*)` 这种"万能"选择器 = 文件管理器；
- 包名/类名再兜一层特征词（`documentsui`/`filemanager`/`hidisk`/`explorer`…），
  已知厂商图库包名（`com.huawei.photos`、`com.hihonor.photos`、`com.miui.gallery`、
  `com.coloros.gallery3d`、`com.vivo.gallery`…）永远放行。

然后在剩下的候选里按"已知图库 > 图库特征词"排序，**逐个 `setPackage(包名)` 定向启动**
（定向是唯一不会被"默认应用"带走的方式）。一个都没有时回 `NEED_IN_APP_GALLERY`，
**绝不**退回文件管理器：相册页把它翻译成"这台设备没有可用的系统图库，授权后就能用
App 内相册"。

`AndroidManifest.xml` 的 `<queries>` 补了 `GET_CONTENT(image/*)` 与
`OPEN_DOCUMENT(image/*)`（后者就是用来取"文件管理器黑名单"的），并恢复
`READ_MEDIA_IMAGES` / `READ_MEDIA_VISUAL_USER_SELECTED`（现在真的查 MediaStore 了）。

## 四、改动清单

| 文件 | 变动 |
|---|---|
| `android/app/src/main/kotlin/app/keepsake/keepsake/GalleryTargets.kt` | 新增：图库候选发现 + 文件管理器排除 + 定向启动 |
| `android/app/src/main/kotlin/app/keepsake/keepsake/MediaLibrary.kt` | 新增：MediaStore 分页查询、分类、权限状态 |
| `android/app/src/main/kotlin/app/keepsake/keepsake/MainActivity.kt` | 新增 `keepsake/media` 通道、权限回填；`pickImages` 改为"定向启动 + 兜底回 App 内" |
| `android/app/src/main/AndroidManifest.xml` | 媒体权限 + `GET_CONTENT/OPEN_DOCUMENT(image/*)` 可见性 |
| `lib/core/chat/media_gallery.dart` | 新增：通道封装（`MediaImage` / `MediaBucket` / `access` / `request` / `list` / `buckets` / `preserve`） |
| `lib/features/chat/gallery/gallery_page.dart` | 新增：微信式相册页 |
| `lib/features/chat/gallery/gallery_preview_page.dart` | 新增：大图预览页（含编辑入口） |
| `lib/features/chat/gallery/image_editor_page.dart` | 新增：裁剪 / 旋转 / 镜像 |
| `lib/features/chat/chat_screen.dart` | `_pickImages()` 改为打开 App 内相册 |
| `lib/core/chat/gallery_picker.dart` | 注释更新；错误码新增 `NEED_IN_APP_GALLERY` |

## 五、验证

本机（Windows + Flutter 3.50.1 / Dart 3.14.0 + Android SDK 36 + NDK 28.2）实测：

| 检查 | 结果 |
|---|---|
| `flutter analyze --no-pub` | **0 error / 0 warning 在本次新增与改动的文件里**；全项目仅剩 13 条改动前就有的历史告警（`brain_*`、`database.dart`、`import_tile.dart`），与本次无关 |
| `flutter build apk --debug --target-platform android-arm64` | ✅ 通过（Kotlin / Manifest 合并 / 资源 / AOT 全部走通） |
| `flutter test --no-pub` | ✅ 全部通过（5/5） |
| `flutter build apk --release --target-platform android-arm64` | ✅ 通过（产物见下） |

构建与测试过程中真实修掉的编译错误（说明这次不是"看起来能过"）：

1. `GalleryTargets.kt` 的 KDoc 里写了 `GET_CONTENT(*/*)`，Kotlin 支持**嵌套块注释**，
   这个 `*/` 把外层注释提前关掉了 → 改成"带通配类型"的文字描述；
2. 同一文件另一处 `ACTION_GET_CONTENT(image/*)` 里的 `/*` 又开启了一个嵌套注释，
   把文件后半段全吞掉（`Unclosed comment`）→ 同样改成文字描述。

真机需要确认的：

1. 华为 / 荣耀：点「从相册选择」是否**一定**进 App 内相册（不是文件管理器、也不是系统图库）；
2. 首次授权的三个选项（全部允许 / 选择照片 / 不允许）分别的表现；
3. 相册分类切换、日期分组小标题、滚动分页、长按预览、勾选序号；
4. 预览页「编辑」→ 裁剪/旋转/镜像 → 完成：图片是否按裁剪结果带上、序号是否正常；
5. 相册权限被拒时点「用系统图库选」：是否进厂商图库（而不是文件管理器）；
6. 发送后附件缩略图/上传是否正常（编辑过的图是 PNG）。

### 可直接安装的验证包

```
build/app/outputs/flutter-apk/app-release.apk
  32,975,316 字节 · versionCode 4260 / 0.4.26 · 签名 = debug（与现有发布包一致，可覆盖安装）
  sha256 5e37680e846c506f19ae49ddc5afd6d2e6d9db725669c9d1d61595782a2af0ae
  本包同时包含后续的 chip 按压态修复（工具芯片不再闪灰块，见 commit fix(chip)）
  只带 lib/arm64-v8a/libflutter.so（arm64 机型直接装；32 位机请用 build-abis.cmd 出包）
```

如需只含 arm64 的分包：`flutter build apk --release --target-platform android-arm64 --split-per-abi`
（产物 `app-arm64-v8a-release.apk`，versionCode 会被 Flutter 加成 6260，属正常分包行为）。
