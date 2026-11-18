package me.rain.mtforum.feature.forum

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.border
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.text.BasicTextField
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextOverflow
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
        // The list HTML often omits member presence, while a conversation
        // contains it. Enrich a bounded set of visible rows using shared cache.
        // Resolve a bounded set together and update their rings as ONE batch,
        // rather than visibly changing avatar outlines one by one.
        coroutineScope {
            val snapshot = data
            val resolved = snapshot.take(7).filter { it.online == null }
                .map { item ->
                    async {
                        val presence = try {
                            withTimeoutOrNull(5500L) {
                                repository.resolveConversationPresence(item.uid)
                            }
                        } catch (e: CancellationException) {
                            throw e
                        } catch (_: Exception) {
                            null
                        }
                        item.uid to presence
                    }
                }.awaitAll().toMap()
            if (resolved.isNotEmpty()) {
                data = snapshot.map { item ->
                    val presence = resolved[item.uid]
                    if (presence == null) item else item.copy(online = presence)
                }
            }
        }
    }
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 6.dp, bottom = 112.dp),
        verticalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        item {
            Row(
                Modifier.fillMaxWidth().padding(start = 7.dp, end = 2.dp, bottom = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("最近会话", Modifier.weight(1f),
                    fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                Text(
                    if (loading) "同步中…" else "刷新",
                    Modifier.clip(RoundedCornerShape(12.dp))
                        .clickable(enabled = !loading) { refresh++ }
                        .padding(horizontal = 12.dp, vertical = 9.dp),
                    fontSize = 12.sp,
                    color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                )
            }
        }
        if (loading && data.isEmpty()) item {
            Box(Modifier.fillMaxWidth().padding(vertical = 58.dp), Alignment.Center) {
                CircularProgressIndicator()
            }
        }
        error?.let { reason ->
            item { EmptyState("加载失败", reason, action = "重试", onAction = { refresh++ }) }
        }
        if (!loading && data.isEmpty() && error == null) item {
            EmptyState("还没有私信", icon = MiuixNavigationIcons.Messages)
        }
        items(data, key = { it.uid }) { item ->
            Row(
                Modifier.fillMaxWidth()
                    .clip(RoundedCornerShape(18.dp))
                    .background(MiuixTheme.colorScheme.surface)
                    .clickable {
                        onOpen(
                            item.name,
                            "${ForumRepository.BaseUrl}/home.php?mod=space&do=pm&subop=view&touid=${item.uid}&mobile=2",
                        )
                    }
                    .heightIn(min = 72.dp)
                    .padding(horizontal = 13.dp, vertical = 11.dp),
                horizontalArrangement = Arrangement.spacedBy(11.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                val knownPresence = repository.cachedConversationPresence(item.uid) ?: item.online
                val ringColor by animateColorAsState(
                    targetValue = when (knownPresence) {
                        true -> Color(0xFF36B97C)
                        false -> Color(0xFFAFB4BD)
                        null -> Color.Transparent
                    },
                    animationSpec = tween(240),
                    label = "presence-avatar-${item.uid}",
                )
                Box(
                    Modifier.border(2.dp, ringColor, CircleShape).padding(3.dp),
                ) {
                    Avatar(item.avatar, item.name, 42)
                }
                Column(
                    Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            item.name,
                            Modifier.weight(1f),
                            fontSize = 15.sp,
                            fontWeight = if (item.unread) FontWeight.SemiBold else FontWeight.Medium,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Text(
                            item.time,
                            fontSize = 10.sp,
                            color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                        )
                    }
                    Text(
                        item.text.ifBlank { "图片或表情" },
                        fontSize = 12.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                    )
                }
                if (item.unread) {
                    Box(
                        Modifier.size(7.dp).background(
                            MiuixTheme.colorScheme.primary, RoundedCornerShape(50),
                        )
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun PrivateBubble(message: ChatMessage, onPreview: (String) -> Unit) {
    val parts = message.parts.ifEmpty {
        buildList {
            if (message.text.isNotBlank()) add(ChatPart(text = message.text))
            message.images.forEach { image ->
                add(ChatPart(imageUrl = image, smiley = ContentParser.isSmileyUrl(image)))
            }
        }
    }
    val sticker = parts.size == 1 && parts[0].smiley
    val bg = if (message.mine) MiuixTheme.colorScheme.primary else MiuixTheme.colorScheme.surface
    val foreground = if (message.mine) MiuixTheme.colorScheme.onPrimary
        else MiuixTheme.colorScheme.onSurface
    val shape = RoundedCornerShape(
        topStart = 18.dp, topEnd = 18.dp,
        bottomStart = if (message.mine) 18.dp else 7.dp,
        bottomEnd = if (message.mine) 7.dp else 18.dp,
    )
    Column(
        Modifier.widthIn(max = 286.dp).clip(shape)
            .background(if (sticker) Color.Transparent else bg)
            .padding(if (sticker) 2.dp else 12.dp)
    ) {
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(3.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            parts.forEach { part ->
                val image = part.imageUrl
                when {
                    image == null && part.text.isNotBlank() -> Box(
                        Modifier.heightIn(min = 23.dp),
                        contentAlignment = Alignment.CenterStart,
                    ) {
                        Text(part.text, fontSize = 15.sp, lineHeight = 22.sp,
                            color = foreground)
                    }
                    image != null && LocalShowImages.current -> {
                        val modifier = if (part.smiley) Modifier.size(if (sticker) 46.dp else 19.dp)
                            else Modifier.widthIn(max = 220.dp).heightIn(max = 230.dp)
                        Box(
                            if (part.smiley && !sticker) Modifier.heightIn(min = 23.dp)
                            else Modifier,
                            contentAlignment = Alignment.Center,
                        ) {
                            AsyncImage(image, if (part.smiley) "表情" else "消息图片",
                                modifier.clip(RoundedCornerShape(if (part.smiley) 6.dp else 13.dp))
                                    .clickable { onPreview(image) },
                                contentScale = ContentScale.Fit)
                        }
                    }
                    image != null -> Text("[图片]", Modifier.clickable { onPreview(image) },
                        fontSize = 13.sp, color = foreground)
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ConversationScreen(
    repository: ForumRepository,
    uid: String,
    title: String,
    onBack: () -> Unit,
    onOpen: (String, String) -> Unit,
) {
    var conversation by remember(uid) { mutableStateOf<Conversation?>(null) }
    val inlineDraft = remember(uid) { ForumInlineEditorState() }
    val text = inlineDraft.markup
    var showSmileys by remember(uid) { mutableStateOf(false) }
    var showImageUrl by remember(uid) { mutableStateOf(false) }
    var showAttachmentMenu by remember(uid) { mutableStateOf(false) }
    var imageUrl by remember(uid) { mutableStateOf("") }
    var previewImage by remember(uid) { mutableStateOf<String?>(null) }
    var sending by remember(uid) { mutableStateOf(false) }
    var uploading by remember(uid) { mutableStateOf(false) }
    var error by remember(uid) { mutableStateOf<String?>(null) }
    var refresh by remember(uid) { mutableIntStateOf(0) }
    val context = LocalContext.current
    val keyboard = androidx.compose.ui.platform.LocalSoftwareKeyboardController.current
    val owner = LocalLifecycleOwner.current
    val scroll = rememberLazyListState()
    val scope = rememberCoroutineScope()
    val pickImage = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        val active = conversation
        if (uri != null && active != null && !sending && !uploading) {
            scope.launch {
                uploading = true
                error = null
                try {
                    val (bytes, filename, type) = withContext(Dispatchers.IO) {
                        val mime = context.contentResolver.getType(uri) ?: "image/jpeg"
                        val limit = (active.upload?.maxBytes ?: 8 * 1024 * 1024)
                            .coerceAtMost(10 * 1024 * 1024)
                        val data = context.contentResolver.openInputStream(uri)?.use {
                            it.readNBytes(limit + 1)
                        } ?: throw ForumException("无法读取图片")
                        if (data.size > limit) throw ForumException("图片超出论坛限制")
                        var name = "picture.jpg"
                        context.contentResolver.query(
                            uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME),
                            null, null, null,
                        )?.use { if (it.moveToFirst()) name = it.getString(0) ?: name }
                        Triple(data, name, mime)
                    }
                    val tag = repository.uploadPrivateImage(active, bytes, filename, type)
                    inlineDraft.insertMedia(uri.toString(), tag, image = true)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    error = e.readable()
                    showImageUrl = true
                } finally {
                    uploading = false
                }
            }
        }
    }

    LaunchedEffect(uid, refresh, owner) {
        owner.lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            while (true) {
                try {
                    val atBottom = conversation == null ||
                        scroll.layoutInfo.visibleItemsInfo.lastOrNull()?.index ==
                            (conversation?.messages?.lastIndex ?: -1)
                    val incoming = repository.conversation(uid)
                    conversation = incoming
                    if (atBottom && incoming.messages.isNotEmpty())
                        scroll.scrollToItem(incoming.messages.lastIndex)
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
        val rawName = conversation?.name?.ifBlank { title } ?: title
        val online = conversation?.online ?: ContentParser.presenceFromLabel(rawName)
        val displayName = ContentParser.displayMemberName(rawName).ifBlank { title }
        Row(
            Modifier.fillMaxWidth().statusBarsPadding().heightIn(min = 64.dp)
                .padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            ToolIcon(MiuixIcons.Useful.Back, "返回", onClick = onBack)
            Row(
                Modifier.weight(1f).padding(start = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(7.dp),
            ) {
                Text(
                    displayName,
                    Modifier.weight(1f, fill = false),
                    fontSize = 19.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (online != null) {
                    Row(
                        Modifier.clip(RoundedCornerShape(50))
                            .background(
                                if (online) Color(0xFF32B67C).copy(alpha = .12f)
                                else Color(0xFF969DA9).copy(alpha = .13f),
                            )
                            .padding(horizontal = 8.dp, vertical = 5.dp),
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(Modifier.size(6.dp).background(
                            if (online) Color(0xFF32B67C) else Color(0xFF969DA9),
                            CircleShape,
                        ))
                        Text(
                            if (online) "在线" else "离线",
                            fontSize = 11.sp,
                            color = if (online) Color(0xFF259567) else Color(0xFF7F8792),
                        )
                    }
                }
            }
            ToolIcon(MiuixIcons.Useful.Personal, "查看资料") {
                onOpen("个人资料",
                    "${ForumRepository.BaseUrl}/home.php?mod=space&uid=$uid&do=profile&mobile=2")
            }
            ToolIcon(MiuixIcons.Useful.Refresh, "刷新") { refresh++ }
        }
        if (conversation == null && error == null) {
            Box(Modifier.weight(1f).fillMaxWidth(), Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            LazyColumn(
                Modifier.weight(1f).fillMaxWidth(),
                state = scroll,
                contentPadding = PaddingValues(16.dp, 10.dp, 16.dp, 12.dp),
                verticalArrangement = Arrangement.spacedBy(7.dp),
            ) {
                items(conversation?.messages.orEmpty()) { item ->
                    Column(
                        Modifier.fillMaxWidth(),
                        horizontalAlignment = if (item.mine) Alignment.End else Alignment.Start,
                    ) {
                        if (item.time.isNotBlank())
                            Text(item.time, Modifier.padding(horizontal = 5.dp, vertical = 2.dp),
                                fontSize = 10.sp,
                                color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                        PrivateBubble(item, onPreview = { previewImage = it })
                    }
                }
            }
        }
        error?.let { value ->
            Text(value, Modifier.fillMaxWidth().padding(horizontal = 17.dp, vertical = 5.dp),
                fontSize = 12.sp,
                color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                maxLines = 3, overflow = TextOverflow.Ellipsis)
        }
        if (showImageUrl) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 15.dp, vertical = 5.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TextField(imageUrl, { imageUrl = it }, label = "https:// 图片链接",
                    modifier = Modifier.weight(1f), maxLines = 1)
                ActionButton("加入", enabled = imageUrl.startsWith("https://")) {
                    val url = imageUrl.trim()
                    if (!url.contains('[') && !url.contains(']')) {
                        inlineDraft.insertMedia(url, "[img]$url[/img]", image = true)
                        imageUrl = ""
                        showImageUrl = false
                    }
                }
            }
        }
        if (showSmileys) {
            ForumSmileyPicker(Modifier.fillMaxWidth().height(202.dp)
                .padding(horizontal = 16.dp, vertical = 5.dp)) { code ->
                val url = code.removePrefix("[img]").removeSuffix("[/img]")
                if (url.startsWith("https://")) inlineDraft.insertMedia(url, code)
            }
        }
        Column(
            Modifier.fillMaxWidth()
                .background(MiuixTheme.colorScheme.background)
                .navigationBarsPadding()
                .padding(horizontal = 12.dp, vertical = 7.dp),
            verticalArrangement = Arrangement.spacedBy(7.dp),
        ) {
            if (showAttachmentMenu) {
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(17.dp))
                        .background(MiuixTheme.colorScheme.surface)
                        .padding(horizontal = 11.dp, vertical = 6.dp),
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        "从相册选择",
                        Modifier.clip(RoundedCornerShape(11.dp))
                            .clickable(enabled = !sending && !uploading) {
                                showAttachmentMenu = false
                                pickImage.launch("image/*")
                            }.padding(horizontal = 10.dp, vertical = 9.dp),
                        fontSize = 13.sp,
                    )
                    Text(
                        "图片链接",
                        Modifier.clip(RoundedCornerShape(11.dp))
                            .clickable {
                                showAttachmentMenu = false
                                showImageUrl = !showImageUrl
                            }.padding(horizontal = 10.dp, vertical = 9.dp),
                        fontSize = 13.sp,
                    )
                }
            }
            val canSend = conversation != null && !sending && !uploading &&
                text.isNotBlank()
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(7.dp),
                verticalAlignment = Alignment.Bottom,
            ) {
                Box(
                    Modifier.size(43.dp).clip(RoundedCornerShape(15.dp))
                        .background(MiuixTheme.colorScheme.surface)
                        .clickable(enabled = !sending && !uploading) {
                            showAttachmentMenu = !showAttachmentMenu
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    Text("＋", fontSize = 24.sp, color = MiuixTheme.colorScheme.onSurface)
                }
                ForumInlineEditor(
                    state = inlineDraft,
                    enabled = !sending && !uploading,
                    hint = if (uploading) "图片上传中…" else "发送消息…",
                    textSizeSp = 14f,
                    modifier = Modifier.weight(1f).heightIn(min = 43.dp, max = 156.dp)
                        .clip(RoundedCornerShape(19.dp))
                        .background(MiuixTheme.colorScheme.surface)
                        .padding(horizontal = 12.dp, vertical = 10.dp),
                    onFocused = { showSmileys = false },
                    centerSingleLine = true,
                )
                Box(
                    Modifier.size(43.dp).clip(RoundedCornerShape(15.dp))
                        .background(if (showSmileys) MiuixTheme.colorScheme.onSurface.copy(alpha = .12f)
                            else MiuixTheme.colorScheme.surface)
                        .clickable {
                            showSmileys = !showSmileys
                            showAttachmentMenu = false
                            if (showSmileys) keyboard?.hide() else keyboard?.show()
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(if (showSmileys) "⌨" else "☺", fontSize = 22.sp,
                        color = MiuixTheme.colorScheme.onSurface)
                }
                Box(
                    Modifier.width(55.dp).height(43.dp).clip(RoundedCornerShape(15.dp))
                        .background(if (canSend) MiuixTheme.colorScheme.primary
                            else MiuixTheme.colorScheme.surface)
                        .clickable(enabled = canSend) {
                            val active = conversation
                            if (active != null) scope.launch {
                                sending = true
                                error = null
                                try {
                                    repository.sendPrivateMessage(active, inlineDraft.markup)
                                    inlineDraft.clear()
                                    showSmileys = false
                                    refresh++
                                } catch (e: CancellationException) {
                                    throw e
                                } catch (e: Exception) {
                                    error = e.readable()
                                } finally {
                                    sending = false
                                }
                            }
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    if (sending || uploading) CircularProgressIndicator(size = 17.dp)
                    else Text("发送", fontSize = 13.sp, fontWeight = FontWeight.Medium,
                        color = if (canSend) MiuixTheme.colorScheme.onPrimary
                            else MiuixTheme.colorScheme.onSurfaceVariantSummary)
                }
            }
        }
    }
    previewImage?.let { image ->
        PrivateImagePreview(imageUrl = image) { previewImage = null }
    }
}

@Composable
private fun PrivateImagePreview(imageUrl: String, onDismiss: () -> Unit) {
    androidx.compose.ui.window.Dialog(
        onDismissRequest = onDismiss,
        properties = androidx.compose.ui.window.DialogProperties(
            usePlatformDefaultWidth = false, decorFitsSystemWindows = false,
        ),
    ) {
        var scale by remember(imageUrl) { mutableFloatStateOf(1f) }
        var translation by remember(imageUrl) { mutableStateOf(androidx.compose.ui.geometry.Offset.Zero) }
        Box(
            Modifier.fillMaxSize().background(Color(0xF5000000)),
        ) {
            AsyncImage(
                model = imageUrl,
                contentDescription = "查看聊天图片",
                modifier = Modifier.fillMaxSize()
                    .pointerInput(imageUrl) {
                        detectTransformGestures { _, pan, zoom, _ ->
                            scale = (scale * zoom).coerceIn(1f, 4.5f)
                            translation = if (scale <= 1f) androidx.compose.ui.geometry.Offset.Zero
                                else translation + pan
                        }
                    }
                    .graphicsLayer {
                        scaleX = scale
                        scaleY = scale
                        translationX = translation.x
                        translationY = translation.y
                    },
                contentScale = ContentScale.Fit,
            )
            Box(
                Modifier.align(Alignment.TopEnd)
                    .statusBarsPadding().padding(18.dp)
                    .clip(RoundedCornerShape(16.dp))
                    .background(Color(0x99000000))
                    .clickable { onDismiss() }
                    .padding(horizontal = 14.dp, vertical = 10.dp),
            ) { Text("关闭", fontSize = 14.sp, color = Color.White) }
        }
    }
}
