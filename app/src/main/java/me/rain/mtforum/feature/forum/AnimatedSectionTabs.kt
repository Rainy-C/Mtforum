package me.rain.mtforum.feature.forum

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import top.yukonga.miuix.kmp.basic.Text
import top.yukonga.miuix.kmp.theme.MiuixTheme

/** A Miuix contour-style segmented bar with a single sliding selection layer.
 * Only the graphics layer translates during transitions, not the measured tabs.
 */
@Composable
internal fun AnimatedSectionTabs(
    tabs: List<String>,
    selectedTabIndex: Int,
    modifier: Modifier = Modifier,
    onTabSelected: (Int) -> Unit,
) {
    if (tabs.isEmpty()) return
    val selected = selectedTabIndex.coerceIn(tabs.indices)
    val progress by animateFloatAsState(
        targetValue = selected.toFloat(),
        animationSpec = tween(durationMillis = 235, easing = FastOutSlowInEasing),
        label = "native-section-selected-tab",
    )
    val outerShape = RoundedCornerShape(21.dp)
    val itemShape = RoundedCornerShape(16.dp)
    val gap = 4.dp
    val inset = 5.dp
    BoxWithConstraints(
        modifier = modifier.fillMaxWidth().height(46.dp)
            .clip(outerShape)
            .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .055f))
            .padding(inset),
    ) {
        val count = tabs.size
        // 5+ sections must scroll horizontally; never squeeze Chinese labels into 40dp pills.
        val itemWidth = if (count > 4) 86.dp else (maxWidth - gap * (count - 1)) / count
        val contentWidth = itemWidth * count + gap * (count - 1)
        val pixelStep = with(LocalDensity.current) { (itemWidth + gap).toPx() }
        val scrollState = rememberScrollState()
        var ready by remember { mutableStateOf(false) }
        val viewportPx = with(LocalDensity.current) { maxWidth.toPx() }
        LaunchedEffect(selected, count, viewportPx, scrollState.maxValue) {
            if (count > 4) {
                val target = (pixelStep * selected - (viewportPx - pixelStep) / 2f)
                    .toInt().coerceIn(0, scrollState.maxValue)
                if (ready) scrollState.animateScrollTo(target) else scrollState.scrollTo(target)
            }
            ready = true
        }
        Box(Modifier.fillMaxSize().horizontalScroll(scrollState)) {
            Box(Modifier.width(contentWidth).fillMaxHeight()) {
                Box(
                    Modifier.width(itemWidth).fillMaxHeight()
                        .graphicsLayer { translationX = pixelStep * progress }
                        .clip(itemShape)
                        .background(MiuixTheme.colorScheme.surface),
                )
                Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(gap)) {
                    tabs.forEachIndexed { index, label ->
                        val ink by animateColorAsState(
                            targetValue = if (index == selected) MiuixTheme.colorScheme.onSurface
                                else MiuixTheme.colorScheme.onSurfaceVariantSummary,
                            animationSpec = tween(180),
                            label = "native-section-tab-ink-$index",
                        )
                        Box(
                            Modifier.width(itemWidth).fillMaxHeight()
                                .clip(itemShape)
                                .clickable(role = Role.Tab) { if (selected != index) onTabSelected(index) }
                                .semantics { this.selected = selected == index },
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(label, color = ink, fontSize = 14.sp,
                                fontWeight = if (selected == index) FontWeight.SemiBold else FontWeight.Medium,
                                maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
        }
    }
}
