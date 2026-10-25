package me.rain.mtforum.feature.forum

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.assertFalse
import me.rain.mtforum.core.network.ContentBlock
import me.rain.mtforum.core.network.ContentLink
import me.rain.mtforum.core.network.NativeContentKind
import org.junit.Test

class MallHistoryTest {
    @Test fun extractsFlattenedExchangeRecords() {
        val text = "10-21 14:25 已兑换 苏轩网络科技 200金币 " +
            "10-21 06:51 已兑换 四月的谎言 200金币 " +
            "10-20 23:51 已兑换 阿强 200金币 " +
            "123.. 22 下一页共有兑换记录109条"
        val rows = parseMallExchanges(text)
        assertEquals(3, rows.size)
        assertEquals("苏轩网络科技", rows[0].username)
        assertEquals("10-21 14:25", rows[0].timestamp)
        assertEquals("200", rows[1].amount)
        assertEquals("阿强", rows[2].username)
    }

    @Test fun doesNotParsePartialOrUnrelatedRecords() {
        assertTrue(parseMallExchanges("立即抢购 查看卡密状态").isEmpty())
        assertTrue(parseMallExchanges("10-21 14:25 已兑换 某某").isEmpty())
    }

    @Test fun onlyMallExchangeConfirmationsGetCompactLayout() {
        assertTrue(isMallConfirmationUrl(
            "https://bbs.binmt.cc/plugin.php?id=keke_integralmall%3Ashow_win&ac=xd&tid=10"
        ))
        assertFalse(isMallConfirmationUrl(
            "https://bbs.binmt.cc/keke_integralmall-view-10.html"
        ))
    }

    @Test fun selectsProductDetailInsteadOfUnrelatedLinks() {
        val detail = ContentLink("查看商品", "https://bbs.binmt.cc/keke_integralmall-view-6.html")
        val other = ContentLink("积分商城", "https://bbs.binmt.cc/keke_integralmall-keke_integralmall.html")
        val item = ContentBlock("商品", "月度卡密", links = listOf(other, detail),
            kind = NativeContentKind.Product)
        assertEquals(detail, mallProductTarget(item))
    }

}
