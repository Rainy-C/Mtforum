package me.rain.mtforum.feature.auth

import android.view.ViewGroup
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import java.io.IOException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import me.rain.mtforum.core.network.ForumRepository
import me.rain.mtforum.core.network.VerificationCoordinator
import me.rain.mtforum.core.ui.ActionButton
import me.rain.mtforum.feature.web.createForumWebView
import me.rain.mtforum.feature.web.releaseForumView
import top.yukonga.miuix.kmp.basic.Card
import top.yukonga.miuix.kmp.basic.Text

/**
 * Human verification stays inside the original site's WebView.
 * A passed challenge is never inferred from URL text or successful page load;
 * the original URL must be confirmed by ForumRepository.probe().
 */
@Composable
fun VerificationHost(request: VerificationCoordinator.Request, repository: ForumRepository) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var manual by remember(request.id) { mutableStateOf(false) }
    var checking by remember(request.id) { mutableStateOf(false) }
    var notice by remember(request.id) { mutableStateOf("正在打开论坛验证…") }
    var lastCheck by remember(request.id) { mutableLongStateOf(0L) }
    suspend fun probe() {
        val now = android.os.SystemClock.elapsedRealtime()
        if (checking || request.result.isCompleted || now - lastCheck < 1800L) return
        checking = true
        lastCheck = now
        try {
            repository.cookies.flush()
            if (repository.probe(request.url)) {
                request.result.complete(true)
            } else {
                notice = "验证尚未被论坛确认，可重试或检查网页中的提示"
            }
        } catch (e: IOException) {
            notice = "论坛网络检查失败，请检查连接后重试"
        } catch (e: Exception) {
            notice = "尚未确认通过，请在下方网页完成验证"
        } finally {
            checking = false
        }
    }
    val webView = remember(request.id, context) {
        createForumWebView(context,
            onFinished = { scope.launch { probe() } },
            onError = { manual = true; notice = "验证页加载失败，请尝试刷新" },
        ).apply { loadUrl(request.url) }
    }
    DisposableEffect(webView) { onDispose { webView.releaseForumView() } }
    LaunchedEffect(request.id) {
        delay(3500)
        manual = true
    }
    LaunchedEffect(request.id) {
        while (!request.result.isCompleted) {
            delay(4500)
            probe()
        }
    }
    if (manual) {
        Dialog(
            onDismissRequest = { request.result.complete(false) },
            properties = DialogProperties(usePlatformDefaultWidth = false),
        ) {
            Card(Modifier.fillMaxWidth(.97f).fillMaxHeight(.86f)) {
                Column(
                    Modifier.fillMaxSize().padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Text("论坛安全验证")
                    Text(notice)
                    // Full-size browser viewport. The original 420dp webview
                    // clipped a whole responsive forum page into a small dialog.
                    AndroidView(
                        factory = {
                            (webView.parent as? ViewGroup)?.removeView(webView)
                            webView
                        },
                        modifier = Modifier.fillMaxWidth().weight(1f),
                    )
                    Row(
                        Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        ActionButton("刷新网页", Modifier.weight(1f), primary = false) {
                            webView.reload()
                        }
                        ActionButton(
                            if (checking) "检查中…" else "我已完成",
                            Modifier.weight(1f),
                            primary = true,
                            loading = checking,
                        ) { scope.launch { probe() } }
                    }
                    ActionButton(
                        "取消验证",
                        Modifier.fillMaxWidth(),
                        primary = false,
                    ) { request.result.complete(false) }
                }
            }
        }
    } else {
        AndroidView(
            factory = {
                (webView.parent as? ViewGroup)?.removeView(webView)
                webView
            },
            modifier = Modifier.size(1.dp).alpha(0f),
        )
    }
}
