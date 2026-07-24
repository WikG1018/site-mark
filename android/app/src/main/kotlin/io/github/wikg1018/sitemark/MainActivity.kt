package io.github.wikg1018.sitemark

import io.flutter.embedding.android.FlutterActivity
import io.github.wikg1018.sitemark.memory.MemoryPressurePlugin

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Wire the ITGSA fair-memory MethodChannel so MEMORY_TRIM / MEMORY_KILL
        // broadcasts received by MemoryPressureReceiver are forwarded to the
        // Dart side and the OEM Binder is ACK'd after Dart handlers finish.
        MemoryPressurePlugin.attach(this, flutterEngine)
    }

    override fun cleanUpFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        MemoryPressurePlugin.detach()
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
