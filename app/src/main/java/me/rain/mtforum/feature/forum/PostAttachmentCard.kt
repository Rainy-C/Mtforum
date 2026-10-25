package me.rain.mtforum.feature.forum

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import me.rain.mtforum.core.network.PostAttachments
import org.jsoup.nodes.Element
import top.yukonga.miuix.kmp.basic.Icon
import top.yukonga.miuix.kmp.basic.Text
import top.yukonga.miuix.kmp.icon.MiuixIcons
import top.yukonga.miuix.kmp.icon.icons.useful.*
import top.yukonga.miuix.kmp.theme.MiuixTheme

/** Never display a Discuz file-type icon as a full-width image. */
@Composable
internal fun PostAttachmentCard(
    node: Element,
    link: String?,
    onOpen: (String, String) -> Unit,
) {
    val title = PostAttachments.fileTitle(node)
    val details = PostAttachments.fileDetails(node, title)
    val color = MiuixTheme.colorScheme
    val radius = RoundedCornerShape(16.dp)
    Row(
        Modifier.fillMaxWidth()
            .clip(radius)
            .background(color.onSurface.copy(alpha = .045f))
            .clickable(enabled = link != null) { link?.let { onOpen(title, it) } }
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            Modifier.size(44.dp).clip(RoundedCornerShape(13.dp))
                .background(color.onSurface.copy(alpha = .065f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(MiuixIcons.Useful.Save, null, Modifier.size(23.dp), tint = color.onSurface)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title, fontSize = 14.sp, fontWeight = FontWeight.SemiBold,
                maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(
                details.ifBlank { if (link != null) "点击查看或下载附件" else "附件地址未提供" },
                fontSize = 12.sp, lineHeight = 17.sp, maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                color = color.onSurfaceVariantSummary,
            )
        }
        if (link != null) {
            Icon(MiuixIcons.Useful.Back, null, Modifier.size(18.dp).rotate(180f),
                tint = color.onSurfaceVariantSummary)
        }
    }
}
