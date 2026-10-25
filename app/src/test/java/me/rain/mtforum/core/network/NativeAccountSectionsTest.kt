package me.rain.mtforum.core.network

import org.jsoup.Jsoup
import org.junit.Assert.*
import org.junit.Test

class NativeAccountSectionsTest {
    private val base = ForumRepository.BaseUrl

    @Test fun socialSectionUsesOneStableSetOfTabs() {
        val urls = socialSectionLinks("$base/home.php?mod=space&do=friend&mobile=2")
        assertEquals(listOf("我的好友", "最近来访", "我看过谁", "我的关注", "我的粉丝", "好友请求"),
            urls.map { it.text })
        assertEquals(6, urls.map { it.url }.distinct().size)
        urls.forEachIndexed { index, link ->
            assertEquals("social", nativeSectionGroup(link.url))
            assertEquals(index, socialSectionIndex(link.url))
            assertTrue(isNativeSectionTab(urls[0].url, link.url))
        }
    }

    @Test fun duplicatesAreSuppressedButProfileOrActionsAreKept() {
        val root = "$base/home.php?mod=space&do=friend&mobile=2"
        val tabs = socialSectionLinks(root)
        assertTrue(isDuplicateAccountNavigation(ContentBlock("", links = tabs.take(4),
            kind = NativeContentKind.Navigation), root))
        assertTrue(isDuplicateAccountNavigation(ContentBlock("最近来访", links = tabs.subList(1,2)), root))
        assertFalse(isDuplicateAccountNavigation(ContentBlock("好友", links = listOf(
            ContentLink("admin", "$base/home.php?mod=space&uid=1&do=profile"))), root))
        assertFalse(isDuplicateAccountNavigation(ContentBlock("打招呼", links = listOf(
            ContentLink("打招呼", "$base/home.php?mod=spacecp&ac=poke&op=send&uid=1"))), root))
    }

    @Test fun creditActionsAreNotMistakenForTabs() {
        val log = "$base/home.php?mod=spacecp&ac=credit&op=log"
        val center = "$base/home.php?mod=spacecp&ac=credit"
        val transfer = "$base/home.php?mod=spacecp&ac=credit&op=transfer"
        assertTrue(isNativeSectionTab(log, center))
        assertFalse(isNativeSectionTab(log, transfer))
        assertFalse(isNativeSectionTab(center, "$base/home.php?mod=spacecp&ac=usergroup&op=buy"))
    }

    @Test fun cleanupDoesNotStripMeaningfulAmountsOrNames() {
        assertEquals("积分: 5314", cleanAccountText("\uE6AF 积分： 5314 "))
        assertEquals("南黎、", cleanAccountText(" 南黎、 "))
        assertEquals("-200 金币", cleanAccountText(" -200 金币 "))
    }

    @Test fun structuredCreditCellsKeepServerValues() {
        val row = Jsoup.parse("<table><tr><td>2026-10-21 14:25</td>" +
            "<td>积分变更</td><td>-200 金币</td></tr></table>")
            .selectFirst("tr")!!
        val facts = parseAccountFacts(row)
        assertEquals(3, facts.size)
        assertEquals("-200 金币", facts[2].value)
    }

    @Test fun forumSocialRowsAreParsedAsPeopleWithoutMenuRows() {
        val html = """
            <div class="comiis_bodybox"><ul class="comiis_userlist01">
            <li class="b_t"><a href="home.php?mod=space&uid=10&do=profile" class="list01_limg">
            <img src="https://cdn.binmt.cc/uc_server/data/avatar/000/00/00/10_avatar_middle.jpg"></a>
            <p class="tit"><a href="home.php?mod=space&uid=10&do=profile">小明</a></p>
            <p class="txt">高中生 积分:5314</p>
            <a href="home.php?mod=spacecp&ac=poke&op=send&uid=10">打招呼</a></li>
            </ul></div>
        """.trimIndent()
        val parsed = NativePageAdapters.parse(Jsoup.parse(html, base),
            "$base/home.php?mod=space&do=friend&mobile=2")!!
        assertEquals(1, parsed.blocks.count { it.kind == NativeContentKind.Person })
        assertEquals("小明", parsed.blocks.first { it.kind == NativeContentKind.Person }.title)
    }
}
