import CoreLocation
import XCTest

@testable import SiteMarkSystemApiCore

final class LocationPermissionRequestPolicyTests: XCTestCase {
    func testNotDeterminedDoesNotCompleteInFlightRequest() {
        XCTAssertFalse(
            LocationPermissionRequestPolicy.shouldCompleteInFlightRequest(
                status: .notDetermined))
    }

    func testDeniedCompletesInFlightRequest() {
        XCTAssertTrue(
            LocationPermissionRequestPolicy.shouldCompleteInFlightRequest(
                status: .denied))
    }

    // authorizedWhenInUse is iOS-only: CoreLocation marks it unavailable on
    // macOS, the host the package's `swift test` suite compiles on.
    #if os(iOS)
    func testAuthorizedWhenInUseCompletesInFlightRequest() {
        XCTAssertTrue(
            LocationPermissionRequestPolicy.shouldCompleteInFlightRequest(
                status: .authorizedWhenInUse))
    }
    #endif

    func testRestrictedCompletesInFlightRequest() {
        XCTAssertTrue(
            LocationPermissionRequestPolicy.shouldCompleteInFlightRequest(
                status: .restricted))
    }

    func testAuthorizedAlwaysCompletesInFlightRequest() {
        XCTAssertTrue(
            LocationPermissionRequestPolicy.shouldCompleteInFlightRequest(
                status: .authorizedAlways))
    }
}
