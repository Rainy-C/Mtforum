package me.rain.mtforum.feature.profile

import android.content.Context
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import coil.imageLoader
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import me.rain.mtforum.core.ui.*
import me.rain.mtforum.core.data.UpdateRepository
import me.rain.mtforum.core.data.UpdateManifest
import top.yukonga.miuix.kmp.basic.*
import top.yukonga.miuix.kmp.extra.*

@OptIn(coil.annotation.ExperimentalCoilApi::class)
@Composable
fun SettingsScreen(onBack: () -> Unit, onAbout: () -> Unit) {
    val context = LocalContext.current
    val preferences = remember { context.getSharedPreferences("appearance", Context.MODE_PRIVATE) }
    var theme by remember { mutableIntStateOf(preferences.getInt("theme", 0)) }
    var images by remember { mutableStateOf(preferences.getBoolean("images", true)) }
    var cleared by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val updateRepository = remember(context) { UpdateRepository(context) }
    val updateDialog = remember { mutableStateOf(false) }
    var latestUpdate by remember { mutableStateOf<UpdateManifest?>(null) }
    var updateError by remember { mutableStateOf<String?>(null) }
    var checkingUpdates by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize()) {
        PageHeader("设置", onBack)
        Column(
            Modifier.verticalScroll(rememberScrollState()).padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            Card(Modifier.fillMaxWidth()) {
                Column {
                    SuperDropdown(
                        items = listOf("跟随系统", "浅色", "深色"),
                        selectedIndex = theme,
                        title = "外观",
                        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)),
                        onSelectedIndexChange = {
                            theme = it
                            preferences.edit().putInt("theme", it).apply()
                        },
                    )
                    SuperSwitch(
                        checked = images,
                        onCheckedChange = {
                            images = it
                            preferences.edit().putBoolean("images", it).apply()
                        },
                        title = "显示帖子图片",
                        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)),
                    )
                }
            }
            Card(Modifier.fillMaxWidth()) {
                Column {
                    SuperArrow(
                        title = "清理图片缓存",
                        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)),
                        summary = if (cleared) "缓存已清理" else null,
                        onClick = {
                            scope.launch {
                                withContext(Dispatchers.IO) {
                                    context.imageLoader.diskCache?.clear()
                                }
                                context.imageLoader.memoryCache?.clear()
                                cleared = true
                            }
                        },
                    )
                    SuperArrow(
                        title = "检查更新",
                        summary = if (checkingUpdates) "正在连接微云…" else "当前版本 ${updateRepository.installedVersion}",
                        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)),
                        onClick = {
                            if (!checkingUpdates) scope.launch {
                                checkingUpdates = true
                                updateError = null
                                latestUpdate = null
                                try {
                                    latestUpdate = updateRepository.fetch()
                                    updateRepository.recordAutoAttempt(latestUpdate)
                                } catch (error: Exception) {
                                    updateError = error.message ?: "请检查网络后重试"
                                } finally {
                                    checkingUpdates = false
                                    updateDialog.value = true
                                }
                            }
                        },
                    )
                    SuperArrow(title = "关于 MT Forum", modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)), onClick = onAbout)
                }
            }
        }
    }
    UpdateStatusDialog(updateDialog, updateRepository, latestUpdate, updateError)
}
