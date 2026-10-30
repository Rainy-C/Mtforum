package me.rain.mtforum.feature.forum

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import top.yukonga.miuix.kmp.basic.Text
import top.yukonga.miuix.kmp.theme.MiuixTheme

/** The captured JSON has image URLs but no Discuz smiley code table.
 * [img] is a fallback for forums where BBCode images are enabled. The server
 * is still authoritative about whether image BBCode is accepted in replies/PMs.
 */
internal fun smileyInsertCode(url: String): String =
    if (url.startsWith("https://cdn.binmt.cc/static/image/smiley/") &&
        !url.contains('[') && !url.contains(']')) "[img]$url[/img]" else ""

// Inventory reconstructed exactly from the uploaded doge.json. Gaps are intentional.
private val smileyGroups: Map<String, List<String>> = mapOf(
    "doge" to ((1..15) + (19..71) + (77..88)).map { index ->
        "https://cdn.binmt.cc/static/image/smiley/doge/$index.png"
    },
    "comiis_tb" to (1..69).map { index ->
        "https://cdn.binmt.cc/static/image/smiley/comiis_tb/tb_$index.png"
    },
    "qq" to ((1..61) + (63..92) + (97..107)).map { index ->
        "https://cdn.binmt.cc/static/image/smiley/qq/qq${index.toString().padStart(3, '0')}.gif"
    },
)

@Composable
internal fun ForumSmileyPicker(
    modifier: Modifier = Modifier,
    onChoose: (String) -> Unit,
) {
    var current by remember { mutableStateOf("doge") }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("doge" to "Doge", "comiis_tb" to "贴吧", "qq" to "QQ").forEach { (key, title) ->
                val selected = key == current
                Box(
                    Modifier.clip(RoundedCornerShape(12.dp))
                        .background(MiuixTheme.colorScheme.onSurface.copy(alpha = if (selected) .12f else .04f))
                        .clickable { current = key }
                        .padding(horizontal = 14.dp, vertical = 8.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(title, fontSize = 13.sp,
                        fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal)
                }
            }
        }
        LazyVerticalGrid(
            columns = GridCells.Fixed(6),
            modifier = Modifier.fillMaxWidth().weight(1f),
            contentPadding = PaddingValues(bottom = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            items(smileyGroups[current].orEmpty(), key = { it }) { url ->
                Box(
                    Modifier.aspectRatio(1f)
                        .clip(RoundedCornerShape(12.dp))
                        .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .035f))
                        .clickable { smileyInsertCode(url).takeIf(String::isNotBlank)?.let(onChoose) }
                        .padding(5.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    AsyncImage(url, "表情", Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
                }
            }
        }
    }
}
