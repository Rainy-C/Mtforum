package me.rain.mtforum.core.data

import org.junit.Assert.assertEquals
import org.junit.Test

class SearchHistoryPolicyTest {
    @Test
    fun newestSearchComesFirstAndMatchesAreDeduplicated() {
        var list = SearchHistoryPolicy.record(emptyList(), " Compose ")
        list = SearchHistoryPolicy.record(list, "Kotlin")
        list = SearchHistoryPolicy.record(list, "compose")
        assertEquals(listOf("compose", "Kotlin"), list)
    }

    @Test
    fun blankQueriesDoNotOverwriteHistory() {
        assertEquals(
            listOf("Termux"),
            SearchHistoryPolicy.record(listOf("Termux"), "   "),
        )
    }

    @Test
    fun historyStaysWithinTwentyEntriesAndTruncatesLongTerms() {
        val list = (1..30).fold(emptyList<String>()) { history, number ->
            SearchHistoryPolicy.record(history, "search-$number")
        }
        assertEquals(20, list.size)
        assertEquals("search-30", list.first())
        assertEquals("search-11", list.last())
        assertEquals(100, SearchHistoryPolicy.record(list, "x".repeat(200)).first().length)
    }
}
