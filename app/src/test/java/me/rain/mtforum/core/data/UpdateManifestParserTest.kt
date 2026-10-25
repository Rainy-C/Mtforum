package me.rain.mtforum.core.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class UpdateManifestParserTest {
    @Test
    fun extractsTheNoteBodyWithEntitiesAndBreaks() {
        val html = """
            <html><head><style>do not include this</style></head>
            <body><div class="wy-notes-wrapper"><time class="note-time">today</time>
            <div class="note-content"><br/>{<br/>&nbsp;&nbsp;&quot;schema_version&quot;: 1,<br/>
            &nbsp;&nbsp;&quot;app_id&quot;: &quot;me.rain.mtforum&quot;<br/>}<br/></div></div></body></html>
        """.trimIndent()
        val json = UpdateManifestParser.extractJson(html)!!
        assertTrue(json.startsWith("{"))
        assertTrue(json.contains("\"schema_version\": 1"))
        assertTrue(json.contains("\"app_id\": \"me.rain.mtforum\""))
        assertFalse(json.contains("do not include this"))
        assertEquals('}', json.last())
    }

    @Test fun rejectsExpiredOrUnrelatedSharePages() {
        assertNull(UpdateManifestParser.extractJson("<html><body>分享已失效</body></html>"))
        assertNull(UpdateManifestParser.extractJson("<div class='note-content'>{}</div>"))
    }

    @Test fun rejectsPlaceholdersAndUnsafeDownloadSchemes() {
        assertNull(UpdateManifestParser.trustedExternalUrl("https://example.com/releases"))
        assertNull(UpdateManifestParser.trustedExternalUrl("http://example.org/file.apk"))
        assertNull(UpdateManifestParser.trustedExternalUrl("javascript:alert(1)"))
        assertEquals(
            "https://download.example.org/releases/0.3.1",
            UpdateManifestParser.trustedExternalUrl("https://download.example.org/releases/0.3.1"),
        )
    }
}
