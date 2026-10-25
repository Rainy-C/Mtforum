package me.rain.mtforum.core.ui

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import top.yukonga.miuix.kmp.basic.Scaffold
import top.yukonga.miuix.kmp.theme.MiuixTheme
import top.yukonga.miuix.kmp.theme.darkColorScheme
import top.yukonga.miuix.kmp.theme.lightColorScheme

val LocalShowImages = staticCompositionLocalOf { true }

@Composable
fun ForumTheme(content: @Composable () -> Unit) {
    val context = LocalContext.current
    val preferences = remember { context.getSharedPreferences("appearance", Context.MODE_PRIVATE) }
    var appearance by remember { mutableIntStateOf(preferences.getInt("theme", 0)) }
    var images by remember { mutableStateOf(preferences.getBoolean("images", true)) }
    DisposableEffect(preferences) {
        val listener =
            SharedPreferences.OnSharedPreferenceChangeListener { prefs, key ->
                if (key == "theme") appearance = prefs.getInt("theme", 0)
                if (key == "images") images = prefs.getBoolean("images", true)
            }
        preferences.registerOnSharedPreferenceChangeListener(listener)
        onDispose { preferences.unregisterOnSharedPreferenceChangeListener(listener) }
    }
    val dark =
        when (appearance) {
            1 -> false
            2 -> true
            else -> isSystemInDarkTheme()
        }
    val colors =
        if (dark) {
            darkColorScheme()
                .copy(
                    primary = Color(0xFFF0F0F0),
                    onPrimary = Color(0xFF151515),
                    background = Color(0xFF101010),
                    onBackground = Color(0xFFF0F0F0),
                    surface = Color(0xFF1C1C1C),
                    secondaryContainer = Color(0xFF1C1C1C),
                    onSecondaryContainer = Color(0xFFB0B0B0),
                    secondaryVariant = Color(0xFF242424),
                    onSecondaryVariant = Color(0xFFE5E5E5),
                    onSurface = Color(0xFFF0F0F0),
                    disabledPrimaryButton = Color(0xFF303030),
                    disabledOnPrimaryButton = Color(0xFF777777),
                )
        } else {
            lightColorScheme()
                .copy(
                    primary = Color(0xFF202020),
                    onPrimary = Color.White,
                    background = Color(0xFFFAFAFA),
                    onBackground = Color(0xFF171717),
                    surface = Color(0xFFF0F0F0),
                    onSurface = Color(0xFF171717),
                    disabledPrimaryButton = Color(0xFFE2E2E2),
                    disabledOnPrimaryButton = Color(0xFF929292),
                )
        }
    CompositionLocalProvider(LocalShowImages provides images) {
        MiuixTheme(colors = colors) {
            Scaffold(
                modifier = Modifier.fillMaxSize(),
                containerColor = colors.background,
                contentWindowInsets = WindowInsets(0, 0, 0, 0),
            ) {
                content()
            }
        }
    }
}
