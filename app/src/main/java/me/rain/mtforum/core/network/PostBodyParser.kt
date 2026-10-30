package me.rain.mtforum.core.network

import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import org.jsoup.nodes.Node
import org.jsoup.nodes.TextNode

/** Browser whitespace rules: source indentation is not a user-authored line break. */
internal object PostBodyParser {
    data class Block(
        val kind: String,
        val node: Element,
        val image: String? = null,
        val align: String? = null,
        val link: String? = null,
    )

    // A locked-content notice in Comiis is commonly a `.comiis_quote`. It is NOT a
    // user quote: class-name-only classification displays misleading quote headings.
    private val gatedNotice = Regex(
        """如果您要查看本帖隐藏内容|本帖隐藏的内容.{0,42}(?:回复|登录|购买|查看|可见)|""" +
            """(?:回复后可见|回复可见|登录后可见|购买后可见|请回复.{0,18}查看|权限不足.{0,24}查看)|""" +
            """(?:内容已隐藏|此处内容已被隐藏|支付.{0,12}(?:金币|积分).{0,12}(?:查看|可见))""",
        RegexOption.IGNORE_CASE,
    )

    private fun isGatedNotice(element: Element): Boolean {
        if (element.hasClass("bb-hide") || element.hasAttr("data-hide") &&
            element.attr("data-hide") == "true") return true
        if (element.classNames().any {
                it.contains("showhide", true) || it.contains("locked", true) ||
                    it.equals("comiis_hide", true) || it.equals("comiis_hidebox", true)
            } &&
            element.text().length < 450) return true
        // Only promote a known *notice* container; do not classify an ordinary
        // quotation merely because it discusses hidden posts.
        val possibleNotice = element.classNames().any {
            it.equals("comiis_quote", true) || it.contains("hide", true) ||
                it.contains("needreply", true)
        }
        return possibleNotice && element.text().length < 320 && gatedNotice.containsMatchIn(element.text())
    }

    private fun codeClass(element: Element): Boolean {
        if (element.normalName() == "pre") return true
        if (element.id().matches(Regex("""code[_-]\d+""", RegexOption.IGNORE_CASE)) &&
            element.selectFirst("ol > li, pre, code") != null) return true
        if (element.hasAttr("data-language") || element.hasAttr("data-lang"))
            return element.selectFirst("ol > li, pre, code") != null
        return element.classNames().any { cls ->
            cls.lowercase() in setOf(
                "blockcode", "bb-code", "codeblock", "code-block", "codebox",
                "comiis_code", "comiis_codes", "comiis_codetext", "comiis_blockcode",
                "syntaxhighlighter", "highlight", "highlight-code",
            ) && (cls.lowercase() !in setOf("highlight", "highlight-code") ||
                element.selectFirst("ol > li, pre, code") != null)
        }
    }

    /**
     * Fallback for Discuz themes that drop the standard code wrapper but retain
     * the numbered `<ol><li>...</li></ol>` lines. Do not turn a normal ordered
     * list into code merely because it has several list items.
     */
    private fun looksLikeCodeList(node: Element): Boolean {
        if (node.normalName() != "ol") return false
        val lines = node.children().filter { it.normalName() == "li" }
        if (lines.size < 2 || lines.size != node.childrenSize() || lines.size > 5000) return false
        val samples = lines.take(24).map { it.wholeText().trim() }
        val unmistakable = Regex(
            """\b(?:suspend\s+fun|fun\s+\w+\s*\(|val\s+\w+\s*=|const\s+\w+|def\s+\w+\s*\(|public\s+class|import\s+[\w.]+|#include\s*[<"]|return\s+[^。；]+[;}]|client\.\w+\(|\w+\([^)]*\)\s*\{|\w+\.\w+\([^)]*\))"""
        )
        val syntax = Regex("""[{};]|//|=>|\b(?:runCatching|println|printf|return|throw|catch)\b""")
        return samples.any { unmistakable.containsMatchIn(it) } &&
            samples.count { syntax.containsMatchIn(it) || unmistakable.containsMatchIn(it) } >= 2
    }

    fun parse(html: String): List<Block> {
        val blocks = mutableListOf<Block>()
        var text = Element("div")
        val seenAttachmentLinks = mutableSetOf<String>()
        fun flush() {
            if (text.text().isNotBlank() || text.selectFirst("img") != null) {
                blocks += Block("text", text, align = text.attr("align").takeIf { it.isNotBlank() })
            }
            text = Element("div")
        }
        fun append(node: Node, wrappers: List<Element>) {
            var item = node.clone()
            for (wrapper in wrappers.asReversed()) {
                item = wrapper.shallowClone().appendChild(item)
            }
            text.appendChild(item)
        }
        fun line() {
            text.appendElement("br")
        }
        fun alignOf(element: Element): String? {
            val attr = element.attr("align").trim()
            if (attr in setOf("left", "center", "right")) return attr
            return Regex("""text-align\s*:\s*(left|center|right)""", RegexOption.IGNORE_CASE)
                .find(element.attr("style"))
                ?.groupValues
                ?.get(1)
        }
        val paragraphs = setOf("p", "div", "li", "h1", "h2", "h3", "h4", "section", "tr")
        fun attach(node: Element) {
            val link = PostAttachments.linkFrom(node)
            val identity = link?.let(PostAttachments::identity)
            if (identity == null || seenAttachmentLinks.add(identity)) {
                flush()
                blocks += Block("attachment", node.clone(), link = link)
            }
        }
        fun walk(node: Node, wrappers: List<Element> = emptyList(), listDepth: Int = 0) {
            if (node is TextNode) {
                val raw = node.wholeText
                if (raw.isBlank() && raw.any { it == '\r' || it == '\n' }) return
                var value = raw.replace('\u00a0', ' ').replace(Regex("[ \t\r\n]+"), " ")
                if (raw.startsWith('\n') || raw.startsWith('\r')) value = value.trimStart()
                if (raw.endsWith('\n') || raw.endsWith('\r')) value = value.trimEnd()
                if (value.isNotEmpty()) append(TextNode(value), wrappers)
                return
            }
            if (node !is Element) return
            val tag = node.normalName()
            if (tag in setOf("script", "style", "noscript") || node.hasAttr("hidden") ||
                Regex("display\\s*:\\s*none", RegexOption.IGNORE_CASE).containsMatchIn(node.attr("style"))) return
            when {
                (node.hasClass("bb-attachment") ||
                    (node.classNames().any { cls ->
                        listOf("attnm", "tattl", "pattl", "attach").any { cls.contains(it, true) }
                    } && PostAttachments.linkFrom(node) != null &&
                        node.select("a[href]").count { a ->
                            ContentParser.absolute(a.attr("href"))?.let(PostAttachments::isDownloadUrl) == true
                        } == 1 &&
                        node.text().length < 450)) -> {
                    attach(node)
                    return
                }
                tag == "a" && node.selectFirst("img")?.let(PostAttachments::isFileIcon) == true &&
                    ContentParser.absolute(node.attr("href"))?.let(PostAttachments::isDownloadUrl) == true -> {
                    attach(node)
                    return
                }
                tag == "img" -> {
                    if (PostAttachments.isFileIcon(node)) {
                        attach(PostAttachments.attachmentContainer(node) ?: node.parent() ?: node)
                        return
                    }
                    // Avatars never belong to the body; smileys stay inline with the text.
                    if (ContentParser.isAvatarImage(node)) return
                    if (ContentParser.isSmileyImage(node)) {
                        append(node, wrappers)
                        return
                    }
                    val url = ContentParser.imageUrl(node) ?: return
                    flush()
                    blocks += Block("image", node.clone(), url,
                        link = node.parent()?.takeIf { it.normalName() == "a" }?.attr("href")
                            ?.let { ContentParser.absolute(it) })
                    return
                }
                tag == "iframe" || tag == "embed" || tag == "video" || tag == "audio" ||
                    (tag == "object" && node.hasAttr("data")) -> {
                    val url = mediaUrl(node) ?: return
                    flush()
                    blocks += Block("media", node.clone(), url)
                    return
                }
                codeClass(node) || looksLikeCodeList(node) -> {
                    flush()
                    blocks += Block("code", node.clone())
                    return
                }
                isGatedNotice(node) || node.hasClass("bb-free") -> {
                    flush()
                    blocks += Block(if (node.hasClass("bb-free")) "free" else "hide", node.clone())
                    return
                }
                tag == "blockquote" || node.hasClass("quote") || node.hasClass("comiis_quote") ||
                    node.hasClass("bb-quote") -> {
                    flush()
                    blocks += Block("quote", node.clone())
                    return
                }
                tag == "table" && (node.hasClass("bb-table") ||
                    node.select("tr").any { it.children().count { cell -> cell.tagName() in setOf("td", "th") } > 1 }) -> {
                    flush()
                    blocks += Block("table", node.clone())
                    return
                }
                tag == "ol" || tag == "ul" -> {
                    val ordered = tag == "ol"
                    val type = node.attr("type").lowercase()
                    // `ul.comiis_img_list` is a gallery: its items are images, not bullet points.
                    val gallery = node.hasClass("comiis_img_list")
                    var index = 1
                    var first = true
                    for (child in node.children()) {
                        if (child.normalName() != "li") {
                            walk(child, wrappers, listDepth)
                            continue
                        }
                        if (gallery || child.text().isBlank()) {
                            child.childNodes().forEach { walk(it, wrappers, listDepth + 1) }
                        } else {
                            if (first) {
                                line()
                                first = false
                            }
                            val number = when {
                                !ordered -> "• "
                                type == "a" -> "${('a' + (index - 1) % 26)}. "
                                type == "i" -> "${index}. "
                                else -> "$index. "
                            }
                            append(TextNode("  ".repeat(listDepth) + number), wrappers)
                            child.childNodes().forEach { walk(it, wrappers, listDepth + 1) }
                            line()
                        }
                        index++
                    }
                    return
                }
                tag == "br" -> {
                    line()
                    return
                }
                tag == "hr" -> {
                    flush()
                    blocks += Block("divider", node.clone())
                    return
                }
            }
            val paragraph = tag in paragraphs
            val nodeAlignment = if (paragraph) alignOf(node) else null
            if (paragraph) {
                if (nodeAlignment != null) { flush(); text.attr("align", nodeAlignment) }
                else line()
            }
            val inline = tag in setOf(
                "b", "strong", "i", "em", "u", "s", "strike", "del", "a", "code", "span", "font",
                "h1", "h2", "h3", "h4"
            )
            val next = if (inline) wrappers + node else wrappers
            node.childNodes().forEach { walk(it, next, listDepth) }
            if (paragraph) {
                if (nodeAlignment != null) flush()
                else line()
            }
        }
        walk(Jsoup.parseBodyFragment(BBCodeParser.normalize(html)).body())
        flush()
        return blocks
    }

    /** Discuz renders `[code]` as one `<li>` per line; join them back with real newlines. */
    fun codeText(node: Element): String {
        val lines = if (node.normalName() == "ol") node.children().filter { it.normalName() == "li" }
            else node.select("ol > li")
        if (lines.isNotEmpty()) {
            return lines.joinToString("\n") { row ->
                // Some Discuz variants put a visible number in a separate label.
                val clean = row.clone()
                clean.select(".lineno, .line-number, .linenumber, .number, .line-num").remove()
                clean.wholeText().replace('\u00a0', ' ').trimEnd()
            }.trim('\n')
        }
        return node.wholeText().replace("\r\n", "\n").replace('\r', '\n').replace('\u00a0', ' ')
            .trim('\n')
    }

    private fun mediaUrl(element: Element): String? {
        val direct =
            listOf("src", "data")
                .firstNotNullOfOrNull { attr ->
                    element.attr(attr).trim().takeIf { it.isNotEmpty() }
                }
        val source = element.selectFirst("source")?.attr("src")?.trim()
        return ContentParser.absolute(listOfNotNull(direct, source).firstOrNull { it.isNotEmpty() } ?: return null)
    }
}
