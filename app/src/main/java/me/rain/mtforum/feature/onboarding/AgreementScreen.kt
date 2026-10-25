package me.rain.mtforum.feature.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import me.rain.mtforum.R
import me.rain.mtforum.core.data.AgreementDocument
import me.rain.mtforum.core.data.AgreementSource
import me.rain.mtforum.core.ui.AgreementRichText
import top.yukonga.miuix.kmp.basic.Checkbox
import top.yukonga.miuix.kmp.basic.Text
import top.yukonga.miuix.kmp.theme.MiuixTheme

@Composable
internal fun AgreementScreen(
    document: AgreementDocument,
    saving: Boolean,
    storageError: Boolean,
    onBack: () -> Unit,
    onAccept: () -> Unit,
) {
    var accepted by rememberSaveable(document.digest) { mutableStateOf(false) }
    val scroll = rememberScrollState()
    val reachedEnd by remember { derivedStateOf { scroll.maxValue != Int.MAX_VALUE && !scroll.canScrollForward } }
    LaunchedEffect(document.digest) { scroll.scrollTo(0) }
    ProvisionScaffold(
        action = stringResource(if (saving) R.string.saving else R.string.agree_continue),
        onBack = onBack,
        onContinue = onAccept,
        enabled = reachedEnd && accepted && !saving,
    ) {
        Column(
            Modifier.weight(1f).fillMaxSize().verticalScroll(scroll).padding(horizontal = 28.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            ProvisionHeader(stringResource(R.string.agreement_title), stringResource(R.string.agreement_subtitle))
            Text(
                text = when (document.source) {
                    AgreementSource.Remote -> stringResource(R.string.agreement_source_remote)
                    AgreementSource.Cached -> stringResource(R.string.agreement_source_cached)
                    AgreementSource.Bundled -> stringResource(R.string.agreement_source_bundled)
                } + (document.updatedAt?.let { " · $it" } ?: ""),
                color = MiuixTheme.colorScheme.onSurfaceSecondary,
                fontSize = 12.sp,
            )
            AgreementRichText(source = document.text)
        }
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 12.dp)
                .clip(RoundedCornerShape(16.dp))
                .background(MiuixTheme.colorScheme.surface)
                .toggleable(
                    value = accepted,
                    enabled = reachedEnd && !saving,
                    role = Role.Checkbox,
                    onValueChange = { accepted = it },
                ).heightIn(min = 56.dp).padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Checkbox(
                checked = accepted,
                onCheckedChange = null,
                enabled = reachedEnd && !saving,
            )
            Text(
                stringResource(if (reachedEnd) R.string.agreement_check else R.string.agreement_scroll_hint),
                fontSize = 14.sp,
                color = MiuixTheme.colorScheme.onSurface,
            )
        }
        if (storageError) {
            Text(
                stringResource(R.string.save_error),
                modifier = Modifier.padding(horizontal = 28.dp),
                color = MiuixTheme.colorScheme.onBackground,
                fontSize = 13.sp,
            )
        }
    }
}
