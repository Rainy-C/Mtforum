package me.rain.mtforum.core.network

import org.jsoup.Jsoup

/** Ported from Rainy-C/Mtforum auth/session and Comiis profile parsers. */
object ForumParser {
    data class LoginForm(val formhash: String, val loginhash: String)

    fun loginForm(html: String): LoginForm {
        val document = Jsoup.parse(html)
        val hash = formhash(html).orEmpty()
        val loginHash = Regex("loginhash=([A-Za-z0-9]+)").find(html)?.groupValues?.get(1)
            ?: document.selectFirst("input[name=loginhash]")?.attr("value").orEmpty()
        if (hash.isBlank() || loginHash.isBlank()) {
            throw ForumException("无法获取登录表单，请重试或使用网页登录")
        }
        return LoginForm(hash, loginHash)
    }

    fun formhash(html: String): String? {
        val input = Jsoup.parse(html).selectFirst("input[name=formhash]")?.attr("value")
        if (!input.isNullOrBlank()) return input
        return Regex("""formhash\s*=\s*['"]([a-fA-F0-9]+)['"]""", RegexOption.IGNORE_CASE)
            .find(html)?.groupValues?.get(1)
            ?: Regex("""(?:[?&]|&amp;)formhash=([a-fA-F0-9]+)""")
                .find(html)?.groupValues?.get(1)
    }

    fun message(raw: String): String {
        val html = Regex("<!\\[CDATA\\[(.*?)\\]\\]>", RegexOption.DOT_MATCHES_ALL)
            .find(raw)?.groupValues?.get(1) ?: raw
        val doc = Jsoup.parse(html)
        doc.select("script,style,noscript").remove()
        val text = (doc.selectFirst("#messagetext p, #messagetext, .alert_error, .alert_info, p")?.text()
            ?: doc.body().text()).replace(Regex("\\s+"), " ").trim()
        if (text.isNotBlank()) return text.take(260)
        // Account endpoints also return script-only AJAX replies.
        val scriptMessage = Regex(
            """(?:showDialog|showError|show_success|errorhandle_\w+|succeedhandle_\w+)\s*\(\s*(['"])((?:\\.|(?!\1)[\s\S])*)\1"""
        ).find(html)?.groupValues?.get(2).orEmpty()
        return Jsoup.parse(scriptMessage.replace("\\n", " ").replace("\\'", "'"))
            .text().trim().take(260)
    }

    fun loginSucceeded(html: String): Boolean =
        html.contains("登录成功") || html.contains("succeedhandle_loginform")

    fun isChallenge(html: String, contentType: String): Boolean {
        val type = contentType.lowercase()
        if (!(type.contains("text/html") || type.contains("application/xhtml"))) return false
        if (html.length > 64 * 1024 || !html.contains("<html", ignoreCase = true)) return false
        val lower = html.lowercase()
        if (!lower.contains("<body")) return lower.contains("<script") || lower.contains("<meta")
        if (hasForumSkeleton(html)) return false
        return Jsoup.parse(html).apply { select("script,style,noscript").remove() }.text().length < 256
    }

    fun hasForumSkeleton(html: String): Boolean =
        Regex("discuz|formhash|comiis|id\\s*=\\s*['\"]?(?:ct|hd|ft|postlist|thread_subject)\\b", RegexOption.IGNORE_CASE)
            .containsMatchIn(html)

    fun profile(html: String): ForumProfile {
        val doc = Jsoup.parse(html, ForumRepository.BaseUrl)
        val uid = Regex("""discuz_uid\s*=\s*['"]?(\d+)""", RegexOption.IGNORE_CASE)
            .find(html)?.groupValues?.get(1)
        if (uid == "0" || doc.selectFirst("input[name=password]") != null) throw SessionExpiredException()
        if (uid.isNullOrBlank()) throw ForumException("未能解析用户身份，请刷新重试")
        val username = doc.selectFirst(".comiis_space_tx h2, .comiis_space_info h2, .comiis_uinfo_a, .vh")?.text()?.trim()
            ?.takeIf { it.isNotEmpty() } ?: doc.selectFirst("h2")?.text()?.trim() ?: "UID $uid"
        val stats = profileStats(doc)
        val avatar = doc.selectFirst(".comiis_space_tx .user_img img, .user_img img, img[src*=avatar]")
        val avatarUrl = avatar?.absUrl("src")?.takeIf { it.startsWith("https://") && it.substringBefore('?').isNotBlank() }
        return ForumProfile(
            uid = uid,
            username = username,
            avatarUrl = avatarUrl,
            userGroup = doc.selectFirst(".kmlev")?.text()?.trim(),
            threads = stats["主题"] ?: stats["帖子"],
            replies = stats["回复"],
            friends = stats["好友"],
            credits = stats["积分"],
            gold = stats["金币"],
        )
    }
    /**
     * The Comiis friends page does not expose a separate total in its profile header.
     * Count actual friend rows only when the returned list is complete. Paginated or
     * unrecognized pages must keep the friend count unknown instead of showing a
     * misleading current-page count (or zero for a login/challenge page).
     */
    fun friendCount(html: String, expectedUid: String): Long? {
        val uid = Regex("""discuz_uid\s*=\s*['"]?(\d+)""", RegexOption.IGNORE_CASE)
            .find(html)?.groupValues?.get(1)
        if (uid == null || uid == "0" || uid != expectedUid) return null

        val doc = Jsoup.parse(html, ForumRepository.BaseUrl)
        val list = doc.selectFirst(".comiis_friend_boxs .comiis_userlist01") ?: return null
        // Page navigation may be rendered outside the list itself.
        if (doc.selectFirst(
                ".comiis_friend_boxs .pg, .comiis_friend_boxs .comiis_page, " +
                    ".comiis_friend_boxs a[href*=page=], .pg a[href*=page=]"
            ) != null
        ) return null

        val rows = list.children().filter { it.tagName() == "li" && it.hasClass("b_t") }
        // Each real friend row links to that user's profile. Ignore decoration rows.
        val friends = rows.count {
            it.selectFirst("a[href*=mod=space][href*=uid=][href*=do=profile]") != null
        }
        // Empty lists are valid, but only trust the explicit empty-state marker.
        if (friends == 0 && (rows.isNotEmpty() || doc.selectFirst(".comiis_notip") == null)) return null
        return friends.toLong()
    }

    /** Read label/value pairs, including "123 帖子", "帖子(123)" and colon variants. */
    internal fun profileStats(doc: org.jsoup.nodes.Element): Map<String, Long> {
        val stats = linkedMapOf<String, Long>()
        val labels = listOf("主题", "帖子", "回复", "好友", "积分", "金币")
        fun number(text: String): Long? = Regex("-?\\d[\\d,]*").find(text)
            ?.value?.replace(",", "")?.toLongOrNull()
        fun label(text: String) = text.replace(Regex("[\\s:：()（）]"), "")
        val containers = doc.select(
            "#psts li, .pf_l li, .comiis_psts li, .comiis_space_profilejf li, " +
                ".comiis_space_jf li, .creditl li, .comiis_space_tx li, .comiis_space_info li"
        )
        for (row in containers) {
            val em = row.selectFirst("em")
            val valueNode = row.selectFirst(".f_0, span, strong")
            val labelText = label(em?.text().orEmpty())
            if (labelText in labels) {
                val copy = row.clone()
                copy.select("em, .xg1").remove()
                number(copy.text())?.let { stats[labelText] = it }
            } else if (valueNode != null) {
                val key = label(row.text().replace(valueNode.text(), ""))
                if (key in labels) number(valueNode.text())?.let { stats[key] = it }
            }
        }
        for (em in doc.select("em")) {
            val sibling = em.nextElementSibling() ?: continue
            val key = label(sibling.text())
            if (sibling.tagName() == "p" && key in labels)
                number(em.text())?.let { stats.putIfAbsent(key, it) }
        }
        // Restrict fallback to short, self-contained stats nodes, never whole-page text
        // where a UID or another user's balance could be mistaken for this account's.
        val candidates = containers + doc.select(
            ".comiis_space_tx a, .comiis_space_info a, .comiis_uinfo a, #psts a, " +
                "a[href*=type=thread], a[href*=type=reply], a[href*=do=friend]"
        )
        for (node in candidates) {
            val text = ContentParser.clean(node.text())
            if (text.length > 100) continue
            for (key in labels) {
                val after = Regex("(?:^|[\\s·|])" + key + "\\s*[:：(（]?\\s*(-?\\d[\\d,]*)")
                    .find(text)?.groupValues?.get(1)
                val before = Regex("(-?\\d[\\d,]*)\\s*" + key + "(?:$|[\\s:：)）])")
                    .find(text)?.groupValues?.get(1)
                (after ?: before)?.replace(",", "")?.toLongOrNull()
                    ?.let { stats.putIfAbsent(key, it) }
            }
        }
        return stats
    }

}

data class ForumProfile(
    val uid: String,
    val username: String,
    val avatarUrl: String? = null,
    val userGroup: String? = null,
    val threads: Long? = null,
    val replies: Long? = null,
    val friends: Long? = null,
    val credits: Long? = null,
    val gold: Long? = null,
)

open class ForumException(message: String) : java.io.IOException(message)
class SessionExpiredException : ForumException("登录已失效，请重新登录")
