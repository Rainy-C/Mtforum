package me.rain.mtforum.feature.forum

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import me.rain.mtforum.core.network.*
import top.yukonga.miuix.kmp.basic.Card
import top.yukonga.miuix.kmp.basic.Text
import top.yukonga.miuix.kmp.theme.MiuixTheme

/** One compact account row; actions use actual server URLs and keep their original callbacks. */
@Composable
internal fun CompactPersonCard(block: ContentBlock, onOpen: (ContentLink) -> Unit) {
    val profile = block.primaryLink
    val name = block.title.ifBlank { profile?.text ?: "论坛用户" }
    val detail = block.text.lineSequence()
        .map(::cleanAccountText).filter { it.isNotBlank() && it != name }
        .firstOrNull { !it.contains("分组 打招呼") && it.length < 120 }
        .orEmpty()
    val actions = block.links.filter { it.url != profile?.url && it.text.isNotBlank() }
        .distinctBy { it.url }
    val contentModifier = if (profile != null) Modifier.clip(RoundedCornerShape(24.dp))
        .clickable(role = Role.Button) { onOpen(profile) } else Modifier
    Card(Modifier.fillMaxWidth().then(contentModifier)) {
        Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Avatar(block.image, name, 44)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(name, fontSize = 16.sp, fontWeight = FontWeight.SemiBold,
                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (detail.isNotBlank()) Text(detail, fontSize = 12.sp,
                        color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            if (actions.isNotEmpty()) {
                Row(
                    Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    actions.forEach { action ->
                        val label = cleanAccountText(action.text)
                            .takeIf { it.isNotBlank() } ?: return@forEach
                        Box(
                            Modifier.clip(RoundedCornerShape(12.dp))
                                .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .06f))
                                .clickable(role = Role.Button) { onOpen(action) }
                                .padding(horizontal = 12.dp, vertical = 7.dp),
                            contentAlignment = Alignment.Center,
                        ) { Text(label, fontSize = 12.sp, maxLines = 1) }
                    }
                }
            }
        }
    }
}

/** Comiis usergroup pages vary by template. Render only actual text and extracted data. */
@Composable
internal fun AccountInfoCard(block: ContentBlock, onOpen: (ContentLink) -> Unit, isCredit: Boolean) {
    val title = cleanAccountText(block.title).takeIf { it.isNotBlank() }
        ?: if (isCredit) "积分记录" else "用户组资料"
    val summary = cleanAccountText(block.text)
        .removePrefix(title).trimStart(' ', ':', '：', '\n')
    val fields = block.facts.distinctBy { it.label to it.value }
    val allValues = (fields.joinToString(" ") { it.value } + " " + summary)
    val summaryIsJustFields = fields.isNotEmpty() && fields.all { summary.contains(cleanAccountText(it.value)) }
    val creditChange = if (isCredit) {
        Regex("[+-]?[0-9][0-9,]*(?:\\.[0-9]+)?\\s*(?:积分|金币|贡献|威望|金钱)")
            .find(allValues)?.value ?: Regex("(?:积分|金币|贡献|威望|金钱)\\s*[:：]?\\s*[+-]?[0-9][0-9,]*")
            .find(allValues)?.value
    } else null
    val date = if (isCredit) Regex("20\\d{2}[-/]\\d{1,2}[-/]\\d{1,2}(?:\\s+\\d{1,2}:\\d{2})?")
        .find(allValues)?.value else null
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(
                    Modifier.size(42.dp).clip(RoundedCornerShape(14.dp))
                        .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .06f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(if (isCredit) "积" else "组", fontWeight = FontWeight.SemiBold,
                        fontSize = if (isCredit) 20.sp else 17.sp)
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(title, fontSize = 16.sp, fontWeight = FontWeight.SemiBold,
                        maxLines = 2, overflow = TextOverflow.Ellipsis)
                    if (date != null) {
                        Text(date, fontSize = 12.sp,
                            color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                    } else if (summary.isNotBlank() && fields.isNotEmpty() && !summaryIsJustFields) {
                        Text(summary, fontSize = 12.sp,
                            color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                            maxLines = 2, overflow = TextOverflow.Ellipsis)
                    }
                }
                if (creditChange != null) {
                    Text(creditChange, fontSize = 14.sp, fontWeight = FontWeight.SemiBold,
                        color = if (creditChange.startsWith("-")) Color(0xFFB95F54)
                            else MiuixTheme.colorScheme.onSurface)
                }
            }
            if (fields.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    fields.forEach { fact ->
                        val text = cleanAccountText(fact.value)
                        if (text.isNotBlank() && text != title && text != date && text != creditChange) {
                            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top,
                                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                if (fact.label.isNotBlank()) Text(
                                    cleanAccountText(fact.label), Modifier.widthIn(max = 110.dp),
                                    fontSize = 12.sp, color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                                Text(text, Modifier.weight(1f), fontSize = 14.sp,
                                    fontWeight = FontWeight.Medium)
                            }
                        }
                    }
                }
            } else if (summary.isNotBlank()) {
                Text(summary, fontSize = 14.sp, lineHeight = 22.sp)
            }
            if (block.links.isNotEmpty()) {
                Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    block.links.distinctBy { it.url }.forEach { link ->
                        Box(Modifier.clip(RoundedCornerShape(12.dp))
                            .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .06f))
                            .clickable { onOpen(link) }
                            .padding(horizontal = 11.dp, vertical = 8.dp)) {
                            Text(cleanAccountText(link.text), fontSize = 12.sp)
                        }
                    }
                }
            }
        }
    }
}

/** Compact two-column overview for credit balances and counters, sourced only from facts. */
@Composable
internal fun CreditOverviewCard(facts: List<ContentFact>) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        facts.chunked(2).forEach { pair ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                pair.forEach { fact ->
                    Card(Modifier.weight(1f)) {
                        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 18.dp),
                            verticalArrangement = Arrangement.spacedBy(7.dp)) {
                            Text(cleanAccountText(fact.label), fontSize = 12.sp,
                                color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                                maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(cleanAccountText(fact.value), fontSize = if (fact.value.length <= 14) 19.sp else 14.sp,
                                lineHeight = 24.sp, fontWeight = FontWeight.SemiBold,
                                maxLines = 3, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
                if (pair.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}
