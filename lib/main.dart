import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/background/capture_background_scheduler.dart';
import 'package:sitemark/platform/local_notification_service.dart';
import 'package:sitemark/src/rust/frb_generated.dart';
import 'package:workmanager/workmanager.dart';

export 'package:sitemark/app.dart' show MyApp;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  // Initialize WorkManager with the headless dispatcher before the UI runs so
  // background capture processing is available immediately. `isInDebugMode`
  // enables verbose WorkManager logging in debug builds.
  await Workmanager().initialize(
    captureCallbackDispatcher,
    // ignore: deprecated_member_use
    isInDebugMode: kDebugMode,
  );
  // The production completion-notification service; SiteMarkApp initializes
  // it (deep-link taps) and keeps its send gate in sync with the persisted
  // settings switch.
  final notificationService = LocalNotificationService();
  runApp(MyApp(completionNotificationService: notificationService));
}
