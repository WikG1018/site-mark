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
        cleanupInterruptedExports: () async => events.add('exports'),
        cleanupInterruptedImports: () async => events.add('imports'),
        cleanupInterruptedBundleRestores: () async => events.add('bundles'),
        cleanupInterruptedProjectDeletions: () async => events.add('deletions'),
        cleanupInterruptedCaptureMedia: () async => events.add('media'),
      );

      await recovery.run();

      expect(events, [
        'exports',
        'imports',
        'bundles',
        'deletions',
        'media',
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
      cleanupInterruptedExports: () async => events.add('exports'),
      cleanupInterruptedImports: () async {
        events.add('imports');
        throw StateError('simulated cleanup failure');
      },
      cleanupInterruptedBundleRestores: () async => events.add('bundles'),
      cleanupInterruptedProjectDeletions: () async => events.add('deletions'),
      cleanupInterruptedCaptureMedia: () async => events.add('media'),
    );

    await recovery.run();

    expect(events, [
      'exports',
      'imports',
      'bundles',
      'deletions',
      'media',
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
        cleanupInterruptedExports: () async => events.add('exports'),
        cleanupInterruptedImports: () async => events.add('imports'),
        cleanupInterruptedBundleRestores: () async {
          events.add('bundles');
          throw StateError('simulated bundle cleanup failure');
        },
        cleanupInterruptedProjectDeletions: () async => events.add('deletions'),
        cleanupInterruptedCaptureMedia: () async => events.add('media'),
      );

      await recovery.run();

      expect(events, [
        'exports',
        'imports',
        'bundles',
        'deletions',
        'media',
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
        cleanupInterruptedExports: () async => events.add('exports'),
        cleanupInterruptedImports: () async => events.add('imports'),
        cleanupInterruptedBundleRestores: () async => events.add('bundles'),
        cleanupInterruptedProjectDeletions: () async {
          events.add('deletions');
          throw StateError('simulated deletion cleanup failure');
        },
        cleanupInterruptedCaptureMedia: () async => events.add('media'),
      );

      await recovery.run();

      expect(events, [
        'exports',
        'imports',
        'bundles',
        'deletions',
        'media',
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
      cleanupInterruptedExports: () async {
        events.add('exports');
        throw StateError('export');
      },
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
      cleanupInterruptedCaptureMedia: () async {
        events.add('media');
        throw StateError('media');
      },
    );

    await recovery.run();

    expect(events, [
      'exports',
      'imports',
      'bundles',
      'deletions',
      'media',
      'camera',
      'location',
      'queue',
    ]);
  });

  for (final failingStage in ['camera', 'location', 'queue']) {
    test(
      '$failingStage recovery failure does not block later stages',
      () async {
        final events = <String>[];
        Future<void> stage(String name) async {
          events.add(name);
          if (name == failingStage) throw StateError(name);
        }

        final recovery = AppStartupRecovery(
          recoverCamera: () => stage('camera'),
          resolveLocations: () => stage('location'),
          reconcileQueue: () => stage('queue'),
          cleanupInterruptedExports: () => stage('exports'),
          cleanupInterruptedImports: () => stage('imports'),
          cleanupInterruptedBundleRestores: () => stage('bundles'),
          cleanupInterruptedProjectDeletions: () => stage('deletions'),
          cleanupInterruptedCaptureMedia: () => stage('media'),
        );

        await recovery.run();

        expect(events, [
          'exports',
          'imports',
          'bundles',
          'deletions',
          'media',
          'camera',
          'location',
          'queue',
        ]);
      },
    );
  }
}
