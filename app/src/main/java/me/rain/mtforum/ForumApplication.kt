package me.rain.mtforum

import android.app.Application
import android.webkit.CookieManager
import coil.ImageLoader
import coil.ImageLoaderFactory
import coil.intercept.Interceptor
import coil.request.CachePolicy
import coil.request.ImageResult
import java.io.IOException
import me.rain.mtforum.core.network.ContentParser
import me.rain.mtforum.core.network.ForumCookies
import me.rain.mtforum.core.network.ForumRepository
import okhttp3.OkHttpClient
import okhttp3.Dispatcher

/** Image requests share the forum session without sending its cookies to image hosts. */
class ForumApplication : Application(), ImageLoaderFactory {
    override fun newImageLoader(): ImageLoader {
        val client =
            OkHttpClient.Builder()
                .dispatcher(Dispatcher().apply {
                    maxRequests = 8
                    maxRequestsPerHost = 4
                })
                .cookieJar(ForumCookies(CookieManager.getInstance()))
                .retryOnConnectionFailure(false)
                .addInterceptor { chain ->
                    chain.proceed(
                        chain
                            .request()
                            .newBuilder()
                            .header("User-Agent", ForumRepository.UserAgent)
                            .header("Referer", ForumRepository.BaseUrl + "/")
                            .build()
                    )
                }
                .addNetworkInterceptor { chain ->
                    val url = chain.request().url
                    if (
                        url.scheme != "https" ||
                            (url.host == ForumRepository.Host &&
                                ContentParser.isMutationUrl(url.toString()))
                    ) {
                        throw IOException("图片地址无效")
                    }
                    chain.proceed(chain.request())
                }
                .build()
        return ImageLoader.Builder(this)
            .okHttpClient(client)
            .components {
                add(
                    object : Interceptor {
                        override suspend fun intercept(chain: Interceptor.Chain): ImageResult {
                            val data = chain.request.data.toString()
                            val forumImage =
                                runCatching {
                                        android.net.Uri.parse(data).host == ForumRepository.Host
                                    }
                                    .getOrDefault(false)
                            val request =
                                if (forumImage)
                                    chain.request
                                        .newBuilder()
                                        .diskCachePolicy(CachePolicy.DISABLED)
                                        .memoryCachePolicy(CachePolicy.DISABLED)
                                        .build()
                                else chain.request
                            return chain.proceed(request)
                        }
                    }
                )
            }
            .build()
    }
}
