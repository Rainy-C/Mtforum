package me.rain.mtforum.core.network

import org.jsoup.Jsoup
import org.junit.Assert.*
import org.junit.Test

class NativeFeedListTest {
    private val base = ForumRepository.BaseUrl

    @Test
    fun myThreadsHaveRealAuthorTimeForumAndNoFollowLinkAsAuthor() {
        val html = """<div><ul class="threadlist">
          <li class="forumlist_li">
            <h2><a href="$base/thread-130-1-1.html">一个测试帖子</a></h2>
            <a href="$base/home.php?mod=space&amp;uid=9">关注</a>
            <a href="$base/home.php?mod=space&amp;uid=9">Cynnie</a>
            <a href="$base/forum-40-1.html">休闲灌水</a>
            <span title="2026-10-20 09:15">昨天</span>
          </li>
        </ul></div>"""
        val result = NativePageAdapters.parse(Jsoup.parse(html),
            "$base/home.php?mod=space&do=thread&view=me&type=thread")!!
        val block = result.blocks.single { it.kind == NativeContentKind.Thread }
        assertEquals("一个测试帖子", block.title)
        assertEquals("Cynnie", block.feedMeta?.author)
        assertEquals("2026-10-20 09:15", block.feedMeta?.time)
        assertEquals("休闲灌水", block.feedMeta?.forum)
        assertEquals("$base/thread-130-1-1.html", block.primaryLink?.url)
        assertNull(block.feedMeta?.likes)
    }

    @Test
    fun noticeKeepsTargetAndDoesNotFabricateStats() {
        val html = """<div class="comiis_notice_list"><li>
            <div class="ntc_body"><a href="$base/thread-81-1-1.html">回复了您</a>
                <span>2026-10-18 12:00</span></div>
        </li></div>"""
        val result = NativePageAdapters.parse(Jsoup.parse(html),
            "$base/home.php?mod=space&do=notice")!!
        val block = result.blocks.single { it.kind == NativeContentKind.Notice }
        assertNotNull(block.primaryLink)
        assertEquals("2026-10-18 12:00", block.feedMeta?.time)
        assertNull(block.feedMeta?.replies)
    }
}
