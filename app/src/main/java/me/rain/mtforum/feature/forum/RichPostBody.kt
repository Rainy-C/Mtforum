package me.rain.mtforum.feature.forum

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.*
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import me.rain.mtforum.core.network.ContentParser
import me.rain.mtforum.core.network.PostAttachments
import me.rain.mtforum.core.network.PostBodyParser
import org.jsoup.nodes.Element
import org.jsoup.nodes.Node
import org.jsoup.nodes.TextNode
import top.yukonga.miuix.kmp.theme.MiuixTheme

@Composable
fun RichPostBody(
    html: String,
    onOpen: (String, String) -> Unit,
    compact: Boolean = false,
    images: List<String> = emptyList(),
    quoteDepth: Int = 0,
) {
    val sections = remember(html) { PostBodyParser.parse(html) }
    val context = LocalContext.current
    val safeOpen: (String, String) -> Unit = remember(onOpen, context) { { title: String, url: String ->
        if (url.startsWith("mailto:", ignoreCase = true) || url.startsWith("mqqwpa:", ignoreCase = true)) {
            runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
        } else onOpen(title, url)
    } }
    val color = MiuixTheme.colorScheme.onSurface
    Column(verticalArrangement = Arrangement.spacedBy(if (compact) 4.dp else 8.dp)) {
        sections.forEach { section ->
            val text = remember(section, safeOpen) { annotated(section.node, safeOpen) }
            val emojis = remember(section) { ContentParser.smileyUrls(section.node) }
            when (section.kind) {
                "image" -> PostImage(section.image!!, safeOpen, section.link)
                "code" -> PostCodeBlock(
                    code = PostBodyParser.codeText(section.node),
                    languageHint = section.node.attr("data-language").ifBlank {
                        section.node.attr("class").split(" ").firstOrNull { it.startsWith("language-") }
                            ?.removePrefix("language-")
                    },
                )
                "quote" -> {
                    val stroke = MiuixTheme.colorScheme.onSurface.copy(alpha = if (quoteDepth % 2 == 0) .38f else .23f)
                    Column(
                        Modifier.fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(MiuixTheme.colorScheme.onSurface.copy(alpha = if (quoteDepth % 2 == 0) .058f else .035f))
                            .drawBehind {
                                drawRect(stroke, topLeft = androidx.compose.ui.geometry.Offset.Zero,
                                    size = androidx.compose.ui.geometry.Size(3.dp.toPx(), size.height))
                            }
                            .padding(start = 13.dp, end = 12.dp, top = 10.dp, bottom = 10.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        // Never insert invented “引用” / “嵌套引用” labels: the
                        // forum often supplies its own reply header inside the quote.
                        if (quoteDepth < 8) {
                            RichPostBody(section.node.html(), safeOpen, compact = true, quoteDepth = quoteDepth + 1)
                        } else {
                            BasicText(section.node.text().take(8000),
                                style = TextStyle(fontSize = 13.sp, color = color))
                        }
                    }
                }
                "hide", "free" -> Column(
                    Modifier.fillMaxWidth().background(MiuixTheme.colorScheme.surface, RoundedCornerShape(12.dp))
                        .padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    BasicText(if (section.kind == "hide") {
                        val prompt = section.node.text()
                        when {
                            "回复" in prompt && ("隐藏" in prompt || "可见" in prompt) -> "回复后可见"
                            "登录" in prompt && ("隐藏" in prompt || "可见" in prompt) -> "登录后可见"
                            "购买" in prompt && ("隐藏" in prompt || "可见" in prompt) -> "购买后可见"
                            else -> "隐藏内容"
                        }
                    } else "免费内容",
                        style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
                            color = MiuixTheme.colorScheme.onSurfaceVariantSummary))
                    RichPostBody(section.node.html(), safeOpen, compact = true, quoteDepth = quoteDepth)
                }
                "attachment" -> PostAttachmentCard(section.node, section.link, safeOpen)
                "divider" -> Spacer(Modifier.fillMaxWidth().height(1.dp)
                    .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .15f)))
                "media" -> PostMedia(section.image.orEmpty(), section.node.normalName(), safeOpen)
                "table" -> PostTable(section.node, safeOpen)
                else ->
                    SelectionContainer {
                        RichText(
                            text = text,
                            emojis = emojis,
                            modifier = Modifier.fillMaxWidth(),
                            style =
                                TextStyle(
                                    fontSize = if (compact) 14.sp else 16.sp,
                                    lineHeight = if (compact) 21.sp else 27.sp,
                                    color = color,
                                    textAlign = section.align.toTextAlign(),
                                ),
                        )
                    }
            }
        }
        val inlineImages = sections.flatMap { block ->
            listOfNotNull(block.image) + block.node.select("img").mapNotNull { ContentParser.imageUrl(it) }
        }.toSet()
        images.distinct().filterNot { it in inlineImages || PostAttachments.isFileIconUrl(it) }
            .forEach { PostImage(it, safeOpen) }
    }
}

private fun String?.toTextAlign(): TextAlign =
    when (this) {
        "center" -> TextAlign.Center
        "right" -> TextAlign.End
        else -> TextAlign.Start
    }

@Composable
private fun RichText(
    text: AnnotatedString,
    emojis: List<String>,
    modifier: Modifier,
    style: TextStyle,
) {
    val emojiSize: TextUnit = if (style.fontSize.value <= 14f) 18.sp else 20.sp
    val inline =
        remember(emojis, emojiSize) {
            if (emojis.isEmpty()) emptyMap()
            else
                emojis.distinct().associateWith { url ->
                    InlineTextContent(Placeholder(emojiSize, emojiSize, PlaceholderVerticalAlign.Center)) {
                        coil.compose.SubcomposeAsyncImage(
                            model = url,
                            contentDescription = null,
                            modifier = Modifier.fillMaxSize(),
                        )
                    }
                }
        }
    BasicText(text, modifier, style = style, inlineContent = inline)
}

@Composable
private fun PostImage(url: String, onOpen: (String, String) -> Unit, linkedUrl: String? = null) {
    if (!me.rain.mtforum.core.ui.LocalShowImages.current) return
    coil.compose.SubcomposeAsyncImage(
        model = url,
        contentDescription = "帖子图片",
        modifier = Modifier.fillMaxWidth().heightIn(min = 80.dp, max = 480.dp)
            .clip(RoundedCornerShape(10.dp)).clickable { onOpen(if (linkedUrl != null) "链接" else "图片", linkedUrl ?: url) },
        contentScale = androidx.compose.ui.layout.ContentScale.FillWidth,
        loading = { top.yukonga.miuix.kmp.basic.Text("图片加载中…", Modifier.padding(12.dp)) },
        error = { top.yukonga.miuix.kmp.basic.Text("图片加载失败，点击查看", Modifier.padding(12.dp)) },
    )
}

internal fun annotated(node: Node, onOpen: (String, String) -> Unit): AnnotatedString =
    buildAnnotatedString {
        fun line() {
            val current = toAnnotatedString().text
            if (current.isNotEmpty() && !current.endsWith("\n\n")) append('\n')
        }
        fun walk(n: Node) {
            if (n is TextNode) {
                val value = n.wholeText.replace('\u00a0', ' ').replace(Regex("[ \t\r\n]+"), " ")
                val current = toAnnotatedString().text
                append(if (current.isEmpty() || current.last() == '\n' || current.last() == ' ') value.trimStart() else value)
                return
            }
            if (n !is Element) return
            val tag = n.tagName()
            if (tag in listOf("script", "style")) return
            if (tag == "img") {
                if (ContentParser.isAvatarImage(n)) return
                if (ContentParser.isSmileyImage(n)) {
                    ContentParser.imageUrl(n)?.let { appendInlineContent(it, "\uFFFC") }
                }
                return
            }
            if (tag == "br") {
                line()
                return
            }
            val link = if (tag == "a") {
                val href = n.attr("href")
                if (href.startsWith("mailto:", true) && href.length <= 260 ||
                    href.startsWith("mqqwpa:", true) && href.length <= 260) href
                else ContentParser.absolute(href)
            } else null
            val span = spanStyleOf(n)
            if (link != null)
                pushLink(
                    LinkAnnotation.Clickable(
                        link,
                        styles =
                            TextLinkStyles(SpanStyle(textDecoration = TextDecoration.Underline)),
                        linkInteractionListener = { onOpen(n.text(), link) },
                    )
                )
            if (span != null) pushStyle(span)
            if (tag == "li") append("• ")
            n.childNodes().forEach(::walk)
            if (span != null) pop()
            if (link != null) pop()
            if (tag in listOf("p", "li", "div")) line()
        }
        walk(node)
    }.let { value ->
        val start = value.text.indexOfFirst { !it.isWhitespace() }
        if (start < 0) AnnotatedString("")
        else value.subSequence(start, value.text.indexOfLast { !it.isWhitespace() } + 1)
    }

/** Maps the inline tags and CSS emitted by Discuz onto Compose text spans. */
private fun spanStyleOf(element: Element): SpanStyle? {
    val base = when (element.normalName()) {
        "b", "strong", "h1", "h2", "h3", "h4" -> SpanStyle(fontWeight = FontWeight.SemiBold)
        "code" -> SpanStyle(fontFamily = FontFamily.Monospace)
        "i", "em" -> SpanStyle(fontStyle = FontStyle.Italic)
        "u" -> SpanStyle(textDecoration = TextDecoration.Underline)
        "s", "del", "strike" -> SpanStyle(textDecoration = TextDecoration.LineThrough)
        else -> null
    }
    val style = element.attr("style")
    val foreground = parseColor(element.attr("color")) ?: cssColor(style, "color")
    val background = parseColor(element.attr("bgcolor")) ?: cssColor(style, "background-color")
        ?: cssColor(style, "background")
    val size = element.attr("size").toIntOrNull()?.takeIf { it in 1..7 }?.let(::fontSizeFor)
        ?: cssFontSize(style)
    val fontName = element.attr("face").ifBlank { cssValue(style, "font-family").orEmpty() }
    val font = when {
        fontName.contains("mono", true) || fontName.contains("courier", true) -> FontFamily.Monospace
        fontName.contains("serif", true) || fontName.contains("宋体", true) -> FontFamily.Serif
        fontName.contains("sans", true) || fontName.contains("黑体", true) || fontName.contains("微软雅黑", true) -> FontFamily.SansSerif
        else -> null
    }
    if (foreground == null && background == null && size == null && font == null) return base
    val extra = SpanStyle(
        color = foreground ?: Color.Unspecified,
        background = background ?: Color.Unspecified,
        fontSize = size ?: TextUnit.Unspecified,
        fontFamily = font,
    )
    return base?.merge(extra) ?: extra
}

private fun parseColor(raw: String): Color? {
    val value = raw.trim()
    val rgb = Regex("""rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})(?:\s*,\s*(0?\.\d+|1(?:\.0+)?))?\s*\)""", RegexOption.IGNORE_CASE).matchEntire(value)
    if (rgb != null) {
        val parts = rgb.groupValues
        val alpha = parts.getOrNull(4).orEmpty().toFloatOrNull()?.coerceIn(0f, 1f) ?: 1f
        return Color(parts[1].toInt().coerceIn(0, 255) / 255f,
            parts[2].toInt().coerceIn(0, 255) / 255f,
            parts[3].toInt().coerceIn(0, 255) / 255f, alpha)
    }
    if (!value.matches(Regex("""#[0-9a-fA-F]{3,8}|[a-zA-Z]{2,24}"""))) return null
    return runCatching { Color(android.graphics.Color.parseColor(value)) }.getOrNull()
}

private fun cssValue(style: String, key: String): String? =
    Regex("""(?:^|;)\s*${Regex.escape(key)}\s*:\s*([^;]+)""", RegexOption.IGNORE_CASE)
        .find(style)?.groupValues?.get(1)?.trim()?.trim('\'', '"')

private fun cssColor(style: String, key: String): Color? = cssValue(style, key)?.let(::parseColor)

private fun cssFontSize(style: String): TextUnit? {
    val raw = cssValue(style, "font-size") ?: return null
    val px = raw.removeSuffix("px").removeSuffix("pt").trim().toFloatOrNull() ?: return null
    return px.takeIf { it in 8f..48f }?.sp
}

private fun fontSizeFor(level: Int): TextUnit = when (level) {
    1 -> 12.sp
    2 -> 14.sp
    3 -> 16.sp
    4 -> 18.sp
    5 -> 24.sp
    6 -> 32.sp
    else -> 40.sp
}
