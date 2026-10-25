package me.rain.mtforum.core.data

import android.content.Context
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import org.jsoup.nodes.Node
import org.jsoup.nodes.TextNode
import java.io.IOException
import java.net.URI
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Data is a JSON document in the body of a publicly shared Weiyun/QQ Collection note. */
internal data class UpdateRelease(
    val versionName: String,
    val versionCode: Long,
    val title: String,
    val releaseDate: String,
    val changelog: List<String>,
    val downloadUrl: String?,
    val downloadPageUrl: String?,
    val fileSizeBytes: Long,
    val sha256: String,
    val forceUpdate: Boolean,
    val minSupportedVersionCode: Long,
) {
    val preferredUrl: String? get() = downloadUrl ?: downloadPageUrl
    fun requiresUpdate(installedCode: Long): Boolean =
        forceUpdate || installedCode < minSupportedVersionCode
}

internal data class UpdateManifest(
    val enabled: Boolean,
    val release: UpdateRelease,
    val checkOnLaunch: Boolean,
    val intervalHours: Int,
    val allowSkipVersion: Boolean,
    val remindLaterHours: Int,
)

internal object UpdateManifestParser {
    /** Keep ONLY .note-content. Never evaluate scripts or trust page metadata. */
    fun extractJson(html: String): String? {
        val root = Jsoup.parse(html).selectFirst(".wy-notes-wrapper .note-content") ?: return null
        val result = StringBuilder()
        root.childNodes().forEach { append(it, result) }
        var json = result.toString().replace('\u00a0', ' ').trim()
        // Some QQ Collection exports double-escape &quot;/&nbsp;, and pasted
        // notes may contain Markdown-escaped underscores. Normalize only the
        // residual encodings, never execute any content.
        if (json.contains("&quot;") || json.contains("&nbsp;") || json.contains("&#34;")) {
            json = org.jsoup.parser.Parser.unescapeEntities(json, false)
                .replace('\u00a0', ' ')
        }
        json = json.replace("\\_", "_")
        return json.takeIf { it.startsWith('{') && it.endsWith('}') }
    }

    fun parse(json: String, appId: String): UpdateManifest {
        val data = try {
            JSONObject(json)
        } catch (e: Exception) {
            throw IOException("更新配置不是有效的 JSON", e)
        }
        if (data.optInt("schema_version", -1) != 1 || data.optString("app_id") != appId ||
            data.optString("channel", "stable") != "stable") {
            throw IOException("更新配置的格式、包名或发布渠道不匹配")
        }
        val latest = data.optJSONObject("latest") ?: throw IOException("更新配置缺少 latest")
        val versionCode = latest.optLong("version_code", 0)
        val versionName = latest.optString("version_name").trim()
        if (versionCode <= 0 || versionName.isBlank()) throw IOException("更新配置缺少有效版本号")
        val notes = latest.optJSONArray("changelog")
        val changelog = if (notes == null) emptyList() else (0 until notes.length())
            .mapNotNull { i -> notes.optString(i).trim().takeIf(String::isNotBlank) }
            .take(30)
        val options = data.optJSONObject("check")
        return UpdateManifest(
            enabled = data.optBoolean("enabled", true),
            release = UpdateRelease(
                versionName = versionName,
                versionCode = versionCode,
                title = latest.optString("title").trim().ifBlank { "MT Forum $versionName" },
                releaseDate = latest.optString("release_date"),
                changelog = changelog,
                downloadUrl = trustedExternalUrl(latest.optString("download_url")),
                downloadPageUrl = trustedExternalUrl(latest.optString("download_page_url")),
                fileSizeBytes = latest.optLong("file_size_bytes", 0).coerceAtLeast(0),
                sha256 = latest.optString("sha256").trim(),
                forceUpdate = latest.optBoolean("force_update", false),
                minSupportedVersionCode = latest.optLong("min_supported_version_code", 0),
            ),
            checkOnLaunch = options?.optBoolean("check_on_launch", true) ?: true,
            intervalHours = (options?.optInt("interval_hours", 24) ?: 24).coerceIn(1, 168),
            allowSkipVersion = options?.optBoolean("allow_skip_version", true) ?: true,
            remindLaterHours = (options?.optInt("remind_later_hours", 24) ?: 24).coerceIn(1, 720),
        )
    }

    /** Invalid or placeholder URLs are never made clickable or launched. */
    fun trustedExternalUrl(raw: String): String? = try {
        val value = raw.trim()
        val uri = URI(value)
        val host = uri.host?.lowercase().orEmpty()
        value.takeIf {
            uri.scheme.equals("https", true) && host.isNotEmpty() &&
                host !in setOf("example.com", "www.example.com", "localhost") &&
                !host.endsWith(".example.com") && uri.userInfo == null
        }
    } catch (_: Exception) { null }

    private fun append(node: Node, text: StringBuilder) {
        when (node) {
            is TextNode -> text.append(node.wholeText)
            is Element -> when (node.normalName()) {
                "br" -> text.append('\n')
                "script", "style", "noscript" -> Unit
                "p", "div", "li" -> {
                    node.childNodes().forEach { append(it, text) }
                    text.append('\n')
                }
                else -> node.childNodes().forEach { append(it, text) }
            }
            else -> Unit
        }
    }
}

internal class UpdateRepository(context: Context) {
    private val appContext = context.applicationContext
    private val prefs = appContext.getSharedPreferences("mtforum_update_checks", Context.MODE_PRIVATE)
    private val http = OkHttpClient.Builder()
        .connectTimeout(4, TimeUnit.SECONDS)
        .readTimeout(5, TimeUnit.SECONDS)
        .callTimeout(8, TimeUnit.SECONDS)
        // No CookieJar: do not send forum/Weiyun login cookies to a public note.
        .build()

    val installedVersion: String by lazy {
        val info = appContext.packageManager.getPackageInfo(appContext.packageName, 0)
        info.versionName.orEmpty()
    }
    val installedCode: Long by lazy {
        val info = appContext.packageManager.getPackageInfo(appContext.packageName, 0)
        info.longVersionCode
    }

    suspend fun fetch(): UpdateManifest = withContext(Dispatchers.IO) {
        val request = Request.Builder().url(ShareUrl)
            .header("Accept", "text/html")
            .header("User-Agent", "Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36")
            .build()
        try {
            http.newCall(request).execute().use { response ->
                if (!response.isSuccessful) throw IOException("更新检查 HTTP ${response.code}")
                val final = URI(response.request.url.toString())
                val host = final.host.orEmpty().lowercase()
                if (final.scheme != "https" || !(host == "sharechain.qq.com" || host == "weiyun.com" || host.endsWith(".weiyun.com"))) {
                    throw IOException("微云分享链接跳转到了未知网站")
                }
                val json = UpdateManifestParser.extractJson(response.body?.string().orEmpty())
                    ?: throw IOException("微云页面中没有找到更新 JSON")
                UpdateManifestParser.parse(json, appContext.packageName)
            }
        } catch (e: IOException) {
            throw e
        } catch (e: Exception) {
            throw IOException("无法读取微云更新配置", e)
        }
    }

    /** Automatic checks are bounded even without network access. */
    fun shouldAutoCheck(): Boolean =
        prefs.getBoolean("automatic_enabled", true) &&
            System.currentTimeMillis() - prefs.getLong("last_attempt", 0L) >=
            prefs.getInt("interval_hours", 24).coerceIn(1, 168) * 3_600_000L

    fun recordAutoAttempt(manifest: UpdateManifest?) {
        prefs.edit().putLong("last_attempt", System.currentTimeMillis())
            .apply {
                if (manifest != null) {
                    putBoolean("automatic_enabled", manifest.checkOnLaunch)
                    putInt("interval_hours", manifest.intervalHours)
                }
            }.apply()
    }

    fun canPrompt(manifest: UpdateManifest): Boolean {
        val release = manifest.release
        val force = release.requiresUpdate(installedCode)
        val newer = manifest.enabled && release.versionCode > installedCode
        return newer && release.preferredUrl != null &&
            (force || (prefs.getLong("remind_after", 0L) <= System.currentTimeMillis() &&
                (!manifest.allowSkipVersion || prefs.getLong("skip_code", 0L) != release.versionCode)))
    }

    fun remindLater(manifest: UpdateManifest) {
        prefs.edit().putLong("remind_after", System.currentTimeMillis() + manifest.remindLaterHours * 3_600_000L).apply()
    }

    fun skipVersion(manifest: UpdateManifest) {
        prefs.edit().putLong("skip_code", manifest.release.versionCode).apply()
    }

    companion object {
        const val ShareUrl = "https://sharechain.qq.com/3aeafde79cfedbbeaf7d95313ea095d9?qq_aio_chat_type=2"
    }
}
