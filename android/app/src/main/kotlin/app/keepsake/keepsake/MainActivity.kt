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
 *   （DocumentsUI 的「最近」界面），所以这里自己发 Intent：
 *   先试 `ACTION_PICK_IMAGES`（Android 13+ 系统图库、可多选），
 *   解析不到就退 `ACTION_PICK`（老式相册选择，直接打开厂商图库）。
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
        pending.success(uris.mapNotNull { copyToCache(it) })
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstallPackages" -> result.success(canInstallPackages())
                    "openInstallSettings" -> openInstallSettings(result)
                    "installApk" -> installApk(call.argument<String>("path"), result)
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

        // Android 13+ 的系统图库选择器（可多选、不需要权限）。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val picker = Intent(MediaStore.ACTION_PICK_IMAGES).apply {
                type = "image/*"
                putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, 9)
            }
            if (picker.resolveActivity(packageManager) != null) {
                launchGallery(picker)
                return
            }
        }

        // 华为等厂商没有系统 Photo Picker：老的 ACTION_PICK 会直接打开厂商图库。
        val fallback = Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI)
        if (fallback.resolveActivity(packageManager) != null) {
            launchGallery(fallback)
            return
        }

        pendingGalleryResult = null
        result.error("NO_GALLERY", "这台设备没有可用的图库选择器", null)
    }

    private fun launchGallery(intent: Intent) {
        try {
            startActivityForResult(intent, galleryRequestCode)
        } catch (error: ActivityNotFoundException) {
            val pending = pendingGalleryResult
            pendingGalleryResult = null
            pending?.error("NO_GALLERY", "打不开图库：${error.message}", null)
        }
    }

    /** 把图库返回的 content:// 复制到 cacheDir/picked/，Dart 侧只认本地路径。 */
    private fun copyToCache(uri: Uri): String? {
        return try {
            val name = queryDisplayName(uri)?.takeIf { it.isNotBlank() }
                ?: "picked_${System.currentTimeMillis()}.jpg"
            val dir = File(cacheDir, "picked").apply { mkdirs() }
            // 同名覆盖，避免多次选图把缓存撑大。
            val target = File(dir, name)
            contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            }
            target.absolutePath
        } catch (error: Exception) {
            null
        }
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
