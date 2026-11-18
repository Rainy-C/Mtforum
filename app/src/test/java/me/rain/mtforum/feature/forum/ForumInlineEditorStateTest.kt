package me.rain.mtforum.feature.forum

import org.junit.Assert.assertEquals
import org.junit.Test

class ForumInlineEditorStateTest {
    @Test fun formattingWhileEditorIsDetachedKeepsCursorInsideTags() {
        val editor = ForumInlineEditorState()
        editor.wrapSelection("[b]", "[/b]")
        assertEquals("[b][/b]", editor.markup)
        editor.insertText("你好")
        assertEquals("[b]你好[/b]", editor.markup)
    }

    @Test fun oldDraftRemainsVisibleAndCanBeFormattedWhileDetached() {
        val editor = ForumInlineEditorState()
        editor.restoreDraft("早上好")
        editor.wrapSelection("[quote]", "[/quote]")
        editor.insertText("继续")
        assertEquals("早上好[quote]继续[/quote]", editor.markup)
    }

    @Test fun offlineInsertionDoesNotLoseExistingText() {
        val editor = ForumInlineEditorState()
        editor.insertText("正文")
        editor.insertText(" 更多")
        assertEquals("正文 更多", editor.markup)
    }
}
