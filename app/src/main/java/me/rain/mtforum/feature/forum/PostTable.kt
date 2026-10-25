package me.rain.mtforum.feature.forum

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import me.rain.mtforum.core.network.ContentParser
import org.jsoup.nodes.Element
import top.yukonga.miuix.kmp.theme.MiuixTheme

internal data class TableCellSpec(val row: Int, val column: Int, val rowSpan: Int, val colSpan: Int, val cell: Element)

/** Respect colspan/rowspan positions so a spanning cell doesn't shift subsequent columns. */
internal fun tableCells(table: Element): List<TableCellSpec> {
    val result = mutableListOf<TableCellSpec>()
    val occupied = mutableSetOf<Pair<Int, Int>>()
    val rows = table.select("tr").filter { it.parents().firstOrNull { p -> p.normalName() == "table" } == table }.take(64)
    rows.forEachIndexed { rowIndex, tr ->
        var column = 0
        tr.children().filter { it.normalName() in setOf("td", "th") }.take(20).forEach { td ->
            while ((rowIndex to column) in occupied) column++
            if (column >= 20) return@forEach
            val span = td.attr("colspan").toIntOrNull()?.coerceIn(1, 20 - column) ?: 1
            val height = td.attr("rowspan").toIntOrNull()?.coerceIn(1, 64 - rowIndex) ?: 1
            result += TableCellSpec(rowIndex, column, height, span, td)
            for (r in rowIndex until rowIndex + height) for (c in column until column + span) occupied.add(r to c)
            column += span
        }
    }
    return result.take(300)
}

@Composable
internal fun PostTable(table: Element, onOpen: (String, String) -> Unit) {
    val cells = remember(table) { tableCells(table) }
    if (cells.isEmpty()) return
    val columnCount = cells.maxOf { it.column + it.colSpan }.coerceIn(1, 20)
    val rowCount = cells.maxOf { it.row + it.rowSpan }.coerceIn(1, 64)
    val cellWidth = 148.dp
    val colors = MiuixTheme.colorScheme
    val borderColor = colors.onSurface.copy(alpha = .13f)
    // A uniform row baseline keeps spans aligned. Long cells grow to their content height.
    val rowHeights = remember(cells) {
        IntArray(rowCount) { 52 }.also { heights ->
            cells.forEach { spec ->
                if (spec.rowSpan == 1) {
                    val count = spec.cell.text().length
                    val charsPerLine = (16 * spec.colSpan).coerceAtLeast(12)
                    val estimatedLines = (count / charsPerLine + 1).coerceIn(1, 18)
                    heights[spec.row] = maxOf(heights[spec.row], 24 + estimatedLines * 22)
                }
            }
        }
    }
    val scroller = rememberScrollState()
    val radius = RoundedCornerShape(12.dp)
    // Clip the *viewport*, not only the wide table: rounded corners remain stable while scrolling.
    Row(
        Modifier.fillMaxWidth().clip(radius)
            .background(colors.surface)
            .border(BorderStroke(1.dp, borderColor), radius)
            .horizontalScroll(scroller),
    ) {
        Box(Modifier.width(cellWidth * columnCount).background(colors.surface)) {
            // Absolute placement handles merged cells on both axes.
            androidx.compose.ui.layout.Layout(
                content = {
                    cells.forEach { spec ->
                        val bgcolor = cssBackground(spec.cell.attr("style")) ?: spec.cell.attr("bgcolor").takeIf { it.isNotBlank() }?.let(::tableColor)
                        val img = spec.cell.selectFirst("img")?.let { ContentParser.imageUrl(it) }
                        Column(
                            Modifier.background(bgcolor ?: if (spec.cell.normalName() == "th") colors.onSurface.copy(alpha = .04f) else Color.Transparent)
                                .border(BorderStroke(.5.dp, borderColor))
                                .padding(10.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            if (img != null && me.rain.mtforum.core.ui.LocalShowImages.current) {
                                AsyncImage(img, null, Modifier.fillMaxWidth().heightIn(max = 160.dp), contentScale = ContentScale.Fit)
                            }
                            SelectionContainer {
                                BasicText(
                                    annotated(spec.cell) { title, url -> onOpen(title, url) },
                                    style = TextStyle(
                                        fontSize = 14.sp, lineHeight = 21.sp,
                                        color = colors.onSurface,
                                        fontWeight = if (spec.cell.normalName() == "th") FontWeight.SemiBold else FontWeight.Normal,
                                        textAlign = when (spec.cell.attr("align")) {
                                            "center" -> TextAlign.Center
                                            "right" -> TextAlign.End
                                            else -> TextAlign.Start
                                        },
                                    ),
                                )
                            }
                        }
                    }
                },
                modifier = Modifier.width(cellWidth * columnCount),
            ) { measurables, constraints ->
                val unit = cellWidth.roundToPx()
                val rowPixels = rowHeights.map { (it.dp).roundToPx() }.toMutableList()
                // Intrinsic heights are queried before the one and only measure pass.
                // Spanning cells then receive the combined height of the rows they occupy.
                cells.forEachIndexed { index, spec ->
                    if (spec.rowSpan == 1) {
                        val height = measurables[index].minIntrinsicHeight(unit * spec.colSpan)
                        rowPixels[spec.row] = maxOf(rowPixels[spec.row], height)
                    }
                }
                cells.forEachIndexed { index, spec ->
                    if (spec.rowSpan > 1) {
                        val height = measurables[index].minIntrinsicHeight(unit * spec.colSpan)
                        val sum = (spec.row until spec.row + spec.rowSpan).sumOf { rowPixels[it] }
                        if (height > sum) rowPixels[spec.row + spec.rowSpan - 1] += height - sum
                    }
                }
                val measured = measurables.mapIndexed { index, item ->
                    val spec = cells[index]
                    val width = unit * spec.colSpan
                    val height = (spec.row until spec.row + spec.rowSpan).sumOf { rowPixels[it] }
                    item.measure(androidx.compose.ui.unit.Constraints.fixed(width, height))
                }
                val rowY = IntArray(rowPixels.size + 1)
                rowPixels.indices.forEach { rowY[it + 1] = rowY[it] + rowPixels[it] }
                layout(unit * columnCount, rowY.last()) {
                    measured.forEachIndexed { i, item ->
                        val spec = cells[i]
                        item.placeRelative(unit * spec.column, rowY[spec.row])
                    }
                }
            }
        }
    }
}

private fun cssBackground(style: String): Color? = Regex("""(?:^|;)\s*background(?:-color)?\s*:\s*([^;]+)""", RegexOption.IGNORE_CASE)
    .find(style)?.groupValues?.get(1)?.let(::tableColor)

private fun tableColor(raw: String): Color? = runCatching {
    Color(android.graphics.Color.parseColor(raw.trim()))
}.getOrNull()
