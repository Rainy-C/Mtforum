package me.rain.mtforum.feature.forum

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.selection.selectable
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
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import top.yukonga.miuix.kmp.basic.Text
import top.yukonga.miuix.kmp.theme.MiuixTheme

/** Single-pass selection painting: no animated shadow or separate graphics layer. */
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
        animationSpec = tween(durationMillis = 270, easing = FastOutSlowInEasing),
        label = "native-section-selected-tab",
    )
    val outerShape = RoundedCornerShape(21.dp)
    val itemShape = RoundedCornerShape(16.dp)
    val gap = 4.dp
    val inset = 5.dp
    BoxWithConstraints(
        modifier = modifier.fillMaxWidth().height(46.dp)
            .clip(outerShape)
            .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .095f))
            .padding(inset),
    ) {
        val count = tabs.size
        // 5+ sections must scroll horizontally; never squeeze Chinese labels into 40dp pills.
        val itemWidth = if (count > 4) 86.dp else (maxWidth - gap * (count - 1)) / count
        val contentWidth = itemWidth * count + gap * (count - 1)
        val pixelStep = with(LocalDensity.current) { (itemWidth + gap).toPx() }
        val pillWidthPx = with(LocalDensity.current) { itemWidth.toPx() }
        val selectedColor = MiuixTheme.colorScheme.surface
        val scrollState = rememberScrollState()
        var ready by remember { mutableStateOf(false) }
        val viewportPx = with(LocalDensity.current) { maxWidth.toPx() }
        LaunchedEffect(selected, count, viewportPx, scrollState.maxValue) {
            if (count > 4) {
                val target = (pixelStep * selected - (viewportPx - pixelStep) / 2f)
                    .toInt().coerceIn(0, scrollState.maxValue)
                if (ready) scrollState.animateScrollTo(target, tween(270, easing = FastOutSlowInEasing))
                else scrollState.scrollTo(target)
            }
            ready = true
        }
        Box(Modifier.fillMaxSize().horizontalScroll(scrollState)) {
            Box(
                Modifier.width(contentWidth).fillMaxHeight()
                    .drawBehind {
                        drawRoundRect(
                            color = selectedColor,
                            topLeft = Offset(x = pixelStep * progress, y = 0f),
                            size = Size(width = pillWidthPx, height = size.height),
                            cornerRadius = CornerRadius(16.dp.toPx()),
                        )
                    },
            ) {
                Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(gap)) {
                    tabs.forEachIndexed { index, label ->
                        val ink by animateColorAsState(
                            targetValue = if (index == selected) MiuixTheme.colorScheme.onSurface
                                else MiuixTheme.colorScheme.onSurfaceVariantSummary,
                            animationSpec = tween(270, easing = FastOutSlowInEasing),
                            label = "native-section-tab-ink-$index",
                        )
                        Box(
                            Modifier.width(itemWidth).fillMaxHeight()
                                .clip(itemShape)
                                .selectable(
                                    selected = selected == index,
                                    interactionSource = null,
                                    indication = null,
                                    role = Role.Tab,
                                ) { if (selected != index) onTabSelected(index) },
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(label, color = ink, fontSize = 14.sp,
                                fontWeight = FontWeight.Medium,
                                maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
        }
    }
}
