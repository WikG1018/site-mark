import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/conditional_polling_stream.dart';
import 'package:sitemark/domain/capture_status.dart';

void main() {
  test('polls while processing and stops after a terminal value', () async {
    final source = StreamController<CaptureStatus>();
    var stored = CaptureStatus.captured;
    var reads = 0;
    final readySeen = Completer<void>();
    final subscription =
        watchWithConditionalPolling<CaptureStatus>(
          source: source.stream,
          load: () async {
            reads += 1;
            return stored;
          },
          shouldPoll: (status) =>
              status == CaptureStatus.captured ||
              status == CaptureStatus.rendering,
          pollInterval: const Duration(milliseconds: 5),
        ).listen((status) {
          if (status == CaptureStatus.ready && !readySeen.isCompleted) {
            readySeen.complete();
          }
        });

    source.add(CaptureStatus.captured);
    await Future<void>.delayed(Duration.zero);
    stored = CaptureStatus.ready;
    await readySeen.future.timeout(const Duration(milliseconds: 200));
    final readsAtReady = reads;
    await Future<void>.delayed(const Duration(milliseconds: 25));

    expect(reads, readsAtReady);
    await subscription.cancel();
    await source.close();
  });

  test('does not poll when the source starts terminal', () async {
    final source = StreamController<CaptureStatus>();
    var reads = 0;
    final subscription = watchWithConditionalPolling<CaptureStatus>(
      source: source.stream,
      load: () async {
        reads += 1;
        return CaptureStatus.ready;
      },
      shouldPoll: (status) =>
          status == CaptureStatus.captured || status == CaptureStatus.rendering,
      pollInterval: const Duration(milliseconds: 5),
    ).listen((_) {});

    source.add(CaptureStatus.ready);
    await Future<void>.delayed(const Duration(milliseconds: 25));

    expect(reads, 0);
    await subscription.cancel();
    await source.close();
  });

  test('cancelling the subscription stops an active poller', () async {
    final source = StreamController<CaptureStatus>();
    final loadStarted = Completer<void>();
    final releaseLoad = Completer<void>();
    var reads = 0;
    final subscription = watchWithConditionalPolling<CaptureStatus>(
      source: source.stream,
      load: () async {
        reads += 1;
        if (!loadStarted.isCompleted) loadStarted.complete();
        await releaseLoad.future;
        return CaptureStatus.captured;
      },
      shouldPoll: (status) => status == CaptureStatus.captured,
      pollInterval: const Duration(milliseconds: 5),
    ).listen((_) {});

    source.add(CaptureStatus.captured);
    await loadStarted.future.timeout(const Duration(milliseconds: 200));
    await subscription.cancel();
    final readsAtCancel = reads;
    releaseLoad.complete();
    await Future<void>.delayed(const Duration(milliseconds: 25));

    expect(reads, readsAtCancel);
    await source.close();
  });

  test('discards stale poll result when source emits a newer value', () async {
    final source = StreamController<CaptureStatus>();
    final loadStarted = Completer<void>();
    final releaseLoad = Completer<void>();
    final emitted = <CaptureStatus>[];
    var loadCalls = 0;
    final subscription =
        watchWithConditionalPolling<CaptureStatus>(
          source: source.stream,
          load: () async {
            loadCalls += 1;
            if (!loadStarted.isCompleted) loadStarted.complete();
            await releaseLoad.future;
            return CaptureStatus.captured;
          },
          shouldPoll: (status) =>
              status == CaptureStatus.captured ||
              status == CaptureStatus.rendering,
          pollInterval: const Duration(milliseconds: 5),
        ).listen((status) {
          emitted.add(status);
        });

    // Source emits captured → polling starts.
    source.add(CaptureStatus.captured);
    await Future<void>.delayed(Duration.zero);

    // Wait for the first poll to start (load is now in-flight).
    await loadStarted.future.timeout(const Duration(milliseconds: 200));

    // Source emits ready while the poll is in-flight.
    source.add(CaptureStatus.ready);
    await Future<void>.delayed(Duration.zero);

    // Release the stale load → it returns captured.
    releaseLoad.complete();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    // The stale captured must NOT have overwritten ready.
    expect(emitted, [CaptureStatus.captured, CaptureStatus.ready]);
    expect(loadCalls, 1);

    await subscription.cancel();
    await source.close();
  });

  test('isPaused skips loads while paused and resumes when unpaused', () async {
    final source = StreamController<CaptureStatus>();
    var paused = true;
    var reads = 0;
    final subscription = watchWithConditionalPolling<CaptureStatus>(
      source: source.stream,
      load: () async {
        reads += 1;
        return CaptureStatus.captured;
      },
      shouldPoll: (status) => status == CaptureStatus.captured,
      pollInterval: const Duration(milliseconds: 5),
      isPaused: () => paused,
    ).listen((_) {});

    // Source emits captured, but polling is paused → no reads should happen
    // even after several intervals.
    source.add(CaptureStatus.captured);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(reads, 0);

    // Unpause → the timer is already running, so the next tick (within one
    // interval) should resume the actual load.
    paused = false;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(reads, greaterThan(0));

    final readsAtResume = reads;
    // Re-pause → reads should stop accumulating (timer keeps running but
    // skips the load).
    paused = true;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(reads, readsAtResume);

    await subscription.cancel();
    await source.close();
  });
}
