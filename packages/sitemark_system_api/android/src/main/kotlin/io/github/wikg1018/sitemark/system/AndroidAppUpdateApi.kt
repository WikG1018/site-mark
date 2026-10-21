package io.github.wikg1018.sitemark.system

import android.app.Activity
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import java.util.concurrent.Executors

/** Explicit foreground update only; system installer owns final confirmation. */
internal class AndroidAppUpdateApi(private val context: Context) : AppUpdateApi {
    private var activity: Activity? = null
    @Volatile private var disposed = false
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun attachActivity(value: Activity) { activity = value }
    fun detachActivity() { activity = null }
    fun dispose() { disposed = true; activity = null; worker.shutdownNow() }

    override fun openInstaller(apkPath: String, expectedSha256: String, expectedVersion: String, callback: (Result<ApkInstallOutcome>) -> Unit) {
        if (activity == null) {
            callback(Result.failure(FlutterError("no_activity", "Open About to install an update", null)))
            return
        }
        worker.execute {
            try {
                val file = verifiedUpdateFile(context.cacheDir, apkPath, expectedSha256)
                val pm = context.packageManager
                @Suppress("DEPRECATION")
                val archive = pm.getPackageArchiveInfo(file.path, PackageManager.GET_SIGNING_CERTIFICATES)
                    ?: throw IllegalArgumentException("invalid_apk")
                @Suppress("DEPRECATION")
                val installed = pm.getPackageInfo(context.packageName, PackageManager.GET_SIGNING_CERTIFICATES)
                validateApkIdentity(installed.identity(), archive.identity(), expectedVersion)
                main.post {
                    if (disposed) return@post
                    try {
                        val current = activity ?: throw IllegalStateException("no_activity")
                        if (!pm.canRequestPackageInstalls()) {
                            callback(Result.success(ApkInstallOutcome.PERMISSION_REQUIRED))
                        } else {
                            val uri = FileProvider.getUriForFile(context, "${context.packageName}.updates", file)
                            val intent = Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            intent.clipData = ClipData.newRawUri("SiteMark update", uri)
                            current.startActivity(intent)
                            callback(Result.success(ApkInstallOutcome.LAUNCHED))
                        }
                    } catch (_: Exception) {
                        callback(Result.failure(FlutterError("installer_unavailable", "Could not open installer", null)))
                    }
                }
            } catch (_: Exception) {
                main.post { if (!disposed) callback(Result.failure(FlutterError("invalid_apk", "Update package verification failed", null))) }
            }
        }
    }

    override fun openInstallPermissionSettings() {
        val current = activity ?: throw FlutterError("no_activity", "Open About to install an update", null)
        current.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}")))
    }

    private fun PackageInfo.identity(): ApkIdentity {
        val signing = signingInfo
        return ApkIdentity(packageName, versionName, longVersionCode,
            signing?.apkContentsSigners?.map { it.toByteArray().hex() }?.toSet() ?: emptySet(),
            if (signing?.hasMultipleSigners() == false)
                signing.signingCertificateHistory?.map { it.toByteArray().hex() }?.toSet() ?: emptySet()
            else emptySet())
    }
    private fun ByteArray.hex() = joinToString("") { "%02x".format(it) }
}
