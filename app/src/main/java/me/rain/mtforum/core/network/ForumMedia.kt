package me.rain.mtforum.core.network

import android.content.Context
import android.net.Uri
import java.io.IOException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import okhttp3.*
import okhttp3.HttpUrl.Companion.toHttpUrl

/** Auth cookies are supplied only to the forum host, including across CDN redirects. */
class ForumMedia(private val repository: ForumRepository) {
    private val client =
        OkHttpClient.Builder()
            .cookieJar(repository.cookies)
            .addNetworkInterceptor { chain ->
                val url = chain.request().url
                if (url.scheme != "https" || url.host !in Hosts) throw IOException("下载地址不受支持")
                chain.proceed(chain.request())
            }
            .build()

    suspend fun save(context: Context, url: String, target: Uri, onProgress: (Long, Long) -> Unit) =
        withContext(Dispatchers.IO) {
            val parsed = url.toHttpUrl()
            if (
                parsed.host !in Hosts ||
                    parsed.scheme != "https" ||
                    parsed.username.isNotEmpty() ||
                    parsed.password.isNotEmpty()
            )
                throw ForumException("下载地址无效")
            suspendCancellableCoroutine<Unit> { continuation ->
                val call =
                    client.newCall(
                        Request.Builder()
                            .url(parsed)
                            .header("User-Agent", ForumRepository.UserAgent)
                            .header("Referer", ForumRepository.BaseUrl + "/")
                            .build()
                    )
                continuation.invokeOnCancellation { call.cancel() }
                call.enqueue(
                    object : Callback {
                        override fun onFailure(call: Call, e: IOException) {
                            if (continuation.isActive) continuation.resumeWith(Result.failure(e))
                        }

                        override fun onResponse(call: Call, response: Response) {
                            try {
                                response.use {
                                    if (!it.isSuccessful) throw ForumException("下载失败（${it.code}）")
                                    val body = it.body ?: throw ForumException("文件内容为空")
                                    if (
                                        it.header("Content-Type").orEmpty().contains("text/html") &&
                                            !it.header("Content-Disposition")
                                                .orEmpty()
                                                .contains("attachment", ignoreCase = true)
                                    )
                                        throw ForumException("论坛要求验证，请返回帖子刷新后重试")
                                    val total = body.contentLength()
                                    context.contentResolver.openOutputStream(target, "w")?.use {
                                        output ->
                                        body.byteStream().use { input ->
                                            val buffer = ByteArray(32768)
                                            var count: Int
                                            var size = 0L
                                            while (input.read(buffer).also { count = it } != -1) {
                                                if (!continuation.isActive)
                                                    throw IOException("下载已取消")
                                                size += count
                                                output.write(buffer, 0, count)
                                                onProgress(size, total)
                                            }
                                        }
                                    } ?: throw ForumException("无法保存到所选位置")
                                }
                                if (continuation.isActive)
                                    continuation.resumeWith(Result.success(Unit))
                            } catch (e: Exception) {
                                // CreateDocument returns a newly created document; remove an
                                // incomplete download.
                                runCatching { context.contentResolver.delete(target, null, null) }
                                if (continuation.isActive)
                                    continuation.resumeWith(Result.failure(e))
                            }
                        }
                    }
                )
            }
        }

    companion object {
        val Hosts = setOf(ForumRepository.Host, "cdn.binmt.cc", "oos.binmt.cc")
    }
}
