package io.github.wikg1018.sitemark

import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.github.wikg1018.sitemark.bridge.SiteMarkSystemApi

class MainActivity : FlutterActivity() {
    private var systemApi: AndroidSystemApi? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val api = AndroidSystemApi(this)
        systemApi = api
        SiteMarkSystemApi.setUp(flutterEngine.dartExecutor.binaryMessenger, api)
    }

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == AndroidSystemApi.REQUEST_CAMERA_CAPTURE) {
            systemApi?.onCameraActivityResult(resultCode)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == AndroidSystemApi.REQUEST_LOCATION_PERMISSION) {
            systemApi?.onLocationPermissionResult()
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        SiteMarkSystemApi.setUp(flutterEngine.dartExecutor.binaryMessenger, null)
        systemApi?.dispose()
        systemApi = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
