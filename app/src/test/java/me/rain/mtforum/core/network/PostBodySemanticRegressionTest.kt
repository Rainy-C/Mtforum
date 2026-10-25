package me.rain.mtforum.core.network

import org.jsoup.Jsoup
import org.junit.Assert.*
import org.junit.Test

/** Regression samples model the current Comiis and Discuz post HTML, not a WebView. */
class PostBodySemanticRegressionTest {
    private val kotlinLines = """
        <ol>
          <li>suspend fun probe(client, url): Profile {</li>
          <li>    val html = runCatching {</li>
          <li>        client.newCall(req).execute()   // 阻塞式 IO</li>
          <li>    }</li>
          <li>}</li>
        </ol>
    """.trimIndent()

    @Test fun comiisHiddenReplyPromptIsNotAQuote() {
        val prompt = """<div class="comiis_quote bg_h f_c">Cynnie，如果您要查看本帖隐藏内容请<a href="forum.php?mod=post&amp;action=reply">回复</a></div>"""
        val sections = PostBodyParser.parse(prompt)
        assertEquals(listOf("hide"), sections.map { it.kind })
        assertEquals("Cynnie，如果您要查看本帖隐藏内容请回复", sections.single().node.text())
        assertEquals("a", sections.single().node.selectFirst("a")?.normalName())
    }

    @Test fun realQuoteAboutHiddenPostsIsStillAQuote() {
        val quote = "<blockquote>这段讨论隐藏帖的引用应该保留</blockquote>"
        assertEquals("quote", PostBodyParser.parse(quote).single().kind)
        val actual = """<div class="comiis_quote"><div class="quotehead">回复 linbt 发表于 2026-10-25</div><div>原话</div></div>"""
        assertEquals("quote", PostBodyParser.parse(actual).single().kind)
    }

    @Test fun comiisCodeWrapperRestoresCodeInsteadOfListParagraphs() {
        val html = "<div class=\"comiis_codetext\"><div class=\"comiis_code\">$kotlinLines</div></div>"
        val blocks = PostBodyParser.parse(html)
        assertEquals(listOf("code"), blocks.map { it.kind })
        assertEquals("suspend fun probe(client, url): Profile {\n    val html = runCatching {\n        client.newCall(req).execute()   // 阻塞式 IO\n    }\n}", PostBodyParser.codeText(blocks.single().node))
    }

    @Test fun codeLikeOrderedListWithoutWrapperStillRestoresCode() {
        val block = PostBodyParser.parse(kotlinLines).single()
        assertEquals("code", block.kind)
        assertTrue(PostBodyParser.codeText(block.node).contains("client.newCall(req).execute()"))
    }

    @Test fun regularNumberedInstructionsRemainNumberedText() {
        val html = "<ol><li>下载安装软件</li><li>进入设置</li><li>点击保存</li></ol>"
        val blocks = PostBodyParser.parse(html)
        assertEquals(listOf("text"), blocks.map { it.kind })
        assertTrue(blocks.single().node.text().contains("1."))
    }

    @Test fun nestedQuotedRepliesDoNotBecomeHiddenOrCodeBlocks() {
        val html = """<blockquote>回复 某某 发表于 10-25<blockquote>上一条回复</blockquote>这是一条新回复</blockquote>"""
        val blocks = PostBodyParser.parse(html)
        assertEquals(listOf("quote"), blocks.map { it.kind })
        assertTrue(PostBodyParser.parse(blocks.single().node.html()).any { it.kind == "quote" })
    }

    @Test fun codeLineNumbersAreNotIncludedInCopiedContent() {
        val node = Jsoup.parseBodyFragment("""<ol><li><span class="line-number">1</span>val a = 1</li><li><span class="line-number">2</span>return a</li></ol>""").selectFirst("ol")!!
        assertEquals("val a = 1\nreturn a", PostBodyParser.codeText(node))
    }
}
