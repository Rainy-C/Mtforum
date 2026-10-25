package me.rain.mtforum.core.network

import org.jsoup.Jsoup
import org.junit.Assert.*
import org.junit.Test

class BBCodeCompatibilityTest {
    @Test fun rawTextStylesAndNestedLinksArePreserved() {
        val html = BBCodeParser.toHtml("[color=red][b]红色加粗[/color][/b] [url=https://example.com][b]链接[/b][/url]")
        val parsed = Jsoup.parseBodyFragment(html)
        assertEquals("红色加粗", parsed.selectFirst("span b")?.text())
        assertEquals("链接", parsed.selectFirst("a b")?.text())
        assertEquals("https://example.com", parsed.selectFirst("a")?.attr("href"))
    }

    @Test fun rawBackgroundTablesAndMergedCellsKeepMarkup() {
        val input = "[table][tr][td][b]表头[/b][/td][td]表头2[/td][/tr]" +
            "[tr][td][color=red]红[/color][/td][td][backcolor=green]绿[/backcolor][/td][/tr][/table]"
        val blocks = PostBodyParser.parse(input)
        assertEquals(listOf("table"), blocks.map { it.kind })
        assertEquals(4, blocks.single().node.select("td").size)
        assertTrue(blocks.single().node.select("td").last()!!.html().contains("background-color"))
        val doc = Jsoup.parse("<table><tr><td rowspan=2>A</td><td>B</td></tr><tr><td>C</td></tr></table>")
        // Native table model is checked in forum UI tests.
        assertEquals(3, doc.select("td").size)
    }

    @Test fun codeExampleKeepsIndentationAndAngleBrackets() {
        val code = "[code]#include <stdio.h>\nint main() {\n  return 0;\n}[/code]"
        val blocks = PostBodyParser.parse(code)
        assertEquals("code", blocks.single().kind)
        assertTrue(PostBodyParser.codeText(blocks.single().node).contains("  return 0;"))
        assertTrue(PostBodyParser.codeText(blocks.single().node).contains("<stdio.h>"))
    }

    @Test fun listLettersQuotesHrAndMedia() {
        val blocks = PostBodyParser.parse("[list=a][*]甲[*]乙[/list][hr][quote]引文[img]https://example.com/a.png[/img][/quote]")
        assertEquals(listOf("text", "divider", "quote"), blocks.map { it.kind })
        assertTrue(blocks[0].node.text().contains("a. 甲"))
        assertTrue(blocks[2].node.selectFirst("img") != null)
    }

    @Test fun convertedHtmlIsNotConvertedTwice() {
        val html = "<p>教程示例：[color=red]文字[/color]</p>"
        assertEquals(html, BBCodeParser.normalize(html))
    }

    @Test fun unsafeUrlsCannotCreateLinks() {
        val html = BBCodeParser.toHtml("[url=javascript:alert(1)]点我[/url][img]javascript:alert(1)[/img]")
        assertTrue(Jsoup.parseBodyFragment(html).select("a, img").isEmpty())
    }
}
