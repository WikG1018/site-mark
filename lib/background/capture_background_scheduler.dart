import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/platform/local_notification_service.dart';
import 'package:sitemark/platform/notification_service.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/capture_processor.dart';
import 'package:workmanager/workmanager.dart';

/// Task name passed to [Workmanager.registerOneOffTask] and matched inside the
/// dispatcher so unrelated work is ignored.
const captureProcessingTask = 'sitemark.processCapture';

/// Unique WorkManager chain name. All capture work is appended to this single
/// serial chain so renders/publishes never run concurrently, preserving the
/// photo-number sequence and MediaStore overwrite semantics.
const captureProcessingQueue = 'sitemark-render-queue';

/// BGTaskScheduler identifier of the opportunistic iOS catch-up task.
///
/// iOS requires an exact three-way match between this constant, the
/// `BGTaskSchedulerPermittedIdentifiers` entry in `ios/Runner/Info.plist`, and
/// the `WorkmanagerPlugin.registerBGProcessingTask(withIdentifier:)` call in
/// `ios/Runner/AppDelegate.swift`. workmanager also delivers the fired task to
/// [captureCallbackDispatcher] under this name: workmanager_apple dispatches
/// by uniqueName, not by the taskName argument.
const iosCaptureProcessingBgTask =
    'io.github.wikg1018.sitemark.capture-processing';

/// Lowest-level bridge to the platform work scheduler.
///
/// Production code uses [WorkmanagerBackgroundWorkClient]; tests inject a
/// recording fake to assert enqueue/reconcile behavior without touching
/// WorkManager.
abstract interface class BackgroundWorkClient {
  /// Initializes the platform work scheduler with the top-level [dispatcher]
  /// that WorkManager invokes from a background isolate.
  Future<void> initialize(void Function() dispatcher);

  /// Appends a single capture-processing work item to the serial queue.
  Future<void> appendCapture({
    required String queueName,
    required String taskName,
    required String captureId,
    required String tag,
  });

  /// (Re-)arms the platform's opportunistic background catch-up task.
  ///
  /// Enqueued chain work already survives process death on Android, so this
  /// is a no-op there. On iOS the BGTaskScheduler request is consumed when
  /// the task fires, so every foreground session and every background run
  /// must submit the next request.
  Future<void> scheduleBackgroundReconcile();
}

/// Coordinates foreground enqueue/reconcile requests against a
/// [BackgroundWorkClient] and the persistent [AppDatabase].
///
/// The scheduler itself holds no WorkManager references; it translates
/// high-level operations into [BackgroundWorkClient.appendCapture] calls and
/// reads pending rows from the database for startup reconciliation.
abstract interface class CaptureBackgroundScheduler {
  Future<void> initialize();

  Future<void> enqueue(String captureId);

  Future<void> reconcilePending();

  Future<void> retry(String captureId);
}

/// Default [CaptureBackgroundScheduler] backed by a [BackgroundWorkClient].
final class PersistentCaptureBackgroundScheduler
    implements CaptureBackgroundScheduler {
  PersistentCaptureBackgroundScheduler({
    required this._client,
    required this._database,
  });

  final BackgroundWorkClient _client;
  final AppDatabase _database;
  Future<void>? _initialization;

  @override
  Future<void> initialize() {
    return _initialization ??= _initializeClient();
  }

  Future<void> _initializeClient() async {
    try {
      await _client.initialize(captureCallbackDispatcher);
    } catch (_) {
      // A transient platform-channel failure must remain retryable.
      _initialization = null;
      rethrow;
    }
  }

  @override
  Future<void> enqueue(String captureId) async {
    // Initialization is intentionally lazy so Android can draw Flutter's first
    // frame without waiting behind the WorkManager platform channel.
    await initialize();
    await _client.appendCapture(
      queueName: captureProcessingQueue,
      taskName: captureProcessingTask,
      captureId: captureId,
      tag: 'capture:$captureId',
    );
  }

  @override
  Future<void> retry(String captureId) async {
    // Reset attempts to 0 and restore the status to `captured` before
    // re-enqueueing. Without this, a `failed` record (status=failed,
    // attempts=3) is re-queued as-is: the processor would increment attempts
    // past `maxAttempts` (immediate re-fail) and `markRendering` would reject
    // the `failed -> rendering` transition (StateError). The reset makes the
    // manual retry behave like a fresh captured record, matching the spec.
    await _database.resetCaptureForRetry(captureId);
    await enqueue(captureId);
  }

  @override
  Future<void> reconcilePending() async {
    final pending = await _database.capturesAwaitingProcessing();
    for (final record in pending) {
      await enqueue(record.id);
    }
  }
}

/// [BackgroundWorkClient] backed by the pinned `workmanager` package.
///
/// Each capture is registered as a one-off task on the [captureProcessingQueue]
/// chain using [ExistingWorkPolicy.append], so WorkManager runs them serially.
/// The pinned Android plugin maps this Dart value to native
/// `APPEND_OR_REPLACE`, dropping failed/cancelled prerequisites before starting
/// the next chain rather than poisoning later captures.
/// The per-capture `tag` (`capture:<id>`) supports cancellation/inspection.
/// Input data carries the `captureId` so the dispatcher knows which record to
/// process.
class WorkmanagerBackgroundWorkClient implements BackgroundWorkClient {
  WorkmanagerBackgroundWorkClient({Workmanager? workmanager, bool? isIos})
    : _workmanager = workmanager ?? Workmanager(),
      _isIos = isIos ?? Platform.isIOS;

  final Workmanager _workmanager;
  final bool _isIos;
  bool _initialized = false;

  @override
  Future<void> initialize(void Function() dispatcher) async {
    if (_initialized) return;
    // isInDebugMode is deprecated and has no effect; omit it.
    await _workmanager.initialize(dispatcher);
    // iOS keeps no persistent WorkManager queue, so the opportunistic
    // BGProcessingTask must be submitted once per session from the
    // foreground isolate; the identifier itself is registered natively in
    // AppDelegate before launch finishes.
    await scheduleBackgroundReconcile();
    _initialized = true;
  }

  @override
  Future<void> appendCapture({
    required String queueName,
    required String taskName,
    required String captureId,
    required String tag,
  }) async {
    await _workmanager.registerOneOffTask(
      // The unique name is the shared queue (see [captureProcessingQueue]):
      // `ExistingWorkPolicy.append` chains every enqueue after the running
      // work for serial execution. Nothing is replaced per capture, so a
      // retry or startup reconcile can briefly leave two pending items for
      // the same capture; they converge through the processor's idempotent
      // state machine (ready early-exit / superseded cleanup) rather than
      // any WorkManager-level dedup.
      queueName,
      taskName,
      inputData: {'captureId': captureId},
      tag: tag,
      existingWorkPolicy: ExistingWorkPolicy.append,
      constraints: Constraints(networkType: NetworkType.notRequired),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(seconds: 30),
    );
  }

  @override
  Future<void> scheduleBackgroundReconcile() async {
    if (!_isIos) return;
    // The uniqueName doubles as the BGTaskScheduler identifier and must
    // exactly match Info.plist and the AppDelegate registration.
    await _workmanager.registerProcessingTask(
      iosCaptureProcessingBgTask,
      iosCaptureProcessingBgTask,
    );
  }
}

/// Constructs a [CaptureProcessor] for the headless background isolate.
///
/// Kept as a top-level function so the dispatcher can build a fresh processor
/// with a dedicated database handle on every invocation without retaining UI
/// state.
CaptureProcessor buildHeadlessCaptureProcessor(AppDatabase database) {
  return CaptureProcessor(
    database: database,
    platform: PigeonPlatformServices(),
    images: RustImagePipeline(),
    outputPaths: AppCaptureOutputPaths(),
  );
}

/// Sends the completion notification for a successfully processed capture
/// when [enabled] (the persisted `AppSetting.completionNotificationsEnabled`
/// switch) is true; a no-op otherwise.
///
/// [localeCode] is the persisted `AppSetting.localeCode` (`'zh'`, `'en'`, or
/// null for "follow system"); it decides the notification copy so the
/// notification follows the in-app language instead of the device locale.
///
/// Extracted as a top-level function so the background dispatcher and unit
/// tests share the exact same gate sequence. The service must be
/// initialized before posting — the tap callback is a no-op here because
/// deep-link handling is owned by the foreground isolate — and its
/// in-memory send gate must be opened explicitly.
Future<void> sendCaptureReadyNotificationIfEnabled({
  required bool enabled,
  required String? localeCode,
  required CompletionNotificationService service,
  required String projectId,
  required String captureId,
  required String photoNumber,
}) async {
  if (!enabled) return;
  await service.initialize((_) {});
  await service.setLocale(localeCode);
  await service.setEnabled(true);
  await service.showCaptureReady(
    projectId: projectId,
    captureId: captureId,
    photoNumber: photoNumber,
  );
}

/// Posts the completion notification for [captureId] after a successful
/// background render, gated on the persisted `completionNotificationsEnabled`
/// switch.
///
/// The background isolate cannot reach the Riverpod container, so a
/// dedicated [LocalNotificationService] instance is constructed here. The
/// whole path is wrapped in try/catch and degrades silently: plugin
/// registration inside the WorkManager background isolate relies on the
/// host app's GeneratedPluginRegistrant registering every plugin, which can
/// fail on some devices. A failure must never fail the work item — the
/// foreground UI already refreshes from the Drift watch streams, so the
/// notification is best-effort only.
Future<void> _notifyCaptureReady(AppDatabase database, String captureId) async {
  try {
    final settings = await database.getAppSettings();
    final record = await database.captureById(captureId);
    final photoNumber = record?.photoNumber;
    if (record == null || photoNumber == null || photoNumber.isEmpty) return;
    await sendCaptureReadyNotificationIfEnabled(
      enabled: settings.completionNotificationsEnabled,
      localeCode: settings.localeCode,
      service: LocalNotificationService(),
      projectId: record.projectId,
      captureId: captureId,
      photoNumber: photoNumber,
    );
  } catch (_) {
    // Silent degradation; see the doc comment above.
  }
}

/// Whether [taskName] names a capture-processing job this dispatcher runs.
///
/// Android delivers the taskName argument given at registration
/// ([captureProcessingTask]); workmanager_apple delivers the uniqueName, so
/// jobs on the serial chain arrive as [captureProcessingQueue].
@visibleForTesting
bool isCaptureTaskName(String taskName) =>
    taskName == captureProcessingTask || taskName == captureProcessingQueue;

/// Re-enqueues every capture awaiting processing and re-arms the iOS
/// background catch-up task.
///
/// Runs inside the dispatcher's BGProcessingTask branch as the opportunistic
/// equivalent of [PersistentCaptureBackgroundScheduler.reconcilePending]:
/// each pending capture is re-enqueued as a one-off job and processed by the
/// same idempotent processor. Kept top-level with injected collaborators so
/// the behavior is testable without the workmanager singleton.
@visibleForTesting
Future<void> reconcilePendingCapturesForBackground({
  required AppDatabase database,
  required BackgroundWorkClient client,
}) async {
  final pending = await database.capturesAwaitingProcessing();
  for (final record in pending) {
    await client.appendCapture(
      queueName: captureProcessingQueue,
      taskName: captureProcessingTask,
      captureId: record.id,
      tag: 'capture:${record.id}',
    );
  }
  await client.scheduleBackgroundReconcile();
}

/// WorkManager entry point invoked from a background isolate.
///
/// Returns `true` (success) for every non-retry outcome so later work in the
/// serial chain is not cancelled; only [CaptureProcessResult.retry] returns
/// `false` to trigger WorkManager's backoff/reschedule.
@pragma('vm:entry-point')
void captureCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    AppDatabase? database;
    try {
      WidgetsFlutterBinding.ensureInitialized();
      if (taskName == iosCaptureProcessingBgTask) {
        // Opportunistic iOS catch-up (see the design doc's background
        // scheduling downgrade): reconcile pending captures, then re-arm the
        // BGTaskScheduler request this run consumed. Android never dispatches
        // this name.
        database = AppDatabase();
        await reconcilePendingCapturesForBackground(
          database: database,
          client: WorkmanagerBackgroundWorkClient(),
        );
        return true;
      }
      // iOS dispatches by uniqueName, so a one-off capture job arrives as
      // [captureProcessingQueue] instead of [captureProcessingTask] (see
      // [isCaptureTaskName]).
      if (!isCaptureTaskName(taskName)) return true;
      final captureId = inputData?['captureId'] as String?;
      if (captureId == null || captureId.isEmpty) return true;
      database = AppDatabase();
      final result = await buildHeadlessCaptureProcessor(
        database,
      ).process(captureId);
      if (result == CaptureProcessResult.succeeded) {
        await _notifyCaptureReady(database, captureId);
      }
      return result != CaptureProcessResult.retry;
    } catch (_) {
      // Keep the task retryable even when database creation/opening, Rust
      // initialization or other processor-adjacent code throws unexpectedly.
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
