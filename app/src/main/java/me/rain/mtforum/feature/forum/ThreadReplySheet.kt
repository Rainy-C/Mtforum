package me.rain.mtforum.feature.forum

import android.view.Gravity
import android.view.WindowManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogWindowProvider
import androidx.compose.ui.window.DialogProperties
import coil.compose.AsyncImage
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import me.rain.mtforum.core.network.*
import top.yukonga.miuix.kmp.basic.Button
import top.yukonga.miuix.kmp.basic.ButtonDefaults
import top.yukonga.miuix.kmp.basic.CircularProgressIndicator
import top.yukonga.miuix.kmp.basic.Icon
import top.yukonga.miuix.kmp.basic.IconButton
import top.yukonga.miuix.kmp.extra.SuperCheckbox
import top.yukonga.miuix.kmp.extra.SuperDropdown
import top.yukonga.miuix.kmp.basic.Text
import top.yukonga.miuix.kmp.icon.MiuixIcons
import top.yukonga.miuix.kmp.icon.icons.useful.*
import top.yukonga.miuix.kmp.theme.MiuixTheme

/** A reply editor belongs to the current thread; it must never create a navigation route. */
internal data class ThreadReplyTarget(val url: String, val author: String?)

@Composable
internal fun ThreadReplySheet(
    repository: ForumRepository,
    target: ThreadReplyTarget,
    onDismiss: () -> Unit,
    onSubmitted: (String) -> Unit,
) {
    var document by remember(target.url) { mutableStateOf<NativeDocument?>(null) }
    var loading by remember(target.url) { mutableStateOf(true) }
    var failure by remember(target.url) { mutableStateOf<String?>(null) }
    var reload by remember(target.url) { mutableIntStateOf(0) }
    var submitting by remember(target.url) { mutableStateOf(false) }
    // Keep the editor alive before the remote reply form arrives. This allows the
    // IME and bottom sheet to start together rather than in two visible stages.
    var messageDraft by remember(target.url) { mutableStateOf("") }
    var draftEdited by remember(target.url) { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val focusRequester = remember(target.url) { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current

    LaunchedEffect(target.url, reload) {
        loading = true
        failure = null
        try {
            document = repository.document(target.url, "回复")
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            failure = e.readable()
        } finally {
            loading = false
        }
    }

    val form = document?.forms?.firstOrNull { it.fields.any { field -> field.key == "message" } }
    val values = remember(form, target.url) {
        mutableStateMapOf<Int, String>().apply {
            form?.fields?.forEachIndexed { index, field -> put(index, field.value) }
        }
    }
    val checked = remember(form, target.url) {
        mutableStateMapOf<Int, Boolean>().apply {
            form?.fields?.forEachIndexed { index, field -> put(index, field.checked) }
        }
    }
    val attachmentAids = remember(form, target.url) { mutableStateListOf<String>() }
    val messageIndex = form?.fields?.indexOfFirst { it.key == "message" } ?: -1
    var showExtras by remember(target.url) { mutableStateOf(false) }
    var expanded by remember(target.url) { mutableStateOf(false) }

    val imagePicker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        val active = form
        if (uri != null && active?.upload != null && !submitting) {
            scope.launch {
                submitting = true
                failure = null
                try {
                    val (bytes, name, type) = withContext(Dispatchers.IO) {
                        val mime = context.contentResolver.getType(uri) ?: "image/jpeg"
                        val limit = active.upload.maxBytes.coerceAtMost(10 * 1024 * 1024)
                        val imageBytes = context.contentResolver.openInputStream(uri)?.use {
                            it.readNBytes(limit + 1)
                        } ?: throw ForumException("无法读取图片")
                        if (imageBytes.size > limit) throw ForumException("图片超过上传限制")
                        var filename = "image.jpg"
                        context.contentResolver.query(
                            uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME),
                            null, null, null,
                        )?.use { if (it.moveToFirst()) filename = it.getString(0) ?: filename }
                        Triple(imageBytes, filename, mime)
                    }
                    val aid = repository.uploadPostImage(active, bytes, name, type)
                    attachmentAids.add(aid)
                    if (messageIndex >= 0) {
                        messageDraft += "\n[attachimg]$aid[/attachimg]\n"
                        draftEdited = true
                        values[messageIndex] = messageDraft
                    }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    failure = e.readable()
                } finally {
                    submitting = false
                }
            }
        }
    }

    fun send() {
        val active = form ?: return
        if (submitting || messageIndex < 0) return
        if (messageDraft.isBlank()) {
            failure = "请输入评论内容"
            return
        }
        val missing = active.fields.withIndex().firstOrNull { (i, field) ->
            field.required && field.type != "hidden" && when (field.type) {
                "checkbox", "radio" -> checked[i] != true
                else -> if (i == messageIndex) messageDraft.isBlank() else values[i].isNullOrBlank()
            }
        }
        if (missing != null) {
            failure = "请填写${missing.value.label}"
            showExtras = true
            expanded = true
            return
        }
        val submitButton = active.submits.firstOrNull {
            it.name.contains("reply", ignoreCase = true) || it.label.contains("回复")
        } ?: active.submits.firstOrNull() ?: RemoteSubmit("回复", "replysubmit", "yes")
        scope.launch {
            submitting = true
            failure = null
            try {
                val data = active.fields.mapIndexedNotNull { index, field ->
                    when (field.type) {
                        "file" -> null
                        "checkbox", "radio" -> if (checked[index] == true)
                            field.key to field.value.ifBlank { "on" } else null
                        else -> field.key to if (index == messageIndex) messageDraft else values[index].orEmpty()
                    }
                }
                val extra = attachmentAids.map { "attachnew[$it][description]" to "" }
                val result = repository.submit(active, data + extra, submitButton)
                if (result.success) onSubmitted(result.message.ifBlank { "评论已发布" })
                else failure = result.message
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                failure = e.readable()
            } finally {
                submitting = false
            }
        }
    }

    // Only non-message, visible fields belong to the extra-options section. The
    // server's hidden fields remain in `values` and are submitted unchanged.
    val extraFields = form?.fields?.withIndex()?.filter { (index, field) ->
        index != messageIndex && field.type != "hidden" && field.type != "file"
    }.orEmpty()
    val hasExtras = extraFields.isNotEmpty() || !form?.captchaImages.isNullOrEmpty()

    // CAPTCHA can be essential to posting; keep it visible rather than hiding
    // it in an optional panel.
    LaunchedEffect(form) {
        if (!form?.captchaImages.isNullOrEmpty()) {
            showExtras = true
            expanded = true
        }
    }
    // Incorporate server-provided quote text without clobbering early typing.
    LaunchedEffect(form) {
        if (form != null && messageIndex >= 0) {
            val initial = form.fields[messageIndex].value
            if (!draftEdited) messageDraft = initial
            else if (initial.isNotBlank() && !messageDraft.startsWith(initial)) {
                messageDraft = initial + "\n" + messageDraft
            }
            values[messageIndex] = messageDraft
        }
    }

    Dialog(
        onDismissRequest = { if (!submitting) onDismiss() },
        properties = DialogProperties(
            dismissOnBackPress = !submitting,
            dismissOnClickOutside = !submitting,
            usePlatformDefaultWidth = false,
            decorFitsSystemWindows = true,
        ),
    ) {
        val view = LocalView.current
        val density = LocalDensity.current
        val dialogWindow = (view.parent as? DialogWindowProvider)?.window
        // Configure the window before the first frame, not after the sheet has
        // appeared, so opening the keyboard cannot cause another layout jump.
        DisposableEffect(dialogWindow) {
            dialogWindow?.setGravity(Gravity.BOTTOM)
            dialogWindow?.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
            dialogWindow?.setLayout(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
            )
            onDispose { }
        }
        LaunchedEffect(focusRequester) {
            withFrameNanos { }
            focusRequester.requestFocus()
            keyboard?.show()
        }

        BoxWithConstraints(Modifier.fillMaxSize()) {
            val available = (maxHeight - 4.dp).coerceAtLeast(0.dp)
            val compactHeight = minOf(224.dp, available)
            val fullHeight = minOf(490.dp, available)
            val rangePx = with(density) { (fullHeight - compactHeight).toPx() }
            val collapseThresholdPx = with(density) { 44.dp.toPx() }
            val closeThresholdPx = with(density) { 96.dp.toPx() }
            var dragging by remember { mutableStateOf(false) }
            var dragPx by remember { mutableFloatStateOf(0f) }

            val gestureHeight = (
                (if (expanded) fullHeight.value else compactHeight.value) -
                    dragPx / density.density
            ).coerceIn(compactHeight.value, fullHeight.value).dp
            val sheetHeight by animateDpAsState(
                targetValue = if (dragging) gestureHeight else if (expanded) fullHeight else compactHeight,
                animationSpec = spring(
                    dampingRatio = Spring.DampingRatioNoBouncy,
                    stiffness = Spring.StiffnessMedium,
                ),
                label = "reply-sheet-height",
            )
            val beyondCollapsedPx = (dragPx - if (expanded) rangePx else 0f).coerceAtLeast(0f)
            val slideOffsetPx by animateFloatAsState(
                targetValue = if (dragging) beyondCollapsedPx else 0f,
                animationSpec = spring(stiffness = Spring.StiffnessMedium),
                label = "reply-sheet-drag",
            )

            // Drag only the handle/title region; text selection, option scrolling
            // and IME editing retain their normal gestures.
            val dragHandle = Modifier.pointerInput(expanded, submitting, rangePx) {
                if (!submitting) {
                    detectVerticalDragGestures(
                        onDragStart = { dragging = true; dragPx = 0f },
                        onVerticalDrag = { change, amount ->
                            change.consume()
                            dragPx = (dragPx + amount).coerceIn(
                                -(rangePx + closeThresholdPx), rangePx + closeThresholdPx * 3,
                            )
                        },
                        onDragCancel = { dragging = false; dragPx = 0f },
                        onDragEnd = {
                            val distance = dragPx
                            when {
                                distance > (if (expanded) rangePx else 0f) + closeThresholdPx -> {
                                    keyboard?.hide()
                                    onDismiss()
                                }
                                distance > collapseThresholdPx -> expanded = false
                                distance < -collapseThresholdPx -> expanded = true
                            }
                            dragging = false
                            dragPx = 0f
                        },
                    )
                }
            }

            Box(Modifier.fillMaxSize().clickable(enabled = !submitting) { onDismiss() })

            Column(
                Modifier.align(Alignment.BottomCenter)
                    .graphicsLayer { translationY = slideOffsetPx }
                    .fillMaxWidth()
                    .height(sheetHeight)
                    .clip(RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp))
                    .background(MiuixTheme.colorScheme.surface)
                    .navigationBarsPadding()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Box(
                    Modifier.fillMaxWidth().height(16.dp).then(dragHandle),
                    contentAlignment = Alignment.TopCenter,
                ) {
                    Box(
                        Modifier.padding(top = 2.dp).width(36.dp).height(4.dp)
                            .clip(RoundedCornerShape(99.dp))
                            .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .2f)),
                    )
                }
                Row(
                    Modifier.fillMaxWidth().height(40.dp).then(dragHandle),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        if (target.author.isNullOrBlank()) "写评论" else "回复 ${target.author}",
                        modifier = Modifier.weight(1f),
                        fontSize = 17.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    if (hasExtras) {
                        Text(
                            if (showExtras) "收起选项" else "更多选项",
                            modifier = Modifier
                                .clip(RoundedCornerShape(12.dp))
                                .clickable(enabled = !submitting) {
                                    showExtras = !showExtras
                                    expanded = showExtras
                                }
                                .padding(horizontal = 10.dp, vertical = 8.dp),
                            fontSize = 12.sp,
                            color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                        )
                    }
                    IconButton(onClick = onDismiss, enabled = !submitting, modifier = Modifier.size(38.dp)) {
                        Icon(MiuixIcons.Useful.Back, "关闭编辑器", Modifier.size(18.dp))
                    }
                }

                // One permanent editor: it is focusable from the first frame,
                // even while the reply form is still loading over the network.
                ReplyMessageEditor(
                    message = messageDraft,
                    onMessageChange = { typed ->
                        draftEdited = true
                        messageDraft = typed.take(form?.fields?.getOrNull(messageIndex)?.maxLength ?: 100000)
                        if (messageIndex >= 0) values[messageIndex] = messageDraft
                    },
                    focusRequester = focusRequester,
                    enabled = !submitting,
                    modifier = Modifier.fillMaxWidth().then(
                        if (showExtras && form != null) Modifier.height(118.dp) else Modifier.weight(1f)
                    ),
                )
                if (showExtras && form != null) {
                    Column(
                        Modifier.fillMaxWidth().weight(1f)
                            .verticalScroll(rememberScrollState()),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        extraFields.forEach { (index, field) ->
                            when (field.type) {
                                "checkbox", "radio" -> SuperCheckbox(
                                    checked = checked[index] == true,
                                    title = field.label,
                                    modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)),
                                    enabled = !submitting,
                                    onCheckedChange = { value ->
                                        if (field.type == "radio") form.fields.forEachIndexed { j, other ->
                                            if (other.key == field.key) checked[j] = false
                                        }
                                        checked[index] = if (field.type == "radio") true else value
                                    },
                                )
                                "select" -> {
                                    if (field.options.isNotEmpty()) {
                                        SuperDropdown(
                                            items = field.options.map { it.label },
                                            selectedIndex = field.options.indexOfFirst {
                                                it.value == values[index]
                                            }.coerceAtLeast(0),
                                            title = field.label,
                                            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)),
                                            enabled = !submitting,
                                            onSelectedIndexChange = { values[index] = field.options[it].value },
                                        )
                                    }
                                }
                                else -> Box(
                                    Modifier.fillMaxWidth()
                                        .clip(RoundedCornerShape(14.dp))
                                        .background(MiuixTheme.colorScheme.background)
                                        .padding(12.dp),
                                ) {
                                    BasicTextField(
                                        value = values[index].orEmpty(),
                                        onValueChange = { values[index] = it.take(field.maxLength ?: 100000) },
                                        enabled = !submitting,
                                        singleLine = true,
                                        cursorBrush = SolidColor(MiuixTheme.colorScheme.onSurface),
                                        textStyle = TextStyle(
                                            color = MiuixTheme.colorScheme.onSurface, fontSize = 14.sp,
                                        ),
                                        decorationBox = { input ->
                                            Box {
                                                if (values[index].isNullOrBlank()) {
                                                    Text(field.label, fontSize = 14.sp,
                                                        color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                                                }
                                                input()
                                            }
                                        },
                                    )
                                }
                            }
                        }
                        form.captchaImages.forEach { image ->
                            AsyncImage(image, "验证码", Modifier.fillMaxWidth().heightIn(max = 86.dp))
                        }
                    }
                }
                if (form == null) {
                    Text(
                        if (loading) "正在获取回复表单…" else failure ?: "无法获取回复表单",
                        fontSize = 12.sp,
                        color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                    )
                    if (!loading) Text(
                        "点击重试",
                        modifier = Modifier.clip(RoundedCornerShape(10.dp))
                            .clickable { reload++ }.padding(6.dp),
                        fontSize = 12.sp,
                    )
                } else if (failure != null) {
                    Text(
                        failure.orEmpty(), fontSize = 12.sp, maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                    )
                }
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 44.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    if (form?.upload != null) {
                        Text(
                            "添加图片",
                            modifier = Modifier.clip(RoundedCornerShape(12.dp))
                                .clickable(enabled = !submitting) { imagePicker.launch("image/*") }
                                .padding(horizontal = 8.dp, vertical = 9.dp),
                            fontSize = 13.sp,
                        )
                    }
                    Text(
                        if (form == null) "准备中…" else "${messageDraft.length} 字",
                        modifier = Modifier.weight(1f),
                        fontSize = 12.sp,
                        color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                    )
                    Button(
                        onClick = ::send,
                        minHeight = 40.dp,
                        enabled = form != null && messageIndex >= 0 && !submitting && messageDraft.isNotBlank(),
                        colors = ButtonDefaults.buttonColorsPrimary(),
                        insideMargin = PaddingValues(horizontal = 14.dp, vertical = 9.dp),
                    ) {
                        if (submitting) CircularProgressIndicator(size = 18.dp)
                        else Text(
                            "发布", fontSize = 14.sp,
                            color = if (form != null && !submitting && messageDraft.isNotBlank())
                                MiuixTheme.colorScheme.onPrimary
                            else MiuixTheme.colorScheme.disabledOnPrimaryButton,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ReplyMessageEditor(
    message: String,
    onMessageChange: (String) -> Unit,
    focusRequester: FocusRequester,
    enabled: Boolean,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier.clip(RoundedCornerShape(18.dp))
            .background(MiuixTheme.colorScheme.background)
            .padding(horizontal = 14.dp, vertical = 12.dp),
    ) {
        BasicTextField(
            value = message,
            onValueChange = onMessageChange,
            enabled = enabled,
            modifier = Modifier.fillMaxSize().focusRequester(focusRequester),
            cursorBrush = SolidColor(MiuixTheme.colorScheme.onSurface),
            textStyle = TextStyle(
                fontSize = 15.sp, lineHeight = 23.sp,
                color = MiuixTheme.colorScheme.onSurface,
            ),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Default),
            decorationBox = { input ->
                Box {
                    if (message.isEmpty()) {
                        Text("说点什么吧…", fontSize = 15.sp,
                            color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                    }
                    input()
                }
            },
        )
    }
}
