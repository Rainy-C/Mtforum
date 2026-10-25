package me.rain.mtforum.feature.onboarding

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import me.rain.mtforum.R
import top.yukonga.miuix.kmp.basic.Text
import top.yukonga.miuix.kmp.theme.MiuixTheme

@Composable
internal fun PermissionScreen(onBack: () -> Unit, onContinue: () -> Unit) {
    val context = LocalContext.current
    val owner = LocalLifecycleOwner.current
    fun isGranted(): Boolean = ContextCompat.checkSelfPermission(
        context, Manifest.permission.POST_NOTIFICATIONS,
    ) == PackageManager.PERMISSION_GRANTED
    var granted by remember { mutableStateOf(isGranted()) }
    var asked by rememberSaveable { mutableStateOf(false) }
    var settingsUnavailable by remember { mutableStateOf(false) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        granted = isGranted()
    }
    DisposableEffect(owner, context) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) granted = isGranted()
        }
        owner.lifecycle.addObserver(observer)
        onDispose { owner.lifecycle.removeObserver(observer) }
    }
    ProvisionScaffold(
        action = stringResource(R.string.continue_action),
        onBack = onBack,
        onContinue = onContinue,
    ) {
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 24.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            ProvisionHeader(stringResource(R.string.permission_title), stringResource(R.string.permission_subtitle))
            PermissionRow(
                title = stringResource(R.string.network_title),
                summary = stringResource(R.string.network_summary),
                status = stringResource(R.string.declared),
            )
            Text(
                stringResource(R.string.optional_permission),
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                fontSize = 13.sp,
                color = MiuixTheme.colorScheme.onSurfaceSecondary,
            )
            PermissionRow(
                title = stringResource(R.string.notification_title),
                summary = stringResource(R.string.notification_summary),
                status = stringResource(if (granted) R.string.granted else R.string.optional),
                onClick = {
                    if (!granted && !asked) {
                        asked = true
                        launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
                    } else {
                        try {
                            context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:${context.packageName}")
                            })
                        } catch (error: ActivityNotFoundException) {
                            settingsUnavailable = true
                        }
                    }
                },
            )
            if (settingsUnavailable) {
                Text(stringResource(R.string.settings_unavailable), fontSize = 13.sp)
            }
        }
    }
}

@Composable
private fun PermissionRow(title: String, summary: String, status: String, onClick: (() -> Unit)? = null) {
    val shape = RoundedCornerShape(18.dp)
    val action = if (onClick != null) Modifier.clickable(role = Role.Button, onClick = onClick) else Modifier
    Row(
        Modifier.fillMaxWidth().clip(shape).background(MiuixTheme.colorScheme.surface)
            .then(action).heightIn(min = 72.dp).padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, fontSize = 16.sp, color = MiuixTheme.colorScheme.onSurface)
            Text(summary, fontSize = 12.sp, color = MiuixTheme.colorScheme.onSurfaceSecondary)
        }
        Text(status, fontSize = 13.sp, color = MiuixTheme.colorScheme.onSurface)
    }
}
