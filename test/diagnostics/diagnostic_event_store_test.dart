import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/diagnostics/diagnostic_event.dart';
import 'package:sitemark/diagnostics/diagnostic_event_store.dart';

void main() {
  test('reads and clears wait for preceding writes', () async {
    final root = await Directory.systemTemp.createTemp(
      'sitemark-diag-ordered-',
    );
    addTearDown(() => root.delete(recursive: true));
    final store = DiagnosticEventStore(directory: root);
    final write = store.append(
      DiagnosticEvent(
        timestamp: DateTime.now(),
        category: DiagnosticCategory.app,
        outcome: DiagnosticOutcome.success,
      ),
    );
    final read = store.readRecent();
    final clear = store.clear();
    expect(await read, hasLength(1));
    await write;
    await clear;
    expect(await store.readRecent(), isEmpty);
  });
  test(
    'drops expired events and never serializes arbitrary private text',
    () async {
      final root = await Directory.systemTemp.createTemp('sitemark-diag-test-');
      addTearDown(() => root.delete(recursive: true));
      final now = DateTime.utc(2026, 7, 30);
      final store = DiagnosticEventStore(
        directory: root,
        clock: () => now,
        maxBytes: 2048,
      );

      await store.append(
        DiagnosticEvent(
          timestamp: now.subtract(const Duration(days: 8)),
          category: DiagnosticCategory.app,
          outcome: DiagnosticOutcome.success,
        ),
      );
      await store.append(
        DiagnosticEvent(
          timestamp: now,
          category: DiagnosticCategory.backup,
          outcome: DiagnosticOutcome.failed,
          code: DiagnosticCode.noCompletedRecords,
          count: 1,
        ),
      );

      final events = await store.readRecent();
      expect(events, hasLength(1));
      final raw = await File('${root.path}/events.jsonl').readAsString();
      expect(raw, isNot(contains('项目')));
      expect(raw, isNot(contains('/storage/')));
    },
  );
}
