import 'dart:async';

import 'package:sitemark/diagnostics/diagnostic_event.dart';
import 'package:sitemark/diagnostics/diagnostic_event_store.dart';

class DiagnosticRecorder {
  DiagnosticRecorder(DiagnosticEventStore store) : _store = Future.value(store);

  DiagnosticRecorder.fromFuture(Future<DiagnosticEventStore> store)
    : _store = store;

  final Future<DiagnosticEventStore> _store;

  void record(DiagnosticEvent event) {
    unawaited(_store.then((store) => store.append(event)).catchError((_) {}));
  }
}
