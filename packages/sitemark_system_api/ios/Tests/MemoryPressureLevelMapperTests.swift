import XCTest

@testable import SiteMarkSystemApiCore

final class MemoryPressureLevelMapperTests: XCTestCase {
    func testWarningMapsToTheTrimLevel() {
        XCTAssertEqual(
            MemoryPressureLevelMapper.levelName(
                for: DispatchSource.MemoryPressureEvent(rawValue: DispatchSource.MemoryPressureEvent
                    .warning.rawValue)),
            "trim")
    }

    func testCriticalMapsToTheKillLevel() {
        XCTAssertEqual(
            MemoryPressureLevelMapper.levelName(
                for: DispatchSource.MemoryPressureEvent(rawValue: DispatchSource.MemoryPressureEvent
                    .critical.rawValue)),
            "kill")
    }

    func testCriticalWinsWhenBothFlagsAreSet() {
        let both = DispatchSource.MemoryPressureEvent(
            rawValue: DispatchSource.MemoryPressureEvent.warning.rawValue
                | DispatchSource.MemoryPressureEvent.critical.rawValue)
        XCTAssertEqual(MemoryPressureLevelMapper.levelName(for: both), "kill")
    }

    func testNormalMapsToNoLevel() {
        XCTAssertNil(
            MemoryPressureLevelMapper.levelName(
                for: DispatchSource.MemoryPressureEvent(rawValue: DispatchSource.MemoryPressureEvent
                    .normal.rawValue)))
    }
}
