package me.rain.mtforum.core.ui

import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import me.rain.mtforum.core.data.ApkDownloadStatus
import me.rain.mtforum.core.data.ApkMimeType
import me.rain.mtforum.core.data.UpdateApkDownloader
import me.rain.mtforum.core.data.UpdateManifest
import me.rain.mtforum.core.data.UpdateRelease
import me.rain.mtforum.core.data.UpdateRepository
import me.rain.mtforum.core.data.canDownloadUpdateInApp
import top.yukonga.miuix.kmp.basic.LinearProgressIndicator
import top.yukonga.miuix.kmp.basic.Text
import top.yukonga.miuix.kmp.extra.SuperDialog
import top.yukonga.miuix.kmp.theme.MiuixTheme

private sealed interface UpdateDownloadUi {
    data object Idle : UpdateDownloadUi
    data class Running(val bytes: Long, val total: Long, val paused: Boolean) : UpdateDownloadUi
    data object Verifying : UpdateDownloadUi
    data class Ready(val uri: Uri) : UpdateDownloadUi
    data class Failed(val message: String) : UpdateDownloadUi
}

private fun sizeLabel(bytes: Long): String =
    if (bytes <= 0) "未知大小" else String.format(java.util.Locale.US, "%.1f MB", bytes / 1_000_000.0)

/** Shared update prompt for automatic checks and Settings; actions stay reachable below the log. */
@Composable
internal fun UpdateStatusDialog(
    visible: MutableState<Boolean>,
    repository: UpdateRepository,
    manifest: UpdateManifest?,
    error: String? = null,
) {
    val context = LocalContext.current
    val downloader = remember(context) { UpdateApkDownloader(context) }
    val release = manifest?.release
    val newer = manifest?.enabled == true && release != null &&
        release.versionCode > repository.installedCode
    val canBrowser = newer && release?.preferredUrl != null
    val canInApp = newer && release != null && canDownloadUpdateInApp(release)
    val required = canBrowser && release?.requiresUpdate(repository.installedCode) == true
    var downloadId by rememberSaveable(release?.versionCode) { mutableStateOf<Long?>(null) }
    var downloadUi by remember(release?.versionCode) { mutableStateOf<UpdateDownloadUi>(UpdateDownloadUi.Idle) }
    var actionMessage by remember(release?.versionCode) { mutableStateOf<String?>(null) }

    LaunchedEffect(downloadId, release?.versionCode) {
        val id = downloadId ?: return@LaunchedEffect
        val target = release ?: return@LaunchedEffect
        while (true) {
            val state = try {
                withContext(Dispatchers.IO) { downloader.status(id) }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                downloadUi = UpdateDownloadUi.Failed("无法读取下载进度，请检查系统下载管理")
                break
            }
            when (state) {
                is ApkDownloadStatus.Progress -> {
                    downloadUi = UpdateDownloadUi.Running(state.downloaded, state.total, state.paused)
                    delay(850)
                }
                is ApkDownloadStatus.Failed -> {
                    downloadUi = UpdateDownloadUi.Failed(state.message)
                    break
                }
                ApkDownloadStatus.Complete -> {
                    downloadUi = UpdateDownloadUi.Verifying
                    downloadUi = try {
                        UpdateDownloadUi.Ready(downloader.verifiedUri(id, target))
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        UpdateDownloadUi.Failed(e.message ?: "文件校验失败，请重新下载")
                    }
                    break
                }
            }
        }
    }

    fun startDownload(target: UpdateRelease) {
        actionMessage = null
        try {
            downloadId?.let(downloader::cancel)
            downloadId = downloader.start(target)
            downloadUi = UpdateDownloadUi.Running(0L, target.fileSizeBytes, false)
        } catch (_: Exception) {
            downloadUi = UpdateDownloadUi.Failed("无法开始下载，请检查下载服务或改用浏览器")
        }
    }

    fun openBrowser(target: UpdateRelease) {
        val url = target.preferredUrl ?: return
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
            .addCategory(Intent.CATEGORY_BROWSABLE)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (runCatching { context.startActivity(intent) }.isSuccess) {
            if (!required) visible.value = false
        } else {
            actionMessage = "无法打开浏览器，请检查是否安装了浏览器"
        }
    }

    fun openInstaller(uri: Uri) {
        actionMessage = null
        if (!context.packageManager.canRequestPackageInstalls()) {
            val settingsIntent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:" + context.packageName),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (runCatching { context.startActivity(settingsIntent) }.isSuccess) {
                actionMessage = "请允许 MTForum 安装更新，然后返回点击“安装更新”"
            } else {
                actionMessage = "无法打开安装授权设置，请在系统设置中允许此应用安装更新"
            }
            return
        }
        val install = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, ApkMimeType)
            clipData = ClipData.newRawUri("MTForum APK", uri)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        if (runCatching { context.startActivity(install) }.isFailure) {
            actionMessage = "无法启动系统安装程序，请从下载管理打开 APK"
        }
    }

    val title = when {
        error != null -> "检查更新失败"
        manifest?.enabled == false -> "更新检查已暂停"
        newer -> release?.title ?: "发现新版本"
        else -> "已经是最新版本"
    }
    val versionSummary = if (newer && release != null) {
        "当前 " + repository.installedVersion + "（" + repository.installedCode + "）" +
            "  →  " + release.versionName + "（" + release.versionCode + "）"
    } else "当前版本 " + repository.installedVersion + "（" + repository.installedCode + "）"

    SuperDialog(
        show = visible,
        title = title,
        summary = error ?: versionSummary,
        onDismissRequest = { if (!required) visible.value = false },
    ) {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (newer && release != null) {
                if (release.releaseDate.isNotBlank()) {
                    Text(
                        "发布于 " + release.releaseDate + "  ·  " + sizeLabel(release.fileSizeBytes),
                        fontSize = 12.sp,
                        color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
                    )
                }
                if (release.changelog.isNotEmpty()) {
                    Text("更新内容", fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                    Column(
                        Modifier.fillMaxWidth().heightIn(max = 144.dp)
                            .verticalScroll(rememberScrollState()),
                        verticalArrangement = Arrangement.spacedBy(7.dp),
                    ) {
                        release.changelog.forEach { note ->
                            Text("• " + note, fontSize = 14.sp, lineHeight = 21.sp)
                        }
                    }
                }
                if (!canBrowser) {
                    Text("已发现新版本，但没有可用的 HTTPS 下载地址。", fontSize = 13.sp)
                } else {
                    when (val state = downloadUi) {
                        UpdateDownloadUi.Idle -> Unit
                        is UpdateDownloadUi.Running -> {
                            val percent = if (state.total > 0L) {
                                (state.bytes.toFloat() / state.total).coerceIn(0f, 1f)
                            } else null
                            Text(
                                if (state.paused) "下载已暂停，等待网络恢复"
                                else "正在下载 " + sizeLabel(state.bytes) +
                                    (if (state.total > 0L) " / " + sizeLabel(state.total) else ""),
                                fontSize = 13.sp,
                            )
                            LinearProgressIndicator(progress = percent, modifier = Modifier.fillMaxWidth())
                        }
                        UpdateDownloadUi.Verifying -> {
                            Text("下载完成，正在验证 APK 完整性…", fontSize = 13.sp)
                            LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                        }
                        is UpdateDownloadUi.Ready -> {
                            Text("下载完成且 SHA-256 校验通过", fontSize = 13.sp)
                        }
                        is UpdateDownloadUi.Failed -> {
                            Text(state.message, fontSize = 13.sp)
                        }
                    }
                    when (val state = downloadUi) {
                        is UpdateDownloadUi.Ready ->
                            ActionButton("安装更新", Modifier.fillMaxWidth()) { openInstaller(state.uri) }
                        is UpdateDownloadUi.Running, UpdateDownloadUi.Verifying ->
                            ActionButton("取消下载", Modifier.fillMaxWidth(), primary = false) {
                                downloadId?.let(downloader::cancel)
                                downloadId = null
                                downloadUi = UpdateDownloadUi.Idle
                            }
                        else -> {
                            if (canInApp) {
                                ActionButton(
                                    if (state is UpdateDownloadUi.Failed) "重新下载" else "应用内下载",
                                    Modifier.fillMaxWidth(),
                                ) { startDownload(release) }
                            } else {
                                Text("应用内下载需提供官方 Release APK 地址及有效的 SHA-256 校验信息。",
                                    fontSize = 12.sp,
                                    color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
                            }
                        }
                    }
                    ActionButton("浏览器下载", Modifier.fillMaxWidth(), primary = false) {
                        openBrowser(release)
                    }
                }
            }
            actionMessage?.let { Text(it, fontSize = 13.sp) }
            if (!required && canBrowser) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    ActionButton("稍后提醒", Modifier.weight(1f), primary = false) {
                        manifest?.let(repository::remindLater)
                        visible.value = false
                    }
                    if (manifest?.allowSkipVersion == true) {
                        ActionButton("跳过此版本", Modifier.weight(1f), primary = false) {
                            manifest?.let(repository::skipVersion)
                            visible.value = false
                        }
                    }
                }
            }
            if (!canBrowser) {
                ActionButton("关闭", Modifier.fillMaxWidth(), primary = false) {
                    visible.value = false
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
