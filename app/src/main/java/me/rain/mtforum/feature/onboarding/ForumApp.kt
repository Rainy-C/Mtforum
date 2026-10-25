package me.rain.mtforum.feature.onboarding

import android.app.Activity
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.Easing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.updateTransition
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import kotlin.math.pow
import kotlin.math.hypot
import kotlin.math.max
import me.rain.mtforum.feature.home.HomeScreen
import java.io.IOException
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import me.rain.mtforum.core.ui.horizontalPageTransition
import me.rain.mtforum.core.data.InitializationStore
import me.rain.mtforum.core.data.AgreementRepository
import me.rain.mtforum.feature.startup.StartupScreen
import top.yukonga.miuix.kmp.theme.MiuixTheme

private enum class Page { Loading, Welcome, Permissions, Agreement, AgreementUpdate, Home }

@Composable
fun ForumApp(store: InitializationStore) {
    val context = LocalContext.current
    val agreementRepository = remember(context) { AgreementRepository(context) }
    var agreement by remember { mutableStateOf(agreementRepository.local()) }
    var page by rememberSaveable { mutableStateOf(Page.Loading) }
    var agreementChecked by remember { mutableStateOf(false) }
    var storageError by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }
    var retry by remember { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()

    // Consent is local state, not a network operation. Never block a returning user's
    // launch on the availability of a public QQ/Weiyun share page.
    LaunchedEffect(store, retry) {
        agreementChecked = false
        storageError = false
        try {
            val savedDigest = store.acceptedDigest().first()
            agreement = agreementRepository.local()
            page = when {
                savedDigest == null -> Page.Welcome
                agreement.source != me.rain.mtforum.core.data.AgreementSource.Bundled &&
                    agreement.digest != savedDigest -> Page.AgreementUpdate
                else -> Page.Home
            }
            agreementChecked = true

            // A failed fetch yields the local copy. Do not re-run the welcome or
            // permissions flow just because a network request times out.
            val refreshed = agreementRepository.refresh()
            agreement = refreshed
            val latestAccepted = store.acceptedDigest().first()
            if (latestAccepted != null && refreshed.source != me.rain.mtforum.core.data.AgreementSource.Bundled) {
                if (refreshed.digest != latestAccepted && page == Page.Home) {
                    page = Page.AgreementUpdate
                } else if (refreshed.digest == latestAccepted && page == Page.AgreementUpdate) {
                    page = Page.Home
                }
            }
        } catch (_: IOException) {
            storageError = true
            page = Page.Loading
        } finally {
            agreementChecked = true
        }
    }

    val activity = context as? Activity
    BackHandler(enabled = page == Page.AgreementUpdate) { activity?.finish() }

    BackHandler(enabled = page == Page.Permissions || page == Page.Agreement) {
        if (!saving) {
            storageError = false
            page = if (page == Page.Agreement) Page.Permissions else Page.Welcome
        }
    }

    when {
        !agreementChecked || page == Page.Loading -> {
            if (storageError) StorageErrorScreen(onRetry = { retry++ })
            else Box(Modifier.fillMaxSize().background(MiuixTheme.colorScheme.background))
        }
        page == Page.Home -> HomeScreen()
        page == Page.AgreementUpdate -> AgreementScreen(
            document = agreement,
            saving = saving,
            storageError = storageError,
            onBack = { activity?.finish() },
            onAccept = {
                if (!saving) {
                    saving = true
                    storageError = false
                    scope.launch {
                        try {
                            store.complete(agreement.digest)
                            page = Page.Home
                        } catch (_: IOException) {
                            storageError = true
                        } finally {
                            saving = false
                        }
                    }
                }
            },
        )
        else -> OnboardingScene(
            page = page,
            onNext = { page = Page.Permissions },
        ) { current ->
            when (current) {
                Page.Permissions -> PermissionScreen(
                    onBack = { page = Page.Welcome },
                    onContinue = { page = Page.Agreement },
                )
                Page.Agreement -> AgreementScreen(
                    document = agreement,
                    saving = saving,
                    storageError = storageError,
                    onBack = { if (!saving) page = Page.Permissions },
                    onAccept = {
                        if (!saving) {
                            saving = true
                            storageError = false
                            scope.launch {
                                try {
                                    store.complete(agreement.digest)
                                    page = Page.Home
                                } catch (error: IOException) {
                                    storageError = true
                                } finally {
                                    saving = false
                                }
                            }
                        }
                    },
                )
                else -> Unit
            }
        }
    }
}

/** Welcome stays mounted beneath the permission page, including its return. */
@Composable
private fun OnboardingScene(
    page: Page,
    onNext: () -> Unit,
    content: @Composable (Page) -> Unit,
) {
    var origin by remember { mutableStateOf<Offset?>(null) }
    var startRadius by remember { mutableStateOf(0f) }
    val fallbackRadius = with(LocalDensity.current) { 36.dp.toPx() }
    val reveal = updateTransition(page != Page.Welcome, label = "welcome-reveal")
    val progress by reveal.animateFloat(
        transitionSpec = {
            if (targetState) tween(600, easing = Easing { 1f - (1f - it).pow(2.4f) })
            else tween(540, easing = Easing { 1f - (1f - it).pow(2.2f) })
        },
        label = "circle-radius",
    ) { visible -> if (visible) 1f else 0f }
    Box(Modifier.fillMaxSize().background(MiuixTheme.colorScheme.background)) {
        StartupScreen(active = page == Page.Welcome && !reveal.isRunning) { center, radius ->
            if (!reveal.isRunning) {
                origin = center
                startRadius = radius
                onNext()
            }
        }
        if (reveal.currentState || reveal.targetState) {
            Box(Modifier.fillMaxSize().drawWithContent {
                val center = origin ?: Offset(size.width / 2f, size.height * 0.78f)
                val largeRadius = hypot(max(center.x, size.width - center.x), max(center.y, size.height - center.y))
                val smallRadius = if (startRadius > 0f) startRadius else fallbackRadius
                val radius = smallRadius + (largeRadius - smallRadius) * progress
                clipPath(Path().apply { addOval(Rect(center, radius)) }) {
                    this@drawWithContent.drawContent()
                }
            }) {
                AnimatedContent(
                    targetState = if (page == Page.Agreement) Page.Agreement else Page.Permissions,
                    transitionSpec = {
                        horizontalPageTransition(forward = targetState == Page.Agreement)
                    },
                    label = "agreement-slide",
                ) { content(it) }
            }
        }
    }
}
