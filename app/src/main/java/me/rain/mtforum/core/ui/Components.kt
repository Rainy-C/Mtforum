package me.rain.mtforum.core.ui

import androidx.compose.foundation.layout.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import top.yukonga.miuix.kmp.basic.*
import top.yukonga.miuix.kmp.icon.MiuixIcons
import top.yukonga.miuix.kmp.icon.icons.useful.Back
import top.yukonga.miuix.kmp.theme.MiuixTheme

@Composable
fun ToolIcon(icon: ImageVector, description: String, enabled: Boolean = true, onClick: () -> Unit) {
    IconButton(onClick = onClick, enabled = enabled, modifier = Modifier.size(48.dp)) {
        Icon(icon, description, Modifier.size(24.dp), tint = MiuixTheme.colorScheme.onBackground)
    }
}

@Composable
fun PageHeader(
    title: String,
    onBack: (() -> Unit)? = null,
    actions: @Composable RowScope.() -> Unit = {},
) {
    Row(
        Modifier.fillMaxWidth()
            .statusBarsPadding()
            .heightIn(min = 64.dp)
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (onBack != null) ToolIcon(MiuixIcons.Useful.Back, "返回", onClick = onBack)
        Text(
            title,
            modifier = Modifier.weight(1f).padding(start = if (onBack == null) 12.dp else 4.dp),
            fontSize = if (onBack == null) 30.sp else 20.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
        )
        actions()
    }
}

@Composable
fun ActionButton(
    text: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    primary: Boolean = true,
    loading: Boolean = false,
    icon: ImageVector? = null,
    onClick: () -> Unit,
) {
    Button(
        onClick = onClick,
        modifier = modifier,
        enabled = enabled && !loading,
        minHeight = 24.dp,
        insideMargin = PaddingValues(horizontal = 20.dp, vertical = 16.dp),
        colors =
            if (primary) ButtonDefaults.buttonColorsPrimary() else ButtonDefaults.buttonColors(),
    ) {
        val color =
            when {
                !enabled || loading ->
                    if (primary) MiuixTheme.colorScheme.disabledOnPrimaryButton
                    else MiuixTheme.colorScheme.disabledOnSecondaryVariant
                primary -> MiuixTheme.colorScheme.onPrimary
                else -> MiuixTheme.colorScheme.onSecondaryVariant
            }
        if (loading)
            CircularProgressIndicator(
                size = 20.dp,
                colors =
                    ProgressIndicatorDefaults.progressIndicatorColors(
                        foregroundColor = color,
                        backgroundColor = color.copy(alpha = .15f),
                    ),
            )
        else if (icon != null) Icon(icon, null, Modifier.size(20.dp), tint = color)
        if (loading || icon != null) Spacer(Modifier.width(10.dp))
        Text(text, fontSize = 16.sp, fontWeight = FontWeight.Medium, color = color)
    }
}

@Composable
fun EmptyState(
    title: String,
    message: String? = null,
    icon: ImageVector? = null,
    action: String? = null,
    onAction: () -> Unit = {},
) {
    Column(
        Modifier.fillMaxWidth().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        if (icon != null)
            Icon(
                icon,
                null,
                Modifier.size(48.dp),
                tint = MiuixTheme.colorScheme.onSurfaceVariantSummary,
            )
        Text(title, fontSize = 18.sp, fontWeight = FontWeight.Medium)
        if (!message.isNullOrBlank())
            Text(message, fontSize = 14.sp, color = MiuixTheme.colorScheme.onSurfaceVariantSummary)
        if (action != null) ActionButton(action, primary = false, onClick = onAction)
    }
}
