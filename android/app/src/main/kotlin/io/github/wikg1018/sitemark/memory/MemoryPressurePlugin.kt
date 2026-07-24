package io.github.wikg1018.sitemark.memory

import android.content.BroadcastReceiver
import android.content.Context
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicLong

/**
 * Owns the `sitemark/memory_pressure` MethodChannel between native and Dart.
 *
 * Two directions of traffic:
 *
 * - Native → Dart: [forward] is called by [MemoryPressureReceiver] when an
 *   ITGSA broadcast arrives. The plugin invokes `onMemoryPressure` on the
 *   Dart side, carrying the level, a unique event ID, and the pending Binder
 *   so the Dart side can ACK after its handlers finish.
 * - Dart → Native: the Dart side calls `acknowledge(eventId, success)` to
 *   complete the OEM Binder callback.
 *
 * Each pressure event gets a monotonically increasing [eventId]. The pending
 * map is keyed by eventId (not level) so that consecutive same-level events
 * cannot be cross-ACKed: the Dart side's ACK for event #1 will not match
 * event #2's entry. When a new event supersedes an older one at the same
 * level, the older event is ACK'd as "not handled" and its PendingResult
 * finished.
 *
 * When the Flutter engine is not attached, the plugin ACKs the Binder with
 * `success = false` so the system can proceed with its default behavior.
 *
 * **PendingResult lifecycle:** the `BroadcastReceiver.PendingResult` from
 * `goAsync()` is held until the Binder `transact` completes (or fails), at
 * which point `finish()` is called via the `onComplete` callback. This
 * ordering is critical: calling `finish()` before `transact` completes allows
 * Android to reclaim the process, causing the ACK to be lost.
 */
class MemoryPressurePlugin : MethodChannel.MethodCallHandler {

    private var channel: MethodChannel? = null

    /// Bundles the OEM Binder callback, the BroadcastReceiver PendingResult,
    /// and the level for cleanup tracking. Keyed by [eventId] in [pending].
    private data class PendingCallback(
        val eventId: Long,
        val level: String,
        val binder: IBinder?,
        val pendingResult: BroadcastReceiver.PendingResult?,
    )

    // Pending OEM callbacks, keyed by eventId. Using eventId (not level)
    // prevents cross-ACK when consecutive same-level events arrive.
    private val pending = HashMap<Long, PendingCallback>()

    // Tracks the current eventId per level so a new event can supersede
    // and clean up the previous one.
    private val levelToEventId = HashMap<String, Long>()

    private val mainHandler = Handler(Looper.getMainLooper())

    fun attachTo(context: Context, flutterEngine: FlutterEngine) {
        // `context` is accepted to match the standard Flutter plugin attach
        // signature but is not currently stored: the plugin only needs the
        // Dart executor to build the MethodChannel.
        channel = MethodChannel(flutterEngine.dartExecutor, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
    }

    fun detachFrom() {
        channel?.setMethodCallHandler(null)
        channel = null
        // ACK any pending callbacks as "not handled" and finish their
        // PendingResults. finish() is called in the onComplete callback,
        // *after* the Binder transact completes.
        synchronized(pending) {
            for (cb in pending.values) {
                MemoryPressureReceiver.acknowledge(cb.binder, false) {
                    cb.pendingResult?.finish()
                }
            }
            pending.clear()
            levelToEventId.clear()
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "acknowledge" -> {
                val eventId = (call.argument<Number>("eventId") ?: -1).toLong()
                val success = call.argument<Boolean>("success") ?: false
                val cb = synchronized(pending) { pending.remove(eventId) }
                if (cb != null) {
                    // finish() is called in onComplete, after transact
                    // completes. This ensures the process is not reclaimed
                    // before the ACK reaches the OEM.
                    MemoryPressureReceiver.acknowledge(cb.binder, success) {
                        cb.pendingResult?.finish()
                    }
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /// Helper: ACK a callback as not-handled and finish its PendingResult
    /// after the transact completes.
    private fun ackAndFinish(cb: PendingCallback, tag: String) {
        Log.w(TAG, "$tag; ACKing eventId=${cb.eventId} level=${cb.level} as not handled")
        MemoryPressureReceiver.acknowledge(cb.binder, false) {
            cb.pendingResult?.finish()
        }
    }

    private fun handleForward(level: String, binder: IBinder?, pendingResult: BroadcastReceiver.PendingResult?) {
        val eventId = nextEventId.incrementAndGet()
        val callback = PendingCallback(eventId, level, binder, pendingResult)

        // Supersede any previous event at this level. The OEM contract does
        // not allow more than one outstanding callback per level; ACK the
        // old one as "not handled" and finish its PendingResult after the
        // transact completes.
        val oldEventId: Long? = synchronized(pending) {
            levelToEventId.put(level, eventId)
        }
        if (oldEventId != null) {
            val oldCb = synchronized(pending) { pending.remove(oldEventId) }
            if (oldCb != null) {
                ackAndFinish(oldCb, "Superseded by new $level event")
            }
        }
        synchronized(pending) { pending[eventId] = callback }

        val channel = this.channel
        if (channel == null) {
            // Engine not attached. ACK as "not handled".
            val cb = synchronized(pending) { pending.remove(eventId) }
            if (cb != null) ackAndFinish(cb, "Engine not attached")
            return
        }

        // Strict timeout: if the Dart side does not ACK within the limit,
        // ACK as "not handled" and finish the PendingResult.
        pendingResult?.let { pr ->
            mainHandler.postDelayed({
                val cb = synchronized(pending) { pending.remove(eventId) }
                if (cb != null && cb.pendingResult === pr) {
                    ackAndFinish(cb, "Dart handler timed out")
                }
            }, ACK_TIMEOUT_MS)
        }

        // Invoke the Dart handler. The Dart side will call `acknowledge` with
        // the eventId to complete the Binder callback when its handlers finish.
        channel.invokeMethod(
            "onMemoryPressure",
            mapOf("level" to level, "eventId" to eventId),
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
                    val cb = synchronized(pending) { pending.remove(eventId) }
                    if (cb != null) ackAndFinish(cb, "Dart handler error: $errorCode $errorMessage")
                }

                override fun notImplemented() {
                    val cb = synchronized(pending) { pending.remove(eventId) }
                    if (cb != null) ackAndFinish(cb, "Dart handler not implemented")
                }
            },
        )
    }

    companion object {
        private const val TAG = "MemoryPressurePlugin"
        private const val CHANNEL_NAME = "sitemark/memory_pressure"

        // Maximum time the Dart side has to ACK a pressure event before the
        // plugin auto-ACKs as "not handled" and finishes the PendingResult.
        // 10 seconds is well within the OEM's typical 20-second window while
        // being short enough that a hung Dart isolate does not leave the
        // broadcast dangling.
        private const val ACK_TIMEOUT_MS = 10_000L

        private val nextEventId = AtomicLong(0)

        @Volatile
        private var instance: MemoryPressurePlugin? = null

        /**
         * Called by [MemoryPressureReceiver] to forward a broadcast to the
         * Dart side. Safe to call from the main thread (broadcasts are
         * delivered there) — the MethodChannel invoke is non-blocking and the
         * Dart handler runs on the UI thread's platform channel executor.
         *
         * The [pendingResult] from `BroadcastReceiver.goAsync()` is held until
         * the Dart side ACKs (or the timeout fires), at which point
         * `finish()` is called *after* the Binder transact completes.
         */
        @JvmStatic
        fun forward(context: Context, level: String, binder: IBinder?, pendingResult: BroadcastReceiver.PendingResult?) {
            // Post to the main thread to guarantee we never block the
            // broadcast dispatch thread, even if the receiver was invoked
            // from a background context.
            val plugin = instance
            if (plugin == null) {
                // Plugin not attached yet. ACK as not handled so the system
                // does not wait. finish() in onComplete after transact.
                Log.w(TAG, "Plugin not attached; ACKing $level as not handled")
                MemoryPressureReceiver.acknowledge(binder, false) {
                    pendingResult?.finish()
                }
                return
            }
            plugin.mainHandler.post { plugin.handleForward(level, binder, pendingResult) }
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
