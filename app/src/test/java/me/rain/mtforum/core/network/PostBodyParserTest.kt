package me.rain.mtforum.core.network

import me.rain.mtforum.feature.forum.annotated
import org.junit.Assert.*
import org.junit.Test

class PostBodyParserTest {
    private fun text(html: String) = PostBodyParser.parse(html)
        .filter { it.kind == "text" }.joinToString("\n") { annotated(it.node) { _, _ -> }.text }

    @Test fun sourceIndentationAndBrAreNotDoubleCounted() {
        assertEquals("第一行\n第二行", text("\r\n  第一行<br />\r\n  第二行\r\n"))
        assertEquals("最近漫画软件大多都跑路了，我的 JM", text("最近漫画软件大多都跑路了，我的\r\n JM"))
    }

    @Test fun repeatedBreaksAndEmptyParagraphsCannotCreateHugeGaps() {
        val value = text("<div>前言</div>" + "<br />\r\n".repeat(20) + "<p></p><p>正文</p>")
        assertEquals("前言\n\n正文", value)
    }

    @Test fun imagesInLayoutTablesKeepTheirOriginalPosition() {
        val blocks = PostBodyParser.parse("""<p>图片前</p><table><tr><td><img src="/none.png" comiis_loadimages="https://cdn.binmt.cc/photo.jpg"></td></tr></table><p>图片后</p>""")
        assertEquals(listOf("text", "image", "text"), blocks.map { it.kind })
        assertEquals("https://cdn.binmt.cc/photo.jpg", blocks[1].image)
        assertEquals("图片前", annotated(blocks[0].node) { _, _ -> }.text)
        assertEquals("图片后", annotated(blocks[2].node) { _, _ -> }.text)
    }

    @Test fun actualTablesAndPreformattedCodeKeepTheirStructure() {
        val blocks = PostBodyParser.parse("<table><tr><td>A</td><td>B</td></tr></table><pre>if (x) {\n  return x;\n}</pre>")
        assertEquals(listOf("table", "code"), blocks.map { it.kind })
        assertTrue(blocks[1].node.wholeText().contains("\n  return"))
    }

    @Test fun adjacentInlineElementsStayTogetherWithTheirLinksAndStyles() {
        val block = PostBodyParser.parse("<b>来</b><span>了</span><a href='/thread-1-1-1.html'>嗷</a>").single()
        val value = annotated(block.node) { _, _ -> }
        assertEquals("来了嗷", value.text)
        assertTrue(value.spanStyles.isNotEmpty())
        assertFalse(value.getLinkAnnotations(0, value.length).isEmpty())
    }

    @Test fun zoomImagesWinOverThumbnailsAndBrokenComiisPrefixesAreRepaired() {
        val image = org.jsoup.Jsoup.parse("""<img src="/none.png" file="/thumb.jpg" zoomfile="https://bbs.binmt.cc/https://oos.binmt.cc/full.jpg">""").selectFirst("img")!!
        assertEquals("https://oos.binmt.cc/full.jpg", ContentParser.imageUrl(image))
        assertNull(ContentParser.imageUrl(org.jsoup.Jsoup.parse("<img src='/none.png'>").selectFirst("img")!!))
    }

    @Test fun discuzCodeBlockLinesAreJoinedWithRealNewlines() {
        val html =
            """<div class="blockcode"><div id="code_1"><ol><li>fun main() {</li><li>  println(1)</li><li>}</li></ol></div></div>"""
        val block = PostBodyParser.parse(html).single()
        assertEquals("code", block.kind)
        assertEquals("fun main() {\n  println(1)\n}", PostBodyParser.codeText(block.node))
    }

    @Test fun avatarsAreDroppedAndSmileysStayInline() {
        val blocks =
            PostBodyParser.parse(
                """<div>正文<img src="https://cdn.binmt.cc/uc_server/images/noavatar_middle.gif">""" +
                    """<img src="https://cdn.binmt.cc/static/image/smiley/comiis_tb/tb_10.png" smilieid="250">结束</div>"""
            )
        assertEquals(listOf("text"), blocks.map { it.kind })
        assertEquals("正文\uFFFC结束", annotated(blocks.single().node) { _, _ -> }.text)
    }

    @Test fun contentImagesStillBecomeTheirOwnBlocks() {
        val blocks = PostBodyParser.parse("""<div>前<img src="https://oos.binmt.cc/forum/a.jpg">后</div>""")
        assertEquals(listOf("text", "image", "text"), blocks.map { it.kind })
    }

    @Test fun orderedAndUnorderedListsKeepTheirMarkers() {
        assertEquals("1. 一\n2. 二", text("<ol><li>一</li><li>二</li></ol>"))
        assertEquals("• 一\n• 二", text("<ul><li>一</li><li>二</li></ul>"))
    }
}
