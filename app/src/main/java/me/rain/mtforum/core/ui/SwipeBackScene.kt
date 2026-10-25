package me.rain.mtforum.core.ui

import androidx.activity.compose.PredictiveBackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Both system predictive back and the fallback edge gesture reveal the previous page. */
@Composable
fun SwipeBackScene(
    enabled: Boolean,
    onBack: () -> Unit,
    previous: @Composable () -> Unit,
    content: @Composable () -> Unit,
) {
    val progress = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    val currentBack by rememberUpdatedState(onBack)
    val density = LocalDensity.current
    val hasSystemGesture =
        WindowInsets.systemGestures.getLeft(density, LocalLayoutDirection.current) > 0
    var width by remember { mutableFloatStateOf(1f) }
    suspend fun finish(commit: Boolean) {
        val destination = if (commit) 1f else 0f
        progress.animateTo(
            destination,
            tween(
                ((kotlin.math.abs(destination - progress.value)) * PageTransitionMillis).toInt().coerceAtLeast(1),
                easing = LinearEasing,
            ),
        )
        if (commit) {
            // Popping the last route turns `enabled` off, which cancels this handler job at its
            // next suspension point. The commit must still finish, otherwise the cancellation is
            // mistaken for a gesture cancel and the already-revealed page is slid back in.
            withContext(NonCancellable) {
                currentBack()
                // Keep the revealed previous frame in place until navigation is composed.
                // Resetting immediately can draw the old page once at translationX = 0.
                withFrameNanos { }
                withFrameNanos { }
                progress.snapTo(0f)
            }
        } else {
            progress.snapTo(0f)
        }
    }
    PredictiveBackHandler(enabled = enabled) { events ->
        try {
            events.collect { progress.snapTo(it.progress) }
            finish(true)
        } catch (e: CancellationException) {
            scope.launch { finish(false) }
            throw e
        }
    }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        width = constraints.maxWidth.toFloat().coerceAtLeast(1f)
        if (progress.value > 0f)
            Box(
                Modifier.fillMaxSize().graphicsLayer {
                    translationX = -(1f - progress.value) * width
                }
            ) {
                previous()
            }
        Box(Modifier.fillMaxSize().graphicsLayer { translationX = progress.value * width }) {
            content()
        }
        if (enabled && !hasSystemGesture)
            Box(
                Modifier.fillMaxHeight().width(22.dp).pointerInput(enabled, width) {
                    var drag = 0f
                    detectHorizontalDragGestures(
                        onDragStart = { drag = 0f },
                        onHorizontalDrag = { change, amount ->
                            change.consume()
                            drag = (drag + amount).coerceIn(0f, width)
                            scope.launch { progress.snapTo(drag / width) }
                        },
                        onDragEnd = { scope.launch { finish(drag / width > .28f) } },
                        onDragCancel = { scope.launch { finish(false) } },
                    )
                }
            )
    }
}
