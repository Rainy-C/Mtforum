package me.rain.mtforum.core.network

import org.jsoup.Jsoup
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertEquals
import org.junit.Test

class HiddenContentCoverageTest {
    @Test fun detectsStructuralHiddenContent() {
        val variants = listOf(
            "<div class='t_f'><div class='bb-hide'>回复可见</div></div>",
            "<div class='t_f'><div class='comiis_hidebox'>帖子隐藏内容</div></div>",
            "<div class='t_f'><div id='hide_102'>需要回复</div></div>",
            "<div class='t_f'><p>登录后可见</p></div>",
            "<div class='t_f'><p>支付 5 金币后可见</p></div>",
        )
        variants.forEach { assertTrue(it, TopicListMetadata.hasHidden(Jsoup.parseBodyFragment(it).body())) }
    }

    @Test fun normalQuoteAboutHidingIsNotHiddenContent() {
        val normal = "<div class='t_f'><blockquote>讨论一下隐藏帖如何工作</blockquote></div>"
        assertFalse(TopicListMetadata.hasHidden(Jsoup.parseBodyFragment(normal).body()))
        assertEquals("quote", PostBodyParser.parse("<blockquote>隐藏帖机制</blockquote>").single().kind)
    }

    @Test fun renderedComiisHiddenBlockRemainsDistinctFromQuote() {
        val blocks = PostBodyParser.parse("<div class='comiis_hide'>支付 5 金币即可查看隐藏内容</div>")
        assertEquals("hide", blocks.single().kind)
    }
}
