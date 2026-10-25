package me.rain.mtforum.core.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import me.rain.mtforum.core.data.UpdateManifest
import me.rain.mtforum.core.data.UpdateRepository
import top.yukonga.miuix.kmp.basic.Text
import top.yukonga.miuix.kmp.extra.SuperDialog

/** Shared visual design for the automatic prompt and Settings > Check updates. */
@Composable
internal fun UpdateStatusDialog(
    visible: MutableState<Boolean>,
    repository: UpdateRepository,
    manifest: UpdateManifest?,
    error: String? = null,
) {
    val context = LocalContext.current
    val release = manifest?.release
    val newer = manifest?.enabled == true && release != null && release.versionCode > repository.installedCode
    val canOpen = newer && release?.preferredUrl != null
    // A forced update without a real download link must never soft-lock the app.
    val required = canOpen && release?.requiresUpdate(repository.installedCode) == true
    val title = when {
        error != null -> "检查更新失败"
        manifest?.enabled == false -> "更新检查已暂停"
        newer -> release?.title ?: "发现新版本"
        else -> "已经是最新版本"
    }
    SuperDialog(
        show = visible,
        title = title,
        summary = if (error != null) error else "当前版本 ${repository.installedVersion} (${repository.installedCode})" +
            (if (newer) " · 最新 ${release?.versionName} (${release?.versionCode})" else ""),
        onDismissRequest = { if (!required) visible.value = false },
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (newer && release != null) {
                if (release.releaseDate.isNotBlank()) Text("发布日期：${release.releaseDate}", fontSize = 12.sp)
                if (release.changelog.isNotEmpty()) {
                    Text("更新内容", fontSize = 15.sp)
                    release.changelog.forEach { Text("• $it", fontSize = 13.sp) }
                }
                if (!canOpen) {
                    Text("已检测到新版本，但发布者尚未填写有效的 HTTPS 下载地址，请稍后重试。", fontSize = 13.sp)
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (canOpen && release != null) {
                    if (!required) {
                        ActionButton("稍后", Modifier.weight(1f), primary = false) {
                            manifest?.let(repository::remindLater)
                            visible.value = false
                        }
                        if (manifest?.allowSkipVersion == true) {
                            ActionButton("跳过", Modifier.weight(1f), primary = false) {
                                manifest?.let(repository::skipVersion)
                                visible.value = false
                            }
                        }
                    }
                    ActionButton("前往下载", Modifier.weight(1f)) {
                        val url = release.preferredUrl ?: return@ActionButton
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                        if (runCatching { context.startActivity(intent) }.isSuccess && !required) {
                            visible.value = false
                        }
                    }
                } else {
                    ActionButton("知道了", Modifier.fillMaxWidth(), primary = false) { visible.value = false }
                }
            }
        }
    }
}

/** Non-blocking startup check. No dialog if the share is unavailable or has placeholders. */
@Composable
internal fun AutoUpdateCheck() {
    val context = LocalContext.current
    val repository = remember(context) { UpdateRepository(context) }
    var available by remember { mutableStateOf<UpdateManifest?>(null) }
    val show = remember { mutableStateOf(false) }
    LaunchedEffect(repository) {
        if (!repository.shouldAutoCheck()) return@LaunchedEffect
        val result = runCatching { repository.fetch() }.getOrNull()
        repository.recordAutoAttempt(result)
        if (result != null && repository.canPrompt(result)) {
            available = result
            show.value = true
        }
    }
    if (available != null) UpdateStatusDialog(show, repository, available)
}
