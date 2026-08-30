import XCTest

@testable import SiteMarkSystemApiCore

private final class FakeCaptureStateStore: CaptureStateStore {
    var removedKeys: [String] = []
    var commitResult = true

    func removeValues(forKey keys: [String]) -> Bool {
        removedKeys.append(contentsOf: keys)
        return commitResult
    }
}

final class CaptureSessionPolicyTests: XCTestCase {
    func testClearPendingRemovesBothKeysSynchronously() {
        let store = FakeCaptureStateStore()

        XCTAssertTrue(CaptureSessionPolicy.clearPending(store))

        XCTAssertEqual(
            store.removedKeys,
            [CaptureSessionPolicy.keyCaptureId, CaptureSessionPolicy.keyCapturePath])
    }

    func testClearPendingReportsDurableFailure() {
        let store = FakeCaptureStateStore()
        store.commitResult = false

        XCTAssertFalse(CaptureSessionPolicy.clearPending(store))
    }
}
