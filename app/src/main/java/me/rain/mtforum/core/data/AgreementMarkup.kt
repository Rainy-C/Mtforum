package me.rain.mtforum.core.data

/**
 * Small, non-HTML formatting language for the remotely hosted agreement.
 *
 * Supported, case-insensitive pairs:
 * [red], [highlight] / [mark] / [yellow], [b], [u], [h1], [h2],
 * [color=red|#RRGGBB], [bg=yellow|#RRGGBB], [backcolor=...].
 * Prefer explicit closing tags (e.g. [/red]); [red]text[red] is also accepted.
 * A missing or malformed closing tag remains literal, so policy text is never lost.
 * Prefix a literal tag with a backslash: \\[red] becomes [red].
 */
internal enum class AgreementStyle { Red, Highlight, Bold, Underline, Heading1, Heading2, Foreground, Background }

internal data class AgreementSpan(
    val start: Int,
    val end: Int,
    val style: AgreementStyle,
    val argument: String? = null,
)

internal data class FormattedAgreement(val text: String, val spans: List<AgreementSpan>)

internal object AgreementMarkup {
    private val tagPattern = Regex("""\[(/?)([a-zA-Z][a-zA-Z0-9]*)(?:=([^\]\r\n]{1,64}))?\]""")
    private val rgbPattern = Regex("""#[0-9a-fA-F]{6}""")
    private val namedColors = setOf("red", "orange", "yellow", "green", "blue", "purple", "gray", "grey")

    private data class Tag(
        val start: Int,
        val end: Int,
        val name: String,
        val closing: Boolean,
        val style: AgreementStyle,
        val argument: String?,
    )

    fun parse(source: String): FormattedAgreement {
        val tags = tagPattern.findAll(source).mapNotNull { match ->
            val name = match.groupValues[2].lowercase()
            val closing = match.groupValues[1].isNotEmpty()
            val rawArg = match.groupValues[3].trim()
            if (isEscaped(source, match.range.first)) return@mapNotNull null
            val style = styleFor(name) ?: return@mapNotNull null
            // Closing tags cannot have parameters; unsupported values remain literal.
            if ((closing && rawArg.isNotEmpty()) ||
                (!closing && (style == AgreementStyle.Foreground || style == AgreementStyle.Background) && !validColor(rawArg)) ||
                (!closing && style != AgreementStyle.Foreground && style != AgreementStyle.Background && rawArg.isNotEmpty())
            ) return@mapNotNull null
            Tag(match.range.first, match.range.last + 1, name, closing, style, rawArg.ifEmpty { null })
        }.toList()

        // Validate pairs before removing syntax, so unmatched [red] remains readable.
        val paired = HashSet<Int>()
        val open = ArrayList<Int>()
        tags.forEachIndexed { index, tag ->
            val top = open.lastOrNull()?.let(tags::get)
            val symmetricClose = !tag.closing && tag.name == "red" && top?.name == "red"
            if (tag.closing || symmetricClose) {
                if (top?.name == tag.name) {
                    paired += open.removeAt(open.lastIndex)
                    paired += index
                }
            } else {
                open += index
            }
        }

        val visible = StringBuilder(source.length)
        val active = ArrayList<Pair<Tag, Int>>()
        val spans = ArrayList<AgreementSpan>()
        var offset = 0
        tags.forEachIndexed { index, tag ->
            appendLiteral(source, offset, tag.start, visible)
            if (index !in paired) {
                appendLiteral(source, tag.start, tag.end, visible)
            } else {
                val isEnd = tag.closing || (tag.name == "red" && active.lastOrNull()?.first?.name == "red")
                if (isEnd) {
                    val (opener, from) = active.removeAt(active.lastIndex)
                    if (visible.length > from) spans += AgreementSpan(from, visible.length, opener.style, opener.argument)
                } else {
                    active += tag to visible.length
                }
            }
            offset = tag.end
        }
        appendLiteral(source, offset, source.length, visible)
        return FormattedAgreement(visible.toString(), spans)
    }

    private fun appendLiteral(source: String, start: Int, end: Int, out: StringBuilder) {
        var index = start
        while (index < end) {
            // Strip one escape slash from literal formatting examples.
            if (source[index] == '\\' && index + 1 < end && source[index + 1] == '[') index++
            out.append(source[index++])
        }
    }

    private fun isEscaped(source: String, tagStart: Int): Boolean {
        var slashes = 0
        var i = tagStart - 1
        while (i >= 0 && source[i] == '\\') { slashes++; i-- }
        return slashes % 2 != 0
    }

    private fun validColor(color: String) = color.lowercase() in namedColors || rgbPattern.matches(color)

    private fun styleFor(name: String): AgreementStyle? = when (name) {
        "red" -> AgreementStyle.Red
        "highlight", "mark", "yellow" -> AgreementStyle.Highlight
        "b", "bold" -> AgreementStyle.Bold
        "u" -> AgreementStyle.Underline
        "h1", "title" -> AgreementStyle.Heading1
        "h2", "subtitle" -> AgreementStyle.Heading2
        "color" -> AgreementStyle.Foreground
        "bg", "backcolor" -> AgreementStyle.Background
        else -> null
    }
}
