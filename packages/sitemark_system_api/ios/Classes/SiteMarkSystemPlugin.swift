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
    /// Channel name used only to pin this plugin to the engine's lifetime.
    public static let lifecycleChannelName = "sitemark/system_plugin_lifecycle"

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
        // Pigeon retains `api` through its own message handlers, but nothing
        // retained `instance`: without this the plugin deallocated at the end
        // of `register`, its `MemoryPressurePlugin` went with it (the pressure
        // source's `[weak self]` handler then never fired) and
        // `detachFromEngine` was never called. Registering a method-call
        // delegate pins the instance to the engine's lifetime, which is the
        // documented Flutter plugin retention contract.
        registrar.addMethodCallDelegate(
            instance,
            channel: FlutterMethodChannel(
                name: lifecycleChannelName,
                binaryMessenger: registrar.messenger()))
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        // The channel exists only to retain this plugin; there is no API here.
        result(FlutterMethodNotImplemented)
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        SiteMarkSystemApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)
        memoryPlugin?.detach()
        memoryPlugin = nil
        api?.dispose()
        api = nil
    }
}
