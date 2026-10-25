package me.rain.mtforum.feature.profile

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import me.rain.mtforum.core.network.ForumRepository
import me.rain.mtforum.core.ui.*
import me.rain.mtforum.core.ui.icons.*
import me.rain.mtforum.feature.forum.Avatar
import top.yukonga.miuix.kmp.basic.*
import top.yukonga.miuix.kmp.extra.SuperArrow
import top.yukonga.miuix.kmp.icon.MiuixIcons
import top.yukonga.miuix.kmp.icon.icons.useful.*
import top.yukonga.miuix.kmp.theme.MiuixTheme

@Composable
fun ProfileScreen(
    state: AccountViewModel.State,
    onLogin: () -> Unit,
    onRefresh: () -> Unit,
    onLogout: () -> Unit,
    onOpen: (String, String) -> Unit,
    onAbout: () -> Unit,
    onSettings: () -> Unit,
    onAvatar: () -> Unit,
) {
    val p = state.profile
    fun open(title: String, path: String) {
        if (!state.loggedIn) onLogin() else onOpen(title, ForumRepository.BaseUrl + path)
    }
    Column(Modifier.fillMaxSize()) {
        PageHeader("我的") {
            if (state.loggedIn)
                ToolIcon(MiuixIcons.Useful.Refresh, "刷新资料", !state.loading) { onRefresh() }
            ToolIcon(MiuixIcons.Useful.Settings, "设置", onClick = onSettings)
        }
        Column(
            Modifier.weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(top = 20.dp, bottom = 128.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(18.dp),
            ) {
                Box(Modifier.clip(CircleShape).clickable { if (state.loggedIn) onAvatar() else onLogin() }) {
                    Avatar(p?.avatarUrl, p?.username.orEmpty(), 76)
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                    Text(
                        if (state.loggedIn) p?.username ?: "论坛成员" else "欢迎来到 MT",
                        fontSize = 22.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                    )
                    if (state.loggedIn)
                        Text(
                            p?.let { "${it.userGroup ?: "论坛成员"} · UID ${it.uid}" } ?: "正在加载资料",
                            fontSize = 13.sp,
                            color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                        )
                    else
                        Text(
                            "登录后，发现更多精彩",
                            fontSize = 14.sp,
                            color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                        )
                }
            }
            if (!state.loggedIn)
                ActionButton(
                    "登录论坛",
                    Modifier.fillMaxWidth(),
                    icon = MiuixNavigationIcons.Profile,
                    onClick = onLogin,
                )
            else
                Card(Modifier.fillMaxWidth()) {
                    Row(Modifier.fillMaxWidth().padding(vertical = 20.dp)) {
                        ProfileStat(p?.threads, "帖子", Modifier.weight(1f)) {
                            open("我的帖子", "/home.php?mod=space&do=thread&view=me&type=thread")
                        }
                        ProfileStat(p?.replies, "回复", Modifier.weight(1f)) {
                            open("我的回复", "/home.php?mod=space&do=thread&view=me&type=reply")
                        }
                        ProfileStat(p?.friends, "好友", Modifier.weight(1f)) {
                            open("我的好友", "/home.php?mod=space&do=friend&mobile=2")
                        }
                    }
                }
            state.error?.let {
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(18.dp)) {
                        Text(it, fontSize = 14.sp)
                        if (state.loggedIn)
                            ActionButton("重新加载", primary = false, onClick = onRefresh)
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Card(
                    Modifier.weight(1f).clip(RoundedCornerShape(28.dp)).clickable {
                        open("我的收藏", "/home.php?mod=space&do=favorite&view=me&type=all")
                    }
                ) {
                    Column(
                        Modifier.padding(20.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Icon(MiuixNavigationIcons.Favorites, null, Modifier.size(26.dp))
                        Text("我的收藏", fontSize = 16.sp, fontWeight = FontWeight.Medium)
                    }
                }
                Card(Modifier.weight(1f).clip(RoundedCornerShape(28.dp)).clickable { open("每日签到", "/k_misign-sign.html") }) {
                    Column(
                        Modifier.padding(20.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Icon(MiuixNavigationIcons.Months, null, Modifier.size(26.dp))
                        Text("每日签到", fontSize = 16.sp, fontWeight = FontWeight.Medium)
                    }
                }
            }
            Card(Modifier.fillMaxWidth()) {
                Column {
                    ProfileEntry(
                        "积分与金币",
                        MiuixNavigationIcons.BankCards,
                        if (state.loggedIn) "${p?.credits ?: "—"} 积分 · ${p?.gold ?: "—"} 金币"
                        else null,
                    ) {
                        open("积分中心", "/home.php?mod=spacecp&ac=credit")
                    }
                    ProfileEntry("好友与关注", MiuixNavigationIcons.Contacts) {
                        open("好友与关注", "/home.php?mod=space&do=friend&mobile=2")
                    }
                    ProfileEntry("个人资料", MiuixIcons.Useful.Personal) {
                        open("个人资料", "/home.php?mod=spacecp&ac=profile&op=base")
                    }
                    ProfileEntry("账号与安全", MiuixNavigationIcons.Lock) {
                        onOpen("账号与安全", "mtforum://account")
                    }
                }
            }
            Card(Modifier.fillMaxWidth()) {
                Column {
                    ProfileEntry("关于 MT Forum", MiuixIcons.Useful.Info, onClick = onAbout)
                    if (state.loggedIn)
                        ProfileEntry("退出登录", MiuixIcons.Useful.NavigatorSwitch, onClick = onLogout)
                }
            }
        }
    }
}

@Composable
fun ProfileEntry(
    title: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    summary: String? = null,
    onClick: () -> Unit,
) {
    SuperArrow(
        title = title,
        summary = summary,
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)),
        leftAction = { Icon(icon, null, Modifier.padding(end = 16.dp).size(23.dp)) },
        onClick = onClick,
    )
}

@Composable
private fun ProfileStat(value: Long?, title: String, modifier: Modifier, onClick: () -> Unit) {
    Column(
        modifier.clip(RoundedCornerShape(16.dp)).clickable(onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(value?.toString() ?: "—", fontSize = 25.sp, fontWeight = FontWeight.SemiBold)
        Text(title, fontSize = 12.sp, color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
    }
}

@Composable
fun AccountToolsScreen(onBack: () -> Unit, onOpen: (String, String) -> Unit) {
    val groups =
        listOf(
            listOf(
                "基本资料" to "ac=profile&op=base",
                "个性签名" to "ac=profile&op=info",
                "联系方式" to "ac=profile&op=contact",
            ),
            listOf(
                "密码与邮箱" to "ac=profile&op=password",
                "手机绑定" to "ac=plugin&id=comiis_sms:comiis_setup",
            ),
            listOf(
                "用户组" to "ac=usergroup",
                "邀请码" to "ac=invite",
                "访问推广" to "ac=promotion",
                "积分记录" to "ac=credit&op=log",
            ),
        )
    Column(Modifier.fillMaxSize()) {
        PageHeader("账号与安全", onBack)
        Column(
            Modifier.verticalScroll(rememberScrollState()).padding(20.dp).navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            groups.forEach { rows ->
                Card(Modifier.fillMaxWidth()) {
                    Column {
                        rows.forEach { (title, query) ->
                            SuperArrow(
                                title = title,
                                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)),
                                onClick = {
                                    onOpen(
                                        title,
                                        "${ForumRepository.BaseUrl}/home.php?mod=spacecp&$query",
                                    )
                                },
                            )
                        }
                    }
                }
            }
            Card(Modifier.fillMaxWidth()) {
                SuperArrow(
                    title = "修改用户名",
                    modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)),
                    onClick = {
                        onOpen("修改用户名", "${ForumRepository.BaseUrl}/plugin.php?id=nimba_rename")
                    },
                )
            }
        }
    }
}
