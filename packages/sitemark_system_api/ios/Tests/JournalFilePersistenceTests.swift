import XCTest

@testable import SiteMarkSystemApiCore

final class JournalFilePersistenceTests: XCTestCase {
    func testRoundTripsThroughARealFileAcrossInstances() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sitemark-journal-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = PublishJournalStore(JournalFilePersistence(directory: directory))

        XCTAssertTrue(
            first.record(
                captureId: "SM-1",
                contentUri: "content://media/external/images/2",
                supersededUris: ["u1", "u2"]))

        // A fresh store over the same file sees the persisted entry — the
        // recovery path runs in a new process after a crash.
        let second = PublishJournalStore(JournalFilePersistence(directory: directory))
        let entries = second.recover()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.captureId, "SM-1")
        XCTAssertEqual(entries.first?.contentUri, "content://media/external/images/2")
        XCTAssertEqual(entries.first?.supersededUris, ["u1", "u2"])
    }

    func testCommitReportsFailureWhenTheDirectoryIsNotWritable() throws {
        let blocker = FileManager.default.temporaryDirectory
            .appendingPathComponent("sitemark-journal-blocker-\(UUID().uuidString)")
        try Data("not a directory".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }

        let persistence = JournalFilePersistence(directory: blocker)
        XCTAssertNil(persistence.snapshot())
        XCTAssertFalse(
            persistence.commit([
                "journal.<encoded>.newUri": .put(.string("content://media/external/images/2"))
            ]))
    }
}
