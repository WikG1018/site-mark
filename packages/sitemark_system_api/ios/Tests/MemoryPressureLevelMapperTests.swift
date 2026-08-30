import XCTest

@testable import SiteMarkSystemApiCore

final class MemoryPressureLevelMapperTests: XCTestCase {
    func testWarningMapsToTheTrimLevel() {
        XCTAssertEqual(
            MemoryPressureLevelMapper.levelName(
                for: DispatchSourceMemoryPressureEvent(rawValue: DispatchSourceMemoryPressureEvent
                    .warning.rawValue)),
            "trim")
    }

    func testCriticalMapsToTheKillLevel() {
        XCTAssertEqual(
            MemoryPressureLevelMapper.levelName(
                for: DispatchSourceMemoryPressureEvent(rawValue: DispatchSourceMemoryPressureEvent
                    .critical.rawValue)),
            "kill")
    }

    func testCriticalWinsWhenBothFlagsAreSet() {
        let both = DispatchSourceMemoryPressureEvent(
            rawValue: DispatchSourceMemoryPressureEvent.warning.rawValue
                | DispatchSourceMemoryPressureEvent.critical.rawValue)
        XCTAssertEqual(MemoryPressureLevelMapper.levelName(for: both), "kill")
    }

    func testNormalMapsToNoLevel() {
        XCTAssertNil(
            MemoryPressureLevelMapper.levelName(
                for: DispatchSourceMemoryPressureEvent(rawValue: DispatchSourceMemoryPressureEvent
                    .normal.rawValue)))
    }
}
