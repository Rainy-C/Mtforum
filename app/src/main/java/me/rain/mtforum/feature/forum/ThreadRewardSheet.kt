package me.rain.mtforum.feature.forum

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import me.rain.mtforum.core.network.*
import okhttp3.HttpUrl.Companion.toHttpUrl
import top.yukonga.miuix.kmp.basic.*
import top.yukonga.miuix.kmp.theme.MiuixTheme

/** Server-provided Discuz rateform, confirmed for main posts and individual replies. */
@Composable
internal fun ThreadRewardSheet(
    repository: ForumRepository,
    tid: String,
    pid: String,
    author: String,
    onDismiss: () -> Unit,
    onDone: (String) -> Unit,
) {
    var form by remember(tid, pid) { mutableStateOf<RemoteForm?>(null) }
    var error by remember(tid, pid) { mutableStateOf<String?>(null) }
    var loading by remember(tid, pid) { mutableStateOf(true) }
    var submitting by remember(tid, pid) { mutableStateOf(false) }
    var score1 by remember(tid, pid) { mutableStateOf("0") }
    var score2 by remember(tid, pid) { mutableStateOf("0") }
    var reason by remember(tid, pid) { mutableStateOf("") }
    val scope = rememberCoroutineScope()

    LaunchedEffect(tid, pid) {
        loading = true
        error = null
        try {
            val url = "${ForumRepository.BaseUrl}/forum.php?mod=misc&action=rate&tid=$tid&pid=$pid&inajax=1"
            val parsed = repository.document(url, "打赏")
            form = parsed.forms.firstOrNull { it.id.startsWith("rateform") &&
                it.fields.any { f -> f.key == "score1" } &&
                it.fields.any { f -> f.key == "score2" } }
            if (form == null) error = "论坛未返回打赏表单，可能无权限或已打赏"
            form?.let { active ->
                score1 = active.fields.firstOrNull { it.key == "score1" }?.value
                    ?.toIntOrNull()?.coerceAtLeast(0)?.toString() ?: "0"
                score2 = active.fields.firstOrNull { it.key == "score2" }?.value
                    ?.toIntOrNull()?.coerceAtLeast(0)?.toString() ?: "0"
                reason = active.fields.firstOrNull { it.key == "reason" }?.value.orEmpty()
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            error = e.readable()
        } finally {
            loading = false
        }
    }

    Dialog(
        onDismissRequest = { if (!submitting) onDismiss() },
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Card(Modifier.fillMaxWidth(.93f)) {
            Column(
                Modifier.fillMaxWidth().padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Text("打赏", fontSize = 21.sp, fontWeight = FontWeight.SemiBold)
                Text("支持 ${author.ifBlank { "论坛作者" }} 的帖子或评论",
                    fontSize = 13.sp, color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                error?.let { Text(it, fontSize = 13.sp,
                    color = MiuixTheme.colorScheme.onSurfaceVariantSummary) }
                if (loading) {
                    Box(Modifier.fillMaxWidth().height(64.dp), Alignment.Center) {
                        CircularProgressIndicator()
                    }
                } else if (form != null) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        listOf("好评" to score1, "金币" to score2).forEachIndexed { index, data ->
                            Column(Modifier.weight(1f),
                                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text(data.first, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                                Box(
                                    Modifier.fillMaxWidth().height(54.dp)
                                        .clip(RoundedCornerShape(15.dp))
                                        .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .055f))
                                        .padding(horizontal = 14.dp),
                                    Alignment.CenterStart,
                                ) {
                                    BasicTextField(
                                        data.second,
                                        { value ->
                                            if (value.length <= 6 && value.all(Char::isDigit)) {
                                                if (index == 0) score1 = value else score2 = value
                                            }
                                        },
                                        modifier = Modifier.fillMaxWidth(),
                                        singleLine = true,
                                        textStyle = TextStyle(fontSize = 19.sp,
                                            fontWeight = FontWeight.SemiBold,
                                            color = MiuixTheme.colorScheme.onSurface),
                                        cursorBrush = SolidColor(MiuixTheme.colorScheme.onSurface),
                                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                                    )
                                }
                            }
                        }
                    }
                    Text("自定义附言", fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                    Box(
                        Modifier.fillMaxWidth().heightIn(min = 68.dp)
                            .clip(RoundedCornerShape(15.dp))
                            .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .055f))
                            .padding(13.dp),
                    ) {
                        BasicTextField(
                            value = reason,
                            onValueChange = { if (it.length <= 180) reason = it },
                            modifier = Modifier.fillMaxWidth(),
                            textStyle = TextStyle(fontSize = 14.sp,
                                color = MiuixTheme.colorScheme.onSurface),
                            maxLines = 3,
                            cursorBrush = SolidColor(MiuixTheme.colorScheme.onSurface),
                            decorationBox = { inner ->
                                Box {
                                    if (reason.isEmpty()) Text("输入打赏理由", fontSize = 14.sp,
                                        color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                                    inner()
                                }
                            },
                        )
                    }
                    Text("数值可编辑，实际允许范围以论坛规则为准；确认后扣除对应积分。",
                        fontSize = 12.sp,
                        color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Box(
                        Modifier.weight(1f).height(45.dp)
                            .clip(RoundedCornerShape(15.dp))
                            .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .06f))
                            .clickable(enabled = !submitting) { onDismiss() },
                        Alignment.Center,
                    ) { Text("取消") }
                    Box(
                        Modifier.weight(1f).height(45.dp)
                            .clip(RoundedCornerShape(15.dp))
                            .background(MiuixTheme.colorScheme.onSurface.copy(
                                alpha = if (form != null && (score1.toIntOrNull() ?: 0) + (score2.toIntOrNull() ?: 0) > 0) 1f else .2f,
                            ))
                            .clickable(enabled = form != null && !submitting &&
                                ((score1.toIntOrNull() ?: 0) > 0 || (score2.toIntOrNull() ?: 0) > 0)) {
                                val active = form ?: return@clickable
                                scope.launch {
                                    submitting = true
                                    error = null
                                    try {
                                        val url = active.url.toHttpUrl().newBuilder()
                                            .setQueryParameter("handlekey", "rateform")
                                            .setQueryParameter("inajax", "1")
                                            .build().toString()
                                        val payload = active.fields.mapNotNull { field ->
                                            if (field.type == "checkbox" && !field.checked) return@mapNotNull null
                                            field.key to when (field.key) {
                                                "score1" -> score1
                                                "score2" -> score2
                                                "reason" -> reason
                                                else -> field.value
                                            }
                                        }
                                        val result = repository.submit(
                                            active.copy(url = url, method = "POST"),
                                            payload,
                                            RemoteSubmit("打赏", "", ""),
                                        )
                                        if (result.success) onDone("打赏成功")
                                        else error = result.message
                                    } catch (e: CancellationException) {
                                        throw e
                                    } catch (e: Exception) {
                                        error = e.readable()
                                    } finally {
                                        submitting = false
                                    }
                                }
                            },
                        Alignment.Center,
                    ) {
                        if (submitting) CircularProgressIndicator(size = 18.dp)
                        else Text("确认打赏",
                            color = MiuixTheme.colorScheme.background)
                    }
                }
            }
        }
    }
}
