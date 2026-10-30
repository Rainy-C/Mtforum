package me.rain.mtforum.core.network

import org.junit.Assert.*
import org.junit.Test

class AccountProfileNavigationTest {
    private val base = "https://bbs.binmt.cc/home.php?mod=spacecp&ac=profile&op=base"
    private val contact = "https://bbs.binmt.cc/home.php?mod=spacecp&ac=profile&op=contact"
    private val password = "https://bbs.binmt.cc/home.php?mod=spacecp&ac=profile&op=password"

    @Test fun profileSectionsAreTabsNotNewRoutes() {
        assertEquals("account-profile", nativeSectionGroup(base))
        assertTrue(isNativeSectionTab(base, contact))
        assertTrue(isNativeSectionTab(contact, password))
        assertFalse(isNativeSectionTab(base, "https://other.example.com/settings"))
    }
}
