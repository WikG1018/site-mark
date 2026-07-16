import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/src/rust/frb_generated.dart';
import 'package:sitemark/workflow/capture_processor.dart';
import 'package:workmanager/workmanager.dart';

/// Task name passed to [Workmanager.registerOneOffTask] and matched inside the
/// dispatcher so unrelated work is ignored.
const captureProcessingTask = 'sitemark.processCapture';

/// Unique WorkManager chain name. All capture work is appended to this single
/// serial chain so renders/publishes never run concurrently, preserving the
/// photo-number sequence and MediaStore overwrite semantics.
const captureProcessingQueue = 'sitemark-render-queue';

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

  @override
  Future<void> initialize() async {
    await _client.initialize(captureCallbackDispatcher);
  }

  @override
  Future<void> enqueue(String captureId) async {
    await _client.appendCapture(
      queueName: captureProcessingQueue,
      taskName: captureProcessingTask,
      captureId: captureId,
      tag: 'capture:$captureId',
    );
  }

  @override
  Future<void> retry(String captureId) => enqueue(captureId);

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
/// The per-capture `tag` (`capture:<id>`) supports cancellation/inspection.
/// Input data carries the `captureId` so the dispatcher knows which record to
/// process.
class WorkmanagerBackgroundWorkClient implements BackgroundWorkClient {
  WorkmanagerBackgroundWorkClient({Workmanager? workmanager})
    : _workmanager = workmanager ?? Workmanager();

  final Workmanager _workmanager;
  bool _initialized = false;

  @override
  Future<void> initialize(void Function() dispatcher) async {
    if (_initialized) return;
    // ignore: deprecated_member_use
    await _workmanager.initialize(dispatcher, isInDebugMode: kDebugMode);
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
      // Use a per-capture unique name so a retry replaces any prior pending
      // instance of the same capture, while `existingWorkPolicy: append`
      // chains it onto the shared queue for serial execution.
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

/// Rust initialization future shared across headless invocations so FRB is
/// initialized exactly once per background isolate.
Future<void>? _backgroundRustInitialization;

/// WorkManager entry point invoked from a background isolate.
///
/// Returns `true` (success) for every non-retry outcome so later work in the
/// serial chain is not cancelled; only [CaptureProcessResult.retry] returns
/// `false` to trigger WorkManager's backoff/reschedule.
@pragma('vm:entry-point')
void captureCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    if (taskName != captureProcessingTask) return true;
    final captureId = inputData?['captureId'] as String?;
    if (captureId == null || captureId.isEmpty) return true;
    await (_backgroundRustInitialization ??= RustLib.init());
    final database = AppDatabase();
    try {
      final result = await buildHeadlessCaptureProcessor(
        database,
      ).process(captureId);
      return result != CaptureProcessResult.retry;
    } finally {
      await database.close();
    }
  });
}
