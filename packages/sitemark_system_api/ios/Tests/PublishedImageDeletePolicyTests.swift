import XCTest

@testable import SiteMarkSystemApiCore

final class PublishedImageDeletePolicyTests: XCTestCase {
    func testAllowsOnlyPhotoLibraryIssuedIdentifiers() {
        XCTAssertTrue(
            PublishedImageDeletePolicy.allowsDelete(
                localIdentifier: "8E8C9E7D-6C0F-4E1B-9D6E-1A2B3C4D5E6F/L0/001"))
        XCTAssertTrue(
            PublishedImageDeletePolicy.allowsDelete(
                localIdentifier: "8e8c9e7d-6c0f-4e1b-9d6e-1a2b3c4d5e6f/L0/007"))
    }

    func testRejectsEverythingOutsideTheAllowlist() {
        XCTAssertFalse(PublishedImageDeletePolicy.allowsDelete(localIdentifier: nil))
        XCTAssertFalse(PublishedImageDeletePolicy.allowsDelete(localIdentifier: ""))
        XCTAssertFalse(
            PublishedImageDeletePolicy.allowsDelete(
                localIdentifier: "content://media/external/images/2"))
        XCTAssertFalse(PublishedImageDeletePolicy.allowsDelete(localIdentifier: "ABC/L0/001"))
        XCTAssertFalse(
            PublishedImageDeletePolicy.allowsDelete(
                localIdentifier: "8E8C9E7D-6C0F-4E1B-9D6E-1A2B3C4D5E6F/L1/001"))
        XCTAssertFalse(
            PublishedImageDeletePolicy.allowsDelete(
                localIdentifier: "8E8C9E7D-6C0F-4E1B-9D6E-1A2B3C4D5E6F/L0/1"))
        XCTAssertFalse(
            PublishedImageDeletePolicy.allowsDelete(
                localIdentifier: "../Pictures/SiteMark"))
    }
}
