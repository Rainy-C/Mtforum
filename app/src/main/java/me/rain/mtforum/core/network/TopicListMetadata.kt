package me.rain.mtforum.core.network

import org.jsoup.nodes.Element

/** Priority matters: a selector union would pick the empty avatar link before the nickname. */
internal object TopicListMetadata {
    data class Value(
        val author: String, val authorUrl: String?, val avatar: String?,
        val likes: String?, val replies: String?, val views: String?, val hidden: Boolean,
    )

    fun parse(row: Element, tid: String, page: String): Value {
        val author = listOf(
            ".top_user", ".by cite a", ".km_user a", ".author a", "a[href*=space-username-]",
            ".forumlist_li_top h2 a", "a[href*=space-uid-]", "a[href*=uid=]",
        ).firstNotNullOfOrNull { selector ->
            row.select(selector).firstOrNull { node ->
                val href = node.attr("href")
                ContentParser.clean(node.text()).isNotBlank() &&
                    !href.contains("mod=spacecp") && !href.contains("ac=follow")
            }
        }
        val avatarNode = listOf("a.wblist_tximg img", "img.top_tximg", ".top_tximg img", ".avt img", ".comiis_listtx img")
            .firstNotNullOfOrNull { row.selectFirst(it) }
        val authorAnchor = author?.let { if (it.hasAttr("href")) it else it.selectFirst("a[href]") ?: it.closest("a[href]") }
        val avatarAnchor = avatarNode?.closest("a[href]")
        val url = authorAnchor?.let { ContentParser.absolute(it.attr("href"), page) }
            ?: avatarAnchor?.let { ContentParser.absolute(it.attr("href"), page) }
        val name = ContentParser.clean(author?.text().orEmpty()).ifBlank {
            ContentParser.clean(avatarAnchor?.attr("title").orEmpty())
                .takeUnless { it in setOf("头像", "个人主页", "查看资料") }.orEmpty()
        }
        val bottom = row.select(".comiis_xznalist_bottom, .comiis_znalist_bottom, .forumlist_li_info, .comiis_list_bottom, .list_info")
        var statNodes = row.select(".comiis_xznalist_bottom .comiis_tm, .comiis_znalist_bottom .comiis_tm")
        if (statNodes.isEmpty()) statNodes = row.select(".comiis_xznalist_bottom ul > li, .comiis_znalist_bottom ul > li")
        val numbers = statNodes.map { count(it.text()) }
        val text = bottom.joinToString(" ") { ContentParser.clean(it.text()) }
        var likes = row.selectFirst(".num-all_$tid")?.let { count(it.text()) }
            ?: labelled(text, "点赞|推荐|赞")
        var replies = labelled(text, "评论|回复") ?: row.selectFirst(".km_reply, .num a")?.let { count(it.text()) }
        var views = labelled(text, "阅读|浏览|查看") ?: row.selectFirst(".km_view, .num em")?.let { count(it.text()) }
        if (numbers.size >= 3) {
            likes = likes ?: numbers[0]
            replies = replies ?: numbers[1]
            views = views ?: numbers[2]
        } else if (numbers.size == 2 && likes != null) {
            replies = replies ?: numbers[0]
            views = views ?: numbers[1]
        }
        return Value(name, url, avatarNode?.let { ContentParser.imageUrl(it, page) }, likes, replies, views, hasHidden(row))
    }

    fun hasHidden(row: Element): Boolean =
        Regex("本(?:帖)?内容被作者隐藏|本帖隐藏的内容|回复后可见|回复可见|查看隐藏内容")
            .containsMatchIn(row.text()) ||
            row.selectFirst(".showhide, .replyhide, .hidecontent, [id^=hide_], " +
                "[id*=showhide], [id*=replyhide], [id*=hidecontent], " +
                "[class*=showhide], [class*=replyhide], [class*=hidecontent]") != null

    private fun count(text: String): String? =
        Regex("""\d[\d,]*(?:\.\d+)?\s*[万亿kKwW]?""").find(ContentParser.clean(text))?.value?.trim()

    private fun labelled(text: String, labels: String): String? {
        val after = Regex("(?:$labels)\\s*[:：]?\\s*(\\d[\\d,]*(?:\\.\\d+)?[万亿kKwW]?)")
            .find(text)?.groupValues?.get(1)
        return after ?: Regex("(\\d[\\d,]*(?:\\.\\d+)?[万亿kKwW]?)\\s*(?:$labels)")
            .find(text)?.groupValues?.get(1)
    }
}
