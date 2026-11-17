package me.rain.mtforum.core.network

import java.io.IOException
import android.os.SystemClock
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.Call
import okhttp3.Callback
import okhttp3.FormBody
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response

class ForumRepository(val cookies: ForumCookies, val verification: VerificationCoordinator) {
    private val sessionMutation = Mutex()
    private val topicCache = linkedMapOf<String, Pair<List<Topic>, String?>>()
    private val presenceCache = java.util.concurrent.ConcurrentHashMap<String, Pair<Boolean?, Long>>()
    private val presenceMaxAgeMs = 120_000L

    fun cachedConversationPresence(uid: String): Boolean? =
        presenceCache[uid]?.takeIf {
            SystemClock.elapsedRealtime() - it.second < presenceMaxAgeMs
        }?.first

    suspend fun resolveConversationPresence(uid: String): Boolean? {
        val record = presenceCache[uid]
        if (record != null &&
            SystemClock.elapsedRealtime() - record.second < presenceMaxAgeMs
        ) return record.first
        val presence = conversation(uid).online
        presenceCache[uid] = presence to SystemClock.elapsedRealtime()
        return presence
    }
    private var cacheGeneration = 0
    // Keep foreground pages responsive without flooding Discuz/PHP with parallel HTML requests.
    private val requestSlots = Semaphore(2)
    private val requestPace = Mutex()
    private var lastRequestAt = 0L
    private val previewSlots = Semaphore(1)
    private val previewCache = linkedMapOf<String, List<String>>()
    private val previewCooldown = linkedMapOf<String, Long>()

    private fun coolDownPreview(id: String) {
        previewCooldown[id] = SystemClock.elapsedRealtime() + 60_000L
        while (previewCooldown.size > 64) previewCooldown.remove(previewCooldown.keys.first())
    }

    fun clearContentCache() {
        presenceCache.clear()
        cacheGeneration++
        topicCache.clear()
        previewCache.clear()
        previewCooldown.clear()
    }

    private val client =
        OkHttpClient.Builder()
            .cookieJar(cookies)
            .retryOnConnectionFailure(false)
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(25, TimeUnit.SECONDS)
            .callTimeout(35, TimeUnit.SECONDS)
            .addInterceptor { chain ->
                chain.proceed(
                    chain
                        .request()
                        .newBuilder()
                        .header("User-Agent", UserAgent)
                        .header("Accept-Language", "zh-CN,zh;q=0.9")
                        .build()
                )
            }
            .addNetworkInterceptor { chain ->
                val url = chain.request().url
                if (url.scheme != "https" || url.host != Host) throw IOException("已阻止论坛外的请求跳转")
                chain.proceed(chain.request())
            }
            .build()

    private data class Page(val body: String, val type: String, val status: Int, val url: String)

    private suspend fun raw(request: Request): Page = requestSlots.withPermit {
        // The gap is between request starts, not between the response and the next page.
        // Cancellation while waiting does not start a request or leak a permit.
        requestPace.withLock {
            val wait = (lastRequestAt + 160L - SystemClock.elapsedRealtime()).coerceAtLeast(0L)
            if (wait > 0L) delay(wait)
            lastRequestAt = SystemClock.elapsedRealtime()
        }
        suspendCancellableCoroutine { continuation ->
            val call = client.newCall(request)
            continuation.invokeOnCancellation { call.cancel() }
            call.enqueue(
                object : Callback {
                    override fun onFailure(call: Call, e: IOException) {
                        if (continuation.isActive) continuation.resumeWith(Result.failure(e))
                    }
    
                    override fun onResponse(call: Call, response: Response) {
                        try {
                            val page =
                                response.use {
                                    val body = it.body ?: throw IOException("服务器返回了空响应")
                                    val source = body.source()
                                    source.request(2_000_001)
                                    if (source.buffer.size > 2_000_000) throw IOException("服务器响应过大")
                                    Page(
                                        body.string(),
                                        it.header("Content-Type").orEmpty(),
                                        it.code,
                                        it.request.url.toString(),
                                    )
                                }
                            if (continuation.isActive) continuation.resumeWith(Result.success(page))
                        } catch (error: IOException) {
                            if (continuation.isActive) continuation.resumeWith(Result.failure(error))
                        }
                    }
                }
            )
        }
    }

    private suspend fun requestPage(request: Request): Page {
        var page = raw(request)
        if (ForumParser.isChallenge(page.body, page.type)) {
            // Keep WAF cookies from the challenge response: clearing these here
            // can discard valid challenge state and create a verification loop.
            val replayable =
                request.method == "GET" && !ContentParser.isMutationUrl(request.url.toString())
            val verificationUrl =
                if (replayable) request.url.toString()
                else "$BaseUrl/member.php?mod=logging&action=login&mobile=2"
            if (!verification.verify(verificationUrl)) throw ForumException("论坛验证未完成，请重试")
            if (!replayable) throw ForumException("验证已完成，请先刷新确认操作结果")
            page = raw(request)
            if (ForumParser.isChallenge(page.body, page.type)) throw ForumException("论坛仍要求验证，请重试")
        }
        if (page.status !in 200..299) throw ForumException("论坛请求失败（${page.status}）")
        return page
    }

    private suspend fun request(request: Request): String = requestPage(request).body

    suspend fun probe(url: String): Boolean {
        val parsed = url.toHttpUrl()
        if (parsed.host != Host || parsed.scheme != "https") return false
        val page = raw(Request.Builder().url(parsed).build())
        return page.status in 200..299 &&
            ForumParser.hasForumSkeleton(page.body) &&
            !ForumParser.isChallenge(page.body, page.type)
    }

    suspend fun login(username: String, password: String, questionId: Int, answer: String) =
        sessionMutation.withLock {
            clearContentCache()
            cookies.clearCore()
            val loginUrl = "$BaseUrl/member.php?mod=logging&action=login&mobile=2"
            val form = ForumParser.loginForm(request(Request.Builder().url(loginUrl).build()))
            val url =
                "$BaseUrl/member.php"
                    .toHttpUrl()
                    .newBuilder()
                    .addQueryParameter("mod", "logging")
                    .addQueryParameter("action", "login")
                    .addQueryParameter("loginsubmit", "yes")
                    .addQueryParameter("loginhash", form.loginhash)
                    .addQueryParameter("handlekey", "loginform")
                    .addQueryParameter("inajax", "1")
                    .build()
            val body =
                FormBody.Builder()
                    .add("formhash", form.formhash)
                    .add("referer", "$BaseUrl/forum.php")
                    .add("fastloginfield", "username")
                    .add("cookietime", "31104000")
                    .add("username", username)
                    .add("password", password)
                    .add("questionid", questionId.toString())
                    .add("answer", answer)
                    .build()
            val response =
                request(
                    Request.Builder()
                        .url(url)
                        .post(body)
                        .header("Referer", loginUrl)
                        .header("X-Requested-With", "XMLHttpRequest")
                        .build()
                )
            if (!ForumParser.loginSucceeded(response)) {
                throw ForumException(ForumParser.message(response).ifBlank { "登录失败，请检查账号信息" })
            }
            if (!cookies.hasSession()) throw ForumException("登录状态未保存，请重新登录")
            withContext(Dispatchers.IO) { cookies.flush() }
        }

    suspend fun profile(): ForumProfile {
        val profileUrl = "$BaseUrl/home.php?mod=space&do=profile&mobile=2"
        var result = ForumParser.profile(request(Request.Builder().url(profileUrl).build()))
        if (result.threads == null || result.replies == null || result.friends == null) {
            try {
                val extra = ForumParser.profile(
                    request(Request.Builder().url("$profileUrl&uid=${result.uid}").build())
                )
                result = result.copy(
                    threads = result.threads ?: extra.threads,
                    replies = result.replies ?: extra.replies,
                    friends = result.friends ?: extra.friends,
                    credits = result.credits ?: extra.credits,
                    gold = result.gold ?: extra.gold,
                )
            } catch (error: SessionExpiredException) {
                throw error
            } catch (_: IOException) {
                // Keep every field already read successfully; unknown is not zero.
            }
        }
        if (result.friends == null) {
            try {
                val html = request(
                    Request.Builder()
                        .url("$BaseUrl/home.php?mod=space&do=friend&mobile=2")
                        .build()
                )
                result = result.copy(friends = ForumParser.friendCount(html, result.uid))
            } catch (error: SessionExpiredException) {
                throw error
            } catch (_: IOException) {
                // Friends are optional; keep the rest of the profile readable.
            }
        }
        if (result.credits == null || result.gold == null) {
            try {
                val body = request(Request.Builder().url("$BaseUrl/home.php?mod=spacecp&ac=credit").build())
                val stats = ForumParser.profileStats(org.jsoup.Jsoup.parse(body))
                result = result.copy(credits = result.credits ?: stats["积分"], gold = result.gold ?: stats["金币"])
            } catch (error: SessionExpiredException) {
                throw error
            } catch (_: IOException) {
                // Balance lookup must not erase profile statistics.
            }
        }
        return result
    }

    suspend fun logout() =
        sessionMutation.withLock {
            try {
                withTimeoutOrNull(5000) {
                    val profile =
                        raw(
                                Request.Builder()
                                    .url("$BaseUrl/home.php?mod=space&do=profile&mobile=2")
                                    .build()
                            )
                            .body
                    ForumParser.formhash(profile)?.let { hash ->
                        val url =
                            "$BaseUrl/member.php"
                                .toHttpUrl()
                                .newBuilder()
                                .addQueryParameter("mod", "logging")
                                .addQueryParameter("action", "logout")
                                .addQueryParameter("formhash", hash)
                                .addQueryParameter("mobile", "2")
                                .build()
                        // Logout does not replay or start a challenge after an uncertain response.
                        raw(Request.Builder().url(url).build())
                    }
                }
            } catch (error: IOException) {
                // Local logout remains available while offline.
            } finally {
                clearContentCache()
                cookies.clear()
            }
        }

    fun safeUrl(value: String): okhttp3.HttpUrl {
        val url = BaseUrl.toHttpUrl().resolve(value) ?: throw ForumException("链接无效")
        if (
            url.scheme != "https" ||
                url.host != Host ||
                url.username.isNotEmpty() ||
                url.password.isNotEmpty()
        ) {
            throw ForumException("无法在论坛内打开此链接")
        }
        return url
    }

    suspend fun html(url: String): Pair<String, String> {
        val page = requestPage(Request.Builder().url(safeUrl(url)).build())
        return page.body to page.url
    }

    suspend fun topics(url: String, refresh: Boolean = false): Pair<List<Topic>, String?> {
        if (!refresh)
            topicCache[url]?.let {
                return it
            }
        val generation = cacheGeneration
        val (body, actual) = html(url)
        val parsed = withContext(Dispatchers.Default) { ContentParser.topics(body, actual) }
        if (generation == cacheGeneration) {
            if (topicCache.size >= 20) topicCache.remove(topicCache.keys.first())
            topicCache[url] = parsed
        }
        return parsed
    }

    suspend fun boards(): List<ForumBoard> {
        val body = html("$BaseUrl/forum.php?forumlist=1").first
        return withContext(Dispatchers.Default) { ContentParser.boards(body) }
    }

    suspend fun detail(url: String): TopicDetail {
        val (body, actual) = html(url)
        return withContext(Dispatchers.Default) { ContentParser.detail(body, actual) }
    }

    /** Details-based thumbnails are optional. One in flight; back off on server failure. */
    suspend fun previewImages(topic: Topic): List<String> = previewSlots.withPermit {
        previewCache[topic.id]?.let { return@withPermit it }
        val now = SystemClock.elapsedRealtime()
        if ((previewCooldown[topic.id] ?: 0L) > now) return@withPermit emptyList()
        val generation = cacheGeneration
        val url = safeUrl(topic.url)
        if (ContentParser.isMutationUrl(url.toString())) return@withPermit emptyList()
        val page = try {
            raw(Request.Builder().url(url).build())
        } catch (error: IOException) {
            // Do not repeatedly request the same failed thumbnail on every scroll.
            coolDownPreview(topic.id)
            return@withPermit emptyList()
        }
        if (page.status !in 200..299 || ForumParser.isChallenge(page.body, page.type)) {
            coolDownPreview(topic.id)
            return@withPermit emptyList()
        }
        val images = try {
            withContext(Dispatchers.Default) {
                ContentParser.detail(page.body, page.url).posts.firstOrNull()?.images.orEmpty().take(3)
            }
        } catch (error: IOException) {
            coolDownPreview(topic.id)
            return@withPermit emptyList()
        }
        if (generation == cacheGeneration) {
            previewCooldown.remove(topic.id)
            previewCache[topic.id] = images
            while (previewCache.size > 64) previewCache.remove(previewCache.keys.first())
        }
        images
    }

    suspend fun userSpace(url: String): UserSpaceProfile {
        val requested = safeUrl(url)
        val uid = UserSpaceParser.uid(requested.toString())
        val target = if (uid != null) "$BaseUrl/home.php?mod=space&do=profile&uid=$uid&mobile=2" else requested.toString()
        val (body, actual) = html(target)
        return withContext(Dispatchers.Default) { UserSpaceParser.parse(body, actual, uid) }
    }

    suspend fun document(url: String, title: String): NativeDocument {
        val (body, actual) = html(url)
        return withContext(Dispatchers.Default) { ContentParser.document(body, actual, title) }
    }

    data class Submission(
        val message: String,
        val success: Boolean,
        val document: NativeDocument,
        val target: String?,
    )

    /**
     * For ordinary thread replies, use the exact fastpostform published by the
     * original thread page. The captured successful Comiis request uses this
     * form, not the separate forum.php?mod=post&action=reply editor page.
     */
    suspend fun replyDocument(targetUrl: String): NativeDocument {
        val target = safeUrl(targetUrl)
        val tid = target.queryParameter("tid")?.takeIf { it.all(Char::isDigit) }
            ?: return document(targetUrl, "回复")
        if (target.queryParameter("repquote") != null)
            return document(targetUrl, "回复")

        val threadUrl = "$BaseUrl/thread-$tid-1-1.html"
        val fromThread = document(threadUrl, "回复")
        val fastpost = fromThread.forms.firstOrNull { form ->
            form.id.startsWith("fastpostform") &&
                form.fields.any { it.key == "message" } &&
                form.fields.any { it.key == "formhash" } &&
                form.url.toHttpUrlOrNull()?.queryParameter("action") == "reply"
        } ?: return document(targetUrl, "回复")

        // Real successful POST captured from the forum includes tid and
        // replysubmit=yes in the URL itself. The raw HTML form action omits
        // these fields because Discuz's fastpost JavaScript supplies them.
        val action = fastpost.url.toHttpUrl().newBuilder().apply {
            removeAllQueryParameters("tid")
            addQueryParameter("tid", tid)
            removeAllQueryParameters("replysubmit")
            addQueryParameter("replysubmit", "yes")
            removeAllQueryParameters("mobile")
            addQueryParameter("mobile", "2")
            removeAllQueryParameters("inajax")
            addQueryParameter("inajax", "1")
            removeAllQueryParameters("handlekey")
            addQueryParameter("handlekey", "fastpost")
        }.build().toString()
        val form = fastpost.copy(
            url = action, method = "POST", referer = threadUrl,
            submits = listOf(RemoteSubmit("发表回复", "", "")),
        )
        return fromThread.copy(forms = listOf(form))
    }

    suspend fun submit(
        form: RemoteForm,
        values: List<Pair<String, String>>,
        submit: RemoteSubmit,
        files: List<ForumUpload> = emptyList(),
    ): Submission {
        val url = safeUrl(submit.url ?: form.url)
        val method = submit.method ?: form.method
        val data = values.toMutableList()
        if (submit.name.isNotEmpty()) data += submit.name to submit.value
        val action = url.queryParameter("action")
        if (action in listOf("newthread", "reply", "edit")) {
            val key =
                when (action) {
                    "newthread" -> "topicsubmit"
                    "reply" -> "replysubmit"
                    else -> "editsubmit"
                }
            if (data.none { it.first == key }) data += key to "yes"
        }
        val builder = Request.Builder().url(url).header("Referer", form.referer)
        if (url.queryParameter("inajax") == "1" || url.queryParameter("ac") == "profile")
            builder.header("X-Requested-With", "XMLHttpRequest")
        if (method == "GET") {
            val target = url.newBuilder()
            data.map { it.first }.distinct().forEach { target.removeAllQueryParameters(it) }
            data.forEach { (key, value) -> target.addQueryParameter(key, value) }
            builder.url(target.build())
        } else {
            val body =
                if (form.multipart || files.isNotEmpty()) {
                    MultipartBody.Builder()
                        .setType(MultipartBody.FORM)
                        .apply {
                            data.forEach { (key, value) -> addFormDataPart(key, value) }
                            files.forEach {
                                addFormDataPart(
                                    it.name,
                                    it.filename,
                                    it.bytes.toRequestBody(it.type.toMediaType()),
                                )
                            }
                        }
                        .build()
                } else
                    FormBody.Builder()
                        .apply { data.forEach { (key, value) -> add(key, value) } }
                        .build()
            builder.post(body)
        }
        val page = requestPage(builder.build())
        val ajaxBody = ContentParser.unwrap(page.body).trimStart()
        if (ajaxBody.startsWith("{")) {
            val json =
                runCatching { org.json.JSONObject(ajaxBody) }.getOrNull()
                    ?: throw ForumException("无法读取操作结果，请返回刷新查看")
            if (!json.has("err") || !json.has("msg")) throw ForumException("无法读取操作结果，请返回刷新查看")
            val message =
                org.jsoup.Jsoup.parse(json.optString("msg")).text().take(200).ifBlank {
                    "请返回查看操作结果"
                }
            val success = json.optInt("err", 1) == 0
            val target =
                json.optString("url").takeIf(String::isNotBlank)?.let {
                    runCatching { safeUrl(it).toString() }.getOrNull()
                }
            return Submission(
                message,
                success,
                NativeDocument("", page.url, listOf(ContentBlock(message)), emptyList()),
                target,
            )
        }
        val failed = Regex("抱歉|失败|错误|无权|不允许|无效的请求|验证码不正确|验证码错误|密码不正确|请先登录|未登录")
            .containsMatchIn(ForumParser.message(page.body))
        val redirectedToThread = action == "reply" && url.toString() != page.url &&
            page.url.toHttpUrlOrNull()?.let { final ->
                final.queryParameter("mod") == "viewthread" ||
                    Regex("""/thread-\d+""").containsMatchIn(final.encodedPath)
            } == true && ForumParser.hasForumSkeleton(page.body)
        val succeeded = !failed && (
            Regex("操作成功|保存成功|修改成功|设置成功|发送成功|主题已发布|回复发布成功|回复成功|回复发表成功|发表成功|发表回复成功|发布成功|个人资料保存成功")
                .containsMatchIn(page.body) ||
                Regex("""(?:parent\.)?show_success\s*\(|succeedhandle_\w+\s*\(""")
                    .containsMatchIn(page.body) ||
                redirectedToThread
        )
        val doc = if (succeeded) NativeDocument("", page.url, emptyList(), emptyList())
            else try {
                withContext(Dispatchers.Default) { ContentParser.document(page.body, page.url) }
            } catch (error: ForumException) {
                NativeDocument("", page.url, emptyList(), emptyList())
            }
        val readable = ForumParser.message(page.body).take(260)
        val message = if (succeeded) "操作成功" else readable.ifBlank { "已收到论坛响应，请查看结果" }
        val target =
            Regex("""(?:window\.location(?:\.href)?|location\.href)\s*=\s*['"]([^'"]+)""")
                .find(page.body)
                ?.groupValues
                ?.get(1)
                ?.let { runCatching { safeUrl(it).toString() }.getOrNull() }
        return Submission(message, succeeded, doc, target)
    }

    suspend fun signIn(): String {
        if (!cookies.hasSession()) throw SessionExpiredException()
        val page = html("$BaseUrl/k_misign-sign.html").first
        val signText = org.jsoup.Jsoup.parse(ContentParser.unwrap(page)).text()
        if (Regex("今日已签到|已签到").containsMatchIn(signText)) return "今日已签到"
        val hash = ForumParser.formhash(page)
            ?: ForumParser.formhash(html("$BaseUrl/home.php?mod=space&do=profile&mobile=2").first)
            ?: throw ForumException("无法获取签到凭证，请刷新后重试")
        val url =
            "$BaseUrl/plugin.php"
                .toHttpUrl()
                .newBuilder()
                .addQueryParameter("id", "k_misign:sign")
                .addQueryParameter("operation", "qiandao")
                .addQueryParameter("format", "text")
                .addQueryParameter("formhash", hash)
                .build()
        val message = ForumParser.message(
                request(
                    Request.Builder()
                        .url(url)
                        .header("Referer", "$BaseUrl/k_misign-sign.html")
                        .header("X-Requested-With", "XMLHttpRequest")
                        .build()
                )
            )
            .ifBlank { "请刷新查看签到结果" }
        if (!Regex("已签到|签到成功").containsMatchIn(message)) throw ForumException(message)
        return message
    }

    data class TopicActionResult(val message: String, val selected: Boolean)

    private fun topicActionFeedback(response: String, favorite: Boolean): TopicActionResult {
        val action = if (favorite) "收藏" else "点赞"
        val message = ForumParser.message(response).trim()
        val repeated = if (favorite)
            Regex("已经收藏|已收藏过|收藏过|重复收藏|已加入收藏").containsMatchIn(message)
        else
            Regex("已经推荐|已推荐过|推荐过|已经点赞|已点赞过|点赞过|已经支持|已支持过|已经评价|已评价过|您已评价过本主题|不能重复|重复推荐|重复点赞")
                .containsMatchIn(message)
        if (repeated) return TopicActionResult(message.ifBlank { "此前已${action}" }, true)
        if (Regex("抱歉|失败|错误|不允许|无权|没有权限|无效|已关闭|禁止|验证码|无法提交|请先登录|请求来路不正确")
                .containsMatchIn(message))
            throw ForumException(message.take(180))
        // Comiis/Discuz replies with recommendv:'+1' instead of the word "成功".
        // This is the first-tap response seen in the captured recommend_add request.
        val recommendAdded = !favorite &&
            Regex("""["']recommendv["']\s*:\s*["']\+1["']""")
                .containsMatchIn(response)
        val confirmed = recommendAdded || message.length in 1..160 &&
            Regex("成功|操作完成|推荐完成|感谢您的支持|谢谢支持|已加入收藏|已为您收藏")
                .containsMatchIn(message)
        if (!confirmed) throw ForumException(
            "论坛未确认${action}结果，请刷新后核对，避免重复操作" +
                (message.take(100).takeIf(String::isNotBlank)?.let { "：$it" } ?: "")
        )
        return TopicActionResult(message.ifBlank { "${action}成功" }, true)
    }

    suspend fun topicAction(tid: String, favorite: Boolean): TopicActionResult {
        if (!cookies.hasSession()) throw SessionExpiredException()
        require(tid.isNotBlank() && tid.all(Char::isDigit))
        val ref = "$BaseUrl/thread-$tid-1-1.html"
        val hash = ForumParser.formhash(html(ref).first)
            ?: throw ForumException("无法获取操作凭证，请刷新帖子后重试")

        if (!favorite) {
            val likeUrl = "$BaseUrl/forum.php".toHttpUrl().newBuilder()
                .addQueryParameter("mod", "misc")
                .addQueryParameter("action", "recommend")
                .addQueryParameter("handlekey", "recommend_add")
                .addQueryParameter("do", "add")
                .addQueryParameter("tid", tid)
                .addQueryParameter("hash", hash)
                .addQueryParameter("inajax", "1")
                .build()
            val response = request(
                Request.Builder().url(likeUrl).header("Referer", ref)
                    .header("X-Requested-With", "XMLHttpRequest").build()
            )
            return topicActionFeedback(response, false)
        }

        // Discuz GET renders a favorite form; the action is not applied until POST.
        val popupUrl = "$BaseUrl/home.php".toHttpUrl().newBuilder()
            .addQueryParameter("mod", "spacecp")
            .addQueryParameter("ac", "favorite")
            .addQueryParameter("type", "thread")
            .addQueryParameter("id", tid)
            .addQueryParameter("formhash", hash)
            .addQueryParameter("inajax", "1")
            .addQueryParameter("handlekey", "favorite")
            .build()
        val popup = request(
            Request.Builder().url(popupUrl).header("Referer", ref)
                .header("X-Requested-With", "XMLHttpRequest").build()
        )
        val form = org.jsoup.Jsoup.parse(ContentParser.unwrap(popup), popupUrl.toString())
            .select("form").firstOrNull { candidate ->
                val action = ContentParser.absolute(candidate.attr("action"), popupUrl.toString())
                    ?: popupUrl.toString()
                val target = action.toHttpUrlOrNull()
                target?.queryParameter("ac") == "favorite" &&
                    target.queryParameter("type") == "thread" &&
                    (target.queryParameter("id") == tid || target.queryParameter("id") == null)
            }
        if (form == null) {
            val message = ForumParser.message(popup)
            if (Regex("已经收藏|已收藏过|收藏过|重复收藏|已加入收藏").containsMatchIn(message))
                return TopicActionResult(message.ifBlank { "此前已收藏" }, true)
            throw ForumException(
                message.take(160).takeIf(String::isNotBlank)
                    ?: "论坛未返回收藏确认表单，无法安全提交"
            )
        }
        val actionUrl = safeUrl(
            ContentParser.absolute(form.attr("action"), popupUrl.toString())
                ?: popupUrl.toString()
        )
        val postUrl = actionUrl.newBuilder().removeAllQueryParameters("inajax")
            .addQueryParameter("inajax", "1").build()
        val posted = mutableSetOf<String>()
        val body = FormBody.Builder()
        form.select("input[name], textarea[name], select[name]").forEach { field ->
            val name = field.attr("name")
            val type = field.attr("type").lowercase()
            if (name.isBlank() || field.hasAttr("disabled") ||
                type in setOf("submit", "button", "reset", "file", "image") ||
                type in setOf("checkbox", "radio") && !field.hasAttr("checked")) return@forEach
            val value = when (field.tagName()) {
                "textarea" -> field.wholeText()
                "select" -> field.selectFirst("option[selected]")?.attr("value")
                    ?: field.selectFirst("option")?.attr("value").orEmpty()
                else -> field.attr("value")
            }
            body.add(name, value)
            posted += name
        }
        if ("formhash" !in posted) body.add("formhash", hash)
        if ("referer" !in posted) body.add("referer", ref)
        if ("favoritesubmit" !in posted) body.add("favoritesubmit", "true")
        form.selectFirst("button[type=submit][name], input[type=submit][name]")?.let {
            body.add(it.attr("name"), it.attr("value").ifBlank { "true" })
        }
        val response = request(
            Request.Builder().url(postUrl).header("Referer", popupUrl.toString())
                .header("X-Requested-With", "XMLHttpRequest")
                .post(body.build()).build()
        )
        return topicActionFeedback(response, true)
    }

    /**
     * Deleting a favorite requires its unique favid, NOT its thread tid.
     * Follow the actual Discuz two-step popup form shown in the user capture.
     * Never act on a favorite unless its list row links to this exact tid.
     */
    private suspend fun favoriteDeleteUrl(tid: String): String? {
        var next: String? = "$BaseUrl/home.php?mod=space&do=favorite&view=me&type=all&mobile=2"
        val seen = mutableSetOf<String>()
        repeat(4) {
            val target = next ?: return null
            if (!seen.add(target)) return null
            val (body, page) = html(target)
            val doc = org.jsoup.Jsoup.parse(ContentParser.unwrap(body), page)
            doc.select("li.mysclist_li, li[id^=fav_]").forEach { row ->
                val thread = row.select("a[href]").firstOrNull {
                    ContentParser.topicId(it.attr("href")) == tid
                }
                if (thread != null) {
                    val delete = row.select("a[href]").firstNotNullOfOrNull {
                        val href = ContentParser.absolute(it.attr("href"), page)
                        val u = href?.toHttpUrlOrNull()
                        if (u?.host == Host && u.queryParameter("mod") == "spacecp" &&
                            u.queryParameter("ac") == "favorite" &&
                            u.queryParameter("op") == "delete" &&
                            u.queryParameter("favid")?.all(Char::isDigit) == true) href else null
                    }
                    if (delete != null) return delete
                }
            }
            next = doc.selectFirst("a.nxt[href], .pg a.next[href]")
                ?.let { ContentParser.absolute(it.attr("href"), page) }
        }
        return null
    }

    suspend fun isThreadFavorited(tid: String): Boolean {
        require(tid.isNotBlank() && tid.all(Char::isDigit))
        if (!cookies.hasSession()) return false
        return favoriteDeleteUrl(tid) != null
    }

    suspend fun unfavoriteThread(tid: String): TopicActionResult {
        if (!cookies.hasSession()) throw SessionExpiredException()
        require(tid.isNotBlank() && tid.all(Char::isDigit))
        val listUrl = "$BaseUrl/home.php?mod=space&do=favorite&view=me&type=all&mobile=2"
        val deleteUrl = favoriteDeleteUrl(tid)
            ?: throw ForumException("未在近期收藏中找到该帖子，请在收藏列表核对")
        val popupUrl = deleteUrl.toHttpUrl().newBuilder()
            .setQueryParameter("inajax", "1").build()
        val popup = request(
            Request.Builder().url(popupUrl).header("Referer", listUrl)
                .header("X-Requested-With", "XMLHttpRequest").build()
        )
        val doc = org.jsoup.Jsoup.parse(ContentParser.unwrap(popup), popupUrl.toString())
        val form = doc.select("form[id^=favoriteform_]").firstOrNull()
            ?: throw ForumException(ForumParser.message(popup).ifBlank { "删除收藏确认表单不存在" })
        val action = ContentParser.absolute(form.attr("action"), popupUrl.toString())
            ?: throw ForumException("删除收藏地址无效")
        val target = safeUrl(action)
        if (target.queryParameter("ac") != "favorite" ||
            target.queryParameter("op") != "delete" ||
            target.queryParameter("favid") != popupUrl.queryParameter("favid"))
            throw ForumException("收藏记录校验失败，已取消删除")
        val postUrl = target.newBuilder()
            .setQueryParameter("handlekey", form.id())
            .setQueryParameter("inajax", "1")
            .build()
        val fields = FormBody.Builder()
        val posted = mutableSetOf<String>()
        form.select("input[name]").forEach { field ->
            val name = field.attr("name")
            val type = field.attr("type").lowercase()
            if (name.isBlank() || type in setOf("button", "reset", "file", "submit")) return@forEach
            fields.add(name, field.attr("value"))
            posted.add(name)
        }
        if ("deletesubmit" !in posted) fields.add("deletesubmit", "true")
        if ("handlekey" !in posted) fields.add("handlekey", form.id())
        val result = request(
            Request.Builder().url(postUrl).header("Referer", popupUrl.toString())
                .header("X-Requested-With", "XMLHttpRequest")
                .post(fields.build()).build()
        )
        val message = ForumParser.message(result)
        if (Regex("操作成功|删除成功|取消收藏成功").containsMatchIn(result))
            return TopicActionResult("已取消收藏", false)
        throw ForumException(message.ifBlank { "论坛未确认取消收藏" })
    }

    suspend fun uploadAvatar(bytes: ByteArray): String {
        if (!cookies.hasSession()) throw SessionExpiredException()
        val profile = html("$BaseUrl/home.php?mod=space&do=profile&mycenter=1").first
        val hash = ForumParser.formhash(profile) ?: throw ForumException("无法获取头像上传凭证")
        val body =
            FormBody.Builder()
                .add(
                    "str",
                    "data:image/jpeg;base64," +
                        android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP),
                )
                .add("formhash", hash)
                .add("comiis_submit", "yes")
                .build()
        val response =
            request(
                Request.Builder()
                    .url("$BaseUrl/plugin.php?id=comiis_app_avatar&inajax=1&mobile=2")
                    .header(
                        "Referer",
                        "$BaseUrl/home.php?mod=space&do=profile&set=comiis&mycenter=1",
                    )
                    .header("X-Requested-With", "XMLHttpRequest")
                    .post(body)
                    .build()
            )
        val message = ForumParser.message(response)
        if (Regex("失败|错误|无效|过期|不允许").containsMatchIn(message))
            throw ForumException(message.take(200))
        return message.ifBlank { "已上传，请刷新查看头像" }
    }

    suspend fun uploadPostImage(
        form: RemoteForm,
        bytes: ByteArray,
        name: String,
        type: String,
    ): String {
        val config = form.upload ?: throw ForumException("当前页面不支持上传图片")
        if (bytes.isEmpty() || bytes.size > config.maxBytes)
            throw ForumException("图片不能超过 ${config.maxBytes / 1024}KB")
        if (!type.startsWith("image/")) throw ForumException("请选择图片文件")
        val data =
            MultipartBody.Builder()
                .setType(MultipartBody.FORM)
                .addFormDataPart("uid", config.uid)
                .addFormDataPart("hash", config.hash)
                .addFormDataPart("Filedata", name, bytes.toRequestBody(type.toMediaType()))
                .build()
        val body =
            request(
                Request.Builder()
                    .url(
                        "$BaseUrl/misc.php?mod=swfupload&operation=upload&type=image&inajax=yes&infloat=yes&simple=2"
                    )
                    .header("Referer", form.url)
                    .header("X-Requested-With", "XMLHttpRequest")
                    .post(data)
                    .build()
            )
        val payload =
            ContentParser.unwrap(body)
                .substringAfter("DISCUZUPLOAD|", "")
                .substringBefore('<')
                .trim()
                .split('|')
        // After removing the marker: type | status | aid | ...
        if (payload.size < 3 || payload[1] != "0" || !payload[2].matches(Regex("\\d+"))) {
            throw ForumException("图片上传失败，请检查格式及大小")
        }
        return payload[2]
    }

    suspend fun conversations(): List<ConversationSummary> {
        val (body, url) = html("$BaseUrl/home.php?mod=space&do=pm&mobile=2")
        val summaries = withContext(Dispatchers.Default) {
            ContentParser.conversations(body, url)
        }
        return summaries.map { item ->
            if (item.online != null) {
                presenceCache[item.uid] = item.online to SystemClock.elapsedRealtime()
                item
            } else item.copy(online = cachedConversationPresence(item.uid))
        }
    }

    suspend fun conversation(uid: String): Conversation {
        require(uid.isNotEmpty() && uid.all(Char::isDigit))
        val (body, url) = html("$BaseUrl/home.php?mod=space&do=pm&subop=view&touid=$uid&mobile=2")
        val result = withContext(Dispatchers.Default) {
            ContentParser.conversation(body, url, uid)
        }
        if (result.online != null) {
            presenceCache[uid] = result.online to SystemClock.elapsedRealtime()
        }
        return result
    }

    suspend fun uploadPrivateImage(
        conversation: Conversation,
        bytes: ByteArray,
        filename: String,
        mime: String,
    ): String {
        val config = conversation.upload
            ?: throw ForumException("论坛私信页未提供图片上传权限。可使用“图片链接”发送已有的网络图片")
        if (!cookies.hasSession()) throw SessionExpiredException()
        val uploadForm = RemoteForm(
            "pm-upload",
            "$BaseUrl/home.php?mod=space&do=pm&subop=view&touid=${conversation.peer}&mobile=2",
            "POST",
            true,
            emptyList(),
            emptyList(),
            upload = config,
        )
        val aid = uploadPostImage(uploadForm, bytes, filename, mime)
        return "[attachimg]$aid[/attachimg]"
    }

    suspend fun sendPrivateMessage(conversation: Conversation, text: String) {
        if (!cookies.hasSession()) throw SessionExpiredException()
        if (text.isBlank()) throw ForumException("消息不能为空")
        val hash =
            conversation.formhash.ifBlank {
                ForumParser.formhash(html("$BaseUrl/home.php?mod=space&do=profile&mobile=2").first)
                    .orEmpty()
            }
        if (hash.isBlank()) throw ForumException("发送凭证已过期，请刷新后重试")
        val url =
            "$BaseUrl/home.php"
                .toHttpUrl()
                .newBuilder()
                .addQueryParameter("mod", "spacecp")
                .addQueryParameter("ac", "pm")
                .addQueryParameter("op", "send")
                .addQueryParameter("pmid", conversation.pmid)
                .addQueryParameter("daterange", "2")
                .addQueryParameter("pmsubmit", "yes")
                .addQueryParameter("mobile", "2")
                .addQueryParameter("handlekey", "pmform")
                .addQueryParameter("inajax", "1")
                .build()
        val body =
            FormBody.Builder()
                .add("formhash", hash)
                .add("touid", conversation.peer)
                .add("message", text.trim())
                .build()
        val response =
            request(
                Request.Builder()
                    .url(url)
                    .header(
                        "Referer",
                        "$BaseUrl/home.php?mod=space&do=pm&subop=view&touid=${conversation.peer}",
                    )
                    .header("X-Requested-With", "XMLHttpRequest")
                    .post(body)
                    .build()
            )
        if (
            !response.contains("操作成功") &&
                !Regex("""succeedhandle_\w+\s*\(\s*['"]""").containsMatchIn(response)
        )
            throw ForumException(ForumParser.message(response).take(200).ifBlank { "发送失败，请稍后重试" })
    }

    data class SmsPage(val phone: String?, val formhash: String)

    suspend fun smsPage(): SmsPage {
        val body = html("$BaseUrl/home.php?mod=spacecp&ac=plugin&id=comiis_sms:comiis_setup").first
        val doc = org.jsoup.Jsoup.parse(ContentParser.unwrap(body))
        val phone =
            doc.select(
                    "input[name=comiis_tel], input[name=secmobilenew], input[name=mobile], input[name=phone]"
                )
                .map { it.attr("value").trim() }
                .firstOrNull { it.matches(Regex("\\d{7,15}")) }
                ?: Regex("""\b(1\d{10})\b""").find(doc.body().text())?.groupValues?.get(1)
        return SmsPage(phone, ForumParser.formhash(body).orEmpty())
    }

    suspend fun requestSmsCode(phone: String, unbind: Boolean): Int {
        if (!cookies.hasSession()) throw SessionExpiredException()
        if (!phone.matches(Regex("\\d{7,15}"))) throw ForumException("请输入正确的手机号码")
        val url =
            "$BaseUrl/plugin.php"
                .toHttpUrl()
                .newBuilder()
                .addQueryParameter("id", "comiis_sms")
                .addQueryParameter("action", if (unbind) "Unbundling" else "binding")
                .addQueryParameter("comiis_tel", phone)
                .addQueryParameter("inajax", "1")
                .build()
        val body =
            request(
                Request.Builder()
                    .url(url)
                    .header(
                        "Referer",
                        "$BaseUrl/home.php?mod=spacecp&ac=plugin&id=comiis_sms:comiis_setup",
                    )
                    .header("X-Requested-With", "XMLHttpRequest")
                    .build()
            )
        val match = Regex("""comiis_mob_reg\|(\d+)\|(\d+)""").find(body)
        if (match?.groupValues?.get(1) != "1")
            throw ForumException(ForumParser.message(body).ifBlank { "验证码发送失败" })
        return (match.groupValues[2].toIntOrNull() ?: 60).coerceIn(1, 600)
    }

    suspend fun confirmSms(phone: String, code: String, unbind: Boolean): String {
        if (!cookies.hasSession()) throw SessionExpiredException()
        val hash =
            smsPage().formhash.ifBlank {
                ForumParser.formhash(html("$BaseUrl/home.php?mod=space&do=profile&mobile=2").first)
                    .orEmpty()
            }
        if (hash.isBlank()) throw ForumException("验证凭证已过期，请刷新后重试")
        val ref = "$BaseUrl/home.php?mod=spacecp&ac=plugin&id=comiis_sms:comiis_setup"
        val data =
            MultipartBody.Builder()
                .setType(MultipartBody.FORM)
                .addFormDataPart("formhash", hash)
                .addFormDataPart("comiis_mobile_bindingsubmit", "true")
                .addFormDataPart(
                    "referer",
                    if (unbind) "$ref&mods=rename"
                    else "$BaseUrl/plugin.php?id=comiis_sms:comiis_sms_post&action=Unbundling",
                )
                .addFormDataPart("comiis_tel", phone.trim())
                .addFormDataPart("code", code.trim())
                .build()
        val response =
            request(
                Request.Builder()
                    .url(
                        "$BaseUrl/plugin.php?id=comiis_sms:comiis_sms_post&action=" +
                            if (unbind) "Unbundling" else "binding"
                    )
                    .header("Referer", if (unbind) ref else "$ref&mobile=2")
                    .post(data)
                    .build()
            )
        if (!response.contains(if (unbind) "解除绑定成功" else "绑定成功"))
            throw ForumException(ForumParser.message(response).ifBlank { "操作失败，请检查验证码" })
        return if (unbind) "解除绑定成功" else "绑定成功"
    }

    companion object {
        const val Host = "bbs.binmt.cc"
        const val BaseUrl = "https://bbs.binmt.cc"
        const val UserAgent =
            "Mozilla/5.0 (Linux; Android 16) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Mobile Safari/537.36"
    }
}
