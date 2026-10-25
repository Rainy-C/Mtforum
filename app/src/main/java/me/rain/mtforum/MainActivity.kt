package me.rain.mtforum

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import me.rain.mtforum.core.data.InitializationStore
import me.rain.mtforum.core.ui.ForumTheme
import me.rain.mtforum.feature.onboarding.ForumApp

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val store = InitializationStore(applicationContext)
        setContent {
            ForumTheme { ForumApp(store) }
        }
    }
}
