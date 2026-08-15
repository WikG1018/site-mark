package io.github.wikg1018.sitemark.system

import java.io.File

/** Minimal storage contract used to make MediaStore replacement testable. */
internal interface PublishedImageStore {
    fun find(displayName: String): String?

    fun insertPending(displayName: String): String

    fun write(contentUri: String, source: File)

    fun setPending(contentUri: String, pending: Boolean)

    fun delete(contentUri: String)
}

/**
 * Publishes a new image or safely replaces an existing one.
 *
 * Replacement never mutates the old row's bytes: a new pending row is
 * created, fully written, and finalized first; only then is the old row
 * deleted. Once the new row is finalized the gallery always holds at
 * least one complete photo, no matter what happens next:
 *
 * - Write or finalize failure → the pending row is cleaned up and the old
 *   published photo is untouched.
 * - Old-row delete failure → the finalized new photo stays published; a
 *   temporary duplicate is acceptable and the next cleanup retries the
 *   delete. Deleting both rows could empty the gallery, so the new row is
 *   never removed after finalization.
 * - Process death at any point → a partially written row stays
 *   `IS_PENDING` and is invisible to other apps.
 */
internal class SafeMediaPublisher(
    private val store: PublishedImageStore,
) {
    fun publish(source: File, displayName: String): String {
        val existing = store.find(displayName)
        return if (existing == null) {
            publishNew(source, displayName)
        } else {
            replaceExisting(existing, source, displayName)
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

    private fun replaceExisting(
        contentUri: String,
        source: File,
        displayName: String,
    ): String {
        val created = store.insertPending(displayName)
        var finalized = false
        try {
            // Write the complete replacement into the new pending row while
            // the old published row is still untouched and visible.
            store.write(created, source)
            // Finalize the new row BEFORE removing the old one. From this
            // point on the gallery holds a complete published photo, so a
            // later failure must never delete the new row.
            store.setPending(created, pending = false)
            finalized = true
            // Best effort: remove the now-superseded old row. If this fails
            // a duplicate remains temporarily — recoverable, unlike deleting
            // both rows and leaving the gallery empty.
            store.delete(contentUri)
            return created
        } catch (error: Throwable) {
            if (!finalized) {
                // Remove the (possibly half-written) pending row so no
                // orphan accumulates. If this cleanup itself fails the row
                // stays pending — invisible to other apps and reaped by
                // MediaStore.
                try {
                    store.delete(created)
                } catch (cleanupError: Throwable) {
                    error.addSuppressed(cleanupError)
                }
            }
            throw error
        }
    }
}
