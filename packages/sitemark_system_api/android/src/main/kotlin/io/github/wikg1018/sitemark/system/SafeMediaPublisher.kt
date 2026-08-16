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

/** Result of publishing (or replacing) a published image. */
internal data class SafePublishOutcome(
    val contentUri: String,
    /**
     * The superseded row whose deletion failed after the new row was
     * finalized. Non-null means the publish SUCCEEDED; the caller must
     * queue a best-effort delete of this URI instead of re-publishing or
     * reporting failure.
     */
    val supersededUri: String? = null,
)

/**
 * Publishes a new image or safely replaces an existing one.
 *
 * Replacement never mutates the old row's bytes: a new pending row is
 * created, fully written, and finalized first; only then is the old row
 * deleted. Once the new row is finalized the publish is a SUCCESS — a
 * later old-row delete failure is reported through
 * [SafePublishOutcome.supersededUri] so the caller can retry just that
 * delete, never re-publish (which would accumulate duplicates):
 *
 * - Write or finalize failure → the pending row is cleaned up, the old
 *   published photo is untouched, and the error propagates.
 * - Old-row delete failure → the finalized new photo stays published and
 *   the caller receives [SafePublishOutcome.supersededUri]; a temporary
 *   duplicate is acceptable and later cleanup converges on it.
 * - Process death at any point → a partially written row stays
 *   `IS_PENDING` and is invisible to other apps.
 */
internal class SafeMediaPublisher(
    private val store: PublishedImageStore,
) {
    fun publish(source: File, displayName: String): SafePublishOutcome {
        val existing = store.find(displayName)
        return if (existing == null) {
            publishNew(source, displayName)
        } else {
            replaceExisting(existing, source, displayName)
        }
    }

    private fun publishNew(source: File, displayName: String): SafePublishOutcome {
        val created = store.insertPending(displayName)
        try {
            store.write(created, source)
            store.setPending(created, pending = false)
            return SafePublishOutcome(contentUri = created)
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
    ): SafePublishOutcome {
        val created = store.insertPending(displayName)
        try {
            // Write the complete replacement into the new pending row while
            // the old published row is still untouched and visible.
            store.write(created, source)
            // Finalize the new row BEFORE removing the old one. From this
            // point on the gallery holds a complete published photo, so the
            // publish has succeeded no matter what happens next.
            store.setPending(created, pending = false)
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
        // Best effort: remove the now-superseded old row. A failure must
        // NOT fail the publish — the caller would re-publish and accumulate
        // duplicates. Report the stale URI so only the delete is retried.
        var superseded: String? = null
        try {
            store.delete(contentUri)
        } catch (_: Throwable) {
            superseded = contentUri
        }
        return SafePublishOutcome(contentUri = created, supersededUri = superseded)
    }
}
