import 'package:flutter/widgets.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/data/nas_sync_database.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/local_network_permission.dart';
import 'package:sitemark/workflow/nas_sync_service.dart';
import 'package:workmanager/workmanager.dart';

/// Periodic WorkManager task that drains the NAS upload queue while the
/// app is backgrounded or killed. Unique name doubles as the task name.
const nasBackgroundTask = 'sitemark.nasSync';

/// iOS BGTaskScheduler identifier. Must match
/// `BGTaskSchedulerPermittedIdentifiers` in Info.plist and the
/// `registerBGProcessingTask` call in AppDelegate when iOS catch-up is wired.
const iosNasSyncBgTask = 'io.github.wikg1018.sitemark.nas-sync';

/// Lowest WorkManager period; the OS will not fire more often than this.
const Duration nasBackgroundPeriod = Duration(minutes: 15);

/// Arms (or keeps) the periodic NAS drain. Called when sync is enabled and
/// after a foreground drain leaves pending work behind.
Future<void> scheduleNasBackgroundDrain({
  Workmanager? workmanager,
  bool enabled = true,
}) async {
  final wm = workmanager ?? Workmanager();
  if (!enabled) {
    await wm.cancelByUniqueName(nasBackgroundTask);
    return;
  }
  await wm.registerPeriodicTask(
    nasBackgroundTask,
    nasBackgroundTask,
    frequency: nasBackgroundPeriod,
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.connected),
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(minutes: 5),
  );
}

/// Cancels the periodic drain (sync disabled).
Future<void> cancelNasBackgroundDrain({Workmanager? workmanager}) =>
    scheduleNasBackgroundDrain(workmanager: workmanager, enabled: false);

/// Builds a one-shot coordinator for the headless isolate. No observers —
/// the dispatcher only needs [NasSyncCoordinator.drainOnce].
NasSyncCoordinator buildHeadlessNasCoordinator(AppDatabase database) {
  return NasSyncCoordinator(
    database,
    SecureStorageNasCredentials(),
    ConnectivityNasConnectivity(),
    RustNasUploader(),
    AppCaptureOutputPaths(),
    checkLocalNetwork: LocalNetworkAccess(
      PigeonLocalNetworkPermission(),
    ).isHostAllowed,
  );
}

/// WorkManager entry point for the periodic NAS drain.
@pragma('vm:entry-point')
void nasCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != nasBackgroundTask && taskName != iosNasSyncBgTask) {
      return true;
    }
    AppDatabase? database;
    try {
      WidgetsFlutterBinding.ensureInitialized();
      database = AppDatabase();
      final config = await database.nasSyncConfig();
      if (!config.enabled) {
        await cancelNasBackgroundDrain();
        return true;
      }
      await buildHeadlessNasCoordinator(database).drainOnce();
      return true;
    } catch (_) {
      // Keep the task retryable: WorkManager backoff reschedules a false.
      return false;
    } finally {
      try {
        await database?.close();
      } catch (_) {
        // Closing a broken handle must not escape and cancel later work.
      }
    }
  });
}
