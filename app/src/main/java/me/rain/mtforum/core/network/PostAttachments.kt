package me.rain.mtforum.core.network

import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import org.jsoup.Jsoup
import org.jsoup.nodes.Element

/** Discuz/Comiis attachment links and file-type icons are not full-width post photos. */
internal object PostAttachments {
    private val iconPath = Regex(
        """(?:/filetype/|/fileicon/|/attachicon/|/images/filetypes?/|/static/image/filetype/)""",
        RegexOption.IGNORE_CASE,
    )

    fun isFileIconUrl(url: String): Boolean = iconPath.containsMatchIn(url)

    fun isFileIcon(image: Element): Boolean =
        image.classNames().any { it.contains("filetype", ignoreCase = true) || it.contains("attachicon", ignoreCase = true) } ||
            listOf("src", "file", "zoomfile", "data-src", "comiis_loadimages")
                .any { isFileIconUrl(image.attr(it)) }

    fun isDownloadUrl(url: String): Boolean {
        val parsed = url.toHttpUrlOrNull() ?: return false
        return parsed.encodedPath.endsWith("attachment.php", ignoreCase = true) ||
            (parsed.encodedPath.endsWith("forum.php", ignoreCase = true) &&
                parsed.queryParameter("mod") == "attachment")
    }

    fun linkFrom(node: Element): String? =
        (listOf(node).filter { it.normalName() == "a" && it.hasAttr("href") } + node.select("a[href]"))
            .firstNotNullOfOrNull { a ->
                ContentParser.absolute(a.attr("href"))?.takeIf(::isDownloadUrl)
            }

    fun identity(url: String): String {
        val parsed = url.toHttpUrlOrNull() ?: return url.trim()
        val aid = parsed.queryParameter("aid")?.trim().orEmpty()
        // aid is unique for a Discuz attachment. Keep the full URL for links without aid.
        return if (aid.isNotEmpty()) "attachment:$aid" else parsed.toString()
    }

    fun visibleAdditionalLinks(html: String, links: List<ContentLink>): List<ContentLink> {
        val shown = Jsoup.parseBodyFragment(html).select("a[href]")
            .mapNotNull { ContentParser.absolute(it.attr("href")) }
            .filter(::isDownloadUrl)
            .map(::identity)
            .toSet()
        return links.filter { isDownloadUrl(it.url) }
            .distinctBy { identity(it.url) }
            .filterNot { identity(it.url) in shown }
    }

    /** Capture the smallest meaningful attachment wrapper, avoiding whole forum/gallery groups. */
    fun attachmentContainer(node: Element): Element? {
        val candidates = generateSequence(node.parent()) { it.parent() }.take(6).toList()
        return candidates.firstOrNull { parent ->
            val classes = parent.className().lowercase()
            val likely = parent.normalName() in setOf("dl", "li") ||
                listOf("attnm", "tattl", "pattl", "attach", "filetype").any { it in classes }
            likely && parent.text().length < 450 &&
                parent.select("a[href]").count { a ->
                    ContentParser.absolute(a.attr("href"))?.let(::isDownloadUrl) == true
                } == 1
        }
    }

    fun fileTitle(node: Element): String {
        val link = (listOf(node).filter { it.normalName() == "a" && it.hasAttr("href") } +
            node.select("a[href]")).firstOrNull { a ->
            ContentParser.absolute(a.attr("href"))?.let(::isDownloadUrl) == true
        }
        val explicit = link?.text()?.trim().orEmpty()
        val fallback = node.text().trim().ifBlank { node.attr("alt").trim() }
        val value = explicit.ifBlank { fallback }.replace(Regex("""\s+"""), " ")
        return value.take(110).ifBlank { "论坛附件" }
    }

    fun fileDetails(node: Element, title: String): String {
        val full = node.text().replace(Regex("""\s+"""), " ").trim()
        return full.removePrefix(title).trim(' ', '·', ',', '，').take(160)
    }
}
