import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/background/capture_background_scheduler.dart';
import 'package:sitemark/platform/ohos_background_work_client.dart';

void main() {
  test('appendCapture runs one capture at a time in enqueue order', () async {
    final started = <String>[];
    final client = InAppSerialBackgroundWorkClient(
      runner: (captureId) async {
        started.add(captureId);
        await Future<void>.delayed(const Duration(milliseconds: 20));
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
}
