package me.rain.mtforum.feature.forum

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import me.rain.mtforum.core.network.*
import me.rain.mtforum.core.ui.*
import top.yukonga.miuix.kmp.basic.*
import top.yukonga.miuix.kmp.extra.*
import top.yukonga.miuix.kmp.icon.MiuixIcons
import top.yukonga.miuix.kmp.icon.icons.useful.*
import top.yukonga.miuix.kmp.theme.MiuixTheme

@Composable
fun NativePageScreen(
    repository: ForumRepository,
    title: String,
    url: String,
    onBack: (() -> Unit)? = null,
    bottomInset: Boolean = false,
    onOpen: (String, String) -> Unit,
    onChanged: () -> Unit = {},
    showHeader: Boolean = true,
    onLogin: () -> Unit = {},
    reloadToken: Int = 0,
) {
    // Rank categories belong to one screen. Do not route rank-tab links through HomeScreen.open().
    if (isRankingsUrl(url)) {
        RankingsScreen(repository, url, onBack, onOpen)
        return
    }
    // Keep section tabs and their fetched documents inside this route. Reopening a tab
    // must not add another HomeScreen route or re-fetch a page already shown.
    var visibleUrl by rememberSaveable(url) { mutableStateOf(url) }
    val sectionGroup = remember(url) { nativeSectionGroup(url) }
    val pageCache = remember(url) { mutableStateMapOf<String, NativeDocument>() }
    val cacheVersions = remember(url) { mutableStateMapOf<String, String>() }
    val sectionTabs = remember(url) { mutableStateListOf<ContentLink>() }
    val pageStates = rememberSaveableStateHolder()
    val mutation = remember(visibleUrl) { ContentParser.isMutationUrl(visibleUrl) }
    val mallConfirm = remember(visibleUrl) { isMallConfirmationUrl(visibleUrl) }
    var issued by rememberSaveable(visibleUrl) { mutableStateOf(false) }
    val document = pageCache[visibleUrl]
    var error by remember(visibleUrl) { mutableStateOf<String?>(null) }
    var loading by remember(visibleUrl) { mutableStateOf(document == null) }
    var refresh by remember { mutableIntStateOf(0) }
    val refreshIds = remember(url) { mutableStateMapOf<String, Int>() }
    fun refreshCurrent() {
        refreshIds[visibleUrl] = (refreshIds[visibleUrl] ?: 0) + 1
        refresh++
    }
    var feedback by remember(visibleUrl) { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val confirm = remember { mutableStateOf(false) }
    var pendingLink by remember { mutableStateOf<ContentLink?>(null) }
    fun open(link: ContentLink) {
        val dangerous = Regex("删除|移除|拉黑|取消关注|解除|兑换|购买|忽略|通过申请|拒绝申请").containsMatchIn(link.text)
        if (dangerous) {
            pendingLink = link
            confirm.value = true
        } else if (isNativeSectionTab(visibleUrl, link.url) && sectionGroup != null) {
            if (nativeSectionTabIdentity(visibleUrl) != nativeSectionTabIdentity(link.url)) {
                visibleUrl = link.url
            }
        } else onOpen(link.text, link.url)
    }
    fun changePage(target: String) {
        if (isNativePageChange(visibleUrl, target)) visibleUrl = target
        else onOpen(title, target)
    }
    LaunchedEffect(visibleUrl, refresh, reloadToken) {
        if (mutation) {
            loading = false
            return@LaunchedEffect
        }
        // A refresh invalidates this section only, not all already visited tabs.
        val version = "$reloadToken:${refreshIds[visibleUrl] ?: 0}"
        if (pageCache.containsKey(visibleUrl) && cacheVersions[visibleUrl] == version) {
            loading = false
            return@LaunchedEffect
        }
        loading = true
        error = null
        try {
            val response = repository.document(visibleUrl, title)
            pageCache[visibleUrl] = response
            cacheVersions[visibleUrl] = version
            if (sectionGroup != null) {
                response.blocks.asSequence().filter { it.kind == NativeContentKind.Navigation }
                    .flatMap { it.links.asSequence() }
                    .filter { isNativeSectionTab(url, it.url) }
                    .forEach { link ->
                        if (sectionTabs.none { nativeSectionTabIdentity(it.url) == nativeSectionTabIdentity(link.url) }) {
                            sectionTabs.add(link)
                        }
                    }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            error = e.readable()
        } finally {
            loading = false
        }
    }
    Column(Modifier.fillMaxSize().imePadding()) {
        if (showHeader)
            PageHeader(if (mallConfirm) "确认兑换" else title, onBack) {
                ToolIcon(MiuixIcons.Useful.Refresh, "刷新", !loading && !mutation) { refreshCurrent() }
            }
        // Favorites use one persistent Miuix segmented bar, even when a category is empty.
        // Its page may use the generic HTML fallback, which otherwise draws another tab row.
        if (sectionGroup == "favorites" || sectionGroup == "social") {
            val tabs = remember(url) {
                if (sectionGroup == "favorites") favoriteSectionLinks(url) else socialSectionLinks(url)
            }
            AnimatedSectionTabs(
                tabs = tabs.map { it.text },
                selectedTabIndex = if (sectionGroup == "favorites") favoriteSectionIndex(visibleUrl)
                    else socialSectionIndex(visibleUrl),
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp),
                onTabSelected = { index -> tabs.getOrNull(index)?.let { open(it) } },
            )
        } else if (sectionGroup != null && sectionTabs.size > 1) {
            Box(Modifier.padding(horizontal = 20.dp)) {
                NativeNavigation(sectionTabs.toList(), visibleUrl, ::open)
            }
        }
        if (loading && document == null)
            Box(Modifier.weight(1f).fillMaxWidth(), Alignment.Center) {
                CircularProgressIndicator()
            }
        else pageStates.SaveableStateProvider(visibleUrl) {
            val listState = rememberLazyListState()
            LazyColumn(
                Modifier.weight(1f).widthIn(max = 680.dp).fillMaxWidth().align(Alignment.CenterHorizontally),
                state = listState,
                contentPadding =
                    PaddingValues(20.dp, 12.dp, 20.dp, if (bottomInset) 128.dp else 32.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                if (mutation && !issued)
                    item {
                        EmptyState(
                            title,
                            action = "确定继续",
                            onAction = {
                                issued = true
                                scope.launch {
                                    loading = true
                                    try {
                                        pageCache[visibleUrl] = repository.document(visibleUrl, title)
                                        onChanged()
                                    } catch (e: CancellationException) {
                                        throw e
                                    } catch (e: Exception) {
                                        feedback = "操作结果未确认，请返回刷新查看"
                                    } finally {
                                        loading = false
                                    }
                                }
                            },
                        )
                    }
                if (mutation && issued && document == null && !loading && feedback == null)
                    item { EmptyState("操作已提交", "请返回查看最新状态") }
                feedback?.let {
                    item {
                        Card(Modifier.fillMaxWidth()) {
                            Text(it, Modifier.padding(20.dp), fontSize = 14.sp)
                        }
                    }
                }
                error?.let {
                    item { EmptyState("加载失败", it, action = "重试", onAction = { refreshCurrent() }) }
                }
                document?.let { doc ->
                    val signPage = (url.contains("k_misign") || url.contains("k_misign:sign")) &&
                        !url.contains("operation=list")
                    if (signPage) item {
                        Box(
                            Modifier.fillParentMaxHeight(.72f).fillMaxWidth(),
                            contentAlignment = Alignment.Center,
                        ) {
                            NativeSignCard(doc, loading) {
                                scope.launch {
                                    loading = true
                                    try {
                                        feedback = repository.signIn()
                                        onChanged()
                                        refreshCurrent()
                                    } catch (e: CancellationException) {
                                        throw e
                                    } catch (e: Exception) {
                                        feedback = e.readable()
                                    } finally {
                                        loading = false
                                    }
                                }
                            }
                        }
                    }
                    val needsLogin =
                        doc.url.contains("action=login") ||
                            doc.forms.any { form ->
                                form.fields.any { it.key == "username" } &&
                                    form.fields.any { it.key == "password" }
                            }
                    if (needsLogin) item { EmptyState("请先登录", action = "登录论坛", onAction = onLogin) }
                    if (!needsLogin)
                        items(accountDisplayBlocks(nativeDisplayBlocks(doc.blocks.flatMap { block ->
                            if (signPage && block.kind == NativeContentKind.Facts) emptyList()
                            else if (isDuplicateAccountNavigation(block, visibleUrl)) {
                                // Both Comiis menu bars, including generic HTML fallbacks.
                                emptyList()
                            } else if (sectionGroup != null && block.kind == NativeContentKind.Navigation) {
                                // The account tabs have a persistent row above the content.
                                // Preserve unrelated navigation actions without duplicating tabs.
                                val otherLinks = block.links.filterNot { isNativeSectionTab(url, it.url) }
                                if (otherLinks.isEmpty()) emptyList() else listOf(block.copy(links = otherLinks))
                            } else listOf(block)
                        }), doc.url)) { block ->
                            NativeContentItem(block, doc.url, ::open)
                        }
                    if (!needsLogin)
                        items(doc.forms, key = { it.id }) { form ->
                            NativeForm(
                                repository,
                                form,
                                mallConfirmation = mallConfirm && form.id == "mall-exchange",
                                onResult = { result ->
                                    feedback = result.message
                                    if (result.success) onChanged()
                                    if (result.success && result.target != null) onOpen(title, result.target)
                                    else if (result.success && (
                                        result.document.forms.isNotEmpty() ||
                                            result.document.blocks.isNotEmpty()
                                    ))
                                        pageCache[visibleUrl] = result.document
                                },
                            )
                        }
                    if (doc.blocks.isEmpty() && doc.forms.isEmpty() && !loading && error == null)
                        item { EmptyState("这里还没有内容", icon = MiuixIcons.Useful.Info) }
                    item {
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            doc.previous?.let { prev ->
                                ActionButton("上一页", Modifier.weight(1f), primary = false) {
                                    changePage(prev)
                                }
                            }
                            doc.next?.let { next ->
                                ActionButton("下一页", Modifier.weight(1f), primary = false) {
                                    changePage(next)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    SuperDialog(
        show = confirm,
        title = pendingLink?.text,
        summary = "确定继续此操作？",
        onDismissRequest = { confirm.value = false },
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            ActionButton("取消", Modifier.weight(1f), primary = false) { confirm.value = false }
            ActionButton("确定", Modifier.weight(1f)) {
                confirm.value = false
                pendingLink?.let { onOpen(it.text, it.url) }
            }
        }
    }
}

@Composable
private fun NativeForm(
    repository: ForumRepository,
    form: RemoteForm,
    mallConfirmation: Boolean = false,
    onResult: (ForumRepository.Submission) -> Unit,
) {
    // Passwords and draft fields remain in memory only. Duplicate names keep their own field index.
    val values =
        remember(form) {
            mutableStateMapOf<Int, String>().apply {
                form.fields.forEachIndexed { i, f -> put(i, f.value) }
            }
        }
    val checked =
        remember(form) {
            mutableStateMapOf<Int, Boolean>().apply {
                form.fields.forEachIndexed { i, f -> put(i, f.checked) }
            }
        }
    val files = remember(form) { mutableStateMapOf<Int, ForumUpload>() }
    val attachmentAids = remember(form) { mutableStateListOf<String>() }
    var fileIndex by remember { mutableIntStateOf(-1) }
    var submitting by remember { mutableStateOf(false) }
    var completed by remember(form) { mutableStateOf(false) }
    var error by remember(form) { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val confirm = remember { mutableStateOf(false) }
    var chosenSubmit by remember { mutableStateOf<RemoteSubmit?>(null) }
    val picker =
        rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
            val index = fileIndex
            if (uri != null && (index in form.fields.indices || index == -2))
                scope.launch {
                    submitting = true
                    try {
                        val upload =
                            withContext(Dispatchers.IO) {
                                val type =
                                    context.contentResolver.getType(uri)
                                        ?: "application/octet-stream"
                                val bytes =
                                    context.contentResolver.openInputStream(uri)?.use {
                                        it.readNBytes(10 * 1024 * 1024 + 1)
                                    } ?: throw ForumException("无法读取所选文件")
                                if (bytes.size > 10 * 1024 * 1024)
                                    throw ForumException("文件不能超过 10MB")
                                var name = "attachment"
                                context.contentResolver
                                    .query(
                                        uri,
                                        arrayOf(android.provider.OpenableColumns.DISPLAY_NAME),
                                        null,
                                        null,
                                        null,
                                    )
                                    ?.use { if (it.moveToFirst()) name = it.getString(0) ?: name }
                                ForumUpload(
                                    if (index == -2) "Filedata" else form.fields[index].key,
                                    name,
                                    type,
                                    bytes,
                                )
                            }
                        if (index == -2) {
                            val aid =
                                repository.uploadPostImage(
                                    form,
                                    upload.bytes,
                                    upload.filename,
                                    upload.type,
                                )
                            attachmentAids.add(aid)
                            val messageIndex = form.fields.indexOfFirst { it.key == "message" }
                            if (messageIndex >= 0)
                                values[messageIndex] =
                                    values[messageIndex].orEmpty() +
                                        "\n[attachimg]$aid[/attachimg]\n"
                        } else files[index] = upload
                        error = null
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        error = e.message ?: "无法读取文件"
                    } finally {
                        submitting = false
                    }
                }
        }
    fun submit(button: RemoteSubmit) {
        if (submitting || completed) return
        val missing =
            form.fields.withIndex().firstOrNull { (i, f) ->
                f.required &&
                    f.type != "hidden" &&
                    when (f.type) {
                        "radio" -> form.fields.withIndex().none { (other, field) ->
                            field.key == f.key && checked[other] == true
                        }
                        "checkbox" -> checked[i] != true
                        "file" -> files[i] == null
                        else -> values[i].isNullOrBlank()
                    }
            }
        if (missing != null) {
            error = "请填写${missing.value.label}"
            return
        }
        val password = form.fields.indexOfFirst { it.key == "newpassword" }
        val confirmation = form.fields.indexOfFirst { it.key == "newpassword2" }
        if (password >= 0 && confirmation >= 0 && values[password] != values[confirmation]) {
            error = "两次输入的新密码不一致"
            return
        }
        scope.launch {
            submitting = true
            error = null
            try {
                val data =
                    form.fields.mapIndexedNotNull { i, f ->
                        when (f.type) {
                            "file" -> null
                            "checkbox",
                            "radio" ->
                                if (checked[i] == true) f.key to f.value.ifBlank { "on" } else null
                            else -> f.key to values[i].orEmpty()
                        }
                    }
                val bindings = attachmentAids.map { "attachnew[$it][description]" to "" }
                val result = repository.submit(form, data + bindings, button, files.values.toList())
                if (result.success) {
                    completed = true
                    form.fields.forEachIndexed { i, f ->
                        if (f.type == "password" || f.type == "textarea") values[i] = ""
                    }
                }
                if (!result.success) error = result.message
                onResult(result)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = e.readable()
            } finally {
                submitting = false
            }
        }
    }
    val groups = form.fields.withIndex().filter { it.value.type != "hidden" }
        .groupBy { nativeFieldSection(it.value) }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        groups.forEach { (section, fields) ->
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(section, Modifier.padding(start = 4.dp), fontSize = 13.sp,
                    color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        fields.forEach { entry ->
                            val index = entry.index
                            val original = entry.value
                            val field = original.copy(label = nativeFieldLabel(original, form))
                            when (field.type) {
                                "hidden" -> Unit
                                "select" ->
                                    SuperDropdown(
                                        items = field.options.map { it.label },
                                        selectedIndex =
                                            field.options
                                                .indexOfFirst { it.value == values[index] }
                                                .coerceAtLeast(0),
                                        title = field.label,
                                        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)),
                                        enabled = !submitting && !completed,
                                        onSelectedIndexChange = { values[index] = field.options[it].value },
                                        insideMargin = PaddingValues(vertical = 14.dp, horizontal = 0.dp),
                                    )
                                "checkbox",
                                "radio" ->
                                    SuperCheckbox(
                                        checked = checked[index] == true,
                                        title = field.label,
                                        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)),
                                        enabled = !submitting && !completed,
                                        onCheckedChange = { value ->
                                            if (field.type == "radio")
                                                form.fields.forEachIndexed { other, f ->
                                                    if (f.key == field.key) checked[other] = false
                                                }
                                            checked[index] = if (field.type == "radio") true else value
                                        },
                                    )
                                "file" ->
                                    ActionButton(
                                        files[index]?.filename ?: "选择${field.label}",
                                        Modifier.fillMaxWidth(),
                                        primary = false,
                                        enabled = !submitting && !completed,
                                        icon = MiuixIcons.Useful.New,
                                    ) {
                                        fileIndex = index
                                        picker.launch("*/*")
                                    }
                                else ->
                                    TextField(
                                        value = values[index].orEmpty(),
                                        onValueChange = { values[index] = it.take(field.maxLength ?: 100000) },
                                        modifier = Modifier.fillMaxWidth(),
                                        label = field.label,
                                        enabled = !submitting && !completed && !field.readOnly,
                                        singleLine = field.type != "textarea",
                                        minLines = if (field.key == "message") 7 else if (field.type == "textarea") 4 else 1,
                                        keyboardOptions =
                                            KeyboardOptions(
                                                keyboardType =
                                                    when (field.type) {
                                                        "password" -> KeyboardType.Password
                                                        "tel" -> KeyboardType.Phone
                                                        "number" -> KeyboardType.Number
                                                        "email" -> KeyboardType.Email
                                                        else -> KeyboardType.Text
                                                    }
                                            ),
                                        visualTransformation =
                                            if (field.type == "password") PasswordVisualTransformation()
                                            else VisualTransformation.None,
                                    )
                            }
                        }
                    }
                }
            }
        }
        if (form.captchaImages.isNotEmpty()) Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("图片验证码", fontSize = 13.sp)
                form.captchaImages.forEach {
                    AsyncImage(it, "验证码", Modifier.fillMaxWidth().height(80.dp))
                }
            }
        }
        Column(
            Modifier.fillMaxWidth().then(
                if (mallConfirmation) Modifier.clip(RoundedCornerShape(26.dp))
                    .background(MiuixTheme.colorScheme.surface)
                    .padding(22.dp) else Modifier
            ),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            if (mallConfirmation) {
                Text("兑换确认", fontSize = 21.sp,
                    fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold)
                Text("请核对本次兑换信息，再确认提交。实际扣除与兑换结果以论坛返回为准。",
                    fontSize = 13.sp, lineHeight = 20.sp,
                    color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
            }
            if (form.upload != null)
                ActionButton(
                    if (attachmentAids.isEmpty()) "添加图片" else "继续添加图片 · ${attachmentAids.size}",
                    Modifier.fillMaxWidth(),
                    primary = false,
                    enabled = !submitting && !completed,
                    icon = MiuixIcons.Useful.New,
                ) {
                    fileIndex = -2
                    picker.launch("image/*")
                }
            error?.let { Text(it, fontSize = 13.sp) }
            form.submits.forEachIndexed { i, button ->
                ActionButton(
                    if (completed) "已提交" else nativeSubmitLabel(form, button),
                    Modifier.fillMaxWidth(),
                    enabled = !completed,
                    primary = i == 0,
                    loading = submitting,
                    icon = MiuixIcons.Useful.Confirm,
                ) {
                    if (!mallConfirmation && Regex("删除|兑换|购买|转账|密码|解除").containsMatchIn(button.label)) {
                        chosenSubmit = button
                        confirm.value = true
                    } else submit(button)
                }
            }
        }
    }
    SuperDialog(
        show = confirm,
        title = chosenSubmit?.label,
        summary = "确认提交当前内容？",
        onDismissRequest = { confirm.value = false },
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            ActionButton("取消", Modifier.weight(1f), primary = false) { confirm.value = false }
            ActionButton("确定", Modifier.weight(1f)) {
                confirm.value = false
                chosenSubmit?.let(::submit)
            }
        }
    }
}
