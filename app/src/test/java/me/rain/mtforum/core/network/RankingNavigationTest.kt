package me.rain.mtforum.core.network

import me.rain.mtforum.feature.forum.isRankingsUrl
import me.rain.mtforum.feature.forum.rankingTabKey
import me.rain.mtforum.feature.forum.rankingPageKey
import me.rain.mtforum.feature.forum.rankingTabs
import org.jsoup.Jsoup
import org.junit.Assert.*
import org.junit.Test

class RankingNavigationTest {
    private val base = ForumRepository.BaseUrl

    @Test
    fun onlineLeaderboardSeparatesNameRankAndAccumulatedMinutesForEveryPosition() {
        val html = """<html><body>
            <ul class="comiis_postphb">
                <li><span class="postphb_mun">1</span><a class="postphb_tit"
                    href="home.php?mod=space&amp;uid=11">Chenghow 在线: 1877690分钟</a></li>
                <li><span class="postphb_mun">2</span><a class="postphb_tit"
                    href="home.php?mod=space&amp;uid=12">诗情 在线: 1720110分钟</a></li>
                <li><span class="postphb_mun">3</span><a class="postphb_tit"
                    href="home.php?mod=space&amp;uid=13">丿丶灵泽 在线: 1426200分钟</a></li>
                <li><a class="postphb_tit"
                    href="home.php?mod=space&amp;uid=14">在线: 1383350分钟 4 两个笑窝</a></li>
                <li><a class="postphb_tit"
                    href="home.php?mod=space&amp;uid=15">在线: 1381810分钟 5 戒酒的李白染</a></li>
            </ul></body></html>"""
        val result = NativePageAdapters.parse(
            Jsoup.parse(html), "$base/misc.php?mod=ranklist&type=member&view=online&mobile=2"
        )!!
        assertEquals(listOf(1, 2, 3, 4, 5), result.blocks.map { it.rank })
        assertEquals(listOf("Chenghow", "诗情", "丿丶灵泽", "两个笑窝", "戒酒的李白染"),
            result.blocks.map { it.title })
        assertEquals(listOf("1877690 分钟", "1720110 分钟", "1426200 分钟",
            "1383350 分钟", "1381810 分钟"), result.blocks.map { it.facts.single().value })
        assertTrue(result.blocks.all { it.facts.single().label == "在线时长" })
    }

    @Test
    fun rankingNavigationOnlySelectsRankTabsAndIgnoresPageAndMobileForTabSelection() {
        val html = """<html><body><div id="comiis_sub"><ul>
          <li><a href="misc.php?mod=ranklist&amp;type=member&amp;view=credit">积分榜</a></li>
          <li><a href="misc.php?mod=ranklist&amp;type=member&amp;view=online">活跃榜</a></li>
          <li><a href="home.php?mod=space&amp;uid=10">用户</a></li>
        </ul></div><ul class="comiis_postphb">
          <li><span class="postphb_mun">1</span><a class="postphb_tit"
            href="home.php?mod=space&amp;uid=11">Chenghow 在线: 1877690分钟</a></li>
        </ul></body></html>"""
        val document = ContentParser.document(
            html, "$base/misc.php?mod=ranklist&type=member&view=online&mobile=2"
        )
        assertEquals(listOf("积分榜", "活跃榜"), rankingTabs(document).map { it.text })
        assertEquals(
            rankingTabKey("$base/misc.php?view=online&type=member&mod=ranklist&page=2"),
            rankingTabKey("$base/misc.php?mod=ranklist&type=member&view=online&mobile=2"),
        )
        assertEquals(
            rankingPageKey("$base/misc.php?view=online&type=member&mod=ranklist"),
            rankingPageKey("$base/misc.php?mod=ranklist&type=member&view=online&mobile=2"),
        )
        assertNotEquals(
            rankingPageKey("$base/misc.php?mod=ranklist&type=member&view=online&page=2"),
            rankingPageKey("$base/misc.php?mod=ranklist&type=member&view=online"),
        )
        assertTrue(isRankingsUrl("$base/misc.php?mod=ranklist&type=member&view=online"))
        assertFalse(isRankingsUrl("$base/home.php?mod=space&uid=11"))
    }
}
