package me.rain.mtforum.feature.forum

import android.media.MediaPlayer
import android.widget.MediaController
import android.widget.VideoView
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import top.yukonga.miuix.kmp.theme.MiuixTheme

/** Embedded direct streams use Android media codecs; hosted sites open their original HTTPS URL. */
@Composable
internal fun PostMedia(url: String, tag: String, onOpen: (String, String) -> Unit) {
    if (!url.startsWith("https://")) return
    val isAudio = tag == "audio" || url.substringBefore('?').matches(Regex(""".*\.(mp3|m4a|aac|ogg|wav|wma|ra|rm)""", RegexOption.IGNORE_CASE))
    val directVideo = !isAudio && url.substringBefore('?').matches(Regex(""".*\.(mp4|m3u8|webm|3gp)""", RegexOption.IGNORE_CASE))
    var active by remember(url) { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().background(MiuixTheme.colorScheme.surface, RoundedCornerShape(14.dp))
        .padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        BasicText(if (isAudio) "音频" else "视频 / 嵌入媒体",
            style = TextStyle(fontSize = 14.sp, color = MiuixTheme.colorScheme.onSurface))
        when {
            isAudio -> {
                PostAudioPlayer(url)
                BasicText("使用外部应用打开", Modifier.clickable { onOpen("音频", url) },
                    style = TextStyle(fontSize = 12.sp, color = MiuixTheme.colorScheme.onSurfaceVariantSummary))
            }
            directVideo && active -> {
                AndroidView(
                    factory = { ctx ->
                        VideoView(ctx).apply {
                            setVideoPath(url)
                            setMediaController(MediaController(ctx).also { it.setAnchorView(this) })
                            setOnPreparedListener { mp -> mp.isLooping = false; start() }
                            setOnErrorListener { _, _, _ -> onOpen("媒体", url); true }
                        }
                    },
                    modifier = Modifier.fillMaxWidth().height(210.dp),
                    onRelease = { it.stopPlayback() },
                )
            }
            else -> {
                BasicText(if (directVideo) "点击播放" else "打开媒体原始页面",
                    Modifier.fillMaxWidth().clickable {
                        if (directVideo) active = true else onOpen("媒体", url)
                    }.padding(vertical = 10.dp),
                    style = TextStyle(fontSize = 13.sp, color = MiuixTheme.colorScheme.onSurface))
            }
        }
        BasicText(url, style = TextStyle(fontSize = 11.sp,
            color = MiuixTheme.colorScheme.onSurfaceVariantSummary), maxLines = 2)
    }
}

@Composable
private fun PostAudioPlayer(url: String) {
    var player by remember(url) { mutableStateOf<MediaPlayer?>(null) }
    var loading by remember(url) { mutableStateOf(false) }
    var playing by remember(url) { mutableStateOf(false) }
    var error by remember(url) { mutableStateOf(false) }
    DisposableEffect(url) {
        onDispose { player?.release(); player = null }
    }
    BasicText(
        when {
            error -> "播放失败，媒体可能不受支持"
            loading -> "音频缓冲中…"
            playing -> "暂停音频"
            else -> "播放音频"
        },
        Modifier.fillMaxWidth().clickable {
            if (loading || error) return@clickable
            val current = player
            if (current == null) {
                loading = true
                runCatching {
                    MediaPlayer().apply {
                        setDataSource(url)
                        setOnPreparedListener { loading = false; playing = true; start() }
                        setOnCompletionListener { playing = false }
                        setOnErrorListener { _, _, _ -> loading = false; playing = false; error = true; true }
                        prepareAsync()
                    }
                }.onSuccess { player = it }
                    .onFailure { loading = false; error = true }
            } else {
                runCatching {
                    if (current.isPlaying) { current.pause(); playing = false }
                    else { current.start(); playing = true }
                }.onFailure { error = true }
            }
        }.padding(vertical = 8.dp),
        style = TextStyle(fontSize = 13.sp, color = MiuixTheme.colorScheme.onSurface),
    )
}
