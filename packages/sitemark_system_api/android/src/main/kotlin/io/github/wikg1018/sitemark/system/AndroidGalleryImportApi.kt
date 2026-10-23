package io.github.wikg1018.sitemark.system

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.exifinterface.media.ExifInterface
import java.io.File
import java.util.concurrent.Executors

internal class AndroidGalleryImportApi(private val context: Context) : GalleryImportApi {
    companion object { const val REQUEST_PICK_IMAGES = 8715 }
    private var activity: Activity? = null
    private var pending: ((Result<List<String>>) -> Unit)? = null
    private val contract = ActivityResultContracts.PickMultipleVisualMedia(GalleryImportPolicy.MAX_IMAGES)
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    fun attachActivity(value: Activity) { activity = value }
    fun detachActivity() { activity = null }

    override fun pickImages(callback: (Result<List<String>>) -> Unit) {
        val host = activity
        if (pending != null || host == null) {
            callback(Result.failure(IllegalStateException("picker_unavailable")))
            return
        }
        pending = callback
        try {
            val intent = contract.createIntent(context, PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
            host.startActivityForResult(intent, REQUEST_PICK_IMAGES)
        } catch (error: Exception) {
            pending = null
            callback(Result.failure(error))
        }
    }

    fun onActivityResult(resultCode: Int, data: Intent?) {
        val callback = pending ?: return
        pending = null
        val granted = mutableListOf<Uri>()
        val result = runCatching {
            val uris = contract.parseResult(resultCode, data).distinct()
            require(uris.size <= GalleryImportPolicy.MAX_IMAGES) { "too_many_images" }
            for (uri in uris) {
                require(uri.scheme == "content") { "invalid_source" }
                context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                granted.add(uri)
            }
            uris.map { it.toString() }
        }
        if (result.isFailure) releaseImages(granted.map { it.toString() })
        callback(result)
    }

    override fun copyImage(sourceUri: String, captureId: String, callback: (Result<GalleryImageCopy>) -> Unit) {
        worker.execute {
            val result = runCatching {
                require(Regex("[A-Za-z0-9_-]{1,100}").matches(captureId)) { "invalid_id" }
                val uri = Uri.parse(sourceUri)
                require(uri.scheme == "content") { "invalid_source" }
                val directory = File(context.filesDir, "originals").apply { mkdirs() }
                val target = File(directory, "$captureId.jpg")
                val reader = AndroidXImageMetadataReader()
                fun validate(file: File) {
                    val info = reader.read(file)
                    require(info.mimeType in setOf("image/jpeg", "image/png")) { "unsupported_image" }
                    require(info.width <= 16384 && info.height <= 16384 && info.width * info.height <= 64000000) { "image_too_large" }
                }
                // A committed atomic copy may outlive the Dart transaction. Reuse
                // it on recovery; never re-open it with a truncating write mode.
                if (!target.exists()) {
                    val input = context.contentResolver.openInputStream(uri) ?: error("source_unavailable")
                    GalleryImportPolicy.copyAtomically(input, target, validate = ::validate)
                } else validate(target)
                val exif = ExifInterface(target)
                GalleryImageCopy(
                    originalPath = target.absolutePath,
                    capturedAtMillis = GalleryImportPolicy.parseExifTime(
                        exif.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL),
                        exif.getAttribute(ExifInterface.TAG_OFFSET_TIME_ORIGINAL),
                    ),
                )
            }
            main.post { callback(result) }
        }
    }

    override fun releaseImages(sourceUris: List<String>) {
        for (value in sourceUris) try {
            context.contentResolver.releasePersistableUriPermission(Uri.parse(value), Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (_: Exception) { /* Permission can already have been revoked. */ }
    }

    fun dispose() {
        pending?.invoke(Result.failure(IllegalStateException("picker_closed")))
        pending = null
        activity = null
        worker.shutdown()
    }
}
