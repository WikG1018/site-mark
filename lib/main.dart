import 'package:flutter/material.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/bootstrap.dart';
import 'package:sitemark/platform/local_notification_service.dart';
import 'package:sitemark/platform/memory_pressure_service.dart';
import 'package:sitemark/platform/platform_services.dart';

export 'package:sitemark/app.dart' show MyApp;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep a photo-app-sized working set in the foreground: list thumbnails,
  // Hero flights, detail previews, and fullscreen paging all compete for the
  // same cache. 40 / 32 MB caused constant re-decode thrash on Android scroll
  // and transition frames. A 2048-wide RGBA decode is ~16 MB, so 96 MB holds
  // roughly six full-size frames plus thumbnails. Memory pressure still
  // clears the cache when the OS asks, so backgrounded PSS stays bounded.
  PaintingBinding.instance.imageCache.maximumSize = 120;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 96 * 1024 * 1024;
  // The production completion-notification service; SiteMarkApp initializes
  // it (deep-link taps) and keeps its send gate in sync with the persisted
  // settings switch.
  final notificationService = LocalNotificationService();
  // The production memory-pressure service; bridges ITGSA MEMORY_TRIM /
  // MEMORY_KILL broadcasts (and Flutter's own didHaveMemoryPressure) to the
  // MemoryPressureCoordinator wired in SiteMarkApp.
  final memoryPressureService = PlatformMemoryPressureService();
  await bootstrapForeground(
    startUi: () => runApp(
      MyApp(
        completionNotificationService: notificationService,
        memoryPressureService: memoryPressureService,
      ),
    ),
    waitForFirstFrame: () => WidgetsBinding.instance.endOfFrame,
    initializeRuntime: initializeForegroundRust,
  );
}
