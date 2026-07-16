package io.github.wikg1018.sitemark.system

import android.app.Activity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry

/**
 * Flutter plugin binding the Pigeon [SiteMarkSystemApi] to a FlutterEngine.
 *
 * On attach to an engine the [AndroidSystemApi] is created with the application
 * [android.content.Context] alone and registered as the Pigeon host - this is
 * the headless-safe path used by background work. When an [Activity] is
 * attached (foreground app), it is forwarded to the API so camera launch and
 * runtime permission requests succeed. Result/permission callbacks from the
 * activity are routed back into the API.
 */
class SiteMarkSystemPlugin :
    FlutterPlugin,
    ActivityAware,
    PluginRegistry.ActivityResultListener,
    PluginRegistry.RequestPermissionsResultListener {

    private var api: AndroidSystemApi? = null
    private var messenger: io.flutter.plugin.common.BinaryMessenger? = null
    private var binding: ActivityPluginBinding? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        messenger = binding.binaryMessenger
        val instance = AndroidSystemApi(binding.applicationContext)
        api = instance
        SiteMarkSystemApi.setUp(binding.binaryMessenger, instance)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        this.binding = binding
        api?.attachActivity(binding.activity)
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = detachActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() = detachActivity()

    private fun detachActivity() {
        binding?.removeActivityResultListener(this)
        binding?.removeRequestPermissionsResultListener(this)
        binding = null
        api?.detachActivity()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        SiteMarkSystemApi.setUp(binding.binaryMessenger, null)
        api?.dispose()
        api = null
        messenger = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?): Boolean {
        if (requestCode == AndroidSystemApi.REQUEST_CAMERA_CAPTURE) {
            api?.onCameraActivityResult(resultCode)
            return true
        }
        return false
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode == AndroidSystemApi.REQUEST_LOCATION_PERMISSION) {
            api?.onLocationPermissionResult()
            return true
        }
        return false
    }

    /** Internal test adapter exposing the live API instance. */
    internal fun apiForTest(): AndroidSystemApi =
        api ?: error("Plugin is not attached to an engine")
}
