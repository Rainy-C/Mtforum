package me.rain.mtforum.core.network

import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/** Pagination is part of one thread, never a new navigation destination. */
internal object ThreadCommentPages {
    fun next(detail: TopicDetail?, visited: Set<String>): String? {
        val active = detail ?: return null
        val page = active.next ?: return null
        val parsed = page.toHttpUrlOrNull() ?: return null
        if (parsed.scheme != "https" || parsed.host != ForumRepository.Host || page in visited) return null
        if (active.tid.isBlank() || ContentParser.topicId(page) != active.tid) return null
        return page
    }

    fun append(original: TopicDetail, page: TopicDetail): TopicDetail {
        require(original.tid.isNotBlank() && original.tid == page.tid) { "下一页不属于当前帖子" }
        return original.copy(
            posts = (original.posts + page.posts).distinctBy(ContentPost::id),
            next = page.next,
            // Retain the first page's identity and reply parameters.
            previous = original.previous,
            formhash = original.formhash ?: page.formhash,
        )
    }
}
