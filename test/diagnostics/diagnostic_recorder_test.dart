import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/diagnostics/diagnostic_event.dart';
import 'package:sitemark/diagnostics/diagnostic_event_store.dart';
import 'package:sitemark/diagnostics/diagnostic_recorder.dart';

// The store's default clock is the real system clock and readRecent applies
// a 7-day retention cutoff, so the event must stay near "now" — a hardcoded
// date silently falls out of the window a week after it was written.
DiagnosticEvent _event() => DiagnosticEvent(
  timestamp: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
  category: DiagnosticCategory.app,
  outcome: DiagnosticOutcome.success,
);

void main() {
  test('record persists the event and keeps droppedCount at zero', () async {
    final root = await Directory.systemTemp.createTemp('sitemark-recorder-ok-');
    addTearDown(() => root.delete(recursive: true));
    final store = DiagnosticEventStore(directory: root);
    final recorder = DiagnosticRecorder(store);

    recorder.record(_event());
    // The recorder fire-and-forgets the append; the store writes with an
    // exclusive file lock, so retry the read until the pipeline settles
    // (Windows rejects concurrent readInto with errno 33).
    var persisted = false;
    for (var attempt = 0; attempt < 100 && !persisted; attempt++) {
      await pumpEventQueue();
      try {
        persisted = (await store.readRecent()).isNotEmpty;
      } on PathAccessException {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    expect(persisted, isTrue, reason: 'event never reached the store file');
    expect(recorder.droppedCount, 0);
  });

  test('a failing store increments droppedCount instead of throwing', () async {
    // Point the store at an existing *file* so `directory.create` rejects
    // every append — deterministic storage failure without mocking IO.
    final root = await Directory.systemTemp.createTemp('sitemark-recorder-io-');
    addTearDown(() => root.delete(recursive: true));
    final blocker = File('${root.path}${Platform.pathSeparator}blocked');
    await blocker.writeAsString('not a directory');
    final store = DiagnosticEventStore(
      directory: Directory('${blocker.path}${Platform.pathSeparator}events'),
    );
    final recorder = DiagnosticRecorder(store);

    recorder.record(_event());
    await _waitForDropped(recorder, 1);
  });

  test('a store future that fails increments droppedCount', () async {
    final recorder = DiagnosticRecorder.fromFuture(
      Future.error(StateError('store unavailable')),
    );

    recorder.record(_event());
    await _waitForDropped(recorder, 1);
  });
}

/// The recorder fire-and-forgets the append through real file IO, so the
/// drop only surfaces after the event loop settles — poll instead of
/// relying on microtask draining (flaky under a full-suite run).
Future<void> _waitForDropped(DiagnosticRecorder recorder, int expected) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (recorder.droppedCount >= expected) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail(
    'droppedCount never reached $expected (was ${recorder.droppedCount}); '
    'the append failure was not recorded',
  );
}
