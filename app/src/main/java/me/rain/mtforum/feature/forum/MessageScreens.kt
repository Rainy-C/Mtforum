package me.rain.mtforum.feature.forum

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import coil.compose.AsyncImage
import kotlinx.coroutines.*
import me.rain.mtforum.core.network.*
import me.rain.mtforum.core.ui.*
import me.rain.mtforum.core.ui.icons.*
import top.yukonga.miuix.kmp.basic.*
import top.yukonga.miuix.kmp.icon.MiuixIcons
import top.yukonga.miuix.kmp.icon.icons.useful.*
import top.yukonga.miuix.kmp.theme.MiuixTheme

@Composable
fun ConversationList(repository: ForumRepository, onOpen: (String, String) -> Unit) {
    var data by remember { mutableStateOf<List<ConversationSummary>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var refresh by remember { mutableIntStateOf(0) }
    LaunchedEffect(refresh) {
        loading = true
        error = null
        try {
            data = repository.conversations()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            error = e.readable()
        } finally {
            loading = false
        }
    }
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(20.dp, 8.dp, 20.dp, 120.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (loading && data.isEmpty())
            item {
                Box(Modifier.fillMaxWidth().padding(60.dp), Alignment.Center) {
                    CircularProgressIndicator()
                }
            }
        error?.let { item { EmptyState("加载失败", it, action = "重试", onAction = { refresh++ }) } }
        if (!loading && data.isEmpty() && error == null)
            item { EmptyState("还没有私信", icon = MiuixNavigationIcons.Messages) }
        items(data, key = { it.uid }) { item ->
            Card(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(26.dp)).clickable {
                    onOpen(
                        item.name,
                        "${ForumRepository.BaseUrl}/home.php?mod=space&do=pm&subop=view&touid=${item.uid}&mobile=2",
                    )
                }
            ) {
                Row(
                    Modifier.padding(horizontal = 15.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Avatar(item.avatar, item.name, 42)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                item.name,
                                Modifier.weight(1f),
                                fontSize = 16.sp,
                                fontWeight = FontWeight.SemiBold,
                            )
                            Text(
                                item.time,
                                fontSize = 11.sp,
                                color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                            )
                        }
                        Text(
                            item.text,
                            fontSize = 13.sp,
                            color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                            maxLines = 1,
                            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                        )
                    }
                    if (item.unread)
                        Box(
                            Modifier.size(7.dp)
                                .background(
                                    MiuixTheme.colorScheme.primary,
                                    RoundedCornerShape(4.dp),
                                )
                        )
                }
            }
        }
        item {
            ActionButton(
                "刷新",
                Modifier.fillMaxWidth(),
                primary = false,
                loading = loading,
                icon = MiuixIcons.Useful.Refresh,
            ) {
                refresh++
            }
        }
    }
}

@Composable
fun ConversationScreen(
    repository: ForumRepository,
    uid: String,
    title: String,
    onBack: () -> Unit,
    onOpen: (String, String) -> Unit,
) {
    var conversation by remember(uid) { mutableStateOf<Conversation?>(null) }
    var text by remember(uid) { mutableStateOf("") }
    var sending by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var refresh by remember { mutableIntStateOf(0) }
    val owner = LocalLifecycleOwner.current
    val scroll = rememberLazyListState()
    val scope = rememberCoroutineScope()
    LaunchedEffect(uid, refresh, owner) {
        owner.lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            while (true) {
                try {
                    val atBottom =
                        conversation == null ||
                            scroll.layoutInfo.visibleItemsInfo.lastOrNull()?.index ==
                                (conversation?.messages?.lastIndex ?: -1)
                    conversation = repository.conversation(uid)
                    error = null
                    if (atBottom && conversation!!.messages.isNotEmpty())
                        scroll.scrollToItem(conversation!!.messages.lastIndex)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    error = e.readable()
                }
                delay(10000)
            }
        }
    }
    Column(Modifier.fillMaxSize().imePadding()) {
        PageHeader(conversation?.name?.ifBlank { title } ?: title, onBack) {
            ToolIcon(MiuixIcons.Useful.Personal, "查看资料") {
                onOpen(
                    "个人资料",
                    "${ForumRepository.BaseUrl}/home.php?mod=space&uid=$uid&do=profile&mobile=2",
                )
            }
            ToolIcon(MiuixIcons.Useful.Refresh, "刷新") { refresh++ }
        }
        error?.let { Text(it, Modifier.padding(20.dp), fontSize = 13.sp) }
        if (conversation == null && error == null)
            Box(Modifier.weight(1f).fillMaxWidth(), Alignment.Center) {
                CircularProgressIndicator()
            }
        else
            LazyColumn(
                Modifier.weight(1f),
                state = scroll,
                contentPadding = PaddingValues(20.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                items(conversation?.messages.orEmpty()) { item ->
                    Column(
                        Modifier.fillMaxWidth(),
                        horizontalAlignment = if (item.mine) Alignment.End else Alignment.Start,
                    ) {
                        if (item.time.isNotBlank())
                            Text(
                                item.time,
                                Modifier.padding(bottom = 6.dp),
                                fontSize = 11.sp,
                                color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                            )
                        Column(
                            Modifier.widthIn(max = 300.dp)
                                .background(
                                    if (item.mine) MiuixTheme.colorScheme.primary
                                    else MiuixTheme.colorScheme.surface,
                                    RoundedCornerShape(18.dp),
                                )
                                .padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            if (item.text.isNotBlank())
                                Text(
                                    item.text,
                                    fontSize = 16.sp,
                                    lineHeight = 24.sp,
                                    color =
                                        if (item.mine) MiuixTheme.colorScheme.onPrimary
                                        else MiuixTheme.colorScheme.onSurface,
                                )
                            if (LocalShowImages.current)
                                item.images.forEach { image ->
                                    AsyncImage(
                                        image,
                                        "消息图片",
                                        Modifier.fillMaxWidth().heightIn(max = 260.dp)
                                            .clip(RoundedCornerShape(14.dp)).clickable {
                                            onOpen("图片", image)
                                        },
                                    )
                                }
                        }
                    }
                }
            }
        Row(
            Modifier.fillMaxWidth().navigationBarsPadding().padding(14.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TextField(
                text,
                { text = it },
                label = "发送消息",
                modifier = Modifier.weight(1f),
                maxLines = 4,
                enabled = !sending,
            )
            ActionButton(
                "发送",
                enabled = text.isNotBlank() && conversation != null,
                loading = sending,
            ) {
                scope.launch {
                    sending = true
                    try {
                        repository.sendPrivateMessage(conversation!!, text)
                        text = ""
                        refresh++
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        error = e.readable()
                    } finally {
                        sending = false
                    }
                }
            }
        }
    }
}
