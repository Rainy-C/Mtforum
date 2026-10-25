package me.rain.mtforum.feature.auth

import android.view.ViewGroup
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import java.io.IOException
import kotlinx.coroutines.delay
import me.rain.mtforum.core.network.ForumRepository
import me.rain.mtforum.core.network.VerificationCoordinator
import me.rain.mtforum.core.ui.ActionButton
import me.rain.mtforum.feature.web.createForumWebView
import me.rain.mtforum.feature.web.releaseForumView
import top.yukonga.miuix.kmp.basic.Card
import top.yukonga.miuix.kmp.basic.Text

/** Same-UA WebView + original-URL HTTP probe; cookies alone never prove success. */
@Composable
fun VerificationHost(request: VerificationCoordinator.Request, repository: ForumRepository) {
    val context = LocalContext.current
    var manual by remember(request.id) { mutableStateOf(false) }
    val webView =
        remember(request.id, context) { createForumWebView(context).apply { loadUrl(request.url) } }
    DisposableEffect(webView) { onDispose { webView.releaseForumView() } }
    LaunchedEffect(request.id, "manual") {
        delay(8000)
        manual = true
    }
    LaunchedEffect(request.id) {
        while (!request.result.isCompleted) {
            delay(1000)
            try {
                if (repository.probe(request.url)) {
                    request.result.complete(true)
                    break
                }
            } catch (error: IOException) {
                // A transient probe failure is not a successful verification.
            }
        }
    }
    if (manual) {
        Dialog(
            onDismissRequest = { request.result.complete(false) },
            properties = DialogProperties(usePlatformDefaultWidth = false),
        ) {
            Card(Modifier.fillMaxWidth().padding(16.dp)) {
                Column(Modifier.padding(16.dp)) {
                    Text("请完成论坛验证")
                    AndroidView(
                        factory = {
                            (webView.parent as? ViewGroup)?.removeView(webView)
                            webView
                        },
                        modifier = Modifier.fillMaxWidth().height(420.dp),
                    )
                    ActionButton(
                        text = "取消验证",
                        modifier = Modifier.fillMaxWidth(),
                        primary = false,
                        onClick = { request.result.complete(false) },
                    )
                }
            }
        }
    } else {
        // Keep the JS environment attached, with no visible full-page jump.
        AndroidView(
            factory = {
                (webView.parent as? ViewGroup)?.removeView(webView)
                webView
            },
            modifier = Modifier.size(1.dp).alpha(0f),
        )
    }
}
