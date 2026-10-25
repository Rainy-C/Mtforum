package me.rain.mtforum.core.network

import org.jsoup.nodes.Entities

/**
 * Compatibility path for posts supplied as *raw* BBCode. Ordinary Discuz responses have already
 * converted BBCode to HTML and must not be processed a second time (tutorials may quote tags).
 * This intentionally does not download attachments or bypass [hide] permissions.
 */
internal object BBCodeParser {
    private val tag = Regex("""\[(/?)([a-zA-Z*]+)(?:=([^\]]+))?]""")
    private val supported = setOf(
        "b", "i", "u", "s", "color", "backcolor", "size", "font", "img", "audio", "media",
        "attach", "attachimg", "quote", "hr", "list", "*", "align", "hide", "url", "code", "free",
        "email", "qq", "table", "tr", "td", "th",
    )
    private val htmlTag = Regex("""</?(?:div|p|span|font|b|strong|i|em|u|s|del|a|img|audio|video|iframe|object|pre|code|blockquote|ul|ol|li|table|tr|td|th|br|hr|section|h[1-6]|body|html)\b[^>]*>""", RegexOption.IGNORE_CASE)
    private val rawTag = Regex("""\[(?:/?(?:b|i|u|s|code|table|quote|img|color|backcolor|size|list|align|hide|media|audio|font|free|url|attach|attachimg|email|qq|tr|td|th|hr))(?=[=\]\s])""", RegexOption.IGNORE_CASE)

    fun normalize(input: String): String {
        if (htmlTag.containsMatchIn(input) || !rawTag.containsMatchIn(input)) return input
        return toHtml(input)
    }

    private data class Open(val name: String, val htmlTag: String)

    fun toHtml(source: String): String {
        val raw = source.replace("[/\u200b", "[/")
        val out = StringBuilder(raw.length + 128)
        val stack = mutableListOf<Open>()
        var position = 0
        val tokens = tag.findAll(raw).iterator()
        fun escape(value: String): String = Entities.escape(value)
        fun open(name: String, element: String, attributes: String = "") {
            out.append('<').append(element).append(attributes).append('>')
            stack.add(Open(name, element))
        }
        fun close(name: String) {
            val idx = stack.indexOfLast { it.name == name }
            if (idx < 0) return
            for (i in stack.lastIndex downTo idx) out.append("</").append(stack.removeAt(i).htmlTag).append('>')
        }
        while (tokens.hasNext()) {
            val match = tokens.next()
            if (match.range.first < position) continue
            val name = match.groupValues[2].lowercase()
            if (name !in supported) continue
            out.append(escape(raw.substring(position, match.range.first)))
            position = match.range.last + 1
            val param = match.groupValues.getOrNull(3).orEmpty().trim().trim('"', '\'')
            if (match.groupValues[1] == "/") {
                close(name)
                continue
            }
            when (name) {
                "b" -> open(name, "b")
                "i" -> open(name, "i")
                "u" -> open(name, "u")
                "s" -> open(name, "s")
                "quote" -> open(name, "blockquote", " class=\"bb-quote\"")
                "free" -> open(name, "div", " class=\"bb-free\"")
                "hide" -> open(name, "div", " class=\"bb-hide\"")
                "table" -> open(name, "table", " class=\"bb-table\"")
                "tr" -> open(name, "tr")
                "td", "th" -> open(name, name)
                "color", "backcolor", "size", "font" -> {
                    val css = when (name) {
                        "color" -> "color"
                        "backcolor" -> "background-color"
                        "size" -> "font-size"
                        else -> "font-family"
                    }
                    val value = when (name) {
                        "size" -> (param.toIntOrNull()?.coerceIn(1, 7)?.let { listOf(12, 14, 16, 18, 24, 32, 40)[it - 1] }?.let { "${it}px" })
                        "font" -> param.takeIf { it.matches(Regex("""[\p{L}\p{N} ,_\-]{1,60}""")) }
                        else -> param.takeIf { it.matches(Regex("""#[0-9a-fA-F]{3,8}|[a-zA-Z]{2,24}""")) }
                    }
                    if (value != null) open(name, "span", " style=\"$css:${escape(value)}\"")
                    else open(name, "span")
                }
                "align" -> open(name, "div", " style=\"text-align:${if (param in setOf("left", "right", "center")) param else "left"}\"")
                "list" -> open(name, if (param.isBlank()) "ul" else "ol", if (param.lowercase() in setOf("a", "i")) " type=\"${param.lowercase()}\"" else "")
                "*" -> {
                    if (stack.any { it.name == "list" }) {
                        close("*")
                        open(name, "li")
                    } else out.append("[*]")
                }
                "hr" -> out.append("<hr>")
                "code" -> {
                    val end = raw.indexOf("[/code]", position, ignoreCase = true)
                    if (end >= 0) {
                        out.append("<pre class=\"bb-code\"")
                        if (param.matches(Regex("""[A-Za-z0-9+#_-]{1,20}"""))) out.append(" data-language=\"").append(param).append('"')
                        out.append(">").append(escape(raw.substring(position, end))).append("</pre>")
                        position = end + 7
                    } else out.append("[code]")
                }
                "url", "email" -> {
                    val closing = "[/$name]"
                    val end = raw.indexOf(closing, position, ignoreCase = true)
                    val plain = raw.substring(position, if (end < 0) raw.length else end)
                    val address = if (name == "url") ContentParser.absolute(param.ifBlank { plain.trim() })
                        else param.ifBlank { plain.trim() }.takeIf {
                            it.matches(Regex("""[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}"""))
                        }?.let { "mailto:$it" }
                    if (address != null) open(name, "a", " href=\"${escape(address)}\"")
                    else open(name, "span")
                }
                "img", "audio", "media", "qq", "attach", "attachimg" -> {
                    val endTag = "[/$name]"
                    val end = raw.indexOf(endTag, position, ignoreCase = true)
                    if (end < 0) { out.append(escape(match.value)); continue }
                    val body = raw.substring(position, end).trim()
                    position = end + endTag.length
                    when (name) {
                        "img" -> {
                            val address = ContentParser.absolute(if (body.startsWith("http://")) "https://" + body.removePrefix("http://") else body)
                            if (address != null) out.append("<img src=\"${escape(address)}\">") else out.append(escape(body))
                        }
                        "audio", "media" -> {
                            val address = ContentParser.absolute(body)
                            val parts = param.split(',')
                            val width = parts.getOrNull(1)?.trim()?.toIntOrNull()?.coerceIn(1, 1200)
                            val height = parts.getOrNull(2)?.trim()?.toIntOrNull()?.coerceIn(1, 900)
                            val dims = if (width != null && height != null) " data-bb-width=\"$width\" data-bb-height=\"$height\"" else ""
                            if (address != null) out.append("<${if (name == "audio") "audio" else "video"} src=\"${escape(address)}\"$dims controls></${if (name == "audio") "audio" else "video"}>")
                            else out.append(escape(body))
                        }
                        "attach", "attachimg" -> out.append("<span class=\"bb-attachment\">附件 #${escape(body)}</span>")
                        "qq" -> if (body.matches(Regex("[0-9]{5,15}"))) out.append("<a href=\"mqqwpa://im/chat?chat_type=wpa&amp;uin=$body\">${escape(body)}</a>") else out.append(escape(body))
                    }
                }
            }
        }
        out.append(escape(raw.substring(position)))
        for (i in stack.lastIndex downTo 0) out.append("</").append(stack[i].htmlTag).append('>')
        return out.toString()
    }
}
