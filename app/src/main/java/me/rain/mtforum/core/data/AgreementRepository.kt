package me.rain.mtforum.core.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import me.rain.mtforum.R
import okhttp3.OkHttpClient
import okhttp3.Request
import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import org.jsoup.nodes.Node
import org.jsoup.nodes.TextNode
import java.io.IOException
import java.net.URI
import java.security.MessageDigest
import java.util.concurrent.TimeUnit

/**
 * The agreement is a public Weiyun/QQ Collection note. Only the note body is used;
 * the surrounding page (navigation, JavaScript and tracking) is never rendered.
 */
internal data class AgreementDocument(
    val text: String,
    val digest: String,
    val source: AgreementSource,
    val updatedAt: String? = null,
)

internal enum class AgreementSource { Remote, Cached, Bundled }

internal data class ParsedAgreement(val text: String, val updatedAt: String?)

/** Pure parser, also exercised with a captured QQ Collection HTML response. */
internal object AgreementHtmlParser {
    fun parse(html: String): ParsedAgreement? {
        val doc = Jsoup.parse(html)
        // Do not use body().text(): that includes UI labels and can swallow line breaks.
        val note = doc.selectFirst(".wy-notes-wrapper .note-content") ?: return null
        val content = StringBuilder()
        note.childNodes().forEach { appendNote(it, content) }
        val text = normalize(content.toString())
        // Reject login, captcha, expired-share and generic error pages, rather than
        // allowing a user to accept an unrelated page as the privacy agreement.
        if (text.length < 400 || !text.contains("MT Forum") ||
            (!text.contains("隐私") && !text.contains("协议"))) return null
        val updatedAt = doc.selectFirst(".wy-notes-wrapper .note-time")
            ?.text()?.trim()?.takeIf { it.isNotEmpty() }
        return ParsedAgreement(text, updatedAt)
    }

    fun normalize(raw: String): String = raw.replace("\r\n", "\n").replace('\r', '\n')
        .replace('\u00a0', ' ')
        .lines().joinToString("\n") { it.trimEnd() }
        .replace(Regex("\n{3,}"), "\n\n").trim()

    private fun appendNote(node: Node, out: StringBuilder) {
        when (node) {
            is TextNode -> out.append(node.wholeText)
            is Element -> {
                when (node.normalName()) {
                    "script", "style", "noscript" -> Unit
                    "br" -> out.append('\n')
                    "p", "div", "section", "li", "h1", "h2", "h3", "h4" -> {
                        if (out.isNotEmpty() && out.last() != '\n') out.append('\n')
                        node.childNodes().forEach { appendNote(it, out) }
                        if (out.isNotEmpty() && out.last() != '\n') out.append('\n')
                    }
                    else -> node.childNodes().forEach { appendNote(it, out) }
                }
            }
            else -> Unit
        }
    }
}

internal class AgreementRepository(context: Context) {
    private val appContext = context.applicationContext
    private val cache = appContext.getSharedPreferences("weiyun_agreement", Context.MODE_PRIVATE)
    private val http = OkHttpClient.Builder()
        .connectTimeout(3, TimeUnit.SECONDS)
        .readTimeout(4, TimeUnit.SECONDS)
        .callTimeout(6, TimeUnit.SECONDS)
        // No CookieJar: do not send forum or QQ login cookies to the share page.
        .build()

    /** Return a readable document immediately, including if Weiyun is unavailable. */
    fun local(): AgreementDocument {
        val cached = cache.getString("body", null)?.let(AgreementHtmlParser::normalize)
        if (!cached.isNullOrBlank() && cached.length >= 400) {
            return document(cached, AgreementSource.Cached, cache.getString("updated_at", null))
        }
        val bundled = appContext.resources.openRawResource(R.raw.agreement_fallback)
            .bufferedReader(Charsets.UTF_8).use { it.readText() }
        return document(AgreementHtmlParser.normalize(bundled), AgreementSource.Bundled)
    }

    /** Refresh from the fixed, public share URL; on failure retain the last known copy. */
    suspend fun refresh(): AgreementDocument = withContext(Dispatchers.IO) {
        try {
            val request = Request.Builder().url(ShareUrl)
                .header("Accept", "text/html")
                .header("User-Agent", "Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36")
                .build()
            http.newCall(request).execute().use { response ->
                if (!response.isSuccessful) throw IOException("Agreement HTTP ${response.code}")
                val finalUrl = URI(response.request.url.toString())
                val host = finalUrl.host.orEmpty().lowercase()
                if (finalUrl.scheme != "https" ||
                    !(host == "sharechain.qq.com" || host == "weiyun.com" || host.endsWith(".weiyun.com"))) {
                    throw IOException("Unexpected agreement redirect")
                }
                val html = response.body?.string() ?: throw IOException("Empty share page")
                val parsed = AgreementHtmlParser.parse(html)
                    ?: throw IOException("Agreement note not present in share page")
                cache.edit().putString("body", parsed.text)
                    .putString("updated_at", parsed.updatedAt).apply()
                document(parsed.text, AgreementSource.Remote, parsed.updatedAt)
            }
        } catch (_: IOException) {
            local()
        } catch (_: IllegalArgumentException) {
            local()
        }
    }

    private fun document(text: String, source: AgreementSource, updatedAt: String? = null) =
        AgreementDocument(text, fingerprint(text), source, updatedAt)

    companion object {
        const val ShareUrl =
            "https://sharechain.qq.com/0f7d3be5e1896ed5a7c5ff7b6f009def?qq_aio_chat_type=2"

        // Visual formatting alone is not a substantive agreement change.
        // Keep the consent checksum tied to what the user actually reads.
        fun fingerprint(text: String): String = MessageDigest.getInstance("SHA-256")
            .digest(AgreementHtmlParser.normalize(AgreementMarkup.parse(text).text).toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
    }
}
