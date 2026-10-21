import 'dart:async';

import 'package:sitemark/diagnostics/diagnostic_event.dart';
import 'package:sitemark/diagnostics/diagnostic_event_store.dart';

class DiagnosticRecorder {
  DiagnosticRecorder(DiagnosticEventStore store) : _store = Future.value(store);

  DiagnosticRecorder.fromFuture(Future<DiagnosticEventStore> store)
    : _store = store;

  final Future<DiagnosticEventStore> _store;

  /// Events dropped because the store rejected them (unwritable directory,
  /// disk failure, ...). Recording must never crash the app, so append
  /// failures are swallowed — this counter keeps them detectable instead of
  /// fully silent, and is surfaced in generated diagnostic bundles.
  int _droppedCount = 0;
  int get droppedCount => _droppedCount;

  void record(DiagnosticEvent event) {
    unawaited(recordAndFlush(event));
  }

  /// Background isolates must finish the write before returning to WorkManager.
  /// Diagnostic storage failures must never change the capture's outcome.
  Future<void> recordAndFlush(DiagnosticEvent event) async {
    try {
      final store = await _store;
      await store.append(event);
    } catch (_) {
      _droppedCount++;
    }
  }
}
