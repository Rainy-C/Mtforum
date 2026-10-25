package me.rain.mtforum.core.network

import org.jsoup.nodes.Element

/** Strip Comiis icon-font glyphs and layout whitespace, never strip actual names or amounts. */
internal fun cleanAccountText(raw: String): String = raw
    .filterNot { it in '\uE000'..'\uF8FF' || it == '\u200B' || it == '\uFEFF' }
    .replace(Regex("[\\t\\u00a0 ]+"), " ")
    .replace(Regex("[ ]*([：:])[ ]*"), ": ")
    .replace(Regex("[ ]*\\n[ ]*"), "\n")
    .trim(' ', '\n', '·', '|')

/** Extract only values provided by server HTML. No invented currency or rank labels. */
internal fun parseAccountFacts(node: Element): List<ContentFact> {
    val cells = node.children().filter { it.tagName() == "td" || it.tagName() == "th" }
        .ifEmpty { node.children().flatMap { it.children() }
            .filter { it.tagName() == "td" || it.tagName() == "th" } }
    if (cells.size == 2) {
        val label = cleanAccountText(cells[0].text()).trimEnd('：', ':')
        val value = cleanAccountText(cells[1].text())
        if (label.isNotBlank() && value.isNotBlank()) return listOf(ContentFact(label, value))
    }
    if (cells.size >= 2) {
        return cells.take(6).mapIndexedNotNull { index, cell ->
            val value = cleanAccountText(cell.text())
            if (value.isBlank()) null else {
                val label = cleanAccountText(cell.attr("data-label"))
                    .ifBlank { cleanAccountText(cell.attr("title")) }
                    .ifBlank { "" }
                ContentFact(label, value)
            }
        }
    }
    val labels = node.select("dt, th, .credit-title, .jf_title")
    val values = node.select("dd, td, .credit-value, .jf_value")
    if (labels.isNotEmpty() && labels.size == values.size)
        return labels.zip(values).mapNotNull { (label, value) ->
            val l = cleanAccountText(label.text()).trimEnd('：', ':')
            val v = cleanAccountText(value.text())
            if (l.isBlank() || v.isBlank()) null else ContentFact(l, v)
        }.take(8)
    return emptyList()
}
