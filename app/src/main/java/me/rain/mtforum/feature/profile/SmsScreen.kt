package me.rain.mtforum.feature.profile

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.*
import me.rain.mtforum.core.network.ForumRepository
import me.rain.mtforum.core.ui.*
import me.rain.mtforum.feature.forum.readable
import top.yukonga.miuix.kmp.basic.*
import top.yukonga.miuix.kmp.extra.SuperDialog
import top.yukonga.miuix.kmp.extra.SuperDropdown

@Composable
fun SmsScreen(repository: ForumRepository, onBack: () -> Unit) {
    var page by remember { mutableStateOf<ForumRepository.SmsPage?>(null) }
    var phone by remember { mutableStateOf("") }
    var code by remember { mutableStateOf("") }
    var action by remember { mutableIntStateOf(0) }
    var busy by remember { mutableStateOf(false) }
    var feedback by remember { mutableStateOf<String?>(null) }
    var cooldown by rememberSaveable { mutableIntStateOf(0) }
    var refresh by remember { mutableIntStateOf(0) }
    val confirm = remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(refresh) {
        busy = true
        try {
            page = repository.smsPage()
            page?.phone?.let { phone = it }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            feedback = e.readable()
        } finally {
            busy = false
        }
    }
    LaunchedEffect(cooldown) {
        if (cooldown > 0) {
            delay(1000)
            cooldown--
        }
    }
    fun submit() {
        scope.launch {
            busy = true
            try {
                feedback = repository.confirmSms(phone, code, action == 1)
                code = ""
                refresh++
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                feedback = e.readable()
            } finally {
                busy = false
            }
        }
    }
    Column(Modifier.fillMaxSize().imePadding()) {
        PageHeader("手机绑定", onBack)
        Column(
            Modifier.verticalScroll(rememberScrollState()).padding(24.dp).navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Card(Modifier.fillMaxWidth()) {
                Text(
                    if (page == null) "正在加载"
                    else
                        page?.phone?.let { "已绑定 ${it.take(3)}****${it.takeLast(4)}" } ?: "尚未绑定手机号码",
                    Modifier.padding(20.dp),
                    fontSize = 16.sp,
                )
            }
            if (page?.phone != null)
                Card(Modifier.fillMaxWidth()) {
                    SuperDropdown(
                        listOf("绑定手机", "解除绑定"),
                        action,
                        "操作",
                        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)),
                        onSelectedIndexChange = {
                            action = it
                            code = ""
                        },
                    )
                }
            TextField(
                phone,
                { phone = it.filter(Char::isDigit).take(15) },
                label = "手机号码",
                singleLine = true,
                enabled = !busy,
                modifier = Modifier.fillMaxWidth(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
            )
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                TextField(
                    code,
                    { code = it.filter(Char::isDigit).take(10) },
                    label = "验证码",
                    singleLine = true,
                    enabled = !busy,
                    modifier = Modifier.weight(1f),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                )
                ActionButton(
                    if (cooldown > 0) "${cooldown}s" else "获取验证码",
                    enabled = !busy && cooldown == 0 && phone.length >= 7,
                    primary = false,
                ) {
                    scope.launch {
                        busy = true
                        try {
                            cooldown = repository.requestSmsCode(phone, action == 1)
                            feedback = "验证码已发送"
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: Exception) {
                            feedback = e.readable()
                        } finally {
                            busy = false
                        }
                    }
                }
            }
            feedback?.let { Text(it, fontSize = 14.sp) }
            ActionButton(
                if (action == 1) "解除绑定" else "确认绑定",
                Modifier.fillMaxWidth(),
                enabled = code.isNotBlank(),
                loading = busy,
            ) {
                if (action == 1) confirm.value = true else submit()
            }
        }
    }
    SuperDialog(
        show = confirm,
        title = "解除手机绑定",
        summary = "确定解除当前手机号码的绑定？",
        onDismissRequest = { confirm.value = false },
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            ActionButton("取消", Modifier.weight(1f), primary = false) { confirm.value = false }
            ActionButton("解除绑定", Modifier.weight(1f)) {
                confirm.value = false
                submit()
            }
        }
    }
}
