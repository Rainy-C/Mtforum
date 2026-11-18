package me.rain.mtforum.feature.forum

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import me.rain.mtforum.core.network.BBCodeParser
import me.rain.mtforum.core.network.ContentPost
import me.rain.mtforum.core.ui.ActionButton
import me.rain.mtforum.core.ui.PageHeader
import top.yukonga.miuix.kmp.basic.Text
import top.yukonga.miuix.kmp.theme.MiuixTheme

/** Convert BBCode exactly as in forum posts, preserving ordinary newlines. */
internal object ThreadDraftPreviewContent {
    private val preBlocks = Regex("""(?is)<pre\b[^>]*>.*?</pre>""")

    fun toHtml(markup: String): String {
        val html = BBCodeParser.toHtml(markup)
        return buildString {
            var start = 0
            preBlocks.findAll(html).forEach { match ->
                append(html.substring(start, match.range.first)
                    .replace("\r\n", "\n").replace("\n", "<br>"))
                append(match.value)
                start = match.range.last + 1
            }
            append(html.substring(start).replace("\r\n", "\n").replace("\n", "<br>"))
        }
    }
}

/**
 * A draft-only counterpart of the actual thread reader.
 * It intentionally shares ThreadPostCard/RichPostBody with the published thread
 * screen. It never sends a request or fabricates engagement counters.
 */
@Composable
internal fun ThreadDraftPreview(
    title: String,
    markup: String,
    boardName: String,
    categoryName: String?,
    author: String?,
    authorLevel: String?,
    authorAvatar: String?,
    uploadedImages: Map<String, String>,
    feedback: String?,
    canPublish: Boolean,
    onEdit: () -> Unit,
    onPublish: () -> Unit,
) {
    val draftPost = remember(markup, author, authorAvatar, authorLevel) {
        ContentPost(
            id = "local-draft",
            author = author?.takeIf { it.isNotBlank() } ?: "当前用户",
            authorUrl = null,
            avatar = authorAvatar,
            time = "尚未发布",
            floor = "",
            html = ThreadDraftPreviewContent.toHtml(markup),
            images = emptyList(),
            links = emptyList(),
            level = authorLevel,
        )
    }
    val hasAttachments = remember(markup) {
        Regex("""\[(?:attachimg|attach)\]\d+\[/(?:attachimg|attach)\]""")
            .containsMatchIn(markup)
    }

    Column(Modifier.fillMaxSize()) {
        PageHeader("帖子预览", onEdit) {
            Text("未发布", fontSize = 12.sp,
                color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
        }
        LazyColumn(
            modifier = Modifier.weight(1f).fillMaxWidth(),
            contentPadding = PaddingValues(
                start = 20.dp, top = 14.dp, end = 20.dp, bottom = 28.dp,
            ),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item(key = "draft-context") {
                Row(
                    Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        boardName.ifBlank { "当前板块" },
                        fontSize = 12.sp,
                        color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    categoryName?.takeIf { it.isNotBlank() }?.let { category ->
                        Text("·  $category", fontSize = 12.sp,
                            color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                            maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    Spacer(Modifier.weight(1f))
                    Text(
                        "草稿",
                        Modifier.clip(RoundedCornerShape(10.dp))
                            .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .07f))
                            .padding(horizontal = 10.dp, vertical = 5.dp),
                        fontSize = 11.sp,
                    )
                }
            }
            item(key = "draft-title") {
                Text(
                    title.trim().ifBlank { "尚未填写帖子标题" },
                    fontSize = 26.sp,
                    lineHeight = 36.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = if (title.isBlank())
                        MiuixTheme.colorScheme.onSurfaceVariantSummary
                    else MiuixTheme.colorScheme.onSurface,
                )
            }
            item(key = "draft-original-post") {
                ThreadPostCard(
                    post = draftPost,
                    compact = false,
                    onOpen = { _, _ -> },
                    onReply = null,
                    onReward = {},
                    showActions = false,
                )
            }
            if (uploadedImages.isNotEmpty()) item(key = "draft-uploads") {
                Column(
                    verticalArrangement = Arrangement.spacedBy(9.dp),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(
                        "本地附件图片",
                        fontSize = 12.sp,
                        color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                    )
                    uploadedImages.filterKeys { aid ->
                        markup.contains("[attachimg]$aid[/attachimg]")
                    }.values.forEach { uri ->
                        AsyncImage(
                            model = uri,
                            contentDescription = "草稿中上传的图片",
                            modifier = Modifier.fillMaxWidth()
                                .heightIn(max = 280.dp)
                                .clip(RoundedCornerShape(13.dp)),
                        )
                    }
                }
            }
            if (hasAttachments) item(key = "draft-attachment-note") {
                Text(
                    "附件在预览中显示为占位符，发布后会由论坛生成正式附件地址。",
                    fontSize = 12.sp,
                    lineHeight = 18.sp,
                    color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                )
            }
        }
        Column(
            Modifier.fillMaxWidth()
                .background(MiuixTheme.colorScheme.background)
                .navigationBarsPadding()
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(9.dp),
        ) {
            feedback?.let {
                Text(
                    it, fontSize = 12.sp,
                    color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                    maxLines = 2,
                )
            }
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                ActionButton("返回编辑", Modifier.weight(1f), primary = false, onClick = onEdit)
                ActionButton("发布帖子", Modifier.weight(1f), enabled = canPublish, onClick = onPublish)
            }
        }
    }
}
