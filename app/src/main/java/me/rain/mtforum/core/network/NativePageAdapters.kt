package me.rain.mtforum.core.network

import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import org.jsoup.nodes.Element

/** Discuz desktop and Comiis mobile page contracts, shared by all native account pages. */
internal object NativePageAdapters {
    data class Result(val blocks: List<ContentBlock>, val signedToday: Boolean? = null)

    fun parse(doc: Element, page: String): Result? {
        val url = page.toHttpUrlOrNull() ?: return null
        val action = url.queryParameter("do")
        val ac = url.queryParameter("ac")
        val plugin = url.queryParameter("id").orEmpty()
        val sign = url.encodedPath.contains("k_misign") || plugin.startsWith("k_misign")
        val mall = url.encodedPath.contains("keke_integralmall") || plugin.startsWith("keke_integralmall")
        val creditHistory = ac == "credit" && url.queryParameter("op") in setOf("log", "loglist", "record")
        val selector = when {
            sign && url.queryParameter("operation") == "list" -> "tbody[id^=autolist_]"
            sign -> return signPage(doc, page)
            mall && (ac == "km" || ac == "buylist") -> "#buylist > li, #buylist > div, .kmdis .kmlist p"
            mall -> "li.col-xs-12.bg_f"
            (url.encodedPath.contains("ranklist") || url.queryParameter("mod") == "ranklist") ->
                ".comiis_rankhot li, .comiis_ranklist_box li, .comiis_ranklist li, " +
                    ".comiis_rank_list li, .comiis_postphb li, dl.bbda, table tr"
            action == "favorite" -> "li.mysclist_li, li[id^=fav_]"
            action == "notice" -> ".comiis_notice_list li, dl[id^=notice_], li:has(.ntc_body)"
            action == "thread" -> "li.forumlist_li, .threadlist li, .tl tbody[id], table.dt tr, .tl tr"
            action == "friend" || url.queryParameter("mod") == "follow" || ac == "friend" ->
                ".comiis_userlist01 > li, .comiis_followlist > li, li[id^=friend_], " +
                    "ul.buddy > li, li.b_t:has(.tit a), #ct li.cl:has(h6), " +
                    "li[id^=comiis_friendbox_]"
            creditHistory -> "ul.creditl li, .comiis_space_jf li, .comiis_creditlist li, " +
                ".creditlog li, .comiis_jflist li, table.dt tr, .creditlog table tr"
            ac == "credit" -> "ul.creditl li, .comiis_space_profilejf li, .comiis_space_jf li, table.dt tr"
            ac == "usergroup" -> ".comiis_levhead, .comiis_usergroup li, .comiis_group_list li, table.dt tr"
            ac == "promotion" -> ".comiis_tg_kmtit, .comiis_tg_kmtxt, .comiis_tg_box_tip"
            else -> return null
        }
        val selectedRows = doc.select(selector).toSet()
        val rows = selectedRows.filter { row ->
            // Ignore table headings and wrappers around other selected rows.
            (row.tagName() != "tr" || row.selectFirst("td") != null) &&
                row.parents().none { parent -> parent in selectedRows }
        }
        val kind = when {
            sign || url.encodedPath.contains("ranklist") || url.queryParameter("mod") == "ranklist" -> NativeContentKind.Rank
            mall -> NativeContentKind.Product
            action == "notice" -> NativeContentKind.Notice
            action == "thread" || action == "favorite" -> NativeContentKind.Thread
            action == "friend" || url.queryParameter("mod") == "follow" || ac == "friend" -> NativeContentKind.Person
            creditHistory -> NativeContentKind.CreditRecord
            ac == "credit" -> NativeContentKind.Facts
            ac == "usergroup" -> NativeContentKind.UserGroup
            else -> NativeContentKind.Text
        }
        val blocks = rows.mapIndexedNotNull { index, element ->
            row(element, page, kind, if (kind == NativeContentKind.Rank) index + 1 else null)?.let { block ->
                if (kind == NativeContentKind.Rank) block.copy(rank = block.rank ?: index + 1)
                else block
            }
        }.distinctBy { it.primaryLink?.url ?: "${it.rank}|${it.title}|${it.text}" }
        if (mall && blocks.isEmpty()) {
            // Product detail and order confirmation are not list templates.
            val details = doc.select(".item-info, .mall-pro-main, .item-btn, #buylist, .kmdis")
                .mapNotNull { row(it, page) }
            return if (details.isEmpty()) null else Result(navigation(doc, page) + details)
        }
        if (blocks.isEmpty()) {
            // Keep the site's explicit empty/permission messages. Do not flatten its menus.
            val message = doc.selectFirst("#messagetext, .alert_info, .alert_error, .nfl h2, .emp")
                ?.let { row(it, page) }
            return if (message != null) Result(navigation(doc, page) + message) else null
        }
        return Result(navigation(doc, page) + blocks)
    }

    private fun navigation(doc: Element, page: String): List<ContentBlock> {
        val links = doc.select("#comiis_sub a, .comiis_topnv a, .tb a, .subtb a, .comiis_ranknav a")
            .mapNotNull { link(it, page) }.distinctBy { it.url }.toMutableList()
        val url = page.toHttpUrlOrNull()
        if (url?.queryParameter("do") == "friend" && url.queryParameter("uid") == null) {
            listOf(
                "我的好友" to "mod=space&do=friend",
                "我的关注" to "mod=follow&do=following",
                "我的粉丝" to "mod=follow&do=follower",
                "好友申请" to "mod=spacecp&ac=friend&op=request",
            ).forEach { (title, query) ->
                val target = "${ForumRepository.BaseUrl}/home.php?$query&mobile=2"
                if (links.none { it.text == title }) links += ContentLink(title, target)
            }
        }
        return if (links.isEmpty()) emptyList() else listOf(ContentBlock("", links = links, kind = NativeContentKind.Navigation))
    }

    // Rankings often embed points, the placement and username in the same HTML element.
    private val rankMetric = Regex("""(?<!\d)([\d,]{1,12})\s*(积分|发帖|帖子|主题|回复|粉丝|金币|热度|活跃度|经验|贡献|人气)""")
    private val onlineDuration = Regex("""在线(?:时长)?\s*[:：]?\s*([\d,]{1,12})\s*(分钟|分|小时|秒|天)""")

    private fun rankName(raw: String, rank: Int?): String {
        var name = ContentParser.clean(raw).replace(rankMetric, "").replace(onlineDuration, "").trim()
        // Some Comiis rows place the score BEFORE "4 Username".
        if (rank != null) name = name.replace(Regex("""^${rank}\s*[.、:]?\s+"""), "")
        return name.trim(' ', '·', '-', '|')
    }

    private fun row(
        original: Element,
        page: String,
        kind: NativeContentKind = NativeContentKind.Text,
        fallbackRank: Int? = null,
    ): ContentBlock? {
        val node = original.clone()
        node.select("script, style, input, select, textarea, button, dt.y").remove()
        val titleNode = listOf(
            ".mall-info h4", "a.postphb_tit", "h6 a.xi2", "p.tit a", ".tit a",
            "h2 a", "h3 a", "h4 a[href*=space-uid-]", "h4 a", "dt:not(.y) a", "a.top_user",
        ).firstNotNullOfOrNull { node.selectFirst(it) }
        val threadTitle = node.select("a[href]").firstOrNull { a ->
            val href = a.attr("href")
            (href.contains("thread-") || href.contains("mod=viewthread")) && a.text().isNotBlank()
        }
        val displayTitle = if (kind == NativeContentKind.Thread) threadTitle ?: titleNode else titleNode ?: threadTitle
        val rank = node.selectFirst(".ranknum img, .postphb_mun img, em img")
            ?.attr("alt")?.toIntOrNull()
            ?: node.selectFirst(".ranknum, .postphb_mun")?.text()?.trim()?.toIntOrNull()
            ?: fallbackRank
        val metric = if (kind == NativeContentKind.Rank) rankMetric.find(node.text()) else null
        val duration = if (kind == NativeContentKind.Rank) onlineDuration.find(node.text()) else null
        val profileAnchor = if (kind == NativeContentKind.Rank) node.select("a[href]").firstOrNull {
            val link = ContentParser.linkTarget(it, page).orEmpty()
            it.text().isNotBlank() && (link.contains("space-uid-") ||
                (link.contains("mod=space") && link.contains("uid=")))
        } else null
        val rawTitle = cleanAccountText(ContentParser.clean((profileAnchor ?: displayTitle)?.text().orEmpty()))
        val title = if (kind == NativeContentKind.Rank) rankName(rawTitle, rank) else rawTitle
        // Preserve paragraph boundaries in notices, logs and account detail rows.
        node.select("br").forEach { it.after("\n") }
        val text = node.wholeText().lines().map { cleanAccountText(ContentParser.clean(it)) }
            .filter(String::isNotBlank).joinToString("\n")
            .ifBlank { cleanAccountText(ContentParser.clean(node.text())) }

        val links = node.select("a[href], a[onclick]").mapNotNull { link(it, page) }
            .distinctBy { it.url }.take(24)
        val imageSelector = if (kind == NativeContentKind.Product)
            ".mall-pic img, .mall-img img, .item-img img, .listpic img, " +
                ".mall-info img, img[comiis_loadimages], img[src*=keke_integralmall]"
        else ".listpic img, .list01_limg img, .avt img, " +
            "img[src*=avatar], img[src*=uc_server], a.notice_img img"
        val image = node.selectFirst(imageSelector)?.let { ContentParser.imageUrl(it, page) }
        if (text.isBlank() && links.isEmpty()) return null
        val primary = when (kind) {
            NativeContentKind.Thread -> links.firstOrNull {
                ContentParser.topicId(it.url) != null && !ContentParser.isMutationUrl(it.url)
            }
            NativeContentKind.Notice -> links.firstOrNull { it.url.contains("goto=findpost") }
                ?: links.firstOrNull { ContentParser.topicId(it.url) != null }
            NativeContentKind.Person, NativeContentKind.Rank -> links.firstOrNull {
                val target = it.url.toHttpUrlOrNull()
                target?.queryParameter("mod") == "space" && target.queryParameter("uid") != null ||
                    it.url.contains("space-uid-")
            } ?: links.firstOrNull { ContentParser.topicId(it.url) != null }
            NativeContentKind.Product -> links.firstOrNull { it.url.contains("keke_integralmall-view") }
            else -> null
        }
        val facts = buildList<ContentFact> {
            if (kind == NativeContentKind.CreditRecord || kind == NativeContentKind.UserGroup) {
                addAll(parseAccountFacts(node))
            }
            if (kind == NativeContentKind.Rank && duration != null) {
                // Online leaderboard reports *accumulated* minutes, not online/offline status.
                val unit = if (duration.groupValues[2] == "分") "分钟" else duration.groupValues[2]
                add(ContentFact("在线时长", "${duration.groupValues[1]} $unit"))
            } else if (kind == NativeContentKind.Rank && metric != null) {
                add(ContentFact(metric.groupValues[2], metric.groupValues[1]))
            }
            if (kind == NativeContentKind.Product) {
                node.selectFirst(".discount-price i, .price-real i")?.text()?.trim()
                    ?.takeIf(String::isNotBlank)?.let { add(ContentFact("价格", "$it 金币")) }
                node.selectFirst(".count-r")?.text()?.trim()?.takeIf(String::isNotBlank)
                    ?.let { add(ContentFact("库存", it)) }
            }
            if (kind == NativeContentKind.Facts) {
                val label = node.selectFirst("em")?.text()?.trim()?.trimEnd(':', '：')
                if (!label.isNullOrBlank()) {
                    val value = node.clone().apply { select("em").remove() }.text().trim()
                    if (value.isNotBlank()) add(ContentFact(label, value))
                }
            }
            if (kind == NativeContentKind.Notice) {
                node.selectFirst("dt span[title], .top_time, .msg_time, dt .xg1")?.let {
                    val time = it.attr("title").ifBlank { it.text() }.trim()
                    if (time.isNotBlank()) add(ContentFact("时间", time))
                }
            }
        }
        val summaryNode = when (kind) {
            NativeContentKind.Notice -> node.selectFirst(".ntc_body")
            NativeContentKind.Person -> node.selectFirst("p.txt, p.maxh, .txt")
            NativeContentKind.Rank -> node.selectFirst("dd:not(.ranknum):not(.avt):not(.m), p")
            NativeContentKind.CreditRecord, NativeContentKind.UserGroup -> node.selectFirst(".summary, p.txt, .txt")
            else -> null
        }
        val summary = if (kind == NativeContentKind.Rank) {
            (duration ?: metric)?.value.orEmpty() // Keep metrics out of the username.
        } else summaryNode?.text()?.let(::cleanAccountText)?.takeIf(String::isNotBlank) ?: text
        val feedMeta = if (kind == NativeContentKind.Thread || kind == NativeContentKind.Notice) {
            val tid = primary?.url?.let(ContentParser::topicId).orEmpty()
            val entry = TopicListMetadata.parse(original, tid, page)
            val authorLink = links.firstOrNull { link ->
                (link.url.contains("space-uid-") || link.url.contains("space-username-") ||
                    (link.url.contains("mod=space") && link.url.contains("uid="))) &&
                    link.text !in setOf("关注", "已关注", "取消关注", "个人资料", "主页")
            }
            val forumLink = links.firstOrNull { link ->
                ContentParser.forumId(link.url) != null && link.url != primary?.url
            }
            val datePattern = Regex("""20\d{2}[-/.]\d{1,2}[-/.]\d{1,2}(?:\s+\d{1,2}:\d{2})?|\d+\s*(?:分钟前|小时前|天前)|昨天|前天""")
            val time = original.select("time, [datetime], [title]").firstNotNullOfOrNull { el ->
                datePattern.find(el.attr("datetime"))?.value
                    ?: datePattern.find(el.attr("title"))?.value
            } ?: datePattern.find(original.text())?.value.orEmpty()
            FeedListMeta(
                author = entry.author.takeUnless {
                    it in setOf("关注", "已关注", "取消关注", "个人资料", "主页", "发消息")
                }.orEmpty().ifBlank { authorLink?.text.orEmpty() },
                authorUrl = entry.authorUrl ?: authorLink?.url,
                avatar = entry.avatar ?: image,
                time = time,
                forum = forumLink?.text.orEmpty(),
                likes = if (kind == NativeContentKind.Thread) entry.likes else null,
                replies = if (kind == NativeContentKind.Thread) entry.replies else null,
                views = if (kind == NativeContentKind.Thread) entry.views else null,
            )
        } else null
        return ContentBlock(summary, title, image, links, kind, facts, rank, primary,
            hasHiddenContent = kind == NativeContentKind.Thread && TopicListMetadata.hasHidden(original),
            feedMeta = feedMeta)
    }

    private fun link(anchor: Element, page: String): ContentLink? {
        val target = ContentParser.linkTarget(anchor, page) ?: return null
        val label = cleanAccountText(ContentParser.clean(anchor.text()))
            .ifBlank { cleanAccountText(ContentParser.clean(anchor.attr("title"))) }
            .ifBlank {
                when {
                    anchor.id().startsWith("a_ignore") -> "删除好友"
                    anchor.id().startsWith("a_poke") -> "打招呼"
                    anchor.id().startsWith("a_sendpm") -> "发消息"
                    anchor.id().startsWith("friend_editnote") -> "编辑备注"
                    else -> ""
                }
            }
            .let { if (it == "取消" && target.contains("ac=follow")) "取消关注" else it }
            .ifBlank { return null }
        return ContentLink(label, target)
    }

    private fun signPage(doc: Element, page: String): Result {
        val text = ContentParser.clean(doc.text())
        val signed = when {
            Regex("今日已签到|已签到|已簽到").containsMatchIn(text) -> true
            Regex("尚未签到|还未签到|立即签到").containsMatchIn(text) -> false
            else -> null
        }
        val lines = listOf(
            "签到等级" to "签到等级\\s*[:：]?\\s*(Lv\\.?\\s*\\d+)",
            "今日排名" to "今日排名\\s*[:：]?\\s*(\\d+)",
            "连续签到" to "连续签到\\s*[:：]?\\s*(\\d+\\s*天)",
            "累计签到" to "累计签到\\s*[:：]?\\s*(\\d+\\s*天)",
        ).mapNotNull { (label, pattern) ->
            Regex(pattern, RegexOption.IGNORE_CASE).find(text)?.groupValues?.get(1)
                ?.let { ContentFact(label, it) }
        }
        val status = when (signed) { true -> "今日已签到"; false -> "今日未签到"; null -> "" }
        val blocks = if (status.isBlank() && lines.isEmpty()) emptyList()
            else listOf(ContentBlock(status, kind = NativeContentKind.Facts, facts = lines))
        return Result(navigation(doc, page) + blocks, signed)
    }
}
