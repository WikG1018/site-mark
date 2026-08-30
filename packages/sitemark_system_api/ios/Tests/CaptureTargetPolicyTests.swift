import XCTest

@testable import SiteMarkSystemApiCore

final class CaptureTargetPolicyTests: XCTestCase {
    func testUsesCaptureIdAsDeterministicJpegFileName() throws {
        XCTAssertEqual(
            try CaptureTargetPolicy.fileName(captureId: "2f90c1a8-1234"),
            "2f90c1a8-1234.jpg")
    }

    func testRejectsIdsThatCouldEscapeThePrivateOriginalsDirectory() {
        XCTAssertThrowsError(try CaptureTargetPolicy.fileName(captureId: "../outside")) {
            error in
            XCTAssertEqual(error as? PolicyError, .invalidCaptureId)
        }
    }

    func testOnlyANonEmptyTargetIsConsideredCapturedDuringRecovery() {
        XCTAssertEqual(
            CaptureTargetPolicy.recoveryDisposition(exists: true, length: 512),
            .captured)
        XCTAssertEqual(
            CaptureTargetPolicy.recoveryDisposition(exists: true, length: 0),
            .cancelled)
        XCTAssertEqual(
            CaptureTargetPolicy.recoveryDisposition(exists: false, length: 512),
            .cancelled)
    }
}
