package io.github.wikg1018.sitemark.system

import android.app.Activity
import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertThrows
import org.junit.Before
import org.junit.Test
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify
import org.mockito.Mockito.`when`

/**
 * Verifies the [SiteMarkSystemPlugin] lifecycle registers and unregisters the
 * Activity result / permission result listeners through the
 * [ActivityPluginBinding], and that the Pigeon host API is wired on attach.
 */
class SiteMarkSystemPluginTest {

    private lateinit var plugin: SiteMarkSystemPlugin
    private lateinit var context: Context

    @Before
    fun setUp() {
        context = mock(Context::class.java)
        plugin = SiteMarkSystemPlugin()
    }

    @Test
    fun attachAndDetachRegisterActivityListeners() {
        val binding = mock(ActivityPluginBinding::class.java)
        val activity = mock(Activity::class.java)
        `when`(binding.activity).thenReturn(activity)

        plugin.onAttachedToActivity(binding)
        verify(binding).addActivityResultListener(plugin)
        verify(binding).addRequestPermissionsResultListener(plugin)

        plugin.onDetachedFromActivity()
        verify(binding).removeActivityResultListener(plugin)
        verify(binding).removeRequestPermissionsResultListener(plugin)
    }

    @Test
    fun engineAttachSetsUpApi() {
        val flutterBinding = mock(FlutterPlugin.FlutterPluginBinding::class.java)
        val messenger = mock(BinaryMessenger::class.java)
        `when`(flutterBinding.binaryMessenger).thenReturn(messenger)
        `when`(flutterBinding.applicationContext).thenReturn(context)

        plugin.onAttachedToEngine(flutterBinding)
        // After attach, the api is non-null; an activity request should throw
        // the headless guard (proving the api exists and is wired).
        val error = org.junit.Assert.assertThrows(IllegalStateException::class.java) {
            plugin.apiForTest().requireActivityForTest()
        }
        assertNotNull(error.message)
    }
}
