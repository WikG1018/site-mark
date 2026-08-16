package io.github.wikg1018.sitemark.system

import java.io.File

/** Minimal storage contract used to make MediaStore replacement testable. */
internal interface PublishedImageStore {
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
 * The key is the caller's stable CAPTURE ID (never the display name: a
 * backup restore can duplicate photo numbers across projects). Returns
 * whether the entry was durably persisted. `null` (no journal configured)
 * counts as persisted so tests without a journal keep the straightforward
 * delete path.
 */
internal fun interface PublishJournalSink {
    fun record(
        captureId: String,
        contentUri: String,
        supersededUris: List<String>,
    ): Boolean
}

/**
 * Publishes a new image or safely replaces a previously published one.
 *
 * WHICH rows may be superseded is decided EXCLUSIVELY by the caller through
 * [supersededCandidates] — the exact previous URI of THIS capture plus any
 * leftover journaled URI of the same capture. Rows that merely share the
 * display name are NEVER touched: a backup restore preserves photo numbers,
 * so another capture (even in another project) may legitimately own a
 * same-named gallery row.
 *
 * The caller's rows are never mutated in place: a new pending row is
 * created, fully written, and finalized first; only then are the superseded
 * rows deleted. Once the new row is finalized the publish is a SUCCESS —
 * later old-row delete failures are reported through
 * [SafePublishOutcome.supersededUris] so the caller can retry just those
 * deletes, never re-publish (which would accumulate duplicates):
 *
 * - Write or finalize failure → the pending row is cleaned up, superseded
 *   rows are untouched, and the error propagates.
 * - Journal persist failure → the finalized row is rolled back
 *   (best-effort delete) and the error propagates. Without the journal a
 *   process death before the caller's database commit would leave the new
 *   gallery photo untracked by anyone — returning "success" here would
 *   silently reopen that window.
 * - Superseded-row delete failure → the finalized new photo stays published
 *   and the caller receives the stale URI in
 *   [SafePublishOutcome.supersededUris]; a temporary duplicate is
 *   acceptable and later cleanup converges on it.
 * - Process death at any point → a partially written row stays
 *   `IS_PENDING` and is invisible to other apps; a journaled finalize is
 *   reconciled by recovery.
 */
internal class SafeMediaPublisher(
    private val store: PublishedImageStore,
    private val journal: PublishJournalSink? = null,
) {
    fun publish(
        source: File,
        displayName: String,
        captureId: String,
        supersededCandidates: List<String>,
    ): SafePublishOutcome {
        val created = store.insertPending(displayName)
        try {
            // Write the complete content into the new pending row while
            // every superseded row is still untouched and visible.
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
        // idempotent no-op). The journal is keyed by the capture ID, so a
        // same-named row owned by ANOTHER capture is never affected.
        //
        // A failed durable persist MUST fail the publish: no journal means
        // nobody could reconcile a crash between this return and the
        // caller's database commit, and the finalized new row would become
        // an untracked gallery orphan. Roll the new row back (best effort)
        // and propagate so the caller retries the whole publish later; the
        // superseded rows were never touched, so nothing is lost.
        val journaled = journal?.record(captureId, created, supersededCandidates) ?: true
        if (!journaled) {
            try {
                store.delete(created)
            } catch (_: Throwable) {
                // Best effort under an already-degraded disk: the row stays
                // published but this publish is still reported as failed.
            }
            error("Unable to persist the publish journal")
        }
        // Best effort: remove only the EXPLICIT superseded URIs. A delete
        // failure must NOT fail the publish (the caller would re-publish
        // and accumulate more duplicates); report the stale URI so only
        // that delete is retried later.
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
