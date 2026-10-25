package me.rain.mtforum.feature.forum

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlin.math.roundToInt
import me.rain.mtforum.core.network.ContentLink
import me.rain.mtforum.core.network.ForumRepository
import me.rain.mtforum.core.network.NativeContentKind
import me.rain.mtforum.core.network.NativeDocument
import me.rain.mtforum.core.ui.ActionButton
import me.rain.mtforum.core.ui.EmptyState
import me.rain.mtforum.core.ui.PageHeader
import me.rain.mtforum.core.ui.ToolIcon
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import top.yukonga.miuix.kmp.basic.CircularProgressIndicator
import top.yukonga.miuix.kmp.basic.Text
import top.yukonga.miuix.kmp.icon.MiuixIcons
import top.yukonga.miuix.kmp.icon.icons.useful.Refresh
import top.yukonga.miuix.kmp.theme.MiuixTheme

/** Rank categories are internal tabs, never new routes in the app navigation stack. */
internal fun isRankingsUrl(raw: String): Boolean {
    val url = raw.toHttpUrlOrNull() ?: return false
    return url.host == ForumRepository.Host &&
        (url.queryParameter("mod") == "ranklist" || url.encodedPath.contains("ranklist"))
}

/** Ignore pagination and mobile-rendering flags when identifying a leaderboard category. */
private fun rankingUrlKey(raw: String, ignorePage: Boolean): String {
    val url = raw.toHttpUrlOrNull() ?: return raw
    val parameters = url.queryParameterNames
        .filterNot { it == "mobile" || ignorePage && it == "page" }
        .sorted()
        .flatMap { name -> url.queryParameterValues(name).map { value -> name to value } }
    return url.encodedPath + "?" + parameters.joinToString("&") { "${it.first}=${it.second.orEmpty()}" }
}

internal fun rankingTabKey(raw: String): String = rankingUrlKey(raw, ignorePage = true)
internal fun rankingPageKey(raw: String): String = rankingUrlKey(raw, ignorePage = false)

internal fun rankingTabs(document: NativeDocument): List<ContentLink> =
    document.blocks.asSequence()
        .filter { it.kind == NativeContentKind.Navigation }
        .flatMap { it.links.asSequence() }
        .filter { isRankingsUrl(it.url) && it.text.isNotBlank() }
        .distinctBy { rankingTabKey(it.url) }
        .toList()

private data class RankingTabBounds(val leftPx: Int, val widthPx: Int)

/**
 * Keep the highlight on a single layer. The position/width interpolate between
 * measured tab bounds so a selection change glides, rather than flashing a new fill.
 */
@Composable
private fun AnimatedRankingTabs(
    tabs: List<ContentLink>,
    currentUrl: String,
    onSelect: (ContentLink) -> Unit,
) {
    val selectedKey = rankingTabKey(currentUrl)
    val density = LocalDensity.current
    val scrollState = rememberScrollState()
    val bounds = remember { mutableStateMapOf<String, RankingTabBounds>() }
    var viewportWidthPx by remember { mutableIntStateOf(0) }
    val pillLeft = remember { Animatable(0f) }
    val pillWidth = remember { Animatable(0f) }
    var previousSelection by remember { mutableStateOf<String?>(null) }
    val activeBounds = bounds[selectedKey]
    val transition = tween<Float>(durationMillis = 210, easing = FastOutSlowInEasing)

    LaunchedEffect(selectedKey, activeBounds) {
        val target = activeBounds ?: return@LaunchedEffect
        val changedTab = previousSelection != null && previousSelection != selectedKey
        previousSelection = selectedKey
        if (changedTab) {
            coroutineScope {
                launch { pillLeft.animateTo(target.leftPx.toFloat(), transition) }
                launch { pillWidth.animateTo(target.widthPx.toFloat(), transition) }
            }
        } else {
            // On first display or a font/layout change, jump to the true bounds;
            // otherwise the indicator incorrectly flies in from the screen edge.
            pillLeft.snapTo(target.leftPx.toFloat())
            pillWidth.snapTo(target.widthPx.toFloat())
        }
    }

    LaunchedEffect(selectedKey, activeBounds, viewportWidthPx) {
        val target = activeBounds ?: return@LaunchedEffect
        if (viewportWidthPx == 0) return@LaunchedEffect
        val edge = with(density) { 20.dp.roundToPx() }
        val left = target.leftPx + edge
        val right = left + target.widthPx
        val visibleLeft = scrollState.value + edge
        val visibleRight = scrollState.value + viewportWidthPx - edge
        val scrollTarget = when {
            left < visibleLeft -> target.leftPx
            right > visibleRight -> right - viewportWidthPx + edge
            else -> null
        }
        if (scrollTarget != null) {
            scrollState.animateScrollTo(scrollTarget.coerceIn(0, scrollState.maxValue), tween(230))
        }
    }

    Box(
        Modifier.fillMaxWidth()
            .onSizeChanged { viewportWidthPx = it.width }
            .horizontalScroll(scrollState)
            .padding(horizontal = 20.dp, vertical = 10.dp),
    ) {
        // The indicator lives on ONE draw layer instead of a separately measured Box.
        // Reading Animatable values inside drawBehind only invalidates drawing, not layout.
        val highlight = MiuixTheme.colorScheme.onSurface.copy(alpha = .11f)
        Box(
            Modifier.drawBehind {
                val width = pillWidth.value
                if (width > .5f) {
                    drawRoundRect(
                        color = highlight,
                        topLeft = Offset(pillLeft.value, 0f),
                        size = Size(width, 48.dp.toPx()),
                        cornerRadius = CornerRadius(18.dp.toPx()),
                    )
                }
            }
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                tabs.forEach { tab ->
                    val key = rankingTabKey(tab.url)
                    val selected = key == selectedKey
                    Box(
                        Modifier.onGloballyPositioned { coordinates ->
                                val measured = RankingTabBounds(
                                    coordinates.positionInParent().x.roundToInt(),
                                    coordinates.size.width,
                                )
                                if (bounds[key] != measured) bounds[key] = measured
                            }
                            .clip(RoundedCornerShape(18.dp))
                            .clickable { onSelect(tab) }
                            .heightIn(min = 48.dp)
                            .padding(horizontal = 19.dp, vertical = 13.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            tab.text,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Medium,
                            color = if (selected) MiuixTheme.colorScheme.onSurface
                                    else MiuixTheme.colorScheme.onSurfaceVariantSummary,
                        )
                    }
                }
            }
        }
    }
}

@Composable
internal fun RankingsScreen(
    repository: ForumRepository,
    initialUrl: String,
    onBack: (() -> Unit)?,
    onOpen: (String, String) -> Unit,
) {
    var currentUrl by rememberSaveable(initialUrl) { mutableStateOf(initialUrl) }
    val documents = remember(initialUrl) { mutableStateMapOf<String, NativeDocument>() }
    val tabs = remember(initialUrl) { mutableStateListOf<ContentLink>() }
    val scrollStates = rememberSaveableStateHolder()
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var refreshSequence by remember { mutableIntStateOf(0) }
    var forceRefreshUrl by remember { mutableStateOf<String?>(null) }
    val activeDocument = documents[rankingPageKey(currentUrl)]

    LaunchedEffect(currentUrl, refreshSequence) {
        val requestedUrl = currentUrl
        val requestedKey = rankingPageKey(requestedUrl)
        val forced = forceRefreshUrl == requestedUrl
        if (documents[requestedKey] != null && !forced) {
            error = null
            loading = false
            return@LaunchedEffect
        }
        loading = true
        error = null
        try {
            val result = repository.document(requestedUrl, "排行榜")
            // Cache each fetched category independently. Returning to it is instant and free.
            documents[requestedKey] = result
            for (tab in rankingTabs(result)) {
                if (tabs.none { rankingTabKey(it.url) == rankingTabKey(tab.url) }) tabs.add(tab)
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            error = e.readable()
        } finally {
            if (forced && forceRefreshUrl == requestedUrl) forceRefreshUrl = null
            loading = false
        }
    }

    Column(Modifier.fillMaxSize()) {
        PageHeader("排行榜", onBack) {
            ToolIcon(MiuixIcons.Useful.Refresh, "刷新榜单", enabled = !loading) {
                forceRefreshUrl = currentUrl
                refreshSequence++
            }
        }
        if (tabs.isNotEmpty()) {
            AnimatedRankingTabs(
                tabs = tabs,
                currentUrl = currentUrl,
                onSelect = { tab ->
                    if (rankingPageKey(currentUrl) != rankingPageKey(tab.url)) currentUrl = tab.url
                },
            )
        }
        if (activeDocument == null && loading) {
            Box(Modifier.weight(1f).fillMaxWidth(), Alignment.Center) { CircularProgressIndicator() }
        } else {
            // Each tab keeps its own list offset, including when the user opens a profile.
            scrollStates.SaveableStateProvider(rankingPageKey(currentUrl)) {
                val scroll = rememberLazyListState()
                LazyColumn(
                    modifier = Modifier.weight(1f).fillMaxWidth(),
                    state = scroll,
                    contentPadding = PaddingValues(20.dp, 12.dp, 20.dp, 34.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    if (loading) {
                        item(key = "refreshing") {
                            Box(Modifier.fillMaxWidth(), Alignment.Center) { CircularProgressIndicator() }
                        }
                    }
                    error?.let { message ->
                        item(key = "error") {
                            EmptyState("榜单加载失败", message, action = "重试", onAction = {
                                forceRefreshUrl = currentUrl
                                refreshSequence++
                            })
                        }
                    }
                    val doc = activeDocument
                    if (doc != null) {
                        val blocks = doc.blocks.filter { it.kind != NativeContentKind.Navigation }
                        items(blocks, key = { block ->
                            "${block.rank}|${block.primaryLink?.url}|${block.title}"
                        }) { block ->
                            NativeContentItem(block, doc.url) { link -> onOpen(link.text, link.url) }
                        }
                        if (blocks.isEmpty() && error == null && !loading) {
                            item(key = "empty") { EmptyState("榜单暂无内容") }
                        }
                        if (doc.previous != null || doc.next != null) {
                            item(key = "pagination") {
                                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                    doc.previous?.let { previous ->
                                        ActionButton("上一页", Modifier.weight(1f), primary = false) {
                                            currentUrl = previous
                                        }
                                    }
                                    doc.next?.let { next ->
                                        ActionButton("下一页", Modifier.weight(1f), primary = false) {
                                            currentUrl = next
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
