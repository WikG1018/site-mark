package io.github.wikg1018.sitemark.memory

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.IBinder
import android.os.Parcel
import android.os.RemoteException
import android.util.Log
import java.util.concurrent.Executors

/**
 * Receives ITGSA (金标联盟) "fair running memory" broadcasts and forwards them
 * to the Flutter side via the `sitemark/memory_pressure` MethodChannel.
 *
 * The OEM Binder callback is held until the Dart side calls back through the
 * channel's `acknowledge` method (see [MemoryPressurePlugin]). If the Dart
 * side does not respond within the OEM timeout, the system falls back to its
 * default behavior (the process is still eligible for trimming/killing).
 *
 * Two actions are handled:
 *
 * - [ACTION_MEMORY_TRIM]: the app should release image caches, dispose
 *   invisible page resources, and pause background polling.
 * - [ACTION_MEMORY_KILL]: the app should persist any unsaved draft state.
 *   This is the last chance before the process is killed.
 *
 * The receiver is registered statically in `AndroidManifest.xml` so it fires
 * even when the app process is in the background. On non-ITGSA ROMs the
 * intents are never broadcast, so the receiver adds zero overhead.
 */
class MemoryPressureReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return
        val level = when (intent.action) {
            ACTION_MEMORY_TRIM -> "trim"
            ACTION_MEMORY_KILL -> "kill"
            else -> return
        }
        // Log at INFO level so real-device verification via logcat can
        // confirm the broadcast was actually delivered by the OEM ROM.
        Log.i(TAG, "Received ${intent.action} (level=$level)")

        // The ITGSA spec passes a Binder through the intent extras so the app
        // can ACK the pressure event. The exact extra key varies by ROM
        // vendor; the published developer docs use "itgsa_memory_callback".
        // We probe for the documented key and a couple of fallbacks observed
        // on early adopter builds so the ACK path works across vendors.
        val callbackBinder = pickCallbackBinder(intent)

        // Use goAsync() so the broadcast stays alive while the Dart side
        // processes the pressure event (image cache flush, draft persistence,
        // Binder ACK). Without this, Android may lower the process priority
        // or terminate it as soon as onReceive() returns, causing the async
        // cleanup and ACK to be lost. The PendingResult is held by the plugin
        // and finished when the Dart side ACKs, or after a strict timeout.
        val pendingResult = goAsync()
        MemoryPressurePlugin.forward(context, level, callbackBinder, pendingResult)
    }

    private fun pickCallbackBinder(intent: Intent): IBinder? {
        // Try the documented keys first, then the fallbacks observed in the
        // wild. Bundle.getBinder(String) is the public, non-deprecated API
        // for retrieving a raw IBinder from a Bundle; it has been available
        // since API 1 and is NOT subject to the hidden-API restrictions that
        // removed the deprecated getIBinder(String) in compileSdk 36. If the
        // ITGSA ROM ships a Bundle implementation that does not round-trip
        // the Binder through getBinder (unlikely but possible on a pre-release
        // ROM), fall back to reflection on the legacy getIBinder method.
        val keys = listOf(
            "itgsa_memory_callback",
            "memory_callback",
            "callback",
        )
        val extras = intent.extras ?: return null
        for (key in keys) {
            val binder = extras.getBinder(key)
            if (binder != null) {
                Log.i(TAG, "Binder found via key '$key' (getBinder)")
                return binder
            }
        }
        // Reflection fallback for ROMs whose Bundle implementation does not
        // surface the OEM Binder through the public getBinder path. The
        // legacy getIBinder was removed from the compileSdk 36 stub but
        // still exists at runtime on all shipping Android versions.
        val getIBinder = try {
            Bundle::class.java.getMethod("getIBinder", String::class.java)
        } catch (_: NoSuchMethodException) {
            null
        }
        if (getIBinder != null) {
            for (key in keys) {
                val binder = getIBinder.invoke(extras, key) as? IBinder
                if (binder != null) {
                    Log.i(TAG, "Binder found via key '$key' (getIBinder reflection)")
                    return binder
                }
            }
        } else {
            Log.w(TAG, "Bundle.getIBinder unavailable; OEM Binder callback cannot be retrieved")
        }
        return null
    }

    internal companion object {
        const val ACTION_MEMORY_TRIM = "itgsa.intent.action.MEMORY_TRIM"
        const val ACTION_MEMORY_KILL = "itgsa.intent.action.MEMORY_KILL"

        private const val TAG = "MemoryPressureReceiver"

        // The Binder transaction code used to ACK a pressure event. ITGSA
        // defines a single transaction whose data is a 4-byte int (1 =
        // handled, 0 = not handled) written after the interface token. The
        // interface descriptor is documented as "itgsa.memory.ICallback" but
        // is only validated on builds that ship the validator; on other
        // builds the transact is a no-op.
        private const val DESCRIPTOR = "itgsa.memory.ICallback"
        private const val TRANSACTION_ON_HANDLE = 1

        // Single-thread executor for Binder ACK transactions. The transact
        // call is a synchronous IPC into system_server's memory-management
        // path; running it on the main thread risks ANR if system_server is
        // busy handling the very memory event we are ACKing (ITGSA I3 fix).
        // A single-thread executor serializes ACKs per level (the OEM
        // contract does not allow concurrent ACKs for the same level) while
        // keeping them off the main thread.
        private val ackExecutor = Executors.newSingleThreadExecutor { r ->
            Thread(r, "MemoryPressureAck").apply { isDaemon = true }
        }

        /**
         * Notifies the OEM Binder that the pressure event was handled.
         *
         * Safe to call from any thread. Posts the actual `transact` call to
         * a background worker thread so a slow system_server response cannot
         * ANR the caller (typically the main thread). Catches
         * [RemoteException] so a dead binder (process already gone) does not
         * crash the caller.
         *
         * [onComplete] is invoked after the transact finishes (success or
         * failure) on the executor thread. Callers use it to release the
         * BroadcastReceiver PendingResult *after* the ACK is sent, so the
         * process is not reclaimed before the Binder transaction completes.
         */
        fun acknowledge(
            binder: IBinder?,
            success: Boolean,
            onComplete: (() -> Unit)? = null,
        ) {
            if (binder == null) {
                onComplete?.invoke()
                return
            }
            ackExecutor.execute {
                val data = Parcel.obtain()
                val reply = Parcel.obtain()
                try {
                    data.writeInterfaceToken(DESCRIPTOR)
                    data.writeInt(if (success) 1 else 0)
                    binder.transact(TRANSACTION_ON_HANDLE, data, reply, 0)
                    // reply is intentionally not parsed; the OEM contract
                    // only requires the transaction itself.
                } catch (_: RemoteException) {
                    // The binder is dead (e.g. the system already killed the
                    // service). Nothing to do.
                } catch (e: Exception) {
                    Log.w(TAG, "acknowledge failed", e)
                } finally {
                    data.recycle()
                    reply.recycle()
                }
                onComplete?.invoke()
            }
        }
    }
}
