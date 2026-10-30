package me.rain.mtforum.core.network

import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/** Navigation groups that are *views* of one account page, not new detail routes. */
internal fun nativeSectionGroup(rawUrl: String): String? {
    val url = rawUrl.toHttpUrlOrNull() ?: return null
    if (url.scheme != "https" || url.host != ForumRepository.Host ||
        url.encodedPath != "/home.php" || ContentParser.isMutationUrl(rawUrl) ||
        url.queryParameter("uid") != null || url.queryParameter("touid") != null) return null
    val mod = url.queryParameter("mod")
    val action = url.queryParameter("do")
    return when {
        mod == "space" && action == "friend" -> "social"
        mod == "follow" && action in setOf("following", "follower") -> "social"
        mod == "spacecp" && url.queryParameter("ac") == "friend" &&
            url.queryParameter("op") == "request" -> "social"
        mod == "space" && action == "thread" && url.queryParameter("view") == "me" -> "my-posts"
        mod == "space" && action == "favorite" -> "favorites"
        mod == "space" && action == "notice" -> "notices"
        mod == "spacecp" && url.queryParameter("ac") == "profile" &&
            url.queryParameter("op") in setOf(null, "base", "info", "contact", "password") -> "account-profile"
        mod == "spacecp" && url.queryParameter("ac") == "credit" &&
            url.queryParameter("op") in setOf(null, "base", "log", "loglist", "record", "rule") -> "credits"
        mod == "spacecp" && url.queryParameter("ac") == "usergroup" &&
            url.queryParameter("op") in setOf(null, "list") -> "usergroups"
        else -> null
    }
}

internal fun isNativeSectionTab(currentUrl: String, targetUrl: String): Boolean {
    val group = nativeSectionGroup(currentUrl) ?: return false
    return group == nativeSectionGroup(targetUrl) && !ContentParser.isMutationUrl(targetUrl)
}

/** Page-number navigation must not add entries to the global back stack. */
internal fun isNativePageChange(currentUrl: String, targetUrl: String): Boolean {
    val current = currentUrl.toHttpUrlOrNull() ?: return false
    val target = targetUrl.toHttpUrlOrNull() ?: return false
    if (target.scheme != "https" || current.host != target.host || current.encodedPath != target.encodedPath ||
        ContentParser.isMutationUrl(targetUrl) || current.queryParameter("page") == target.queryParameter("page")) {
        return false
    }
    return current.sectionIdentity() == target.sectionIdentity()
}

// Canonicalize query order too: Discuz can reorder parameters between pages.
private fun HttpUrl.sectionIdentity(): String = buildString {
    append(scheme).append("://").append(host).append(encodedPath)
    (queryParameterNames - setOf("page", "mobile")).sorted().forEach { key ->
        append('|').append(key).append('=').append(queryParameterValues(key).joinToString(","))
    }
}

internal fun nativeSectionTabIdentity(url: String): String =
    url.toHttpUrlOrNull()?.sectionIdentity() ?: url


/** A stable list for the compact favorites segmented bar, including empty categories.
 * The forum only provides titles/links in favorite rows. No extra detail requests.
 */
private val favoriteTypes = listOf(
    "all" to "全部收藏",
    "thread" to "帖子",
    "forum" to "版块",
    "group" to "群组",
)

internal fun favoriteSectionLinks(rawUrl: String): List<ContentLink> {
    if (nativeSectionGroup(rawUrl) != "favorites") return emptyList()
    val source = rawUrl.toHttpUrlOrNull() ?: return emptyList()
    return favoriteTypes.map { (type, title) ->
        ContentLink(title, source.newBuilder()
            .removeAllQueryParameters("type")
            .removeAllQueryParameters("page")
            .addQueryParameter("type", type)
            .build().toString())
    }
}

internal fun favoriteSectionIndex(rawUrl: String): Int {
    val type = rawUrl.toHttpUrlOrNull()?.queryParameter("type") ?: "all"
    return favoriteTypes.indexOfFirst { it.first == type }.coerceAtLeast(0)
}

/** Do not render the site's own duplicate tab row below our persistent Miuix bar. */
internal fun isFavoriteTabNavigation(block: ContentBlock, rawUrl: String): Boolean {
    if (nativeSectionGroup(rawUrl) != "favorites") return false
    if (block.kind == NativeContentKind.Navigation) return true
    return block.links.size >= 2 && block.links.all { isNativeSectionTab(rawUrl, it.url) }
}

/** Account social categories belong to ONE persistent screen. The website sometimes
 * ships two independent tab bars; only these six categories are shown by the app.
 */
private val socialTypes = listOf(
    Triple("我的好友", "space", "friend"),
    Triple("最近来访", "space", "visitor"),
    Triple("我看过谁", "space", "trace"),
    Triple("我的关注", "follow", "following"),
    Triple("我的粉丝", "follow", "follower"),
    Triple("好友请求", "spacecp", "request"),
)

internal fun socialSectionLinks(rawUrl: String): List<ContentLink> {
    if (nativeSectionGroup(rawUrl) != "social") return emptyList()
    val base = ForumRepository.BaseUrl
    return socialTypes.map { (title, module, selector) ->
        val query = when (module) {
            "space" -> "mod=space&do=friend" +
                (if (selector == "friend") "" else "&view=$selector")
            "follow" -> "mod=follow&do=$selector"
            else -> "mod=spacecp&ac=friend&op=request"
        }
        ContentLink(title, "$base/home.php?$query&mobile=2")
    }
}

internal fun socialSectionIndex(rawUrl: String): Int {
    val parsed = rawUrl.toHttpUrlOrNull() ?: return 0
    return when {
        parsed.queryParameter("mod") == "follow" && parsed.queryParameter("do") == "following" -> 3
        parsed.queryParameter("mod") == "follow" && parsed.queryParameter("do") == "follower" -> 4
        parsed.queryParameter("mod") == "spacecp" && parsed.queryParameter("op") == "request" -> 5
        parsed.queryParameter("view") == "visitor" -> 1
        parsed.queryParameter("view") == "trace" -> 2
        else -> 0
    }
}

/** Recognize even the generic HTML fallback's tab blocks, not only Navigation kind.
 * User operation rows and actual profile links must never be discarded.
 */
internal fun isDuplicateAccountNavigation(block: ContentBlock, rawUrl: String): Boolean {
    val group = nativeSectionGroup(rawUrl) ?: return false
    if (group == "favorites") {
        if (isFavoriteTabNavigation(block, rawUrl)) return true
        return block.primaryLink == null && block.links.size == 1 &&
            isSingleSectionTab(block, rawUrl)
    }
    if (group == "social") {
        if (block.kind == NativeContentKind.Navigation) return true
        val labels = setOf("我的好友", "最近来访", "我看过谁", "好友请求", "好友申请", "我的关注", "我的粉丝")
        if (block.primaryLink != null) return false
        val matching = block.links.count { link ->
            link.text.trim() in labels && nativeSectionGroup(link.url) == "social"
        }
        return matching >= 2 || matching == 1 && block.links.size == 1 &&
            isSingleSectionTab(block, rawUrl)
    }
    if (block.kind == NativeContentKind.Navigation)
        return block.links.size >= 2 && block.links.all { isNativeSectionTab(rawUrl, it.url) }
    return block.primaryLink == null &&
        (block.links.count { isNativeSectionTab(rawUrl, it.url) } >= 2 ||
            block.links.size == 1 && isSingleSectionTab(block, rawUrl))
}

private fun isSingleSectionTab(block: ContentBlock, page: String): Boolean {
    val only = block.links.singleOrNull() ?: return false
    if (!isNativeSectionTab(page, only.url)) return false
    val label = only.text.trim()
    val full = block.text.trim()
    // Comiis sometimes appends a count: "回复 (2)" / "粉丝 12".
    return label.isNotBlank() && full.startsWith(label) && full.length - label.length <= 12
}
