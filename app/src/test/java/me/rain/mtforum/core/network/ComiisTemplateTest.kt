package me.rain.mtforum.core.network

import org.junit.Assert.*
import org.junit.Test
import me.rain.mtforum.feature.forum.annotated

/** Fixture captured from bbs.binmt.cc thread-174960 (Comiis mobile template). */
class ComiisTemplateTest {
    private val html: String by lazy {
        checkNotNull(javaClass.classLoader?.getResourceAsStream("comiis_thread.html")) {
            "comiis_thread.html fixture missing"
        }.bufferedReader().use { it.readText() }
    }

    private val detail by lazy {
        ContentParser.detail(html, "${ForumRepository.BaseUrl}/thread-174960-1-1.html")
    }

    @Test
    fun splitsAllFloorsOfTheComiisTemplate() {
        assertEquals(10, detail.posts.size)
        assertEquals("MultiTTS 开源版本出来了 修复了bug 以后应该会有微软的hd语音吧", detail.title)
        assertEquals("174960", detail.tid)
    }

    @Test
    fun bodyIsTheMessageTableNotTheOuterContainer() {
        val first = detail.posts.first()
        assertTrue(first.html.contains("众所周知"))
        // The outer `.comiis_message` also carries the rate button and the "liked by" strip.
        assertFalse(first.html.contains("comiis_recommend_list_a"))
        assertFalse(first.html.contains("comiis_rate"))
        assertFalse(first.html.contains("_avatar_middle"))
        assertFalse(first.html.contains("noavatar_middle"))
    }

    @Test
    fun likedByAvatarsAndSmileysNeverBecomeContentImages() {
        val images = detail.posts.flatMap { it.images }
        assertTrue(images.none { it.contains("/avatar/") || it.contains("noavatar") })
        assertTrue(images.none { it.contains("/smiley/") })
        assertEquals(
            listOf("https://oos.binmt.cc/forum/202610/18/121503wi9h99d30mx66old.jpg"),
            detail.posts.first().images,
        )
    }

    @Test
    fun floorTimeIsParsedForEveryPost() {
        assertTrue(detail.posts.all { it.time.isNotBlank() })
        assertEquals("6 小时前 来自 四川", detail.posts.first().time)
    }

    @Test
    fun smileyIsKeptInlineInsteadOfBecomingAPostImage() {
        val post = detail.posts.first { it.id == "11983658" }
        assertTrue(post.html.contains("/static/image/smiley/"))
        assertTrue(post.images.isEmpty())
    }

    @Test
    fun guestAttachmentPromoIsNotPartOfTheBody() {
        val html =
            """<div id="pid1"><div class="comiis_message"><div class="comiis_messages">
                <div class="comiis_a comiis_message_table">正文</div>
                <div class="comiis_p10 bg_e f14 mt10 mb5 cl">
                    <div class="comiis_noatt_ico bg_0 f_f"></div>
                    <h3 class="f_c">本帖子中包含更多精彩资源</h3>
                    <p>您需要登录才可以查看，没帐号? 立即注册</p>
                </div>
            </div></div></div>"""
        val post = ContentParser.detail(html, "${ForumRepository.BaseUrl}/thread-1-1-1.html").posts.single()
        assertTrue(post.html.contains("正文"))
        assertFalse(post.html.contains("本帖子中包含更多精彩资源"))
        assertFalse(post.html.contains("立即注册"))
    }

    @Test
    fun gallerySiblingOfTheMessageTableStaysInThePost() {
        val html =
            """<div id="pid11984733">
                <div class="comiis_postli_top"><img class="top_tximg" src="https://cdn.binmt.cc/uc_server/data/avatar/000/16/07/21_avatar_middle.jpg"></div>
                <div class="comiis_message"><div class="comiis_messages">
                    <div class="comiis_a comiis_message_table cl">正文</div>
                    <ul class="comiis_img_list cl">
                        <li><span onclick="x"><img src="https://cdn.binmt.cc/template/comiis_app/pic/none.png" comiis_loadimages="https://oos.binmt.cc/forum/a.jpg"></span></li>
                        <li><span onclick="y"><img src="https://cdn.binmt.cc/template/comiis_app/pic/none.png" comiis_loadimages="https://oos.binmt.cc/forum/b.jpg"></span></li>
                    </ul>
                </div><div class="comiis_rate">赞赏</div></div>
            </div>"""
        val post = ContentParser.detail(html, "${ForumRepository.BaseUrl}/thread-1-1-1.html").posts.single()
        assertTrue(post.html.contains("正文"))
        assertFalse(post.html.contains("赞赏"))
        assertFalse(post.html.contains("avatar"))
        assertEquals(
            listOf("https://oos.binmt.cc/forum/a.jpg", "https://oos.binmt.cc/forum/b.jpg"),
            post.images,
        )
        val blocks = PostBodyParser.parse(post.html)
        assertEquals(listOf("text", "image", "image"), blocks.map { it.kind })
        assertEquals("正文", annotated(blocks.first().node) { _, _ -> }.text)
    }
}
