package me.rain.mtforum.core.data

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Environment
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.FileInputStream
import java.net.URI
import java.security.MessageDigest

internal const val ApkMimeType = "application/vnd.android.package-archive"

/** In-app installation is limited to this repository's HTTPS release APK with a known hash. */
internal fun canDownloadUpdateInApp(release: UpdateRelease): Boolean {
    if (!release.sha256.matches(Regex("[0-9a-fA-F]{64}")) || release.fileSizeBytes <= 0L) {
        return false
    }
    return try {
        val url = URI(release.downloadUrl ?: return false)
        url.scheme.equals("https", ignoreCase = true) &&
            url.host.equals("github.com", ignoreCase = true) &&
            url.port == -1 && url.userInfo == null &&
            url.path.startsWith(
                "/Rainy-C/Mtforum/releases/download/v" + release.versionName + "-build."
            ) &&
            url.path.endsWith("/MtForum-v" + release.versionName + "-release.apk")
    } catch (_: Exception) {
        false
    }
}

internal sealed interface ApkDownloadStatus {
    data class Progress(val downloaded: Long, val total: Long, val paused: Boolean) : ApkDownloadStatus
    data object Complete : ApkDownloadStatus
    data class Failed(val message: String) : ApkDownloadStatus
}

/** Uses the OS download service: download continues in background and appears in Downloads. */
internal class UpdateApkDownloader(context: Context) {
    private val manager = context.applicationContext.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager

    fun start(release: UpdateRelease): Long {
        require(canDownloadUpdateInApp(release)) { "缺少可信的 APK 地址或校验信息" }
        val filename = "MTForum-v" + release.versionName + "-" + System.currentTimeMillis() + ".apk"
        val request = DownloadManager.Request(Uri.parse(release.downloadUrl!!))
            .setTitle("MTForum " + release.versionName)
            .setDescription("正在下载应用更新")
            .setMimeType(ApkMimeType)
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, filename)
        return manager.enqueue(request)
    }

    fun status(id: Long): ApkDownloadStatus {
        val query = DownloadManager.Query().setFilterById(id)
        return manager.query(query)?.use { cursor ->
            if (!cursor.moveToFirst()) return@use ApkDownloadStatus.Failed("下载任务已不存在，请重新下载")
            fun int(column: String) = cursor.getInt(cursor.getColumnIndexOrThrow(column))
            fun long(column: String) = cursor.getLong(cursor.getColumnIndexOrThrow(column))
            when (int(DownloadManager.COLUMN_STATUS)) {
                DownloadManager.STATUS_SUCCESSFUL -> ApkDownloadStatus.Complete
                DownloadManager.STATUS_FAILED -> {
                    val reason = int(DownloadManager.COLUMN_REASON)
                    ApkDownloadStatus.Failed(
                        if (reason == DownloadManager.ERROR_INSUFFICIENT_SPACE) "存储空间不足，请清理后重试"
                        else "下载失败，请检查网络连接或改用浏览器下载"
                    )
                }
                DownloadManager.STATUS_PAUSED -> ApkDownloadStatus.Progress(
                    long(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR),
                    long(DownloadManager.COLUMN_TOTAL_SIZE_BYTES), true,
                )
                else -> ApkDownloadStatus.Progress(
                    long(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR),
                    long(DownloadManager.COLUMN_TOTAL_SIZE_BYTES), false,
                )
            }
        } ?: ApkDownloadStatus.Failed("无法读取下载状态，请从系统下载管理查看")
    }

    /** Never hand an unverified APK to Android's package installer. */
    suspend fun verifiedUri(id: Long, release: UpdateRelease): Uri = withContext(Dispatchers.IO) {
        require(canDownloadUpdateInApp(release)) { "更新文件的安全校验信息无效" }
        val digest = MessageDigest.getInstance("SHA-256")
        var bytes = 0L
        manager.openDownloadedFile(id).use { descriptor ->
            FileInputStream(descriptor.fileDescriptor).use { stream ->
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val read = stream.read(buffer)
                    if (read == -1) break
                    digest.update(buffer, 0, read)
                    bytes += read
                }
            }
        }
        val hash = digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
        if (bytes != release.fileSizeBytes || !hash.equals(release.sha256, ignoreCase = true)) {
            manager.remove(id)
            throw IllegalStateException("APK 大小或 SHA-256 不一致，已移除不安全的下载文件")
        }
        manager.getUriForDownloadedFile(id)
            ?: throw IllegalStateException("系统无法打开已下载的 APK，请重试")
    }

    fun cancel(id: Long) {
        manager.remove(id)
    }
}
