package cool.happyword.wordmagic.ui

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

/** Decode the first QR payload from a gallery [uri]. Returns null when no code is found. */
suspend fun decodeQrPayloadFromUri(context: Context, uri: Uri): String? = suspendCoroutine { cont ->
    val scanner = BarcodeScanning.getClient()
    val image = runCatching {
        context.contentResolver.openInputStream(uri)?.use { stream ->
            val bitmap = BitmapFactory.decodeStream(stream) ?: return@runCatching null
            InputImage.fromBitmap(bitmap, 0)
        }
    }.getOrNull()
    if (image == null) {
        cont.resume(null)
        return@suspendCoroutine
    }
    scanner.process(image)
        .addOnSuccessListener { barcodes ->
            val payload = barcodes.firstOrNull { !it.rawValue.isNullOrBlank() }?.rawValue
            cont.resume(payload)
        }
        .addOnFailureListener {
            cont.resume(null)
        }
}
