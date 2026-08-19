import 'package:flutter/material.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/bootstrap.dart';
import 'package:sitemark/platform/external_link_service.dart';
import 'package:sitemark/platform/local_notification_service.dart';
import 'package:sitemark/platform/memory_pressure_service.dart';
import 'package:sitemark/platform/ohos_capability.dart';
import 'package:sitemark/platform/ohos_platform_services.dart';
import 'package:sitemark/platform/platform_services.dart';

export 'package:sitemark/app.dart' show MyApp;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Tighten Flutter's image cache for the ITGSA "fair running memory"
  // mechanism. The defaults (1000 entries / 100 MB) are tuned for image-heavy
  // social apps; SiteMark is an offline engineering tool whose working set
  // is a handful of thumbnails plus at most one detail image, so 32 MB / 40
  // entries is plenty and keeps the PSS footprint low when backgrounded.
  PaintingBinding.instance.imageCache.maximumSize = 40;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 32 * 1024 * 1024;
  // The production completion-notification service; SiteMarkApp initializes
  // it (deep-link taps) and keeps its send gate in sync with the persisted
  // settings switch.
  final notificationService = isOhosBuild
      ? OhosCompletionNotificationService()
      : LocalNotificationService();
  // The production memory-pressure service; bridges ITGSA MEMORY_TRIM /
  // MEMORY_KILL broadcasts (and Flutter's own didHaveMemoryPressure) to the
  // MemoryPressureCoordinator wired in SiteMarkApp.
  final memoryPressureService = PlatformMemoryPressureService();
  await bootstrapForeground(
    startUi: () => runApp(
      MyApp(
        completionNotificationService: notificationService,
        memoryPressureService: memoryPressureService,
        shareService: isOhosBuild ? OhosShareFileService() : null,
        externalLinkService: isOhosBuild
            ? const NoopExternalLinkService()
            : null,
      ),
    ),
    waitForFirstFrame: () => WidgetsBinding.instance.endOfFrame,
    initializeRuntime: initializeForegroundRust,
  );
}
