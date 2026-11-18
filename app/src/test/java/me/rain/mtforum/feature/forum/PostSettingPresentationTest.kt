package me.rain.mtforum.feature.forum

import me.rain.mtforum.core.network.RemoteField
import org.junit.Assert.*
import org.junit.Test

class PostSettingPresentationTest {
    @Test fun knownDiscuzFieldsAreClearlyNamed() {
        assertEquals("阅读权限", PostSettingPresentation.label(
            RemoteField("readperm", "填写内容", "text", "0")))
        assertEquals("主题售价（金币）", PostSettingPresentation.label(
            RemoteField("price", "填写内容", "text", "0")))
        assertEquals("收到回复时通知我", PostSettingPresentation.label(
            RemoteField("allownoticeauthor", "", "checkbox", "1")))
    }
    @Test fun technicalFieldsDoNotAppearAsSettings() {
        assertFalse(PostSettingPresentation.isVisible(
            RemoteField("formhash", "formhash", "hidden", "x")))
        assertFalse(PostSettingPresentation.isVisible(
            RemoteField("message", "内容", "textarea", "")))
        assertTrue(PostSettingPresentation.isVisible(
            RemoteField("readperm", "填写内容", "text", "0")))
    }
    @Test fun unknownForumFieldsRetainRealLabels() {
        assertEquals("板块自定义字段", PostSettingPresentation.label(
            RemoteField("custom-1", "板块自定义字段", "text", "")))
    }
}
