import Foundation

/// Maps DispatchSource memory-pressure events onto the levels the Dart
/// side already understands (`lib/platform/memory_pressure_service.dart`).
///
/// Android's three levels come from different sources: `system` is Flutter's
/// own framework callback (the engine delivers it natively on iOS too — no
/// native forwarding needed), while `trim` / `kill` arrive from ITGSA
/// broadcasts that have no iOS equivalent. DispatchSource's WARNING/CRITICAL
/// are the closest iOS signals and map onto `trim` / `kill` respectively.
public enum MemoryPressureLevelMapper {
    public static func levelName(for event: DispatchSourceMemoryPressureEvent) -> String? {
        if event.contains(.critical) {
            return "kill"
        }
        if event.contains(.warning) {
            return "trim"
        }
        return nil
    }
}
