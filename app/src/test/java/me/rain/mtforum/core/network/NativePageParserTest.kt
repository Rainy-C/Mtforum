package me.rain.mtforum.core.network

import org.junit.Assert.*
import org.junit.Test

/** Structured rows captured from the Comiis friend/notice pages. */
class NativePageParserTest {
    private val base = ForumRepository.BaseUrl
    private val avatar = "https://cdn.binmt.cc/uc_server/data/avatar/000/00/00/01_avatar_middle.jpg?v=x"

    @Test
    fun rankingSeparatesAllPositionsNamesAndPoints() {
        val html = """<html><body><ul class="comiis_postphb">
            <li><span class="postphb_mun">1</span><a class="postphb_tit"
                href="home.php?mod=space&amp;uid=10">Bin 69176积分</a></li>
            <li><span class="postphb_mun">2</span><a class="postphb_tit"
                href="home.php?mod=space&amp;uid=11">喵喵猫 64010积分</a></li>
            <li><span class="postphb_mun">3</span><a class="postphb_tit"
                href="home.php?mod=space&amp;uid=12">dyliloveyou 49577积分</a></li>
            <li><a class="postphb_tit" href="home.php?mod=space&amp;uid=13">38597积分 4 青山</a></li>
            <li><a class="postphb_tit" href="home.php?mod=space&amp;uid=14">38327积分 5 康哥</a></li>
        </ul></body></html>"""
        val result = NativePageAdapters.parse(
            org.jsoup.Jsoup.parse(html),
            "$base/misc.php?mod=ranklist&type=member&view=credit&mobile=2",
        )!!
        assertEquals(listOf(1, 2, 3, 4, 5), result.blocks.map { it.rank })
        assertEquals(listOf("Bin", "喵喵猫", "dyliloveyou", "青山", "康哥"), result.blocks.map { it.title })
        assertEquals(listOf("69176", "64010", "49577", "38597", "38327"),
            result.blocks.map { it.facts.single().value })
        assertTrue(result.blocks.all { it.primaryLink != null })
    }

    @Test
    fun friendListKeepsTabsAvatarNameAndActions() {
        val html =
            """<html><head><title>好友 - MT论坛</title></head><body>
            <div id="comiis_sub"><ul class="swiper-wrapper">
                <li class="swiper-slide f_0"><a href="$base/home.php?mod=space&amp;do=friend">我的好友</a></li>
                <li class="swiper-slide"><a href="$base/home.php?mod=follow&amp;do=following&amp;uid=154205">我的关注</a></li>
            </ul></div>
            <div class="comiis_friend_boxs"><ul>
                <li class="b_t">
                    <a href="$base/home.php?mod=spacecp&amp;ac=friend&amp;op=ignore&amp;uid=1&amp;handlekey=delfriendhk" class="dialog kmdel f_g comiis_font">&#xe647</a>
                    <p class="ytit f_d">
                        <a href="$base/home.php?mod=spacecp&amp;ac=follow&amp;op=del&amp;fuid=1&amp;hash=479fb68e&amp;handlekey=followmod"><font>取消</font></a>
                        <a href="$base/home.php?mod=space&amp;do=pm&amp;subop=view&amp;touid=1"><font>发消息</font></a>
                    </p>
                    <a href="$base/home.php?mod=space&amp;uid=1&amp;do=profile" class="list01_limg"><img src="$avatar"></a>
                    <p class="tit"><a href="$base/home.php?mod=space&amp;uid=1&amp;do=profile">admin</a></p>
                    <p class="txt"><font>硕士生</font><font>积分:5314</font></p>
                </li>
            </ul></div>
            </body></html>"""
        val doc = ContentParser.document(html, "$base/home.php?mod=space&do=friend")
        assertEquals(2, doc.blocks.size)
        val tabs = doc.blocks.first()
        assertTrue(tabs.links.any { it.text == "我的好友" })
        assertTrue(tabs.links.any { it.text == "我的关注" })
        val row = doc.blocks[1]
        assertEquals("admin", row.title)
        assertTrue(row.text.contains("admin"))
        assertTrue(row.text.contains("积分:5314"))
        assertEquals(avatar, row.image)
        assertTrue(row.links.any { it.text == "删除好友" })
        assertTrue(row.links.any { it.text == "取消" })
        assertTrue(row.links.any { it.text == "发消息" })
    }

    @Test
    fun creditPageKeepsTabsTotalsAndBalances() {
        val html =
            """<html><head><title>积分 - MT论坛</title></head><body><div class="comiis_bodybox">
            <div class="comiis_topnv"><ul class="comiis_flex">
                <li class="flex f_0"><a href="$base/home.php?mod=spacecp&amp;ac=credit&amp;op=base">我的</a></li>
                <li class="flex"><a href="$base/home.php?mod=spacecp&amp;ac=credit&amp;op=log">记录</a></li>
            </ul></div>
            <div class="comiis_credit_box"><div class="comiis_creditl cl">
                <h2>积分: <span>1133</span><p>总积分=金币X0.2+主题数X3</p></h2>
                <ul>
                    <li><span> 金币: </span>141</li>
                    <li><span> 好评: </span>7</li>
                </ul>
            </div></div>
            </div></body></html>"""
        val doc = ContentParser.document(html, "$base/home.php?mod=spacecp&ac=credit")
        val text = doc.blocks.joinToString("\n") { it.text }
        assertTrue(text.contains("金币"))
        assertTrue(text.contains("好评"))
        assertTrue(text.contains("1133"))
        assertTrue(doc.blocks.any { block -> block.links.any { it.text == "记录" } })
    }

    @Test
    fun pageChromeIsNeverRendered() {
        val html =
            """<html><body><div class="comiis_body">
            <div class="comiis_sidenv_box">Cynnie Lv.4 高中生 积分:1133 首页 社区 访问推广</div>
            <div class="comiis_loadings">数据加载中</div>
            <div class="comiis_bodybox">
                <div class="comiis_topnv"><ul><li><a href="$base/home.php?mod=space&amp;do=favorite&amp;view=me">全部收藏</a></li></ul></div>
                <ul class="comiis_fav_list">
                    <li><p class="tit"><a href="$base/thread-1-1-1.html">【举报】论坛存在带后门的网络验证源码</a></p>
                        <p class="txt">MT论坛-Flutter 客户端</p></li>
                </ul>
            </div>
            <div id="comiis_foot_box">选择您感兴趣的东西发布吧</div>
            <div class="comiis_fmenu">选择发帖版块 MT专区</div>
            <div id="comiis_wx_description_box">来自: MT论坛</div>
            </div></body></html>"""
        val doc = ContentParser.document(html, "$base/home.php?mod=space&do=favorite&view=me")
        val all = doc.blocks.joinToString("\n") { it.text }
        assertFalse(all.contains("数据加载中"))
        assertFalse(all.contains("访问推广"))
        assertFalse(all.contains("选择发帖版块"))
        assertFalse(all.contains("来自: MT论坛"))
        assertTrue(all.contains("【举报】"))
    }

    @Test
    fun brokenMarkupFallsBackInsteadOfFailing() {
        val doc = ContentParser.document("<div><li><a href='javascript:;'>x</div>", "$base/home.php?mod=space&do=friend")
        assertTrue(doc.blocks.isNotEmpty() || doc.forms.isEmpty())
    }

    @Test
    fun noticeRowsKeepAuthorAvatarAndTarget() {
        val html =
            """<html><head><title>提醒 - MT论坛</title></head><body>
            <div class="comiis_notice_list"><ul>
                <li>
                    <a class="notice_img" href="$base/home.php?mod=space&amp;uid=2&amp;do=profile"><img src="$avatar"></a>
                    <div class="ntc_body"><a href="$base/thread-123-1-1.html">回复了您</a><span>2026-10-18 12:00</span></div>
                </li>
            </ul></div>
            </body></html>"""
        val doc = ContentParser.document(html, "$base/home.php?mod=space&do=notice")
        val row = doc.blocks.single()
        assertEquals("回复了您", row.title)
        assertTrue(row.text.contains("2026-10-18"))
        assertEquals(avatar, row.image)
        assertTrue(row.links.any { it.url.endsWith("/thread-123-1-1.html") })
    }
}
