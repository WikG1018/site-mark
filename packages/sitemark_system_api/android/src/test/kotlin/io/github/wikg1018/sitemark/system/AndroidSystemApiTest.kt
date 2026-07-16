package io.github.wikg1018.sitemark.system

import android.Manifest
import android.app.Activity
import android.content.ContentResolver
import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.content.res.AssetManager
import android.location.LocationManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Before
import org.junit.Test
import org.mockito.Mockito.`when`
import org.mockito.Mockito.mock
import org.mockito.Mockito.anyInt
import org.mockito.Mockito.anyString

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

    @Before
    fun setUp() {
        context = mock(Context::class.java)
        val prefs = mock(SharedPreferences::class.java)
        val editor = mock(SharedPreferences.Editor::class.java)
        `when`(prefs.edit()).thenReturn(editor)
        `when`(editor.putString(anyString(), anyString())).thenReturn(editor)
        `when`(editor.remove(anyString())).thenReturn(editor)
        `when`(editor.apply()).then {} // no-op
        `when`(context.getSharedPreferences(anyString(), anyInt())).thenReturn(prefs)
        `when`(context.getSystemService(LocationManager::class.java)).thenReturn(mock(LocationManager::class.java))
        // Permission checks return denied so the API never believes it has GPS.
        `when`(context.checkPermission(anyString(), anyInt(), anyInt())).thenReturn(PackageManager.PERMISSION_DENIED)
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
            api.publishJpegForTest(sourcePath = "/data/nonexistent.jpg", displayName = "SM-20260716-001")
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
}
