package me.rain.mtforum.feature.web

import android.annotation.SuppressLint
import android.content.Context
import android.net.Uri
import android.webkit.CookieManager
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import me.rain.mtforum.core.network.ForumRepository

fun isForumUrl(url: String): Boolean {
    val uri = Uri.parse(url)
    return uri.scheme == "https" && uri.host == ForumRepository.Host && uri.userInfo == null
}

@SuppressLint("SetJavaScriptEnabled")
fun createForumWebView(
    context: Context,
    onFinished: (() -> Unit)? = null,
    onError: (() -> Unit)? = null,
): WebView = WebView(context).apply {
    settings.apply {
        javaScriptEnabled = true
        domStorageEnabled = true
        userAgentString = ForumRepository.UserAgent
        allowFileAccess = false
        allowContentAccess = false
        mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        javaScriptCanOpenWindowsAutomatically = false
        setSupportMultipleWindows(false)
    }
    CookieManager.getInstance().setAcceptThirdPartyCookies(this, false)
    webViewClient = object : WebViewClient() {
        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
            request.isForMainFrame && !isForumUrl(request.url.toString())

        override fun onPageStarted(view: WebView, url: String, favicon: android.graphics.Bitmap?) {
            if (url != "about:blank" && !isForumUrl(url)) view.stopLoading()
        }

        override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
            if (request.isForMainFrame) onError?.invoke()
        }

        override fun onPageFinished(view: WebView, url: String) {
            if (isForumUrl(url)) onFinished?.invoke()
        }
    }
}

fun WebView.releaseForumView() {
    stopLoading()
    webViewClient = WebViewClient()
    (parent as? android.view.ViewGroup)?.removeView(this)
    removeAllViews()
    destroy()
}
