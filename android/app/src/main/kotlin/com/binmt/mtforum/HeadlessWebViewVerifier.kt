package com.binmt.mtforum

import android.annotation.SuppressLint
import android.app.Activity
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * 不可见 WebView 人机验证器。
 *
 * 用途：站点返回人机验证 / WAF JS 挑战页时，在**后台**跑一遍挑战脚本，
 * 把挑战生成的 Cookie 交给 Dart 侧回流到 CookieJar，然后由 Dart 侧用
 * 「原 URL + 原 UA 重新请求能否拿到论坛页」判定是否通过。
 *
 * 关键设计：
 * - WebView 挂在 Activity 内容视图上（1x1、INVISIBLE、不可点击不可聚焦）。
 *   WebView 只有真正附着到窗口才会执行 JS —— 仅 new 一个 WebView 而不挂载，
 *   挑战脚本不会运行；
 * - UA 由 Dart 侧传入（与 Dio 完全一致），并在 loadUrl 的请求头里再写一次；
 * - 启动前清掉旧防护 Cookie，只注入 Dart 侧给出的核心登录 Cookie；
 * - 本类**不做通过判定**，只负责"跑脚本 + 读写 Cookie"。
 */
class HeadlessWebViewVerifier(private val activity: Activity) {

    private class Session(
        val id: String,
        val url: String,
        val container: FrameLayout,
        val webView: WebView,
        var loadCount: Int = 0,
    )

    private val sessions = ConcurrentHashMap<String, Session>()

    fun isAvailable(): Boolean = true

    /**
     * 启动一次后台验证，返回会话 id。
     *
     * 必须运行在主线程（Flutter MethodChannel 的 handler 天然在主线程）。
     */
    @SuppressLint("SetJavaScriptEnabled")
    fun start(
        url: String,
        userAgent: String,
        cookies: Map<String, String>,
        staleCookieNames: List<String>,
    ): String? {
        if (url.isBlank()) return null
        val parsed = Uri.parse(url)
        val host = parsed.host ?: return null

        val container = FrameLayout(activity)
        val webView = WebView(activity)

        try {
            val settings: WebSettings = webView.settings
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.databaseEnabled = true
            settings.loadsImagesAutomatically = true
            settings.javaScriptCanOpenWindowsAutomatically = false
            settings.setSupportMultipleWindows(false)
            settings.cacheMode = WebSettings.LOAD_DEFAULT
            settings.mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
            if (userAgent.isNotBlank()) {
                settings.userAgentString = userAgent
            }

            webView.setBackgroundColor(Color.TRANSPARENT)
            webView.isVerticalScrollBarEnabled = false
            webView.isHorizontalScrollBarEnabled = false
            webView.isFocusable = false
            webView.isFocusableInTouchMode = false
            webView.isClickable = false
            webView.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO

            val session = Session(
                id = UUID.randomUUID().toString(),
                url = url,
                container = container,
                webView = webView,
            )

            webView.webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView, pageUrl: String) {
                    session.loadCount += 1
                    // 挑战脚本通常在页面加载后立刻写 Cookie，flush 保证
                    // Dart 侧下一次 getCookie 就能读到。
                    runCatching { CookieManager.getInstance().flush() }
                }

                @Deprecated("Deprecated in Java")
                override fun shouldOverrideUrlLoading(view: WebView, target: String): Boolean = false
            }

            container.addView(
                webView,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                ),
            )
            // 1x1、移出可视区域、完全不可见：不参与布局、不可点击。
            container.visibility = View.INVISIBLE
            container.isClickable = false
            container.isFocusable = false
            container.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO

            val params = FrameLayout.LayoutParams(1, 1)
            params.leftMargin = -2
            params.topMargin = -2
            val root = activity.findViewById<ViewGroup>(android.R.id.content)
            if (root == null) {
                webView.destroy()
                return null
            }
            root.addView(container, params)

            prepareCookies(webView, url, host, cookies, staleCookieNames)

            sessions[session.id] = session
            // 显式带上 UA，确保本次加载的请求头与 Dio 完全一致。
            webView.loadUrl(url, mapOf("User-Agent" to userAgent))
            return session.id
        } catch (t: Throwable) {
            runCatching {
                (webView.parent as? ViewGroup)?.removeView(webView)
                webView.destroy()
                (container.parent as? ViewGroup)?.removeView(container)
            }
            return null
        }
    }

    private fun prepareCookies(
        webView: WebView,
        url: String,
        host: String,
        cookies: Map<String, String>,
        staleCookieNames: List<String>,
    ) {
        val manager = CookieManager.getInstance()
        manager.setAcceptCookie(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            manager.setAcceptThirdPartyCookies(webView, true)
        }

        // 1) 清理旧防护 Cookie：域名写法可能有三种，逐种删一次。
        if (staleCookieNames.isNotEmpty()) {
            for (name in staleCookieNames) {
                if (name.isBlank()) continue
                for (domainPart in domainCandidates(host)) {
                    runCatching {
                        manager.setCookie(
                            url,
                            "$name=; Max-Age=0; Path=/$domainPart",
                        )
                    }
                }
            }
        }

        // 2) 只注入核心登录 Cookie（绝不注入防护 Cookie）。
        for ((name, value) in cookies) {
            if (name.isBlank()) continue
            val sanitized = value.replace("\n", "").replace("\r", "")
            // host-only + 带点域名两种写法都写一遍，兼容服务端两种存储形态。
            for (domainPart in domainCandidates(host)) {
                runCatching {
                    manager.setCookie(url, "$name=$sanitized; Path=/$domainPart")
                }
            }
        }
        runCatching { manager.flush() }
    }

    private fun domainCandidates(host: String): List<String> =
        listOf("", "; Domain=$host", "; Domain=.$host")

    /** 读取会话当前 Cookie（`name=value; name2=value2`）与加载完成次数。 */
    fun cookies(sessionId: String): Map<String, Any> {
        val session = sessions[sessionId] ?: return emptyMap()
        val raw = runCatching {
            CookieManager.getInstance().getCookie(session.url)
        }.getOrNull() ?: ""
        return mapOf(
            "cookie" to raw,
            "loadCount" to session.loadCount,
        )
    }

    /** 销毁会话并释放 WebView。 */
    fun dispose(sessionId: String) {
        val session = sessions.remove(sessionId) ?: return
        runCatching {
            session.webView.stopLoading()
            session.webView.webViewClient = WebViewClient()
            (session.webView.parent as? ViewGroup)?.removeView(session.webView)
            session.webView.destroy()
            (session.container.parent as? ViewGroup)?.removeView(session.container)
        }
    }

    /** Activity 销毁时兜底清理，避免 WebView 泄漏。 */
    fun disposeAll() {
        for (id in sessions.keys.toList()) {
            dispose(id)
        }
    }
}
