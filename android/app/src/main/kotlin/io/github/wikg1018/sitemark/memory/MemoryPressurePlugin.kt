package io.github.wikg1018.sitemark.memory

import android.content.Context
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Owns the `sitemark/memory_pressure` MethodChannel between native and Dart.
 *
 * Two directions of traffic:
 *
 * - Native → Dart: [forward] is called by [MemoryPressureReceiver] when an
 *   ITGSA broadcast arrives. The plugin invokes `onMemoryPressure` on the
 *   Dart side, carrying the level and the pending Binder so the Dart side can
 *   ACK after its handlers finish.
 * - Dart → Native: the Dart side calls `acknowledge(level, success)` to
 *   complete the OEM Binder callback.
 *
 * The plugin keeps the most recent pending Binder keyed by level so a
 * slow-to-ACK Dart side still has a chance to ACK before the OEM timeout.
 * Only one outstanding callback per level is tracked because the OEM contract
 * serializes pressure events per level.
 *
 * When the Flutter engine is not attached (e.g. the app is in a pure
 * background state where the engine was destroyed), the plugin ACKs the
 * Binder with `success = false` so the system can proceed with its default
 * behavior. This keeps the app from being killed while it still has a chance
 * to release memory, but never blocks the system.
 */
class MemoryPressurePlugin : MethodChannel.MethodCallHandler {

    private var channel: MethodChannel? = null
    private var context: Context? = null

    // Pending OEM callbacks, keyed by level name. Only the most recent Binder
    // per level is retained; older ones (if any) are ACK'd as "not handled"
    // so the system does not wait indefinitely.
    private val pending = HashMap<String, IBinder?>()
    private val mainHandler = Handler(Looper.getMainLooper())

    fun attachTo(context: Context, flutterEngine: FlutterEngine) {
        this.context = context.applicationContext
        channel = MethodChannel(flutterEngine.dartExecutor, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
    }

    fun detachFrom() {
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
        // ACK any pending callbacks as "not handled" so the system does not
        // leak them waiting for a response that will never come.
        synchronized(pending) {
            for (binder in pending.values) {
                MemoryPressureReceiver.acknowledge(binder, false)
            }
            pending.clear()
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "acknowledge" -> {
                val args = call.argument<Map<String, Any>>("args")
                    ?: (call.arguments as? Map<String, Any>)
                @Suppress("UNCHECKED_CAST")
                val level = (args?.get("level") as? String) ?: ""
                val success = (args?.get("success") as? Boolean) ?: false
                val binder = synchronized(pending) { pending.remove(level) }
                MemoryPressureReceiver.acknowledge(binder, success)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun handleForward(level: String, binder: IBinder?) {
        // If there's already a pending callback for this level, ACK it as
        // "not handled" before stashing the new one. The OEM contract does
        // not allow more than one outstanding callback per level.
        val previous = synchronized(pending) { pending.put(level, binder) }
        if (previous != null && previous !== binder) {
            MemoryPressureReceiver.acknowledge(previous, false)
        }

        val channel = this.channel
        if (channel == null) {
            // Engine not attached (e.g. background broadcast received before
            // the Flutter engine was spun up, or after it was torn down).
            // ACK as "not handled" so the system can proceed.
            Log.w(TAG, "Engine not attached for level=$level; ACKing as not handled")
            val b = synchronized(pending) { pending.remove(level) }
            MemoryPressureReceiver.acknowledge(b, false)
            return
        }

        // Invoke the Dart handler. The Dart side will call `acknowledge` to
        // complete the Binder callback when its handlers finish.
        channel.invokeMethod(
            "onMemoryPressure",
            mapOf("level" to level),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    // The Dart handler returned; if it did not ACK, the
                    // pending Binder remains. A best-effort ACK is sent from
                    // the Dart side via `acknowledge`. Nothing to do here.
                }

                override fun error(
                    errorCode: String,
                    errorMessage: String?,
                    errorDetails: Any?,
                ) {
                    Log.w(
                        TAG,
                        "Dart handler error: $errorCode $errorMessage; ACKing $level as not handled",
                    )
                    val b = synchronized(pending) { pending.remove(level) }
                    MemoryPressureReceiver.acknowledge(b, false)
                }

                override fun notImplemented() {
                    Log.w(TAG, "Dart handler not implemented; ACKing $level as not handled")
                    val b = synchronized(pending) { pending.remove(level) }
                    MemoryPressureReceiver.acknowledge(b, false)
                }
            },
        )
    }

    companion object {
        private const val TAG = "MemoryPressurePlugin"
        private const val CHANNEL_NAME = "sitemark/memory_pressure"

        @Volatile
        private var instance: MemoryPressurePlugin? = null

        /**
         * Called by [MemoryPressureReceiver] to forward a broadcast to the
         * Dart side. Safe to call from the main thread (broadcasts are
         * delivered there) — the MethodChannel invoke is non-blocking and the
         * Dart handler runs on the UI thread's platform channel executor.
         */
        @JvmStatic
        fun forward(context: Context, level: String, binder: IBinder?) {
            // Post to the main thread to guarantee we never block the
            // broadcast dispatch thread, even if the receiver was invoked
            // from a background context.
            val plugin = instance
            if (plugin == null) {
                // Plugin not attached yet. ACK as not handled so the system
                // does not wait.
                Log.w(TAG, "Plugin not attached; ACKing $level as not handled")
                MemoryPressureReceiver.acknowledge(binder, false)
                return
            }
            plugin.mainHandler.post { plugin.handleForward(level, binder) }
        }

        /**
         * Called by [MainActivity] to register the plugin with the Flutter
         * engine. Idempotent.
         */
        @JvmStatic
        fun attach(context: Context, flutterEngine: FlutterEngine) {
            if (instance == null) {
                instance = MemoryPressurePlugin()
            }
            instance!!.attachTo(context, flutterEngine)
        }

        /**
         * Called by [MainActivity] when the engine is torn down.
         */
        @JvmStatic
        fun detach() {
            instance?.detachFrom()
        }
    }
}
