package me.rain.mtforum.core.network

import android.os.Handler
import android.os.Looper
import android.webkit.CookieManager
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl

/** One app-private cookie store for HTTP and verification/login WebViews. */
class ForumCookies(private val manager: CookieManager) : CookieJar {
    private val main = Handler(Looper.getMainLooper())

    override fun loadForRequest(url: HttpUrl): List<Cookie> {
        if (url.host != ForumRepository.Host) return emptyList()
        return header(url.toString()).split(';').mapNotNull { item ->
            val separator = item.indexOf('=')
            if (separator < 1) return@mapNotNull null
            runCatching {
                Cookie.Builder().name(item.substring(0, separator).trim())
                    .value(item.substring(separator + 1).trim())
                    .hostOnlyDomain(url.host).path("/").secure().build()
            }.getOrNull()
        }
    }

    override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
        if (url.host != ForumRepository.Host || cookies.isEmpty()) return
        check(Looper.myLooper() != Looper.getMainLooper())
        val saved = CountDownLatch(cookies.size)
        main.post {
            cookies.forEach { cookie ->
                manager.setCookie(url.toString(), cookie.toString()) { saved.countDown() }
            }
        }
        try {
            if (!saved.await(10, TimeUnit.SECONDS)) throw IOException("保存登录状态超时，请重试")
        } catch (error: InterruptedException) {
            Thread.currentThread().interrupt()
            throw IOException("保存登录状态已取消", error)
        }
    }

    fun header(url: String = ForumRepository.BaseUrl): String = manager.getCookie(url).orEmpty()

    fun hasSession(): Boolean {
        val names = header().split(';').mapNotNull { item ->
            val parts = item.trim().split('=', limit = 2)
            if (parts.size == 2 && parts[1].isNotEmpty()) parts[0] else null
        }.toSet()
        return "cQWy_2132_auth" in names && "cQWy_2132_saltkey" in names
    }

    /** Reset only account cookies; a completed WAF verification survives a retry. */
    suspend fun clearCore() {
        val names = cookieNames().filter { it.startsWith("cQWy_2132_") }.toSet() +
            setOf("cQWy_2132_auth", "cQWy_2132_saltkey")
        expire(names)
    }

    /** Same cleanup classification as the old client's CookieClassifier. */
    suspend fun clearWaf() {
        val exact = setOf("acw_sc__v2", "acw_tc", "cdn_sec_tc", "sec_tc", "aliyungf_tc", "ssxmod_itna", "ssxmod_itna2")
        val prefixes = listOf("acw_", "acwsc_", "aliyungf_", "ssxmod_", "__cdn")
        expire(cookieNames().filter { name ->
            val lower = name.lowercase()
            lower in exact || prefixes.any { lower.startsWith(it) }
        }.toSet())
    }

    private fun cookieNames(): List<String> = header().split(';').mapNotNull {
        it.substringBefore('=').trim().takeIf(String::isNotEmpty)
    }

    private suspend fun expire(names: Set<String>) {
        if (names.isEmpty()) return
        kotlinx.coroutines.suspendCancellableCoroutine<Unit> { continuation ->
            main.post {
                val domains = listOf("", "; Domain=${ForumRepository.Host}", "; Domain=.${ForumRepository.Host}", "; Domain=.binmt.cc")
                var remaining = names.size * domains.size
                for (name in names) for (domain in domains) {
                    manager.setCookie(ForumRepository.BaseUrl, "$name=; Max-Age=0; Path=/$domain") {
                        remaining--
                        if (remaining == 0 && continuation.isActive) continuation.resumeWith(Result.success(Unit))
                    }
                }
            }
        }
    }

    suspend fun clear() = kotlinx.coroutines.suspendCancellableCoroutine<Unit> { continuation ->
        manager.removeAllCookies {
            manager.flush()
            if (continuation.isActive) continuation.resumeWith(Result.success(Unit))
        }
    }

    fun flush() = manager.flush()
}
