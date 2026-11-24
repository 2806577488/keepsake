package app.keepsake.keepsake

import android.content.Context
import android.content.Intent
import android.provider.MediaStore
import java.util.Locale

/**
 * 一个"可以用它打开图库"的候选：包名 + 已经 `setPackage` 好的启动 Intent。
 */
internal data class GalleryTarget(
    val packageName: String,
    val label: String,
    val intent: Intent,
    val score: Int,
)

/**
 * 找出真正的「图库」，并且**把文件管理器排除掉**。
 *
 * 为什么需要这个文件：
 * 直接用隐式 Intent（`ACTION_GET_CONTENT` / `ACTION_PICK`）时，同一个 Intent
 * 往往同时被「图库」和「文件管理器」注册。系统会按"默认应用"或"上次的选择"
 * 直接拉起其中某一个 —— 这正是「点相册却进了文件管理器」的根因，也是前几个
 * 版本反复调 Intent 顺序、`resolveActivity`、`<queries>` 都修不掉的原因：
 * 隐式 Intent 的最终落点由 ROM 决定，App 无法控制。
 *
 * 这里的做法：
 * 1. 先问系统"谁负责文档选择"（`ACTION_OPEN_DOCUMENT` 的响应者、以及
 *    `ACTION_GET_CONTENT` 带通配类型（* / *）这种"万能"选择器），这些包
 *    一律视为文件管理器；
 * 2. 再问"谁能处理 `ACTION_PICK` 与 `ACTION_GET_CONTENT`（图片类型）"，扣掉第 1 步
 *    得到的包、再扣掉包名/类名里带文档特征词的包；
 * 3. 剩下的按"已知厂商图库 > 图库特征词"排序，用 `setPackage` 定向启动。
 *
 * 一个图库都找不到时由调用方回 `NEED_IN_APP_GALLERY`，交给 App 内网格 ——
 * 绝不再退回文件管理器。
 */
internal object GalleryTargets {

    /** 国内常见厂商图库包名（顺序 = 优先级）。 */
    private val knownGalleries: List<String> = listOf(
        "com.huawei.photos",
        "com.hihonor.photos",
        "com.huawei.gallery",
        "com.miui.gallery",
        "com.coloros.gallery3d",
        "com.oppo.gallery3d",
        "com.vivo.gallery",
        "com.bbk.gallery",
        "com.sec.android.gallery3d",
        "com.meizu.media.gallery",
        "com.google.android.apps.photos",
        "com.android.gallery3d",
    )

    /** 文件管理器 / 文档选择器的特征词：包名或 Activity 类名命中即判定"不是图库"。 */
    private val documentMarkers: List<String> = listOf(
        "documentsui",
        "documentsactivity",
        "documentui",
        "documentpicker",
        "filemanager",
        "file_manager",
        "fileexplorer",
        "file_explorer",
        "filebrowser",
        "file_browser",
        "filepicker",
        "hidisk",
        "downloadprovider",
        "myfiles",
        "nbu.files",
        "explorer",
    )

    /** 图库特征词：没进已知包名表的厂商图库靠这个认出来。 */
    private val galleryMarkers: List<String> = listOf(
        "gallery",
        "photos",
        "photo",
        "album",
        "picture",
        "media.module",
    )

    private const val KIND_PICK = 1
    private const val KIND_GET_CONTENT = 0

    /** 一次探测：Intent + 它是"相册语义"(PICK) 还是"取内容语义"(GET_CONTENT)。 */
    private class Probe(val intent: Intent, val kind: Int)

    /** 按优先级返回可定向启动的图库（已排除文件管理器，已 `setPackage`）。 */
    fun discover(context: Context): List<GalleryTarget> {
        val manager = context.packageManager
        val documents = documentPackages(context)
        val best = LinkedHashMap<String, GalleryTarget>()
        for (probe in probes()) {
            val resolved = try {
                manager.queryIntentActivities(probe.intent, 0)
            } catch (error: Exception) {
                emptyList()
            }
            for (info in resolved) {
                val activity = info.activityInfo ?: continue
                val packageName = activity.packageName
                val className = activity.name
                if (packageName == context.packageName) continue
                if (isDocumentPackage(packageName, className, documents)) continue
                val score = scoreOf(packageName, className, probe.kind)
                if (score < 0) continue
                val existing = best[packageName]
                if (existing != null && existing.score >= score) continue
                val launch = Intent(probe.intent).setPackage(packageName)
                val label = try {
                    info.loadLabel(manager).toString()
                } catch (error: Exception) {
                    packageName
                }
                best[packageName] = GalleryTarget(packageName, label, launch, score)
            }
        }
        return best.values.sortedByDescending { it.score }
    }

    /** `documents` 里出现的包（系统里负责"选文件"的那些）。 */
    fun documentPackages(context: Context): Set<String> {
        val manager = context.packageManager
        val result = LinkedHashSet<String>()
        // 只问"文档类"探测：OPEN_DOCUMENT 只由文档选择器实现；
        // GET_CONTENT 带通配类型（任意 mime）时同样只有文件管理器会实现。
        val probes = listOf(
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply { type = "image/*" },
            Intent(Intent.ACTION_GET_CONTENT).apply { type = "*/*" },
        )
        for (probe in probes) {
            val resolved = try {
                manager.queryIntentActivities(probe, 0)
            } catch (error: Exception) {
                emptyList()
            }
            for (info in resolved) {
                val packageName = info.activityInfo?.packageName ?: continue
                if (packageName != context.packageName) result.add(packageName)
            }
        }
        return result
    }

    /** 某条 Intent 的响应者里有没有"非文件管理器"的（给 Photo Picker 用）。 */
    fun resolvesOutsideDocuments(context: Context, intent: Intent): Boolean {
        val documents = documentPackages(context)
        val resolved = try {
            context.packageManager.queryIntentActivities(intent, 0)
        } catch (error: Exception) {
            emptyList()
        }
        return resolved.any { info ->
            val activity = info.activityInfo ?: return@any false
            !isDocumentPackage(activity.packageName, activity.name, documents)
        }
    }

    private fun probes(): List<Probe> {
        // ACTION_PICK 是"相册语义"：文件管理器一般只实现 GET_CONTENT / OPEN_DOCUMENT，
        // 所以 PICK 的响应者更接近图库；GET_CONTENT 放在后面兜底。
        val pick = Intent(Intent.ACTION_PICK).apply {
            setDataAndType(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, "image/*")
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        val getContent = Intent(Intent.ACTION_GET_CONTENT).apply {
            type = "image/*"
            addCategory(Intent.CATEGORY_OPENABLE)
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        return listOf(
            Probe(pick, KIND_PICK),
            Probe(getContent, KIND_GET_CONTENT),
        )
    }

    private fun isDocumentPackage(
        packageName: String,
        className: String,
        documents: Set<String>,
    ): Boolean {
        // 已知厂商图库永远放行：它们既可能响应 GET_CONTENT(*/*)，也可能被
        // 某些 ROM 算进"文档选择器"，但用户点相册就是要看到它。
        if (knownGalleries.contains(packageName)) return false
        val key = "$packageName/$className".lowercase(Locale.ROOT)
        if (documentMarkers.any { key.contains(it) }) return true
        return documents.contains(packageName)
    }

    private fun scoreOf(packageName: String, className: String, kind: Int): Int {
        val knownIndex = knownGalleries.indexOf(packageName)
        // PICK 比 GET_CONTENT 更"像图库"，加 40 分做次级排序。
        val kindBonus = if (kind == KIND_PICK) 40 else 0
        if (knownIndex >= 0) return 1000 - knownIndex + kindBonus
        val key = "$packageName/$className".lowercase(Locale.ROOT)
        if (galleryMarkers.any { key.contains(it) }) return 100 + kindBonus
        return kindBonus
    }
}
