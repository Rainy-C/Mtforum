package me.rain.mtforum.core.network

import org.junit.Assert.*
import org.junit.Test

class ContentParserTest {
    private val base = ForumRepository.BaseUrl

    @Test
    fun forumStatsAreNotPrependedToBoardNames() {
        val html = """<a href="forum-41-1.html"><em>597</em> 逆向交流</a>
            <a href="forum-38-1.html">3 建议反馈</a>
            <a href="forum-2-1.html">版本发布</a>"""
        val boards = ContentParser.boards(html)
        assertEquals("逆向交流", boards.first { it.id == "41" }.title)
        assertEquals("597", boards.first { it.id == "41" }.todayPosts)
        assertEquals("建议反馈", boards.first { it.id == "38" }.title)
        assertEquals("3", boards.first { it.id == "38" }.todayPosts)
        assertNull(boards.first { it.id == "2" }.todayPosts)
    }

    @Test
    fun desktopTablePostsKeepBodyLazyImagesAndSeparateReplies() {
        val html = """<title>桌面帖子 - MT论坛</title><div id="post_101"><table id="pid101"><tr>
            <td class="pls"><div class="authi"><a href="home.php?uid=1">甲</a></div></td>
            <td><table><tr><td id="postmessage_101" class="t_f"><p>完整正文</p>
            <img file="http://cdn.binmt.cc/one.jpg" src="static/image/common/none.gif"></td></tr></table></td></tr></table></div>
            <div id="post_102"><table id="pid102"><tr><td id="postmessage_102" class="t_f">第二楼</td></tr></table></div>"""
        val posts = ContentParser.detail(html, "$base/thread-123-1-1.html").posts
        assertEquals(listOf("101", "102"), posts.map { it.id })
        assertTrue(posts.first().html.contains("完整正文"))
        assertFalse(posts.first().html.contains("第二楼"))
        assertEquals(listOf("https://cdn.binmt.cc/one.jpg"), posts.first().images)
        assertEquals("第二楼", org.jsoup.Jsoup.parse(posts.last().html).text())
    }

    @Test
    fun messageOnlyTableTemplateStillHasVisibleContent() {
        val html = """<table><tr><td id="postmessage_301">正文<br>换行</td></tr></table>"""
        val post = ContentParser.detail(html, "$base/thread-123-1-1.html").posts.single()
        assertEquals("301", post.id)
        assertTrue(post.html.contains("正文"))
    }

    @Test
    fun topicThumbnailsPreferRealImagesAndKeepThreeDistinctPreviews() {
        val html = """<li class="forumlist_li"><h2><a href="thread-123-1-1.html">图片帖</a></h2>
            <div class="comiis_xznalist_img"><img data-original="//cdn.binmt.cc/1.jpg" src="loading.gif">
            <img file="/2.jpg"><img data-src="/3.jpg"><img file="/4.jpg"></div></li>"""
        val images = ContentParser.topics(html, "$base/forum-41-1.html").first.single().images
        assertEquals(listOf("https://cdn.binmt.cc/1.jpg", "$base/2.jpg", "$base/3.jpg"), images)
    }

    @Test
    fun desktopListReadsActualComiisStatsAndImageAttachmentMarker() {
        val html = """<table><tbody id="normalthread_174581"><tr><td><div class="comiis_postlist">
            <div class="comiis_listtx"><img src="//cdn.binmt.cc/avatar.jpg"></div>
            <h2><a href="thread-174581-1-1.html">真实帖子标题</a><img alt="attach_img" title="图片附件" src="image_s.gif"></h2>
            <p><em class="km_view">1668</em><em class="km_reply"><a href="thread-174581-1-1.html">238</a></em>
            <em class="km_user"><a href="space-uid-28305.html">宋言</a></em></p></div></td></tr></tbody></table>"""
        val topic = ContentParser.topics(html, "$base/forum-41-1.html").first.single()
        assertEquals("宋言", topic.author)
        assertEquals("1668", topic.views)
        assertEquals("238", topic.replies)
        assertTrue(topic.hasImageAttachments)
        assertTrue(topic.images.isEmpty()) // The attachment indicator is not a thumbnail.
        assertEquals("https://cdn.binmt.cc/avatar.jpg", topic.avatar)
    }

    @Test
    fun attachmentPermissionNoticeIsNotInjectedIntoThePostBody() {
        val html = """<div id="post_1"><table id="pid1"><tr><td><table><tr>
            <td id="postmessage_1">正文<div class="locked">回复后查看隐藏内容</div></td></tr></table>
            <div class="attach_nopermission">您需要<a href="member.php?mod=logging&amp;action=login">登录</a>才可以查看资源</div>
            </td></tr></table></div>"""
        val post = ContentParser.detail(html, "$base/thread-123-1-1.html").posts.single()
        assertTrue(post.html.contains("回复后查看隐藏内容"))
        assertFalse(post.html.contains("才可以查看资源"))
    }

    @Test
    fun guideUsesTheSameThreadStatsAndNextPageAsTheOldComiisTemplate() {
        val html =
            """<li class="forumlist_li"><a class="top_user" href="home.php?mod=space&uid=42">作者</a>
            <h2><a href="thread-123-1-1.html">完整标题</a></h2><a href="forum-41-1.html">来自逆向交流</a>
            <div class="comiis_xznalist_bottom"><span class="comiis_tm">8</span><span class="comiis_tm">12</span><span class="comiis_tm">321</span></div></li>
            <a class="nxt" href="forum.php?mod=guide&page=2">下一页</a>"""
        val (items, next) = ContentParser.topics(html, "$base/forum.php?mod=guide")
        assertEquals(1, items.size)
        assertEquals("123", items.single().id)
        assertEquals("作者", items.single().author)
        assertEquals("逆向交流", items.single().forum)
        assertEquals("12", items.single().replies)
        assertEquals("321", items.single().views)
        assertEquals("8", items.single().likes)
        assertEquals("$base/forum.php?mod=guide&page=2", next)
    }

    @Test
    fun parsesEveryFloorWithComiisMessageTableAndKeepsAttachmentLinks() {
        val html =
            """<title>示例标题 - MT论坛</title><input name="formhash" value="a123">
            <div id="pid101"><a class="top_user" href="home.php?mod=space&uid=1">甲</a>
            <div class="comiis_message_table"><p>第一段<br>第二段</p><a href="forum.php?mod=attachment&aid=abc">附件.zip</a></div></div>
            <div id="pid102"><a class="top_user" href="home.php?mod=space&uid=2">乙</a><div class="comiis_message_table">引用后的回复</div></div>"""
        val data = ContentParser.detail(html, "$base/thread-123-1-1.html")
        assertEquals("示例标题", data.title)
        assertEquals(listOf("101", "102"), data.posts.map { it.id })
        assertTrue(data.posts.first().html.contains("第一段"))
        assertEquals("引用后的回复", org.jsoup.Jsoup.parse(data.posts.last().html).text())
        assertEquals("附件.zip", data.posts.first().links.single().text)
    }

    @Test
    fun quotedReplyPreservesAllServerGeneratedHiddenFieldsAndDuplicateNames() {
        val html =
            """<form id="postform" method="post" action="forum.php?mod=post&amp;action=reply&amp;tid=123">
            <input type="hidden" name="formhash" value="abcd"><input type="hidden" name="noticeauthor" value="encoded%2Bvalue">
            <input type="hidden" name="reppid" value="101"><input type="hidden" name="reppost" value="yes">
            <input type="checkbox" name="aids[]" value="1" checked><input type="checkbox" name="aids[]" value="2">
            <textarea name="message">引用内容</textarea><button name="replysubmit" value="yes">发布回复</button></form>"""
        val form =
            ContentParser.document(html, "$base/forum.php?mod=post&action=reply").forms.single()
        assertEquals("POST", form.method)
        assertEquals("encoded%2Bvalue", form.fields.first { it.key == "noticeauthor" }.value)
        assertEquals("101", form.fields.first { it.key == "reppid" }.value)
        assertEquals(2, form.fields.count { it.key == "aids[]" })
        assertEquals(
            listOf(true, false),
            form.fields.filter { it.key == "aids[]" }.map { it.checked },
        )
        assertEquals("replysubmit", form.submits.single().name)
        assertEquals("yes", form.submits.single().value)
    }

    @Test
    fun externalFormActionsAndNonHttpsLinksAreRejected() {
        val html =
            """<form method="post" action="https://evil.example/steal"><input name="password" type="password"></form>"""
        assertTrue(ContentParser.document(html, base).forms.isEmpty())
        assertNull(ContentParser.absolute("javascript:alert(1)"))
        assertNull(ContentParser.absolute("file:///etc/passwd"))
        assertNull(ContentParser.absolute("https://name:password@bbs.binmt.cc/"))
        assertEquals(
            "https://cdn.binmt.cc/image.png",
            ContentParser.absolute("//cdn.binmt.cc/image.png"),
        )
    }

    @Test
    fun selectedOptionsAndLabelsKeepPrivacySettingsAndEditableValues() {
        val html =
            """<form method="post" action="home.php?mod=spacecp"><label for="name">真实姓名</label><input id="name" name="realname" value="甲">
            <select name="privacy[realname]"><option value="0">公开</option><option value="1" selected>好友</option></select>
            <textarea name="sightml">一行
两行</textarea></form>"""
        val form = ContentParser.document(html, "$base/home.php").forms.single()
        assertEquals("真实姓名", form.fields.first().label)
        val privacy = form.fields.first { it.key == "privacy[realname]" }
        assertEquals("1", privacy.value)
        assertEquals(listOf("公开", "好友"), privacy.options.map { it.label })
        assertTrue(form.fields.last().value.contains('\n'))
    }

    @Test
    fun editorUsesPageUploadHashInsteadOfFormhash() {
        val html =
            """<script>var options = { uploadformdata: {uid:'42', hash:'abcdef123'},maxfilesize:2048};</script>
            <form method="post" action="forum.php?mod=post"><input type="hidden" name="formhash" value="ff0011"><textarea name="message"></textarea></form>"""
        val form = ContentParser.document(html, "$base/forum.php?mod=post").forms.single()
        assertEquals("42", form.upload?.uid)
        assertEquals("abcdef123", form.upload?.hash)
        assertEquals(2048 * 1024, form.upload?.maxBytes)
    }

    @Test
    fun emptyUnreadMarkerIsStillUnread() {
        val html =
            """<li><a href="home.php?mod=space&amp;do=pm&amp;subop=view&amp;touid=22"><h2>乙</h2><span class="kmnums"></span><p class="msg_mes">你好</p></a></li>"""
        val data = ContentParser.conversations(html, base)
        assertEquals("22", data.single().uid)
        assertEquals("乙", data.single().name)
        assertTrue(data.single().unread)
    }

    @Test
    fun conversationDirectionUsesActualSenderUidAndPeerMarker() {
        val html =
            """<script>var discuz_uid='1';</script><form id="pmform" action="home.php?pmid=8"><input name="formhash" value="abcd"></form>
            <div class="comiis_pm_list"><div class="comiis_my_msg"><a href="home.php?uid=1"></a><div class="dialog_blue y"><div class="msg_mes">自己的消息</div></div></div>
            <div class="comiis_friend_msg"><a href="home.php?uid=2"></a><div class="dialog_white z"><div class="msg_mes">对方的消息</div></div></div></div>"""
        val data = ContentParser.conversation(html, base, "2")
        assertEquals("8", data.pmid)
        assertEquals(2, data.messages.size)
        assertTrue(data.messages.first().mine)
        assertFalse(data.messages.last().mine)
    }

    @Test
    fun mutatingGetLinksAreNeverTreatedAsReadOnlyPages() {
        assertTrue(
            ContentParser.isMutationUrl(
                "$base/home.php?mod=spacecp&ac=common&op=ignore&formhash=abcd"
            )
        )
        assertTrue(
            ContentParser.isMutationUrl("$base/forum.php?mod=ajax&action=deleteattach&aids[]=1")
        )
        assertFalse(
            ContentParser.isMutationUrl("$base/home.php?mod=spacecp&ac=profile&op=password")
        )
        assertFalse(ContentParser.isMutationUrl("$base/thread-123-1-1.html"))
    }

    @Test
    fun confirmationFormsWithOnlyHiddenFieldsStillExposeTheSubmitButton() {
        val html =
            """<form action="home.php?mod=spacecp&amp;ac=friend&amp;op=delete" method="post"><input type="hidden" name="formhash" value="abcd"><input type="hidden" name="uid" value="42"><button name="friendsubmit" value="true">确定删除</button></form>"""
        val form = ContentParser.document(html, base).forms.single()
        assertEquals("42", form.fields.first { it.key == "uid" }.value)
        assertEquals("确定删除", form.submits.single().label)
        assertEquals("friendsubmit", form.submits.single().name)
    }

    @Test
    fun securityFormFieldsHaveUserFacingLabelsAndKeepTheOriginalNames() {
        val html =
            """<form action="home.php?mod=spacecp&amp;ac=profile" method="post"><input type="password" name="oldpassword"><input name="emailnew" value="name@example.com"><select name="questionidnew"><option value="0">不修改</option></select><input name="answernew"></form>"""
        val form = ContentParser.document(html, base).forms.single()
        assertEquals(listOf("当前密码", "邮箱", "新的安全提问", "安全提问答案"), form.fields.map { it.label })
        assertEquals("name@example.com", form.fields.first { it.key == "emailnew" }.value)
        assertEquals("oldpassword", form.fields.first().key)
    }
}
