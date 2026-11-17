package me.rain.mtforum.feature.forum

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import top.yukonga.miuix.kmp.basic.Text

/** Forum-supplied member level, rendered consistently in topics and replies. */
@Composable
internal fun UserLevelPill(level: String) {
    val name = level.trim().take(24)
    if (name.isEmpty()) return
    val number = Regex("""(?i)Lv\.?\s*(\d+)""").find(name)
        ?.groupValues?.getOrNull(1)?.toIntOrNull()
    val accent = when {
        number == null -> Color(0xFF72849C)
        number >= 7 -> Color(0xFFD79635)
        number >= 4 -> Color(0xFF4E84C4)
        else -> Color(0xFF57A58A)
    }
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(accent.copy(alpha = .12f))
            .border(0.8.dp, accent.copy(alpha = .25f), RoundedCornerShape(50))
            .padding(horizontal = 8.dp, vertical = 3.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            name,
            fontSize = 10.sp,
            lineHeight = 13.sp,
            fontWeight = FontWeight.SemiBold,
            color = accent,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}
