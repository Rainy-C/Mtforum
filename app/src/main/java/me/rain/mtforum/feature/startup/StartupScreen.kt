package me.rain.mtforum.feature.startup

import android.content.Context
import android.graphics.Color
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.sevtinge.hyperceiler.provision.renderengine.GlowController
import com.sevtinge.hyperceiler.provision.renderengine.RenderViewLayout
import me.rain.mtforum.R
import me.rain.mtforum.feature.startup.legacy.MotionAnimator
import me.rain.mtforum.feature.startup.legacy.NativeBlur

/** Keeps the reference project's renderer inside a Compose-owned lifecycle. */
@Composable
fun StartupScreen(active: Boolean, onNext: (Offset, Float) -> Unit) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val next by rememberUpdatedState(onNext)
    val intro = remember(context) { IntroView(context) { center, radius -> next(center, radius) } }
    DisposableEffect(intro, lifecycleOwner) {
        lifecycleOwner.lifecycle.addObserver(intro)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(intro)
            intro.release()
        }
    }
    AndroidView(
        factory = { intro },
        update = { it.setUiActive(active) },
        modifier = Modifier.fillMaxSize(),
    )
}

private class IntroView(context: Context, onNext: (Offset, Float) -> Unit) :
    FrameLayout(context), DefaultLifecycleObserver {
    private val renderLayout: RenderViewLayout
    private val controller: GlowController
    private val motion: MotionAnimator
    private var started = false
    private var active = false
    private var foreground = false
    private var uiActive = true
    private var released = false
    private var shaderFailed = false
    private val begin = Runnable { beginWhenReady() }

    init {
        LayoutInflater.from(context).inflate(R.layout.provision_startup_layout, this, true)
        renderLayout = findViewById(R.id.render_view_layout)
        val glow = View(context)
        renderLayout.attachView(glow, 0.2f, Color.BLACK)
        controller = GlowController(glow)
        val icon = findViewById<ImageView>(R.id.logo_image)
        val wordmark = findViewById<TextView>(R.id.text_logo_image)
        val wrapper = findViewById<View>(R.id.logo_image_wrapper)
        val next = findViewById<View>(R.id.next_layout)
        icon.setImageResource(R.drawable.rainkernel_logo)
        NativeBlur.setupContainer(findViewById(R.id.miui_enter_layout), dp(50))
        icon.visibility = INVISIBLE
        wrapper.visibility = INVISIBLE
        next.visibility = INVISIBLE
        motion = MotionAnimator(icon, wrapper, next)
        // A fixed dark foreground must not be altered by MIUI blend modes.
        val foregroundColor = Color.rgb(28, 28, 30)
        icon.setColorFilter(foregroundColor)
        wordmark.setTextColor(foregroundColor)
        next.setOnClickListener {
            next.isEnabled = false
            val position = IntArray(2)
            next.getLocationInWindow(position)
            onNext(
                Offset(position[0] + next.width / 2f, position[1] + next.height / 2f),
                next.width / 2f,
            )
        }
        addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            if (active && !started && width > 0 && height > 0) post(begin)
        }
    }

    override fun onStart(owner: LifecycleOwner) {
        foreground = true
        synchronizeActivity()
    }

    private fun beginWhenReady() {
        if (!active || released || width == 0 || height == 0) return
        if (!shaderFailed) {
            try {
                controller.start(!started)
                controller.thaw()
                controller.setCircleYOffsetWithView(findViewById(R.id.logo_image_wrapper), renderLayout)
            } catch (error: RuntimeException) {
                shaderFailed = true
                controller.stop()
                Log.e("MtForum", "Welcome shader unavailable", error)
            }
        }
        if (!started) {
            started = true
            motion.play()
        } else {
            motion.resume()
        }
    }

    override fun onStop(owner: LifecycleOwner) {
        foreground = false
        synchronizeActivity()
    }

    fun setUiActive(value: Boolean) {
        uiActive = value
        findViewById<View>(R.id.next_layout).isEnabled = value
        synchronizeActivity()
    }

    private fun synchronizeActivity() {
        val shouldRun = foreground && uiActive
        if (shouldRun == active) return
        active = shouldRun
        if (active) {
            post(begin)
            return
        }
        removeCallbacks(begin)
        controller.freeze()
        motion.pause()
    }

    fun release() {
        released = true
        removeCallbacks(begin)
        controller.stop()
        motion.cancel()
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}
