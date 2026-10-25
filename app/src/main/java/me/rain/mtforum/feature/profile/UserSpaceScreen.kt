package me.rain.mtforum.feature.profile

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import kotlinx.coroutines.CancellationException
import me.rain.mtforum.core.network.*
import me.rain.mtforum.core.ui.*
import me.rain.mtforum.feature.forum.Avatar
import me.rain.mtforum.feature.forum.NativeFacts
import me.rain.mtforum.feature.forum.NativeHairline
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
    var refresh by remember { mutableIntStateOf(0) }
    val showImages = LocalShowImages.current
    LaunchedEffect(url, refresh) {
        loading = true
        error = null
        try {
            profile = repository.userSpace(url)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            error = e.readable()
        } finally {
            loading = false
        }
    }
    Column(Modifier.fillMaxSize()) {
        PageHeader("用户主页", onBack) {
            ToolIcon(MiuixIcons.Useful.Refresh, "刷新主页", !loading) { refresh++ }
        }
        if (profile == null && loading) Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
        else LazyColumn(
            Modifier.weight(1f).widthIn(max = 680.dp).fillMaxWidth().align(Alignment.CenterHorizontally)
                .navigationBarsPadding(),
            contentPadding = PaddingValues(20.dp, 12.dp, 20.dp, 32.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            error?.let { message -> item { EmptyState("主页加载失败", message, action = "重试", onAction = { refresh++ }) } }
            profile?.let { user ->
                item {
                    Card(Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(22.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                                Avatar(if (showImages) user.avatar else null, user.name, 72)
                                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                                    Text(user.name, fontSize = 23.sp, lineHeight = 30.sp, fontWeight = FontWeight.SemiBold)
                                    val group = listOf(user.level, user.group).filter(String::isNotBlank).joinToString(" · ")
                                    if (group.isNotBlank()) Text(group, fontSize = 13.sp,
                                        color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                                    Text("UID ${user.uid}", fontSize = 12.sp,
                                        color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                                }
                            }
                            if (user.signature.isNotBlank()) SelectionContainer {
                                Text(user.signature, fontSize = 14.sp, lineHeight = 23.sp,
                                    color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                            }
                            NativeHairline()
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                listOf("帖子", "回复", "好友").forEach { label ->
                                    Column(Modifier.weight(1f).clip(RoundedCornerShape(14.dp)).clickable {
                                        val query = when (label) {
                                            "帖子" -> "mod=space&do=thread&type=thread&view=me"
                                            "回复" -> "mod=space&do=thread&type=reply&view=me"
                                            else -> "mod=space&do=friend&from=space"
                                        }
                                        onOpen("${user.name}的$label", "${ForumRepository.BaseUrl}/home.php?${query}&uid=${user.uid}&mobile=2")
                                    }.padding(vertical = 6.dp), horizontalAlignment = Alignment.CenterHorizontally,
                                        verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                        Text(user.stats[label]?.toString() ?: "—", fontSize = 24.sp, fontWeight = FontWeight.SemiBold)
                                        Text(label, fontSize = 12.sp, color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                                    }
                                }
                            }
                            if (user.actions.isNotEmpty()) {
                                user.actions.chunked(2).forEachIndexed { row, actions ->
                                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                        actions.forEachIndexed { index, action ->
                                            ActionButton(action.text, Modifier.weight(1f), primary = row == 0 && index == 0 && action.text != "取消关注") {
                                                onOpen(action.text, action.url)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                val balances = listOf("关注", "粉丝", "人气", "积分", "金币").mapNotNull { label ->
                    user.stats[label]?.let { ContentFact(label, it.toString()) }
                }
                if (balances.isNotEmpty()) item { ProfileSection("数据概览") { NativeFacts(balances) } }
                if (user.medals.isNotEmpty() && showImages) item {
                    ProfileSection("勋章") {
                        Card(Modifier.fillMaxWidth()) {
                            Row(Modifier.horizontalScroll(rememberScrollState()).padding(18.dp),
                                horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                                user.medals.forEach { (name, image) -> AsyncImage(image, name, Modifier.size(40.dp)) }
                            }
                        }
                    }
                }
                if (user.details.isNotEmpty()) item { ProfileSection("公开资料") { NativeFacts(user.details) } }
            }
        }
    }
}

@Composable
private fun ProfileSection(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
        Text(title, Modifier.padding(start = 4.dp), fontSize = 13.sp,
            color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
        content()
    }
}
