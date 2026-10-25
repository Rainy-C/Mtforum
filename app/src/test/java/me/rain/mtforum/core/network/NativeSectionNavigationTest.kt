package me.rain.mtforum.core.network

import org.junit.Assert.*
import org.junit.Test

class NativeSectionNavigationTest {
    private val base = ForumRepository.BaseUrl

    @Test fun socialTabsAreInTheSamePage() {
        val friends = "$base/home.php?mod=space&do=friend&mobile=2"
        val following = "$base/home.php?mod=follow&do=following&mobile=2"
        val followers = "$base/home.php?mod=follow&do=follower&mobile=2"
        val requests = "$base/home.php?mod=spacecp&ac=friend&op=request&mobile=2"
        assertEquals("social", nativeSectionGroup(friends))
        assertTrue(isNativeSectionTab(friends, following))
        assertTrue(isNativeSectionTab(following, followers))
        assertTrue(isNativeSectionTab(followers, requests))
        assertFalse(isNativeSectionTab(friends, "$base/thread-234-1-1.html"))
    }

    @Test fun otherAccountFiltersSwitchWithoutPushingRoutes() {
        val thread = "$base/home.php?mod=space&do=thread&view=me&type=thread"
        val reply = "$base/home.php?mod=space&do=thread&view=me&type=reply"
        val favorite = "$base/home.php?mod=space&do=favorite&view=me&type=all"
        val favoriteBoard = "$base/home.php?mod=space&do=favorite&view=me&type=forum"
        assertTrue(isNativeSectionTab(thread, reply))
        assertTrue(isNativeSectionTab(favorite, favoriteBoard))
        assertFalse(isNativeSectionTab(thread, favorite))
    }

    @Test fun userProfilesAndMutationsNeverSwitchInsideAccountTabs() {
        val friends = "$base/home.php?mod=space&do=friend"
        assertFalse(isNativeSectionTab(friends, "$base/home.php?mod=space&do=friend&uid=123"))
        assertFalse(isNativeSectionTab(friends, "$base/home.php?mod=spacecp&ac=friend&op=delete&formhash=abc"))
        assertFalse(isNativeSectionTab(friends, "https://example.com/home.php?mod=space&do=friend"))
    }

    @Test fun pagingRemainsInPlaceWithoutSwallowingOtherLinks() {
        val first = "$base/home.php?mod=space&do=friend&mobile=2&page=1"
        val second = "$base/home.php?mod=space&do=friend&mobile=2&page=2"
        assertTrue(isNativePageChange(first, second))
        assertTrue(isNativePageChange(first, "$base/home.php?page=2&do=friend&mod=space&mobile=2"))
        assertFalse(isNativePageChange(first, "$base/home.php?mod=space&do=favorite&page=2"))
        assertFalse(isNativePageChange(first, "$base/thread-20-1-1.html"))
    }
    @Test fun favoriteTabsAreStableAcrossEmptyCategories() {
        val all = "$base/home.php?mod=space&do=favorite&view=me&type=all"
        val tabs = favoriteSectionLinks(all)
        assertEquals(listOf("全部收藏", "帖子", "版块", "群组"), tabs.map { it.text })
        assertEquals(4, tabs.map { it.url }.distinct().size)
        assertTrue(tabs.all { isNativeSectionTab(all, it.url) })
        assertEquals(0, favoriteSectionIndex(all))
        assertEquals(2, favoriteSectionIndex(tabs[2].url))
        assertEquals(3, favoriteSectionIndex(tabs[3].url))
        assertTrue(tabs.all { "view=me" in it.url })
        assertTrue(tabs.all { "page=" !in it.url })
    }

    @Test fun favoriteFallbackNavigationIsFilteredButEmptyMessageIsNot() {
        val page = "$base/home.php?mod=space&do=favorite&type=forum"
        val tabs = favoriteSectionLinks(page)
        // Fallback HTML parser represents a tab row as an otherwise blank text block.
        assertTrue(isFavoriteTabNavigation(ContentBlock("", links = tabs), page))
        assertTrue(isFavoriteTabNavigation(ContentBlock("", links = tabs,
            kind = NativeContentKind.Navigation), page))
        assertFalse(isFavoriteTabNavigation(ContentBlock("您还没有添加任何收藏"), page))
        assertFalse(isFavoriteTabNavigation(ContentBlock("帖子", links = listOf(
            ContentLink("查看帖子", "$base/thread-172220-1-1.html"))), page))
    }
}
