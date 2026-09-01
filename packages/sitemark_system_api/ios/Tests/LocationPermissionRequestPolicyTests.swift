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

    func testAuthorizedWhenInUseCompletesInFlightRequest() {
        XCTAssertTrue(
            LocationPermissionRequestPolicy.shouldCompleteInFlightRequest(
                status: .authorizedWhenInUse))
    }

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
