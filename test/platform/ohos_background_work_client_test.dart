import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/background/capture_background_scheduler.dart';
import 'package:sitemark/platform/ohos_background_work_client.dart';
import 'package:sitemark/workflow/capture_processor.dart';

void main() {
  test('appendCapture runs one capture at a time in enqueue order', () async {
    final started = <String>[];
    final client = InAppSerialBackgroundWorkClient(
      runner: (captureId) async {
        started.add(captureId);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return CaptureProcessResult.succeeded;
      },
    );
    await client.initialize(() {});
    unawaited(client.appendCapture(
      queueName: captureProcessingQueue,
      taskName: captureProcessingTask,
      captureId: 'c1',
      tag: 'capture:c1',
    ));
    unawaited(client.appendCapture(
      queueName: captureProcessingQueue,
      taskName: captureProcessingTask,
      captureId: 'c2',
      tag: 'capture:c2',
    ));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(started, ['c1']);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(started, ['c1', 'c2']);
  });

  test('same captureId replaces a not-yet-running item', () async {
    final started = <String>[];
    final gate = Completer<void>();
    var c1Runs = 0;
    final client = InAppSerialBackgroundWorkClient(
      runner: (captureId) async {
        if (captureId == 'c1') c1Runs += 1;
        started.add(captureId);
        if (captureId == 'hold') await gate.future;
        return CaptureProcessResult.succeeded;
      },
    );
    await client.initialize(() {});
    await client.appendCapture(
      queueName: captureProcessingQueue,
      taskName: captureProcessingTask,
      captureId: 'hold',
      tag: 'capture:hold',
    );
    await client.appendCapture(
      queueName: captureProcessingQueue,
      taskName: captureProcessingTask,
      captureId: 'c1',
      tag: 'capture:c1',
    );
    await client.appendCapture(
      queueName: captureProcessingQueue,
      taskName: captureProcessingTask,
      captureId: 'c1',
      tag: 'capture:c1',
    );
    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(c1Runs, 1);
  });

  test('retry uses 30s then 60s exponential backoff before succeeding', () async {
    final waits = <Duration>[];
    var runs = 0;
    final client = InAppSerialBackgroundWorkClient(
      runner: (captureId) async {
        runs += 1;
        if (runs < 3) return CaptureProcessResult.retry;
        return CaptureProcessResult.succeeded;
      },
      wait: (duration) async {
        waits.add(duration);
      },
    );
    await client.appendCapture(
      queueName: captureProcessingQueue,
      taskName: captureProcessingTask,
      captureId: 'c1',
      tag: 'capture:c1',
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(runs, 3);
    expect(waits, [
      const Duration(seconds: 30),
      const Duration(seconds: 60),
    ]);
  });

  test('retry of c1 does not block c2', () async {
    final started = <String>[];
    final retryGate = Completer<void>();
    var c1Runs = 0;
    final client = InAppSerialBackgroundWorkClient(
      runner: (captureId) async {
        started.add(captureId);
        if (captureId == 'c1') {
          c1Runs += 1;
          if (c1Runs == 1) return CaptureProcessResult.retry;
        }
        return CaptureProcessResult.succeeded;
      },
      wait: (_) => retryGate.future,
    );
    unawaited(
      client.appendCapture(
        queueName: captureProcessingQueue,
        taskName: captureProcessingTask,
        captureId: 'c1',
        tag: 'capture:c1',
      ),
    );
    unawaited(
      client.appendCapture(
        queueName: captureProcessingQueue,
        taskName: captureProcessingTask,
        captureId: 'c2',
        tag: 'capture:c2',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(started, ['c1', 'c2']);
    expect(c1Runs, 1);
    retryGate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c1Runs, 2);
    expect(started, ['c1', 'c2', 'c1']);
  });

  test('runner throw schedules retry with 30s backoff', () async {
    final waits = <Duration>[];
    var runs = 0;
    final client = InAppSerialBackgroundWorkClient(
      runner: (captureId) async {
        runs += 1;
        if (runs == 1) throw StateError('boom');
        return CaptureProcessResult.succeeded;
      },
      wait: (duration) async {
        waits.add(duration);
      },
    );
    await client.appendCapture(
      queueName: captureProcessingQueue,
      taskName: captureProcessingTask,
      captureId: 'c1',
      tag: 'capture:c1',
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(runs, 2);
    expect(waits, [const Duration(seconds: 30)]);
  });

  test('failed does not requeue', () async {
    final waits = <Duration>[];
    var runs = 0;
    final client = InAppSerialBackgroundWorkClient(
      runner: (captureId) async {
        runs += 1;
        return CaptureProcessResult.failed;
      },
      wait: (duration) async {
        waits.add(duration);
      },
    );
    await client.appendCapture(
      queueName: captureProcessingQueue,
      taskName: captureProcessingTask,
      captureId: 'c1',
      tag: 'capture:c1',
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(runs, 1);
    expect(waits, isEmpty);
  });
}
