package me.rain.mtforum.feature.profile

import android.graphics.Bitmap
import android.graphics.ImageDecoder
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import java.io.ByteArrayOutputStream
import kotlinx.coroutines.*
import me.rain.mtforum.core.network.ForumRepository
import me.rain.mtforum.core.ui.*
import me.rain.mtforum.feature.forum.readable
import top.yukonga.miuix.kmp.basic.Text

@Composable
fun AvatarScreen(
    repository: ForumRepository,
    currentAvatar: String?,
    onBack: () -> Unit,
    onChanged: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var bitmap by remember { mutableStateOf<Bitmap?>(null) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    val picker =
        rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
            if (uri != null)
                scope.launch {
                    busy = true
                    message = null
                    try {
                        bitmap =
                            withContext(Dispatchers.IO) {
                                val source =
                                    ImageDecoder.decodeBitmap(
                                        ImageDecoder.createSource(context.contentResolver, uri)
                                    ) { decoder, info, _ ->
                                        decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                                        val width = info.size.width
                                        val height = info.size.height
                                        val ratio = (2048f / maxOf(width, height)).coerceAtMost(1f)
                                        decoder.setTargetSize(
                                            (width * ratio).toInt().coerceAtLeast(1),
                                            (height * ratio).toInt().coerceAtLeast(1),
                                        )
                                    }
                                val size = minOf(source.width, source.height)
                                val square =
                                    Bitmap.createBitmap(
                                        source,
                                        (source.width - size) / 2,
                                        (source.height - size) / 2,
                                        size,
                                        size,
                                    )
                                val result = Bitmap.createScaledBitmap(square, 512, 512, true)
                                if (source !== square && source !== result) source.recycle()
                                if (square !== result) square.recycle()
                                result
                            }
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        message = e.readable()
                    } finally {
                        busy = false
                    }
                }
        }
    Column(Modifier.fillMaxSize()) {
        PageHeader("更换头像", onBack)
        Column(
            Modifier.weight(1f).padding(28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            Spacer(Modifier.height(36.dp))
            if (bitmap != null)
                Image(bitmap!!.asImageBitmap(), "新头像", Modifier.size(180.dp).clip(CircleShape))
            else AsyncImage(currentAvatar, "当前头像", Modifier.size(180.dp).clip(CircleShape))
            Spacer(Modifier.height(12.dp))
            ActionButton("选择照片", Modifier.fillMaxWidth(), primary = false, enabled = !busy) {
                picker.launch("image/*")
            }
            ActionButton(
                "保存头像",
                Modifier.fillMaxWidth(),
                enabled = bitmap != null,
                loading = busy,
            ) {
                scope.launch {
                    busy = true
                    message = null
                    try {
                        val bytes =
                            withContext(Dispatchers.Default) {
                                ByteArrayOutputStream().use { out ->
                                    bitmap!!.compress(Bitmap.CompressFormat.JPEG, 90, out)
                                    out.toByteArray()
                                }
                            }
                        message = repository.uploadAvatar(bytes)
                        onChanged()
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        message = e.readable()
                    } finally {
                        busy = false
                    }
                }
            }
            message?.let { Text(it) }
        }
    }
}
