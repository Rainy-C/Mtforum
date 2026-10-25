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
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response

class ForumRepository(val cookies: ForumCookies, val verification: VerificationCoordinator) {
    private val sessionMutation = Mutex()
    private val topicCache = linkedMapOf<String, Pair<List<Topic>, String?>>()
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
            cookies.clearWaf()
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
        if (page.body.trimStart().startsWith("{")) {
            val json =
                runCatching { org.json.JSONObject(page.body) }.getOrNull()
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
        val failed = Regex("抱歉|失败|错误|无权|不允许|验证码不正确|密码不正确")
            .containsMatchIn(ForumParser.message(page.body))
        val succeeded = !failed && (
            Regex("操作成功|保存成功|修改成功|设置成功|发送成功|主题已发布|回复发布成功|回复成功|个人资料保存成功")
                .containsMatchIn(page.body) ||
                Regex("""(?:parent\.)?show_success\s*\(|succeedhandle_\w+\s*\(""")
                    .containsMatchIn(page.body)
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

    suspend fun topicAction(tid: String, favorite: Boolean): String {
        if (!cookies.hasSession()) throw SessionExpiredException()
        require(tid.all(Char::isDigit) && tid.isNotEmpty())
        val ref = "$BaseUrl/thread-$tid-1-1.html"
        val hash = ForumParser.formhash(html(ref).first) ?: throw ForumException("凭证已过期，请刷新后重试")
        val url =
            if (favorite)
                "$BaseUrl/home.php"
                    .toHttpUrl()
                    .newBuilder()
                    .addQueryParameter("mod", "spacecp")
                    .addQueryParameter("ac", "favorite")
                    .addQueryParameter("type", "thread")
                    .addQueryParameter("id", tid)
                    .addQueryParameter("formhash", hash)
                    .addQueryParameter("mobile", "2")
                    .build()
            else
                "$BaseUrl/forum.php"
                    .toHttpUrl()
                    .newBuilder()
                    .addQueryParameter("mod", "misc")
                    .addQueryParameter("action", "recommend")
                    .addQueryParameter("handlekey", "recommend_add")
                    .addQueryParameter("do", "add")
                    .addQueryParameter("tid", tid)
                    .addQueryParameter("hash", hash)
                    .build()
        return ForumParser.message(
                request(
                    Request.Builder()
                        .url(url)
                        .header("Referer", ref)
                        .header("X-Requested-With", "XMLHttpRequest")
                        .build()
                )
            )
            .ifBlank { "请刷新查看结果" }
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
        return withContext(Dispatchers.Default) { ContentParser.conversations(body, url) }
    }

    suspend fun conversation(uid: String): Conversation {
        require(uid.isNotEmpty() && uid.all(Char::isDigit))
        val (body, url) = html("$BaseUrl/home.php?mod=space&do=pm&subop=view&touid=$uid&mobile=2")
        return withContext(Dispatchers.Default) { ContentParser.conversation(body, url, uid) }
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
