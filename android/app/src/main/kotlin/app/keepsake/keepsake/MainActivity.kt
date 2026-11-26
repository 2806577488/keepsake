package app.keepsake.keepsake

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.widget.Toast
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * Keepsake 主 Activity。
 *
 * 除 Flutter 默认行为，额外提供三条通道：
 * - `keepsake/update`：应用内更新（安装未知来源权限 / 安装 APK）；
 * - `keepsake/gallery`：**备选**路径 —— 系统图库选图。国产 ROM 上隐式
 *   Intent 会被文件管理器抢走（`ACTION_GET_CONTENT` 同时被图库与文件管理
 *   注册），所以这里改成"先问系统谁是真图库，再用 `setPackage` 定向启动"，
 *   文件管理器一律排除；一个都没有时回 `NEED_IN_APP_GALLERY`，由 App 内
 *   相册网格兜底（见 `keepsake/media`）；
 * - `keepsake/media`：本机相册列表（App 内网格用，只读 MediaStore，不发
 *   Intent，因此不可能跳到文件管理器）。
 *
 * 对应 Dart 侧：lib/core/update/update_service.dart、
 * lib/core/chat/gallery_picker.dart、lib/core/chat/media_gallery.dart。
 */
class MainActivity : FlutterActivity() {

    private val updateChannelName = "keepsake/update"
    private val galleryChannelName = "keepsake/gallery"
    private val mediaChannelName = "keepsake/media"

    /**
     * 更新通道的引用：`keepsake/update` 是**双向**的 ——
     * Dart 调原生（installApk / applyPatch …），原生也通过它把差分合并进度
     * 推回 Dart（`patchProgress`），所以要把通道对象存下来。
     */
    private var updateChannel: MethodChannel? = null

    /** 原生侧线程（合并 APK）回到主线程再回结果/发进度。 */
    private val mainHandler = Handler(Looper.getMainLooper())

    /** 图库选择是异步的：先挂起 Flutter 侧的结果，等 onActivityResult 回来再回填。 */
    private var pendingGalleryResult: MethodChannel.Result? = null

    /** 图库选图用的 requestCode（与 Flutter 插件用的区间错开）。 */
    private val galleryRequestCode = 0x4b01

    /** 相册权限申请的 requestCode（与图库的错开）。 */
    private val mediaPermissionRequestCode = 0x4b02

    /** 相册权限申请的挂起结果：运行时权限是异步的，要等 onRequestPermissionsResult。 */
    private var pendingMediaPermission: MethodChannel.Result? = null

    /** Photo Picker 一次最多选几张（与 Dart 侧附件上限无关，只约束系统图库）。 */
    private val maxPickedImages = 9

    /** 缓存文件名长度上限（M3：provider 的 DISPLAY_NAME 可能极长）。 */
    private val maxFileNameLength = 80

    /** 查不到/查不了名字时的兜底名。 */
    private val defaultPickedName = "image.jpg"

    /** 同一毫秒内多选多张时的序号，避免「时间戳前缀」自己撞车。 */
    private var pickedSeq = 0

    /** 「用其他应用打开」文本文件时最多读多少字节（防止误开超大日志吃满内存）。 */
    private val maxIncomingTextBytes = 2 * 1024 * 1024

    /**
     * 图库选图返回。
     *
     * 注意：FlutterActivity 只继承 [Activity]，没有 ComponentActivity 的
     * `registerForActivityResult`，所以这里用旧的 startActivityForResult 回调。
     */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != galleryRequestCode) return
        val pending = pendingGalleryResult
        pendingGalleryResult = null
        if (pending == null) return
        if (resultCode != Activity.RESULT_OK) {
            // 用户取消：返回空列表，Dart 侧当作「没选」处理，不弹错误。
            pending.success(emptyList<String>())
            return
        }
        val uris = mutableListOf<Uri>()
        val clip = data?.clipData
        if (clip != null) {
            for (index in 0 until clip.itemCount) {
                clip.getItemAt(index)?.uri?.let { uris.add(it) }
            }
        } else {
            data?.data?.let { uris.add(it) }
        }
        val copied = uris.mapNotNull { copyToCache(it) }
        if (copied.isEmpty() && uris.isNotEmpty()) {
            // 系统确实返回了图、但一张都没读出来：必须显式报错，
            // 不能当成「用户取消」静默返回空列表（M2）。
            pending.error(
                "COPY_FAILED",
                "图片读取失败：图库返回了 ${uris.size} 张，但没有一张能读出来",
                null,
            )
            return
        }
        pending.success(copied)
    }

    /**
     * 相册权限的回填。
     *
     * `grantResults` 在"系统直接取消/被打断"时可能是空数组，所以不按它判断
     * 结果，而是重新查一次真实授权状态（Android 14 的「部分照片」也能正确
     * 落成 PARTIAL）。
     */
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != mediaPermissionRequestCode) return
        val pending = pendingMediaPermission ?: return
        pendingMediaPermission = null
        mainHandler.post {
            pending.success(MediaLibrary.access(this) != MediaAccess.NONE)
        }
    }

    /** 冷启动就带着文件来（「用其他应用打开」→ Keepsake）。 */
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        readIncomingText(intent)?.let { deliverIncomingText(it) }
    }

    /** 已在前台时又被「用其他应用打开」一次（launchMode 是 singleTop）。 */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readIncomingText(intent)?.let { deliverIncomingText(it) }
    }

    /**
     * 读「用其他应用打开」的文本文件内容。
     *
     * 只认 text 开头的 MIME；超过 [maxIncomingTextBytes] 截断。读不到就返回 null（不弹错误）。
     */
    private fun readIncomingText(intent: Intent?): String? {
        if (intent == null || intent.action != Intent.ACTION_VIEW) return null
        val uri = intent.data ?: return null
        val type = intent.type
            ?: try {
                contentResolver.getType(uri)
            } catch (error: Exception) {
                null
            }
            ?: ""
        if (!type.startsWith("text/")) return null
        return try {
            contentResolver.openInputStream(uri)?.use { input ->
                val out = ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                var total = 0
                while (total < maxIncomingTextBytes) {
                    val read = input.read(buffer)
                    if (read <= 0) break
                    val allowed = minOf(read, maxIncomingTextBytes - total)
                    if (allowed <= 0) break
                    out.write(buffer, 0, allowed)
                    total += allowed
                }
                String(out.toByteArray(), Charsets.UTF_8)
            }
        } catch (error: Exception) {
            null
        }
    }

    /** MVP：把文件内容复制到剪贴板并提示粘贴（暂时不自动建会话）。 */
    private fun deliverIncomingText(text: String) {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return
        try {
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            clipboard.setPrimaryClip(ClipData.newPlainText("Keepsake", trimmed))
        } catch (error: Exception) {
            // 剪贴板不可用：下面的 Toast 仍会提示
        }
        Toast.makeText(
            this,
            "已读取文件内容（${trimmed.length} 字）并复制，粘贴到输入框即可",
            Toast.LENGTH_LONG,
        ).show()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val update = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannelName)
        updateChannel = update
        update.setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstallPackages" -> result.success(canInstallPackages())
                    "openInstallSettings" -> openInstallSettings(result)
                    "installApk" -> installApk(call.argument<String>("path"), result)
                    // H4：安装被厂商安全策略拦时，Dart 侧要按厂商给中文引导，
                    // 而 Dart 侧没有 device_info_plus 依赖 → 由这里暴露 Build.MANUFACTURER。
                    "deviceManufacturer" -> result.success(Build.MANUFACTURER ?: "")
                    // 分 ABI 挑包：Dart 侧同样没有 device_info_plus 依赖，
                    // 拿不到 Build.SUPPORTED_ABIS，就由这里给。
                    "supportedAbis" -> result.success(supportedAbis())
                    // 差分更新：已安装 APK 的 sha256（用于在下载补丁前筛掉对不上的补丁）。
                    "installedApkSha256" -> installedApkSha256(result)
                    // 差分更新：把补丁套到已安装 APK 上，校验通过后返回新 APK 路径。
                    "applyPatch" -> applyPatch(call, result)
                    // 完整包下载后的 sha256 校验（E-24）：Dart 侧没有加密库。
                    "fileSha256" -> fileSha256(call.argument<String>("path"), result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, galleryChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickImages" -> pickImages(result)
                    else -> result.notImplemented()
                }
            }
        // App 内相册网格：只读 MediaStore，不发任何选图 Intent。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "access" -> result.success(MediaLibrary.access(this).wireName)
                    "request" -> requestMediaPermission(result)
                    "list" -> listMediaImages(call, result)
                    "buckets" -> listMediaBuckets(result)
                    else -> result.notImplemented()
                }
            }
    }

    // ---------------------------------------------------------------------
    // App 内相册（MediaStore）
    // ---------------------------------------------------------------------

    /** 申请「照片和视频」权限；回填 true 表示至少拿到了"部分照片"访问。 */
    private fun requestMediaPermission(result: MethodChannel.Result) {
        if (MediaLibrary.access(this) != MediaAccess.NONE) {
            result.success(true)
            return
        }
        if (pendingMediaPermission != null) {
            result.error("BUSY", "上一次权限申请还没结束", null)
            return
        }
        pendingMediaPermission = result
        try {
            requestPermissions(MediaLibrary.permissions(), mediaPermissionRequestCode)
        } catch (error: Exception) {
            pendingMediaPermission = null
            result.error("REQUEST_FAILED", error.message ?: "申请相册权限失败", null)
        }
    }

    /** 读一页相册图片（后台线程 + 回主线程回结果）。 */
    private fun listMediaImages(call: MethodCall, result: MethodChannel.Result) {
        if (MediaLibrary.access(this) == MediaAccess.NONE) {
            // 没授权时查询必然失败（Android 10+ 还可能是 SecurityException）：
            // 先给明确错误码，让 Dart 侧显示"允许访问照片"而不是一个空网格。
            result.error("NO_PERMISSION", "还没有「照片和视频」权限", null)
            return
        }
        val offset = (call.argument<Int>("offset") ?: 0).coerceAtLeast(0)
        val limit = (call.argument<Int>("limit") ?: 60).coerceIn(1, 500)
        val bucketId = call.argument<String>("bucketId")
        Thread {
            try {
                val images = MediaLibrary.list(this, offset, limit, bucketId)
                mainHandler.post { result.success(images) }
            } catch (error: Exception) {
                mainHandler.post {
                    result.error("LIST_FAILED", error.message ?: "读取相册失败", null)
                }
            }
        }.start()
    }

    /** 读相册分类（微信式顶部「全部图片 ▾」）。 */
    private fun listMediaBuckets(result: MethodChannel.Result) {
        if (MediaLibrary.access(this) == MediaAccess.NONE) {
            result.error("NO_PERMISSION", "还没有「照片和视频」权限", null)
            return
        }
        Thread {
            try {
                val buckets = MediaLibrary.buckets(this)
                mainHandler.post { result.success(buckets) }
            } catch (error: Exception) {
                mainHandler.post {
                    result.error("LIST_FAILED", error.message ?: "读取相册分类失败", null)
                }
            }
        }.start()
    }

    // ---------------------------------------------------------------------
    // 图库选图
    // ---------------------------------------------------------------------

    private fun pickImages(result: MethodChannel.Result) {
        if (pendingGalleryResult != null) {
            result.error("BUSY", "上一次选图还没结束", null)
            return
        }
        pendingGalleryResult = result

        // 1) Android 13+ 的系统 Photo Picker（AOSP MediaProvider / 带 GMS 的机型）。
        //    先确认它的响应者不是文件管理器 —— 极少数 ROM 会把这个 action 接到
        //    文档界面上，那种情况宁可不走这一步。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val picker = Intent(MediaStore.ACTION_PICK_IMAGES).apply {
                type = "image/*"
                putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, maxPickedImages)
            }
            val usablePicker = try {
                GalleryTargets.resolvesOutsideDocuments(this, picker)
            } catch (error: Exception) {
                false
            }
            if (usablePicker && tryLaunchGallery(picker)) return
        }

        // 2) 厂商图库：`GalleryTargets.discover` 已经排除了文件管理器 / 文档选择器，
        //    这里逐个 `setPackage(图库包名)` 定向启动 —— 定向是唯一能保证
        //    "不会因为默认应用而进文件管理器"的做法。
        val targets = try {
            GalleryTargets.discover(this)
        } catch (error: Exception) {
            emptyList<GalleryTarget>()
        }
        for (target in targets) {
            if (tryLaunchGallery(target.intent)) return
        }

        // 3) 一个真图库都找不到：**绝不**退回文件管理器（用户点的是「相册」），
        //    交给 Dart 侧留在 App 内相册里选。
        pendingGalleryResult = null
        result.error(
            "NEED_IN_APP_GALLERY",
            "这台设备没有可用的系统图库（只剩文件管理器），请用 App 内相册",
            null,
        )
    }

    /** 尝试启动一个选图 Intent；系统里没有对应 Activity 时返回 false（继续回退）。 */
    private fun tryLaunchGallery(intent: Intent): Boolean {
        return try {
            startActivityForResult(intent, galleryRequestCode)
            true
        } catch (error: ActivityNotFoundException) {
            false
        } catch (error: Exception) {
            false
        }
    }

    /**
     * 把图库返回的 content:// 复制到 `cacheDir/picked/`，Dart 侧只认本地路径。
     *
     * 两级失败分开处理（M2）：
     * - 查文件名失败 → 回退到默认名，不连图一起丢；
     * - 打不开流 / 复制失败 → 返回 null（由调用方过滤），**绝不**返回不存在的路径。
     */
    private fun copyToCache(uri: Uri): String? {
        val dir = try {
            File(cacheDir, "picked").apply { mkdirs() }
        } catch (error: Exception) {
            return null
        }
        // 名字查询单独兜住：华为/部分 provider 查 OpenableColumns 会抛 SecurityException。
        val rawName = try {
            queryDisplayName(uri)
        } catch (error: Exception) {
            null
        }
        // 时间戳 + 序号前缀：多选同名文件（连拍、多目录）不会互相覆盖（M3）。
        val seq = pickedSeq++
        val prefix = "${System.currentTimeMillis()}_$seq"
        val target = File(dir, "${prefix}_${safeFileName(rawName)}")
        val input = try {
            contentResolver.openInputStream(uri)
        } catch (error: Exception) {
            null
        }
        if (input == null) return null
        return try {
            input.use { stream ->
                target.outputStream().use { output -> stream.copyTo(output) }
            }
            target.absolutePath
        } catch (error: Exception) {
            // 复制失败：删掉半截文件，返回 null（不能给 Dart 一个坏路径）。
            try {
                if (target.exists()) target.delete()
            } catch (cleanupError: Exception) {
                // 删不掉也不影响结论。
            }
            null
        }
    }

    /**
     * 附件名清洗（M3）：只取 basename，过滤路径分隔符、`..` 与文件名非法字符，
     * 超长截断到 [maxFileNameLength] 字符（保留扩展名）。中文名保留原样。
     */
    private fun safeFileName(raw: String?): String {
        var name = (raw ?: "").trim()
        name = name.substringAfterLast('/').substringAfterLast('\\')
        name = name.replace("..", "_")
        // 文件名非法字符 + 控制字符；保留中文以便附件列表能看懂。
        name = name.replace(Regex("[\\\\/:*?\"<>|\\u0000-\\u001F]"), "_")
        name = name.trim('.', '_', '-', ' ')
        if (name.isEmpty()) return defaultPickedName
        if (name.length > maxFileNameLength) {
            val dot = name.lastIndexOf('.')
            val ext = if (dot > 0 && name.length - dot <= 8) name.substring(dot) else ""
            name = name.substring(0, maxFileNameLength - ext.length) + ext
        }
        return name
    }

    private fun queryDisplayName(uri: Uri): String? {
        var name: String? = null
        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst() && !cursor.isNull(0)) {
                name = cursor.getString(0)
            }
        }
        return name
    }

    // ---------------------------------------------------------------------
    // 应用内更新
    // ---------------------------------------------------------------------

    /** Android 8.0（API 26）起必须由用户显式授权「安装未知来源应用」。 */
    private fun canInstallPackages(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            packageManager.canRequestPackageInstalls()

    private fun openInstallSettings(result: MethodChannel.Result) {
        try {
            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                .setData(Uri.parse("package:$packageName"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            result.success(null)
        } catch (error: Exception) {
            result.error("SETTINGS_FAILED", "打开安装权限设置失败：${error.message}", null)
        }
    }

    private fun installApk(rawPath: String?, result: MethodChannel.Result) {
        if (rawPath.isNullOrBlank()) {
            result.error("BAD_ARGS", "安装包路径为空", null)
            return
        }
        val apk = File(rawPath)
        // 传进来的是 Flutter 侧刚落盘的文件，先确认它真的在、且可读。
        if (!apk.exists() || !apk.isFile) {
            result.error("FILE_MISSING", "安装包不存在：$rawPath", null)
            return
        }
        if (!apk.canRead()) {
            result.error("FILE_UNREADABLE", "安装包不可读：$rawPath", null)
            return
        }
        if (!canInstallPackages()) {
            result.error("NEED_PERMISSION", "还没有允许「安装未知来源应用」", null)
            return
        }
        try {
            // authority 与 AndroidManifest.xml 的 ${applicationId}.fileprovider 一致。
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", apk)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(null)
        } catch (error: ActivityNotFoundException) {
            result.error("NO_INSTALLER", "系统里没有可用的安装器", null)
        } catch (error: Exception) {
            // FileProvider 路径不在 file_paths.xml 白名单内时也走这里（IllegalArgumentException）。
            result.error("INSTALL_FAILED", "打开安装器失败：${error.message}", null)
        }
    }

    // ---------------------------------------------------------------------
    // 分 ABI 挑包 + 差分更新（patch 合并）
    // ---------------------------------------------------------------------

    /** 本机支持的全部 ABI，按优先级（`arm64-v8a` / `armeabi-v7a` …）。 */
    private fun supportedAbis(): List<String> = try {
        Build.SUPPORTED_ABIS?.toList() ?: emptyList()
    } catch (error: Exception) {
        emptyList()
    }

    /** 已安装 APK 的路径（`applicationInfo.sourceDir`）；拿不到时为 null。 */
    private fun installedApkPath(): String? = try {
        applicationInfo?.sourceDir
    } catch (error: Exception) {
        null
    }

    /** 已安装 APK 的 sha256：Dart 侧没加密库，用它来判断补丁能不能对上。 */
    private fun installedApkSha256(result: MethodChannel.Result) {
        val path = installedApkPath()
        if (path.isNullOrBlank()) {
            result.error("NO_SOURCE_DIR", "读不到已安装 APK 的路径", null)
            return
        }
        runOnBackground(result) { BsPatch.sha256(File(path)) }
    }

    /**
     * 任意文件的 sha256（完整包下载后的校验用，E-24）。
     *
     * 为什么放原生：Dart 侧没有加密库，且 40MB 级 APK 用纯 Dart 算会很慢；
     * [BsPatch.sha256] 是现成的流式实现，走后台线程。
     */
    private fun fileSha256(rawPath: String?, result: MethodChannel.Result) {
        if (rawPath.isNullOrBlank()) {
            result.error("BAD_ARGS", "文件路径为空", null)
            return
        }
        val file = File(rawPath)
        if (!file.exists() || !file.isFile) {
            result.error("FILE_MISSING", "文件不存在：$rawPath", null)
            return
        }
        runOnBackground(result) { BsPatch.sha256(file) }
    }

    /**
     * 差分合并：`已安装 APK + 补丁 → 新 APK`。
     *
     * 参数（`call.arguments`）：
     * - `patch`：补丁绝对路径；
     * - `outDir`：输出目录（Dart 侧的 `updates/`，在 FileProvider 白名单内）；
     * - `outName`：输出文件名（如 `keepsake-0.4.21-arm64.apk`）；
     * - `targetSha256`：**必填**，新 APK 的 sha256；不匹配就不产出可用文件；
     * - `patchSha256`：可选，补丁文件自身的 sha256；
     * - `fromSha256`：可选，已安装 APK 的 sha256（对不上说明补丁不是给这一版的）。
     *
     * 成功回传新 APK 的绝对路径（Dart 侧直接交给 installApk）。
     * 任何失败都回 `PATCH_FAILED`（或 `IO_FAILED`），Dart 侧据此回退到完整包下载。
     */
    private fun applyPatch(call: MethodCall, result: MethodChannel.Result) {
        val patchPath = call.argument<String>("patch")
        val outDir = call.argument<String>("outDir")
        val outName = call.argument<String>("outName") ?: "keepsake-patched.apk"
        val targetSha = call.argument<String>("targetSha256")?.trim().orEmpty()
        val patchSha = call.argument<String>("patchSha256")?.trim()?.takeIf { it.isNotEmpty() }
        val fromSha = call.argument<String>("fromSha256")?.trim()?.takeIf { it.isNotEmpty() }

        if (patchPath.isNullOrBlank()) {
            result.error("BAD_ARGS", "补丁路径为空", null)
            return
        }
        if (outDir.isNullOrBlank()) {
            result.error("BAD_ARGS", "输出目录为空", null)
            return
        }
        if (targetSha.length != 64) {
            // 没有目标校验值就不能合并：宁可全量下载，也不装一个没法验证的包。
            result.error("BAD_ARGS", "缺少新包的 sha256 校验值，拒绝合并", null)
            return
        }
        val sourceDir = installedApkPath()
        if (sourceDir.isNullOrBlank()) {
            result.error("NO_SOURCE_DIR", "读不到已安装 APK 的路径", null)
            return
        }

        val patchFile = File(patchPath)
        val outFile = File(File(outDir), safeFileName(outName))
        // 合并 40MB 级的包要几秒到十几秒，绝不能在主线程做。
        runOnBackground(result) {
            if (patchSha != null) {
                val actualPatch = BsPatch.sha256(patchFile)
                if (!actualPatch.equals(patchSha, ignoreCase = true)) {
                    throw BsPatch.PatchException("补丁文件校验失败（sha256 不匹配），不会用来合并")
                }
            }
            val oldApk = File(sourceDir)
            if (fromSha != null) {
                val actualFrom = BsPatch.sha256(oldApk)
                if (!actualFrom.equals(fromSha, ignoreCase = true)) {
                    throw BsPatch.PatchException("本机已安装的 APK 与该补丁对不上（不是同一次构建）")
                }
            }
            BsPatch.apply(oldApk, patchFile, outFile, targetSha) { done, total ->
                // 进度推回 Dart（MethodChannel 双向）；主线程回调。
                mainHandler.post {
                    updateChannel?.invokeMethod(
                        "patchProgress",
                        mapOf("done" to done, "total" to total),
                    )
                }
            }
            outFile.absolutePath
        }
    }

    /** 后台线程跑 [block]，结果/异常都回主线程交给 [result]。 */
    private fun <T> runOnBackground(result: MethodChannel.Result, block: () -> T) {
        Thread {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (error: BsPatch.PatchException) {
                mainHandler.post { result.error("PATCH_FAILED", error.message ?: "合并失败", null) }
            } catch (error: Exception) {
                mainHandler.post {
                    result.error("IO_FAILED", error.message ?: "差分合并时发生未知错误", null)
                }
            }
        }.start()
    }
}
