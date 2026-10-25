package me.rain.mtforum.feature.forum

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import me.rain.mtforum.core.network.*
import me.rain.mtforum.core.ui.*
import top.yukonga.miuix.kmp.basic.*
import top.yukonga.miuix.kmp.icon.MiuixIcons
import top.yukonga.miuix.kmp.icon.icons.useful.Save

@Composable
fun MediaScreen(
    repository: ForumRepository,
    title: String,
    url: String,
    image: Boolean,
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val media = remember(repository) { ForumMedia(repository) }
    var scale by remember { mutableFloatStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    var busy by remember { mutableStateOf(false) }
    var progress by remember { mutableFloatStateOf(0f) }
    var message by remember { mutableStateOf<String?>(null) }
    val picker =
        rememberLauncherForActivityResult(
            ActivityResultContracts.CreateDocument("application/octet-stream")
        ) { uri ->
            if (uri != null)
                scope.launch {
                    busy = true
                    message = null
                    try {
                        media.save(context, url, uri) { current, total ->
                            progress = if (total > 0) current.toFloat() / total else 0f
                        }
                        message = "保存成功"
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        message = e.readable()
                    } finally {
                        busy = false
                    }
                }
        }
    fun save() {
        if (!busy)
            picker.launch(
                title.takeIf { it.contains('.') }
                    ?: android.webkit.URLUtil.guessFileName(url, null, null)
            )
    }
    Column(Modifier.fillMaxSize()) {
        PageHeader(if (image) "图片" else "下载附件", onBack) {
            ToolIcon(MiuixIcons.Useful.Save, "保存", !busy, onClick = ::save)
        }
        if (image)
            Box(
                Modifier.weight(1f).fillMaxWidth().pointerInput(Unit) {
                    detectTransformGestures { _, pan, zoom, _ ->
                        scale = (scale * zoom).coerceIn(1f, 5f)
                        offset = if (scale > 1f) offset + pan else Offset.Zero
                    }
                },
                Alignment.Center,
            ) {
                AsyncImage(
                    url,
                    "帖子图片",
                    Modifier.fillMaxSize().graphicsLayer {
                        scaleX = scale
                        scaleY = scale
                        translationX = offset.x
                        translationY = offset.y
                    },
                    contentScale = androidx.compose.ui.layout.ContentScale.Fit,
                )
            }
        else
            Box(Modifier.weight(1f).fillMaxWidth(), Alignment.Center) {
                EmptyState(
                    title,
                    icon = MiuixIcons.Useful.Save,
                    action = "选择保存位置",
                    onAction = ::save,
                )
            }
        if (busy)
            LinearProgressIndicator(
                progress = progress.takeIf { it > 0f },
                modifier = Modifier.padding(20.dp),
            )
        message?.let { Text(it, Modifier.padding(20.dp)) }
        Spacer(Modifier.navigationBarsPadding())
    }
}
