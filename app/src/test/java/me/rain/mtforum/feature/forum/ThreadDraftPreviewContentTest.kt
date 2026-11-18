package me.rain.mtforum.feature.forum

import org.junit.Assert.assertTrue
import org.junit.Test

class ThreadDraftPreviewContentTest {
    @Test fun previewRendersBbcodeFormatting() {
        val html = ThreadDraftPreviewContent.toHtml("你好 [b]加粗[/b]")
        assertTrue(html.contains("<b>加粗</b>"))
    }

    @Test fun previewPreservesParagraphBreaks() {
        val html = ThreadDraftPreviewContent.toHtml("第一段\\n第二段".replace("\\n", "\n"))
        assertTrue(html.contains("第一段<br>第二段"))
    }

    @Test fun previewDoesNotCorruptCodeLineBreaks() {
        val html = ThreadDraftPreviewContent.toHtml("[code=java]a\\nb[/code]".replace("\\n", "\n"))
        assertTrue(html.contains("a\nb</pre>"))
    }

    @Test fun previewLeavesAttachmentPlaceholderInsteadOfInventingUrl() {
        val html = ThreadDraftPreviewContent.toHtml("[attachimg]42[/attachimg]")
        assertTrue(html.contains("附件 #42"))
    }
}
