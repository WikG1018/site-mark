package io.github.wikg1018.sitemark.system

import java.io.File

/** Minimal storage contract used to make MediaStore replacement testable. */
internal interface PublishedImageStore {
    fun find(displayName: String): String?

    fun insertPending(displayName: String): String

    fun backup(contentUri: String, destination: File)

    fun write(contentUri: String, source: File)

    fun setPending(contentUri: String, pending: Boolean)

    fun delete(contentUri: String)
}

/**
 * Publishes a new image or safely replaces an existing one.
 *
 * Existing bytes are copied to app-private cache before MediaStore is
 * mutated. If replacement fails, the previous bytes and published state are
 * restored before the original error is rethrown.
 */
internal class SafeMediaPublisher(
    private val store: PublishedImageStore,
    private val createBackupFile: () -> File,
) {
    fun publish(source: File, displayName: String): String {
        val existing = store.find(displayName)
        return if (existing == null) {
            publishNew(source, displayName)
        } else {
            replaceExisting(existing, source)
        }
    }

    private fun publishNew(source: File, displayName: String): String {
        val created = store.insertPending(displayName)
        try {
            store.write(created, source)
            store.setPending(created, pending = false)
            return created
        } catch (error: Throwable) {
            try {
                store.delete(created)
            } catch (cleanupError: Throwable) {
                error.addSuppressed(cleanupError)
            }
            throw error
        }
    }

    private fun replaceExisting(contentUri: String, source: File): String {
        val backup = createBackupFile()
        var pendingSet = false
        try {
            // A backup failure is safe: the existing row is still untouched.
            store.backup(contentUri, backup)
            store.setPending(contentUri, pending = true)
            pendingSet = true
            store.write(contentUri, source)
            store.setPending(contentUri, pending = false)
            return contentUri
        } catch (error: Throwable) {
            if (pendingSet) {
                val restored = try {
                    store.write(contentUri, backup)
                    true
                } catch (restoreError: Throwable) {
                    error.addSuppressed(restoreError)
                    false
                }
                // Do not expose potentially partial bytes if both the
                // replacement and restoration writes failed.
                if (restored) {
                    clearPendingAfterFailure(contentUri, error)
                }
            }
            throw error
        } finally {
            try {
                backup.delete()
            } catch (_: Throwable) {
                // Cache cleanup must not mask publication success or failure.
            }
        }
    }

    private fun clearPendingAfterFailure(contentUri: String, error: Throwable) {
        try {
            store.setPending(contentUri, pending = false)
        } catch (cleanupError: Throwable) {
            error.addSuppressed(cleanupError)
        }
    }
}
