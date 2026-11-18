package me.rain.mtforum.feature.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import kotlinx.coroutines.CancellationException
import me.rain.mtforum.core.network.*
import me.rain.mtforum.core.ui.*
import me.rain.mtforum.feature.forum.Avatar
import me.rain.mtforum.feature.forum.UserLevelPill
import me.rain.mtforum.feature.forum.NativeFacts
import me.rain.mtforum.feature.forum.readable
import top.yukonga.miuix.kmp.basic.*
import top.yukonga.miuix.kmp.icon.MiuixIcons
import top.yukonga.miuix.kmp.icon.icons.useful.*
import top.yukonga.miuix.kmp.theme.MiuixTheme

@Composable
fun UserSpaceScreen(repository: ForumRepository, url: String, onBack: () -> Unit, onOpen: (String, String) -> Unit) {
    var profile by remember(url) { mutableStateOf<UserSpaceProfile?>(null) }
    var loading by remember(url) { mutableStateOf(true) }
    var error by remember(url) { mutableStateOf<String?>(null) }
    var refresh by remember(url) { mutableIntStateOf(0) }
    val showImages = LocalShowImages.current

    LaunchedEffect(url, refresh) {
        loading = true
        error = null
        try { profile = repository.userSpace(url) }
        catch (e: CancellationException) { throw e }
        catch (e: Exception) { error = e.readable() }
        finally { loading = false }
    }

    Column(Modifier.fillMaxSize()) {
        PageHeader("用户主页", onBack) {
            ToolIcon(MiuixIcons.Useful.Refresh, "刷新主页", !loading) { refresh++ }
        }
        if (profile == null && loading) Box(Modifier.fillMaxSize(), Alignment.Center) {
            CircularProgressIndicator()
        } else LazyColumn(
            Modifier.weight(1f).widthIn(max = 680.dp).fillMaxWidth()
                .align(Alignment.CenterHorizontally).navigationBarsPadding(),
            contentPadding = PaddingValues(horizontal = 17.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(13.dp),
        ) {
            error?.let { message -> item { EmptyState("主页加载失败", message, action = "重试", onAction = { refresh++ }) } }
            profile?.let { user ->
                item {
                    Card(Modifier.fillMaxWidth()) {
                        Column(Modifier.fillMaxWidth().padding(17.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                                Avatar(if (showImages) user.avatar else null, user.name, 64)
                                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                    Text(user.name, fontSize = 22.sp, lineHeight = 27.sp, fontWeight = FontWeight.SemiBold,
                                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
                                        val rank = listOf(user.level, user.group).map(String::trim)
                                            .filter(String::isNotBlank).distinct().joinToString(" · ")
                                        if (rank.isNotBlank()) UserLevelPill(rank)
                                        Text("UID ${user.uid}", fontSize = 11.sp,
                                            color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                                    }
                                }
                            }
                            if (user.signature.isNotBlank()) {
                                var expanded by remember(user.uid) { mutableStateOf(false) }
                                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                    SelectionContainer {
                                        Text(user.signature, fontSize = 13.sp, lineHeight = 20.sp,
                                            color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                                            maxLines = if (expanded) Int.MAX_VALUE else 2, overflow = TextOverflow.Ellipsis)
                                    }
                                    if (user.signature.length > 45) Text(
                                        if (expanded) "收起简介" else "展开简介",
                                        Modifier.clickable { expanded = !expanded }.padding(vertical = 3.dp),
                                        fontSize = 11.sp, color = MiuixTheme.colorScheme.primary,
                                    )
                                }
                            }
                            Row(
                                Modifier.fillMaxWidth().clip(RoundedCornerShape(17.dp))
                                    .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .055f))
                                    .padding(vertical = 12.dp, horizontal = 4.dp),
                                horizontalArrangement = Arrangement.spacedBy(3.dp),
                            ) {
                                listOf("帖子", "回复", "好友").forEach { label ->
                                    val query = when (label) {
                                        "帖子" -> "mod=space&do=thread&type=thread&view=me"
                                        "回复" -> "mod=space&do=thread&type=reply&view=me"
                                        else -> "mod=space&do=friend&from=space"
                                    }
                                    Column(
                                        Modifier.weight(1f).clip(RoundedCornerShape(12.dp))
                                            .clickable {
                                                onOpen("${user.name}的$label",
                                                    "${ForumRepository.BaseUrl}/home.php?$query&uid=${user.uid}&mobile=2")
                                            }.padding(vertical = 3.dp),
                                        horizontalAlignment = Alignment.CenterHorizontally,
                                        verticalArrangement = Arrangement.spacedBy(3.dp),
                                    ) {
                                        Text(user.stats[label]?.toString() ?: "—", fontSize = 22.sp,
                                            fontWeight = FontWeight.SemiBold)
                                        Text(label, fontSize = 11.sp,
                                            color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                                    }
                                }
                            }
                            if (user.actions.isNotEmpty()) {
                                val actions = user.actions.sortedBy {
                                    when (it.text) { "关注", "取消关注" -> 0; "加好友" -> 1; "发私信" -> 2; else -> 3 }
                                }
                                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    actions.take(3).forEachIndexed { index, action ->
                                        ActionButton(action.text, Modifier.weight(1f),
                                            primary = index == 0 && action.text != "取消关注") {
                                            onOpen(action.text, action.url)
                                        }
                                    }
                                }
                                if (actions.size > 3) Row(Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    actions.drop(3).forEach { action ->
                                        ActionButton(action.text, Modifier.weight(1f), primary = false) {
                                            onOpen(action.text, action.url)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                val metrics = listOf("关注", "粉丝", "人气", "积分", "金币")
                    .mapNotNull { label -> user.stats[label]?.let { label to it } }
                if (metrics.isNotEmpty()) item {
                    ProfileSection("社区数据") {
                        Card(Modifier.fillMaxWidth()) {
                            Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
                                metrics.chunked(3).forEach { group ->
                                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                                        group.forEach { (label, value) ->
                                            Column(
                                                Modifier.weight(1f).clip(RoundedCornerShape(15.dp))
                                                    .background(MiuixTheme.colorScheme.onSurface.copy(alpha = .055f))
                                                    .padding(horizontal = 12.dp, vertical = 13.dp),
                                                verticalArrangement = Arrangement.spacedBy(4.dp),
                                            ) {
                                                Text(label, fontSize = 11.sp,
                                                    color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                                                Text(value.toString(), fontSize = 19.sp,
                                                    fontWeight = FontWeight.SemiBold, maxLines = 1,
                                                    overflow = TextOverflow.Ellipsis)
                                            }
                                        }
                                        repeat(3 - group.size) { Spacer(Modifier.weight(1f)) }
                                    }
                                }
                            }
                        }
                    }
                }
                if (user.medals.isNotEmpty() && showImages) item {
                    ProfileSection("勋章") {
                        Card(Modifier.fillMaxWidth()) {
                            Row(Modifier.horizontalScroll(rememberScrollState()).padding(16.dp),
                                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                user.medals.forEach { (name, image) -> AsyncImage(image, name, Modifier.size(38.dp)) }
                            }
                        }
                    }
                }
                if (user.details.isNotEmpty()) item { ProfileSection("公开资料") { NativeFacts(user.details) } }
            }
            item { Spacer(Modifier.height(22.dp)) }
        }
    }
}

@Composable
private fun ProfileSection(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
        Text(title, Modifier.padding(start = 5.dp), fontSize = 13.sp, fontWeight = FontWeight.Medium,
            color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
        content()
    }
}
