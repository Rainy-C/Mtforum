package me.rain.mtforum.core.ui

import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.sp
import me.rain.mtforum.core.data.AgreementMarkup
import me.rain.mtforum.core.data.AgreementSpan
import me.rain.mtforum.core.data.AgreementStyle
import top.yukonga.miuix.kmp.theme.MiuixTheme

/** One trusted, bounded set of inline formats. No HTML, JavaScript or external fonts are executed. */
@Composable
internal fun AgreementRichText(
    source: String,
    modifier: Modifier = Modifier,
) {
    val formatted = remember(source) { AgreementMarkup.parse(source) }
    val defaultColor = MiuixTheme.colorScheme.onBackground
    val dark = defaultColor.luminance() > .5f
    val annotated = remember(formatted, dark) {
        buildAnnotatedString {
            append(formatted.text)
            formatted.spans.forEach { range ->
                addStyle(range.toSpanStyle(dark), range.start, range.end)
            }
        }
    }
    BasicText(
        text = annotated,
        modifier = modifier,
        style = TextStyle(color = defaultColor, fontSize = 15.sp, lineHeight = 25.sp),
    )
}

private fun AgreementSpan.toSpanStyle(dark: Boolean): SpanStyle = when (style) {
    AgreementStyle.Red -> SpanStyle(color = if (dark) Color(0xFFFF8A80) else Color(0xFFC62828), fontWeight = FontWeight.Medium)
    AgreementStyle.Highlight -> SpanStyle(
        background = if (dark) Color(0xFF615021) else Color(0xFFFFE8A3),
        color = if (dark) Color(0xFFFFF3CA) else Color(0xFF493900),
    )
    AgreementStyle.Bold -> SpanStyle(fontWeight = FontWeight.Bold)
    AgreementStyle.Underline -> SpanStyle(textDecoration = TextDecoration.Underline)
    AgreementStyle.Heading1 -> SpanStyle(fontWeight = FontWeight.Bold, fontSize = 21.sp)
    AgreementStyle.Heading2 -> SpanStyle(fontWeight = FontWeight.SemiBold, fontSize = 18.sp)
    AgreementStyle.Foreground -> SpanStyle(color = parseColor(argument.orEmpty(), dark))
    AgreementStyle.Background -> parseColor(argument.orEmpty(), dark).let { color ->
        SpanStyle(
            background = color,
            color = if (color.luminance() > .52f) Color(0xFF222222) else Color.White,
        )
    }
}

private fun parseColor(value: String, dark: Boolean): Color {
    if (value.startsWith('#') && value.length == 7) {
        return Color((0xFF000000L or value.drop(1).toLong(16)).toInt())
    }
    return when (value.lowercase()) {
        "red" -> if (dark) Color(0xFFFF8A80) else Color(0xFFC62828)
        "orange" -> if (dark) Color(0xFFFFB74D) else Color(0xFFC75B12)
        "yellow" -> if (dark) Color(0xFFFFE082) else Color(0xFF986B00)
        "green" -> if (dark) Color(0xFFA5D6A7) else Color(0xFF237C46)
        "blue" -> if (dark) Color(0xFF90CAF9) else Color(0xFF226FC0)
        "purple" -> if (dark) Color(0xFFCE93D8) else Color(0xFF8B3EA3)
        "gray", "grey" -> if (dark) Color(0xFFBDBDBD) else Color(0xFF616161)
        else -> Color.Unspecified
    }
}
