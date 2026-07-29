import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/workflow/app_startup_recovery.dart';

void main() {
  test(
    'cleans interrupted imports, bundles, and deletions before core recovery',
    () async {
      final events = <String>[];
      final recovery = AppStartupRecovery(
        recoverCamera: () async => events.add('camera'),
        resolveLocations: () async => events.add('location'),
        reconcileQueue: () async => events.add('queue'),
        cleanupInterruptedImports: () async => events.add('imports'),
        cleanupInterruptedBundleRestores: () async => events.add('bundles'),
        cleanupInterruptedProjectDeletions: () async => events.add('deletions'),
      );

      await recovery.run();

      expect(events, [
        'imports',
        'bundles',
        'deletions',
        'camera',
        'location',
        'queue',
      ]);
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
      cleanupInterruptedBundleRestores: () async => events.add('bundles'),
      cleanupInterruptedProjectDeletions: () async => events.add('deletions'),
    );

    await recovery.run();

    expect(events, [
      'imports',
      'bundles',
      'deletions',
      'camera',
      'location',
      'queue',
    ]);
  });

  test(
    'bundle cleanup failure does not block later startup recovery',
    () async {
      final events = <String>[];
      final recovery = AppStartupRecovery(
        recoverCamera: () async => events.add('camera'),
        resolveLocations: () async => events.add('location'),
        reconcileQueue: () async => events.add('queue'),
        cleanupInterruptedImports: () async => events.add('imports'),
        cleanupInterruptedBundleRestores: () async {
          events.add('bundles');
          throw StateError('simulated bundle cleanup failure');
        },
        cleanupInterruptedProjectDeletions: () async => events.add('deletions'),
      );

      await recovery.run();

      expect(events, [
        'imports',
        'bundles',
        'deletions',
        'camera',
        'location',
        'queue',
      ]);
    },
  );

  test(
    'project deletion cleanup failure does not block core startup recovery',
    () async {
      final events = <String>[];
      final recovery = AppStartupRecovery(
        recoverCamera: () async => events.add('camera'),
        resolveLocations: () async => events.add('location'),
        reconcileQueue: () async => events.add('queue'),
        cleanupInterruptedImports: () async => events.add('imports'),
        cleanupInterruptedBundleRestores: () async => events.add('bundles'),
        cleanupInterruptedProjectDeletions: () async {
          events.add('deletions');
          throw StateError('simulated deletion cleanup failure');
        },
      );

      await recovery.run();

      expect(events, [
        'imports',
        'bundles',
        'deletions',
        'camera',
        'location',
        'queue',
      ]);
    },
  );

  test('all cleanup failures remain isolated from core recovery', () async {
    final events = <String>[];
    final recovery = AppStartupRecovery(
      recoverCamera: () async => events.add('camera'),
      resolveLocations: () async => events.add('location'),
      reconcileQueue: () async => events.add('queue'),
      cleanupInterruptedImports: () async {
        events.add('imports');
        throw StateError('import');
      },
      cleanupInterruptedBundleRestores: () async {
        events.add('bundles');
        throw StateError('bundle');
      },
      cleanupInterruptedProjectDeletions: () async {
        events.add('deletions');
        throw StateError('delete');
      },
    );

    await recovery.run();

    expect(events, [
      'imports',
      'bundles',
      'deletions',
      'camera',
      'location',
      'queue',
    ]);
  });
}
