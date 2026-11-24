package app.keepsake.keepsake

import android.Manifest
import android.content.ContentResolver
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore

/** 相册读取权限的三种状态（对外用 [wireName] 传给 Dart）。 */
internal enum class MediaAccess(val wireName: String) {
    /** 还没授权 / 用户拒绝。 */
    NONE("none"),

    /** Android 14 的「部分照片访问」：只能读用户挑过的那几张。 */
    PARTIAL("partial"),

    /** 可以读全部照片。 */
    FULL("full"),
}

/**
 * 直接查 MediaStore 的本机相册（给 App 内自己的网格用）。
 *
 * 为什么不走系统选图器：见 `GalleryTargets.kt` 顶部说明。这里只负责"把图片
 * 列表读出来"，不涉及任何 Intent，所以**不可能**跳到文件管理器。
 *
 * 权限：Android 13+ 是 `READ_MEDIA_IMAGES`；Android 14+ 还允许用户只授权
 * 「部分照片」（`READ_MEDIA_VISUAL_USER_SELECTED`），此时 MediaStore 只会
 * 返回用户挑过的那些，界面上要如实提示"仅显示已授权的照片"。
 */
internal object MediaLibrary {

    /** 当前授权状态（不申请、不弹框）。 */
    fun access(context: Context): MediaAccess {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val images = context.checkSelfPermission(Manifest.permission.READ_MEDIA_IMAGES)
            if (images == PackageManager.PERMISSION_GRANTED) return MediaAccess.FULL
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                val selected = context.checkSelfPermission(
                    Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
                )
                if (selected == PackageManager.PERMISSION_GRANTED) return MediaAccess.PARTIAL
            }
            return MediaAccess.NONE
        }
        val legacy = context.checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE)
        return if (legacy == PackageManager.PERMISSION_GRANTED) MediaAccess.FULL else MediaAccess.NONE
    }

    /** 运行时申请的权限集合。 */
    fun permissions(): Array<String> = when {
        // 34+ 必须同时申请"部分访问"，系统才会给出「全部允许 / 选择照片 / 不允许」。
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> arrayOf(
            Manifest.permission.READ_MEDIA_IMAGES,
            Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
        )
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> arrayOf(
            Manifest.permission.READ_MEDIA_IMAGES,
        )
        else -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
    }

    /**
     * 取一页图片（按加入时间倒序）。
     *
     * 返回的 Map 字段：`path`（绝对路径，可直接 `File(...)` 读）、`name`、
     * `size`（字节）、`dateAdded`（毫秒）。`path` 查不到的条目直接跳过 ——
     * 云端相册 / 某些 provider 的 `DATA` 为空，给 Dart 一个空路径只会白块。
     *
     * [bucketId] 非空时只取该目录（微信式「全部图片 / 相机 / 截图」切换）。
     *
     * 注意：调用方必须在后台线程调用（MediaStore 查询 + 上万张图的分页读取
     * 偶尔会到几十毫秒）。
     */
    fun list(
        context: Context,
        offset: Int,
        limit: Int,
        bucketId: String?,
    ): List<Map<String, Any?>> {
        val resolver: ContentResolver = context.contentResolver
        val collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DATA,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.SIZE,
            MediaStore.Images.Media.DATE_ADDED,
        )
        val sortOrder =
            "${MediaStore.Images.Media.DATE_ADDED} DESC, ${MediaStore.Images.Media._ID} DESC"
        val selection = if (bucketId.isNullOrEmpty()) null
        else "${MediaStore.Images.Media.BUCKET_ID} = ?"
        val selectionArgs = if (bucketId.isNullOrEmpty()) null else arrayOf(bucketId)
        val cursor = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Android 11+ 的分页：LIMIT/OFFSET 走 Bundle 参数，不需要拼 SQL 字符串。
            val args = Bundle().apply {
                putInt(ContentResolver.QUERY_ARG_OFFSET, offset)
                putInt(ContentResolver.QUERY_ARG_LIMIT, limit)
                putString(ContentResolver.QUERY_ARG_SQL_SORT_ORDER, sortOrder)
                if (selection != null && selectionArgs != null) {
                    putString(ContentResolver.QUERY_ARG_SQL_SELECTION, selection)
                    putStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, selectionArgs)
                }
            }
            resolver.query(collection, projection, args, null)
        } else {
            resolver.query(
                collection,
                projection,
                selection,
                selectionArgs,
                "$sortOrder LIMIT $limit OFFSET $offset",
            )
        } ?: return emptyList()

        val images = ArrayList<Map<String, Any?>>()
        cursor.use { rows ->
            val pathIndex = rows.getColumnIndex(MediaStore.Images.Media.DATA)
            val nameIndex = rows.getColumnIndex(MediaStore.Images.Media.DISPLAY_NAME)
            val sizeIndex = rows.getColumnIndex(MediaStore.Images.Media.SIZE)
            val dateIndex = rows.getColumnIndex(MediaStore.Images.Media.DATE_ADDED)
            if (pathIndex < 0) return emptyList()
            while (rows.moveToNext()) {
                val path = rows.getString(pathIndex)?.trim()
                if (path.isNullOrEmpty()) continue
                val name = if (nameIndex >= 0) rows.getString(nameIndex) ?: "" else ""
                val size = if (sizeIndex >= 0) rows.getLong(sizeIndex) else 0L
                // MediaStore 的 DATE_ADDED 是秒，统一换成毫秒给 Dart。
                val addedSeconds = if (dateIndex >= 0) rows.getLong(dateIndex) else 0L
                images.add(
                    mapOf(
                        "path" to path,
                        "name" to name,
                        "size" to size,
                        "dateAdded" to addedSeconds * 1000L,
                    ),
                )
            }
        }
        return images
    }

    /**
     * 相册分类（目录）列表，按张数从多到少。
     *
     * 为什么不用 `GROUP BY`：MediaStore 的分组查询在部分 ROM（华为 EMUI）上
     * 会漏掉 `BUCKET_DISPLAY_NAME`，拼出来的名字是空的。这里按时间倒序扫一遍
     * 全表（只有 4 列、一次索引扫描，上万张也就几十毫秒，且跑在后台线程），
     * 用"第一次遇到即封面"的方式归组，结果稳定。
     */
    fun buckets(context: Context): Map<String, Any?> {
        val resolver: ContentResolver = context.contentResolver
        val collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Images.Media.BUCKET_ID,
            MediaStore.Images.Media.BUCKET_DISPLAY_NAME,
            MediaStore.Images.Media.DATA,
            MediaStore.Images.Media.DATE_ADDED,
        )
        val sortOrder = "${MediaStore.Images.Media.DATE_ADDED} DESC"
        val cursor = try {
            resolver.query(collection, projection, null, null, sortOrder)
        } catch (error: Exception) {
            null
        } ?: return mapOf("total" to 0, "buckets" to emptyList<Map<String, Any?>>())

        val grouped = LinkedHashMap<String, MutableMap<String, Any?>>()
        var total = 0
        cursor.use { rows ->
            val idIndex = rows.getColumnIndex(MediaStore.Images.Media.BUCKET_ID)
            val nameIndex = rows.getColumnIndex(MediaStore.Images.Media.BUCKET_DISPLAY_NAME)
            val pathIndex = rows.getColumnIndex(MediaStore.Images.Media.DATA)
            while (rows.moveToNext()) {
                total += 1
                val bucketId = if (idIndex >= 0) rows.getString(idIndex)?.trim() ?: "" else ""
                val displayName = if (nameIndex >= 0) rows.getString(nameIndex)?.trim() ?: "" else ""
                val path = if (pathIndex >= 0) rows.getString(pathIndex)?.trim() ?: "" else ""
                val key = if (bucketId.isNotEmpty()) bucketId else displayName
                if (key.isEmpty()) continue
                val entry = grouped[key]
                if (entry == null) {
                    // 时间倒序 → 每个目录第一张就是最新一张，天然是封面。
                    grouped[key] = mutableMapOf<String, Any?>(
                        "id" to bucketId,
                        "name" to displayName,
                        "count" to 1,
                        "cover" to path,
                    )
                } else {
                    entry["count"] = ((entry["count"] as? Int) ?: 1) + 1
                }
            }
        }
        return mapOf(
            "total" to total,
            "buckets" to grouped.values.sortedByDescending { entry ->
                (entry["count"] as? Int) ?: 0
            },
        )
    }
}
