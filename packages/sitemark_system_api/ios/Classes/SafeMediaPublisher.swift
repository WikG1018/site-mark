import Foundation

/// Minimal storage contract used to make photo-library replacement
/// testable. The production adapter (Phase 2b) wraps PHPhotoLibrary; the
/// Android counterpart wraps MediaStore.
public protocol PublishedImageStore: AnyObject {
    func insertPending(displayName: String) throws -> String
    func write(contentUri: String, source: URL) throws
    func setPending(contentUri: String, pending: Bool) throws
    func delete(contentUri: String) throws
}

/// Result of publishing (or replacing) a published image.
public struct SafePublishOutcome: Equatable {
    public let contentUri: String

    /// Every superseded candidate the caller passed in, reported verbatim.
    /// The publisher never deletes gallery assets itself — legacy upgrades
    /// can leave two records sharing one asset, so the caller must queue a
    /// reference-checked, delete-only cleanup for each URI instead.
    public let supersededUris: [String]

    public init(contentUri: String, supersededUris: [String]) {
        self.contentUri = contentUri
        self.supersededUris = supersededUris
    }
}

/// Durably persists a publish intent right after the replacement asset is
/// finalized but BEFORE any superseded row is deleted, so a process death
/// between the native publish and the caller's database commit can be
/// reconciled on the next launch. Returns whether the entry was durably
/// persisted. A nil sink (no journal configured) counts as persisted so
/// tests without a journal keep the straightforward path.
public typealias PublishJournalSink =
    (_ captureId: String, _ contentUri: String, _ supersededUris: [String]) -> Bool

/// Publishes a new image or safely replaces a previously published one.
///
/// WHICH rows may be superseded is decided EXCLUSIVELY by the caller
/// through `supersededCandidates` — the exact previous URI of THIS capture
/// plus any leftover journaled URIs of the same capture. Rows that merely
/// share the display name are NEVER candidates: a backup restore preserves
/// photo numbers, so another capture (even in another project) may
/// legitimately own a same-named gallery row.
///
/// The publisher NEVER deletes superseded rows itself. Legacy upgrades can
/// leave TWO records sharing one gallery URI; only the caller can check the
/// whole database for remaining references before deleting. Every candidate
/// is therefore reported through `SafePublishOutcome.supersededUris` and the
/// caller queues a reference-checked, delete-only cleanup for each:
///
/// - Write or finalize failure → the pending row is cleaned up, superseded
///   rows are untouched, and the error propagates.
/// - Journal persist failure → the finalized row is rolled back
///   (best-effort delete) and the error propagates. Without the journal a
///   process death before the caller's database commit would leave the new
///   gallery photo untracked by anyone — returning "success" here would
///   silently reopen that window.
/// - Process death at any point → a partially written row stays pending and
///   is invisible to other apps; a journaled finalize is reconciled by
///   recovery.
public final class SafeMediaPublisher {
    private let store: PublishedImageStore
    private let journal: PublishJournalSink?

    public init(store: PublishedImageStore, journal: PublishJournalSink? = nil) {
        self.store = store
        self.journal = journal
    }

    public func publish(
        source: URL,
        displayName: String,
        captureId: String,
        supersededCandidates: [String]
    ) throws -> SafePublishOutcome {
        let created = try store.insertPending(displayName: displayName)
        do {
            // Write the complete content into the new pending row while
            // every superseded row is still untouched and visible.
            try store.write(contentUri: created, source: source)
            // Finalize the new row. From this point on the gallery holds a
            // complete published photo, so the publish has succeeded no
            // matter what happens next.
            try store.setPending(contentUri: created, pending: false)
        } catch {
            // Remove the (possibly half-written) pending row so no orphan
            // accumulates. If this cleanup itself fails the row stays
            // pending — invisible to other apps. (Android chains the
            // cleanup error onto the primary via addSuppressed; Swift has
            // no equivalent, so the cleanup error is dropped and the
            // primary error propagates unchanged.)
            try? store.delete(contentUri: created)
            throw error
        }
        // Persist the publish intent. If the process dies before the
        // caller's database commit, recovery learns the new URI AND every
        // stale candidate (re-queuing an already-deleted URI is an
        // idempotent no-op). The journal is keyed by the capture ID, so a
        // same-named row owned by ANOTHER capture is never affected.
        //
        // A failed durable persist MUST fail the publish: no journal means
        // nobody could reconcile a crash between this return and the
        // caller's database commit, and the finalized new row would become
        // an untracked gallery orphan. Roll the new row back (best effort)
        // and propagate so the caller retries the whole publish later; the
        // superseded rows were never touched, so nothing is lost.
        let journaled = journal?(captureId, created, supersededCandidates) ?? true
        if !journaled {
            try? store.delete(contentUri: created)
            throw PolicyError.unableToPersistPublishJournal
        }
        // Report every candidate for the caller's reference-checked,
        // delete-only cleanup queue. The gallery keeps a temporary
        // duplicate until that cleanup runs — acceptable, and the only
        // safe default given the shared-URI legacy state above.
        return SafePublishOutcome(contentUri: created, supersededUris: supersededCandidates)
    }
}
