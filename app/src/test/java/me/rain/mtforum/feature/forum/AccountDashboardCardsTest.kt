package me.rain.mtforum.feature.forum

import me.rain.mtforum.core.network.ContentBlock
import me.rain.mtforum.core.network.ContentFact
import me.rain.mtforum.core.network.ContentLink
import me.rain.mtforum.core.network.NativeContentKind
import org.junit.Assert.*
import org.junit.Test

class AccountDashboardCardsTest {
    private val creditPage = "https://bbs.binmt.cc/home.php?mod=spacecp&ac=credit"
    private val promoPage = "https://bbs.binmt.cc/home.php?mod=spacecp&ac=promotion"

    @Test fun creditOverviewCombinesFragmentsAndKeepsExactValues() {
        val blocks = listOf(
            ContentBlock("金币: 212", "积分记录"),
            ContentBlock("好评: 7", "积分记录"),
            ContentBlock("信誉: 106", "积分记录"),
            ContentBlock("积分: 1400 总积分=金币X0.2+主题数X3\n+(1-1/(在线时间(小时)/5000+1))X20000"),
        )
        val grouped = accountDisplayBlocks(blocks, creditPage)
        assertEquals(1, grouped.size)
        val data = creditSnapshot(grouped.single())
        assertEquals("1400", data.total)
        assertEquals(listOf("金币" to "212", "好评" to "7", "信誉" to "106"),
            data.balances.map { it.label to it.value })
        assertTrue(data.formula!!.contains("在线时间(小时)"))
    }

    @Test fun structuredCreditFieldsDoNotLoseUnknownDetails() {
        val card = ContentBlock("", facts = listOf(
            ContentFact("金币", "212"), ContentFact("备注", "由论坛同步"),
        ))
        val data = creditSnapshot(card)
        assertEquals("212", data.balances.single().value)
        assertTrue(data.remainder.contains("由论坛同步"))
    }

    @Test fun groupScreenShowsCurrentAndNextLevelWithoutGuessingProgress() {
        val data = groupProgress("我的等级: 高中生\nLv.4\nLv.5\n还需要 600 积分升级到 大学生")
        assertEquals("高中生", data.current)
        assertEquals(listOf("Lv.4", "Lv.5"), data.levels)
        assertEquals("600", data.remaining)
        assertEquals("大学生", data.nextGroup)
    }

    @Test fun creditHistoryExtractsReasonDateAndSignedDelta() {
        val row = ContentBlock("金币 +2 2026-10-26 10:05每日签到", "积分记录",
            kind = NativeContentKind.CreditRecord)
        val data = creditTransaction(row)
        assertEquals("金币 +2", data.amount)
        assertEquals("2026-10-26 10:05", data.date)
        assertEquals("每日签到", data.reason)
    }

    @Test fun promotionMergesOnlyContentAndPreservesRealActions() {
        val link = ContentLink("推广详情", "https://bbs.binmt.cc/home.php?mod=spacecp&ac=promotion&op=detail")
        val navigation = ContentBlock("", links = listOf(link), kind = NativeContentKind.Navigation)
        val blocks = listOf(
            navigation,
            ContentBlock("Cynnie"), ContentBlock("UID: 154205"),
            ContentBlock("邀请您的朋友扫码加入吧"),
            ContentBlock("网友通过二维码访问，您将获得 金币+20", links = listOf(link)),
        )
        val grouped = accountDisplayBlocks(blocks, promoPage)
        assertEquals(2, grouped.size)
        assertEquals(navigation, grouped.first())
        assertEquals(listOf(link), grouped.last().links)
        val data = promotionDetails(grouped.last().text)
        assertEquals("Cynnie", data.username)
        assertEquals("154205", data.uid)
        assertEquals("金币+20", data.reward)
        assertTrue(data.messages.any { it.contains("二维码") })
    }

    @Test fun promotionQrUsesTheSameReferralUrlAsCapturedComiisResponse() {
        val details = promotionDetails(
            "Cynnie\nUID: 154205\n邀请您的朋友扫码加入吧\n网友通过二维码访问，您将获得 金币+20"
        )
        assertEquals("https://bbs.binmt.cc/?fromuid=154205", promotionInviteUrl(details.uid))
        assertNull(promotionInviteUrl(null))
        assertNull(promotionInviteUrl(""))
        assertNull(promotionInviteUrl("154205&other=1"))
    }
}
