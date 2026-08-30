import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/background/capture_background_scheduler.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/platform/notification_service.dart';
import 'package:workmanager/workmanager.dart';

void main() {
  late AppDatabase database;
  late _RecordingBackgroundWorkClient client;
  late CaptureBackgroundScheduler scheduler;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.createProject(
      id: 'project-1',
      name: '东区厂房改造',
      createdAt: DateTime(2026, 7, 16, 8),
    );
    client = _RecordingBackgroundWorkClient();
    scheduler = PersistentCaptureBackgroundScheduler(
      client: client,
      database: database,
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedCaptured(String id) async {
    await database.createPendingCapture(
      id: id,
      projectId: 'project-1',
      originalPath: '/private/$id.jpg',
      workLocation: 'A 区',
      workContent: '检查',
      photographer: '张工',
      watermarkLocaleCode: 'zh',
      createdAt: DateTime(2026, 7, 16, 9, 30),
    );
    await database.markCaptured(
      captureId: id,
      capturedAt: DateTime(2026, 7, 16, 9, 32, 18),
    );
    // Resolve the location so the row is eligible for processing. The
    // coordinator marks pending-location rows as resolved/unavailable before
    // enqueuing; `capturesAwaitingProcessing` excludes rows still pending.
    await database.resolveCaptureLocation(
      captureId: id,
      resolution: 'unavailable',
      outcome: 'unavailable',
    );
  }

  test(
    'enqueue appends to the serial render queue with capture tag and input',
    () async {
      await scheduler.enqueue('capture-1');

      expect(client.initialized, isTrue);
      expect(client.appendCalls, hasLength(1));
      final call = client.appendCalls.single;
      expect(call.queueName, captureProcessingQueue);
      expect(call.taskName, captureProcessingTask);
      expect(call.captureId, 'capture-1');
      expect(call.tag, 'capture:capture-1');
    },
  );

  test('concurrent enqueue calls share one initialization future', () async {
    client.initializeGate = Completer<void>();

    final first = scheduler.enqueue('capture-1');
    final second = scheduler.enqueue('capture-2');
    await Future<void>.delayed(Duration.zero);

    expect(client.initializeCalls, 1);
    expect(client.appendCalls, isEmpty);

    client.initializeGate!.complete();
    await Future.wait([first, second]);
    expect(client.appendCalls, hasLength(2));
  });

  test('initialization can retry after a transient failure', () async {
    client.initializeFailures = 1;

    await expectLater(scheduler.enqueue('capture-1'), throwsStateError);
    expect(client.appendCalls, isEmpty);

    await scheduler.enqueue('capture-1');
    expect(client.initializeCalls, 2);
    expect(client.appendCalls, hasLength(1));
  });

  test('retry re-enqueues with the same queue and tag', () async {
    // retry now resets the record before enqueueing, so seed a `failed`
    // capture (the only state from which a manual retry is meaningful) first.
    await seedCaptured('capture-1');
    await database.markRendering(
      captureId: 'capture-1',
      originalSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    await database.markFailed(captureId: 'capture-1', reason: 'boom');
    await scheduler.retry('capture-1');

    expect(client.appendCalls, hasLength(1));
    expect(client.appendCalls.single.captureId, 'capture-1');
    expect(client.appendCalls.single.tag, 'capture:capture-1');
    expect(client.appendCalls.single.queueName, captureProcessingQueue);
  });

  test(
    'retry resets a failed record to captured with attempts cleared before enqueue',
    () async {
      // Seed a capture, drive it to `failed` with attempts exhausted, then
      // exercise the manual retry path. Before the fix, `retry` enqueued the
      // failed record as-is and the processor would either throw (failed ->
      // rendering is illegal) or immediately re-fail (attempts >= maxAttempts).
      await seedCaptured('capture-1');
      await database.markRendering(
        captureId: 'capture-1',
        originalSha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
      await database.markFailed(captureId: 'capture-1', reason: 'boom');
      await database.incrementProcessingAttempts('capture-1');
      await database.incrementProcessingAttempts('capture-1');
      await database.incrementProcessingAttempts('capture-1');
      final beforeRetry = (await database.captureById('capture-1'))!;
      expect(beforeRetry.status, CaptureStatus.failed);
      expect(beforeRetry.processingAttempts, 3);
      expect(beforeRetry.failureReason, 'boom');

      await scheduler.retry('capture-1');

      // The reset ran before enqueue, so the record is back to `captured`
      // with its immutable evidence retained for tamper verification.
      final afterRetry = (await database.captureById('capture-1'))!;
      expect(afterRetry.status, CaptureStatus.captured);
      expect(afterRetry.processingAttempts, 0);
      expect(afterRetry.failureReason, isNull);
      expect(
        afterRetry.originalSha256,
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
      expect(afterRetry.publishedUri, isNull);
      // And the capture was appended to the serial queue exactly once.
      expect(client.appendCalls, hasLength(1));
      expect(client.appendCalls.single.captureId, 'capture-1');
    },
  );

  test(
    'reconcilePending enqueues every captured and rendering row once',
    () async {
      await seedCaptured('capture-1');
      await seedCaptured('capture-2');
      await database.markRendering(
        captureId: 'capture-2',
        originalSha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );

      await scheduler.reconcilePending();

      expect(client.appendCalls, hasLength(2));
      final ids = client.appendCalls.map((call) => call.captureId).toList();
      expect(ids, containsAll(['capture-1', 'capture-2']));
      // Each captured/rendering row is reconciled exactly once.
      final uniqueIds = ids.toSet();
      expect(uniqueIds.length, ids.length);
      // All calls share the single serial chain name.
      expect(client.appendCalls.map((call) => call.queueName).toSet(), {
        captureProcessingQueue,
      });
      // Every call carries the capture:<id> tag.
      for (final call in client.appendCalls) {
        expect(call.tag, 'capture:${call.captureId}');
      }
    },
  );

  test('reconcilePending skips ready and failed rows', () async {
    await seedCaptured('capture-1');
    await seedCaptured('capture-2');
    await database.markRendering(
      captureId: 'capture-1',
      originalSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    await database.markReady(
      captureId: 'capture-1',
      publishedUri: 'content://media/site-mark/1',
    );
    await database.markFailed(captureId: 'capture-2', reason: 'boom');

    await scheduler.reconcilePending();

    expect(client.appendCalls, isEmpty);
  });

  test('initialize forwards the dispatcher to the work client', () async {
    await scheduler.initialize();

    expect(client.initialized, isTrue);
    expect(client.dispatcher, captureCallbackDispatcher);
  });

  test('capturesAwaitingProcessing orders oldest first', () async {
    await seedCaptured('capture-2');
    await seedCaptured('capture-1');

    final pending = await database.capturesAwaitingProcessing();

    expect(pending.map((row) => row.id).toList(), ['capture-2', 'capture-1']);
  });

  test('capturesAwaitingProcessing excludes pending-location rows', () async {
    // seedCaptured resolves the location, so capture-1 is eligible. A freshly
    // captured record whose location is still pending must be excluded so the
    // processor doesn't consume the render budget before the coordinator
    // finalizes the location source.
    await seedCaptured('capture-1');
    await database.createPendingCapture(
      id: 'capture-pending',
      projectId: 'project-1',
      originalPath: '/private/capture-pending.jpg',
      workLocation: 'B 区',
      workContent: '复查',
      photographer: '李工',
      watermarkLocaleCode: 'zh',
      createdAt: DateTime(2026, 7, 16, 10),
    );
    await database.markCaptured(
      captureId: 'capture-pending',
      capturedAt: DateTime(2026, 7, 16, 10, 5),
    );

    final pending = await database.capturesAwaitingProcessing();

    expect(pending.map((row) => row.id).toList(), ['capture-1']);
  });

  group('completion notification gate', () {
    test('does not touch the service when the switch is off', () async {
      final service = _RecordingCompletionNotificationService();

      await sendCaptureReadyNotificationIfEnabled(
        enabled: false,
        localeCode: 'en',
        service: service,
        projectId: 'project-1',
        captureId: 'capture-1',
        photoNumber: 'IMG-0001',
      );

      expect(service.initializeCalls, 0);
      expect(service.enabledValues, isEmpty);
      expect(service.localeValues, isEmpty);
      expect(service.showCalls, 0);
    });

    test(
      'initializes, opens the gate, and posts when the switch is on',
      () async {
        final service = _RecordingCompletionNotificationService();

        await sendCaptureReadyNotificationIfEnabled(
          enabled: true,
          localeCode: 'en',
          service: service,
          projectId: 'project-1',
          captureId: 'capture-1',
          photoNumber: 'IMG-0001',
        );

        expect(service.initializeCalls, 1);
        expect(service.enabledValues, [true]);
        expect(service.localeValues, ['en']);
        expect(service.showCalls, 1);
        expect(service.lastProjectId, 'project-1');
        expect(service.lastCaptureId, 'capture-1');
        expect(service.lastPhotoNumber, 'IMG-0001');
      },
    );
  });
  group('iOS background catch-up wiring', () {
    test(
      'isCaptureTaskName accepts both the Android task name and the iOS uniqueName',
      () {
        // workmanager_apple dispatches by uniqueName, so on iOS a one-off
        // capture job arrives as the serial-queue name instead of
        // [captureProcessingTask]. The BGProcessingTask itself is handled by
        // a dedicated branch and must not count as a capture job.
        expect(isCaptureTaskName(captureProcessingTask), isTrue);
        expect(isCaptureTaskName(captureProcessingQueue), isTrue);
        expect(isCaptureTaskName(iosCaptureProcessingBgTask), isFalse);
        expect(isCaptureTaskName('unrelated.task'), isFalse);
        expect(isCaptureTaskName(''), isFalse);
      },
    );

    test(
      'background reconcile re-enqueues pending captures and re-arms the task',
      () async {
        await seedCaptured('capture-1');
        await seedCaptured('capture-2');
        await database.markRendering(
          captureId: 'capture-2',
          originalSha256:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        );

        final backgroundClient = _RecordingBackgroundWorkClient();
        await reconcilePendingCapturesForBackground(
          database: database,
          client: backgroundClient,
        );

        expect(backgroundClient.appendCalls, hasLength(2));
        for (final call in backgroundClient.appendCalls) {
          expect(call.queueName, captureProcessingQueue);
          expect(call.taskName, captureProcessingTask);
          expect(call.tag, 'capture:${call.captureId}');
        }
        // BGTaskScheduler requests are one-shot: the run must submit the
        // next request before returning.
        expect(backgroundClient.reconcileScheduled, 1);
      },
    );

    test('background reconcile re-arms even when nothing is pending', () async {
      final backgroundClient = _RecordingBackgroundWorkClient();
      await reconcilePendingCapturesForBackground(
        database: database,
        client: backgroundClient,
      );

      expect(backgroundClient.appendCalls, isEmpty);
      expect(backgroundClient.reconcileScheduled, 1);
    });
  });

  group('WorkmanagerBackgroundWorkClient', () {
    test(
      'initialize registers the iOS processing task under the plist identifier',
      () async {
        final workmanager = _RecordingWorkmanager();
        final iosClient = WorkmanagerBackgroundWorkClient(
          workmanager: workmanager,
          isIos: true,
        );

        await iosClient.initialize(() {});

        expect(workmanager.initializeCalls, 1);
        expect(workmanager.processingTaskRegistrations, hasLength(1));
        expect(workmanager.processingTaskRegistrations.single, (
          iosCaptureProcessingBgTask,
          iosCaptureProcessingBgTask,
        ));
      },
    );

    test('initialize skips BGTaskScheduler registration off iOS', () async {
      final workmanager = _RecordingWorkmanager();
      final androidClient = WorkmanagerBackgroundWorkClient(
        workmanager: workmanager,
        isIos: false,
      );

      await androidClient.initialize(() {});

      expect(workmanager.initializeCalls, 1);
      expect(workmanager.processingTaskRegistrations, isEmpty);
    });

    test('scheduleBackgroundReconcile only submits on iOS', () async {
      final workmanager = _RecordingWorkmanager();
      final androidClient = WorkmanagerBackgroundWorkClient(
        workmanager: workmanager,
        isIos: false,
      );
      final iosClient = WorkmanagerBackgroundWorkClient(
        workmanager: workmanager,
        isIos: true,
      );

      await androidClient.scheduleBackgroundReconcile();
      expect(workmanager.processingTaskRegistrations, isEmpty);

      await iosClient.scheduleBackgroundReconcile();
      expect(workmanager.processingTaskRegistrations, hasLength(1));
    });

    test(
      'appendCapture registers a one-off task on the serial queue',
      () async {
        final workmanager = _RecordingWorkmanager();
        final client = WorkmanagerBackgroundWorkClient(
          workmanager: workmanager,
          isIos: false,
        );

        await client.appendCapture(
          queueName: captureProcessingQueue,
          taskName: captureProcessingTask,
          captureId: 'capture-1',
          tag: 'capture:capture-1',
        );

        final registration = workmanager.oneOffRegistrations.single;
        expect(registration.uniqueName, captureProcessingQueue);
        expect(registration.taskName, captureProcessingTask);
        expect(registration.inputData, {'captureId': 'capture-1'});
        expect(registration.tag, 'capture:capture-1');
        // Serial chaining relies on the append policy staying in place.
        expect(registration.existingWorkPolicy, ExistingWorkPolicy.append);
      },
    );
  });
}

class _AppendCall {
  _AppendCall({
    required this.queueName,
    required this.taskName,
    required this.captureId,
    required this.tag,
  });

  final String queueName;
  final String taskName;
  final String captureId;
  final String tag;
}

class _RecordingBackgroundWorkClient implements BackgroundWorkClient {
  final List<_AppendCall> appendCalls = [];
  bool initialized = false;
  int initializeCalls = 0;
  int initializeFailures = 0;
  int reconcileScheduled = 0;
  Completer<void>? initializeGate;
  void Function()? dispatcher;

  @override
  Future<void> initialize(void Function() dispatcher) async {
    initializeCalls++;
    initialized = true;
    this.dispatcher = dispatcher;
    await initializeGate?.future;
    if (initializeFailures > 0) {
      initializeFailures--;
      throw StateError('transient initialization failure');
    }
  }

  @override
  Future<void> scheduleBackgroundReconcile() async {
    reconcileScheduled++;
  }

  @override
  Future<void> appendCapture({
    required String queueName,
    required String taskName,
    required String captureId,
    required String tag,
  }) async {
    appendCalls.add(
      _AppendCall(
        queueName: queueName,
        taskName: taskName,
        captureId: captureId,
        tag: tag,
      ),
    );
  }
}

/// Records the gate sequence driven by
/// [sendCaptureReadyNotificationIfEnabled] so the background notification
/// path can be asserted without the real plugin.
class _RecordingCompletionNotificationService
    implements CompletionNotificationService {
  int initializeCalls = 0;
  final List<bool> enabledValues = [];
  final List<String?> localeValues = [];
  int showCalls = 0;
  String? lastProjectId;
  String? lastCaptureId;
  String? lastPhotoNumber;

  @override
  Future<void> initialize(
    void Function(String deepLinkPath) onTapDeepLink,
  ) async {
    initializeCalls++;
  }

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> showCaptureReady({
    required String projectId,
    required String captureId,
    required String photoNumber,
  }) async {
    showCalls++;
    lastProjectId = projectId;
    lastCaptureId = captureId;
    lastPhotoNumber = photoNumber;
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    enabledValues.add(enabled);
  }

  @override
  Future<void> setLocale(String? localeCode) async {
    localeValues.add(localeCode);
  }
}

class _OneOffRegistration {
  _OneOffRegistration({
    required this.uniqueName,
    required this.taskName,
    required this.inputData,
    required this.tag,
    required this.existingWorkPolicy,
  });

  final String uniqueName;
  final String taskName;
  final Map<String, dynamic>? inputData;
  final String? tag;
  final ExistingWorkPolicy? existingWorkPolicy;
}

/// Records the workmanager calls [WorkmanagerBackgroundWorkClient] makes so
/// the iOS BGTaskScheduler wiring can be asserted without the plugin.
class _RecordingWorkmanager implements Workmanager {
  int initializeCalls = 0;
  final List<(String uniqueName, String taskName)> processingTaskRegistrations =
      [];
  final List<_OneOffRegistration> oneOffRegistrations = [];

  @override
  Future<void> initialize(
    Function callbackDispatcher, {
    bool isInDebugMode = false,
  }) async {
    initializeCalls++;
  }

  @override
  void executeTask(BackgroundTaskHandler backgroundTaskHandler) {}

  @override
  Future<void> registerOneOffTask(
    String uniqueName,
    String taskName, {
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
    OutOfQuotaPolicy? outOfQuotaPolicy,
  }) async {
    oneOffRegistrations.add(
      _OneOffRegistration(
        uniqueName: uniqueName,
        taskName: taskName,
        inputData: inputData,
        tag: tag,
        existingWorkPolicy: existingWorkPolicy,
      ),
    );
  }

  @override
  Future<void> registerPeriodicTask(
    String uniqueName,
    String taskName, {
    Duration? frequency,
    Duration? flexInterval,
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingPeriodicWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<bool> isScheduledByUniqueName(String uniqueName) async {
    throw UnimplementedError();
  }

  @override
  Future<void> registerProcessingTask(
    String uniqueName,
    String taskName, {
    Duration? initialDelay,
    Map<String, dynamic>? inputData,
    Constraints? constraints,
  }) async {
    processingTaskRegistrations.add((uniqueName, taskName));
  }

  @override
  Future<void> cancelByUniqueName(String uniqueName) async {}

  @override
  Future<void> cancelByTag(String tag) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<String> printScheduledTasks() async => '';
}
