package me.rain.mtforum.feature.onboarding

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import me.rain.mtforum.R
import me.rain.mtforum.core.ui.ActionButton
import me.rain.mtforum.core.ui.ToolIcon
import top.yukonga.miuix.kmp.basic.Text
import top.yukonga.miuix.kmp.icon.MiuixIcons
import top.yukonga.miuix.kmp.icon.icons.useful.Back
import top.yukonga.miuix.kmp.theme.MiuixTheme

@Composable
internal fun ProvisionScaffold(
    action: String,
    onContinue: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    onBack: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier.fillMaxSize().background(MiuixTheme.colorScheme.background).safeDrawingPadding()
    ) {
        Box(Modifier.fillMaxWidth().height(64.dp).padding(start = 12.dp)) {
            if (onBack != null) {
                ToolIcon(MiuixIcons.Useful.Back, stringResource(R.string.back), onClick = onBack)
            }
        }
        Column(Modifier.weight(1f).fillMaxWidth(), content = content)
        ActionButton(
            text = action,
            onClick = onContinue,
            enabled = enabled,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 18.dp),
        )
    }
}

@Composable
internal fun ProvisionHeader(title: String, subtitle: String) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Image(
            painter = painterResource(R.drawable.provision_service_state),
            contentDescription = null,
            colorFilter = ColorFilter.tint(MiuixTheme.colorScheme.onBackground),
            modifier =
                Modifier.align(Alignment.CenterHorizontally)
                    .padding(top = 30.dp, bottom = 12.dp)
                    .size(100.dp),
        )
        Text(title, fontSize = 32.sp, color = MiuixTheme.colorScheme.onBackground)
        Text(subtitle, fontSize = 14.sp, color = MiuixTheme.colorScheme.onSurfaceSecondary)
        Spacer(Modifier.height(16.dp))
    }
}

@Composable
internal fun StorageErrorScreen(onRetry: () -> Unit) {
    ProvisionScaffold(action = stringResource(R.string.retry), onContinue = onRetry) {
        Text(
            text = stringResource(R.string.storage_error),
            modifier = Modifier.padding(28.dp),
            color = MiuixTheme.colorScheme.onBackground,
        )
    }
}
