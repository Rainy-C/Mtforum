package me.rain.mtforum.feature.forum

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.layout.ContentScale
import coil.compose.AsyncImage
import me.rain.mtforum.core.ui.LocalShowImages
import me.rain.mtforum.core.ui.icons.MiuixNavigationIcons
import me.rain.mtforum.core.ui.icons.BankCards
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import me.rain.mtforum.core.network.ContentBlock
import me.rain.mtforum.core.network.ContentLink
import top.yukonga.miuix.kmp.basic.*
import top.yukonga.miuix.kmp.theme.MiuixTheme

internal data class MallExchange(
    val timestamp: String,
    val status: String,
    val username: String,
    val amount: String,
)

/**
 * The Comiis mall sometimes supplies its purchase history as ONE text node rather
 * than individual list rows. Match complete records only: an incomplete record is
 * left in the ordinary renderer instead of inventing a user or a price.
 */
internal fun parseMallExchanges(text: String): List<MallExchange> {
    val record = Regex(
        """(\d{1,2}[-/]\d{1,2}\s+\d{1,2}:\d{2})\s+(已兑换|兑换成功|未兑换|兑换中|兑换失败|已抢购|已发放)\s+(.+?)\s+(\d[\d,]*)\s*金币(?=\s|$)"""
    )
    return record.findAll(text.replace(Regex("""\s+"""), " "))
        .mapNotNull { match ->
            val user = match.groupValues[3].trim()
            if (user.isBlank() || user.length > 80) null
            else MallExchange(match.groupValues[1], match.groupValues[2], user, match.groupValues[4])
        }
        .toList()
}

/** Exchange confirmation is an explicit, non-mutating GET page. */
internal fun isMallConfirmationUrl(url: String): Boolean {
    val parsed = url.toHttpUrlOrNull() ?: return false
    return parsed.queryParameter("id") == "keke_integralmall:show_win" &&
        parsed.queryParameter("ac") == "xd"
}

/** A product page may contain several navigational anchors; prefer the actual item. */
internal fun mallProductTarget(block: ContentBlock): ContentLink? =
    block.primaryLink ?: block.links.firstOrNull {
        it.url.contains("keke_integralmall-view") ||
            (it.url.contains("keke_integralmall") && it.text.contains("查看"))
    }

@Composable
internal fun MallProductCard(block: ContentBlock, onOpen: (ContentLink) -> Unit) {
    val target = mallProductTarget(block) ?: block.links.firstOrNull {
        it.text.contains("抢购") || it.text.contains("兑换")
    }
    val title = block.title.ifBlank { "积分商品" }
    val facts = block.facts.filter { it.value.isNotBlank() }.distinctBy { it.label }
    Card(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(26.dp)).then(
            if (target != null) Modifier.clickable { onOpen(target) } else Modifier
        )
    ) {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                if (LocalShowImages.current && !block.image.isNullOrBlank()) {
                    AsyncImage(
                        block.image, title,
                        Modifier.size(88.dp).clip(RoundedCornerShape(20.dp)),
                        contentScale = ContentScale.Crop,
                    )
                } else {
                    Box(
                        Modifier.size(72.dp).clip(RoundedCornerShape(20.dp))
                            .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .055f)),
                        contentAlignment = Alignment.Center,
                    ) { Icon(MiuixNavigationIcons.BankCards, null, Modifier.size(34.dp)) }
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(title, fontSize = 18.sp, lineHeight = 25.sp,
                        fontWeight = FontWeight.SemiBold, maxLines = 3,
                        overflow = TextOverflow.Ellipsis)
                    if (facts.isNotEmpty()) {
                        facts.take(2).forEach { fact ->
                            Row(verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text(fact.label, fontSize = 12.sp,
                                    color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                                Text(fact.value, fontSize = if (fact.label == "价格") 16.sp else 13.sp,
                                    fontWeight = FontWeight.SemiBold, maxLines = 1,
                                    overflow = TextOverflow.Ellipsis)
                            }
                        }
                    }
                }
            }
            val description = block.text.trim().removePrefix(title).trim()
            if (description.isNotEmpty() && description != title) {
                Text(description, fontSize = 13.sp, lineHeight = 20.sp,
                    color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                    maxLines = 3, overflow = TextOverflow.Ellipsis)
            }
            if (target != null) {
                Button(
                    onClick = { onOpen(target) },
                    modifier = Modifier.fillMaxWidth(),
                    insideMargin = PaddingValues(horizontal = 14.dp, vertical = 12.dp),
                    colors = ButtonDefaults.buttonColorsPrimary(),
                ) {
                    Text(target.text.ifBlank { "查看商品" }.take(12), fontSize = 15.sp, fontWeight = FontWeight.SemiBold,
                        color = MiuixTheme.colorScheme.onPrimary)
                }
            }
        }
    }
}

internal fun mallActions(block: ContentBlock): Boolean {
    val labels = block.links.map { it.text }
    return labels.size >= 2 && labels.any { it.contains("抢购") || it.contains("兑换") } &&
        labels.any { it.contains("卡密") || it.contains("状态") }
}

@Composable
internal fun MallActionsCard(block: ContentBlock, onOpen: (ContentLink) -> Unit) {
    val actions = block.links.filter { link ->
        listOf("抢购", "兑换", "卡密", "状态").any { it in link.text }
    }.distinctBy { it.url }.take(2)
    val headline = block.title.takeIf { it.isNotBlank() &&
        !it.contains("立即抢购") && !it.contains("查看卡密") } ?: "商品服务"
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(
                    Modifier.size(44.dp).clip(RoundedCornerShape(15.dp))
                        .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .06f)),
                    contentAlignment = Alignment.Center,
                ) { Icon(MiuixNavigationIcons.BankCards, null, Modifier.size(24.dp)) }
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(headline, fontSize = 19.sp, fontWeight = FontWeight.SemiBold,
                        maxLines = 2, overflow = TextOverflow.Ellipsis)
                    Text("兑换与卡密查询", fontSize = 12.sp,
                        color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                }
            }
            if (actions.isNotEmpty()) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    actions.forEachIndexed { index, link ->
                        Button(
                            onClick = { onOpen(link) },
                            modifier = Modifier.weight(1f),
                            insideMargin = PaddingValues(horizontal = 7.dp, vertical = 12.dp),
                            minWidth = 0.dp,
                            colors = if (index == 0) ButtonDefaults.buttonColorsPrimary()
                                     else ButtonDefaults.buttonColors(),
                        ) {
                            Text(link.text, maxLines = 1, overflow = TextOverflow.Ellipsis,
                                fontSize = 14.sp,
                                color = if (index == 0) MiuixTheme.colorScheme.onPrimary
                                        else MiuixTheme.colorScheme.onSecondaryVariant)
                        }
                    }
                }
            }
        }
    }
}

@Composable
internal fun MallExchangeHistoryCard(
    records: List<MallExchange>,
    links: List<ContentLink>,
    onOpen: (ContentLink) -> Unit,
) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(horizontal = 18.dp, vertical = 18.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("兑换记录", Modifier.weight(1f), fontSize = 20.sp,
                    fontWeight = FontWeight.SemiBold)
                Text("${records.size} 条", fontSize = 12.sp,
                    color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
            }
            records.forEachIndexed { index, entry ->
                if (index != 0) NativeHairline()
                val account = links.firstOrNull { it.text.trim() == entry.username }
                Column(
                    Modifier.fillMaxWidth().then(
                        if (account != null) Modifier.clip(RoundedCornerShape(12.dp))
                            .clickable { onOpen(account) } else Modifier
                    ).padding(vertical = 5.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Text(entry.timestamp, Modifier.weight(1f), fontSize = 12.sp,
                            color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                        val accent = if (entry.status == "已兑换" || entry.status == "兑换成功")
                            Color(0xFF6E8866) else MiuixTheme.colorScheme.onSurfaceVariantSummary
                        Box(
                            Modifier.clip(RoundedCornerShape(9.dp))
                                .background(accent.copy(alpha = .12f))
                                .padding(horizontal = 10.dp, vertical = 5.dp),
                        ) {
                            Text(entry.status, fontSize = 12.sp, color = accent, fontWeight = FontWeight.Medium)
                        }
                    }
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text(entry.username, Modifier.weight(1f), fontSize = 16.sp,
                            fontWeight = FontWeight.Medium, maxLines = 2,
                            overflow = TextOverflow.Ellipsis)
                        Text("${entry.amount} 金币", fontSize = 15.sp,
                            fontWeight = FontWeight.SemiBold)
                    }
                }
            }
            val extras = links.filterNot { link -> records.any { it.username == link.text.trim() } }
                .distinctBy { it.url }.take(4)
            if (extras.isNotEmpty()) {
                NativeHairline()
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    extras.forEach { link ->
                        Text(link.text, Modifier.weight(1f).clip(RoundedCornerShape(12.dp))
                            .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .05f))
                            .clickable { onOpen(link) }.padding(9.dp),
                            maxLines = 1, fontSize = 12.sp,
                            color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                            overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}
