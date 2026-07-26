import 'package:flutter/foundation.dart';

/// Starts the Flutter UI before awaiting non-visual native runtime setup.
///
/// Android keeps its system splash visible until Flutter draws the first
/// frame. Starting the widget tree first lets that frame render immediately,
/// while callers can still await initialization and surface failures.
Future<void> bootstrapForeground({
  required VoidCallback startUi,
  required Future<void> Function() waitForFirstFrame,
  required Future<void> Function() initializeRuntime,
}) async {
  startUi();
  await waitForFirstFrame();
  await initializeRuntime();
}
