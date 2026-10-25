package me.rain.mtforum.core.network

import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import org.jsoup.Jsoup

data class UserSpaceProfile(
    val uid: String,
    val name: String,
    val avatar: String?,
    val group: String,
    val level: String,
    val stats: Map<String, Long>,
    val signature: String,
    val details: List<ContentFact>,
    val actions: List<ContentLink>,
    val medals: List<Pair<String, String>>,
)

/** Target identity comes from the requested user/visible profile, never discuz_uid (the viewer). */
internal object UserSpaceParser {
    fun uid(url: String): String? = Regex("""space-uid-(\d+)""").find(url)?.groupValues?.get(1)
        ?: url.toHttpUrlOrNull()?.queryParameter("uid")?.takeIf { it.matches(Regex("\\d+")) }

    fun parse(body: String, page: String, requestedUid: String?): UserSpaceProfile {
        val doc = Jsoup.parse(ContentParser.unwrap(body), page)
        val details = linkedMapOf<String, String>()
        doc.select(".comiis_space_profile li, .u_profile .pf_l li, .u_profile tr").forEach { row ->
            val labelNode = row.selectFirst("span, em, th") ?: return@forEach
            val label = ContentParser.clean(labelNode.text()).trimEnd(':', '：')
            val value = row.selectFirst(".profile_rs, .profile_r, td")?.text()
                ?: row.clone().apply { select("em").remove() }.text().removePrefix(labelNode.text())
            val clean = ContentParser.clean(value)
            if (label.isNotBlank() && label.length <= 20 && clean.isNotBlank()) details.putIfAbsent(label, clean)
        }
        val visibleUid = listOf("用户ID", "用户 ID", "UID").firstNotNullOfOrNull { label ->
            details[label]?.takeIf { it.matches(Regex("\\d+")) }
        } ?: doc.selectFirst(".u_profile h2")?.text()?.let {
            Regex("""UID\s*[:：]\s*(\d+)""").find(it)?.groupValues?.get(1)
        }
        if (requestedUid != null && visibleUid != null && requestedUid != visibleUid)
            throw ForumException("返回的用户主页与请求不一致，请刷新重试")
        val id = requestedUid ?: visibleUid ?: uid(page) ?: throw ForumException("未能读取用户主页身份")
        val nameNode = listOf(".comiis_space_info h2", ".comiis_space_tx h2", "#uhd .h h2", ".u_profile h2")
            .firstNotNullOfOrNull { doc.selectFirst(it) }
        val name = nameNode?.clone()?.apply { select(".kmlev, .kmlevs, .top_lev").remove() }
            ?.text()?.let(ContentParser::clean)?.takeIf { it.isNotBlank() && !it.startsWith("UID:") }
            ?: doc.selectFirst("#uhd .h p a")?.text()?.let(ContentParser::clean)?.takeIf(String::isNotBlank)
            ?: "UID $id"
        if (doc.selectFirst(".comiis_space_info, .comiis_space_tx, #uhd, .u_profile") == null)
            throw ForumException(ForumParser.message(body).ifBlank { "该用户主页暂不可访问" })
        val stats = ForumParser.profileStats(doc).toMutableMap()
        val labels = listOf("帖子", "回复", "好友", "粉丝", "关注", "人气", "主题数", "回帖数", "好友数")
        doc.select(".comiis_space_profileico li a span, .comiis_space_tx > p > span, .u_profile ul.bbda a").forEach { node ->
            val text = ContentParser.clean(node.text())
            labels.forEach { label ->
                val after = Regex(label + "\\s*[:：]?\\s*([\\d,]+)").find(text)?.groupValues?.get(1)
                val before = Regex("([\\d,]+)\\s*" + label).find(text)?.groupValues?.get(1)
                (after ?: before)?.replace(",", "")?.toLongOrNull()?.let { stats.putIfAbsent(label, it) }
            }
        }
        mapOf("主题数" to "帖子", "主题" to "帖子", "回帖数" to "回复", "好友数" to "好友").forEach { (from, to) ->
            stats[from]?.let { stats.putIfAbsent(to, it) }
        }
        val avatar = listOf(".comiis_space_info .user_img img", ".comiis_space_tx .user_img img", "#uhd .avt img")
            .firstNotNullOfOrNull { doc.selectFirst(it) }?.let { ContentParser.imageUrl(it, page) }
        val actions = doc.select("a[href], a[onclick]").mapNotNull { link ->
            val target = ContentParser.linkTarget(link, page) ?: return@mapNotNull null
            val parsed = target.toHttpUrlOrNull() ?: return@mapNotNull null
            val label = when {
                parsed.queryParameter("do") == "pm" && parsed.queryParameter("touid") == id -> "发私信"
                parsed.queryParameter("ac") == "follow" && parsed.queryParameter("fuid") == id ->
                    if (parsed.queryParameter("op") == "del") "取消关注" else "关注"
                parsed.queryParameter("ac") == "friend" && parsed.queryParameter("uid") == id ->
                    if (parsed.queryParameter("op") == "add") "加好友" else return@mapNotNull null
                else -> return@mapNotNull null
            }
            ContentLink(label, target)
        }.distinctBy { it.text }
        val signature = details.remove("个人签名") ?: details.remove("签名").orEmpty()
        listOf("用户ID", "用户 ID", "UID").forEach { details.remove(it) }
        val medals = doc.select("#comiis_medal img, [class*=medal] img, [class*=xunzhang] img").mapNotNull { image ->
            ContentParser.imageUrl(image, page)?.let { image.attr("alt") to it }
        }.distinctBy { it.second }
        return UserSpaceProfile(id, name, avatar, doc.selectFirst(".comiis_space_tx .kmlev, .kmlev")?.text().orEmpty(),
            doc.selectFirst(".comiis_space_tx .kmlevs, .kmlevs")?.text().orEmpty(), stats, signature,
            details.map { ContentFact(it.key, it.value) }, actions, medals)
    }
}
