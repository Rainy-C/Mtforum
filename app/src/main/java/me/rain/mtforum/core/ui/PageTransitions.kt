package me.rain.mtforum.core.ui

import androidx.compose.animation.ContentTransform
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith

/** Shared duration for page pushes, tab switches and swipe-back settle animations. */
const val PageTransitionMillis = 300

/** Shared full-width push for peer pages and ordinary forward/back navigation. */
fun horizontalPageTransition(forward: Boolean): ContentTransform {
    val direction = if (forward) 1 else -1
    return slideInHorizontally(tween(PageTransitionMillis, easing = FastOutSlowInEasing)) {
            it * direction
        } togetherWith
        slideOutHorizontally(tween(PageTransitionMillis, easing = FastOutSlowInEasing)) {
            -it * direction
        }
}
