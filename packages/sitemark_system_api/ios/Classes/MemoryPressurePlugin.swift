import Flutter
import Foundation

/// Owns the `sitemark/memory_pressure` MethodChannel on iOS.
///
/// Android's plugin carries an OEM Binder callback and a goAsync()
/// PendingResult per event, with supersede/timeout ACK semantics. iOS has
/// no such system contract: DispatchSource memory-pressure events carry no
/// ack obligation, so the plugin keeps only what the Dart side needs —
/// monotonic event IDs on `onMemoryPressure`, and `acknowledge` as a
/// no-op success (the Dart service calls it unconditionally). The
/// Android behaviors that exist purely to service the Binder lifecycle are
/// deliberately not simulated (design doc, memory-pressure section).
public class MemoryPressurePlugin {
    static let channelName = "sitemark/memory_pressure"

    private var channel: FlutterMethodChannel?
    // The iOS-only C typealias: `DispatchSource.MemoryPressureSourceObject`
    // does not exist in the iOS Swift overlay.
    private var source: DispatchSourceMemoryPressureSourceObject?
    private var nextEventId: Int64 = 0

    func attach(messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "acknowledge":
                // No Binder callback is pending on iOS; the ack is a no-op
                // so the Dart code stays platform-agnostic.
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        self.channel = channel
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source, !source.isCancelled else { return }
            guard let level = MemoryPressureLevelMapper.levelName(for: source.data) else {
                return
            }
            self.forward(level: level)
        }
        source.resume()
        self.source = source
    }

    func detach() {
        source?.cancel()
        source = nil
        channel?.setMethodCallHandler(nil)
        channel = nil
    }

    private func forward(level: String) {
        nextEventId += 1
        channel?.invokeMethod(
            "onMemoryPressure",
            arguments: ["level": level, "eventId": nextEventId])
    }
}
