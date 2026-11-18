package me.rain.mtforum.feature.forum

import android.content.Context
import android.graphics.BitmapFactory
import android.provider.OpenableColumns
import androidx.compose.foundation.Image
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import me.rain.mtforum.core.network.*
import me.rain.mtforum.core.ui.*
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import top.yukonga.miuix.kmp.basic.*
import top.yukonga.miuix.kmp.extra.SuperCheckbox
import top.yukonga.miuix.kmp.extra.SuperDropdown
import top.yukonga.miuix.kmp.icon.MiuixIcons
import top.yukonga.miuix.kmp.icon.icons.useful.*
import top.yukonga.miuix.kmp.theme.MiuixTheme

/** Native Discuz new-thread composer. Form tokens come from the current session. */
@Composable
internal fun NewThreadScreen(
    repository: ForumRepository,
    url: String,
    boardTitle: String,
    userName: String? = null,
    userGroup: String? = null,
    userAvatar: String? = null,
    onSwitchBoard: (String, String) -> Unit,
    onBack: () -> Unit,
    onCreated: () -> Unit,
    onPublished: (String) -> Unit,
) {
    val fid = remember(url) {
        url.toHttpUrlOrNull()?.queryParameter("fid")
            ?.takeIf { it.matches(Regex("""\d{1,10}""")) }.orEmpty()
    }
    val context = LocalContext.current
    val prefs = remember(context) {
        context.getSharedPreferences("new-thread-drafts", Context.MODE_PRIVATE)
    }
    val key = "forum-$fid"
    var subject by rememberSaveable(url) {
        mutableStateOf(prefs.getString("$key-title", "").orEmpty())
    }
    val draft = remember(url) { ForumInlineEditorState() }
    var doc by remember(url) { mutableStateOf<NativeDocument?>(null) }
    var fetching by remember(url) { mutableStateOf(true) }
    var fetchError by remember(url) { mutableStateOf<String?>(null) }
    var feedback by remember(url) { mutableStateOf<String?>(null) }
    var reload by remember(url) { mutableIntStateOf(0) }
    var sending by remember(url) { mutableStateOf(false) }
    var uploading by remember(url) { mutableStateOf(false) }
    var published by remember(url) { mutableStateOf(false) }
    var targetUrl by remember(url) { mutableStateOf<String?>(null) }
    var smileys by remember(url) { mutableStateOf(false) }
    var showPreview by remember(url) { mutableStateOf(false) }
    var showOptions by remember(url) { mutableStateOf(false) }
    var showFormatting by remember(url) { mutableStateOf(false) }
    var insertPanel by remember(url) { mutableStateOf("") }
    var mentionName by remember(url) { mutableStateOf("") }
    var linkUrl by remember(url) { mutableStateOf("") }
    var linkLabel by remember(url) { mutableStateOf("") }
    var boards by remember(repository) { mutableStateOf<List<ForumBoard>>(emptyList()) }
    val localImageAttachments = remember(url) { mutableStateMapOf<String, String>() }
    var boardPickerVisible by remember(url) { mutableStateOf(false) }
    var expandedEditor by remember(url) { mutableStateOf(false) }
    var draftSaved by remember(url) { mutableStateOf(false) }
    var challengeReload by remember(url) { mutableIntStateOf(0) }
    var challenge by remember(url) { mutableStateOf<ForumRepository.PostingChallenge?>(null) }
    var challengeError by remember(url) { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val keyboard = LocalSoftwareKeyboardController.current
    val focus = LocalFocusManager.current
    BackHandler(enabled = showPreview && !published) {
        showPreview = false
    }
    LaunchedEffect(repository) {
        boards = try { repository.boards().distinctBy { it.id } }
            catch (e: CancellationException) { throw e }
            catch (_: Exception) { emptyList() }
    }

    LaunchedEffect(url) { draft.restoreDraft(prefs.getString("$key-content", "").orEmpty()) }
    LaunchedEffect(subject, draft.markup, published) {
        draftSaved = false
        if (!published) {
            delay(500)
            prefs.edit().putString("$key-title", subject)
                .putString("$key-content", draft.markup).apply()
            draftSaved = true
        }
    }
    DisposableEffect(url) {
        onDispose {
            if (!published) {
                prefs.edit().putString("$key-title", subject)
                    .putString("$key-content", draft.markup).apply()
            }
        }
    }
    LaunchedEffect(url, reload) {
        if (fid.isBlank()) {
            fetching = false
            fetchError = "请先选择发帖板块"
            return@LaunchedEffect
        }
        fetching = true
        fetchError = null
        try {
            doc = repository.document(url, "发布帖子")
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            fetchError = e.readable()
        } finally {
            fetching = false
        }
    }
    val form = doc?.forms?.firstOrNull { f ->
        f.fields.any { it.key == "subject" } && f.fields.any { it.key == "message" }
    }
    val values = remember(form) {
        mutableStateMapOf<Int, String>().apply {
            form?.fields?.forEachIndexed { i, f -> put(i, f.value) }
        }
    }
    val checks = remember(form) {
        mutableStateMapOf<Int, Boolean>().apply {
            form?.fields?.forEachIndexed { i, f -> put(i, f.checked) }
        }
    }
    val titleLimit = (form?.fields?.firstOrNull { it.key == "subject" }?.maxLength ?: 180)
        .coerceIn(1, 180)
    val categoryIndex = form?.fields?.indexOfFirst { it.key == "typeid" } ?: -1
    val category = form?.fields?.getOrNull(categoryIndex)
    val extras = form?.fields?.withIndex()?.filter { (_, field) ->
        PostSettingPresentation.isVisible(field)
    }.orEmpty()
    val needsChallenge = form?.fields?.any {
        it.key in setOf("seccodehash", "seccode", "secqaahash")
    } == true
    LaunchedEffect(form, challengeReload) {
        challenge = null
        challengeError = null
        if (needsChallenge && form != null) {
            showOptions = true
            try {
                challenge = repository.loadPostingChallenge(form)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                challengeError = e.readable()
            }
        }
    }
    val enabled = !sending && !published
    val ready = form != null && !fetching && !sending && !uploading &&
        !published && subject.isNotBlank() && draft.markup.isNotBlank()
    val attachmentCount = remember(draft.markup) {
        Regex("""\[(?:attachimg|attach)\]\d+\[/(?:attachimg|attach)\]""")
            .findAll(draft.markup).count()
    }

    fun uploadSelected(uris: List<android.net.Uri>, imagesOnly: Boolean) {
        val active = form ?: return
        if (active.upload == null || uris.isEmpty() || uploading || !enabled) return
        scope.launch {
            uploading = true
            feedback = null
            try {
                for (uri in uris.take(8)) {
                    val (bytes, name, mime) = withContext(Dispatchers.IO) {
                        val kind = context.contentResolver.getType(uri)
                            ?: if (imagesOnly) "image/jpeg" else "application/octet-stream"
                        val max = active.upload.maxBytes.coerceAtMost(10 * 1024 * 1024)
                        val body = context.contentResolver.openInputStream(uri)?.use {
                            it.readNBytes(max + 1)
                        } ?: throw ForumException("无法读取附件")
                        if (body.size > max) throw ForumException("附件超过论坛上传限制")
                        var filename = if (imagesOnly) "picture.jpg" else "attachment.bin"
                        context.contentResolver.query(
                            uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null,
                        )?.use { cursor ->
                            if (cursor.moveToFirst()) filename = cursor.getString(0) ?: filename
                        }
                        Triple(body, filename, kind)
                    }
                    val isImage = mime.startsWith("image/")
                    val aid = repository.uploadPostAttachment(
                        active, bytes, name, mime, image = isImage,
                    )
                    if (isImage) {
                        localImageAttachments[aid] = uri.toString()
                        draft.insertMedia(uri.toString(), "[attachimg]$aid[/attachimg]", image = true)
                    } else draft.insertText("[attach]$aid[/attach]")
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                feedback = e.readable()
            } finally {
                uploading = false
            }
        }
    }

    val pickImage = rememberLauncherForActivityResult(
        ActivityResultContracts.GetMultipleContents(),
    ) { uris -> uploadSelected(uris, imagesOnly = true) }
    val pickFiles = rememberLauncherForActivityResult(
        ActivityResultContracts.GetMultipleContents(),
    ) { uris -> uploadSelected(uris, imagesOnly = false) }

    fun publish() {
        val active = form ?: run {
            feedback = fetchError ?: "尚未获取论坛发帖表单"
            return
        }
        if (sending || uploading || published) return
        if (subject.isBlank() || draft.markup.isBlank()) {
            feedback = if (subject.isBlank()) "请输入标题" else "请输入正文"
            return
        }
        val max = active.fields.firstOrNull { it.key == "subject" }?.maxLength
        if (max != null && subject.length > max) {
            feedback = "标题不得超过 $max 字"
            return
        }
        val missing = active.fields.withIndex().firstOrNull { (index, field) ->
            field.required && field.type != "hidden" &&
                field.key !in setOf("subject", "message") &&
                (if (field.type in setOf("checkbox", "radio"))
                    active.fields.withIndex().none { (otherIndex, other) ->
                        other.key == field.key && checks[otherIndex] == true
                    }
                else values[index].isNullOrBlank())
        }
        if (missing != null) {
            showPreview = false
            showOptions = true
            feedback = "请填写 ${PostSettingPresentation.label(missing.value)}"
            return
        }
        scope.launch {
            sending = true
            feedback = null
            try {
                val action = "${ForumRepository.BaseUrl}/forum.php" +
                    "?mod=post&action=newthread&fid=$fid&topicsubmit=yes&inajax=1"
                val fields = active.fields.mapIndexedNotNull { i, field ->
                    when (field.type) {
                        "file" -> null
                        "checkbox", "radio" ->
                            if (checks[i] == true)
                                field.key to field.value.ifBlank { "on" } else null
                        else -> field.key to when (field.key) {
                            "subject" -> subject.trim()
                            "message" -> draft.markup
                            else -> values[i].orEmpty()
                        }
                    }
                }
                val aids = Regex("""\[(?:attachimg|attach)\](\d+)\[/(?:attachimg|attach)\]""")
                    .findAll(draft.markup).map { it.groupValues[1] }.distinct()
                    .map { "attachnew[$it][description]" to "" }.toList()
                val response = repository.submit(
                    active.copy(url = action, method = "POST", multipart = false),
                    fields + aids, RemoteSubmit("发布帖子", "", ""),
                )
                if (response.success) {
                    published = true
                    targetUrl = response.target
                    onCreated()
                    prefs.edit().remove("$key-title").remove("$key-content").apply()
                    feedback = response.message.ifBlank { "发布成功" }
                    focus.clearFocus()
                    keyboard?.hide()
                } else {
                    feedback = response.message.ifBlank {
                        "未能确认发帖结果，请检查帖子列表后再决定是否重试"
                    }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                feedback = e.readable()
            } finally {
                sending = false
            }
        }
    }

    if (boardPickerVisible) {
        Dialog(onDismissRequest = { boardPickerVisible = false }) {
            Card(Modifier.fillMaxWidth()) {
                Column(
                    Modifier.fillMaxWidth().padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Text("选择发布板块", Modifier.weight(1f),
                            fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
                        Text("关闭", Modifier.clickable { boardPickerVisible = false }
                            .padding(horizontal = 6.dp, vertical = 8.dp),
                            fontSize = 12.sp,
                            color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                    }
                    Column(
                        Modifier.fillMaxWidth().heightIn(max = 430.dp)
                            .verticalScroll(rememberScrollState()),
                        verticalArrangement = Arrangement.spacedBy(5.dp),
                    ) {
                        boards.forEach { board ->
                            val selected = board.id == fid
                            Row(
                                Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp))
                                    .background(MiuixTheme.colorScheme.onSurface
                                        .copy(alpha = if (selected) .13f else .035f))
                                    .clickable(enabled = enabled) {
                                        boardPickerVisible = false
                                        if (board.id != fid) {
                                            val nextKey = "forum-" + board.id
                                            val edit = prefs.edit()
                                                .putString(key + "-title", subject)
                                                .putString(key + "-content", draft.markup)
                                            // Switching to a fresh board carries the text along.
                                            // An existing draft in the destination remains intact.
                                            if (prefs.getString(nextKey + "-title", "").isNullOrBlank() &&
                                                prefs.getString(nextKey + "-content", "").isNullOrBlank()) {
                                                edit.putString(nextKey + "-title", subject)
                                                    .putString(nextKey + "-content", draft.markup)
                                            }
                                            edit.apply()
                                            onSwitchBoard(board.id, board.title)
                                        }
                                    }
                                    .padding(horizontal = 14.dp, vertical = 13.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                Column(Modifier.weight(1f),
                                    verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                    Text(board.title, fontSize = 14.sp,
                                        fontWeight = if (selected) FontWeight.SemiBold
                                            else FontWeight.Medium, maxLines = 1,
                                        overflow = TextOverflow.Ellipsis)
                                    Text(board.group, fontSize = 11.sp,
                                        color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                                }
                                if (selected) Text("当前", fontSize = 11.sp,
                                    color = MiuixTheme.colorScheme.primary)
                            }
                        }
                    }
                }
            }
        }
    }

    Column(Modifier.fillMaxSize().imePadding()) {
        if (!showPreview || published) {
            PageHeader("发布帖子", onBack) {
                if (!published) Text(
                    "预览",
                    Modifier.clip(RoundedCornerShape(12.dp))
                        .clickable(enabled = !sending) {
                            keyboard?.hide()
                            focus.clearFocus(force = true)
                            smileys = false
                            insertPanel = ""
                            showPreview = true
                        }
                        .padding(horizontal = 12.dp, vertical = 8.dp),
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                )
                ToolIcon(MiuixIcons.Useful.Refresh, "刷新表单", !fetching && !sending && !published) {
                    reload++
                }
            }
        }
        if (published) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Card(Modifier.fillMaxWidth().padding(20.dp)) {
                    Column(Modifier.fillMaxWidth().padding(22.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text("发布成功", fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
                        Text(feedback.orEmpty())
                        targetUrl?.let { publishedThread ->
                            ActionButton("查看帖子", Modifier.fillMaxWidth()) {
                                onPublished(publishedThread)
                            }
                        }
                        ActionButton("返回板块", Modifier.fillMaxWidth(), primary = false) {
                            onBack()
                        }
                    }
                }
            }
        } else if (showPreview) {
            ThreadDraftPreview(
                title = subject,
                markup = draft.markup,
                boardName = boards.firstOrNull { it.id == fid }?.title ?: boardTitle,
                categoryName = category?.options?.firstOrNull {
                    it.value == values[categoryIndex]
                }?.label,
                author = userName,
                authorLevel = userGroup,
                authorAvatar = userAvatar,
                uploadedImages = localImageAttachments,
                feedback = feedback,
                canPublish = ready,
                onEdit = { showPreview = false },
                onPublish = { publish() },
            )
        } else {
            LazyColumn(
                Modifier.weight(1f).fillMaxWidth(),
                contentPadding = PaddingValues(horizontal = 18.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                item {
                    Card(Modifier.fillMaxWidth()) {
                        Row(
                            Modifier.fillMaxWidth()
                                .clip(RoundedCornerShape(20.dp))
                                .clickable(enabled = enabled && boards.isNotEmpty()) {
                                    boardPickerVisible = true
                                }
                                .padding(horizontal = 17.dp, vertical = 15.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text("发布板块", fontSize = 11.sp,
                                    color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                                Text(
                                    boards.firstOrNull { it.id == fid }?.let { it.group + " / " + it.title }
                                        ?: boardTitle.ifBlank { "当前板块" },
                                    fontSize = 16.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }
                            Text(
                                if (boards.isEmpty()) "正在获取…" else "更换  ›",
                                fontSize = 13.sp,
                                maxLines = 1,
                                color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                            )
                        }
                    }
                }
                item {
                    Card(Modifier.fillMaxWidth()) {
                        Column(Modifier.fillMaxWidth().padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(11.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text("帖子标题", Modifier.weight(1f), fontSize = 15.sp,
                                    fontWeight = FontWeight.SemiBold)
                                Text("${subject.length}/$titleLimit", fontSize = 11.sp,
                                    color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                            }
                            TextField(
                                value = subject, onValueChange = { subject = it.take(titleLimit) },
                                label = "请输入帖子标题", modifier = Modifier.fillMaxWidth(),
                                singleLine = true, enabled = enabled,
                            )
                            if (!userName.isNullOrBlank() || !userGroup.isNullOrBlank()) {
                                Row(Modifier.fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Text("发布身份", fontSize = 12.sp,
                                        color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                                    if (!userName.isNullOrBlank())
                                        Text(userName, fontSize = 12.sp, maxLines = 1)
                                    if (!userGroup.isNullOrBlank())
                                        UserLevelPill(userGroup)
                                }
                            }
                            if (category != null && category.options.size > 1) {
                                Row(
                                    Modifier.fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                                ) {
                                    Text("主题分类", fontSize = 12.sp,
                                        color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                                    Row(
                                        Modifier.weight(1f).horizontalScroll(rememberScrollState()),
                                        horizontalArrangement = Arrangement.spacedBy(7.dp),
                                    ) {
                                        category.options.forEach { option ->
                                            val selected = values[categoryIndex] == option.value
                                            Box(
                                                Modifier.clip(RoundedCornerShape(12.dp))
                                                    .background(MiuixTheme.colorScheme.onSurface
                                                        .copy(alpha = if (selected) .15f else .055f))
                                                    .clickable(enabled = enabled) {
                                                        values[categoryIndex] = option.value
                                                    }
                                                    .padding(horizontal = 13.dp, vertical = 9.dp),
                                            ) {
                                                Text(
                                                    option.label.ifBlank { "未分类" },
                                                    fontSize = 12.sp, maxLines = 1,
                                                    fontWeight = if (selected) FontWeight.SemiBold
                                                        else FontWeight.Normal,
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                item {
                    Card(Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(9.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                Text("正文", Modifier.weight(1f), fontSize = 15.sp,
                                    fontWeight = FontWeight.SemiBold)
                                Text("${draft.markup.length} 字", fontSize = 12.sp,
                                    color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                                Text(if (expandedEditor) "收起" else "扩展",
                                    Modifier.clip(RoundedCornerShape(10.dp))
                                        .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .07f))
                                        .clickable { expandedEditor = !expandedEditor }
                                        .padding(horizontal = 10.dp, vertical = 7.dp),
                                    fontSize = 12.sp)
                            }
                            Box(
                                Modifier.fillMaxWidth().height(if (expandedEditor) 450.dp else 260.dp)
                                    .clip(RoundedCornerShape(18.dp))
                                    .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .045f))
                                    .padding(12.dp),
                            ) {
                                ForumInlineEditor(
                                    draft, Modifier.fillMaxSize(),
                                    "分享内容、教程、经验或提问…", enabled,
                                    textSizeSp = 15f,
                                    onFocused = {
                                        smileys = false
                                        insertPanel = ""
                                    },
                                )
                            }
                            Row(
                                Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                                horizontalArrangement = Arrangement.spacedBy(7.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                listOf(
                                    Triple("加粗", "[b]", "[/b]"),
                                    Triple("斜体", "[i]", "[/i]"),
                                    Triple("链接", "[url]", "[/url]"),
                                    Triple("引用", "[quote]", "[/quote]"),
                                    Triple("代码", "[code]", "[/code]"),
                                ).forEach { (label, prefix, suffix) ->
                                    ComposeEditorTool(label, enabled) {
                                        draft.wrapSelection(prefix, suffix)
                                    }
                                }
                                ComposeEditorTool(if (showFormatting) "收起" else "更多", enabled,
                                    active = showFormatting) {
                                    showFormatting = !showFormatting
                                }
                            }
                            if (showFormatting) {
                                Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                                    horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                                    listOf(
                                        Triple("下划线", "[u]", "[/u]"),
                                        Triple("删除线", "[s]", "[/s]"),
                                        Triple("列表", "[list]\n[*]", "\n[/list]"),
                                        Triple("隐藏", "[hide]", "[/hide]"),
                                    ).forEach { (label, prefix, suffix) ->
                                        ComposeEditorTool(label, enabled) {
                                            draft.wrapSelection(prefix, suffix)
                                        }
                                    }
                                }
                            }
                            Text("选中文字后点击工具即可添加格式，图片和表情按光标位置插入",
                                fontSize = 11.sp,
                                color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                        }
                    }
                }
                if (needsChallenge || form?.captchaImages?.isNotEmpty() == true) item {
                    Card(Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            Row(Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically) {
                                Text("论坛安全验证", Modifier.weight(1f),
                                    fontWeight = FontWeight.SemiBold)
                                Text("刷新验证",
                                    Modifier.clickable(enabled = !sending) { challengeReload++ }
                                        .padding(8.dp),
                                    fontSize = 12.sp)
                            }
                            val bitmap = remember(challenge?.imageBytes) {
                                challenge?.imageBytes?.let { raw ->
                                    BitmapFactory.decodeByteArray(raw, 0, raw.size)
                                        ?.asImageBitmap()
                                }
                            }
                            if (bitmap != null) Image(
                                bitmap, "论坛图片验证码",
                                Modifier.fillMaxWidth().height(82.dp),
                                contentScale = ContentScale.Fit,
                            )
                            else form?.captchaImages?.forEach { image ->
                                AsyncImage(image, "验证码",
                                    Modifier.fillMaxWidth().height(82.dp))
                            }
                            challenge?.question?.let { question ->
                                Text(question, fontSize = 14.sp)
                            }
                            challengeError?.let { problem ->
                                Text(problem, fontSize = 12.sp)
                            }
                            Text("验证码答案在下方附加选项中填写",
                                fontSize = 12.sp,
                                color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                        }
                    }
                }
                if (extras.isNotEmpty()) item {
                    Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                        Row(
                            Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp))
                                .background(MiuixTheme.colorScheme.surface)
                                .clickable { showOptions = !showOptions }
                                .padding(16.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(Modifier.weight(1f),
                                verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                Text("发布设置", fontWeight = FontWeight.SemiBold)
                                Text(
                                    extras.joinToString(" · ", limit = 3, truncated = "…") {
                                        PostSettingPresentation.label(it.value)
                                    },
                                    fontSize = 11.sp,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                                )
                            }
                            Text(if (showOptions) "收起 ↑" else "展开 ↓",
                                fontSize = 12.sp, maxLines = 1)
                        }
                        if (showOptions) Card(Modifier.fillMaxWidth()) {
                            Column(Modifier.padding(16.dp),
                                verticalArrangement = Arrangement.spacedBy(13.dp)) {
                                extras.forEach { (index, field) ->
                                    when (field.type) {
                                        "checkbox", "radio" -> SuperCheckbox(
                                            checked = checks[index] == true,
                                            title = PostSettingPresentation.label(field),
                                            modifier = Modifier.fillMaxWidth(), enabled = enabled,
                                            onCheckedChange = { selected ->
                                                if (field.type == "radio" && selected) {
                                                    form?.fields?.forEachIndexed { i, other ->
                                                        if (other.key == field.key) checks[i] = false
                                                    }
                                                }
                                                checks[index] = selected
                                            },
                                        )
                                        "select" -> if (field.options.isNotEmpty()) {
                                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                                Text(PostSettingPresentation.label(field),
                                                    fontSize = 13.sp,
                                                    fontWeight = FontWeight.Medium)
                                                Row(
                                                    Modifier.fillMaxWidth()
                                                        .horizontalScroll(rememberScrollState()),
                                                    horizontalArrangement = Arrangement.spacedBy(7.dp),
                                                ) {
                                                    field.options.forEach { option ->
                                                        ComposeEditorTool(
                                                            option.label,
                                                            enabled,
                                                            active = values[index] == option.value,
                                                        ) { values[index] = option.value }
                                                    }
                                                }
                                            }
                                        }
                                        else -> Column(
                                            verticalArrangement = Arrangement.spacedBy(5.dp),
                                        ) {
                                            TextField(
                                                value = values[index].orEmpty(),
                                                onValueChange = {
                                                    values[index] = it.take(field.maxLength ?: 5000)
                                                },
                                                modifier = Modifier.fillMaxWidth(),
                                                label = PostSettingPresentation.label(field),
                                                enabled = enabled && !field.readOnly,
                                                singleLine = field.type != "textarea",
                                                minLines = if (field.type == "textarea") 3 else 1,
                                            )
                                            PostSettingPresentation.hint(field)?.let { hint ->
                                                Text(hint, Modifier.padding(horizontal = 5.dp),
                                                    fontSize = 11.sp,
                                                    color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                if (!fetching && (form == null || fetchError != null)) item {
                    EmptyState("无法加载发帖表单",
                        fetchError ?: "板块可能没有发帖权限，请检查登录状态",
                        action = "重试", onAction = { reload++ })
                }
                if (fetching) item {
                    Row(Modifier.fillMaxWidth().padding(15.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(size = 19.dp)
                        Text("正在加载发帖权限及表单…", fontSize = 12.sp)
                    }
                }
            }
            if (insertPanel.isNotEmpty()) {
                Column(
                    Modifier.fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 7.dp),
                    verticalArrangement = Arrangement.spacedBy(9.dp),
                ) {
                    if (insertPanel == "mention") {
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                            TextField(
                                mentionName,
                                { mentionName = it.take(40) },
                                label = "输入要 @ 的用户名",
                                modifier = Modifier.weight(1f),
                                singleLine = true,
                            )
                            ComposeEditorTool("@插入", mentionName.isNotBlank()) {
                                draft.insertText("@${mentionName.trim()} ")
                                mentionName = ""
                                insertPanel = ""
                            }
                        }
                    } else {
                        Text("插入链接或媒体", fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold)
                        TextField(
                            linkUrl, { linkUrl = it.take(2048) },
                            label = "网址，例如 https://example.com",
                            modifier = Modifier.fillMaxWidth(), singleLine = true,
                        )
                        TextField(
                            linkLabel, { linkLabel = it.take(100) },
                            label = "链接名称（选填）",
                            modifier = Modifier.fillMaxWidth(), singleLine = true,
                        )
                        Row(Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                            ComposeEditorTool("插入链接", linkUrl.startsWith("https://") ||
                                linkUrl.startsWith("http://")) {
                                val address = linkUrl.trim()
                                val caption = linkLabel.trim().ifBlank { address }
                                draft.insertText("[url=$address]$caption[/url]")
                                linkUrl = ""
                                linkLabel = ""
                                insertPanel = ""
                            }
                            ComposeEditorTool("插入网络图片", linkUrl.startsWith("https://")) {
                                val address = linkUrl.trim()
                                draft.insertMedia(address, "[img]$address[/img]", image = true)
                                linkUrl = ""
                                linkLabel = ""
                                insertPanel = ""
                            }
                        }
                    }
                }
            }
            val keyboardVisible = WindowInsets.ime.getBottom(LocalDensity.current) > 0
            if (smileys && !keyboardVisible) ForumSmileyPicker(
                Modifier.fillMaxWidth().height(190.dp)
                    .padding(horizontal = 15.dp, vertical = 4.dp),
            ) { code ->
                val image = code.removePrefix("[img]").removeSuffix("[/img]")
                if (image.startsWith("https://")) draft.insertMedia(image, code)
            }
            Column(
                Modifier.fillMaxWidth()
                    .background(MiuixTheme.colorScheme.background)
                    .navigationBarsPadding().padding(horizontal = 16.dp, vertical = 9.dp),
                verticalArrangement = Arrangement.spacedBy(9.dp),
            ) {
                feedback?.let { message ->
                    Text(
                        message,
                        Modifier.fillMaxWidth()
                            .clip(RoundedCornerShape(13.dp))
                            .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .06f))
                            .padding(horizontal = 12.dp, vertical = 9.dp),
                        fontSize = 12.sp,
                        maxLines = 3,
                        color = MiuixTheme.colorScheme.onSurface,
                    )
                }
                Row(
                    Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(7.dp),
                ) {
                    ComposeEditorTool(if (uploading) "上传中" else "插入图片",
                        enabled && !uploading && form?.upload != null) {
                        insertPanel = ""
                        pickImage.launch("image/*")
                    }
                    ComposeEditorTool(if (smileys) "收起表情" else "表情", enabled) {
                        insertPanel = ""
                        smileys = !smileys
                        if (smileys) { keyboard?.hide(); focus.clearFocus() }
                    }
                    ComposeEditorTool("附件", enabled && !uploading && form?.upload != null) {
                        insertPanel = ""
                        pickFiles.launch("*/*")
                    }
                    ComposeEditorTool("@", enabled) {
                        smileys = false
                        insertPanel = if (insertPanel == "mention") "" else "mention"
                    }
                    ComposeEditorTool("链接", enabled) {
                        smileys = false
                        insertPanel = if (insertPanel == "insert") "" else "insert"
                    }
                }
                Text(
                    when {
                        uploading -> "图片上传中"
                        attachmentCount > 0 -> "已插入 $attachmentCount 项附件 · 草稿自动保存"
                        draftSaved -> "草稿已自动保存"
                        else -> "编辑中 · 离开时自动保留草稿"
                    },
                    fontSize = 11.sp,
                    color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                    maxLines = 1,
                )
                ActionButton(
                    if (sending) "正在发布…" else if (uploading) "图片上传中…" else "发布帖子",
                    Modifier.fillMaxWidth(), enabled = ready, loading = sending,
                ) { publish() }
            }
        }
    }
}

@Composable
private fun ComposeEditorTool(
    title: String,
    enabled: Boolean,
    active: Boolean = false,
    onClick: () -> Unit,
) {
    Box(
        Modifier.clip(RoundedCornerShape(12.dp))
            .background(
                MiuixTheme.colorScheme.onSurface.copy(alpha = if (active) .13f else .06f)
            )
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 11.dp, vertical = 9.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            title, fontSize = 12.sp,
            color = if (enabled) MiuixTheme.colorScheme.onSurface
                else MiuixTheme.colorScheme.onSurfaceVariantSummary.copy(alpha = .55f),
            maxLines = 1,
        )
    }
}
