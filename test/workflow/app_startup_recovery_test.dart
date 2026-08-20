import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/workflow/app_startup_recovery.dart';

AppStartupRecovery recoveryFor(
  List<String> events, {
  Future<void> Function()? recoverCamera,
  Future<void> Function()? reconcileQueue,
  Future<void> Function()? cleanupInterruptedCaptureMedia,
  Future<void> Function()? recoverPublishJournals,
  Future<void> Function()? cleanupInterruptedExports,
  Future<void> Function()? cleanupInterruptedImports,
  Future<void> Function()? cleanupInterruptedBundleRestores,
  Future<void> Function()? cleanupInterruptedProjectDeletions,
  Future<void> Function()? resolveLocations,
}) {
  Future<void> stage(String name) async => events.add(name);
  return AppStartupRecovery(
    recoverCamera: recoverCamera ?? () => stage('camera'),
    resolveLocations: resolveLocations ?? () => stage('location'),
    reconcileQueue: reconcileQueue ?? () => stage('queue'),
    cleanupInterruptedExports:
        cleanupInterruptedExports ?? () => stage('exports'),
    cleanupInterruptedImports:
        cleanupInterruptedImports ?? () => stage('imports'),
    cleanupInterruptedBundleRestores:
        cleanupInterruptedBundleRestores ?? () => stage('bundles'),
    cleanupInterruptedProjectDeletions:
        cleanupInterruptedProjectDeletions ?? () => stage('deletions'),
    cleanupInterruptedCaptureMedia:
        cleanupInterruptedCaptureMedia ?? () => stage('media'),
    recoverPublishJournals:
        recoverPublishJournals ?? () => stage('publishJournals'),
  );
}

void expectCleanupThenCore(List<String> events) {
  expect(events.take(4).toList(), [
    'exports',
    'imports',
    'bundles',
    'deletions',
  ]);
  expect(
    events.skip(4).toSet(),
    {
      'media',
      'publishJournals',
      'camera',
      'location',
      'queue',
    },
  );
  expect(events, hasLength(9));
}

void main() {
  test(
    'cleans interrupted imports, bundles, and deletions before core recovery',
    () async {
      final events = <String>[];
      await recoveryFor(events).run();
      expectCleanupThenCore(events);
    },
  );

  test('import cleanup failure does not block core startup recovery', () async {
    final events = <String>[];
    await recoveryFor(
      events,
      cleanupInterruptedImports: () async {
        events.add('imports');
        throw StateError('simulated cleanup failure');
      },
    ).run();
    expectCleanupThenCore(events);
  });

  test(
    'bundle cleanup failure does not block later startup recovery',
    () async {
      final events = <String>[];
      await recoveryFor(
        events,
        cleanupInterruptedBundleRestores: () async {
          events.add('bundles');
          throw StateError('simulated bundle cleanup failure');
        },
      ).run();
      expectCleanupThenCore(events);
    },
  );

  test(
    'project deletion cleanup failure does not block core startup recovery',
    () async {
      final events = <String>[];
      await recoveryFor(
        events,
        cleanupInterruptedProjectDeletions: () async {
          events.add('deletions');
          throw StateError('simulated deletion cleanup failure');
        },
      ).run();
      expectCleanupThenCore(events);
    },
  );

  test('all cleanup failures remain isolated from core recovery', () async {
    final events = <String>[];
    await recoveryFor(
      events,
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
    ).run();
    expectCleanupThenCore(events);
  });

  for (final failingStage in ['publishJournals', 'camera', 'location', 'queue']) {
    test(
      '$failingStage recovery failure does not block later stages',
      () async {
        final events = <String>[];
        Future<void> stage(String name) async {
          events.add(name);
          if (name == failingStage) throw StateError(name);
        }

        await recoveryFor(
          events,
          recoverCamera: () => stage('camera'),
          resolveLocations: () => stage('location'),
          reconcileQueue: () => stage('queue'),
          cleanupInterruptedExports: () => stage('exports'),
          cleanupInterruptedImports: () => stage('imports'),
          cleanupInterruptedBundleRestores: () => stage('bundles'),
          cleanupInterruptedProjectDeletions: () => stage('deletions'),
          cleanupInterruptedCaptureMedia: () => stage('media'),
          recoverPublishJournals: () => stage('publishJournals'),
        ).run();
        expectCleanupThenCore(events);
      },
    );
  }

  test(
    'hanging camera recovery still starts queue journal and album windows',
    () async {
      final cameraHang = Completer<void>();
      final started = <String>[];
      final recovery = AppStartupRecovery(
        recoverCamera: () async {
          started.add('camera');
          await cameraHang.future;
        },
        resolveLocations: () async => started.add('location'),
        reconcileQueue: () async => started.add('queue'),
        cleanupInterruptedExports: () async => started.add('exports'),
        cleanupInterruptedImports: () async => started.add('imports'),
        cleanupInterruptedBundleRestores: () async => started.add('bundles'),
        cleanupInterruptedProjectDeletions: () async => started.add('deletions'),
        cleanupInterruptedCaptureMedia: () async => started.add('media'),
        recoverPublishJournals: () async => started.add('publishJournals'),
      );

      unawaited(recovery.run());
      for (var i = 0; i < 20; i++) {
        if (started.contains('queue') &&
            started.contains('media') &&
            started.contains('publishJournals')) {
          break;
        }
        await Future<void>.delayed(Duration.zero);
      }

      expect(
        started,
        containsAll(['camera', 'queue', 'media', 'publishJournals']),
      );
      expect(cameraHang.isCompleted, isFalse);
    },
  );

  test('camera recovery error does not skip queue reconcile', () async {
    final events = <String>[];
    await recoveryFor(
      events,
      recoverCamera: () async {
        events.add('camera');
        throw StateError('camera host dead');
      },
    ).run();

    expect(
      events,
      containsAll(['camera', 'queue', 'media', 'publishJournals']),
    );
  });
}
