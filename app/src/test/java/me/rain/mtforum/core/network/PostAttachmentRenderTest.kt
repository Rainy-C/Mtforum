package me.rain.mtforum.core.network

import org.jsoup.Jsoup
import org.junit.Assert.*
import org.junit.Test

class PostAttachmentRenderTest {
    private val fileUrl = "https://bbs.binmt.cc/forum.php?mod=attachment&aid=349231"
    private val fileIcon = "https://bbs.binmt.cc/static/image/filetype/txt.gif"

    @Test fun fileTypeIconBecomesAnAttachmentNotAFullWidthImage() {
        val html = """<dl class="tattl"><dt><a href="$fileUrl"><img src="$fileIcon"/>test.txt</a></dt>""" +
            """<dd>41 Bytes，下载次数：44</dd></dl><p>结束</p>"""
        val blocks = PostBodyParser.parse(html)
        assertEquals(listOf("attachment", "text"), blocks.map { it.kind })
        assertEquals(fileUrl, blocks.first().link)
        assertTrue(PostAttachments.fileDetails(blocks.first().node, "test.txt").contains("41 Bytes"))
    }

    @Test fun ordinaryContentAndAttachedPhotosAreNotMistakenForIcons() {
        val normal = PostBodyParser.parse("""<img src="https://bbs.binmt.cc/data/attachment/forum/picture.jpg">""")
        assertEquals("image", normal.single().kind)
        val linked = PostBodyParser.parse("""<a href="$fileUrl"><img src="https://bbs.binmt.cc/data/attachment/forum/picture.jpg"/></a>""")
        assertEquals("image", linked.single().kind)
        assertFalse(PostAttachments.isFileIconUrl("https://bbs.binmt.cc/data/attachment/forum/picture.jpg"))
    }

    @Test fun duplicateFooterLinkIsRemovedButUnshownAttachmentRemains() {
        val other = "https://bbs.binmt.cc/forum.php?mod=attachment&aid=888888"
        val body = """<a href="$fileUrl">test.txt</a>"""
        val links = listOf(ContentLink("test.txt", fileUrl), ContentLink("again", fileUrl), ContentLink("other", other))
        assertEquals(listOf(other), PostAttachments.visibleAdditionalLinks(body, links).map { it.url })
    }

    @Test fun nestedQuotesAreSeparateNodesAndKeepStyles() {
        val blocks = PostBodyParser.parse("""<blockquote>外层<blockquote><b>内层</b></blockquote></blockquote>""")
        assertEquals("quote", blocks.single().kind)
        val inside = PostBodyParser.parse(blocks.single().node.html())
        assertTrue(inside.any { it.kind == "quote" })
    }

    @Test fun iconsNeverNeedImageUrlsToDisplayTheirMetadata() {
        val icon = Jsoup.parse("""<img src="$fileIcon" alt="test.txt">""").selectFirst("img")!!
        assertTrue(PostAttachments.isFileIcon(icon))
        assertEquals("test.txt", PostAttachments.fileTitle(icon))
    }
}
