package me.rain.mtforum.feature.profile

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import me.rain.mtforum.R
import me.rain.mtforum.core.ui.PageHeader
import me.rain.mtforum.core.data.AgreementRepository
import me.rain.mtforum.core.data.AgreementSource
import me.rain.mtforum.core.ui.AgreementRichText
import top.yukonga.miuix.kmp.basic.*

@Composable
fun AboutScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val repository = remember(context) { AgreementRepository(context) }
    var agreement by remember { mutableStateOf(repository.local()) }
    LaunchedEffect(repository) { agreement = repository.refresh() }
    Column(Modifier.fillMaxSize()) {
        PageHeader("关于与隐私", onBack)
        Column(
            Modifier.verticalScroll(rememberScrollState()).navigationBarsPadding().padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            Image(
                painterResource(R.drawable.rainkernel_logo),
                null,
                Modifier.size(80.dp).align(Alignment.CenterHorizontally),
                colorFilter =
                    androidx.compose.ui.graphics.ColorFilter.tint(
                        top.yukonga.miuix.kmp.theme.MiuixTheme.colorScheme.onBackground
                    ),
            )
            Text("MT Forum", Modifier.align(Alignment.CenterHorizontally), fontSize = 24.sp)
            Text("0.3.0", Modifier.align(Alignment.CenterHorizontally), fontSize = 14.sp)
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("使用与隐私说明", fontSize = 18.sp)
                    Text(
                        when (agreement.source) {
                            AgreementSource.Remote -> stringResource(R.string.agreement_source_remote)
                            AgreementSource.Cached -> stringResource(R.string.agreement_source_cached)
                            AgreementSource.Bundled -> stringResource(R.string.agreement_source_bundled)
                        } + (agreement.updatedAt?.let { " · $it" } ?: ""),
                        fontSize = 12.sp,
                    )
                    AgreementRichText(source = agreement.text)
                }
            }
        }
    }
}
