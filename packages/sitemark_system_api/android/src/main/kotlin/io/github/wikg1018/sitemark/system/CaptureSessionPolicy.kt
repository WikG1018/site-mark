package io.github.wikg1018.sitemark.system

import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri

/**
 * Durable camera-session helpers. Clearing pending capture state uses
 * [SharedPreferences.Editor.commit] so a process death cannot resurrect a
 * stale target after finish. URI grants are revoked with the same READ|WRITE
 * flags used when launching the system camera.
 */
internal object CaptureSessionPolicy {
    const val PREFERENCES = "sitemark_capture_recovery"
    const val KEY_CAPTURE_ID = "capture_id"
    const val KEY_CAPTURE_PATH = "capture_path"
    const val URI_GRANT_FLAGS =
        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION

    fun captureContentUri(packageName: String, captureId: String): Uri =
        Uri.Builder()
            .scheme("content")
            .authority("$packageName.capture")
            .appendPath("capture")
            .appendPath(captureId)
            .build()

    fun shouldRevoke(captureId: String?): Boolean = !captureId.isNullOrEmpty()

    fun clearPending(editor: SharedPreferences.Editor): Boolean =
        editor.remove(KEY_CAPTURE_ID).remove(KEY_CAPTURE_PATH).commit()
}
