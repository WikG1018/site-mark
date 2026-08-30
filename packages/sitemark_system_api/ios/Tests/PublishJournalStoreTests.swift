import XCTest

@testable import SiteMarkSystemApiCore

private func encoded(_ captureId: String) -> String {
    PublishJournalStore.encodeCaptureId(captureId)
}

/// In-memory journal persistence double; commits go straight into `values`.
private final class FakeJournalPersistence: JournalPersistence {
    var values: [String: JournalValue] = [:]

    /// Returned by every commit; flip to simulate disk failure.
    var commitResult = true

    /// Test-only hook that pauses a commit containing removals.
    var beforeRemovalCommit: (() -> Void)?

    func snapshot() -> [String: JournalValue]? { values }

    func commit(_ mutations: [String: JournalMutation]) -> Bool {
        let hasRemovals = mutations.values.contains { mutation in
            if case .remove = mutation { return true }
            return false
        }
        if hasRemovals {
            beforeRemovalCommit?()
        }
        for (key, mutation) in mutations {
            switch mutation {
            case .put(let value):
                values[key] = value
            case .remove:
                values.removeValue(forKey: key)
            }
        }
        return commitResult
    }
}

/// Verifies `PublishJournalStore` against an in-memory persistence double:
/// record/recover round-trip, durable-commit failure reporting, skipping of
/// incomplete entries, and targeted clear.
final class PublishJournalStoreTests: XCTestCase {
    func testRecordAndRecoverRoundTripsAnEntry() {
        let store = PublishJournalStore(FakeJournalPersistence())

        let recorded = store.record(
            captureId: "SM-1",
            contentUri: "content://media/external/images/2",
            supersededUris: ["u1", "u2"])

        XCTAssertTrue(recorded)
        let entries = store.recover()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.captureId, "SM-1")
        XCTAssertEqual(entries.first?.contentUri, "content://media/external/images/2")
        XCTAssertEqual(entries.first?.supersededUris, ["u1", "u2"])
    }

    func testRecordReportsAFailedDurableCommit() {
        // 同步落盘失败（磁盘满/损坏）必须让调用方知道，否则发布方会误以为
        // journal 已持久化而删除旧行。
        let persistence = FakeJournalPersistence()
        persistence.commitResult = false
        let store = PublishJournalStore(persistence)

        XCTAssertFalse(
            store.record(
                captureId: "SM-1",
                contentUri: "content://media/external/images/2",
                supersededUris: ["u1"]))
    }

    func testRecoverSkipsIncompleteEntries() {
        let persistence = FakeJournalPersistence()
        // 残缺条目 A：有 .exists 与 .staleCount 但缺 .newUri —— 恢复时被跳过。
        let brokenPrefix = "journal.\(encoded("Broken"))"
        persistence.values[brokenPrefix + ".exists"] = .bool(true)
        persistence.values[brokenPrefix + ".staleCount"] = .int(1)
        persistence.values[brokenPrefix + ".stale.0"] = .string("content://media/old/1")
        // 残缺条目 B：有 .newUri 但缺 .exists —— 扫描只从 .exists 键出发，不可见。
        let ghostPrefix = "journal.\(encoded("Ghost"))"
        persistence.values[ghostPrefix + ".newUri"] = .string("content://media/ghost/9")
        persistence.values[ghostPrefix + ".staleCount"] = .int(0)
        let store = PublishJournalStore(persistence)

        XCTAssertTrue(store.recover().isEmpty)
    }

    // Regression (persistence-unsafe keys): every key must stay inside the
    // safe alphabet [A-Za-z0-9._-]. The capture ID is embedded as unpadded
    // base64url, so ANY capture ID (NUL, '.', surrogate pairs, emoji, ...)
    // still round-trips, and residue written by other key formats is
    // skipped instead of recovered.
    func testKeysStaySafeAndRoundTripHostileCaptureIds() {
        let persistence = FakeJournalPersistence()
        let store = PublishJournalStore(persistence)
        let hostile = "cap\u{0}.id.值\u{1F4F7}"

        XCTAssertTrue(
            store.record(
                captureId: hostile,
                contentUri: "content://media/external/images/9",
                supersededUris: ["u1"]))

        XCTAssertFalse(persistence.values.isEmpty)
        let safeKeyRegex = try! NSRegularExpression(pattern: "^[A-Za-z0-9._\\-]+$")
        for key in persistence.values.keys {
            let range = NSRange(key.startIndex..., in: key)
            XCTAssertNotNil(
                safeKeyRegex.firstMatch(in: key, range: range),
                "unsafe journal key: \(key)")
        }

        let entries = store.recover()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.captureId, hostile)
        XCTAssertEqual(
            store.peek(captureId: hostile)?.contentUri, "content://media/external/images/9")
        XCTAssertTrue(
            store.clear(captureId: hostile, expectedContentUri: "content://media/external/images/9"))
        XCTAssertTrue(store.recover().isEmpty)
    }

    func testRecoverIgnoresResidueOfRetiredNulSeparatedKeyFormat() {
        let persistence = FakeJournalPersistence()
        // Pre-release builds keyed entries as "journal.<id><NUL>.<field>".
        // The NUL is not base64url, so decoding must fail and recovery must
        // skip the residue instead of returning a corrupted capture ID.
        persistence.values["journal.capture-1\u{0}.exists"] = .bool(true)
        persistence.values["journal.capture-1\u{0}.newUri"] = .string(
            "content://media/external/images/2")
        persistence.values["journal.capture-1\u{0}.staleCount"] = .int(0)
        let store = PublishJournalStore(persistence)

        XCTAssertTrue(store.recover().isEmpty)
    }

    func testClearRemovesOnlyTheTargetedEntry() {
        let store = PublishJournalStore(FakeJournalPersistence())
        store.record(
            captureId: "SM-1",
            contentUri: "content://media/external/images/1",
            supersededUris: ["content://media/old/1"])
        store.record(
            captureId: "SM-2",
            contentUri: "content://media/external/images/2",
            supersededUris: [])

        XCTAssertTrue(store.clear(captureId: "SM-1", expectedContentUri: "content://media/external/images/1"))

        let remaining = store.recover()
        XCTAssertEqual(remaining.map(\.captureId), ["SM-2"])
        let entry = remaining.first
        XCTAssertEqual(entry?.captureId, "SM-2")
        XCTAssertEqual(entry?.contentUri, "content://media/external/images/2")
        XCTAssertEqual(entry?.supersededUris, [])
    }

    func testClearingAMissingEntryIsAnIdempotentSuccess() {
        let store = PublishJournalStore(FakeJournalPersistence())

        XCTAssertTrue(store.clear(captureId: "SM-1", expectedContentUri: "content://media/external/images/1"))
        XCTAssertTrue(store.recover().isEmpty)
    }

    // Regression (interleaved same-capture publishes): an OLDER operation
    // must never clear an entry that a NEWER publish already overwrote —
    // losing it would make the newer finalized publish unrecoverable after
    // a crash. P1 journals U2; P2 journals U3 over it; P1's conditional
    // clear(U2) must leave the journal (still U3) untouched.
    func testClearWithAStaleExpectedURILeavesANewerEntryUntouched() {
        let store = PublishJournalStore(FakeJournalPersistence())
        store.record(
            captureId: "SM-1",
            contentUri: "content://media/external/images/2",
            supersededUris: ["content://media/old/1"])
        store.record(
            captureId: "SM-1",
            contentUri: "content://media/external/images/3",
            supersededUris: ["content://media/old/2"])

        XCTAssertFalse(store.clear(captureId: "SM-1", expectedContentUri: "content://media/external/images/2"))

        let entries = store.recover()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.captureId, "SM-1")
        XCTAssertEqual(entries.first?.contentUri, "content://media/external/images/3")
        XCTAssertEqual(entries.first?.supersededUris, ["content://media/old/2"])
    }

    // Regression (real thread interleaving): clear compares the expected
    // URI and commits its removals; without a shared lock across store
    // instances, a newer record could land in between and then be erased by
    // the stale removal. Two store instances mirror the production setup
    // where publishing runs on a worker while Pigeon clear calls arrive
    // concurrently.
    func testConcurrentClearCannotRemoveANewerJournalEntry() {
        let persistence = FakeJournalPersistence()
        let clearingStore = PublishJournalStore(persistence)
        let recordingStore = PublishJournalStore(persistence)
        XCTAssertTrue(
            clearingStore.record(
                captureId: "SM-1",
                contentUri: "content://media/external/images/1",
                supersededUris: []))

        let clearReachedCommit = DispatchSemaphore(value: 0)
        let newerRecordStarted = DispatchSemaphore(value: 0)
        let newerRecordFinished = DispatchSemaphore(value: 0)
        var newerRecordStartedConfirmed = false
        persistence.beforeRemovalCommit = {
            clearReachedCommit.signal()
            newerRecordStartedConfirmed =
                newerRecordStarted.wait(timeout: .now() + 2) == .success
            // Without a shared lock, the newer write finishes inside this
            // window and the stale removal then erases it. With the lock,
            // the write waits and lands immediately after clear completes.
            _ = newerRecordFinished.wait(timeout: .now() + 0.25)
        }

        var clearResult = false
        var recordResult = false
        let clearDone = DispatchSemaphore(value: 0)
        let recordDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            clearResult = clearingStore.clear(
                captureId: "SM-1",
                expectedContentUri: "content://media/external/images/1")
            clearDone.signal()
        }
        XCTAssertEqual(clearReachedCommit.wait(timeout: .now() + 2), .success)
        DispatchQueue.global().async {
            newerRecordStarted.signal()
            recordResult = recordingStore.record(
                captureId: "SM-1",
                contentUri: "content://media/external/images/2",
                supersededUris: ["content://media/external/images/1"])
            newerRecordFinished.signal()
            recordDone.signal()
        }

        XCTAssertEqual(clearDone.wait(timeout: .now() + 3), .success)
        XCTAssertEqual(recordDone.wait(timeout: .now() + 3), .success)
        XCTAssertTrue(newerRecordStartedConfirmed)
        XCTAssertTrue(clearResult)
        XCTAssertTrue(recordResult)

        let entries = clearingStore.recover()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.contentUri, "content://media/external/images/2")
        XCTAssertEqual(entries.first?.supersededUris, ["content://media/external/images/1"])
    }

    func testPeekReturnsTheCompleteEntryIncludingSupersededURIs() {
        let store = PublishJournalStore(FakeJournalPersistence())

        XCTAssertNil(store.peek(captureId: "SM-1"))
        store.record(
            captureId: "SM-1",
            contentUri: "content://media/external/images/2",
            supersededUris: ["content://media/old/1"])

        let entry = store.peek(captureId: "SM-1")
        XCTAssertEqual(entry?.contentUri, "content://media/external/images/2")
        XCTAssertEqual(entry?.supersededUris, ["content://media/old/1"])
    }

    // Regression (consecutive crashes): a second publish of the same
    // capture must fold the ENTIRE leftover journal entry — its content URI
    // AND its superseded URIs — into the new candidates. Reading only the
    // content URI would permanently lose tracking of the earliest stale
    // URIs. The overwrite must also drop stale slots beyond the new count
    // so recovery can never mix URIs of two different publishes.
    func testRePublishOverALeftoverEntryReplacesItWithoutResidue() {
        let store = PublishJournalStore(FakeJournalPersistence())
        // First crashed publish: U2 with two stale candidates.
        store.record(
            captureId: "SM-1",
            contentUri: "content://media/external/images/2",
            supersededUris: ["u1", "u2"])
        // Second publish overwrites the entry with fewer stale URIs.
        store.record(
            captureId: "SM-1",
            contentUri: "content://media/external/images/3",
            supersededUris: ["u1"])

        let entries = store.recover()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.contentUri, "content://media/external/images/3")
        XCTAssertEqual(entries.first?.supersededUris, ["u1"])
        // The stale slot of the overwritten entry is gone too.
        XCTAssertEqual(store.peek(captureId: "SM-1")?.supersededUris, ["u1"])
    }
}
