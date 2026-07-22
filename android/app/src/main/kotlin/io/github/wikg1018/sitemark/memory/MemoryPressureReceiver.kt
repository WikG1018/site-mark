package io.github.wikg1018.sitemark.memory

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.IBinder
import android.os.Parcel
import android.os.RemoteException
import android.util.Log

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

        // The ITGSA spec passes a Binder through the intent extras so the app
        // can ACK the pressure event. The exact extra key varies by ROM
        // vendor; the published developer docs use "itgsa_memory_callback".
        // We probe for the documented key and a couple of fallbacks observed
        // on early adopter builds so the ACK path works across vendors.
        val callbackBinder = pickCallbackBinder(intent)

        // Always forward to Flutter (best-effort). The Dart side owns the
        // release/backup logic; we just bridge the signal.
        MemoryPressurePlugin.forward(context, level, callbackBinder)

        // The receiver must not block the main thread. The Binder ACK is
        // posted from the Flutter side after the Dart handlers complete, so
        // here we just return. The system treats returning from onReceive as
        // "broadcast received" but NOT as "memory released"; the actual ACK
        // that defers killing the process happens through the Binder.
    }

    private fun pickCallbackBinder(intent: Intent): IBinder? {
        // Try the documented keys first, then the fallbacks observed in the
        // wild. Using Bundle.getIBinder preserves the Binder across IPC.
        val keys = listOf(
            "itgsa_memory_callback",
            "memory_callback",
            "callback",
        )
        val extras = intent.extras ?: return null
        // Bundle.getIBinder was a public API method that got deprecated in
        // API 34 and removed from the compileSdk 36 stub. The method still
        // exists at runtime on all Android versions; we reach it via
        // reflection so the OEM callback Binder can be retrieved regardless
        // of the compileSdk used to build the app.
        val getIBinder = try {
            Bundle::class.java.getMethod("getIBinder", String::class.java)
        } catch (_: NoSuchMethodException) {
            null
        }
        for (key in keys) {
            val binder = getIBinder?.invoke(extras, key) as? IBinder
            if (binder != null) return binder
        }
        return null
    }

    internal companion object {
        const val ACTION_MEMORY_TRIM = "itgsa.intent.action.MEMORY_TRIM"
        const val ACTION_MEMORY_KILL = "itgsa.intent.action.MEMORY_KILL"

        // The Binder transaction code used to ACK a pressure event. ITGSA
        // defines a single transaction whose data is a 1-byte boolean: 1 =
        // handled, 0 = not handled. The interface descriptor is documented as
        // "itgsa.memory.ICallback" but is only validated on builds that ship
        // the validator; on other builds the transact is a no-op.
        private const val DESCRIPTOR = "itgsa.memory.ICallback"
        private const val TRANSACTION_ON_HANDLE = 1

        /**
         * Notifies the OEM Binder that the pressure event was handled.
         *
         * Safe to call from any thread. Catches [RemoteException] so a dead
         * binder (process already gone) does not crash the caller.
         */
        fun acknowledge(binder: IBinder?, success: Boolean) {
            if (binder == null) return
            val data = Parcel.obtain()
            val reply = Parcel.obtain()
            try {
                data.writeInterfaceToken(DESCRIPTOR)
                data.writeInt(if (success) 1 else 0)
                binder.transact(TRANSACTION_ON_HANDLE, data, reply, 0)
                // reply is intentionally not parsed; the OEM contract only
                // requires the transaction itself.
            } catch (_: RemoteException) {
                // The binder is dead (e.g. the system already killed the
                // service). Nothing to do.
            } catch (e: Exception) {
                Log.w("MemoryPressureReceiver", "acknowledge failed", e)
            } finally {
                data.recycle()
                reply.recycle()
            }
        }
    }
}
