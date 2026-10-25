package me.rain.mtforum.feature.auth

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.*
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import me.rain.mtforum.R
import me.rain.mtforum.core.ui.*
import me.rain.mtforum.core.ui.icons.*
import me.rain.mtforum.feature.profile.AccountViewModel
import top.yukonga.miuix.kmp.basic.*
import top.yukonga.miuix.kmp.extra.SuperDropdown
import top.yukonga.miuix.kmp.icon.MiuixIcons
import top.yukonga.miuix.kmp.icon.icons.useful.NavigatorSwitch
import top.yukonga.miuix.kmp.theme.MiuixTheme

@Composable
fun LoginScreen(
    state: AccountViewModel.State,
    onBack: () -> Unit,
    onBrowserLogin: () -> Unit,
    onLogin: (String, String, Int, String, () -> Unit) -> Unit,
) {
    var username by rememberSaveable { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var answer by remember { mutableStateOf("") }
    var showPassword by remember { mutableStateOf(false) }
    var question by rememberSaveable { mutableIntStateOf(0) }
    val keyboard = LocalSoftwareKeyboardController.current
    val busy = state.signingIn
    val questions =
        listOf(
            "无安全提问",
            "母亲的名字",
            "爷爷的名字",
            "父亲出生的城市",
            "您其中一位老师的名字",
            "您个人计算机的型号",
            "您最喜欢的餐馆名称",
            "驾驶执照最后四位数字",
        )
    fun submit() {
        keyboard?.hide()
        onLogin(username, password, question, answer) {
            password = ""
            answer = ""
            onBack()
        }
    }
    BackHandler(enabled = busy) {}
    Column(Modifier.fillMaxSize().statusBarsPadding().imePadding()) {
        Column(
            Modifier.weight(1f)
                .verticalScroll(rememberScrollState())
                .widthIn(max = 520.dp)
                .align(Alignment.CenterHorizontally)
                .padding(horizontal = 28.dp)
                .navigationBarsPadding()
        ) {
            Spacer(Modifier.height(24.dp))
            Image(
                painterResource(R.drawable.rainkernel_logo),
                null,
                Modifier.size(64.dp),
                colorFilter =
                    androidx.compose.ui.graphics.ColorFilter.tint(
                        MiuixTheme.colorScheme.onBackground
                    ),
            )
            Spacer(Modifier.height(28.dp))
            Text("欢迎回来", fontSize = 34.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(8.dp))
            Text(
                "登录 MT 论坛",
                fontSize = 16.sp,
                color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
            )
            Spacer(Modifier.height(28.dp))
            TextField(
                username,
                { username = it },
                label = "用户名 / 手机号",
                singleLine = true,
                enabled = !busy,
                modifier = Modifier.fillMaxWidth(),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                leadingIcon = {
                    Icon(
                        MiuixNavigationIcons.Profile,
                        null,
                        Modifier.padding(start = 14.dp, end = 10.dp).size(22.dp),
                    )
                },
            )
            Spacer(Modifier.height(14.dp))
            TextField(
                password,
                { password = it },
                label = "密码",
                singleLine = true,
                enabled = !busy,
                modifier = Modifier.fillMaxWidth(),
                leadingIcon = {
                    Icon(
                        MiuixNavigationIcons.Lock,
                        null,
                        Modifier.padding(start = 14.dp, end = 10.dp).size(22.dp),
                    )
                },
                trailingIcon = {
                    ToolIcon(
                        if (showPassword) MiuixNavigationIcons.Hide else MiuixNavigationIcons.Show,
                        if (showPassword) "隐藏密码" else "显示密码",
                        !busy,
                    ) {
                        showPassword = !showPassword
                    }
                },
                visualTransformation =
                    if (showPassword) VisualTransformation.None else PasswordVisualTransformation(),
                keyboardOptions =
                    KeyboardOptions(
                        keyboardType = KeyboardType.Password,
                        imeAction = if (question == 0) ImeAction.Done else ImeAction.Next,
                    ),
                keyboardActions =
                    KeyboardActions(onDone = { if (!busy && password.isNotEmpty()) submit() }),
            )
            Spacer(Modifier.height(14.dp))
            Card(Modifier.fillMaxWidth()) {
                SuperDropdown(
                    items = questions,
                    selectedIndex = question,
                    title = "安全提问",
                    modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)),
                    enabled = !busy,
                    onSelectedIndexChange = {
                        question = it
                        answer = ""
                    },
                )
            }
            AnimatedVisibility(question != 0) {
                TextField(
                    answer,
                    { answer = it },
                    label = "安全提问答案",
                    singleLine = true,
                    enabled = !busy,
                    modifier = Modifier.fillMaxWidth().padding(top = 14.dp),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { if (!busy) submit() }),
                )
            }
            state.error?.let { Text(it, Modifier.padding(top = 16.dp), fontSize = 14.sp) }
            Spacer(Modifier.height(28.dp))
            ActionButton(
                if (busy) "正在登录" else "登录",
                Modifier.fillMaxWidth(),
                loading = busy,
                enabled =
                    username.isNotBlank() &&
                        password.isNotEmpty() &&
                        (question == 0 || answer.isNotBlank()),
                onClick = ::submit,
            )
            Spacer(Modifier.height(14.dp))
            ActionButton(
                "网页登录",
                Modifier.fillMaxWidth(),
                primary = false,
                enabled = !busy,
                icon = MiuixIcons.Useful.NavigatorSwitch,
                onClick = onBrowserLogin,
            )
            Spacer(Modifier.height(40.dp))
        }
    }
}
