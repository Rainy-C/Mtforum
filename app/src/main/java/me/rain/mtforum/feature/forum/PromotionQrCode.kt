package me.rain.mtforum.feature.forum

import android.graphics.Bitmap
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter

/** Draw locally, so the user's UID/link is never submitted to a third-party QR service. */
internal fun createPromotionQr(url: String): ImageBitmap {
    val size = 768
    val modules = QRCodeWriter().encode(
        url,
        BarcodeFormat.QR_CODE,
        size,
        size,
        mapOf(EncodeHintType.MARGIN to 4),
    )
    val pixels = IntArray(size * size) { index ->
        if (modules.get(index % size, index / size)) android.graphics.Color.BLACK
        else android.graphics.Color.WHITE
    }
    return Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888).apply {
        setPixels(pixels, 0, size, 0, 0, size, size)
    }.asImageBitmap()
}
