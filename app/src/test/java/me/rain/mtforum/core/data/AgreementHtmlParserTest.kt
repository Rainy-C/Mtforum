package me.rain.mtforum.core.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AgreementHtmlParserTest {
    private val body = "MT Forum 使用与隐私说明\n\n一、独立客户端及适用范围\n\n" +
        "MT Forum 是第三方独立开发的 Android 客户端，应说明使用与隐私规则。".repeat(12)

    @Test fun extractsOnlyWeiyunNoteAndPreservesBreaks() {
        val html = """
            <html><head><title>QQ收藏</title></head><body>
            <div>无关站点导航</div>
            <section class="wy-notes-wrapper">
              <header><time class="note-time">2026-10-25 23:32:15</time></header>
              <article><div class="note-content">${body.replace("\n", "<br/>")}&amp; 阅读确认</div></article>
            </section><script>secret_not_agreement</script></body></html>
        """.trimIndent()
        val parsed = AgreementHtmlParser.parse(html)
        assertNotNull(parsed)
        assertEquals("2026-10-25 23:32:15", parsed!!.updatedAt)
        assertTrue(parsed.text.contains("独立客户端及适用范围\n\nMT Forum"))
        assertTrue(parsed.text.endsWith("& 阅读确认"))
        assertFalse(parsed.text.contains("无关站点导航"))
        assertFalse(parsed.text.contains("secret_not_agreement"))
    }

    @Test fun remoteMarkupSurvivesHtmlExtraction() {
        val highlighted = body + "<br/>[red]请注意账号安全[/red]" +
            "<br/>[highlight]重要说明[/highlight]"
        val page = "<section class='wy-notes-wrapper'><div class='note-content'>" + highlighted.replace("\n", "<br/>") +
            "</div></section>"
        val raw = AgreementHtmlParser.parse(page)!!.text
        assertTrue(raw.contains("[red]请注意账号安全[/red]"))
        assertTrue(raw.contains("[highlight]重要说明[/highlight]"))
        val visible = AgreementMarkup.parse(raw)
        assertFalse(visible.text.contains("[/red]"))
        assertTrue(visible.text.contains("请注意账号安全"))
    }

    @Test fun missingOrIncorrectDocumentIsRejected() {
        assertNull(AgreementHtmlParser.parse("<html><body>分享已经失效</body></html>"))
        assertNull(AgreementHtmlParser.parse(
            "<section class='wy-notes-wrapper'><div class='note-content'>下载失败</div></section>"
        ))
    }

    @Test fun contentDigestIgnoresWhitespaceButNotTextChanges() {
        val first = AgreementRepository.fingerprint(body)
        val formattingOnly = AgreementRepository.fingerprint("  " + body.replace("\n", "\r\n") + "  ")
        assertEquals(first, formattingOnly)
        assertTrue(first != AgreementRepository.fingerprint(body + " 新的协议条款"))
    }
}
