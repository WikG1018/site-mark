package io.github.wikg1018.sitemark.system

import android.Manifest
import android.app.Activity
import android.content.ClipData
import android.content.ContentResolver
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
    private val preferences =
        context.getSharedPreferences(CaptureSessionPolicy.PREFERENCES, Context.MODE_PRIVATE)
    private val locationManager = context.getSystemService(LocationManager::class.java)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioExecutor = Executors.newSingleThreadExecutor()

    private var activity: Activity? = null

    private var cameraCallback: ((Result<CameraCaptureResult>) -> Unit)? = null
    private var archiveSaveCallback: ((Result<ArchiveSaveOutcome>) -> Unit)? = null
    private var archiveSaveSource: File? = null
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
            .putString(CaptureSessionPolicy.KEY_CAPTURE_ID, captureId)
            .putString(CaptureSessionPolicy.KEY_CAPTURE_PATH, target.absolutePath)
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
        val uri = CaptureSessionPolicy.captureContentUri(context.packageName, captureId)
        val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
            putExtra(MediaStore.EXTRA_OUTPUT, uri)
            clipData = ClipData.newRawUri("SiteMark capture", uri)
            addFlags(CaptureSessionPolicy.URI_GRANT_FLAGS)
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
        val captureId = preferences.getString(CaptureSessionPolicy.KEY_CAPTURE_ID, null) ?: return null
        val path = preferences.getString(CaptureSessionPolicy.KEY_CAPTURE_PATH, null) ?: return null
        val file = File(path)
        return RecoveredCameraCapture(
            captureId = captureId,
            outputPath = path,
            hasContent = CaptureTargetPolicy.recoveryDisposition(file.exists(), file.length()) ==
                RecoveryDisposition.CAPTURED,
        )
    }

    override fun finishCameraCapture(captureId: String, keepOriginal: Boolean) {
        val pendingId = preferences.getString(CaptureSessionPolicy.KEY_CAPTURE_ID, null)
        if (pendingId != captureId) return
        val path = preferences.getString(CaptureSessionPolicy.KEY_CAPTURE_PATH, null)
        revokeCaptureUriPermission(captureId)
        CaptureSessionPolicy.clearPending(preferences.edit())
        if (!keepOriginal && path != null) {
            File(path).delete()
        }
    }

    fun onCameraActivityResult(resultCode: Int) {
        val callback = cameraCallback ?: return
        cameraCallback = null
        val captureId = preferences.getString(CaptureSessionPolicy.KEY_CAPTURE_ID, null)
        val path = preferences.getString(CaptureSessionPolicy.KEY_CAPTURE_PATH, null).orEmpty()
        revokeCaptureUriPermission(captureId)
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

    override fun saveArchive(
        sourcePath: String,
        suggestedName: String,
        callback: (Result<ArchiveSaveOutcome>) -> Unit,
    ) {
        if (archiveSaveCallback != null) {
            callback(Result.failure(IllegalStateException("A backup save is already active")))
            return
        }
        val foreground = activity
        if (foreground == null) {
            callback(Result.failure(IllegalStateException("Saving a backup requires a foreground activity")))
            return
        }
        val source = runCatching {
            ArchiveSavePolicy.validateSource(sourcePath, context.dataDir)
        }.getOrElse { error ->
            callback(Result.failure(error))
            return
        }
        val safeName = runCatching {
            ArchiveSavePolicy.normalizeSuggestedName(suggestedName)
        }.getOrElse { error ->
            callback(Result.failure(error))
            return
        }
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/zip"
            putExtra(Intent.EXTRA_TITLE, safeName)
        }
        archiveSaveCallback = callback
        archiveSaveSource = source
        try {
            foreground.startActivityForResult(intent, REQUEST_ARCHIVE_SAVE)
        } catch (error: Throwable) {
            archiveSaveCallback = null
            archiveSaveSource = null
            callback(Result.failure(error))
        }
    }

    fun onArchiveSaveActivityResult(resultCode: Int, data: Intent?) {
        val callback = archiveSaveCallback ?: return
        val source = archiveSaveSource
        archiveSaveCallback = null
        archiveSaveSource = null
        val destination = data?.data
        if (resultCode != Activity.RESULT_OK || destination == null) {
            callback(Result.success(ArchiveSaveOutcome.CANCELLED))
            return
        }
        ioExecutor.execute {
            val result = runCatching {
                requireNotNull(source) { "Backup source is unavailable" }
                context.contentResolver.openOutputStream(destination, "w")?.let { output ->
                    ArchiveSavePolicy.copy(source, output)
                } ?: error("Unable to open the selected backup destination")
                ArchiveSaveOutcome.SAVED
            }
            mainHandler.post { callback(result) }
        }
    }

    private fun publishJpegInternal(sourcePath: String, displayName: String): MediaPublishResult {
        val source = validatedPrivateFile(sourcePath)
        val safeName = normalizedJpegName(displayName)
        val resolver = context.contentResolver
        val collection = MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val publisher = SafeMediaPublisher(
            store = AndroidPublishedImageStore(
                resolver = resolver,
                collection = collection,
                relativePath = PublishedImageDeletePolicy.PUBLISHED_RELATIVE_PATH,
            ),
        )
        val outcome = publisher.publish(source, safeName)
        return MediaPublishResult(outcome.contentUri, outcome.supersededUris)
    }

    override fun deletePublishedImage(contentUri: String, callback: (Result<Unit>) -> Unit) {
        ioExecutor.execute {
            val result = runCatching { deletePublishedImageInternal(contentUri) }
            mainHandler.post { callback(result) }
        }
    }

    private fun deletePublishedImageInternal(contentUri: String) {
        val uri = Uri.parse(contentUri)
        require(PublishedImageDeletePolicy.allowsUri(uri.scheme, uri.authority)) {
            "Published image URI is not a MediaStore image"
        }
        // The user may have deleted the photo from the gallery themselves.
        // A missing row is the desired end state, so treat it as success —
        // failing here would keep the cleanup marker pending forever and
        // retry the delete on every launch.
        if (!publishedRowExists(uri)) return
        val relativePath = queryPublishedRelativePath(uri)
        require(PublishedImageDeletePolicy.allowsRelativePath(relativePath)) {
            "Published image is outside Pictures/SiteMark"
        }
        context.contentResolver.delete(uri, null, null)
    }

    private fun publishedRowExists(uri: Uri): Boolean {
        // A null cursor means MediaProvider is temporarily unavailable
        // (crashed, restarting, storage mounting) — NOT that the row is
        // gone. Treating it as "missing" would report delete success,
        // clear the retry marker and orphan the photo forever. Only a real
        // cursor with zero rows proves the user deleted it themselves.
        val cursor =
            context.contentResolver.query(
                uri,
                arrayOf(MediaStore.Images.Media._ID),
                null,
                null,
                null,
            ) ?: error("MediaStore did not answer the published image query")
        return cursor.use { it.moveToFirst() }
    }

    private fun queryPublishedRelativePath(uri: Uri): String? {
        context.contentResolver.query(
            uri,
            arrayOf(MediaStore.Images.Media.RELATIVE_PATH),
            null,
            null,
            null,
        )?.use { cursor ->
            val index = cursor.getColumnIndex(MediaStore.Images.Media.RELATIVE_PATH)
            if (index >= 0 && cursor.moveToFirst()) {
                return cursor.getString(index)
            }
        }
        return null
    }

    fun dispose() {
        locationCancellation?.cancel()
        locationTimeout?.let(mainHandler::removeCallbacks)
        archiveSaveCallback = null
        archiveSaveSource = null
        ioExecutor.shutdown()
    }

    private fun revokeCaptureUriPermission(captureId: String?) {
        if (!CaptureSessionPolicy.shouldRevoke(captureId)) return
        val id = captureId ?: return
        val packageName = context.packageName ?: return
        context.revokeUriPermission(
            CaptureSessionPolicy.captureContentUri(packageName, id),
            CaptureSessionPolicy.URI_GRANT_FLAGS,
        )
    }

    private fun preparedTarget(captureId: String): File {
        require(preferences.getString(CaptureSessionPolicy.KEY_CAPTURE_ID, null) == captureId) {
            "Capture target has not been prepared"
        }
        val path = preferences.getString(CaptureSessionPolicy.KEY_CAPTURE_PATH, null)
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

    companion object {
        const val REQUEST_CAMERA_CAPTURE = 41001
        const val REQUEST_LOCATION_PERMISSION = 41002
        const val REQUEST_ARCHIVE_SAVE = 41003
        private const val DEFAULT_LOCATION_TIMEOUT_MILLIS = 10_000L
        private const val KEY_LOCATION_PERMISSION_REQUESTED = "location_permission_requested"
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

    /**
     * Test adapter for the synchronous delete body. Runs the policy checks +
     * MediaStore query inline (no executor hop) so the idempotent-delete
     * contract can be asserted without waiting on a background thread.
     */
    internal fun deletePublishedImageForTest(contentUri: String) {
        deletePublishedImageInternal(contentUri)
    }
}

private class AndroidPublishedImageStore(
    private val resolver: ContentResolver,
    private val collection: Uri,
    private val relativePath: String,
) : PublishedImageStore {
    override fun findAll(displayName: String): List<String> {
        val projection = arrayOf(MediaStore.Images.Media._ID)
        val selection =
            "${MediaStore.Images.Media.DISPLAY_NAME} = ? AND " +
                "${MediaStore.Images.Media.RELATIVE_PATH} = ? AND " +
                "${MediaStore.Images.Media.IS_PENDING} = 0"
        val arguments = arrayOf(displayName, relativePath)
        // Every matching row is a superseded duplicate once the replacement
        // is finalized, so collect them all — replacing only one arbitrary
        // row would leave historical duplicates unconverged.
        val uris = mutableListOf<String>()
        resolver.query(collection, projection, selection, arguments, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                uris.add(ContentUris.withAppendedId(collection, cursor.getLong(0)).toString())
            }
        }
        return uris
    }

    override fun insertPending(displayName: String): String {
        val uri = resolver.insert(
            collection,
            ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, displayName)
                put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                put(MediaStore.Images.Media.RELATIVE_PATH, relativePath)
                put(MediaStore.Images.Media.IS_PENDING, 1)
            },
        ) ?: error("MediaStore did not create an image")
        return uri.toString()
    }

    override fun write(contentUri: String, source: File) {
        source.inputStream().use { input ->
            resolver.openOutputStream(Uri.parse(contentUri), "w")?.use { output ->
                input.copyTo(output)
            } ?: error("MediaStore did not open the output stream")
        }
    }

    override fun setPending(contentUri: String, pending: Boolean) {
        val updated = resolver.update(
            Uri.parse(contentUri),
            ContentValues().apply {
                put(MediaStore.Images.Media.IS_PENDING, if (pending) 1 else 0)
            },
            null,
            null,
        )
        check(updated > 0) { "MediaStore did not update the image state" }
    }

    override fun delete(contentUri: String) {
        resolver.delete(Uri.parse(contentUri), null, null)
    }
}
