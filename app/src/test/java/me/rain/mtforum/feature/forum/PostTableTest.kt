package me.rain.mtforum.feature.forum

import org.jsoup.Jsoup
import org.junit.Assert.*
import org.junit.Test

class PostTableTest {
    @Test fun spansDoNotShiftFollowingCells() {
        val table = Jsoup.parse("""<table><tr><th rowspan='2'>A</th><td>B</td></tr>
            <tr><td>C</td></tr><tr><td colspan='2'>D</td></tr></table>""").selectFirst("table")!!
        val cells = tableCells(table)
        assertEquals(listOf(0, 1, 1, 0), cells.map { it.column })
        assertEquals(listOf(0, 0, 1, 2), cells.map { it.row })
        assertEquals(2, cells.first().rowSpan)
        assertEquals(2, cells.last().colSpan)
    }
}
