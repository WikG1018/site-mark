import XCTest

@testable import SiteMarkSystemApiCore

private final class FakePublishedImageStore: PublishedImageStore {
    enum FakeStoreError: Error, Equatable {
        case writeFailed
        case finalizeFailed
    }

    final class Row {
        var bytes: String
        var pending: Bool

        init(bytes: String, pending: Bool) {
            self.bytes = bytes
            self.pending = pending
        }
    }

    static let oldURI = "content://media/site-mark/1"
    static let duplicateURI = "content://media/site-mark/0"
    static let newURI = "content://media/site-mark/2"

    private(set) var rows: [String: Row] = [:]
    var failWrite = false
    var failFinalize = false

    init(existingBytes: String?, duplicateBytes: String? = nil) {
        if let existingBytes {
            rows[Self.oldURI] = Row(bytes: existingBytes, pending: false)
        }
        if let duplicateBytes {
            rows[Self.duplicateURI] = Row(bytes: duplicateBytes, pending: false)
        }
    }

    func insertPending(displayName: String) throws -> String {
        rows[Self.newURI] = Row(bytes: "", pending: true)
        return Self.newURI
    }

    func write(contentUri: String, source: URL) throws {
        guard let row = rows[contentUri] else { return }
        row.bytes = "partial"
        if failWrite {
            throw FakeStoreError.writeFailed
        }
        row.bytes = String(decoding: try Data(contentsOf: source), as: UTF8.self)
    }

    func setPending(contentUri: String, pending: Bool) throws {
        if !pending && failFinalize {
            throw FakeStoreError.finalizeFailed
        }
        rows[contentUri]?.pending = pending
    }

    func delete(contentUri: String) throws {
        rows.removeValue(forKey: contentUri)
    }
}

final class SafeMediaPublisherTests: XCTestCase {
    private func makeSource(_ directory: URL, name: String, text: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func makeTempDirectory(_ label: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sitemark-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testReplacementPublishesANewRowAndReportsTheExplicitOldOne() throws {
        let directory = try makeTempDirectory("publisher")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try makeSource(directory, name: "replacement.jpg", text: "new-image")
        let store = FakePublishedImageStore(existingBytes: "old-image")
        let publisher = SafeMediaPublisher(store: store)

        let published = try publisher.publish(
            source: source,
            displayName: "capture.jpg",
            captureId: "capture-1",
            supersededCandidates: [FakePublishedImageStore.oldURI])

        XCTAssertEqual(published.contentUri, FakePublishedImageStore.newURI)
        // The publisher NEVER deletes the old row itself: a legacy upgrade
        // can leave two records sharing one URI, so the caller must queue a
        // reference-checked, delete-only cleanup instead.
        XCTAssertEqual(published.supersededUris, [FakePublishedImageStore.oldURI])
        // The old row survives until the caller's cleanup runs, and the new
        // row is finalized with the new bytes — never a half-written row
        // left visible.
        XCTAssertEqual(store.rows[FakePublishedImageStore.oldURI]?.bytes, "old-image")
        XCTAssertEqual(store.rows[FakePublishedImageStore.newURI]?.bytes, "new-image")
        XCTAssertEqual(store.rows[FakePublishedImageStore.newURI]?.pending, false)
    }

    func testReplacementWriteFailureKeepsTheOldRowIntact() throws {
        let directory = try makeTempDirectory("publisher")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try makeSource(directory, name: "replacement.jpg", text: "new-image")
        let store = FakePublishedImageStore(existingBytes: "old-image")
        store.failWrite = true
        let publisher = SafeMediaPublisher(store: store)

        XCTAssertThrowsError(
            try publisher.publish(
                source: source,
                displayName: "capture.jpg",
                captureId: "capture-1",
                supersededCandidates: [FakePublishedImageStore.oldURI])
        ) { error in
            XCTAssertEqual(error as? FakePublishedImageStore.FakeStoreError, .writeFailed)
        }

        // The old published row was never touched...
        XCTAssertEqual(store.rows[FakePublishedImageStore.oldURI]?.bytes, "old-image")
        XCTAssertEqual(store.rows[FakePublishedImageStore.oldURI]?.pending, false)
        // ...and the partially written pending row is cleaned up.
        XCTAssertNil(store.rows[FakePublishedImageStore.newURI])
    }

    func testEveryCandidateIsReportedVerbatimAndNoRowIsEverDeleted() throws {
        let directory = try makeTempDirectory("publisher")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try makeSource(directory, name: "replacement.jpg", text: "new-image")
        let store = FakePublishedImageStore(
            existingBytes: "old-image",
            duplicateBytes: "older-image")
        let publisher = SafeMediaPublisher(store: store)

        // The publish SUCCEEDED (new row finalized); every stale candidate —
        // including ones whose delete could never succeed — is reported
        // independently for the caller's cleanup queue.
        let published = try publisher.publish(
            source: source,
            displayName: "capture.jpg",
            captureId: "capture-1",
            supersededCandidates: [
                FakePublishedImageStore.oldURI,
                FakePublishedImageStore.duplicateURI,
            ])

        XCTAssertEqual(published.contentUri, FakePublishedImageStore.newURI)
        XCTAssertEqual(
            Set(published.supersededUris),
            Set([FakePublishedImageStore.oldURI, FakePublishedImageStore.duplicateURI]))
        XCTAssertEqual(store.rows[FakePublishedImageStore.newURI]?.pending, false)
        // Neither stale row was touched by the publisher.
        XCTAssertEqual(store.rows[FakePublishedImageStore.oldURI]?.bytes, "old-image")
        XCTAssertEqual(store.rows[FakePublishedImageStore.duplicateURI]?.bytes, "older-image")
    }

    // Regression (backup restore): which rows may be superseded is decided
    // EXCLUSIVELY by the caller's explicit candidate list. A same-named row
    // owned by ANOTHER capture — e.g. the original project's row while a
    // restored project re-saves its photo with the same preserved photo
    // number — must NEVER become a candidate.
    func testSameNamedRowsOutsideTheExplicitCandidatesAreNeverReported() throws {
        let directory = try makeTempDirectory("publisher")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try makeSource(directory, name: "replacement.jpg", text: "new-image")
        // Both pre-existing rows share the display name "capture.jpg", but
        // only oldURI belongs to THIS capture.
        let store = FakePublishedImageStore(
            existingBytes: "old-image",
            duplicateBytes: "other-captures-image")
        let publisher = SafeMediaPublisher(store: store)

        let published = try publisher.publish(
            source: source,
            displayName: "capture.jpg",
            captureId: "capture-1",
            supersededCandidates: [FakePublishedImageStore.oldURI])

        XCTAssertEqual(published.contentUri, FakePublishedImageStore.newURI)
        // Only the explicit candidate is reported for cleanup...
        XCTAssertEqual(published.supersededUris, [FakePublishedImageStore.oldURI])
        // ...while the same-named row of the OTHER capture is neither
        // deleted nor queued — deleting it would destroy the original
        // project's published photo.
        XCTAssertEqual(store.rows[FakePublishedImageStore.duplicateURI]?.bytes, "other-captures-image")
        XCTAssertEqual(store.rows[FakePublishedImageStore.duplicateURI]?.pending, false)
        XCTAssertEqual(store.rows[FakePublishedImageStore.newURI]?.pending, false)
    }

    func testFinalizeFailureKeepsTheOldRowAndCleansThePendingRow() throws {
        let directory = try makeTempDirectory("publisher")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try makeSource(directory, name: "replacement.jpg", text: "new-image")
        let store = FakePublishedImageStore(existingBytes: "old-image")
        store.failFinalize = true
        let publisher = SafeMediaPublisher(store: store)

        XCTAssertThrowsError(
            try publisher.publish(
                source: source,
                displayName: "capture.jpg",
                captureId: "capture-1",
                supersededCandidates: [FakePublishedImageStore.oldURI])
        ) { error in
            XCTAssertEqual(error as? FakePublishedImageStore.FakeStoreError, .finalizeFailed)
        }

        // Finalization happens before the old row is removed, so the old
        // published photo is untouched and the unfinalized pending row must
        // not linger as an orphan; the caller can safely retry.
        XCTAssertEqual(store.rows[FakePublishedImageStore.oldURI]?.bytes, "old-image")
        XCTAssertEqual(store.rows[FakePublishedImageStore.oldURI]?.pending, false)
        XCTAssertNil(store.rows[FakePublishedImageStore.newURI])
    }

    func testJournalRecordsTheFinalizedPublishBeforeAnySupersededCleanup() throws {
        let directory = try makeTempDirectory("publisher")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try makeSource(directory, name: "replacement.jpg", text: "new-image")
        let store = FakePublishedImageStore(existingBytes: "old-image")
        var calls: [(captureId: String, uri: String, superseded: [String])] = []
        let journal: PublishJournalSink = { captureId, uri, superseded in
            calls.append((captureId, uri, superseded))
            // 时序证明：journal 被调用时新行已转正、旧行还未被任何清理触碰
            // —— 转正之后、清理之前。
            XCTAssertTrue(store.rows.keys.contains(FakePublishedImageStore.oldURI))
            XCTAssertEqual(store.rows[FakePublishedImageStore.newURI]?.pending, false)
            return true
        }
        let publisher = SafeMediaPublisher(store: store, journal: journal)

        let published = try publisher.publish(
            source: source,
            displayName: "capture.jpg",
            captureId: "capture-1",
            supersededCandidates: [FakePublishedImageStore.oldURI])

        // journal 恰好记录一次，键为稳定的 captureId（绝非照片编号：备份
        // 恢复后两个项目可能同时存在相同编号）。
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.captureId, "capture-1")
        XCTAssertEqual(calls.first?.uri, FakePublishedImageStore.newURI)
        XCTAssertEqual(calls.first?.superseded, [FakePublishedImageStore.oldURI])
        XCTAssertEqual(published.contentUri, FakePublishedImageStore.newURI)
        XCTAssertEqual(published.supersededUris, [FakePublishedImageStore.oldURI])
    }

    // Regression: a journal that failed to persist durably MUST fail the
    // publish. Returning "success" would let the process die between this
    // return and the caller's database commit, leaving the finalized new
    // gallery photo tracked by nobody. The new row is rolled back
    // (best-effort) and the untouched superseded rows stay published.
    func testJournalWriteFailureRollsBackTheFinalizedRowAndFailsThePublish() throws {
        let directory = try makeTempDirectory("publisher")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try makeSource(directory, name: "replacement.jpg", text: "new-image")
        let store = FakePublishedImageStore(existingBytes: "old-image")
        let publisher = SafeMediaPublisher(store: store, journal: { _, _, _ in false })

        XCTAssertThrowsError(
            try publisher.publish(
                source: source,
                displayName: "capture.jpg",
                captureId: "capture-1",
                supersededCandidates: [FakePublishedImageStore.oldURI])
        ) { error in
            XCTAssertEqual(error as? PolicyError, .unableToPersistPublishJournal)
        }

        // The finalized new row was rolled back...
        XCTAssertNil(store.rows[FakePublishedImageStore.newURI])
        // ...and the superseded row was never deleted (it is still the
        // photo the caller's database references).
        XCTAssertEqual(store.rows[FakePublishedImageStore.oldURI]?.bytes, "old-image")
        XCTAssertEqual(store.rows[FakePublishedImageStore.oldURI]?.pending, false)
    }

    func testFirstPublishJournalsTheNewRowWithNoSupersededCandidates() throws {
        let directory = try makeTempDirectory("publisher")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try makeSource(directory, name: "new.jpg", text: "new-image")
        let store = FakePublishedImageStore(existingBytes: nil)
        var calls: [(captureId: String, uri: String, superseded: [String])] = []
        let journal: PublishJournalSink = { captureId, uri, superseded in
            calls.append((captureId, uri, superseded))
            return true
        }
        let publisher = SafeMediaPublisher(store: store, journal: journal)

        let published = try publisher.publish(
            source: source,
            displayName: "capture.jpg",
            captureId: "capture-1",
            supersededCandidates: [])

        // 首次发布也要 journal：否则提交前崩溃会留下无人追踪的孤儿。
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.captureId, "capture-1")
        XCTAssertEqual(calls.first?.uri, FakePublishedImageStore.newURI)
        XCTAssertEqual(calls.first?.superseded, [])
        XCTAssertEqual(published.contentUri, FakePublishedImageStore.newURI)
        XCTAssertTrue(published.supersededUris.isEmpty)
    }

    func testNewImageFailureDeletesItsPendingRow() throws {
        let directory = try makeTempDirectory("publisher")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try makeSource(directory, name: "new.jpg", text: "new-image")
        let store = FakePublishedImageStore(existingBytes: nil)
        store.failWrite = true
        let publisher = SafeMediaPublisher(store: store)

        XCTAssertThrowsError(
            try publisher.publish(
                source: source,
                displayName: "capture.jpg",
                captureId: "capture-1",
                supersededCandidates: [])
        ) { error in
            XCTAssertEqual(error as? FakePublishedImageStore.FakeStoreError, .writeFailed)
        }

        XCTAssertTrue(store.rows.isEmpty)
    }
}
