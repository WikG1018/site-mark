package io.github.wikg1018.sitemark.system

import java.io.File

/** Minimal storage contract used to make MediaStore replacement testable. */
internal interface PublishedImageStore {
    /** Returns the URIs of ALL published rows with [displayName]. */
    fun findAll(displayName: String): List<String>

    fun insertPending(displayName: String): String

    fun write(contentUri: String, source: File)

    fun setPending(contentUri: String, pending: Boolean)

    fun delete(contentUri: String)
}

/** Result of publishing (or replacing) a published image. */
internal data class SafePublishOutcome(
    val contentUri: String,
    /**
     * Every superseded row whose deletion failed after the new row was
     * finalized. Non-empty means the publish SUCCEEDED; the caller must
     * queue a best-effort delete of each URI instead of re-publishing or
     * reporting failure.
     */
    val supersededUris: List<String> = emptyList(),
)

/**
 * Durably persists a publish intent right after the replacement row is
 * finalized but BEFORE any superseded row is deleted, so a process death
 * between the native publish and the caller's database commit can be
 * reconciled on the next launch.
 *
 * Returns whether the entry was durably persisted. `null` (no journal
 * configured) counts as persisted so tests without a journal keep the
 * straightforward delete path.
 */
internal fun interface PublishJournalSink {
    fun record(
        displayName: String,
        contentUri: String,
        supersededUris: List<String>,
    ): Boolean
}

/**
 * Publishes a new image or safely replaces an existing one.
 *
 * Replacement never mutates the old rows' bytes: a new pending row is
 * created, fully written, and finalized first; only then are the old rows
 * deleted. ALL published rows sharing the display name are superseded, so
 * duplicates left behind by earlier failed replacements also converge.
 * Once the new row is finalized the publish is a SUCCESS — later old-row
 * delete failures are reported through [SafePublishOutcome.supersededUris]
 * so the caller can retry just those deletes, never re-publish (which
 * would accumulate duplicates):
 *
 * - Write or finalize failure → the pending row is cleaned up, the old
 *   published photo is untouched, and the error propagates.
 * - Old-row delete failure → the finalized new photo stays published and
 *   the caller receives the stale URI in [SafePublishOutcome.supersededUris];
 *   a temporary duplicate is acceptable and later cleanup converges on it.
 * - Process death at any point → a partially written row stays
 *   `IS_PENDING` and is invisible to other apps.
 */
internal class SafeMediaPublisher(
    private val store: PublishedImageStore,
    private val journal: PublishJournalSink? = null,
) {
    fun publish(source: File, displayName: String): SafePublishOutcome {
        val existing = store.findAll(displayName)
        return if (existing.isEmpty()) {
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
        } catch (error: Throwable) {
            try {
                store.delete(created)
            } catch (cleanupError: Throwable) {
                error.addSuppressed(cleanupError)
            }
            throw error
        }
        // Journal the finalized new row even on the first publish: a crash
        // before the caller commits would otherwise leave an untracked
        // gallery orphan.
        journal?.record(displayName, created, emptyList())
        return SafePublishOutcome(contentUri = created)
    }

    private fun replaceExisting(
        supersededCandidates: List<String>,
        source: File,
        displayName: String,
    ): SafePublishOutcome {
        val created = store.insertPending(displayName)
        try {
            // Write the complete replacement into the new pending row while
            // the old published rows are still untouched and visible.
            store.write(created, source)
            // Finalize the new row BEFORE removing the old ones. From this
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
        // Persist the publish intent BEFORE deleting anything: if the
        // process dies mid-delete, recovery learns both the new URI and
        // every stale candidate (re-queuing an already-deleted URI is an
        // idempotent no-op). When the journal cannot be persisted, keep the
        // old rows and report them ALL as superseded — the caller's
        // transactional cleanup queue then owns their tracking instead of a
        // journal we know was never written.
        val journaled = journal?.record(displayName, created, supersededCandidates) ?: true
        if (!journaled) {
            return SafePublishOutcome(contentUri = created, supersededUris = supersededCandidates)
        }
        // Best effort: remove EVERY superseded row with this display name —
        // including duplicates left behind by earlier failed replacements —
        // so the gallery converges to a single row. A delete failure must
        // NOT fail the publish (the caller would re-publish and accumulate
        // more duplicates); report the stale URI so only that delete is
        // retried later.
        val superseded = mutableListOf<String>()
        for (candidate in supersededCandidates) {
            try {
                store.delete(candidate)
            } catch (_: Throwable) {
                superseded.add(candidate)
            }
        }
        return SafePublishOutcome(contentUri = created, supersededUris = superseded)
    }
}
