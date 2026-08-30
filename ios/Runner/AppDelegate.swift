import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // BGTaskScheduler handlers must be registered before launch finishes. The
    // identifier must exactly match the Dart `iosCaptureProcessingBgTask`
    // constant and the `BGTaskSchedulerPermittedIdentifiers` entry in
    // Info.plist (workmanager_apple 0.9.x does not register it on its own).
    WorkmanagerPlugin.registerBGProcessingTask(
      withIdentifier: "io.github.wikg1018.sitemark.capture-processing"
    )
    // Background tasks run in a separate headless Flutter engine that does
    // not register plugins on its own; without this, the capture dispatcher
    // cannot reach drift/path_provider/the Rust bridge.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
