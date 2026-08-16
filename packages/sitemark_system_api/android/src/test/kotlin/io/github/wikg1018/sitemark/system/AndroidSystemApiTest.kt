package io.github.wikg1018.sitemark.system

import android.Manifest
import android.app.Activity
import android.content.ContentResolver
import android.content.ContentValues
import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.content.res.AssetManager
import android.database.Cursor
import android.location.Location
import android.location.LocationManager
import android.net.Uri
import android.os.CancellationSignal
import android.provider.MediaStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Before
import org.junit.Test
import org.mockito.ArgumentMatchers.any
import org.mockito.ArgumentMatchers.eq
import org.mockito.ArgumentMatchers.isNull
import org.mockito.Mockito.`when`
import org.mockito.Mockito.doAnswer
import org.mockito.Mockito.mock
import org.mockito.Mockito.mockStatic
import org.mockito.Mockito.never
import org.mockito.Mockito.verify
import org.mockito.Mockito.anyInt
import org.mockito.Mockito.anyString
import java.util.concurrent.Executor
import java.util.function.Consumer

/**
 * Verifies the headless-safety contract of [AndroidSystemApi]: MediaStore
 * publish works with an application [Context] alone, while the system camera
 * fails fast with a clear error message when no foreground [Activity] is
 * attached.
 *
 * Uses Mockito fakes rather than Robolectric so the contract can be checked
 * without a full Android runtime (per the brief: "Use a fake Context ... or a
 * mock").
 */
class AndroidSystemApiTest {

    private lateinit var context: Context
    private lateinit var locationManager: LocationManager

    @Before
    fun setUp() {
        context = mock(Context::class.java)
        val prefs = mock(SharedPreferences::class.java)
        val editor = mock(SharedPreferences.Editor::class.java)
        `when`(prefs.edit()).thenReturn(editor)
        `when`(editor.putString(anyString(), anyString())).thenReturn(editor)
        `when`(editor.putBoolean(anyString(), org.mockito.ArgumentMatchers.anyBoolean())).thenReturn(editor)
        `when`(editor.remove(anyString())).thenReturn(editor)
        `when`(editor.apply()).then {} // no-op
        `when`(editor.commit()).thenReturn(true)
        `when`(context.getSharedPreferences(anyString(), anyInt())).thenReturn(prefs)
        locationManager = mock(LocationManager::class.java)
        `when`(context.getSystemService(LocationManager::class.java)).thenReturn(locationManager)
        // Permission checks return denied so the API never believes it has GPS.
        `when`(context.checkPermission(anyString(), anyInt(), anyInt())).thenReturn(PackageManager.PERMISSION_DENIED)
        `when`(context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION))
            .thenReturn(PackageManager.PERMISSION_DENIED)
        `when`(context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION))
            .thenReturn(PackageManager.PERMISSION_DENIED)
        // Provide a real data dir so validatedPrivateFile reaches its
        // "outside private storage" guard rather than NPE-ing on a null dir.
        `when`(context.dataDir).thenReturn(java.io.File(System.getProperty("java.io.tmpdir")!!))
    }

    @Test
    fun publishDoesNotRequireActivity() {
        val api = AndroidSystemApi(context)
        // The publish path must NOT throw the "foreground activity" guard. With
        // a fake source path outside app-private storage, it fails the
        // validation guard instead - proving no Activity is required to reach
        // the publish logic.
        val error = assertThrows(IllegalArgumentException::class.java) {
            api.publishJpegForTest(
                sourcePath = "/data/nonexistent.jpg",
                displayName = "SM-20260716-001",
                captureId = "capture-1",
                publishedUri = null,
            )
        }
        assertEquals(false, error.message!!.contains("foreground activity"))
    }

    @Test
    fun cameraFailsClearlyWithoutActivity() {
        val api = AndroidSystemApi(context)
        val error = assertThrows(IllegalStateException::class.java) {
            api.requireActivityForTest()
        }
        assertEquals("System camera requires a foreground activity", error.message)
    }

    @Test
    fun currentLocationWithoutPermissionReturnsDeniedWithoutRequestingPermission() {
        `when`(context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION))
            .thenReturn(PackageManager.PERMISSION_DENIED)
        `when`(context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION))
            .thenReturn(PackageManager.PERMISSION_DENIED)
        val api = AndroidSystemApi(context)
        var outcome: LocationOutcome? = null
        api.requestCurrentLocation(1_000) { result ->
            outcome = result.getOrThrow().outcome
        }
        assertEquals(LocationOutcome.PERMISSION_DENIED, outcome)
    }

    @Test
    fun permissionStateIsGrantedWhenEitherForegroundPermissionExists() {
        `when`(context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION))
            .thenReturn(PackageManager.PERMISSION_GRANTED)
        val api = AndroidSystemApi(context)
        assertEquals(LocationPermissionState.GRANTED, api.getLocationPermissionState())
    }

    @Test
    fun concurrentLocationRequestsShareTheInFlightResult() {
        `when`(context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION))
            .thenReturn(PackageManager.PERMISSION_GRANTED)
        `when`(locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)).thenReturn(true)
        `when`(context.mainExecutor).thenReturn(Executor { command -> command.run() })
        var locationConsumer: Consumer<Location>? = null
        doAnswer { invocation ->
            locationConsumer = invocation.getArgument(3)
            null
        }.`when`(locationManager).getCurrentLocation(
            eq(LocationManager.NETWORK_PROVIDER),
            any(CancellationSignal::class.java),
            any(Executor::class.java),
            any(),
        )
        val api = AndroidSystemApi(context)
        var first: Result<LocationResult>? = null
        var second: Result<LocationResult>? = null

        api.requestCurrentLocation(10_000) { first = it }
        api.requestCurrentLocation(10_000) { second = it }

        assertNull(first)
        assertNull(second)

        val location = mock(Location::class.java)
        `when`(location.latitude).thenReturn(23.123)
        `when`(location.longitude).thenReturn(113.456)
        `when`(location.accuracy).thenReturn(12.0f)
        locationConsumer!!.accept(location)

        val firstLocation = requireNotNull(first).getOrThrow()
        val secondLocation = requireNotNull(second).getOrThrow()
        assertEquals(LocationOutcome.APPROXIMATE, firstLocation.outcome)
        assertEquals(LocationOutcome.APPROXIMATE, secondLocation.outcome)
        assertEquals(23.123, secondLocation.latitude!!, 0.000001)
        assertEquals(113.456, secondLocation.longitude!!, 0.000001)
    }

    @Test
    fun normalizedJpegNameAcceptsPhotoNumbersWithPunctuationPreservedByDart() {
        val api = AndroidSystemApi(context)
        assertEquals(
            "东区厂房改造-SM-20260717-001.jpg",
            api.normalizedJpegName("东区厂房改造-SM-20260717-001"),
        )
        assertEquals(
            "东区厂房改造（一期）-SM-20260717-001.jpg",
            api.normalizedJpegName("东区厂房改造（一期）-SM-20260717-001"),
        )
        assertEquals(
            "A.B-SM-20260717-001.jpg",
            api.normalizedJpegName("A.B-SM-20260717-001"),
        )
        assertEquals(
            "--A-SM-20260717-001.jpg",
            api.normalizedJpegName("--A-SM-20260717-001"),
        )
        assertEquals(
            "C&D-SM-20260717-001.jpg",
            api.normalizedJpegName("C&D-SM-20260717-001"),
        )
        assertEquals(
            "Project-SM-20260717-001.jpg",
            api.normalizedJpegName("Project-SM-20260717-001"),
        )
    }

    @Test
    fun normalizedJpegNameRejectsPathSeparators() {
        val api = AndroidSystemApi(context)
        assertThrows(IllegalArgumentException::class.java) {
            api.normalizedJpegName("project/SM-20260717-001")
        }
        assertThrows(IllegalArgumentException::class.java) {
            api.normalizedJpegName("project\\SM-20260717-001")
        }
        assertThrows(IllegalArgumentException::class.java) {
            api.normalizedJpegName("project:SM-20260717-001")
        }
    }

    @Test
    fun normalizedJpegNameRejectsUnicodeWhitespaceAndControlChars() {
        val api = AndroidSystemApi(context)
        // C1 control (U+0080)
        assertThrows(IllegalArgumentException::class.java) {
            api.normalizedJpegName("A\u0080B-SM-001")
        }
        // NBSP (U+00A0)
        assertThrows(IllegalArgumentException::class.java) {
            api.normalizedJpegName("A\u00A0B-SM-001")
        }
        // EM SPACE (U+2003)
        assertThrows(IllegalArgumentException::class.java) {
            api.normalizedJpegName("A\u2003B-SM-001")
        }
        // LINE SEPARATOR (U+2028)
        assertThrows(IllegalArgumentException::class.java) {
            api.normalizedJpegName("A\u2028B-SM-001")
        }
        // ZWNBSP / BOM (U+FEFF)
        assertThrows(IllegalArgumentException::class.java) {
            api.normalizedJpegName("A\uFEFFB-SM-001")
        }
    }

    @Test
    fun deletePublishedImageTreatsAMissingGalleryRowAsSuccess() {
        val resolver = mock(ContentResolver::class.java)
        `when`(context.contentResolver).thenReturn(resolver)
        // MediaStore reports "row not found" as a cursor with zero rows.
        val emptyCursor = mock(Cursor::class.java)
        `when`(emptyCursor.moveToFirst()).thenReturn(false)
        val uri = mediaUri()
        mockStatic(Uri::class.java).use { staticUri ->
            staticUri.`when`<Uri> { Uri.parse(anyString()) }.thenReturn(uri)
            stubResolverQueries(resolver, idCursor = emptyCursor, pathCursor = null)
            val api = AndroidSystemApi(context)

            // The user may have deleted the photo from the gallery
            // themselves; the missing row is the desired end state and must
            // NOT throw — failing would keep the cleanup marker pending
            // forever and retry the delete on every launch.
            api.deletePublishedImageForTest(uri.toString())

            verify(resolver, never()).delete(any(Uri::class.java), isNull(), isNull())
        }
    }

    @Test
    fun deletePublishedImageFailsWhenMediaStoreReturnsNoCursor() {
        val resolver = mock(ContentResolver::class.java)
        `when`(context.contentResolver).thenReturn(resolver)
        val uri = mediaUri()
        mockStatic(Uri::class.java).use { staticUri ->
            staticUri.`when`<Uri> { Uri.parse(anyString()) }.thenReturn(uri)
            // A null cursor means MediaProvider is temporarily unavailable,
            // not that the row is gone — this must throw so the cleanup
            // marker survives and the delete is retried later.
            stubResolverQueries(resolver, idCursor = null, pathCursor = null)
            val api = AndroidSystemApi(context)

            val error = assertThrows(IllegalStateException::class.java) {
                api.deletePublishedImageForTest(uri.toString())
            }

            assertEquals("MediaStore did not answer the published image query", error.message)
            verify(resolver, never()).delete(any(Uri::class.java), isNull(), isNull())
        }
    }

    @Test
    fun deletePublishedImageDeletesAnExistingRowInPicturesSiteMark() {
        val resolver = mock(ContentResolver::class.java)
        `when`(context.contentResolver).thenReturn(resolver)
        val idCursor = mock(Cursor::class.java)
        `when`(idCursor.moveToFirst()).thenReturn(true)
        val pathCursor = mock(Cursor::class.java)
        `when`(pathCursor.getColumnIndex(MediaStore.Images.Media.RELATIVE_PATH)).thenReturn(0)
        `when`(pathCursor.moveToFirst()).thenReturn(true)
        `when`(pathCursor.getString(0)).thenReturn(PublishedImageDeletePolicy.PUBLISHED_RELATIVE_PATH)
        val uri = mediaUri()
        mockStatic(Uri::class.java).use { staticUri ->
            staticUri.`when`<Uri> { Uri.parse(anyString()) }.thenReturn(uri)
            stubResolverQueries(resolver, idCursor = idCursor, pathCursor = pathCursor)
            val api = AndroidSystemApi(context)

            api.deletePublishedImageForTest(uri.toString())

            verify(resolver).delete(eq(uri), isNull(), isNull())
        }
    }

    @Test
    fun deletePublishedImageFailsWhenProviderReturnsNegativeRowCount() {
        val resolver = mock(ContentResolver::class.java)
        `when`(context.contentResolver).thenReturn(resolver)
        val idCursor = mock(Cursor::class.java)
        `when`(idCursor.moveToFirst()).thenReturn(true)
        val pathCursor = mock(Cursor::class.java)
        `when`(pathCursor.getColumnIndex(MediaStore.Images.Media.RELATIVE_PATH)).thenReturn(0)
        `when`(pathCursor.moveToFirst()).thenReturn(true)
        `when`(pathCursor.getString(0)).thenReturn(PublishedImageDeletePolicy.PUBLISHED_RELATIVE_PATH)
        val uri = mediaUri()
        mockStatic(Uri::class.java).use { staticUri ->
            staticUri.`when`<Uri> { Uri.parse(anyString()) }.thenReturn(uri)
            stubResolverQueries(resolver, idCursor = idCursor, pathCursor = pathCursor)
            // -1 = 远端 Provider 未抛异常地失败了（AOSP 契约允许返回 -1），
            // 删除结果未知，必须抛错让持久化清理任务存活并重试。
            `when`(resolver.delete(any(Uri::class.java), isNull(), isNull())).thenReturn(-1)
            val api = AndroidSystemApi(context)

            val error = assertThrows(IllegalStateException::class.java) {
                api.deletePublishedImageForTest(uri.toString())
            }

            assertEquals("MediaStore did not answer the delete", error.message)
        }
    }

    @Test
    fun deletePublishedImageTreatsZeroDeletedRowsAsIdempotentSuccess() {
        val resolver = mock(ContentResolver::class.java)
        `when`(context.contentResolver).thenReturn(resolver)
        val idCursor = mock(Cursor::class.java)
        `when`(idCursor.moveToFirst()).thenReturn(true)
        val pathCursor = mock(Cursor::class.java)
        `when`(pathCursor.getColumnIndex(MediaStore.Images.Media.RELATIVE_PATH)).thenReturn(0)
        `when`(pathCursor.moveToFirst()).thenReturn(true)
        `when`(pathCursor.getString(0)).thenReturn(PublishedImageDeletePolicy.PUBLISHED_RELATIVE_PATH)
        val uri = mediaUri()
        mockStatic(Uri::class.java).use { staticUri ->
            staticUri.`when`<Uri> { Uri.parse(anyString()) }.thenReturn(uri)
            stubResolverQueries(resolver, idCursor = idCursor, pathCursor = pathCursor)
            // 0 = 行已不存在（例如用户自己删了），正是期望的终态；
            // 抛错会让清理标记永远 pending 并在每次启动时重试。
            `when`(resolver.delete(any(Uri::class.java), isNull(), isNull())).thenReturn(0)
            val api = AndroidSystemApi(context)

            api.deletePublishedImageForTest(uri.toString())

            verify(resolver).delete(eq(uri), isNull(), isNull())
        }
    }

    @Test
    fun publishFailsFastWhenCaptureIdIsBlank() {
        val resolver = mock(ContentResolver::class.java)
        `when`(context.contentResolver).thenReturn(resolver)
        // validatedPrivateFile 要求源文件在 dataDir 内且非空 —— dataDir 已被
        // setUp 指向 java.io.tmpdir，创建一个真实非空文件。
        val source = java.io.File(context.dataDir, "sm-publish-source.jpg")
        source.writeText("jpeg-bytes")
        try {
            val collection = mock(Uri::class.java)
            mockStatic(MediaStore.Images.Media::class.java).use { staticMedia ->
                // 纯 JVM 下 android.jar 静态方法未 stub，需要 mock 后
                // getContentUri 才能返回可控的集合 Uri。
                staticMedia.`when`<Uri> {
                    MediaStore.Images.Media.getContentUri(anyString())
                }.thenReturn(collection)
                val api = AndroidSystemApi(context)

                // The capture ID keys the durable publish journal; a blank
                // one would journal under an unidentifiable key, so the
                // publish must refuse before touching MediaStore.
                assertThrows(IllegalArgumentException::class.java) {
                    api.publishJpegForTest(source.absolutePath, "SM-20260716-001", "  ", null)
                }

                // 绝不 insert —— 否则会在无 journal 键的情况下创建新行。
                verify(resolver, never())
                    .insert(any(Uri::class.java), any(ContentValues::class.java))
            }
        } finally {
            source.delete()
        }
    }

    /** Returns a Uri double that passes the MediaStore allowlist check. */
    private fun mediaUri(): Uri {
        val uri = mock(Uri::class.java)
        `when`(uri.scheme).thenReturn("content")
        `when`(uri.authority).thenReturn(MediaStore.AUTHORITY)
        return uri
    }

    /**
     * Stubs [ContentResolver.query] to answer with the cursor matching the
     * requested projection so the delete body runs without a real
     * ContentProvider. Must be called inside an active [mockStatic] scope.
     */
    private fun stubResolverQueries(
        resolver: ContentResolver,
        idCursor: Cursor?,
        pathCursor: Cursor?,
    ) {
        doAnswer { invocation ->
            val projection = invocation.getArgument<Array<String>>(1)
            when (projection.firstOrNull()) {
                MediaStore.Images.Media._ID -> idCursor
                MediaStore.Images.Media.RELATIVE_PATH -> pathCursor
                else -> null
            }
        }.`when`(resolver).query(
            any(Uri::class.java),
            any(Array<String>::class.java),
            isNull(),
            isNull(),
            isNull(),
        )
    }
}
