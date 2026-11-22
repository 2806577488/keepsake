package app.keepsake.keepsake

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Keepsake 主 Activity。
 *
 * 除 Flutter 默认行为，额外提供两条通道：
 * - `keepsake/update`：应用内更新（安装未知来源权限 / 安装 APK）；
 * - `keepsake/gallery`：直接用系统图库选图。
 *   `image_picker` 在华为等没有 AOSP Photo Picker 的设备上会回退到文件管理器
 *   （DocumentsUI 的「最近」界面），所以这里自己发 Intent，顺序为
 *   `ACTION_PICK_IMAGES`（Android 13+）→ `ACTION_GET_CONTENT`（可多选，
 *   华为系打开的就是厂商图库）→ `ACTION_PICK`（老式相册，单张语义兜底）。
 *
 * 对应 Dart 侧：lib/core/update/update_service.dart、lib/core/chat/gallery_picker.dart。
 */
class MainActivity : FlutterActivity() {

    private val updateChannelName = "keepsake/update"
    private val galleryChannelName = "keepsake/gallery"

    /** 图库选择是异步的：先挂起 Flutter 侧的结果，等 onActivityResult 回来再回填。 */
    private var pendingGalleryResult: MethodChannel.Result? = null

    /** 图库选图用的 requestCode（与 Flutter 插件用的区间错开）。 */
    private val galleryRequestCode = 0x4b01

    /** Photo Picker 一次最多选几张（与 Dart 侧附件上限无关，只约束系统图库）。 */
    private val maxPickedImages = 9

    /** 缓存文件名长度上限（M3：provider 的 DISPLAY_NAME 可能极长）。 */
    private val maxFileNameLength = 80

    /** 查不到/查不了名字时的兜底名。 */
    private val defaultPickedName = "image.jpg"

    /** 同一毫秒内多选多张时的序号，避免「时间戳前缀」自己撞车。 */
    private var pickedSeq = 0

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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstallPackages" -> result.success(canInstallPackages())
                    "openInstallSettings" -> openInstallSettings(result)
                    "installApk" -> installApk(call.argument<String>("path"), result)
                    // H4：安装被厂商安全策略拦时，Dart 侧要按厂商给中文引导，
                    // 而 Dart 侧没有 device_info_plus 依赖 → 由这里暴露 Build.MANUFACTURER。
                    "deviceManufacturer" -> result.success(Build.MANUFACTURER ?: "")
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

        // 回退顺序（H2）：PICK_IMAGES → GET_CONTENT → PICK，每级独立 try/catch。
        // 全部直接 start、不用 resolveActivity 做门禁——Android 11+ 包可见性过滤
        // 会把「明明有应用」误判成 null（H1 的根因）。
        //
        // 1) Android 13+ 系统图片选择器（Photo Picker）：可多选、不需要读相册权限。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val picker = Intent(MediaStore.ACTION_PICK_IMAGES).apply {
                type = "image/*"
                putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, maxPickedImages)
            }
            if (tryLaunchGallery(picker)) return
        }

        // 2) 华为/荣耀没有系统 Photo Picker：ACTION_GET_CONTENT 在华为系 ROM 上
        //    打开的是「图库」而不是文件管理器（AOSP 上才直落 DocumentsUI），
        //    且支持多选 → 比 ACTION_PICK（单张语义）更靠前。
        val open = Intent(Intent.ACTION_GET_CONTENT).apply {
            type = "image/*"
            addCategory(Intent.CATEGORY_OPENABLE)
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        if (tryLaunchGallery(open)) return

        // 3) 老式相册选择：保证至少能进厂商图库。部分 ROM 只回第一张，
        //    onActivityResult 里已经按 clipData 优先、data 兜底读取。
        val pick = Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI).apply {
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        if (tryLaunchGallery(pick)) return

        pendingGalleryResult = null
        result.error("NO_GALLERY", "这台设备没有可用的图库选择器", null)
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
}
