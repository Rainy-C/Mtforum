package me.rain.mtforum.feature.forum

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import me.rain.mtforum.core.network.*
import me.rain.mtforum.core.ui.ActionButton
import me.rain.mtforum.core.ui.LocalShowImages
import me.rain.mtforum.core.ui.icons.*
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import top.yukonga.miuix.kmp.basic.*
import top.yukonga.miuix.kmp.icon.MiuixIcons
import top.yukonga.miuix.kmp.icon.icons.useful.*
import top.yukonga.miuix.kmp.theme.MiuixTheme

/** Group adjacent account balances without changing their source order or values. */
internal fun nativeDisplayBlocks(blocks: List<ContentBlock>): List<ContentBlock> = buildList<ContentBlock> {
    for (block in blocks) {
        val previous = lastOrNull()
        if (previous?.kind == NativeContentKind.Facts && block.kind == NativeContentKind.Facts &&
            previous.facts.isNotEmpty() && block.facts.isNotEmpty() &&
            previous.links.isEmpty() && block.links.isEmpty()) {
            removeAt(lastIndex)
            add(previous.copy(facts = previous.facts + block.facts))
        } else add(block)
    }
}

/** The credit dashboard and promotion page are single pieces of information.
 * Keep the site's original data and links, but avoid a separate card for every HTML fragment.
 */
internal fun accountDisplayBlocks(blocks: List<ContentBlock>, page: String): List<ContentBlock> {
    val url = page.toHttpUrlOrNull() ?: return blocks
    val creditHome = url.queryParameter("ac") == "credit" &&
        url.queryParameter("op") in setOf(null, "base")
    val promotion = url.queryParameter("ac") == "promotion"
    if (!creditHome && !promotion) return blocks
    val isSummary: (ContentBlock) -> Boolean = { block ->
        block.kind in setOf(NativeContentKind.Text, NativeContentKind.Facts,
            NativeContentKind.CreditRecord, NativeContentKind.UserGroup) &&
            block.primaryLink == null && block.image == null &&
            (block.text.isNotBlank() || block.facts.isNotEmpty())
    }
    val summaries = blocks.filter(isSummary)
    if (summaries.size < 2) return blocks
    val merged = ContentBlock(
        text = summaries.joinToString("\n") { it.text },
        title = "",
        links = summaries.flatMap { it.links }.distinctBy { it.url },
        kind = if (creditHome) NativeContentKind.Facts else NativeContentKind.Text,
        facts = summaries.flatMap { it.facts }.distinctBy { it.label to it.value },
    )
    val first = blocks.indexOfFirst(isSummary)
    return buildList {
        blocks.forEachIndexed { index, block ->
            if (index == first) add(merged)
            if (!isSummary(block)) add(block)
        }
    }
}

@Composable
internal fun NativeContentItem(block: ContentBlock, page: String, onOpen: (ContentLink) -> Unit) {
    if (block.kind == NativeContentKind.Rank) {
        RankContentCard(block, onOpen)
        return
    }
    if (block.kind == NativeContentKind.Person) {
        CompactPersonCard(block, onOpen)
        return
    }
    val url = page.toHttpUrlOrNull()
    val creditPage = url?.queryParameter("ac") == "credit"
    val groupPage = url?.queryParameter("ac") == "usergroup"
    val creditHome = creditPage && url?.queryParameter("op") in setOf(null, "base")
    val creditHistory = creditPage && url?.queryParameter("op") in setOf("log", "loglist", "record")
    if (creditHome && block.kind in setOf(NativeContentKind.Facts, NativeContentKind.Text,
            NativeContentKind.CreditRecord) &&
        (block.text.isNotBlank() || block.facts.isNotEmpty())) {
        CreditDashboardCard(block, onOpen)
        return
    }
    if (url?.queryParameter("ac") == "promotion" && block.kind == NativeContentKind.Text) {
        PromotionDashboardCard(block, onOpen)
        return
    }
    if (creditHistory && block.kind in setOf(NativeContentKind.CreditRecord, NativeContentKind.Text,
            NativeContentKind.Facts)) {
        CreditHistoryCard(block, onOpen)
        return
    }
    if (groupPage && block.kind in setOf(NativeContentKind.UserGroup, NativeContentKind.Text)) {
        UserGroupDashboardCard(block, onOpen)
        return
    }
    if (block.kind in setOf(NativeContentKind.CreditRecord, NativeContentKind.UserGroup) ||
        (creditPage || groupPage) && block.kind == NativeContentKind.Text &&
        block.text.isNotBlank() && block.links.none { isNativeSectionTab(page, it.url) }) {
        AccountInfoCard(block, onOpen, isCredit = creditPage)
        return
    }
    if (page.contains("keke_integralmall", ignoreCase = true)) {
        val exchanges = androidx.compose.runtime.remember(block.text) { parseMallExchanges(block.text) }
        if (exchanges.isNotEmpty()) {
            MallExchangeHistoryCard(exchanges, block.links, onOpen)
            return
        }
        if (mallActions(block)) {
            MallActionsCard(block, onOpen)
            return
        }
        if (block.kind == NativeContentKind.Product) {
            MallProductCard(block, onOpen)
            return
        }
    }
    if (block.kind == NativeContentKind.Navigation || block.text.isBlank() && block.links.isNotEmpty()) {
        NativeNavigation(block.links, page, onOpen)
        return
    }
    if (block.kind == NativeContentKind.Facts && block.facts.isNotEmpty()) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (creditPage) CreditOverviewCard(block.facts)
            else NativeFacts(block.facts)
            if (block.links.isNotEmpty()) NativeLinkActions(block.links, onOpen)
        }
        return
    }
    // Discuz favorite lists contain a title and thread URL, not author, avatar or
    // engagement metrics. Use a purpose-built compact entry instead of empty TopicCard chrome.
    if (page.toHttpUrlOrNull()?.queryParameter("do") == "favorite" &&
        block.kind == NativeContentKind.Thread) {
        val favoriteTarget = block.primaryLink ?: block.links.firstOrNull {
            ContentParser.topicId(it.url) != null && !ContentParser.isMutationUrl(it.url)
        }
        if (favoriteTarget != null) {
            FavoriteThreadCard(block.title.ifBlank { favoriteTarget.text }, favoriteTarget, onOpen)
            return
        }
    }
    // Forum activity / notice lists share the exact same topic-card component as Home.
    // Avoid rendering the source HTML's author, follow button, level and timestamp
    // as separate text lines and duplicate action chips.
    if (block.kind == NativeContentKind.Thread || block.kind == NativeContentKind.Notice) {
        val target = block.primaryLink ?: block.links.firstOrNull { link ->
            ContentParser.topicId(link.url) != null && !ContentParser.isMutationUrl(link.url)
        }
        if (target != null) {
            val meta = block.feedMeta
            val title = block.title.ifBlank { target.text.ifBlank { "消息通知" } }
            val notice = block.kind == NativeContentKind.Notice
            val summary = if (notice) {
                val body = nativeSummary(block, title)
                val time = meta?.time.orEmpty()
                if (time.isBlank()) body else body.replace(time, "").trim()
            } else ""
            val author = meta?.author.orEmpty().ifBlank { if (notice) "论坛通知" else "" }
            val topic = Topic(
                id = ContentParser.topicId(target.url) ?: target.url,
                title = title,
                url = target.url,
                author = author,
                authorUrl = meta?.authorUrl,
                avatar = meta?.avatar,
                forum = meta?.forum.orEmpty(),
                time = meta?.time.orEmpty(),
                excerpt = summary,
                likes = meta?.likes,
                replies = meta?.replies,
                views = meta?.views,
                hasHiddenContent = block.hasHiddenContent,
            )
            TopicCard(
                topic = topic,
                repository = null,
                onAuthor = meta?.authorUrl?.let { authorUrl ->
                    { onOpen(ContentLink(author, authorUrl)) }
                },
                showStats = !notice && listOf(meta?.likes, meta?.replies, meta?.views).any { it != null },
            ) { onOpen(target) }
            // Account activity lists should render ONE topic card per entry.
            // Raw forum rows also contain numeric action links ("0", "2" etc.) that
            // are NOT extra posts. Never draw them as detached buttons below a card.
            return
        }
    }
    val target = block.primaryLink ?: block.links.firstOrNull {
        block.title.isNotBlank() && it.text == block.title && !ContentParser.isMutationUrl(it.url)
    }
    val rowModifier = if (target != null)
        Modifier.clip(RoundedCornerShape(26.dp)).clickable(role = Role.Button) { onOpen(target) }
        else Modifier
    Card(Modifier.fillMaxWidth().then(rowModifier)) {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                if (block.kind == NativeContentKind.Rank && block.rank != null) {
                    RankBadge(block.rank)
                }
                if (block.kind == NativeContentKind.Product) {
                    if (LocalShowImages.current && block.image != null)
                        AsyncImage(block.image, block.title, Modifier.size(84.dp).clip(RoundedCornerShape(16.dp)),
                            contentScale = ContentScale.Crop)
                } else if (block.kind in setOf(NativeContentKind.Person, NativeContentKind.Rank, NativeContentKind.Notice)) {
                    if (block.image != null && LocalShowImages.current) Avatar(block.image, block.title, if (block.kind == NativeContentKind.Rank) 48 else 44)
                    else if (block.kind == NativeContentKind.Notice)
                        Box(Modifier.size(44.dp).clip(RoundedCornerShape(14.dp))
                            .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .05f)), Alignment.Center) {
                            Icon(MiuixNavigationIcons.Messages, null, Modifier.size(22.dp),
                                tint = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                        }
                    else Avatar(null, block.title, if (block.kind == NativeContentKind.Rank) 48 else 44)
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                    val title = block.title.ifBlank {
                        when (block.kind) {
                            NativeContentKind.Notice -> "消息通知"
                            else -> block.primaryLink?.text.orEmpty()
                        }
                    }
                    if (title.isNotBlank())
                        Text(title, fontSize = 16.sp, lineHeight = 23.sp, fontWeight = FontWeight.SemiBold,
                            maxLines = if (block.kind == NativeContentKind.Person) 1 else 3,
                            overflow = TextOverflow.Ellipsis)
                    if (block.hasHiddenContent) HiddenContentBadge()
                    val summary = nativeSummary(block, title)
                    if (summary.isNotBlank()) {
                        if (block.kind == NativeContentKind.Text) SelectionContainer {
                            Text(summary, fontSize = 15.sp, lineHeight = 24.sp)
                        } else Text(summary, fontSize = 14.sp, lineHeight = 22.sp,
                            color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                            maxLines = when (block.kind) {
                                NativeContentKind.Person, NativeContentKind.Rank -> 2
                                NativeContentKind.Product -> 2
                                else -> 4
                            }, overflow = TextOverflow.Ellipsis)
                    }
                    block.facts.forEach { fact ->
                        Text(fact.value, fontSize = if (fact.label == "价格") 19.sp else 12.sp,
                            fontWeight = if (fact.label == "价格") FontWeight.SemiBold else FontWeight.Normal,
                            color = if (fact.label == "价格") MiuixTheme.colorScheme.onSurface
                                else MiuixTheme.colorScheme.onSurfaceVariantSummary)
                    }
                }
                if (target != null) {
                    if (block.kind == NativeContentKind.Rank) RankArrowChip()
                    else Icon(MiuixIcons.Useful.Back, null, Modifier.padding(top = 3.dp).size(18.dp).rotate(180f),
                        tint = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                }
            }
            if (block.kind == NativeContentKind.Text && block.image != null && LocalShowImages.current)
                AsyncImage(block.image, null, Modifier.fillMaxWidth().heightIn(max = 200.dp)
                    .clip(RoundedCornerShape(14.dp)), contentScale = ContentScale.Fit)
            val extraLinks = block.links.filter { it.url != target?.url }
            if (extraLinks.isNotEmpty()) NativeLinkActions(extraLinks, onOpen)
        }
    }
}

@Composable
private fun FavoriteThreadCard(
    title: String,
    link: ContentLink,
    onOpen: (ContentLink) -> Unit,
) {
    Card(
        Modifier.fillMaxWidth()
            .clip(RoundedCornerShape(24.dp))
            .clickable(role = Role.Button) { onOpen(link) },
    ) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Box(
                Modifier.size(44.dp).clip(RoundedCornerShape(15.dp))
                    .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .055f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    MiuixNavigationIcons.Favorites, null, Modifier.size(22.dp),
                    tint = MiuixTheme.colorScheme.onSurface,
                )
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Text(
                    title, fontSize = 16.sp, lineHeight = 22.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 2, overflow = TextOverflow.Ellipsis,
                )
                Text(
                    "收藏的帖子", fontSize = 12.sp,
                    color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                )
            }
            Icon(
                MiuixIcons.Useful.Back, null, Modifier.size(17.dp).rotate(180f),
                tint = MiuixTheme.colorScheme.onSurfaceVariantSummary,
            )
        }
    }
}

private fun nativeSummary(block: ContentBlock, title: String): String {
    var text = block.text.trim()
    if (title.isNotBlank() && text.startsWith(title)) text = text.removePrefix(title).trimStart(' ', '·', '\n')
    if (block.kind == NativeContentKind.Product && block.facts.isNotEmpty()) return ""
    return text
}

@Composable
internal fun NativeNavigation(links: List<ContentLink>, page: String, onOpen: (ContentLink) -> Unit) {
    fun identity(value: String): String {
        val parsed = value.toHttpUrlOrNull() ?: return value
        return parsed.newBuilder().removeAllQueryParameters("mobile")
            .removeAllQueryParameters("page").build().toString()
    }
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(vertical = 2.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        links.forEach { link ->
            val selected = identity(page) == identity(link.url)
            val fill by animateColorAsState(
                targetValue = if (selected) MiuixTheme.colorScheme.onSurface.copy(alpha = .09f)
                    else MiuixTheme.colorScheme.surface,
                animationSpec = tween(180),
                label = "native-tab-background",
            )
            val ink by animateColorAsState(
                targetValue = if (selected) MiuixTheme.colorScheme.onSurface
                    else MiuixTheme.colorScheme.onSurfaceVariantSummary,
                animationSpec = tween(180),
                label = "native-tab-text",
            )
            Box(Modifier.clip(RoundedCornerShape(16.dp))
                .background(fill)
                .clickable(role = Role.Tab) { onOpen(link) }
                .semantics { this.selected = selected }
                .heightIn(min = 48.dp).padding(horizontal = 17.dp, vertical = 13.dp), Alignment.Center) {
                Text(link.text, fontSize = 14.sp, maxLines = 1, color = ink)
            }
        }
    }
}

internal fun nativeFieldSection(field: RemoteField): String = when {
    field.key.startsWith("privacy[") -> "隐私设置"
    field.key == "oldpassword" -> "验证身份"
    field.key in setOf("newpassword", "newpassword2", "questionidnew", "answernew") -> "安全设置"
    field.key in setOf("email", "emailnew", "qq", "mobile", "secmobilenew", "secmobiccnew") -> "联系方式"
    field.key in setOf("subject", "message", "typeid") -> "正文内容"
    field.key in setOf("usesig", "allownoticeauthor", "readperm", "price") -> "发布设置"
    field.key in setOf("seccodeverify", "code", "answer") -> "验证信息"
    field.key in setOf("sightml", "bio") -> "个性资料"
    field.key == "addr" -> "收货信息"
    else -> "基本信息"
}

internal fun nativeFieldLabel(field: RemoteField, form: RemoteForm): String {
    if (!field.key.startsWith("privacy[")) return field.label
    val target = field.key.removePrefix("privacy[").removeSuffix("]")
    val name = form.fields.firstOrNull { it.key == target }?.label
        ?: when (target) { "residecity" -> "居住地区"; else -> "此项资料" }
    return "${name}可见范围"
}

internal fun nativeSubmitLabel(form: RemoteForm, submit: RemoteSubmit): String {
    if (submit.label !in setOf("保存", "提交", "发送", "确定")) return submit.label
    val target = form.url.toHttpUrlOrNull()
    return when {
        target?.queryParameter("action") == "reply" -> "发送回复"
        target?.queryParameter("action") == "newthread" -> "发布帖子"
        target?.queryParameter("action") == "edit" -> "保存修改"
        form.fields.any { it.key == "oldpassword" } -> "保存安全设置"
        target?.queryParameter("ac") == "profile" -> "保存资料"
        else -> submit.label
    }
}

@Composable
private fun NativeLinkActions(links: List<ContentLink>, onOpen: (ContentLink) -> Unit) {
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        links.forEach { link ->
            Button(onClick = { onOpen(link) }, minHeight = 48.dp,
                insideMargin = PaddingValues(horizontal = 14.dp, vertical = 10.dp),
                colors = ButtonDefaults.buttonColors()) {
                Text(link.text, fontSize = 13.sp, maxLines = 1)
            }
        }
    }
}

@Composable
internal fun NativeFacts(facts: List<ContentFact>) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(horizontal = 20.dp, vertical = 6.dp)) {
            facts.forEachIndexed { index, fact ->
                if (index > 0) NativeHairline()
                Row(Modifier.fillMaxWidth().padding(vertical = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(18.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(fact.label, Modifier.weight(1f), fontSize = 14.sp,
                        color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                    Text(fact.value, Modifier.weight(1.5f), fontSize = if (fact.value.length <= 12) 19.sp else 14.sp,
                        fontWeight = if (fact.value.length <= 12) FontWeight.SemiBold else FontWeight.Normal,
                        textAlign = androidx.compose.ui.text.style.TextAlign.End, lineHeight = 23.sp)
                }
            }
        }
    }
}

@Composable
internal fun NativeHairline() {
    Box(Modifier.fillMaxWidth().height(1.dp).background(MiuixTheme.colorScheme.onSurface.copy(alpha = .055f)))
}

private fun rankBadgeFill(rank: Int): Color = when (rank) {
    1 -> Color(0xFFFFC75A).copy(alpha = .24f)
    2 -> Color(0xFFC8D0DF).copy(alpha = .28f)
    3 -> Color(0xFFE9A86B).copy(alpha = .22f)
    else -> Color(0x14000000)
}

private fun rankBadgeTint(rank: Int): Color = when (rank) {
    1 -> Color(0xFF9E6500)
    2 -> Color(0xFF667085)
    3 -> Color(0xFF8F4E1C)
    else -> Color(0xFF767676)
}

/** Rank, avatar, account name and metric are independent fields for EVERY place. */
@Composable
private fun RankContentCard(block: ContentBlock, onOpen: (ContentLink) -> Unit) {
    val target = block.primaryLink
    val score = block.facts.firstOrNull()
    Card(Modifier.fillMaxWidth().then(
        if (target != null) Modifier.clip(RoundedCornerShape(26.dp))
            .clickable(role = Role.Button) { onOpen(target) } else Modifier
    )) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 18.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            RankBadge(block.rank)
            if (LocalShowImages.current && block.image != null) {
                AsyncImage(block.image, block.title,
                    Modifier.size(48.dp).clip(RoundedCornerShape(24.dp)),
                    contentScale = ContentScale.Crop)
            } else {
                Avatar(null, block.title, 48)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Text(
                    block.title.ifBlank { "未知用户" },
                    fontSize = 16.sp,
                    lineHeight = 22.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                if (score != null) {
                    if (score.label == "在线时长") {
                        // Online rankings count total online minutes. Never put this in the name.
                        val duration = score.value.trim().split(Regex("""\s+"""), limit = 2)
                        val minutes = duration.firstOrNull().orEmpty().replace(",", "")
                            .toLongOrNull()?.let { java.lang.String.format(java.util.Locale.US, "%,d", it) }
                            ?: duration.firstOrNull().orEmpty()
                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text("累计在线时长", fontSize = 11.sp,
                                color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                            Text("$minutes ${duration.getOrNull(1).orEmpty()}",
                                fontSize = 14.sp, fontWeight = FontWeight.Medium,
                                maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    } else {
                        Text(
                            "${score.value} ${score.label}",
                            fontSize = 13.sp,
                            lineHeight = 19.sp,
                            color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                        )
                    }
                }
            }
            if (target != null) RankArrowChip()
        }
    }
}

@Composable
private fun RankBadge(rank: Int?) {
    val position = rank ?: 0
    Box(
        Modifier.size(42.dp).clip(RoundedCornerShape(15.dp)).background(rankBadgeFill(position)),
        contentAlignment = Alignment.Center,
    ) {
        Text(if (rank != null) rank.toString() else "—",
            fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = rankBadgeTint(position))
    }
}

@Composable
private fun RankArrowChip() {
    Box(
        Modifier.padding(top = 2.dp).size(28.dp).clip(RoundedCornerShape(999.dp))
            .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .055f)),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            MiuixIcons.Useful.Back,
            null,
            Modifier.size(15.dp).rotate(180f),
            tint = MiuixTheme.colorScheme.onSurfaceVariantSummary,
        )
    }
}

@Composable
internal fun NativeSignCard(document: NativeDocument, loading: Boolean, onSign: () -> Unit) {
    val facts = document.blocks.flatMap { it.facts }.distinctBy { it.label }
    val signed = document.signedToday == true
    Card(Modifier.fillMaxWidth()) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 22.dp, vertical = 26.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Box(
                Modifier.size(72.dp).clip(RoundedCornerShape(24.dp))
                    .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .065f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    MiuixNavigationIcons.Months,
                    null,
                    Modifier.size(34.dp),
                    tint = MiuixTheme.colorScheme.onSurface,
                )
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    if (signed) "今日已签到" else "每日签到",
                    fontSize = 25.sp, fontWeight = FontWeight.SemiBold,
                )
                Text(
                    if (signed) "今天的签到已完成，明天见" else "记录今天的到访",
                    fontSize = 13.sp,
                    color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                )
            }
            if (facts.isNotEmpty()) {
                Column(
                    Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    facts.chunked(2).forEach { pair ->
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            pair.forEach { fact ->
                                Column(
                                    Modifier.weight(1f).clip(RoundedCornerShape(18.dp))
                                        .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .045f))
                                        .padding(horizontal = 10.dp, vertical = 15.dp),
                                    horizontalAlignment = Alignment.CenterHorizontally,
                                    verticalArrangement = Arrangement.spacedBy(5.dp),
                                ) {
                                    Text(fact.value, fontSize = 20.sp, fontWeight = FontWeight.SemiBold,
                                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    Text(fact.label, fontSize = 12.sp, maxLines = 1,
                                        color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                                }
                            }
                            if (pair.size == 1) Spacer(Modifier.weight(1f))
                        }
                    }
                }
            }
            ActionButton(
                if (signed) "今日已完成" else "立即签到",
                Modifier.widthIn(max = 310.dp).fillMaxWidth(),
                enabled = !signed && !loading,
                loading = loading,
                icon = MiuixIcons.Useful.Confirm,
                onClick = onSign,
            )
        }
    }
}
