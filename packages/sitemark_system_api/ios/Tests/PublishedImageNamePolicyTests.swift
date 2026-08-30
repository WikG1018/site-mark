import XCTest

@testable import SiteMarkSystemApiCore

final class PublishedImageNamePolicyTests: XCTestCase {
    func testStripsJpegSuffixesCaseSensitivelyAndAppendsJpg() throws {
        XCTAssertEqual(try PublishedImageNamePolicy.normalizedJpegName("capture"), "capture.jpg")
        XCTAssertEqual(
            try PublishedImageNamePolicy.normalizedJpegName("capture.jpg"), "capture.jpg")
        XCTAssertEqual(
            try PublishedImageNamePolicy.normalizedJpegName("capture.jpeg"), "capture.jpg")
        // Kotlin's removeSuffix is case-sensitive, so an uppercase suffix
        // survives and is doubled — ported verbatim as the Android
        // behavior baseline.
        XCTAssertEqual(
            try PublishedImageNamePolicy.normalizedJpegName("capture.JPG"), "capture.JPG.jpg")
    }

    func testRejectsEmptyAndForbiddenNames() {
        XCTAssertThrowsError(try PublishedImageNamePolicy.normalizedJpegName("")) { error in
            XCTAssertEqual(error as? PolicyError, .invalidPublishedImageName)
        }
        XCTAssertThrowsError(try PublishedImageNamePolicy.normalizedJpegName(" ")) { error in
            // A lone space is \p{Z}, part of the forbidden separator set.
            XCTAssertEqual(error as? PolicyError, .invalidPublishedImageName)
        }
        XCTAssertThrowsError(try PublishedImageNamePolicy.normalizedJpegName("a/b.jpg")) {
            error in
            XCTAssertEqual(error as? PolicyError, .invalidPublishedImageName)
        }
        XCTAssertThrowsError(try PublishedImageNamePolicy.normalizedJpegName("a\u{0}b")) {
            error in
            XCTAssertEqual(error as? PolicyError, .invalidPublishedImageName)
        }
    }

    func testAllowsPlainNamesWithDotsAndHyphens() throws {
        XCTAssertEqual(
            try PublishedImageNamePolicy.normalizedJpegName("SM-1.2026.jpg"), "SM-1.2026.jpg")
    }
}
