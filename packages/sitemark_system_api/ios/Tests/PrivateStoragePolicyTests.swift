import XCTest

@testable import SiteMarkSystemApiCore

final class PrivateStoragePolicyTests: XCTestCase {
    private func makeTempDirectory(_ label: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sitemark-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testRejectsSourcesOutsideTheSandboxRoot() throws {
        let root = try makeTempDirectory("private")
        let outside = try makeTempDirectory("outside")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let outsideFile = outside.appendingPathComponent("photo.jpg")
        try Data("x".utf8).write(to: outsideFile)

        XCTAssertThrowsError(
            try PrivateStoragePolicy.validatedPrivateFile(
                path: outsideFile.path, sandboxRoot: root)
        ) { error in
            XCTAssertEqual(error as? PolicyError, .privateStorageRequired)
        }
    }

    func testRequiresAnExistingNonEmptyFileInsideTheRoot() throws {
        let root = try makeTempDirectory("private")
        defer { try? FileManager.default.removeItem(at: root) }
        let empty = root.appendingPathComponent("empty.jpg")
        FileManager.default.createFile(atPath: empty.path, contents: nil)
        let real = root.appendingPathComponent("photo.jpg")
        try Data("jpeg-bytes".utf8).write(to: real)

        XCTAssertThrowsError(
            try PrivateStoragePolicy.validatedPrivateFile(path: empty.path, sandboxRoot: root)
        ) { error in
            XCTAssertEqual(error as? PolicyError, .privateFileMissingOrEmpty)
        }
        XCTAssertThrowsError(
            try PrivateStoragePolicy.validatedPrivateFile(
                path: root.appendingPathComponent("missing.jpg").path, sandboxRoot: root)
        ) { error in
            XCTAssertEqual(error as? PolicyError, .privateFileMissingOrEmpty)
        }
        let validated = try PrivateStoragePolicy.validatedPrivateFile(
            path: real.path, sandboxRoot: root)
        XCTAssertEqual(validated.lastPathComponent, "photo.jpg")
    }
}
