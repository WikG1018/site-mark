import Flutter
import UIKit

/// Flutter plugin binding the Pigeon `SiteMarkSystemApi` to a FlutterEngine.
///
/// iOS port of SiteMarkSystemPlugin: on attach to an engine the
/// `IOSSystemApi` is created headless-safe and registered as the Pigeon
/// host; the memory-pressure channel is wired in the same step (Android
/// attaches it from MainActivity). There is no Activity/ActivityResult
/// plumbing on iOS — view-controller presentation and permission callbacks
/// resolve at call time.
public class SiteMarkSystemPlugin: NSObject, FlutterPlugin {
    private var api: IOSSystemApi?
    private var memoryPlugin: MemoryPressurePlugin?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = SiteMarkSystemPlugin()
        let api = IOSSystemApi()
        instance.api = api
        SiteMarkSystemApiSetup.setUp(binaryMessenger: registrar.messenger(), api: api)
        let memory = MemoryPressurePlugin()
        memory.attach(messenger: registrar.messenger())
        instance.memoryPlugin = memory
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        SiteMarkSystemApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)
        memoryPlugin?.detach()
        memoryPlugin = nil
        api?.dispose()
        api = nil
    }
}
