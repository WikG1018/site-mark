import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/background/capture_background_scheduler.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';

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
  }

  test(
    'enqueue appends to the serial render queue with capture tag and input',
    () async {
      await scheduler.enqueue('capture-1');

      expect(client.appendCalls, hasLength(1));
      final call = client.appendCalls.single;
      expect(call.queueName, captureProcessingQueue);
      expect(call.taskName, captureProcessingTask);
      expect(call.captureId, 'capture-1');
      expect(call.tag, 'capture:capture-1');
    },
  );

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
  void Function()? dispatcher;

  @override
  Future<void> initialize(void Function() dispatcher) async {
    initialized = true;
    this.dispatcher = dispatcher;
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
