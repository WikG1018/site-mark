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
 * created and fully written first, and only after that succeeds is the old
 * row deleted and the new row finalized. If the process dies at any point,
 * the previously published photo is either intact or (in the narrow window
 * between the old row's deletion and the new row's finalization) recoverable
 * by re-publishing from the private original — a partially written row can
 * never become visible to other apps because it stays `IS_PENDING` until
 * the very last step.
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
        try {
            // Write the complete replacement into the new pending row while
            // the old published row is still untouched and visible.
            store.write(created, source)
            // Remove the old row only after the new bytes are durable. The
            // new row keeps its IS_PENDING state until the name is free, so
            // MediaStore never auto-renames the replacement to "name (1).jpg".
            store.delete(contentUri)
            store.setPending(created, pending = false)
            return created
        } catch (error: Throwable) {
            // Remove the (possibly half-written) pending row so no orphan
            // accumulates. If this cleanup itself fails the row stays
            // pending — invisible to other apps and reaped by MediaStore.
            try {
                store.delete(created)
            } catch (cleanupError: Throwable) {
                error.addSuppressed(cleanupError)
            }
            throw error
        }
    }
}
