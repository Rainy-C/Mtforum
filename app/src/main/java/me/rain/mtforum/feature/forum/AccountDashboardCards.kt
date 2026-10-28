package me.rain.mtforum.feature.forum

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.widget.Toast
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import me.rain.mtforum.core.network.ContentBlock
import me.rain.mtforum.core.network.ContentFact
import me.rain.mtforum.core.network.ContentLink
import me.rain.mtforum.core.network.cleanAccountText
import me.rain.mtforum.core.ui.ActionButton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import top.yukonga.miuix.kmp.basic.Card
import top.yukonga.miuix.kmp.basic.Text
import top.yukonga.miuix.kmp.theme.MiuixTheme

private val creditAmount = Regex("""(?:总积分|金币|好评|信誉|威望|贡献|金钱|积分)\s*[:：]\s*([+-]?[\d,]+(?:\.\d+)?)""")
private val creditNames = setOf("总积分", "积分", "金币", "好评", "信誉", "威望", "贡献", "金钱")
private val transactionDate = Regex("""20\d{2}[-/.]\d{1,2}[-/.]\d{1,2}(?:\s+\d{1,2}:\d{2})?""")
private val transactionChange = Regex(
    """(?:金币|好评|信誉|威望|积分|贡献|金钱)\s*[:：]?\s*[+＋-]\s*[\d,]+(?:\.\d+)?|[+＋-]\s*[\d,]+(?:\.\d+)?\s*(?:金币|好评|信誉|威望|积分|贡献|金钱)"""
)

internal data class CreditSnapshot(
    val total: String?,
    val balances: List<ContentFact>,
    val formula: String?,
    val remainder: String,
)

/** Tolerate both Comiis text rows and structured Discuz table cells; never invent a balance. */
internal fun creditSnapshot(block: ContentBlock): CreditSnapshot {
    val raw = cleanAccountText(block.text)
    val extracted = buildList {
        block.facts.forEach { fact ->
            val label = cleanAccountText(fact.label).trimEnd(':', '：')
            val value = cleanAccountText(fact.value)
            if (label in creditNames && value.matches(Regex("""[+-]?[\d,]+(?:\.\d+)?"""))) {
                add(ContentFact(label, value))
            }
        }
        Regex("""(总积分|金币|好评|信誉|威望|贡献|金钱|积分)\s*[:：]\s*([+-]?[\d,]+(?:\.\d+)?)""")
            .findAll(raw).forEach { add(ContentFact(it.groupValues[1], it.groupValues[2])) }
    }.distinctBy { it.label }
    val total = extracted.firstOrNull { it.label in setOf("总积分", "积分") }?.value
    val balances = extracted.filterNot { it.label in setOf("总积分", "积分") }
    val formulaIndex = raw.indexOf("总积分=").takeIf { it >= 0 }
        ?: raw.indexOf("总积分＝").takeIf { it >= 0 }
    val formula = formulaIndex?.let { raw.substring(it).trim() }
    val remainder = raw.let { if (formulaIndex != null) it.substring(0, formulaIndex) else it }
        .replace(creditAmount, "")
        .lineSequence().map { it.trim(' ', ':', '：', '·') }
        .filter { it.isNotBlank() && it != "积分记录" && it != "积分中心" }
        .plus(block.facts.asSequence().filter { fact ->
            cleanAccountText(fact.label).trimEnd(':', '：') !in creditNames &&
                cleanAccountText(fact.value).isNotBlank()
        }.map { fact -> cleanAccountText(fact.label + ": " + fact.value) })
        .distinct().joinToString("\n")
    return CreditSnapshot(total, balances, formula, remainder)
}

@Composable
internal fun CreditDashboardCard(block: ContentBlock, onOpen: (ContentLink) -> Unit) {
    val data = creditSnapshot(block)
    val muted = MiuixTheme.colorScheme.onSurfaceVariantSummary
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            if (data.total != null) {
                Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Text("总积分", fontSize = 13.sp, color = muted)
                    Text(data.total, fontSize = 34.sp, lineHeight = 39.sp,
                        fontWeight = FontWeight.SemiBold)
                }
            } else {
                Text("积分概览", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            }
            if (data.balances.isNotEmpty()) {
                AccountSeparator()
                data.balances.chunked(2).forEach { pair ->
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        pair.forEach { fact ->
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Text(fact.label, fontSize = 12.sp, color = muted)
                                Text(fact.value, fontSize = 23.sp, lineHeight = 28.sp,
                                    fontWeight = FontWeight.SemiBold, maxLines = 1,
                                    overflow = TextOverflow.Ellipsis)
                            }
                        }
                        if (pair.size == 1) Spacer(Modifier.weight(1f))
                    }
                }
            }
            if (!data.formula.isNullOrBlank()) {
                AccountSeparator()
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("积分计算规则", fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                    Text(data.formula, fontSize = 13.sp, lineHeight = 21.sp, color = muted)
                }
            }
            if (data.remainder.isNotBlank()) {
                Text(data.remainder, fontSize = 14.sp, lineHeight = 22.sp, color = muted)
            }
            AccountLinkActions(block.links, onOpen)
        }
    }
}

internal data class GroupProgress(
    val current: String?,
    val levels: List<String>,
    val remaining: String?,
    val nextGroup: String?,
)

internal fun groupProgress(text: String): GroupProgress {
    val raw = cleanAccountText(text)
    val current = Regex("""我的等级\s*[:：]\s*([^\n]+)""").find(raw)
        ?.groupValues?.get(1)?.substringBefore("Lv.")?.trim()?.ifBlank { null }
    val levels = Regex("""Lv\.?\s*\d+""", RegexOption.IGNORE_CASE)
        .findAll(raw).map { it.value.replace(" ", "") }.distinct().take(2).toList()
    val upgrade = Regex("""还需要\s*([\d,]+)\s*积分\s*升级到\s*([^\s\n]+)""")
        .find(raw)
    return GroupProgress(current, levels, upgrade?.groupValues?.get(1), upgrade?.groupValues?.get(2))
}

@Composable
internal fun UserGroupDashboardCard(block: ContentBlock, onOpen: (ContentLink) -> Unit) {
    val raw = cleanAccountText(block.text)
    val progress = groupProgress(raw)
    val muted = MiuixTheme.colorScheme.onSurfaceVariantSummary
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text("当前用户组", fontSize = 13.sp, color = muted)
            if (progress.current != null) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(progress.current, Modifier.weight(1f), fontSize = 25.sp,
                        lineHeight = 31.sp, fontWeight = FontWeight.SemiBold)
                    progress.levels.firstOrNull()?.let { level ->
                        AccountTag(level)
                    }
                }
            } else {
                Text(raw.ifBlank { block.title }, fontSize = 16.sp, lineHeight = 24.sp)
            }
            if (progress.remaining != null && progress.nextGroup != null) {
                AccountSeparator()
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("下一等级", fontSize = 12.sp, color = muted)
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Text(progress.nextGroup, Modifier.weight(1f), fontSize = 17.sp,
                            fontWeight = FontWeight.SemiBold)
                        progress.levels.getOrNull(1)?.let { AccountTag(it) }
                    }
                    Text("还需 " + progress.remaining + " 积分升级", fontSize = 14.sp, color = muted)
                }
            } else if (progress.current != null) {
                val details = raw.lineSequence().filter { it.isNotBlank() &&
                    !it.startsWith("我的等级") && !it.matches(Regex("""Lv\.?\s*\d+""")) }
                    .joinToString("\n")
                if (details.isNotBlank()) Text(details, fontSize = 14.sp, lineHeight = 22.sp,
                    color = muted)
            }
            if (block.facts.isNotEmpty()) {
                block.facts.forEach { fact ->
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(cleanAccountText(fact.label), fontSize = 13.sp, color = muted)
                        Text(cleanAccountText(fact.value), Modifier.weight(1f), fontSize = 14.sp)
                    }
                }
            }
            AccountLinkActions(block.links, onOpen)
        }
    }
}

internal data class CreditTransaction(val amount: String?, val date: String?, val reason: String)

internal fun creditTransaction(block: ContentBlock): CreditTransaction {
    val raw = cleanAccountText(block.text).ifBlank {
        cleanAccountText(block.facts.joinToString("\n") { it.value })
    }
    val amountMatch = transactionChange.find(raw)
    val dateMatch = transactionDate.find(raw)
    val amount = amountMatch?.value?.replace(Regex("""\s+"""), " ")
    val date = dateMatch?.value
    val reason = raw.replace(transactionChange, "")
        .replace(transactionDate, "")
        .replace("积分记录", "")
        .lineSequence().map { it.trim(' ', '/', ':', '：', '-', '·') }
        .filter(String::isNotBlank).distinct().joinToString(" · ")
        .ifBlank { cleanAccountText(block.title).takeUnless { it == "积分记录" }.orEmpty() }
    return CreditTransaction(amount, date, reason)
}

@Composable
internal fun CreditHistoryCard(block: ContentBlock, onOpen: (ContentLink) -> Unit) {
    val transaction = creditTransaction(block)
    val muted = MiuixTheme.colorScheme.onSurfaceVariantSummary
    val dark = MiuixTheme.colorScheme.background.luminance() < .5f
    if (transaction.amount == null && transaction.date == null && block.links.isEmpty()) {
        // Comiis may output the selected history category as an otherwise empty row.
        Text(transaction.reason.ifBlank { "积分明细" }, Modifier.padding(horizontal = 4.dp, vertical = 2.dp),
            fontSize = 13.sp, color = muted)
        return
    }
    val isIncrease = transaction.amount?.contains('+') == true ||
        transaction.amount?.contains('＋') == true
    val isDecrease = transaction.amount?.contains('-') == true
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Text(transaction.reason.ifBlank { "积分变动" }, fontSize = 16.sp,
                        lineHeight = 23.sp, fontWeight = FontWeight.SemiBold)
                    transaction.date?.let { Text(it, fontSize = 12.sp, color = muted) }
                }
                transaction.amount?.let { amount ->
                    Text(amount, fontSize = 16.sp, fontWeight = FontWeight.SemiBold,
                        color = when {
                            isIncrease -> if (dark) Color(0xFF8DCEA6) else Color(0xFF236947)
                            isDecrease -> if (dark) Color(0xFFEF9691) else Color(0xFFB44440)
                            else -> MiuixTheme.colorScheme.onSurface
                        }, maxLines = 2)
                }
            }
            AccountLinkActions(block.links, onOpen)
        }
    }
}

internal data class PromotionDetails(
    val username: String?, val uid: String?, val reward: String?, val messages: List<String>,
)

internal fun promotionDetails(text: String): PromotionDetails {
    val raw = cleanAccountText(text)
    val lines = raw.lineSequence().map(String::trim).filter(String::isNotBlank).distinct().toList()
    val uid = Regex("""UID\s*[:：]\s*(\d+)""", RegexOption.IGNORE_CASE)
        .find(raw)?.groupValues?.get(1)
    val reward = Regex("""(?:金币|积分|好评|信誉)\s*[+＋-]\s*\d+""").find(raw)?.value
    val username = lines.firstOrNull { it.length in 2..36 && !it.contains(':') &&
        !it.contains('：') && !it.contains(' ') && !it.contains("邀请") &&
        !it.contains("推广") && !it.contains("奖励") && !it.contains("二维码") }
    val messages = lines.filterNot { it == username || it.startsWith("UID", ignoreCase = true) ||
        it in setOf("访问推广", "推广信息") }
    return PromotionDetails(username, uid, reward, messages)
}

/** Comiis draws this URL with jquery.qrcode; the QR is not an image in the HTML response. */
internal fun promotionInviteUrl(uid: String?): String? {
    if (uid == null || !uid.matches(Regex("""[1-9]\d{0,14}"""))) return null
    return "https://bbs.binmt.cc/?fromuid=$uid"
}

@Composable
internal fun PromotionDashboardCard(block: ContentBlock, onOpen: (ContentLink) -> Unit) {
    val data = promotionDetails(block.text)
    val muted = MiuixTheme.colorScheme.onSurfaceVariantSummary
    val context = LocalContext.current
    val inviteUrl = promotionInviteUrl(data.uid)
    val qrResult by produceState<Result<ImageBitmap>?>(initialValue = null, key1 = inviteUrl) {
        value = inviteUrl?.let { url ->
            withContext(Dispatchers.Default) { runCatching { createPromotionQr(url) } }
        }
    }
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(17.dp)) {
            Text("我的推广二维码", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            if (data.username != null || data.uid != null) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    data.username?.let { username ->
                        Text(username, fontSize = 25.sp, lineHeight = 32.sp,
                            fontWeight = FontWeight.SemiBold)
                    }
                    data.uid?.let { Text("UID " + it, fontSize = 13.sp, color = muted) }
                }
            }
            if (inviteUrl != null) {
                AccountSeparator()
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    BoxWithConstraints(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                        val side = (maxWidth - 48.dp).coerceIn(120.dp, 240.dp)
                        Box(Modifier.clip(RoundedCornerShape(22.dp)).background(Color.White)
                            .padding(14.dp), contentAlignment = Alignment.Center) {
                            val qr = qrResult?.getOrNull()
                            if (qr != null) {
                                Image(qr, "我的论坛访问推广二维码", Modifier.size(side),
                                    filterQuality = FilterQuality.None)
                            } else {
                                Box(Modifier.size(side), contentAlignment = Alignment.Center) {
                                    Text(if (qrResult?.isFailure == true) "二维码生成失败" else "正在生成二维码…",
                                        fontSize = 13.sp, color = Color.DarkGray)
                                }
                            }
                        }
                    }
                    Text(data.messages.firstOrNull { it.contains("扫码") && it.contains("邀请") }
                        ?: "邀请好友扫码加入论坛", fontSize = 14.sp, color = muted)
                    Text(inviteUrl, fontSize = 12.sp, color = muted,
                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        ActionButton("复制链接", Modifier.weight(1f), primary = false) {
                            context.getSystemService(ClipboardManager::class.java)
                                ?.setPrimaryClip(ClipData.newPlainText("MT Forum 访问推广", inviteUrl))
                            Toast.makeText(context, "邀请链接已复制", Toast.LENGTH_SHORT).show()
                        }
                        ActionButton("分享好友", Modifier.weight(1f)) {
                            val intent = Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(Intent.EXTRA_TEXT, inviteUrl)
                            }
                            context.startActivity(Intent.createChooser(intent, "分享邀请链接"))
                        }
                    }
                }
            } else {
                Text("无法获取推广 UID，请刷新后重试", fontSize = 14.sp, color = muted)
            }
            data.reward?.let { reward ->
                Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp))
                    .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .055f))
                    .padding(horizontal = 16.dp, vertical = 15.dp)) {
                    Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                        Text("邀请奖励", fontSize = 12.sp, color = muted)
                        Text(reward, fontSize = 22.sp, lineHeight = 27.sp,
                            fontWeight = FontWeight.SemiBold)
                    }
                }
            }
            val remainingMessages = data.messages.filterNot { inviteUrl != null &&
                it.contains("邀请") && it.contains("扫码") }
            if (remainingMessages.isNotEmpty()) {
                AccountSeparator()
                remainingMessages.forEach { message ->
                    Text(message, fontSize = 14.sp, lineHeight = 23.sp, color = muted)
                }
            } else if (data.username == null && data.uid == null) {
                Text(cleanAccountText(block.text), fontSize = 15.sp, lineHeight = 23.sp)
            }
            AccountLinkActions(block.links, onOpen)
        }
    }
}

@Composable
private fun AccountTag(value: String) {
    Box(Modifier.clip(RoundedCornerShape(11.dp))
        .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .07f))
        .padding(horizontal = 11.dp, vertical = 7.dp), contentAlignment = Alignment.Center) {
        Text(value, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun AccountSeparator() {
    Box(Modifier.fillMaxWidth().height(1.dp)
        .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .08f)))
}

@Composable
private fun AccountLinkActions(links: List<ContentLink>, onOpen: (ContentLink) -> Unit) {
    val actions = links.filter { cleanAccountText(it.text).isNotBlank() }.distinctBy { it.url }
    if (actions.isEmpty()) return
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        actions.forEach { link ->
            Box(Modifier.clip(RoundedCornerShape(13.dp))
                .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .07f))
                .clickable(role = Role.Button) { onOpen(link) }
                .heightIn(min = 48.dp).padding(horizontal = 14.dp, vertical = 11.dp),
                contentAlignment = Alignment.Center) {
                Text(cleanAccountText(link.text), fontSize = 13.sp, maxLines = 1)
            }
        }
    }
}
