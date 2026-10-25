package me.rain.mtforum.feature.web

import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import me.rain.mtforum.core.ui.*
import top.yukonga.miuix.kmp.basic.LinearProgressIndicator
import top.yukonga.miuix.kmp.icon.MiuixIcons
import top.yukonga.miuix.kmp.icon.icons.useful.Confirm

@Composable
fun ForumBrowserScreen(title: String, url: String, onClose: () -> Unit) {
    require(isForumUrl(url))
    val context = LocalContext.current
    var loading by remember(url) { mutableStateOf(true) }
    var failed by remember(url) { mutableStateOf(false) }
    val webView =
        remember(url, context) {
            createForumWebView(
                    context,
                    onFinished = { loading = false },
                    onError = {
                        loading = false
                        failed = true
                    },
                )
                .apply { loadUrl(url) }
        }
    DisposableEffect(webView) { onDispose { webView.releaseForumView() } }
    Column(Modifier.fillMaxSize().navigationBarsPadding()) {
        PageHeader(title, { if (webView.canGoBack()) webView.goBack() else onClose() }) {
            ToolIcon(MiuixIcons.Useful.Confirm, "完成登录", onClick = onClose)
        }
        if (loading) LinearProgressIndicator()
        if (failed)
            EmptyState(
                "加载失败",
                action = "重试",
                onAction = {
                    failed = false
                    loading = true
                    webView.reload()
                },
            )
        AndroidView(factory = { webView }, modifier = Modifier.weight(1f).fillMaxWidth())
    }
}
