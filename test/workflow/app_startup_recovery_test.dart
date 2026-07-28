import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/workflow/app_startup_recovery.dart';

void main() {
  test(
    'cleans interrupted imports and deletions, then recovers camera, locations, and queue',
    () async {
      final events = <String>[];
      final recovery = AppStartupRecovery(
        recoverCamera: () async => events.add('camera'),
        resolveLocations: () async => events.add('location'),
        reconcileQueue: () async => events.add('queue'),
        cleanupInterruptedImports: () async => events.add('imports'),
        cleanupInterruptedProjectDeletions: () async => events.add('deletions'),
      );

      await recovery.run();

      expect(events, ['imports', 'deletions', 'camera', 'location', 'queue']);
    },
  );

  test('import cleanup failure does not block core startup recovery', () async {
    final events = <String>[];
    final recovery = AppStartupRecovery(
      recoverCamera: () async => events.add('camera'),
      resolveLocations: () async => events.add('location'),
      reconcileQueue: () async => events.add('queue'),
      cleanupInterruptedImports: () async {
        events.add('imports');
        throw StateError('simulated cleanup failure');
      },
      cleanupInterruptedProjectDeletions: () async => events.add('deletions'),
    );

    await recovery.run();

    expect(events, ['imports', 'deletions', 'camera', 'location', 'queue']);
  });

  test(
    'project deletion cleanup failure does not block core startup recovery',
    () async {
      final events = <String>[];
      final recovery = AppStartupRecovery(
        recoverCamera: () async => events.add('camera'),
        resolveLocations: () async => events.add('location'),
        reconcileQueue: () async => events.add('queue'),
        cleanupInterruptedImports: () async => events.add('imports'),
        cleanupInterruptedProjectDeletions: () async {
          events.add('deletions');
          throw StateError('simulated deletion cleanup failure');
        },
      );

      await recovery.run();

      expect(events, ['imports', 'deletions', 'camera', 'location', 'queue']);
    },
  );
}
