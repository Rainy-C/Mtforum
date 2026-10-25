package me.rain.mtforum.feature.forum

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kyant.backdrop.backdrops.layerBackdrop
import com.kyant.backdrop.backdrops.rememberLayerBackdrop
import coil.compose.AsyncImage
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import me.rain.mtforum.core.network.*
import me.rain.mtforum.core.ui.*
import me.rain.mtforum.core.ui.icons.*
import top.yukonga.miuix.kmp.basic.*
import top.yukonga.miuix.kmp.extra.SuperArrow
import top.yukonga.miuix.kmp.extra.DropdownImpl
import top.yukonga.miuix.kmp.icon.MiuixIcons
import top.yukonga.miuix.kmp.icon.icons.useful.*
import top.yukonga.miuix.kmp.theme.MiuixTheme

fun Throwable.readable(): String =
    if (this is ForumException) message ?: "论坛请求失败"
    else "暂时无法连接论坛，请稍后重试（${this::class.simpleName}: ${message.orEmpty().take(80)}）"

@Composable
fun Avatar(url: String?, name: String, size: Int = 38) {
    Box(
        Modifier.size(size.dp).clip(CircleShape).background(MiuixTheme.colorScheme.surface),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            name.take(1).ifBlank { "M" },
            fontSize = (size * .38f).sp,
            fontWeight = FontWeight.Medium,
        )
        if (!url.isNullOrBlank()) AsyncImage(url, null, Modifier.fillMaxSize())
    }
}

@Composable
fun TopicsScreen(
    repository: ForumRepository,
    title: String,
    url: String,
    home: Boolean = false,
    sessionKey: Boolean = false,
    onBack: (() -> Unit)? = null,
    onSearch: () -> Unit = {},
    onCompose: (() -> Unit)? = null,
    onOpen: (String, String) -> Unit,
) {
    var boardTopics by remember(url, sessionKey) { mutableStateOf<List<Topic>>(emptyList()) }
    var boardNext by remember(url, sessionKey) { mutableStateOf<String?>(null) }
    val homePages = remember(repository, sessionKey) { mutableStateMapOf<String, GuideFeedPage>() }
    var selectedMask by rememberSaveable { mutableIntStateOf(1) } // Hot by default.
    // Older installs may restore a multi-select mask. Never query two feeds for a single tab.
    val singleMask = 1 shl selectedMask.countTrailingZeroBits().coerceIn(0, GuideFeeds.views.lastIndex)
    LaunchedEffect(singleMask) {
        if (selectedMask != singleMask) selectedMask = singleMask
    }
    val selectedViews = GuideFeeds.selected(singleMask)
    val topics = if (home) GuideFeeds.merge(selectedViews, homePages) else boardTopics
    val hasMore = if (home) selectedViews.any { homePages[it]?.next != null } else boardNext != null
    var error by remember(url, sessionKey) { mutableStateOf<String?>(null) }
    var loading by remember(url, sessionKey) { mutableStateOf(false) }
    var loadingMore by remember(url, sessionKey) { mutableStateOf(false) }
    var refresh by remember { mutableIntStateOf(0) }
    var nextFeedOffset by remember { mutableIntStateOf(0) }
    var loadMoreJob by remember { mutableStateOf<Job?>(null) }
    val scope = rememberCoroutineScope()
    val scroll = rememberLazyListState()

    LaunchedEffect(url, home, selectedMask, refresh, sessionKey, repository) {
        // Re-selecting a fully cached combination should not trigger a loading flash.
        if (home && selectedViews.all { homePages[it]?.generation == refresh }) {
            error = null
            loading = false
            return@LaunchedEffect
        }
        loading = true
        error = null
        try {
            if (home) {
                // Rapid feed switches should collapse into one set of requests.
                delay(180)
                for (view in selectedViews) {
                    if (homePages[view]?.generation == refresh) continue
                    val target = "${ForumRepository.BaseUrl}/forum.php?mod=guide&view=$view&index=1&mobile=2"
                    try {
                        val result = repository.topics(target, refresh = refresh > 0)
                        homePages[view] = GuideFeedPage(result.first, result.second, refresh)
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        // A bad category must not prevent the other selected feeds loading.
                        error = e.readable()
                    }
                }
            } else {
                val result = repository.topics(url, refresh = refresh > 0)
                boardTopics = result.first
                boardNext = result.second
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            error = e.readable()
        } finally {
            loading = false
        }
    }

    fun reload() {
        loadMoreJob?.cancel()
        refresh++
    }

    Column(Modifier.fillMaxSize()) {
        PageHeader(title, onBack) {
            if (home) {
                GuideFeedSelector(selectedMask) { index ->
                    loadMoreJob?.cancel()
                    selectedMask = 1 shl index
                }
            }
            ToolIcon(MiuixIcons.Useful.Search, "搜索", onClick = onSearch)
            if (onCompose != null) ToolIcon(MiuixIcons.Useful.Edit, "发帖", onClick = onCompose)
            ToolIcon(MiuixIcons.Useful.Refresh, "刷新", !loading && !loadingMore) { reload() }
        }
        if (loading && topics.isEmpty()) {
            Box(Modifier.weight(1f).fillMaxWidth(), Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            LazyColumn(
                state = scroll,
                modifier = Modifier.weight(1f),
                contentPadding = PaddingValues(20.dp, 12.dp, 20.dp, if (home) 128.dp else 36.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                error?.let {
                    item {
                        if (topics.isEmpty()) EmptyState("加载失败", it, action = "重试", onAction = ::reload)
                        else Row(
                            Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Text("部分内容未加载", Modifier.weight(1f), fontSize = 13.sp,
                                color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                            Button(onClick = ::reload, minWidth = 0.dp,
                                insideMargin = PaddingValues(horizontal = 12.dp, vertical = 8.dp)) {
                                Text("重试", fontSize = 13.sp)
                            }
                        }
                    }
                }
                if (topics.isEmpty() && error == null)
                    item { EmptyState("还没有帖子", icon = MiuixNavigationIcons.Community) }
                items(topics, key = { it.id }) { topic ->
                    TopicCard(topic, repository, sessionKey,
                        onAuthor = topic.authorUrl?.let { authorUrl -> { onOpen(topic.author, authorUrl) } },
                    ) { onOpen(topic.title, topic.url) }
                }
                if (loading && topics.isNotEmpty()) {
                    item(key = "guide-loading") {
                        Box(Modifier.fillMaxWidth(), Alignment.Center) { CircularProgressIndicator() }
                    }
                }
                if (hasMore) {
                    item(key = "guide-more") {
                        ActionButton(
                            if (loadingMore || loading) "加载中" else "加载更多",
                            Modifier.fillMaxWidth(),
                            primary = false,
                            loading = loadingMore || loading,
                        ) {
                            if (loading || loadingMore) return@ActionButton
                            loadMoreJob = scope.launch {
                                loadingMore = true
                                error = null
                                try {
                                    if (home) {
                                        // At most two pages per tap, sequentially, to keep forum pressure low.
                                        val eligible = selectedViews.filter { homePages[it]?.next != null }
                                        if (eligible.isNotEmpty()) {
                                            val offset = nextFeedOffset % eligible.size
                                            val toLoad = (eligible.drop(offset) + eligible.take(offset)).take(2)
                                            for (view in toLoad) {
                                                val before = homePages[view] ?: continue
                                                val target = before.next ?: continue
                                                val result = repository.topics(target, refresh = refresh > 0)
                                                homePages[view] = before.copy(
                                                    topics = (before.topics + result.first).distinctBy { it.id },
                                                    next = result.second,
                                                )
                                            }
                                            nextFeedOffset += toLoad.size
                                        }
                                    } else {
                                        val target = boardNext ?: return@launch
                                        val result = repository.topics(target, refresh = refresh > 0)
                                        boardTopics = (boardTopics + result.first).distinctBy { it.id }
                                        boardNext = result.second
                                    }
                                } catch (e: CancellationException) {
                                    throw e
                                } catch (e: Exception) {
                                    error = e.readable()
                                } finally {
                                    loadingMore = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/** Keep Miuix's dropdown visuals, but prevent a wide popup hugging the window edge. */
private object CenteredGuidePopup : PopupPositionProvider {
    override fun getMargins(): PaddingValues = PaddingValues(horizontal = 16.dp, vertical = 8.dp)

    override fun calculatePosition(
        anchorBounds: IntRect,
        windowBounds: IntRect,
        layoutDirection: LayoutDirection,
        popupContentSize: IntSize,
        popupMargin: IntRect,
        alignment: PopupPositionProvider.Align,
    ): IntOffset {
        val availableLeft = windowBounds.left + popupMargin.left
        val availableRight = (windowBounds.right - popupContentSize.width - popupMargin.right)
            .coerceAtLeast(availableLeft)
        val centerX = windowBounds.left + (windowBounds.width - popupContentSize.width) / 2
        val below = anchorBounds.bottom + popupMargin.bottom
        val above = anchorBounds.top - popupContentSize.height - popupMargin.top
        val y = if (below + popupContentSize.height <= windowBounds.bottom) below else above
        val minY = windowBounds.top + popupMargin.top
        val maxY = (windowBounds.bottom - popupContentSize.height - popupMargin.bottom)
            .coerceAtLeast(minY)
        return IntOffset(centerX.coerceIn(availableLeft, availableRight), y.coerceIn(minY, maxY))
    }
}

@Composable
private fun GuideFeedSelector(selectedMask: Int, onSelect: (Int) -> Unit) {
    val expanded = remember { mutableStateOf(false) }
    val selectedIndex = selectedMask.countTrailingZeroBits().coerceIn(0, GuideFeeds.titles.lastIndex)
    Box {
        Button(
            onClick = { expanded.value = true },
            modifier = Modifier.heightIn(min = 40.dp),
            minWidth = 0.dp,
            insideMargin = PaddingValues(horizontal = 11.dp, vertical = 9.dp),
            colors = ButtonDefaults.buttonColors(),
        ) {
            Icon(MiuixIcons.Useful.Order, null, Modifier.size(17.dp),
                tint = MiuixTheme.colorScheme.onSecondaryVariant)
            Spacer(Modifier.width(7.dp))
            Text(GuideFeeds.titles[selectedIndex], fontSize = 13.sp, maxLines = 1,
                color = MiuixTheme.colorScheme.onSecondaryVariant)
        }
        ListPopup(
            show = expanded,
            popupPositionProvider = CenteredGuidePopup,
            alignment = PopupPositionProvider.Align.Right,
            onDismissRequest = { expanded.value = false },
        ) {
            ListPopupColumn {
                GuideFeeds.titles.forEachIndexed { index, title ->
                    DropdownImpl(
                        text = title,
                        optionSize = GuideFeeds.titles.size,
                        isSelected = selectedIndex == index,
                        index = index,
                        onSelectedIndexChange = { selection ->
                            expanded.value = false
                            onSelect(selection)
                        },
                    )
                }
            }
        }
    }
}

@Composable
fun FilterBar(items: List<String>, selected: Int, onSelect: (Int) -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items.forEachIndexed { index, title ->
            Button(
                onClick = { onSelect(index) },
                modifier = Modifier.weight(1f),
                insideMargin = PaddingValues(horizontal = 4.dp, vertical = 10.dp),
                minWidth = 0.dp,
                colors =
                    if (selected == index) ButtonDefaults.buttonColorsPrimary()
                    else ButtonDefaults.buttonColors(),
            ) {
                Text(
                    title,
                    fontSize = 13.sp,
                    color =
                        if (selected == index) MiuixTheme.colorScheme.onPrimary
                        else MiuixTheme.colorScheme.onSecondaryVariant,
                )
            }
        }
    }
}

@Composable
internal fun TopicCard(
    topic: Topic, repository: ForumRepository?, sessionKey: Boolean = false,
    onAuthor: (() -> Unit)? = null, showStats: Boolean = true, onClick: () -> Unit,
) {
    val showImages = LocalShowImages.current
    var previews by remember(topic.id, topic.images, sessionKey) { mutableStateOf(topic.images) }
    LaunchedEffect(topic.id, showImages, topic.hasImageAttachments, topic.hasHiddenContent, sessionKey) {
        if (repository != null && showImages && previews.isEmpty() && topic.hasImageAttachments && !topic.hasHiddenContent) {
            try {
                previews = repository.previewImages(topic)
            } catch (error: CancellationException) {
                throw error
            } catch (_: java.io.IOException) {
                // Keep the compact text card when a thumbnail is unavailable.
            }
        }
    }
    Card(Modifier.fillMaxWidth().clip(RoundedCornerShape(26.dp)).clickable(onClick = onClick)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(11.dp)) {
            // Favorites may provide a thread title but no author or avatar. Do not
            // invent an "unknown author" identity or a fake initial avatar.
            if (topic.author.isNotBlank() || topic.time.isNotBlank() || topic.forum.isNotBlank()) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Row(
                        Modifier.weight(1f).heightIn(min = if (topic.author.isBlank()) 26.dp else 48.dp)
                            .clip(RoundedCornerShape(14.dp))
                            .then(if (onAuthor != null && topic.author.isNotBlank())
                                Modifier.clickable(onClick = onAuthor) else Modifier),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        if (topic.author.isNotBlank()) {
                            Avatar(if (showImages) topic.avatar else null, topic.author, size = 34)
                        }
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            if (topic.author.isNotBlank())
                                Text(topic.author, fontSize = 14.sp, fontWeight = FontWeight.Medium,
                                    maxLines = 1, overflow = TextOverflow.Ellipsis)
                            if (topic.time.isNotBlank())
                                Text(topic.time, fontSize = 11.sp,
                                    color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                        }
                    }
                    if (topic.forum.isNotBlank())
                        Text(topic.forum, modifier = Modifier.widthIn(max = 100.dp),
                            maxLines = 1, overflow = TextOverflow.Ellipsis, fontSize = 12.sp,
                            color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                }
            }
            Text(
                topic.title,
                fontSize = 17.sp,
                fontWeight = FontWeight.SemiBold,
                lineHeight = 25.sp,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            if (topic.hasHiddenContent) HiddenContentBadge()
            if (topic.excerpt.isNotBlank() && topic.excerpt != topic.title)
                Text(
                    topic.excerpt,
                    fontSize = 12.sp,
                    lineHeight = 17.sp,
                    color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            if (showImages && previews.size >= 3)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    previews.take(3).forEach {
                        AsyncImage(
                            it,
                            null,
                            Modifier.weight(1f)
                                .aspectRatio(1.6f)
                                .clip(androidx.compose.foundation.shape.RoundedCornerShape(12.dp)),
                            contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                        )
                    }
                }
            if (showStats) {
                NativeHairline()
                Row(Modifier.fillMaxWidth()) {
                    TopicStat(MiuixIcons.Useful.Like, "赞", topic.likes ?: "—", Modifier.weight(1f))
                    TopicStat(MiuixNavigationIcons.Messages, "回复", topic.replies ?: "—", Modifier.weight(1f))
                    TopicStat(MiuixNavigationIcons.Show, "浏览", topic.views ?: "—", Modifier.weight(1f))
                }
            }
        }
    }
}

/** Distinct but subdued indicator for posts whose body contains restricted/hidden content. */
@Composable
internal fun HiddenContentBadge() {
    val dark = MiuixTheme.colorScheme.background.luminance() < 0.5f
    val accent = if (dark) Color(0xFFFFC887) else Color(0xFF915414)
    val fill = if (dark) Color(0xFFBD803F).copy(alpha = .23f)
               else Color(0xFFE5A155).copy(alpha = .18f)
    Row(
        Modifier.background(fill, RoundedCornerShape(10.dp))
            .padding(horizontal = 10.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(MiuixNavigationIcons.Lock, null, Modifier.size(14.dp), tint = accent)
        Text("含隐藏内容", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = accent)
    }
}

@Composable
private fun TopicStat(
    icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, value: String, modifier: Modifier,
) {
    Row(modifier.padding(vertical = 3.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center) {
        Icon(icon, label, Modifier.size(15.dp), tint = MiuixTheme.colorScheme.onSurfaceVariantSummary)
        Spacer(Modifier.width(6.dp))
        Text(value, fontSize = 12.sp, fontWeight = FontWeight.Medium,
            color = MiuixTheme.colorScheme.onSurfaceVariantSummary, maxLines = 1,
            overflow = TextOverflow.Ellipsis)
    }
}

@Composable
fun CommunityScreen(repository: ForumRepository, onOpen: (String, String) -> Unit) {
    var boards by remember { mutableStateOf(ContentParser.defaultBoards) }
    var refreshing by remember { mutableStateOf(false) }
    var refresh by remember { mutableIntStateOf(0) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(refresh) {
        refreshing = true
        try {
            boards = repository.boards()
            error = null
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            error = e.readable()
        } finally {
            refreshing = false
        }
    }
    Column(Modifier.fillMaxSize()) {
        PageHeader("社区") { ToolIcon(MiuixIcons.Useful.Refresh, "刷新", !refreshing) { refresh++ } }
        LazyColumn(
            contentPadding = PaddingValues(20.dp, 14.dp, 20.dp, 132.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            error?.let {
                item {
                    Card(Modifier.fillMaxWidth()) {
                        Text(
                            it,
                            modifier = Modifier.padding(horizontal = 18.dp, vertical = 16.dp),
                            fontSize = 13.sp,
                            color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                        )
                    }
                }
            }
            item {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    CommunityShortcutCard(
                        title = "排行榜",
                        summary = "看看论坛活跃用户",
                        icon = MiuixIcons.Useful.Order,
                        modifier = Modifier.weight(1f),
                    ) {
                        onOpen(
                            "排行榜",
                            "${ForumRepository.BaseUrl}/misc.php?mod=ranklist&type=member&view=credit&mobile=2",
                        )
                    }
                    CommunityShortcutCard(
                        title = "积分商城",
                        summary = "兑换论坛道具和奖励",
                        icon = MiuixIcons.Useful.Like,
                        modifier = Modifier.weight(1f),
                    ) {
                        onOpen(
                            "积分商城",
                            "${ForumRepository.BaseUrl}/keke_integralmall-keke_integralmall.html",
                        )
                    }
                }
            }
            boards.groupBy { it.group }.forEach { (group, values) ->
                item { CommunitySectionHeader(group) }
                item {
                    Card(Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(vertical = 6.dp)) {
                            values.forEachIndexed { index, board ->
                                CommunityBoardRow(board) {
                                    onOpen(
                                        board.title,
                                        "${ForumRepository.BaseUrl}/forum-${board.id}-1.html",
                                    )
                                }
                                if (index != values.lastIndex) {
                                    Box(Modifier.padding(start = 74.dp, end = 18.dp)) { NativeHairline() }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CommunityShortcutCard(
    title: String,
    summary: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Card(modifier.clip(RoundedCornerShape(26.dp)).clickable(onClick = onClick)) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 18.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Box(
                Modifier.size(42.dp)
                    .clip(RoundedCornerShape(15.dp))
                    .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .06f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(icon, null, Modifier.size(22.dp), tint = MiuixTheme.colorScheme.onSurface)
            }
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(title, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
                Text(summary, fontSize = 12.sp, lineHeight = 18.sp,
                    color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
            }
        }
    }
}

@Composable
private fun CommunitySectionHeader(title: String) {
    Text(
        title,
        modifier = Modifier.padding(start = 6.dp, top = 4.dp, bottom = 2.dp),
        fontSize = 14.sp,
        fontWeight = FontWeight.Medium,
        color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
    )
}

@Composable
private fun CommunityBoardRow(board: ForumBoard, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(
            Modifier.size(42.dp)
                .clip(RoundedCornerShape(15.dp))
                .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .055f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(MiuixNavigationIcons.Community, null, Modifier.size(24.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(board.title, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            val subtitle = board.todayPosts?.let { "今日发帖 $it" } ?: board.summary
            if (subtitle.isNotBlank()) {
                Text(
                    subtitle,
                    fontSize = 12.sp,
                    lineHeight = 18.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                )
            }
        }
        Box(
            Modifier.size(30.dp)
                .clip(CircleShape)
                .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .05f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                MiuixIcons.Useful.Back,
                null,
                Modifier.size(16.dp).rotate(180f),
                tint = MiuixTheme.colorScheme.onSurfaceVariantSummary,
            )
        }
    }
}

@Composable
fun SearchScreen(
    repository: ForumRepository,
    onBack: () -> Unit,
    onOpen: (String, String) -> Unit,
) {
    var query by rememberSaveable { mutableStateOf("") }
    var result by remember { mutableStateOf<NativeDocument?>(null) }
    var topics by remember { mutableStateOf<List<Topic>>(emptyList()) }
    var nextPage by remember { mutableStateOf<String?>(null) }
    var loadingMore by remember { mutableStateOf(false) }
    var moreError by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var searched by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    fun search() {
        if (busy || query.isBlank()) return
        scope.launch {
            busy = true
            error = null
            moreError = null
            nextPage = null
            searched = true
            try {
                val form =
                    repository
                        .document("${ForumRepository.BaseUrl}/search.php?mod=forum&mobile=2", "搜索")
                        .forms
                        .firstOrNull { it.fields.any { f -> f.key == "srchtxt" } }
                        ?: throw ForumException("搜索暂时不可用，请稍后重试")
                val fields =
                    form.fields.filter { it.type == "hidden" }.map { it.key to it.value } +
                        listOf("srchtxt" to query.trim(), "searchsubmit" to "yes", "mod" to "forum")
                val response =
                    repository.submit(
                        form.copy(method = "POST"),
                        fields,
                        RemoteSubmit("搜索", "", ""),
                    )
                result = response.document
                val content = repository.topics(response.document.url)
                topics = content.first
                nextPage = content.second ?: response.document.next
                if (topics.isEmpty() && response.document.blocks.isNotEmpty())
                    error = response.document.blocks.first().text.take(240)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = e.readable()
            } finally {
                busy = false
            }
        }
    }
    fun loadMore() {
        val next = nextPage ?: return
        if (busy || loadingMore) return
        scope.launch {
            loadingMore = true
            moreError = null
            try {
                val (page, following) = repository.topics(next)
                topics = (topics + page).distinctBy { it.id }
                nextPage = following?.takeUnless { it == next }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                moreError = e.readable()
            } finally {
                loadingMore = false
            }
        }
    }
    Column(Modifier.fillMaxSize().imePadding()) {
        PageHeader("搜索", onBack)
        Row(
            Modifier.padding(20.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            TextField(
                query,
                { query = it },
                label = "搜索帖子",
                singleLine = true,
                modifier = Modifier.weight(1f),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                keyboardActions = KeyboardActions(onSearch = { search() }),
            )
            ToolIcon(MiuixIcons.Useful.Search, "搜索", !busy) { search() }
        }
        if (busy)
            Box(Modifier.weight(1f).fillMaxWidth(), Alignment.Center) {
                CircularProgressIndicator()
            }
        else
            LazyColumn(
                contentPadding = PaddingValues(20.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                error?.let { item { EmptyState("搜索结果", it) } }
                if (topics.isEmpty() && error == null)
                    item {
                        EmptyState(
                            if (searched) "没有找到相关帖子" else "发现感兴趣的内容",
                            icon = MiuixIcons.Useful.Search,
                        )
                    }
                items(topics, key = { it.id }) { topic ->
                    TopicCard(topic, repository,
                        onAuthor = topic.authorUrl?.let { authorUrl -> { onOpen(topic.author, authorUrl) } },
                    ) { onOpen(topic.title, topic.url) }
                }
                if (nextPage != null || loadingMore || moreError != null) {
                    item {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            moreError?.let { message ->
                                Text(message, fontSize = 13.sp,
                                    color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                            }
                            if (nextPage != null) ActionButton(
                                if (loadingMore) "加载中" else if (moreError != null) "重试加载" else "加载更多",
                                Modifier.fillMaxWidth(), primary = false, loading = loadingMore,
                            ) { loadMore() }
                        }
                    }
                }
            }
    }
}

@Composable
fun ThreadScreen(
    repository: ForumRepository,
    url: String,
    onBack: () -> Unit,
    loggedIn: Boolean,
    onLogin: () -> Unit,
    onOpen: (String, String) -> Unit,
) {
    var detail by remember(url) { mutableStateOf<TopicDetail?>(null) }
    var error by remember(url) { mutableStateOf<String?>(null) }
    var refresh by remember(url) { mutableIntStateOf(0) }
    var busy by remember(url) { mutableStateOf(false) }
    var moreLoading by remember(url) { mutableStateOf(false) }
    var moreError by remember(url) { mutableStateOf<String?>(null) }
    var visitedPages by remember(url) { mutableStateOf(setOf(url)) }
    var loadMoreJob by remember(url) { mutableStateOf<Job?>(null) }
    var feedback by remember(url) { mutableStateOf<String?>(null) }
    val scroll = rememberLazyListState()
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val commentBackdrop = rememberLayerBackdrop()
    var replyTarget by remember(url) { mutableStateOf<ThreadReplyTarget?>(null) }

    LaunchedEffect(url, refresh) {
        // A refresh replaces the entire accumulated comment stream, not just page one.
        loadMoreJob?.cancel()
        moreLoading = false
        moreError = null
        busy = true
        error = null
        try {
            detail = repository.detail(url)
            visitedPages = setOf(url)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            error = e.readable()
        } finally {
            busy = false
        }
    }

    fun reply(pid: String? = null, author: String? = null) {
        if (!loggedIn) {
            onLogin()
            return
        }
        detail?.let { d ->
            replyTarget = ThreadReplyTarget(
                url = "${ForumRepository.BaseUrl}/forum.php?mod=post&action=reply&tid=${d.tid}&fid=${d.fid}&mobile=2" +
                    (pid?.let { "&repquote=$it" } ?: ""),
                author = author,
            )
        }
    }

    fun share() {
        context.startActivity(
            android.content.Intent.createChooser(
                android.content.Intent(android.content.Intent.ACTION_SEND)
                    .setType("text/plain")
                    .putExtra(android.content.Intent.EXTRA_TEXT, "${detail?.title.orEmpty()}\n$url"),
                "分享帖子",
            )
        )
    }

    fun topicAction(favorite: Boolean) {
        if (!loggedIn) {
            onLogin()
            return
        }
        val tid = detail?.tid ?: return
        if (busy) return
        scope.launch {
            busy = true
            try {
                feedback = repository.topicAction(tid, favorite)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                feedback = e.readable()
            } finally {
                busy = false
            }
        }
    }

    val nextPage = ThreadCommentPages.next(detail, visitedPages)
    fun loadMore() {
        val target = ThreadCommentPages.next(detail, visitedPages) ?: return
        if (busy || moreLoading || moreError != null) return
        moreLoading = true
        loadMoreJob = scope.launch {
            try {
                val page = repository.detail(target)
                val current = detail ?: return@launch
                detail = ThreadCommentPages.append(current, page)
                visitedPages = visitedPages + target
                moreError = null
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                moreError = e.readable()
            } finally {
                moreLoading = false
            }
        }
    }

    // Start the next batch only when the reader approaches the end. No new route, no jump
    // to the top, and no repeated request for a page already received.
    val nearBottom by remember {
        derivedStateOf {
            val layout = scroll.layoutInfo
            val last = layout.visibleItemsInfo.lastOrNull()?.index ?: -1
            layout.totalItemsCount > 0 && last >= layout.totalItemsCount - 3
        }
    }
    LaunchedEffect(nearBottom, nextPage, busy, moreLoading, moreError) {
        if (nearBottom && nextPage != null && !busy && !moreLoading && moreError == null) {
            loadMore()
        }
    }

    Column(Modifier.fillMaxSize()) {
        PageHeader("帖子", onBack) {
            ToolIcon(MiuixIcons.Useful.Share, "分享", onClick = ::share)
            ToolIcon(MiuixIcons.Useful.Refresh, "刷新", !busy && !moreLoading) { refresh++ }
        }
        Box(Modifier.weight(1f)) {
            // Record only the post list. The glass footer is drawn as a sibling,
            // not captured inside its own backdrop (no recursive glass artifact).
            Box(Modifier.fillMaxSize()
                .layerBackdrop(commentBackdrop)
                .background(MiuixTheme.colorScheme.background)) {
                if (busy && detail == null) {
                    Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
                } else {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        state = scroll,
                        contentPadding = PaddingValues(start = 20.dp, top = 14.dp, end = 20.dp, bottom = 116.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        error?.let { reason ->
                            item(key = "thread-error") {
                                EmptyState("加载失败", reason, action = "重试", onAction = { refresh++ })
                            }
                        }
                        detail?.let { data ->
                            item(key = "thread-title") {
                                Text(
                                    data.title,
                                    fontSize = 26.sp,
                                    lineHeight = 36.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    modifier = Modifier.padding(bottom = 4.dp),
                                )
                            }
                            if (data.posts.isEmpty()) {
                                item(key = "thread-empty") {
                                    EmptyState("暂时无法显示帖子", action = "查看论坛提示") {
                                        onOpen(
                                            "论坛提示",
                                            url + if (url.contains("?")) "&nativeview=1" else "?nativeview=1",
                                        )
                                    }
                                }
                            } else {
                                val hasOriginalPost = data.previous == null
                                if (hasOriginalPost) {
                                    val original = data.posts.first()
                                    item(key = "thread-original") {
                                        ThreadPostCard(original, compact = false, onOpen = onOpen,
                                            onReply = { reply(original.id, original.author) })
                                    }
                                }
                                val comments = if (hasOriginalPost) data.posts.drop(1) else data.posts
                                item(key = "thread-comments-heading") {
                                    Row(
                                        Modifier.fillMaxWidth().padding(top = 12.dp, bottom = 2.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(9.dp),
                                    ) {
                                        Text("评论", fontSize = 19.sp, fontWeight = FontWeight.SemiBold)
                                        Text("已加载 ${comments.size} 条", fontSize = 12.sp,
                                            color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                                    }
                                }
                                if (comments.isEmpty() && nextPage == null) {
                                    item(key = "thread-no-comments") {
                                        EmptyState("还没有评论", "来写下第一条评论吧")
                                    }
                                }
                                items(comments, key = { "comment-${it.id}" }) { post ->
                                    ThreadPostCard(post, compact = true, onOpen = onOpen,
                                        onReply = { reply(post.id, post.author) })
                                }
                                if (nextPage != null || moreLoading || moreError != null) {
                                    item(key = "thread-more-comments") {
                                        when {
                                            moreLoading -> Box(Modifier.fillMaxWidth().padding(14.dp), Alignment.Center) {
                                                CircularProgressIndicator()
                                            }
                                            moreError != null -> EmptyState(
                                                "更多评论加载失败", moreError,
                                                action = "重新加载",
                                                onAction = { moreError = null },
                                            )
                                            else -> ActionButton("加载更多评论", Modifier.fillMaxWidth(), primary = false) {
                                                loadMore()
                                            }
                                        }
                                    }
                                } else if (comments.isNotEmpty()) {
                                    item(key = "thread-comments-end") {
                                        Text("已经看到全部评论", Modifier.fillMaxWidth().padding(vertical = 14.dp),
                                            fontSize = 12.sp,
                                            color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                                            textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Column(
                Modifier.align(Alignment.BottomCenter)
                    .navigationBarsPadding()
                    .padding(bottom = 12.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                feedback?.let { message ->
                    Text(
                        message,
                        Modifier.clip(RoundedCornerShape(16.dp))
                            .background(MiuixTheme.colorScheme.surface)
                            .clickable { feedback = null }
                            .padding(horizontal = 16.dp, vertical = 9.dp),
                        fontSize = 12.sp,
                        color = MiuixTheme.colorScheme.onSurface,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                ThreadActionBar(
                    backdrop = commentBackdrop,
                    enabled = !busy,
                    onReply = { reply() },
                    onLike = { topicAction(false) },
                    onFavorite = { topicAction(true) },
                    onShare = ::share,
                    onComments = {
                        val d = detail
                        if (d != null && d.posts.isNotEmpty()) {
                            scope.launch { scroll.animateScrollToItem(if (d.previous == null) 2 else 1) }
                        } else reply()
                    },
                )
            }
        }
    }
    replyTarget?.let { target ->
        ThreadReplySheet(
            repository = repository,
            target = target,
            onDismiss = { replyTarget = null },
            onSubmitted = { result ->
                replyTarget = null
                feedback = result
                refresh++
            },
        )
    }
}

@Composable
private fun ThreadPostCard(
    post: ContentPost,
    compact: Boolean,
    onOpen: (String, String) -> Unit,
    onReply: () -> Unit,
) {
    Card(Modifier.fillMaxWidth()) {
        Column(
            Modifier.padding(horizontal = if (compact) 14.dp else 12.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(if (compact) 10.dp else 8.dp),
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Box(
                    Modifier.clip(CircleShape).clickable(enabled = post.authorUrl != null) {
                        post.authorUrl?.let { onOpen(post.author, it) }
                    },
                ) { Avatar(post.avatar, post.author, size = if (compact) 34 else 30) }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(post.author, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                    if (post.time.isNotBlank()) Text(
                        post.time, fontSize = 11.sp,
                        color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                    )
                }
                if (post.floor.isNotBlank()) Text(
                    post.floor, fontSize = 12.sp,
                    color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                )
            }
            RichPostBody(post.html, onOpen, compact = compact, images = post.images)
            PostAttachments.visibleAdditionalLinks(post.html, post.links).forEach { link ->
                SuperArrow(
                    title = link.text.take(70),
                    modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)),
                    onClick = { onOpen(link.text, link.url) },
                )
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                Row(
                    Modifier.clip(RoundedCornerShape(18.dp))
                        .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .055f))
                        .clickable(onClick = onReply)
                        .padding(horizontal = 12.dp, vertical = 7.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Icon(MiuixNavigationIcons.Messages, null, Modifier.size(15.dp),
                        tint = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                    Text("回复", fontSize = 12.sp,
                        color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                }
            }
        }
    }
}
