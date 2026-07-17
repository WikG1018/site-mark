package io.github.wikg1018.sitemark.system

import android.Manifest
import android.app.Activity
import android.content.ClipData
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Settings
import android.location.Location
import android.location.LocationManager
import android.net.Uri
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import java.io.File
import java.util.concurrent.Executors

/**
 * Headless-safe implementation of the Pigeon [SiteMarkSystemApi].
 *
 * Constructed with an application [Context] alone, which is enough for the
 * file-target, recovery-preferences and MediaStore publish/delete paths used by
 * background work. Camera launch and runtime location permission requests
 * require a foreground [Activity]; attach one with [attachActivity] and detach
 * it with [detachActivity]. When no activity is attached, the camera/location
 * paths fail fast with a clear [IllegalStateException] from [requireActivity]
 * rather than NPE-ing on a null activity.
 *
 * All Pigeon callbacks are dispatched on the main looper via [mainHandler]
 * (never `activity.runOnUiThread`), so the API works without an activity.
 */
class AndroidSystemApi(
    private val context: Context,
    private val metadataReader: ImageMetadataReader = AndroidXImageMetadataReader(),
) : SiteMarkSystemApi {
    private val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
    private val locationManager = context.getSystemService(LocationManager::class.java)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioExecutor = Executors.newSingleThreadExecutor()

    private var activity: Activity? = null

    private var cameraCallback: ((Result<CameraCaptureResult>) -> Unit)? = null
    private val locationCallbacks = mutableListOf<(Result<LocationResult>) -> Unit>()
    private var locationCancellation: CancellationSignal? = null
    private var locationTimeout: Runnable? = null
    private var permissionCallback: ((Result<LocationPermissionState>) -> Unit)? = null
    private var requestedLocationTimeoutMillis: Long = DEFAULT_LOCATION_TIMEOUT_MILLIS

    /** Attaches a foreground [Activity] enabling camera launch and permission requests. */
    fun attachActivity(activity: Activity) {
        this.activity = activity
    }

    /** Detaches the foreground [Activity]; the API remains usable for headless paths. */
    fun detachActivity() {
        this.activity = null
    }

    /**
     * Returns the attached [Activity] or throws a clear error. Used by every
     * path that genuinely requires a foreground activity (camera launch,
     * runtime permission request).
     */
    private fun requireActivity(): Activity =
        activity ?: error("System camera requires a foreground activity")

    override fun createCameraTarget(captureId: String): String {
        val directory = File(context.filesDir, "originals").apply { mkdirs() }
        val target = File(directory, CaptureTargetPolicy.fileName(captureId))
        if (target.exists() && !target.delete()) {
            error("Unable to replace existing capture target")
        }
        preferences.edit()
            .putString(KEY_CAPTURE_ID, captureId)
            .putString(KEY_CAPTURE_PATH, target.absolutePath)
            .apply()
        return target.absolutePath
    }

    override fun launchCamera(
        captureId: String,
        callback: (Result<CameraCaptureResult>) -> Unit,
    ) {
        if (cameraCallback != null) {
            callback(Result.failure(IllegalStateException("A camera capture is already active")))
            return
        }
        val activity = try {
            requireActivity()
        } catch (error: IllegalStateException) {
            callback(Result.failure(error))
            return
        }
        val target = preparedTarget(captureId)
        val uri = Uri.Builder()
            .scheme("content")
            .authority("${context.packageName}.capture")
            .appendPath("capture")
            .appendPath(captureId)
            .build()
        val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
            putExtra(MediaStore.EXTRA_OUTPUT, uri)
            clipData = ClipData.newRawUri("SiteMark capture", uri)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        if (intent.resolveActivity(context.packageManager) == null) {
            callback(
                Result.success(
                    CameraCaptureResult(
                        outcome = CameraOutcome.FAILED,
                        outputPath = target.absolutePath,
                        errorMessage = "No system camera application is available",
                    ),
                ),
            )
            return
        }
        cameraCallback = callback
        try {
            activity.startActivityForResult(intent, REQUEST_CAMERA_CAPTURE)
        } catch (error: Throwable) {
            cameraCallback = null
            callback(Result.failure(error))
        }
    }

    override fun recoverCameraCapture(): RecoveredCameraCapture? {
        val captureId = preferences.getString(KEY_CAPTURE_ID, null) ?: return null
        val path = preferences.getString(KEY_CAPTURE_PATH, null) ?: return null
        val file = File(path)
        return RecoveredCameraCapture(
            captureId = captureId,
            outputPath = path,
            hasContent = CaptureTargetPolicy.recoveryDisposition(file.exists(), file.length()) ==
                RecoveryDisposition.CAPTURED,
        )
    }

    override fun finishCameraCapture(captureId: String, keepOriginal: Boolean) {
        val pendingId = preferences.getString(KEY_CAPTURE_ID, null)
        if (pendingId != captureId) return
        val path = preferences.getString(KEY_CAPTURE_PATH, null)
        preferences.edit().remove(KEY_CAPTURE_ID).remove(KEY_CAPTURE_PATH).apply()
        if (!keepOriginal && path != null) {
            File(path).delete()
        }
    }

    fun onCameraActivityResult(resultCode: Int) {
        val callback = cameraCallback ?: return
        cameraCallback = null
        val captureId = preferences.getString(KEY_CAPTURE_ID, null)
        val path = preferences.getString(KEY_CAPTURE_PATH, null).orEmpty()
        val file = File(path)
        val captured = resultCode == Activity.RESULT_OK && file.exists() && file.length() > 0L
        if (captured) {
            callback(
                Result.success(
                    CameraCaptureResult(CameraOutcome.CAPTURED, file.absolutePath, null),
                ),
            )
        } else {
            if (captureId != null) finishCameraCapture(captureId, keepOriginal = false)
            callback(Result.success(CameraCaptureResult(CameraOutcome.CANCELLED, path, null)))
        }
    }

    override fun getLocationPermissionState(): LocationPermissionState {
        if (hasLocationPermission()) return LocationPermissionState.GRANTED
        val asked = preferences.getBoolean(KEY_LOCATION_PERMISSION_REQUESTED, false)
        val canExplain = activity?.shouldShowRequestPermissionRationale(
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == true
        return if (asked && !canExplain) {
            LocationPermissionState.PERMANENTLY_DENIED
        } else {
            LocationPermissionState.DENIED
        }
    }

    override fun requestLocationPermission(
        callback: (Result<LocationPermissionState>) -> Unit,
    ) {
        if (hasLocationPermission()) {
            callback(Result.success(LocationPermissionState.GRANTED))
            return
        }
        val foreground = try {
            requireActivity()
        } catch (error: IllegalStateException) {
            callback(Result.failure(error))
            return
        }
        permissionCallback = callback
        preferences.edit().putBoolean(KEY_LOCATION_PERMISSION_REQUESTED, true).apply()
        foreground.requestPermissions(
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ),
            REQUEST_LOCATION_PERMISSION,
        )
    }

    override fun openApplicationSettings() {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", context.packageName, null),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    override fun inspectImage(
        path: String,
        callback: (Result<ImageMetadataResult>) -> Unit,
    ) {
        ioExecutor.execute {
            val result = runCatching {
                val file = validatedPrivateFile(path)
                metadataReader.read(file)
            }
            mainHandler.post { callback(result) }
        }
    }

    internal fun inspectImageForTest(path: String): ImageMetadataResult =
        metadataReader.read(validatedPrivateFile(path))

    override fun requestCurrentLocation(
        timeoutMillis: Long,
        callback: (Result<LocationResult>) -> Unit,
    ) {
        locationCallbacks.add(callback)
        if (locationCallbacks.size > 1) {
            return
        }
        requestedLocationTimeoutMillis = timeoutMillis.coerceIn(1_000L, 30_000L)
        if (!hasLocationPermission()) {
            finishLocation(
                LocationResult(
                    outcome = LocationOutcome.PERMISSION_DENIED,
                    latitude = null,
                    longitude = null,
                    accuracyMeters = null,
                    address = null,
                    errorMessage = null,
                ),
            )
            return
        }
        startCurrentLocation()
    }

    fun onLocationPermissionResult() {
        val callback = permissionCallback ?: return
        permissionCallback = null
        callback(Result.success(getLocationPermissionState()))
    }

    private fun startCurrentLocation() {
        val provider = preferredLocationProvider()
        if (provider == null) {
            finishLocation(
                LocationResult(
                    LocationOutcome.SERVICES_DISABLED,
                    null,
                    null,
                    null,
                    null,
                    null,
                ),
            )
            return
        }
        val cancellation = CancellationSignal()
        locationCancellation = cancellation
        val timeout = Runnable {
            cancellation.cancel()
            finishLocation(LocationResult(LocationOutcome.TIMEOUT, null, null, null, null, null))
        }
        locationTimeout = timeout
        mainHandler.postDelayed(timeout, requestedLocationTimeoutMillis)
        try {
            locationManager.getCurrentLocation(
                provider,
                cancellation,
                context.mainExecutor,
            ) { location ->
                if (location == null) {
                    finishLocation(
                        LocationResult(LocationOutcome.UNAVAILABLE, null, null, null, null, null),
                    )
                } else {
                    finishLocation(location.toPigeonResult())
                }
            }
        } catch (error: SecurityException) {
            finishLocation(
                LocationResult(
                    LocationOutcome.PERMISSION_DENIED,
                    null,
                    null,
                    null,
                    null,
                    error.message,
                ),
            )
        } catch (error: Throwable) {
            finishLocation(
                LocationResult(
                    LocationOutcome.UNAVAILABLE,
                    null,
                    null,
                    null,
                    null,
                    error.message,
                ),
            )
        }
    }

    private fun Location.toPigeonResult(): LocationResult {
        val outcome = if (
            context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            LocationOutcome.PRECISE
        } else {
            LocationOutcome.APPROXIMATE
        }
        return LocationResult(
            outcome = outcome,
            latitude = latitude,
            longitude = longitude,
            accuracyMeters = accuracy.toDouble(),
            address = null,
            errorMessage = null,
        )
    }

    private fun finishLocation(result: LocationResult) {
        if (locationCallbacks.isEmpty()) return
        val callbacks = locationCallbacks.toList()
        locationCallbacks.clear()
        locationCancellation = null
        locationTimeout?.let(mainHandler::removeCallbacks)
        locationTimeout = null
        callbacks.forEach { callback -> callback(Result.success(result)) }
    }

    override fun publishJpeg(
        sourcePath: String,
        displayName: String,
        callback: (Result<MediaPublishResult>) -> Unit,
    ) {
        ioExecutor.execute {
            val result = runCatching { publishJpegInternal(sourcePath, displayName) }
            mainHandler.post { callback(result) }
        }
    }

    private fun publishJpegInternal(sourcePath: String, displayName: String): MediaPublishResult {
        val source = validatedPrivateFile(sourcePath)
        val safeName = normalizedJpegName(displayName)
        val resolver = context.contentResolver
        val collection = MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        var created = false
        val uri = findPublishedImage(collection, safeName) ?: run {
            created = true
            resolver.insert(
                collection,
                ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, safeName)
                    put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                    put(MediaStore.Images.Media.RELATIVE_PATH, PUBLISHED_RELATIVE_PATH)
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                },
            ) ?: error("MediaStore did not create an image")
        }
        try {
            if (!created) {
                resolver.update(
                    uri,
                    ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 1) },
                    null,
                    null,
                )
            }
            source.inputStream().use { input ->
                resolver.openOutputStream(uri, "w")?.use { output ->
                    input.copyTo(output)
                } ?: error("MediaStore did not open the output stream")
            }
            resolver.update(
                uri,
                ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) },
                null,
                null,
            )
            return MediaPublishResult(uri.toString())
        } catch (error: Throwable) {
            if (created) resolver.delete(uri, null, null)
            throw error
        }
    }

    override fun deletePublishedImage(contentUri: String, callback: (Result<Unit>) -> Unit) {
        ioExecutor.execute {
            val result = runCatching {
                val uri = Uri.parse(contentUri)
                require(uri.scheme == "content") { "Expected a content URI" }
                context.contentResolver.delete(uri, null, null)
                Unit
            }
            mainHandler.post { callback(result) }
        }
    }

    fun dispose() {
        locationCancellation?.cancel()
        locationTimeout?.let(mainHandler::removeCallbacks)
        ioExecutor.shutdown()
    }

    private fun preparedTarget(captureId: String): File {
        require(preferences.getString(KEY_CAPTURE_ID, null) == captureId) {
            "Capture target has not been prepared"
        }
        val path = preferences.getString(KEY_CAPTURE_PATH, null)
            ?: error("Capture target path is missing")
        val expected = File(File(context.filesDir, "originals"), CaptureTargetPolicy.fileName(captureId))
        val target = File(path)
        require(target.canonicalFile == expected.canonicalFile) { "Capture target is outside private storage" }
        return target
    }

    private fun hasLocationPermission(): Boolean {
        return context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED ||
            context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun preferredLocationProvider(): String? {
        val hasFine = context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        if (hasFine && locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
            return LocationManager.GPS_PROVIDER
        }
        if (locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
            return LocationManager.NETWORK_PROVIDER
        }
        return null
    }

    private fun validatedPrivateFile(path: String): File {
        val file = File(path).canonicalFile
        val dataDirectory = context.dataDir.canonicalFile
        require(file.path.startsWith(dataDirectory.path + File.separator)) {
            "Source image must be in app-private storage"
        }
        require(file.isFile && file.length() > 0L) { "Source image is empty or missing" }
        return file
    }

    internal fun normalizedJpegName(displayName: String): String {
        val base = displayName.removeSuffix(".jpg").removeSuffix(".jpeg")
        // Unified forbidden set: control chars (Cc incl. C1), Unicode
        // separators (Z: spaces, NBSP, EM SPACE, line/para separators),
        // ZWNBSP/BOM, and path/shell metacharacters.
        require(base.isNotEmpty() && !base.contains(Regex("[\\p{Cc}\\p{Z}\\uFEFF/\\\\:*?\"<>|]"))) {
            "Invalid published image name"
        }
        return "$base.jpg"
    }

    private fun findPublishedImage(collection: Uri, displayName: String): Uri? {
        val projection = arrayOf(MediaStore.Images.Media._ID)
        val selection =
            "${MediaStore.Images.Media.DISPLAY_NAME} = ? AND " +
                "${MediaStore.Images.Media.RELATIVE_PATH} = ?"
        val arguments = arrayOf(displayName, PUBLISHED_RELATIVE_PATH)
        context.contentResolver.query(collection, projection, selection, arguments, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                return ContentUris.withAppendedId(collection, cursor.getLong(0))
            }
        }
        return null
    }

    companion object {
        const val REQUEST_CAMERA_CAPTURE = 41001
        const val REQUEST_LOCATION_PERMISSION = 41002
        private const val DEFAULT_LOCATION_TIMEOUT_MILLIS = 10_000L
        private const val PREFERENCES = "sitemark_capture_recovery"
        private const val KEY_CAPTURE_ID = "capture_id"
        private const val KEY_CAPTURE_PATH = "capture_path"
        private const val KEY_LOCATION_PERMISSION_REQUESTED = "location_permission_requested"
        private const val PUBLISHED_RELATIVE_PATH = "Pictures/SiteMark/"
    }

    // ------------------------------------------------------------------
    // Internal test adapters. These delegate directly to the production
    // private methods/fields and are intentionally excluded from the Pigeon
    // interface. They allow the headless-safety contract to be unit-tested
    // without an instrumented Android runtime.
    // ------------------------------------------------------------------

    /** Test adapter for the [requireActivity] guard. */
    internal fun requireActivityForTest(): Activity = requireActivity()

    /**
     * Test adapter for the synchronous publish body. Runs the validation +
     * MediaStore write inline (no executor hop) so the headless-safety
     * contract can be asserted without waiting on a background thread.
     */
    internal fun publishJpegForTest(sourcePath: String, displayName: String): MediaPublishResult =
        publishJpegInternal(sourcePath, displayName)
}
