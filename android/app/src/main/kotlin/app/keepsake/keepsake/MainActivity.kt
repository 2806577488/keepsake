package app.keepsake.keepsake

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Keepsake 主 Activity。
 *
 * 除了 Flutter 默认行为，额外提供一条应用内更新通道 `keepsake/update`：
 * - `canInstallPackages`：是否已允许安装未知来源应用；
 * - `openInstallSettings`：跳到系统「允许安装未知来源应用」设置页；
 * - `installApk(path)`：用 FileProvider 把下载好的 APK 交给系统安装器。
 *
 * 对应 Dart 侧：lib/core/update/update_service.dart。
 */
class MainActivity : FlutterActivity() {

    private val updateChannelName = "keepsake/update"

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
    }

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
