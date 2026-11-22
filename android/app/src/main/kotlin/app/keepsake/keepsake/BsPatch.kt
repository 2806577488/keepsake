package app.keepsake.keepsake

import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.Closeable
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.io.RandomAccessFile
import java.security.MessageDigest
import java.util.zip.Inflater
import java.util.zip.InflaterInputStream

/**
 * 纯 Java/Kotlin 的 bspatch 合并器（**无 NDK / 无 JNI / 无第三方库**）。
 *
 * ## 为什么不是「zip 差分」
 *
 * APK 用 APK Signature Scheme v2/v3 签名，签名覆盖**整个文件的字节**。
 * 按 zip 条目重新打包出来的 APK 与 CI 构建的产物不可能逐字节一致
 * （条目顺序、对齐填充、压缩级别、时间戳、签名块位置都会变），
 * 而客户端**没有私钥**可以重签 → 装上去必然 `INSTALL_FAILED_INVALID_APK`
 * 或「签名不一致」。所以只有「逐字节重建新 APK」的差分（bsdiff 语义）可行。
 *
 * ## 为什么压缩层是 zlib 而不是 bzip2
 *
 * 标准 bsdiff 补丁里的三段（ctrl / diff / extra）是 bzip2 压缩的，
 * 而 Java/Android 没有内置 bzip2 解码器；引第三方纯 Java 库要改
 * `android/app/build.gradle.kts` 并新增依赖（本项目约束不允许）。
 * 因此 CI 端用 `bsdiff` 生成标准补丁后，由 `tool/make_patch.py` 把三段
 * bzip2 **转码**成 zlib（raw deflate）并写成本文件读的 **KSD1 容器**：
 * 算法语义（ctrl/diff/extra 三个流 + 旧包随机读）与 bspatch 完全一致，
 * 只是压缩包格式换成了 JDK 自带的 `java.util.zip.Inflater`。
 *
 * ## KSD1 容器格式（小端）
 *
 * ```
 * 0..3    magic  "KSD1"
 * 4..11   newSize            int64   新 APK 字节数
 * 12..15  ctrlCompLen        uint32  ctrl 段压缩字节数
 * 16..19  ctrlRawLen         uint32  ctrl 段解压字节数
 * 20..23  diffCompLen        uint32
 * 24..27  diffRawLen         uint32
 * 28..31  extraCompLen       uint32
 * 32..35  extraRawLen        uint32
 * 36..    ctrl | diff | extra   三段各自的 raw deflate 数据
 * ```
 *
 * 三段在文件里的偏移由头部长度直接算出，所以每段可以**独立**开一个
 * `InflaterInputStream`（`Inflater` 会多读压缩流尾部的字节，独立开流后
 * 多读也无所谓），全程流式，不把整包读进内存 —— 32 位低端机也能合并
 * 40MB+ 的 APK。
 *
 * ctrl 段与 bsdiff 原文一致：每 24 字节一组 `(diffLen, extraLen, seek)`，
 * 均为 int64 小端；`seek` 可以为负。diff 段与旧包逐字节相加，extra 段原样写入。
 */
internal object BsPatch {

    /** 补丁格式不对 / 数据不完整 / 校验失败。消息可直接展示给用户。 */
    class PatchException(message: String) : Exception(message)

    private val MAGIC = byteArrayOf('K'.code.toByte(), 'S'.code.toByte(), 'D'.code.toByte(), '1'.code.toByte())

    /** 头部固定 36 字节（magic 4 + newSize 8 + 6 × uint32）。 */
    private const val HEADER_SIZE = 36L

    /** 读写块大小：64KB，兼顾 32 位机的堆与 IO 效率。 */
    private const val BLOCK = 64 * 1024

    /** 进度上报粒度：每 1MB 回调一次，避免刷爆 MethodChannel。 */
    private const val PROGRESS_STEP = 1024L * 1024L

    /** 新包大小上限（防御畸形补丁把磁盘写爆）。 */
    private const val MAX_NEW_SIZE = 512L * 1024 * 1024

    /**
     * 把 [patchFile] 套到 [oldApk] 上，逐字节还原新 APK 写到 [outFile]。
     *
     * @param expectedTargetSha256 期望的新 APK sha256（64 位十六进制，必填）；
     *   不一致时删除输出文件并抛 [PatchException]。
     * @param onProgress 已写入字节数 / 新包总字节数（每 1MB 一次）。
     * @return 新 APK 的 sha256（小写十六进制）。
     *
     * 失败时一律删除半截输出文件，**绝不**把没校验过的包交给安装器。
     */
    fun apply(
        oldApk: File,
        patchFile: File,
        outFile: File,
        expectedTargetSha256: String,
        onProgress: ((Long, Long) -> Unit)? = null,
    ): String {
        if (!oldApk.isFile) throw PatchException("已安装的 APK 读不到：${oldApk.path}")
        if (!oldApk.canRead()) throw PatchException("已安装的 APK 不可读：${oldApk.path}")
        if (!patchFile.isFile) throw PatchException("补丁文件不存在：${patchFile.path}")
        if (expectedTargetSha256.length != 64) {
            // 没有目标校验值就不允许合并：宁可不更新，也不能装一个来路不明的包。
            throw PatchException("缺少新包的 sha256 校验值，拒绝合并")
        }

        val header = readHeader(patchFile)
        val newSize = header.newSize
        if (newSize <= 0 || newSize > MAX_NEW_SIZE) {
            throw PatchException("补丁头里的新包大小不合法（$newSize 字节）")
        }

        val parent = outFile.parentFile
        if (parent != null && !parent.exists() && !parent.mkdirs()) {
            throw PatchException("创建输出目录失败：${parent.path}")
        }
        // 先写临时文件，校验通过后再改名，避免中断留下一个看起来正常的坏 APK。
        val temp = File(outFile.path + ".part")
        deleteQuietly(temp)
        deleteQuietly(outFile)

        val digest = MessageDigest.getInstance("SHA-256")
        var wrote = 0L
        var nextReport = 0L

        try {
            RandomAccessFile(oldApk, "r").use { old ->
                val oldLen = old.length()
                Section(patchFile, HEADER_SIZE, header.ctrlCompLen).use { ctrl ->
                    Section(patchFile, HEADER_SIZE + header.ctrlCompLen, header.diffCompLen).use { diff ->
                        val extraOffset = HEADER_SIZE + header.ctrlCompLen + header.diffCompLen
                        Section(patchFile, extraOffset, header.extraCompLen).use { extra ->
                            BufferedOutputStream(FileOutputStream(temp), BLOCK).use { out ->
                                var oldPos = 0L
                                val oldBuf = ByteArray(BLOCK)
                                val diffBuf = ByteArray(BLOCK)
                                val outBuf = ByteArray(BLOCK)

                                while (wrote < newSize) {
                                    val triple = ByteArray(24)
                                    readFully(ctrl.stream, triple, 24, "控制段")
                                    val diffLen = readInt64(triple, 0)
                                    val extraLen = readInt64(triple, 8)
                                    val seek = readInt64(triple, 16)
                                    if (diffLen < 0 || extraLen < 0) {
                                        throw PatchException("控制段长度非法（$diffLen / $extraLen）")
                                    }
                                    if (wrote + diffLen + extraLen > newSize) {
                                        throw PatchException("控制段越界：会把新包写超出声明大小")
                                    }

                                    // 1) diff 段与旧包叠加。旧包越界部分按 0 处理（bspatch 语义）。
                                    var left = diffLen
                                    while (left > 0) {
                                        val chunk = (if (left < BLOCK) left else BLOCK.toLong()).toInt()
                                        readFully(diff.stream, diffBuf, chunk, "diff 段")
                                        val avail = when {
                                            oldPos < 0 || oldPos >= oldLen -> 0
                                            else -> {
                                                val rest = oldLen - oldPos
                                                (if (rest < chunk) rest else chunk.toLong()).toInt()
                                            }
                                        }
                                        if (avail > 0) {
                                            old.seek(oldPos)
                                            readFully(old, oldBuf, avail, "旧包")
                                        }
                                        for (i in 0 until chunk) {
                                            val base = if (i < avail) oldBuf[i].toInt() and 0xFF else 0
                                            outBuf[i] = ((base + (diffBuf[i].toInt() and 0xFF)) and 0xFF).toByte()
                                        }
                                        out.write(outBuf, 0, chunk)
                                        digest.update(outBuf, 0, chunk)
                                        wrote += chunk
                                        oldPos += chunk
                                        left -= chunk
                                        if (wrote >= nextReport) {
                                            onProgress?.invoke(wrote, newSize)
                                            nextReport = wrote + PROGRESS_STEP
                                        }
                                    }

                                    // 2) extra 段原样写入（新增内容）。
                                    var leftExtra = extraLen
                                    while (leftExtra > 0) {
                                        val chunk = (if (leftExtra < BLOCK) leftExtra else BLOCK.toLong()).toInt()
                                        readFully(extra.stream, outBuf, chunk, "extra 段")
                                        out.write(outBuf, 0, chunk)
                                        digest.update(outBuf, 0, chunk)
                                        wrote += chunk
                                        leftExtra -= chunk
                                        if (wrote >= nextReport) {
                                            onProgress?.invoke(wrote, newSize)
                                            nextReport = wrote + PROGRESS_STEP
                                        }
                                    }

                                    // 3) ctrl 里的 seek：下一段从旧包的哪个位置继续读。
                                    oldPos += seek
                                }
                            }
                        }
                    }
                }
            }
        } catch (error: Throwable) {
            // 任何失败都不留残骸，并把原始原因往上报。
            deleteQuietly(temp)
            deleteQuietly(outFile)
            throw when (error) {
                is PatchException -> error
                is IOException -> PatchException("合并失败：读写补丁/安装包出错（${error.message}）")
                else -> PatchException("合并失败：${error.message ?: error::class.java.simpleName}")
            }
        }

        if (wrote != newSize) {
            deleteQuietly(temp)
            throw PatchException("合并结果大小不对（$wrote/$newSize 字节）")
        }

        val actual = hex(digest.digest())
        if (!actual.equals(expectedTargetSha256.trim(), ignoreCase = true)) {
            deleteQuietly(temp)
            throw PatchException(
                "合并出来的安装包校验失败（sha256 不匹配），已删除：期望 " +
                    "${expectedTargetSha256.take(12)}…，实际 ${actual.take(12)}…",
            )
        }

        onProgress?.invoke(newSize, newSize)
        if (outFile.exists()) deleteQuietly(outFile)
        if (!temp.renameTo(outFile)) {
            deleteQuietly(temp)
            throw PatchException("重命名合并结果失败：${outFile.path}")
        }
        return actual
    }

    /** 流式计算文件 sha256（小写十六进制）。 */
    fun sha256(file: File): String {
        if (!file.isFile) throw PatchException("文件不存在：${file.path}")
        val digest = MessageDigest.getInstance("SHA-256")
        val buf = ByteArray(BLOCK)
        FileInputStream(file).use { input ->
            while (true) {
                val read = input.read(buf)
                if (read <= 0) break
                digest.update(buf, 0, read)
            }
        }
        return hex(digest.digest())
    }

    // ---------------------------------------------------------------------
    // 内部实现
    // ---------------------------------------------------------------------

    private class Header(val newSize: Long, val ctrlCompLen: Long, val diffCompLen: Long, val extraCompLen: Long)

    /** 一段独立的 raw-deflate 输入流（偏移由头部算出，互不干扰）。 */
    private class Section(file: File, offset: Long, compLen: Long) : Closeable {
        private val raw = FileInputStream(file)
        private val inflater = Inflater(true)
        val stream: InflaterInputStream

        init {
            if (compLen <= 0) {
                raw.close()
                inflater.end()
                throw PatchException("补丁段长度为 0，补丁已损坏")
            }
            raw.channel.position(offset)
            stream = InflaterInputStream(BufferedInputStream(raw, BLOCK), inflater, BLOCK)
        }

        override fun close() {
            try {
                stream.close()
            } catch (ignored: Exception) {
                // 关闭失败不影响结论（补丁已经用完）。
            }
            try {
                inflater.end()
            } catch (ignored: Exception) {
                // 同上。
            }
            try {
                raw.close()
            } catch (ignored: Exception) {
                // 同上。
            }
        }
    }

    private fun readHeader(file: File): Header {
        val buf = ByteArray(HEADER_SIZE.toInt())
        FileInputStream(file).use { input ->
            val read = input.readNBytesCompat(buf, buf.size)
            if (read < buf.size) throw PatchException("补丁文件太短，不是 KSD1 补丁")
        }
        if (buf[0] != MAGIC[0] || buf[1] != MAGIC[1] || buf[2] != MAGIC[2] || buf[3] != MAGIC[3]) {
            throw PatchException("补丁格式不对（缺少 KSD1 标识）")
        }
        val newSize = readInt64(buf, 4)
        val ctrlComp = readUInt32(buf, 12)
        val ctrlRaw = readUInt32(buf, 16)
        val diffComp = readUInt32(buf, 20)
        val diffRaw = readUInt32(buf, 24)
        val extraComp = readUInt32(buf, 28)
        val extraRaw = readUInt32(buf, 32)
        if (ctrlRaw <= 0 || diffRaw < 0 || extraRaw < 0) {
            throw PatchException("补丁头里的段长度不合法")
        }
        val expectedLen = HEADER_SIZE + ctrlComp + diffComp + extraComp
        if (file.length() < expectedLen) {
            throw PatchException("补丁文件不完整（${file.length()}/$expectedLen 字节）")
        }
        return Header(newSize, ctrlComp, diffComp, extraComp)
    }

    private fun java.io.InputStream.readNBytesCompat(buf: ByteArray, len: Int): Int {
        var total = 0
        while (total < len) {
            val read = read(buf, total, len - total)
            if (read < 0) break
            total += read
        }
        return total
    }

    /** 从流里读满 [len] 字节；短读即补丁截断，显式报错。 */
    private fun readFully(input: java.io.InputStream, buf: ByteArray, len: Int, what: String) {
        var total = 0
        while (total < len) {
            val read = input.read(buf, total, len - total)
            if (read < 0) throw PatchException("补丁数据不完整（$what 只剩 $total/$len 字节）")
            total += read
        }
    }

    /** 从 [RandomAccessFile] 读满 [len] 字节（旧包读完就是损坏，显式报错）。 */
    private fun readFully(old: RandomAccessFile, buf: ByteArray, len: Int, what: String) {
        var total = 0
        while (total < len) {
            val read = old.read(buf, total, len - total)
            if (read < 0) throw PatchException("$what 读取不完整（需要 $len 字节，只读到 $total）")
            total += read
        }
    }

    private fun readInt64(buf: ByteArray, offset: Int): Long {
        var value = 0L
        for (i in 7 downTo 0) {
            value = (value shl 8) or (buf[offset + i].toLong() and 0xFF)
        }
        return value
    }

    private fun readUInt32(buf: ByteArray, offset: Int): Long {
        var value = 0L
        for (i in 3 downTo 0) {
            value = (value shl 8) or (buf[offset + i].toLong() and 0xFF)
        }
        return value
    }

    private fun hex(bytes: ByteArray): String {
        val sb = StringBuilder(bytes.size * 2)
        for (b in bytes) {
            val v = b.toInt() and 0xFF
            sb.append(HEX[v ushr 4]).append(HEX[v and 0x0F])
        }
        return sb.toString()
    }

    private val HEX = "0123456789abcdef".toCharArray()

    private fun deleteQuietly(file: File) {
        try {
            if (file.exists()) file.delete()
        } catch (ignored: Exception) {
            // 删不掉也不该盖住真正的错误。
        }
    }
}
