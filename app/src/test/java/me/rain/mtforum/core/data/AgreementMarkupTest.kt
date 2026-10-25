package me.rain.mtforum.core.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgreementMarkupTest {
    @Test fun redTagsWorkWithBothClosingForms() {
        val canonical = AgreementMarkup.parse("使用 [red]特别注意[/red] 条款")
        val shorthand = AgreementMarkup.parse("使用 [red]特别注意[red] 条款")
        assertEquals("使用 特别注意 条款", canonical.text)
        assertEquals(canonical, shorthand)
        assertEquals(AgreementSpan(3, 7, AgreementStyle.Red), canonical.spans.single())
    }

    @Test fun nestedHeadingAndHighlightKeepVisibleTextClean() {
        val data = AgreementMarkup.parse("[h1]重要事项[/h1]\n[highlight]请仔细阅读 [b]隐私条款[/b][/highlight]")
        assertEquals("重要事项\n请仔细阅读 隐私条款", data.text)
        assertEquals(3, data.spans.size)
        assertTrue(data.spans.any { it.style == AgreementStyle.Heading1 && data.text.substring(it.start, it.end) == "重要事项" })
        assertTrue(data.spans.any { it.style == AgreementStyle.Highlight && data.text.substring(it.start, it.end) == "请仔细阅读 隐私条款" })
        assertTrue(data.spans.any { it.style == AgreementStyle.Bold && data.text.substring(it.start, it.end) == "隐私条款" })
    }

    @Test fun customColorsAndUnderlineAreSupported() {
        val data = AgreementMarkup.parse("[color=#D32F2F]红色[/color] [bg=yellow][u]高亮[/u][/bg]")
        assertEquals("红色 高亮", data.text)
        assertTrue(data.spans.any { it.style == AgreementStyle.Foreground && it.argument == "#D32F2F" })
        assertTrue(data.spans.any { it.style == AgreementStyle.Background && it.argument == "yellow" })
        assertTrue(data.spans.any { it.style == AgreementStyle.Underline })
    }

    @Test fun escapedAndUnknownTagsRemainLiteral() {
        val raw = AgreementMarkup.parse("教程：\\[red]词汇[/red]，以及 [unsupported]内容[/unsupported]")
        assertEquals("教程：[red]词汇[/red]，以及 [unsupported]内容[/unsupported]", raw.text)
        assertTrue(raw.spans.isEmpty())
    }

    @Test fun missingClosingOrInvalidColorNeverDeleteText() {
        val data = AgreementMarkup.parse("[red]提醒 [color=javascript:alert(1)]注意[/color]")
        assertEquals("[red]提醒 [color=javascript:alert(1)]注意[/color]", data.text)
        assertTrue(data.spans.isEmpty())
    }

    @Test fun formattingOnlyChangeDoesNotInvalidateExistingConsent() {
        val plain = "MT Forum 使用与隐私说明\n\n请保护账号安全。"
        val rich = "MT Forum 使用与隐私说明\n\n请保护[red]账号安全[/red]。"
        assertEquals(AgreementRepository.fingerprint(plain), AgreementRepository.fingerprint(rich))
        assertFalse(AgreementRepository.fingerprint(plain) == AgreementRepository.fingerprint(rich + "新增条款"))
    }
}
