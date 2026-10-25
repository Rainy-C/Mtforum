package me.rain.mtforum.core.network

import org.junit.Assert.*
import org.junit.Test

class ThreadCommentPagesTest {
    private val base = ForumRepository.BaseUrl
    private fun comment(id: String) = ContentPost(id, "用户$id", null, null, "", "$id 楼", "<p>评论$id</p>", emptyList(), emptyList())
    private fun page(posts: List<ContentPost>, next: String? = null) = TopicDetail(
        title = "讨论", tid = "123", fid = "41", posts = posts,
        next = next, previous = null, formhash = "ok",
    )

    @Test fun loadsNextPageInsideTheSameThreadOnly() {
        val target = "$base/thread-123-1-2.html"
        val current = page(listOf(comment("1")), target)
        assertEquals(target, ThreadCommentPages.next(current, setOf("$base/thread-123-1-1.html")))
        assertNull(ThreadCommentPages.next(current, setOf(target)))
        assertNull(ThreadCommentPages.next(current.copy(next = "$base/thread-999-1-2.html"), emptySet()))
        assertNull(ThreadCommentPages.next(current.copy(next = "https://example.com/thread-123-1-2.html"), emptySet()))
    }

    @Test fun appendsUniqueCommentsPreservingFirstPageMetadata() {
        val first = page(listOf(comment("1"), comment("2")), "$base/thread-123-1-2.html")
        val second = page(listOf(comment("2"), comment("3")), "$base/thread-123-1-3.html")
            .copy(title = "分页标题", fid = "", previous = "$base/thread-123-1-1.html")
        val result = ThreadCommentPages.append(first, second)
        assertEquals(listOf("1", "2", "3"), result.posts.map { it.id })
        assertEquals("讨论", result.title)
        assertNull(result.previous)
        assertEquals(first.fid, result.fid)
        assertEquals(second.next, result.next)
    }

    @Test(expected = IllegalArgumentException::class)
    fun cannotMergeDifferentThread() {
        ThreadCommentPages.append(page(listOf(comment("1"))), page(listOf(comment("2"))).copy(tid = "999"))
    }
}
