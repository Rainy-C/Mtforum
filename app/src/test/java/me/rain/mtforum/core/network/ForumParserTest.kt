package me.rain.mtforum.core.network

import org.junit.Assert.*
import org.junit.Test

class ForumParserTest {
    @Test fun loginFormAcceptsReversedInputAttributes() {
        val form = ForumParser.loginForm("""<form action='member.php?loginhash=ABC123'><input value='a12f' name='formhash'></form>""")
        assertEquals("a12f", form.formhash)
        assertEquals("ABC123", form.loginhash)
    }

    @Test fun ajaxCdataIsNotAChallengeAndMessageIsReadable() {
        val body = """<?xml version='1.0'?><root><![CDATA[<div id='messagetext'><p>密码错误，请重试</p></div>]]></root>"""
        assertFalse(ForumParser.isChallenge(body, "text/xml"))
        assertEquals("密码错误，请重试", ForumParser.message(body))
    }

    @Test fun detectsScriptInterstitialWithoutBody() {
        assertTrue(ForumParser.isChallenge("<html><script>location.reload()</script></html>", "text/html"))
        assertFalse(ForumParser.isChallenge("<html><body><div class='comiis_space_tx'>资料</div></body></html>", "text/html"))
    }

    @Test fun profileReadsBothComiisStatLayoutsAndKeepsMissingUnknown() {
        val html = """<html><body><script>var discuz_uid='42';</script>
            <div class='comiis_space_tx'><h2>雨晨</h2><span class='kmlev'>正式会员</span></div>
            <ul class='pf_l'><li><em>帖子</em>12</li><li><em>回复</em>34</li></ul>
            <div class='comiis_space_profilejf'><ul><li><span class='f_0'>1,205</span>金币</li></ul></div>
            </body></html>"""
        val profile = ForumParser.profile(html)
        assertEquals("42", profile.uid)
        assertEquals("雨晨", profile.username)
        assertEquals(12L, profile.threads)
        assertEquals(34L, profile.replies)
        assertEquals(1205L, profile.gold)
        assertNull(profile.friends)
        assertNull(profile.credits)
    }

    @Test fun mobileHeaderCountsDoNotRequireAListWrapper() {
        val profile = ForumParser.profile("""<html><body><script>discuz_uid='9'</script><h2>用户</h2><div><em>35</em><p>积分</p></div></body></html>""")
        assertEquals(35L, profile.credits)
        assertNull(profile.threads)
    }

    @Test fun uidIsNeverUsedAsAPostCount() {
        val profile = ForumParser.profile("""<html><body><script>discuz_uid="17"</script><h2>用户</h2><div>UID 17 帖子</div></body></html>""")
        assertNull(profile.threads)
    }

    @Test fun friendsPageCountsOnlyActualFriendEntries() {
        val html = """<html><body><script>var discuz_uid = '154205';</script>
            <div class='comiis_friend_boxs'><div class='comiis_userlist01'>
              <li class='b_t'><a href='home.php?mod=space&amp;uid=1&amp;do=profile'>A</a></li>
              <li class='b_t'><a href='home.php?mod=space&amp;uid=2&amp;do=profile'>B</a></li>
              <li class='b_t'><a href='home.php?mod=space&amp;uid=3&amp;do=profile'>C</a></li>
              <li class='b_t'><a href='home.php?mod=space&amp;uid=4&amp;do=profile'>D</a></li>
              <li class='b_t'><a href='home.php?mod=space&amp;uid=5&amp;do=profile'>E</a></li>
              <li class='b_t'>Decorative row</li>
            </div></div><div class='comiis_notip' style='display:none'>没有相关用户列表</div>
            </body></html>"""
        assertEquals(5L, ForumParser.friendCount(html, "154205"))
        assertNull(ForumParser.friendCount(html, "999"))
    }

    @Test fun paginatedFriendsPageDoesNotClaimPartialCount() {
        val html = """<html><body><script>discuz_uid='17'</script>
            <div class='comiis_friend_boxs'><div class='comiis_userlist01'>
              <li class='b_t'><a href='home.php?mod=space&amp;uid=5&amp;do=profile'>Friend</a></li>
            </div><div class='pg'><a href='home.php?mod=space&amp;do=friend&amp;page=2'>2</a></div></div>
            </body></html>"""
        assertNull(ForumParser.friendCount(html, "17"))
    }

    @Test fun unknownOrUnauthenticatedFriendPageIsNotZero() {
        assertNull(ForumParser.friendCount("<html><body>验证码</body></html>", "154205"))
        assertNull(ForumParser.friendCount("<script>discuz_uid='154205'</script>", "154205"))
    }

    @Test(expected = SessionExpiredException::class)
    fun loginPageNeverBecomesAnAuthenticatedProfile() {
        ForumParser.profile("<html><body><input name='password'></body></html>")
    }
}
