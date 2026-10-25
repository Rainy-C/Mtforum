package me.rain.mtforum.core.network

import org.junit.Assert.assertEquals
import org.junit.Test

class GuideFeedsTest {
    @Test fun selectionSupportsMultipleFeedsButNotEmpty() {
        assertEquals(listOf("hot"), GuideFeeds.selected(1))
        assertEquals(3, GuideFeeds.toggle(1, 1))
        assertEquals(listOf("hot", "newthread"), GuideFeeds.selected(3))
        assertEquals(1, GuideFeeds.toggle(1, 0))
        assertEquals(1, GuideFeeds.toggle(3, 1))
    }

    @Test fun mergeInterleavesAndDeduplicatesWithStableOrder() {
        fun topic(id: String) = Topic(id, id, "https://bbs.binmt.cc/thread-$id-1-1.html")
        val pages = mapOf(
            "hot" to GuideFeedPage(listOf(topic("a"), topic("b"), topic("c")), null, 0),
            "newthread" to GuideFeedPage(listOf(topic("b"), topic("d")), null, 0),
        )
        assertEquals(listOf("a", "b", "d", "c"),
            GuideFeeds.merge(listOf("hot", "newthread"), pages).map { it.id })
    }
}
