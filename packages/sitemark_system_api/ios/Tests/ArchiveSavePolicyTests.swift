import XCTest

@testable import SiteMarkSystemApiCore

final class ArchiveSavePolicyTests: XCTestCase {
    private func makeTempDirectory(_ label: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sitemark-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testValidatesPrivateZipAndStreamsItsBytes() throws {
        let root = try makeTempDirectory("archive")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("backup.zip")
        let payload = Data((0..<(64 * 1024)).map { UInt8($0 % 251) })
        try payload.write(to: source)

        let validated = try ArchiveSavePolicy.validateSource(
            sourcePath: source.path, dataDirectory: root)
        let destination = root.appendingPathComponent("chosen.zip")
        try ArchiveSavePolicy.copy(source: validated, destination: destination)

        XCTAssertEqual(try Data(contentsOf: destination), payload)
    }

    func testRejectsOutsidePrivateStorageAndNonZipFiles() throws {
        let root = try makeTempDirectory("private")
        let outside = try makeTempDirectory("outside")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let outsideZip = outside.appendingPathComponent("backup.zip")
        try Data("zip".utf8).write(to: outsideZip)
        let privateText = root.appendingPathComponent("backup.txt")
        try Data("text".utf8).write(to: privateText)

        XCTAssertThrowsError(
            try ArchiveSavePolicy.validateSource(
                sourcePath: outsideZip.path, dataDirectory: root)
        ) { error in
            XCTAssertEqual(error as? PolicyError, .backupSourceNotPrivate)
        }
        XCTAssertThrowsError(
            try ArchiveSavePolicy.validateSource(
                sourcePath: privateText.path, dataDirectory: root)
        ) { error in
            XCTAssertEqual(error as? PolicyError, .backupSourceNotZip)
        }
    }

    func testNormalizesOnlySafeZipNames() throws {
        XCTAssertEqual(
            try ArchiveSavePolicy.normalizeSuggestedName("sitemark-backup-123.zip"),
            "sitemark-backup-123.zip")
        XCTAssertThrowsError(try ArchiveSavePolicy.normalizeSuggestedName("../backup.zip")) {
            error in
            XCTAssertEqual(error as? PolicyError, .invalidBackupFilename)
        }
        XCTAssertThrowsError(try ArchiveSavePolicy.normalizeSuggestedName("backup.jpg")) {
            error in
            XCTAssertEqual(error as? PolicyError, .invalidBackupFilename)
        }
    }
}
