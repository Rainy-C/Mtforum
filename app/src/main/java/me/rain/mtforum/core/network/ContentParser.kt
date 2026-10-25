package me.rain.mtforum.core.network

import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import org.jsoup.Jsoup
import org.jsoup.nodes.Element

object ContentParser {
    private val base = ForumRepository.BaseUrl
    private val tidPattern = Regex("(?:thread-|[?&](?:tid|ptid)=)(\\d+)")
    private val fidPattern = Regex("(?:forum-|[?&]fid=)(\\d+)")
    private val cdata = Regex("<!\\[CDATA\\[([\\s\\S]*?)]]>")

    fun unwrap(body: String) = cdata.find(body)?.groupValues?.get(1) ?: body

    fun clean(text: String): String =
        text.replace(Regex("[\\uE000-\\uF8FF\\uFFFD]"), "").replace(Regex("\\s+"), " ").trim()

    fun absolute(raw: String, page: String = base): String? {
        val decoded = raw.trim().replace("&amp;", "&")
        val value = if (decoded.startsWith("$base/https://")) decoded.removePrefix("$base/") else decoded
        if (value.isBlank() || value.startsWith("#") || value.startsWith("javascript:", true))
            return null
        val url = page.toHttpUrlOrNull()?.resolve(value) ?: return null
        return url.takeIf { it.scheme == "https" && it.username.isEmpty() && it.password.isEmpty() }
            ?.toString()
    }

    fun isMutationUrl(url: String): Boolean {
        val parsed = url.toHttpUrlOrNull() ?: return false
        val op = parsed.queryParameter("op").orEmpty()
        val action = parsed.queryParameter("action").orEmpty()
        return (parsed.queryParameter("formhash") != null &&
            parsed.queryParameter("ac") in setOf("favorite", "friend", "follow")) ||
            (parsed.queryParameter("id") == "comiis_sms" &&
                parsed.queryParameter("comiis_tel") != null) ||
            op in setOf("delete", "ignore", "remove", "del", "sub") ||
            action in setOf("delete", "deleteattach", "logout", "recommend", "block", "unblock") ||
            parsed.queryParameter("operation") == "qiandao" ||
            (parsed.queryParameter("ac") == "follow" && op in setOf("add", "del")) ||
            (parsed.queryParameter("op") == "password" && parsed.queryParameter("resend") == "1")
    }

    internal fun linkTarget(el: Element, page: String): String? {
        absolute(el.attr("href"), page)?.let {
            return it
        }
        val script = el.attr("href") + " " + el.attr("onclick")
        return Regex("""['"]([^'"\r\n]+)['"]""").findAll(script)
            .map { it.groupValues[1] }
            .filter { it.contains(".php?") || it.contains(".html") }
            .mapNotNull { absolute(it, page) }
            .firstOrNull { it.toHttpUrlOrNull()?.host == ForumRepository.Host }
    }

    fun topicId(url: String) = tidPattern.find(url)?.groupValues?.get(1)

    fun forumId(url: String) = fidPattern.find(url)?.groupValues?.get(1)

    private fun Element.image(page: String = base): String? {
        val img = if (tagName() == "img") this else selectFirst("img") ?: return null
        return listOf("zoomfile", "file", "comiis_loadimages", "data-original", "data-src", "data-lazy-src", "src").firstNotNullOfOrNull {
            val raw = img.attr(it).trim()
            if (raw.contains("imageloading.gif") || raw.contains("comiis_loadimg.gif") ||
                raw.endsWith("/none.png") || raw.endsWith("/none.gif")) return@firstNotNullOfOrNull null
            // Old Discuz attachments may still advertise HTTP on an HTTPS page.
            absolute(if (raw.startsWith("http://")) "https://" + raw.removePrefix("http://") else raw, page)
        }
    }

    fun imageUrl(image: Element, page: String = base): String? = image.image(page)

    private val smileyPath =
        Regex("""/static/image/smil(?:ey|ie)s?/|/smil(?:ey|ie)s?/""", RegexOption.IGNORE_CASE)

    /** Forum smileys are inline text, never full-width content images. */
    fun isSmileyImage(image: Element): Boolean {
        if (image.hasAttr("smilieid")) return true
        if (image.classNames().any { it.contains("smilie", ignoreCase = true) }) return true
        return imageSources(image).any { smileyPath.containsMatchIn(it) }
    }

    /** Author avatars ("liked by" strip included) never belong in the post body. */
    fun isAvatarImage(image: Element): Boolean {
        if (image.classNames().any { it.equals("top_tximg", ignoreCase = true) }) return true
        return imageSources(image).any {
            it.contains("/avatar/") || it.contains("noavatar", ignoreCase = true)
        }
    }

    fun smileyUrls(node: Element): List<String> =
        node.select("img")
            .filter { isSmileyImage(it) }
            .mapNotNull { imageUrl(it) }
            .distinct()

    private fun imageSources(image: Element): List<String> =
        listOf("src", "file", "zoomfile", "comiis_loadimages", "data-original", "data-src", "data-lazy-src")
            .map { image.attr(it).trim() }
            .filter { it.isNotEmpty() }

    /** Removes template chrome that lives inside the message container in Comiis. */
    private fun Element.stripMessageChrome() {
        select(
                "script, style, .comiis_rate, .comiis_tags, .comiis_dzhan_img, .comiis_manage, " +
                    ".comiis_postli_times, .comiis_recommend_list_a, .pstatus, .attach_nopermission"
            )
            .remove()
        select("img").filter { isAvatarImage(it) }.forEach { it.remove() }
        // Guest view replaces attachments with a "log in to view" promo block.
        select(".comiis_noatt_ico").forEach { it.parent()?.remove() }
    }

    private fun next(doc: Element, page: String) =
        doc.select("a.nxt, a.next, a[rel=next], .pg a, .pgs a, .comiis_page a")
            .firstOrNull {
                it.hasClass("nxt") ||
                    it.hasClass("next") ||
                    it.attr("rel") == "next" ||
                    it.text().contains("下一页")
            }
            ?.let { absolute(it.attr("href"), page) }

    private fun previous(doc: Element, page: String) =
        doc.select("a.prev, a.pre, .pg a, .pgs a, .comiis_page a")
            .firstOrNull { it.hasClass("prev") || it.hasClass("pre") || it.text().contains("上一页") }
            ?.let { absolute(it.attr("href"), page) }

    fun topics(body: String, page: String): Pair<List<Topic>, String?> {
        val doc = Jsoup.parse(unwrap(body), page)
        var rows =
            doc.select(
                "li.forumlist_li, tbody[id^=normalthread], .threadlist li, .tl tbody, .comiis_mh_twlist li"
            )
        if (rows.isEmpty())
            rows =
                org.jsoup.select.Elements(
                    doc.select("a[href]")
                        .filter { topicId(it.attr("href")) != null }
                        .map { it.closest("li, tr, article") ?: it.parent() ?: it }
                        .distinct()
                )
        val items =
            rows
                .mapNotNull { row ->
                    val a =
                        row.select("h2 a[href], .list_body a[href], a.s.xst, a.xst, a[href]")
                            .firstOrNull {
                                topicId(it.attr("href")) != null && clean(it.text()).isNotBlank()
                            } ?: return@mapNotNull null
                    val id = topicId(a.attr("href")) ?: return@mapNotNull null
                    val metadata = TopicListMetadata.parse(row, id, page)
                    Topic(
                        id,
                        clean(a.text()),
                        absolute(a.attr("href"), page) ?: "$base/thread-$id-1-1.html",
                        metadata.author,
                        metadata.authorUrl,
                        metadata.avatar,
                        clean(row.selectFirst("a[href*=forum-]")?.text().orEmpty())
                            .removePrefix("来自")
                            .trim(),
                        clean(
                            row.selectFirst(".forumlist_li_time, .by em")
                                ?.text()
                                .orEmpty()
                        ),
                        clean(row.selectFirst(".list_body, .comiis_list_summary")?.text().orEmpty())
                            .take(200),
                        metadata.replies,
                        metadata.views,
                        metadata.likes,
                        row.select(
                                ".comiis_pyqlist_img img, .comiis_pyqlist_imgs img, .list_img img, .comiis_list_img img, .comiis_xznalist_img img, .comiis_znalist_img img, img[file], img[data-original]"
                            )
                            .mapNotNull { it.image(page) }
                            .distinct()
                            .take(3),
                        hasImageAttachments = row.selectFirst("img[alt=attach_img], img[title=图片附件]") != null,
                        hasHiddenContent = metadata.hidden,
                    )
                }
                .distinctBy { it.id }
        return items to next(doc, page)
    }

    val defaultBoards =
        listOf(
            ForumBoard("2", "版本发布", "MT 专区"),
            ForumBoard("37", "插件交流", "MT 专区"),
            ForumBoard("38", "建议反馈", "MT 专区"),
            ForumBoard("41", "逆向交流", "交流与讨论"),
            ForumBoard("39", "玩机交流", "交流与讨论"),
            ForumBoard("42", "编程开发", "交流与讨论"),
            ForumBoard("40", "求助问答", "交流与讨论"),
            ForumBoard("44", "综合交流", "交流与讨论"),
            ForumBoard("50", "休闲灌水", "交流与讨论"),
            ForumBoard("46", "官方公告", "论坛事务"),
            ForumBoard("53", "申诉举报", "论坛事务"),
        )

    fun boards(body: String): List<ForumBoard> {
        val doc = Jsoup.parse(body)
        val result =
            doc.select("a[href]")
                .mapNotNull { a ->
                    val id = forumId(a.attr("href")) ?: return@mapNotNull null
                    val raw = clean(a.text())
                    val chosen = clean(a.selectFirst("h2, h3, .tit")?.text() ?: a.ownText())
                        .ifBlank { raw }
                    // The Comiis forum index prefixes board titles with today's post count.
                    // Keep it as a separate statistic rather than part of the board name.
                    val countPrefix = Regex("""^(\d{1,8})\s+(.+)$""")
                    val prefixed = countPrefix.matchEntire(raw)
                        ?: countPrefix.matchEntire(chosen)
                    val todayPosts = prefixed?.groupValues?.get(1)
                    val title = (countPrefix.matchEntire(chosen)?.groupValues?.get(2)
                        ?: (if (chosen == raw || chosen == todayPosts) prefixed?.groupValues?.get(2) else null)
                        ?: chosen).trim()
                    if (title.isBlank() || title.length > 32 || title.contains("下一页"))
                        return@mapNotNull null
                    val known = defaultBoards.firstOrNull { it.id == id }
                    ForumBoard(id, title, known?.group ?: "更多板块", known?.summary.orEmpty(), todayPosts)
                }
                .distinctBy { it.id }
        return if (result.isEmpty()) defaultBoards else result
    }

    fun detail(body: String, page: String): TopicDetail {
        val html = unwrap(body)
        val doc = Jsoup.parse(html, page)
        val starts =
            Regex("<[^>]+\\bid\\s*=\\s*['\"](?:pid|post_)(\\d+)['\"][^>]*>", RegexOption.IGNORE_CASE)
                .findAll(html)
                .toList()
                .distinctBy { it.groupValues[1] }
                .ifEmpty {
                    Regex("<[^>]+\\bid\\s*=\\s*['\"]postmessage_(\\d+)['\"][^>]*>", RegexOption.IGNORE_CASE)
                        .findAll(html).toList()
                }
        val posts =
            starts.mapIndexed { i, start ->
                val fragment =
                    Jsoup.parse(
                        "<table><tbody><tr><td>" + html.substring(
                            start.range.first,
                            starts.getOrNull(i + 1)?.range?.first ?: html.length,
                        ) + "</td></tr></tbody></table>",
                        page,
                    )
                val author = fragment.selectFirst(".top_user, .authi a, .pi .authi a, .comiis_post_username a, .comiis_vty a[href*=uid=]")
                // The Comiis template wraps the body in `.comiis_messages`, which holds the text
                // table *and* the sibling `ul.comiis_img_list` with attachment images. The outer
                // `.comiis_message` also carries the rate button, tags and the "liked by" strip,
                // so the chain must stop at `.comiis_messages`.
                val source =
                    fragment.selectFirst("[id^=postmessage_]")
                        ?: fragment.selectFirst(".comiis_messages")
                        ?: fragment.selectFirst(".comiis_a.comiis_message_table")
                        ?: fragment.selectFirst(".comiis_message_table")
                        ?: fragment.selectFirst(".t_f")
                        ?: fragment.selectFirst(".message")
                val message = source?.clone()?.apply { stripMessageChrome() }
                // Some template variants put the attachment gallery next to the message
                // wrapper instead of inside it; recover it when the body carries no image.
                if (message != null && message.selectFirst("img") == null) {
                    fragment.selectFirst(".comiis_img_list, .comiis_aimg, .pattl")?.clone()?.let { gallery ->
                        gallery.select("img")
                            .filter { isAvatarImage(it) || isSmileyImage(it) }
                            .forEach { it.remove() }
                        if (gallery.selectFirst("img") != null) message.appendChild(gallery)
                    }
                }
                val messageHtml = message?.html().orEmpty()
                ContentPost(
                    start.groupValues[1],
                    clean(author?.text().orEmpty()).ifBlank { "论坛成员" },
                    author?.let { absolute(it.attr("href"), page) },
                    fragment.selectFirst("img.top_tximg, .top_tximg img, .avatar img, .avt img")?.image(page),
                    clean(
                        fragment
                            .selectFirst(
                                ".comiis_postli_time .kmtime, .comiis_postli_times .comiis_tm, " +
                                    ".forumlist_li_time, .authi em, .comiis_posttime"
                            )
                            ?.text()
                            .orEmpty()
                    ),
                    clean(fragment.selectFirst(".f_d.y, .pi strong")?.text().orEmpty()).ifBlank {
                        "${i + 1} 楼"
                    },
                    messageHtml,
                    fragment
                        .select(
                            "[id^=postmessage_] img, .comiis_message_table img, .comiis_message img, .t_f img, .comiis_img_list img, .comiis_aimg img"
                        )
                        .filterNot { isSmileyImage(it) || isAvatarImage(it) }
                        .mapNotNull { it.image(page) }
                        .distinct(),
                    (message?.select("a[href]").orEmpty() +
                            fragment.select(
                                "a[href*=mod=attachment], a[href*=attachment.php], a[href*=aid=]"
                            ))
                        .mapNotNull { a ->
                            absolute(a.attr("href"), page)?.let {
                                ContentLink(clean(a.text()).ifBlank { "打开链接" }, it)
                            }
                        }
                        .distinctBy { it.url },
                )
            }
        return TopicDetail(
            clean(
                doc.selectFirst(".comiis_thread_title, .comiis_viewtit, #thread_subject")?.text()
                    ?: doc.title().substringBefore(" - MT论坛").substringBefore(" - MT论坛")
            ),
            topicId(page).orEmpty(),
            Regex("forum-viewforum-fid-(\\d+)").find(html)?.groupValues?.get(1)
                ?: doc.select("a[href]")
                    .firstNotNullOfOrNull { forumId(it.attr("href")) }
                    .orEmpty(),
            posts,
            next(doc, page),
            previous(doc, page),
            ForumParser.formhash(html),
        )
    }

    private val labels =
        mapOf(
            "subject" to "标题",
            "message" to "内容",
            "username" to "用户名",
            "password" to "密码",
            "oldpassword" to "当前密码",
            "newpassword" to "新密码",
            "newpassword2" to "确认新密码",
            "email" to "邮箱",
            "realname" to "真实姓名",
            "gender" to "性别",
            "birthyear" to "出生年份",
            "birthmonth" to "出生月份",
            "birthday" to "出生日期",
            "resideprovince" to "居住省份",
            "residecity" to "居住城市",
            "occupation" to "职业",
            "qq" to "QQ",
            "mobile" to "手机号码",
            "sightml" to "个性签名",
            "bio" to "自我介绍",
            "answer" to "答案",
            "questionid" to "安全提问",
            "seccodeverify" to "验证码",
            "emailnew" to "邮箱",
            "secmobilenew" to "手机号码",
            "secmobiccnew" to "国家或地区代码",
            "questionidnew" to "新的安全提问",
            "answernew" to "安全提问答案",
            "newname" to "新用户名",
            "typeid" to "帖子分类",
            "usesig" to "使用个人签名",
            "allownoticeauthor" to "接收回复通知",
            "comiis_tel" to "手机号码",
            "code" to "验证码",
            "addr" to "收货信息",
            "srchtxt" to "搜索帖子",
            "reason" to "申请理由",
            "amount" to "数量",
            "credits" to "积分",
            "touid" to "对方 UID",
        )

    private fun fieldLabel(el: Element, form: Element): String {
        val key = el.attr("name")
        if (key.startsWith("privacy[")) return "可见范围"
        val explicit =
            form
                .select("label[for]")
                .firstOrNull { it.attr("for") == el.id() && el.id().isNotEmpty() }
                ?.text()
        val optionLabel = if (el.attr("type").lowercase() in setOf("radio", "checkbox"))
            (el.nextSibling() as? org.jsoup.nodes.TextNode)?.text()?.let(::clean)?.takeIf(String::isNotBlank)
            else null
        val adjacent =
            el.closest("label")?.text()
                ?: el.closest("tr")?.selectFirst("th")?.text()
                ?: el.closest("li, .comiis_input_style, .comiis_inputbox")
                    ?.selectFirst(
                        "label, .tit, .name, h2, .comiis_styli_tit, .comiis_styli_title, .comiis_input_tit"
                    )
                    ?.text()
        return clean(
                explicit
                    ?: optionLabel
                    ?: labels[key]
                    ?: adjacent
                    ?: el.attr("placeholder").ifBlank { el.attr("title") }
            )
            .take(60)
            .ifBlank { if (key.startsWith("privacy[")) "可见范围" else "填写内容" }
    }

    fun document(body: String, page: String, fallbackTitle: String = ""): NativeDocument =
        try {
            parseDocument(body, page, fallbackTitle)
        } catch (error: Exception) {
            // Surface the failure through the existing retry UI. Dumping body.text()
            // hides parser bugs and turns menus, editors and private data into one card.
            throw ForumException(
                "页面解析失败（${error.javaClass.simpleName}）：" +
                    error.message.orEmpty().take(180)
            )
        }

    private fun parseDocument(body: String, page: String, fallbackTitle: String = ""): NativeDocument {
        val html = unwrap(body)
        val doc = Jsoup.parse(html, page)
        val documentTitle = clean(doc.title().substringBefore(" - MT"))
        val pageHash = ForumParser.formhash(html)
        val uploadBlock =
            Regex("""uploadformdata\s*:\s*\{([^}]*)\}""", RegexOption.IGNORE_CASE)
                .find(html)
                ?.groupValues
                ?.get(1)
                .orEmpty()
        val uploadUid =
            Regex("""["']?uid["']?\s*:\s*["']?(\d+)""").find(uploadBlock)?.groupValues?.get(1)
        val uploadHash =
            Regex("""["']?hash["']?\s*:\s*["']([a-fA-F0-9]+)["']""")
                .find(uploadBlock)
                ?.groupValues
                ?.get(1)
        val maxBytes =
            (Regex("""maxfilesize\s*[:=]\s*["']?(\d+)""")
                .find(html)
                ?.groupValues
                ?.get(1)
                ?.toIntOrNull() ?: 1024) * 1024
        val upload =
            if (uploadUid != null && uploadHash != null)
                UploadConfig(uploadUid, uploadHash, maxBytes.coerceIn(1024, 20 * 1024 * 1024))
            else null
        doc.select(
                "script, style, noscript, iframe, head, header, footer, nav, " +
                    ".comiis_footer, #comiis_foot_menu, #comiis_foot_box, .comiis_fmenu, " +
                    "#comiis_head, .comiis_head, .comiis_header, " +
                    ".comiis_sidenv, .comiis_sidenv_box, .comiis_leftmenubg, " +
                    ".comiis_loadings, .comiis_gobtn, #comiis_bgbox, #mask, #comiis_menu_bg, " +
                    "#comiis_alert, #comiis_wx_title_box, #comiis_wx_description_box, " +
                    "#nv, #ft, #hd"
            )
            .remove()
        doc.select("form[id]").forEach { form ->
            val externalControls = doc.select("input[form], textarea[form], select[form], button[form]")
                .filter { it.attr("form") == form.id() && !form.containsControl(it) }
            externalControls.forEach { form.appendChild(it.clone()) }
        }
        RemoteFormContracts.recover(doc, page, pageHash)
        val adaptation = NativePageAdapters.parse(doc, page)
        val forms =
            doc.select("form").mapIndexedNotNull { index, form ->
                val url = absolute(form.attr("action"), page) ?: page
                if (url.toHttpUrlOrNull()?.host != ForumRepository.Host)
                    return@mapIndexedNotNull null
                val fields =
                    form
                        .select("input[name], textarea[name], select[name]")
                        .filterNot {
                            it.hasAttr("disabled") ||
                                it.attr("type").lowercase() in listOf("button", "submit", "reset", "image")
                        }
                        .map { el ->
                            val type =
                                when (el.tagName()) {
                                    "textarea" -> "textarea"
                                    "select" -> "select"
                                    else -> el.attr("type").lowercase().ifBlank { "text" }
                                }
                            val opts =
                                if (type == "select")
                                    el.select("option").filterNot { it.hasAttr("disabled") }.map {
                                        FieldOption(clean(it.text()), if (it.hasAttr("value")) it.attr("value") else it.text())
                                    }
                                else emptyList()
                            val value =
                                when (type) {
                                    "textarea" -> el.wholeText()
                                    "select" ->
                                        el.select("option").firstOrNull { it.hasAttr("selected") && !it.hasAttr("disabled") }
                                            ?.let { if (it.hasAttr("value")) it.attr("value") else it.text() }
                                            ?: opts.firstOrNull()?.value.orEmpty()
                                    "checkbox", "radio" -> el.attr("value").ifBlank { "on" }
                                    else -> el.attr("value")
                                }
                            RemoteField(
                                el.attr("name"),
                                fieldLabel(el, form),
                                type,
                                value,
                                el.hasAttr("required"),
                                el.hasAttr("checked"),
                                opts,
                                el.attr("maxlength").toIntOrNull()?.coerceAtLeast(0),
                                el.hasAttr("readonly"),
                            )
                        }
                if (
                    fields.none { it.type != "hidden" } &&
                        form.select("button, input[type=submit]").isEmpty()
                )
                    return@mapIndexedNotNull null
                val submits =
                    form
                        .select("button, input[type=submit], input[type=image]")
                        .filterNot { it.hasAttr("disabled") || it.attr("type").lowercase() in setOf("button", "reset") }
                        .map { el ->
                            RemoteSubmit(
                                clean(el.text().ifBlank { el.attr("value") }).ifBlank { "保存" },
                                el.attr("name"),
                                el.attr("value"),
                                el.attr("formaction").takeIf(String::isNotBlank)?.let { absolute(it, page) },
                                el.attr("formmethod").uppercase().takeIf { it == "GET" || it == "POST" },
                            )
                        }
                        .distinctBy { listOf(it.name, it.value, it.url, it.method, it.label) }
                        .ifEmpty {
                            listOf(
                                RemoteSubmit(
                                    if (fields.any { it.key == "message" }) "发送" else "保存",
                                    "",
                                    "",
                                )
                            )
                        }
                RemoteFormContracts.complete(RemoteForm(
                    form.id().ifBlank { "form" } + "-$index",
                    url,
                    form.attr("method").uppercase().ifBlank { "GET" },
                    form.attr("enctype").contains("multipart"),
                    fields,
                    submits,
                    if (fields.any { it.key == "message" }) upload else null,
                    form.select("img[id*=seccode], img[src*=seccode]").mapNotNull { it.image(page) },
                    page,
                ), pageHash)
            }.let { parsed ->
                if (parsed.isNotEmpty()) parsed
                else listOfNotNull(RemoteFormContracts.mallConfirmation(doc, page))
            }
        // Forms can wrap favorites, credit logs and user-group tables. Keep their
        // read-only rows after extracting the actual controls for native editing.
        doc.select("form").forEach { form ->
            form.select("input, textarea, select, button").remove()
            form.unwrap()
        }
        val root =
            doc.selectFirst(".comiis_bodybox")
                ?: doc.selectFirst("#ct")
                ?: doc.selectFirst("#wp")
                ?: doc.selectFirst(".comiis_body")
                ?: doc.selectFirst("#comiis_body")
                ?: doc.selectFirst("main")
                ?: doc.body()
        val rows =
            root
                .select(
                    "li, article, dl.bbda, tbody[id^=autolist_], .comiis_notice_list, .comiis_friend_msg, .comiis_pmlist, .comiis_pmslist, .comiis_quote, tr, .comiis_space_profile, .comiis_tip, .alert_info, .alert_error, .alert_right"
                )
                .filter { e ->
                    e.parents().none { p ->
                        p != root && p.tagName() in listOf("li", "article", "tr", "dl")
                    } &&
                        !hasRowDescendant(e) &&
                        e.parents().none { p -> p.id() == "comiis_sub" || p.hasClass("comiis_topnv") } &&
                        !e.hasClass("swiper-slide")
                }
        val tabs = root.selectFirst("#comiis_sub, .comiis_topnv")?.let { block(it, page) }
        val rowBlocks = rows.mapNotNull { rowBlock(it, page) }
        val loose =
            root.select("h2, h3")
                .filter { el ->
                    el.parents().none { it.tagName() == "li" } &&
                        el.text().isNotBlank() &&
                        rowBlocks.none { it.text.contains(clean(el.text())) }
                }
                .mapNotNull { block(it, page) }
                .take(4)
        val blocks = if (adaptation != null) adaptation.blocks else buildList {
            tabs?.let { add(it.copy(text = "")) }
            // Account editors must not duplicate every field label in a second card.
            if (forms.isEmpty()) {
                addAll(rowBlocks)
                addAll(loose)
                if (isEmpty()) addAll(readableBlocks(root, page))
            } else {
                root.select("#messagetext, .alert_error, .alert_info, .comiis_tip")
                    .mapNotNull { block(it, page) }.forEach { add(it) }
            }
        }
        return NativeDocument(
            fallbackTitle.ifBlank { documentTitle },
            page,
            blocks.distinctBy { it.text to it.links }.take(160),
            forms,
            next(doc, page),
            previous(doc, page),
            ForumParser.formhash(html),
            adaptation?.signedToday,
        )
    }

    private fun Element.containsControl(control: Element): Boolean =
        control.parents().any { it === this }

    /** Descend layout wrappers instead of flattening the entire document. */
    private fun readableBlocks(root: Element, page: String): List<ContentBlock> {
        val result = mutableListOf<ContentBlock>()
        fun visit(node: Element, depth: Int) {
            if (depth > 16 || result.size >= 160) return
            if (node.tagName() in setOf("script", "style", "form", "input", "button")) return
            if (node.hasAttr("hidden") ||
                Regex("display\\s*:\\s*none", RegexOption.IGNORE_CASE)
                    .containsMatchIn(node.attr("style"))) return
            val meaningful = node.children().filter {
                it.tagName() !in setOf("script", "style", "input", "button", "br")
            }
            val leaf = node.tagName() in setOf("p", "h1", "h2", "h3", "h4", "li", "tr", "dl")
            if (leaf || meaningful.isEmpty()) {
                block(node, page)?.let(result::add)
                return
            }
            val own = clean(node.ownText())
            if (own.isNotBlank()) result += ContentBlock(own)
            meaningful.forEach { visit(it, depth + 1) }
        }
        root.children().forEach { visit(it, 0) }
        return result
    }

    /** True when the element only wraps other rows (e.g. a list container). */
    private fun hasRowDescendant(el: Element): Boolean =
        el.children().any { child ->
            child.tagName() in setOf("li", "tr", "article") ||
                child.selectFirst("li, tr, article") != null
        }

    /** Structured row for Comiis list pages (friends, followers, notices, medals...). */
    private fun rowBlock(el: Element, page: String): ContentBlock? {
        val titleEl =
            el.selectFirst("p.tit a, .tit a, h2 a, h3 a, h4 a, .mall-info h4, " +
                    "a.postphb_tit, dt:not(.y) a, .ntc_body a[href], a.top_user")
        val title = clean(titleEl?.text().orEmpty()).take(80)
        val bodyEl =
            el.selectFirst("p.txt, .txt, .ntc_body, .comiis_pm_txt, .summary, .comiis_tip")
        val body = clean(bodyEl?.text().orEmpty()).ifBlank { clean(el.text()) }
        val text =
            when {
                title.isBlank() -> body
                body.isBlank() -> title
                body.contains(title) -> body
                else -> "$title · $body"
            }
        val image =
            el.selectFirst(
                    "a.list01_limg img, .list01_limg img, .comiis_notice_list img, " +
                        "img[src*=avatar], img[src*=uc_server], img"
                )
                ?.image(page)
        val links =
            el.select("a[href], a[onclick]")
                .mapNotNull { a ->
                    val url = linkTarget(a, page) ?: return@mapNotNull null
                    ContentLink(actionLabel(a), url)
                }
                .distinctBy { it.url }
                .take(10)
        if (text.isBlank() && links.isEmpty() && image == null) return null
        return ContentBlock(text, title, image, links)
    }

    private fun actionLabel(anchor: Element): String {
        val text = clean(anchor.text())
        if (text.isNotEmpty()) return text
        val id = anchor.id()
        return when {
            anchor.hasClass("kmdel") || id.startsWith("a_ignore") -> "删除好友"
            id.startsWith("a_sendpm") -> "发消息"
            id.startsWith("a_poke") -> "打招呼"
            anchor.hasClass("dialog") -> "设置"
            else -> clean(anchor.attr("title")).ifBlank { "查看" }
        }
    }

    private fun block(el: Element, page: String): ContentBlock? {
        val text = clean(el.text())
        val links =
            el.select("a[href], a[onclick]")
                .mapNotNull { a ->
                    linkTarget(a, page)?.let {
                        ContentLink(
                            clean(a.text()).ifBlank { a.attr("title") }.ifBlank { "查看" },
                            it,
                        )
                    }
                }
                .distinctBy { it.url }
                .take(24)
        val img = el.selectFirst("img")?.image(page)
        if (text.isBlank() && links.isEmpty() && img == null) return null
        return ContentBlock(
            text,
            clean(el.selectFirst("h2, h3, h4, strong")?.text().orEmpty()).take(80),
            img,
            links,
        )
    }

    fun conversations(body: String, page: String): List<ConversationSummary> {
        val doc = Jsoup.parse(unwrap(body), page)
        return doc.select("a[href*=do=pm][href*=subop=view][href*=touid=]")
            .mapNotNull { link ->
                val uid =
                    Regex("""[?&]touid=(\d+)""").find(link.attr("href"))?.groupValues?.get(1)
                        ?: return@mapNotNull null
                val row =
                    link.closest("li, .comiis_pmlist, .comiis_friend_msg") ?: link.parent() ?: link
                val time = clean(row.selectFirst(".msg_time, time, .f_d")?.text().orEmpty())
                val summary =
                    clean(
                        row.selectFirst(".msg_mes, .summary, .comiis_pm_txt, p")?.text().orEmpty()
                    )
                val name =
                    clean(
                            row.selectFirst(".username, .comiis_pm_user, h2, h3, h4, strong")
                                ?.text()
                                .orEmpty()
                        )
                        .replace(time, "")
                        .replace(summary, "")
                        .trim()
                        .ifBlank { clean(link.text()).take(30) }
                        .ifBlank { "论坛成员" }
                ConversationSummary(
                    uid,
                    name,
                    row.image(page),
                    summary,
                    time,
                    row.selectFirst("span.kmnums") != null,
                )
            }
            .distinctBy { it.uid }
    }

    fun conversation(body: String, page: String, peer: String): Conversation {
        val html = unwrap(body)
        val doc = Jsoup.parse(html, page)
        val ownUid = Regex("""discuz_uid\s*=\s*['"]?(\d+)""").find(html)?.groupValues?.get(1)
        val messages =
            doc.select(".msg_mes")
                .map { node ->
                    var row = node
                    repeat(8) {
                        if (
                            row.parent() != null &&
                                row.parent()!!.select(".msg_mes").size == 1 &&
                                !row.hasClass("comiis_friend_msg") &&
                                !row.hasClass("comiis_my_msg")
                        )
                            row = row.parent()!!
                    }
                    val sender =
                        row.select("a[href*=uid=]").firstNotNullOfOrNull {
                            Regex("""[?&]uid=(\d+)""").find(it.attr("href"))?.groupValues?.get(1)
                        }
                    val peerMarked =
                        sender == peer ||
                            row.selectFirst(".dialog_white.z, .dialog_green.z") != null
                    val mine =
                        !peerMarked &&
                            (sender != null && sender == ownUid ||
                                row.classNames().any {
                                    it.contains("my_msg") ||
                                        it.contains("self") ||
                                        it.contains("msg_right")
                                } ||
                                node.parent()?.hasClass("y") == true ||
                                row.selectFirst(
                                    ".dialog_blue.y, .dialog_green.y, .comiis_msg_right"
                                ) != null)
                    val bb =
                        Regex(
                            """\[img(?:=[^]]+)?]\s*([^\[\]\r\n]+?)\s*\[/img]""",
                            RegexOption.IGNORE_CASE,
                        )
                    val text = node.wholeText()
                    val images =
                        node.select("img").mapNotNull { it.image(page) } +
                            bb.findAll(text)
                                .mapNotNull { absolute(it.groupValues[1], page) }
                                .toList()
                    ChatMessage(
                        bb.replace(text, "").trim(),
                        clean(row.selectFirst(".msg_time")?.text().orEmpty()),
                        mine,
                        images.distinct(),
                    )
                }
                .distinct()
        val form = doc.selectFirst("#pmform")
        val pmid =
            Regex("""[?&]pmid=(\d+)""").find(form?.attr("action").orEmpty())?.groupValues?.get(1)
                ?: "0"
        val name =
            clean(doc.selectFirst(".comiis_pm_tit, .comiis_pm_user, h2.flex")?.text().orEmpty())
        return Conversation(peer, name, pmid, ForumParser.formhash(html).orEmpty(), messages)
    }
}
