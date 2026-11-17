package me.rain.mtforum.feature.forum

import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
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
import top.yukonga.miuix.kmp.basic.CircularProgressIndicator
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
    liked: Boolean,
    favorited: Boolean,
    likeLoading: Boolean,
    favoriteLoading: Boolean,
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
                GlassActionIcon(
                    if (liked) ThreadLikeSolid else MiuixIcons.Useful.Like,
                    if (liked) "已点赞" else "点赞",
                    enabled, Modifier.weight(1f),
                    selected = liked, selectedColor = Color(0xFFE96666),
                    loading = likeLoading, onClick = onLike,
                )
                GlassActionIcon(MiuixNavigationIcons.Messages, "查看评论", true, Modifier.weight(1f),
                    onClick = onComments)
                GlassActionIcon(
                    if (favorited) ThreadFavoriteStarSolid else ThreadFavoriteStar,
                    if (favorited) "已收藏" else "收藏",
                    enabled, Modifier.weight(1f),
                    selected = favorited, selectedColor = Color(0xFFF0AC38),
                    loading = favoriteLoading, onClick = onFavorite,
                )
                GlassActionIcon(MiuixIcons.Useful.Share, "分享", true, Modifier.weight(1f),
                    onClick = onShare)
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
    selected: Boolean = false,
    selectedColor: Color = Color.Unspecified,
    loading: Boolean = false,
    onClick: () -> Unit,
) {
    val active = if (selectedColor == Color.Unspecified)
        MiuixTheme.colorScheme.primary else selectedColor
    val tint = when {
        selected -> active
        enabled -> MiuixTheme.colorScheme.onSurface
        else -> MiuixTheme.colorScheme.onSurfaceVariantSummary.copy(alpha = .45f)
    }
    val iconScale by animateFloatAsState(
        targetValue = if (selected) 1.15f else 1f,
        animationSpec = tween(durationMillis = 200),
        label = "thread-action-scale-$description",
    )
    Box(
        modifier.height(38.dp)
            .clip(RoundedCornerShape(50))
            .background(if (selected) active.copy(alpha = .13f) else Color.Transparent)
            .clickable(enabled = enabled && !loading, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        if (loading) CircularProgressIndicator(size = 18.dp)
        else Icon(
            icon, description,
            Modifier.size(21.dp).graphicsLayer {
                scaleX = iconScale
                scaleY = iconScale
            },
            tint = tint,
        )
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

/** Filled silhouettes are used only after the server confirms the action. */
private val ThreadFavoriteStarSolid: ImageVector by lazy {
    ImageVector.Builder(
        name = "ThreadFavoriteStarSolid",
        defaultWidth = 24.dp, defaultHeight = 24.dp,
        viewportWidth = 24f, viewportHeight = 24f,
    ).apply {
        path(fill = SolidColor(Color.Black)) {
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
private val ThreadLikeSolid: ImageVector by lazy {
    ImageVector.Builder(
        name = "ThreadLikeSolid",
        defaultWidth = 24.dp, defaultHeight = 24.dp,
        viewportWidth = 24f, viewportHeight = 24f,
    ).apply {
        path(fill = SolidColor(Color.Black)) {
            moveTo(6.7f, 10.1f)
            lineTo(10f, 3.4f)
            curveTo(10.7f, 2f, 12f, 2.8f, 12f, 4.1f)
            lineTo(12f, 8.2f)
            lineTo(18.9f, 8.2f)
            curveTo(21f, 8.2f, 22f, 9.5f, 21.5f, 11.6f)
            lineTo(19.7f, 19f)
            curveTo(19.4f, 20.3f, 18.6f, 21f, 17.3f, 21f)
            lineTo(8.2f, 21f)
            curveTo(7.4f, 21f, 6.7f, 20.3f, 6.7f, 19.5f)
            close()
        }
        path(fill = SolidColor(Color.Black)) {
            moveTo(2f, 10.2f)
            lineTo(5.2f, 10.2f)
            lineTo(5.2f, 21f)
            lineTo(2f, 21f)
            close()
        }
    }.build()
}
