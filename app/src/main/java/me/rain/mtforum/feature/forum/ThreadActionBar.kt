package me.rain.mtforum.feature.forum

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kyant.backdrop.backdrops.LayerBackdrop
import com.kyant.backdrop.drawBackdrop
import com.kyant.backdrop.effects.blur
import com.kyant.backdrop.effects.lens
import me.rain.mtforum.core.ui.icons.*
import top.yukonga.miuix.kmp.basic.Icon
import top.yukonga.miuix.kmp.basic.Text
import top.yukonga.miuix.kmp.icon.MiuixIcons
import top.yukonga.miuix.kmp.icon.icons.useful.*
import top.yukonga.miuix.kmp.theme.MiuixTheme

/** Real backdrop-sampling liquid glass, intentionally limited to the thread footer. */
@Composable
internal fun ThreadActionBar(
    backdrop: LayerBackdrop,
    enabled: Boolean,
    onReply: () -> Unit,
    onLike: () -> Unit,
    onComments: () -> Unit,
    onFavorite: () -> Unit,
    onShare: () -> Unit,
) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        LiquidCapsule(backdrop, Modifier.weight(.39f)) {
            Row(
                Modifier.fillMaxSize()
                    .clip(RoundedCornerShape(50))
                    .clickable(onClick = onReply)
                    .padding(horizontal = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
            ) {
                Icon(MiuixIcons.Useful.Edit, null, Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text("写评论", fontSize = 13.sp, maxLines = 1)
            }
        }
        LiquidCapsule(backdrop, Modifier.weight(.61f)) {
            Row(
                Modifier.fillMaxSize().padding(horizontal = 3.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceEvenly,
            ) {
                GlassActionIcon(MiuixIcons.Useful.Like, "点赞", enabled, Modifier.weight(1f), onLike)
                GlassActionIcon(MiuixNavigationIcons.Messages, "查看评论", true, Modifier.weight(1f), onComments)
                GlassActionIcon(ThreadFavoriteStar, "收藏", enabled, Modifier.weight(1f), onFavorite)
                GlassActionIcon(MiuixIcons.Useful.Share, "分享", true, Modifier.weight(1f), onShare)
            }
        }
    }
}

/** Glass samples the scrollable post content recorded by ThreadScreen. */
@Composable
private fun LiquidCapsule(
    backdrop: LayerBackdrop,
    modifier: Modifier = Modifier,
    content: @Composable BoxScope.() -> Unit,
) {
    val dark = MiuixTheme.colorScheme.background.luminance() < 0.5f
    val surface = if (dark) Color(0xFF18191D).copy(alpha = .34f)
        else Color.White.copy(alpha = .34f)
    Box(
        modifier
            .height(48.dp)
            .drawBackdrop(
                backdrop = backdrop,
                shape = { RoundedCornerShape(50) },
                effects = {
                    // Actual sampled background blur + edge refraction.
                    blur(8.dp.toPx())
                    lens(7.dp.toPx(), 12.dp.toPx(), chromaticAberration = true)
                },
                onDrawSurface = { drawRect(surface) },
            ),
        contentAlignment = Alignment.Center,
        content = content,
    )
}

@Composable
private fun GlassActionIcon(
    icon: ImageVector,
    description: String,
    enabled: Boolean,
    modifier: Modifier,
    onClick: () -> Unit,
) {
    val tint = if (enabled) MiuixTheme.colorScheme.onSurface
        else MiuixTheme.colorScheme.onSurfaceVariantSummary.copy(alpha = .45f)
    Box(
        modifier.height(38.dp)
            .clip(RoundedCornerShape(50))
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, description, Modifier.size(21.dp), tint = tint)
    }
}

/** A crisp outline star, matching the reference comment toolbar. */
private val ThreadFavoriteStar: ImageVector by lazy {
    ImageVector.Builder(
        name = "ThreadFavoriteStar",
        defaultWidth = 24.dp, defaultHeight = 24.dp,
        viewportWidth = 24f, viewportHeight = 24f,
    ).apply {
        path(
            fill = null,
            stroke = SolidColor(Color.Black),
            strokeLineWidth = 1.9f,
            strokeLineCap = StrokeCap.Round,
            strokeLineJoin = StrokeJoin.Round,
        ) {
            moveTo(12f, 2.8f)
            lineTo(14.85f, 8.7f)
            lineTo(21.1f, 9.4f)
            lineTo(16.6f, 13.9f)
            lineTo(17.7f, 20.3f)
            lineTo(12f, 17.2f)
            lineTo(6.3f, 20.3f)
            lineTo(7.4f, 13.9f)
            lineTo(2.9f, 9.4f)
            lineTo(9.15f, 8.7f)
            close()
        }
    }.build()
}
