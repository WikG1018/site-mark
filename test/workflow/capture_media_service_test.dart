import 'dart:io' show Directory;
import 'dart:ui' show Locale;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/diagnostics/diagnostic_event.dart';
import 'package:sitemark/diagnostics/diagnostic_event_store.dart';
import 'package:sitemark/diagnostics/diagnostic_recorder.dart';
import 'package:sitemark/domain/capture_media_failure.dart';
import 'package:sitemark/domain/project_lifecycle.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/domain/original_photo_state.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/capture_media_cleanup_store.dart';
import 'package:sitemark/workflow/capture_media_service.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

const digestA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  late AppDatabase database;
  late _MediaFiles files;
  late _MediaPlatform platform;
  late _MediaPaths paths;
  late MemoryCaptureMediaCleanupPendingStore pendingStore;
  late CaptureMediaService service;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'project-1', name: '东区厂房改造');
    final pending = await database.createPendingCapture(
      id: 'capture-1',
      projectId: 'project-1',
      originalPath: '/private/original.jpg',
      workLocation: 'A 区',
      workContent: '风管检查',
      photographer: '张工',
      watermarkLocaleCode: 'zh',
      locationResolution: 'resolved',
    );
    await database.markCaptured(
      captureId: pending.id,
      capturedAt: DateTime(2026, 7, 16, 9),
    );
    await database.markRendering(
      captureId: pending.id,
      originalSha256: digestA,
    );
    await database.markReady(
      captureId: pending.id,
      publishedUri: 'content://media/site-mark/1',
    );

    files = _MediaFiles();
    platform = _MediaPlatform();
    paths = _MediaPaths();
    pendingStore = MemoryCaptureMediaCleanupPendingStore();
    service = CaptureMediaService(
      database: database,
      platform: platform,
      outputPaths: paths,
      files: files,
      pendingStore: pendingStore,
    );
  });

  /// Creates a second fully-`ready` capture row referencing [publishedUri],
  /// e.g. to simulate a legacy upgrade where two records share one URI.
  Future<void> createSecondReadyCapture(String publishedUri) async {
    final pending = await database.createPendingCapture(
      id: 'capture-2',
      projectId: 'project-1',
      originalPath: '/private/original-2.jpg',
      workLocation: 'B 区',
      workContent: '桥架检查',
      photographer: '李工',
      watermarkLocaleCode: 'zh',
      locationResolution: 'resolved',
    );
    await database.markCaptured(
      captureId: pending.id,
      capturedAt: DateTime(2026, 7, 16, 10),
    );
    await database.markRendering(
      captureId: pending.id,
      originalSha256: digestA,
    );
    await database.markReady(captureId: pending.id, publishedUri: publishedUri);
  }

  CaptureRecord mediaRecord({DateTime? originalDeletedAt}) => CaptureRecord(
    id: 'capture-1',
    projectId: 'project-1',
    photoNumber: 'SM-20260716-001',
    workLocation: 'A 区',
    workContent: '风管检查',
    photographer: '张工',
    originalPath: '/private/original.jpg',
    publishedUri: 'content://media/site-mark/1',
    originalSha256: digestA,
    status: CaptureStatus.ready,
    createdAt: DateTime(2026, 7, 16, 9),
    capturedAt: DateTime(2026, 7, 16, 9),
    processingAttempts: 0,
    watermarkLocaleCode: 'zh',
    locationResolution: 'resolved',
    originalDeletedAt: originalDeletedAt,
  );

  test('original state distinguishes retained cleared and missing', () async {
    files.existing.add('/private/original.jpg');
    expect(
      await service.originalState(mediaRecord()),
      OriginalPhotoState.retained,
    );

    expect(
      await service.originalState(
        mediaRecord(originalDeletedAt: DateTime(2026, 7, 16)),
      ),
      OriginalPhotoState.cleared,
    );

    files.existing.clear();
    expect(
      await service.originalState(mediaRecord()),
      OriginalPhotoState.missing,
    );
  });

  test(
    'inspect reports original and rendered metadata independently',
    () async {
      files.existing.addAll([
        '/private/original.jpg',
        '/rendered/capture-1.jpg',
      ]);
      platform.metadataByPath['/private/original.jpg'] = ImageMetadataResult(
        width: 4000,
        height: 3000,
        fileSizeBytes: 5_000_000,
        mimeType: 'image/jpeg',
      );
      platform.metadataByPath['/rendered/capture-1.jpg'] = ImageMetadataResult(
        width: 4000,
        height: 3000,
        fileSizeBytes: 3_200_000,
        mimeType: 'image/jpeg',
      );

      final info = await service.inspect(mediaRecord());
      expect(info.original?.fileSizeBytes, 5_000_000);
      expect(info.watermarked?.fileSizeBytes, 3_200_000);
      expect(info.originalState, OriginalPhotoState.retained);
    },
  );

  test(
    'clear originals preserves record rendered image URI and hash',
    () async {
      files.existing.add('/private/original.jpg');
      final result = await service.clearOriginals(['capture-1']);
      final row = await database.captureById('capture-1');
      expect(result.succeededIds, ['capture-1']);
      expect(files.deleted, ['/private/original.jpg']);
      expect(row, isNotNull);
      expect(row?.publishedUri, 'content://media/site-mark/1');
      expect(row?.originalSha256, digestA);
      expect(row?.originalDeletedAt, isNotNull);
    },
  );

  test('delete all retries gallery cleanup after the row commits', () async {
    platform.deleteError = StateError('MediaStore failure');
    final result = await service.deleteAll(['capture-1']);
    expect(result.succeededIds, ['capture-1']);
    expect(await database.captureById('capture-1'), isNull);
    // The gallery delete failed but the durable superseded-cleanup task
    // committed WITH the row deletion; the app-private marker only covers
    // the private files, which deleted fine.
    expect(await pendingStore.list(), isEmpty);
    expect(
      (await database.pendingSupersededCleanups()).map(
        (task) => task.publishedUri,
      ),
      ['content://media/site-mark/1'],
    );

    platform.deleteError = null;
    await service.cleanupInterrupted();

    expect(platform.deletedUris, ['content://media/site-mark/1']);
    expect(await database.pendingSupersededCleanups(), isEmpty);
  });

  test(
    'cleanup retry budget stalls a permanently failing URI until re-enqueued',
    () async {
      platform.failingDeleteUris.add('content://media/site-mark/1');
      // deleteAll queues the task AND drives the queue once in the same
      // user action, so the first failed attempt is already counted.
      final result = await service.deleteAll(['capture-1']);
      expect(result.succeededIds, ['capture-1']);
      var task = (await database.pendingSupersededCleanups()).single;
      expect(task.retryCount, 1);
      expect(task.stalledAt, isNull);

      // Each later launch records one more failed attempt; the loop stops
      // BEFORE the budget-exhausting attempt, which runs below and parks
      // the task out of the pending set.
      for (
        var attempt = 2;
        attempt < CaptureMediaService.maxCleanupRetries;
        attempt++
      ) {
        await service.cleanupInterrupted();
        task = (await database.pendingSupersededCleanups()).single;
        expect(task.retryCount, attempt);
        expect(task.stalledAt, isNull);
      }

      // The attempt that exhausts the budget parks the task: no longer
      // pending, visible as stalled, and NEVER retried on later launches.
      await service.cleanupInterrupted();
      expect(await database.pendingSupersededCleanups(), isEmpty);
      final stalled = await database.stalledSupersededCleanups();
      expect(stalled, hasLength(1));
      expect(stalled.single.retryCount, CaptureMediaService.maxCleanupRetries);
      expect(stalled.single.stalledAt, isNotNull);

      platform.failingDeleteUris.clear();
      await service.cleanupInterrupted();
      expect(platform.deletedUris, isEmpty);

      // A URI still referenced by any record must NOT consume budget even
      // after re-enqueue: waiting for the last reference to disappear is
      // normal convergence, not a failure.
      // Re-enqueueing the URI (a fresh publish of that capture) resets the
      // budget and lets the delete converge.
      await database.enqueueSupersededCleanups('capture-1', [
        'content://media/site-mark/1',
      ]);
      final resumed = (await database.pendingSupersededCleanups()).single;
      expect(resumed.retryCount, 0);
      expect(resumed.stalledAt, isNull);
      expect(await database.stalledSupersededCleanups(), isEmpty);

      await service.cleanupInterrupted();
      expect(platform.deletedUris, ['content://media/site-mark/1']);
      expect(await database.pendingSupersededCleanups(), isEmpty);
    },
  );

  test('a referenced URI never consumes the cleanup retry budget', () async {
    // Two rows share one legacy URI. The owner already republished to a
    // NEW URI, so only the sibling still references the stale one — the
    // upgrade scenario where the queue holds a URI another record uses.
    await createSecondReadyCapture('content://media/site-mark/1');
    await database.updatePublishedUri(
      'capture-1',
      'content://media/site-mark/2',
      expectedPreviousUri: 'content://media/site-mark/1',
    );
    await database.enqueueSupersededCleanups('capture-1', [
      'content://media/site-mark/1',
    ]);

    // Repeated launches keep skipping the referenced URI WITHOUT ever
    // counting a failure or stalling it.
    for (var i = 0; i < CaptureMediaService.maxCleanupRetries + 2; i++) {
      await service.cleanupInterrupted();
    }
    final task = (await database.pendingSupersededCleanups()).single;
    expect(task.retryCount, 0);
    expect(task.stalledAt, isNull);
    expect(platform.deletedUris, isEmpty);

    // Once the last reference disappears the delete converges normally.
    await database.deleteCapture('capture-2');
    await service.cleanupInterrupted();
    expect(platform.deletedUris, ['content://media/site-mark/1']);
    expect(await database.pendingSupersededCleanups(), isEmpty);
  });

  test(
    'cleanup failures, stalls, and journal recoveries emit diagnostic events',
    () async {
      final store = _RecordingDiagnosticStore();
      final recorder = DiagnosticRecorder(store);
      final observed = CaptureMediaService(
        database: database,
        platform: platform,
        outputPaths: paths,
        files: files,
        pendingStore: pendingStore,
        diagnostics: recorder,
      );

      // Drain the budget for one URI: deleteAll drives the queue once and
      // each cleanupInterrupted() one more time until the stall event.
      platform.failingDeleteUris.add('content://media/site-mark/1');
      await observed.deleteAll(['capture-1']);
      for (var i = 1; i < CaptureMediaService.maxCleanupRetries; i++) {
        await observed.cleanupInterrupted();
      }
      await pumpEventQueue();

      final deletions = store.events
          .where((event) => event.category == DiagnosticCategory.deletion)
          .toList();
      final failed = deletions
          .where((event) => event.outcome == DiagnosticOutcome.failed)
          .toList();
      final blocked = deletions
          .where((event) => event.outcome == DiagnosticOutcome.blocked)
          .toList();
      expect(failed, hasLength(CaptureMediaService.maxCleanupRetries - 1));
      expect(blocked, hasLength(1));
      expect(blocked.single.retryCount, CaptureMediaService.maxCleanupRetries);
      expect(
        failed.map((event) => event.retryCount),
        List.generate(
          CaptureMediaService.maxCleanupRetries - 1,
          (index) => index + 1,
        ),
      );

      // A recovered journal emits one processing event per entry: success
      // when its CAS commit lands.
      platform.failingDeleteUris.clear();
      platform.deleteError = null;
      final second = await database.createPendingCapture(
        id: 'capture-2',
        projectId: 'project-1',
        originalPath: '/private/original-2.jpg',
        workLocation: 'B 区',
        workContent: '桥架检查',
        photographer: '李工',
        watermarkLocaleCode: 'zh',
        locationResolution: 'resolved',
      );
      await database.markCaptured(
        captureId: second.id,
        capturedAt: DateTime(2026, 7, 16, 10),
      );
      platform.recoveredJournals
        ..clear()
        ..add(
          RecoveredPublishJournalEntry(
            captureId: 'capture-2',
            contentUri: 'content://media/site-mark/9',
            supersededUris: const [],
          ),
        );
      await observed.cleanupInterrupted();
      await pumpEventQueue();

      final recoveries = store.events
          .where((event) => event.category == DiagnosticCategory.processing)
          .toList();
      // capture-2 is `captured`: the background processor owns the state,
      // no CAS runs, and no recovery event is emitted — only real
      // reconciliation outcomes are counted. Re-check with a ready row.
      expect(recoveries, isEmpty);

      await database.markRendering(
        captureId: second.id,
        originalSha256: digestA,
      );
      await database.markReady(
        captureId: second.id,
        publishedUri: 'content://media/site-mark/8',
      );
      platform.recoveredJournals
        ..clear()
        ..add(
          RecoveredPublishJournalEntry(
            captureId: 'capture-2',
            contentUri: 'content://media/site-mark/9',
            supersededUris: const ['content://media/site-mark/8'],
          ),
        );
      await observed.cleanupInterrupted();
      await pumpEventQueue();

      final outcomes = store.events
          .where((event) => event.category == DiagnosticCategory.processing)
          .map((event) => event.outcome)
          .toList();
      expect(outcomes, contains(DiagnosticOutcome.success));
    },
  );

  test(
    'clear originals commits database state before retryable file cleanup',
    () async {
      files.existing.add('/private/original.jpg');
      files.failures.add('/private/original.jpg');

      final result = await service.clearOriginals(['capture-1']);

      expect(result.succeededIds, ['capture-1']);
      expect(
        (await database.captureById('capture-1'))?.originalDeletedAt,
        isNotNull,
      );
      expect(await pendingStore.list(), hasLength(1));

      files.failures.clear();
      await service.cleanupInterrupted();

      expect(files.existing, isNot(contains('/private/original.jpg')));
      expect(await pendingStore.list(), isEmpty);
    },
  );

  test('delete all commits the row before retryable private cleanup', () async {
    files.existing.addAll(['/private/original.jpg', '/rendered/capture-1.jpg']);
    files.failures.add('/rendered/capture-1.jpg');

    final result = await service.deleteAll(['capture-1']);

    expect(result.succeededIds, ['capture-1']);
    expect(await database.captureById('capture-1'), isNull);
    expect(await pendingStore.list(), hasLength(1));

    files.failures.clear();
    await service.cleanupInterrupted();

    expect(files.existing, isEmpty);
    expect(await pendingStore.list(), isEmpty);
  });

  test('startup resumes a delete committed only as a marker', () async {
    final pending = PendingCaptureMediaCleanup(
      captureId: 'capture-1',
      kind: CaptureMediaCleanupKind.deleteCapture,
      paths: const ['/private/original.jpg', '/rendered/capture-1.jpg'],
      publishedUri: 'content://media/site-mark/1',
    );
    files.existing.addAll(pending.paths);
    await pendingStore.write(pending);
    await database.deleteCapture('capture-1');

    await service.cleanupInterrupted();

    expect(platform.deletedUris, ['content://media/site-mark/1']);
    expect(await database.captureById('capture-1'), isNull);
    expect(files.existing, isEmpty);
    expect(await pendingStore.list(), isEmpty);
  });

  test('startup abandons an uncommitted delete marker safely', () async {
    const pending = PendingCaptureMediaCleanup(
      captureId: 'capture-1',
      kind: CaptureMediaCleanupKind.deleteCapture,
      paths: ['/private/original.jpg', '/rendered/capture-1.jpg'],
      publishedUri: 'content://media/site-mark/1',
    );
    files.existing.addAll(pending.paths);
    await pendingStore.write(pending);

    await service.cleanupInterrupted();

    expect(await database.captureById('capture-1'), isNotNull);
    expect(files.existing, containsAll(pending.paths));
    expect(platform.deletedUris, isEmpty);
    expect(await pendingStore.list(), isEmpty);
  });

  // Regression: pre-commit failures must never carry raw exceptions, stack
  // traces, or file paths. Post-commit media cleanup failures are instead
  // persisted for startup retry and count as a completed user action.
  test('pre-commit failures are enum reasons, never raw text', () async {
    files.existing.add('/private/original.jpg');
    final failingService = CaptureMediaService(
      database: database,
      platform: platform,
      outputPaths: paths,
      files: files,
      pendingStore: _ThrowingMediaCleanupPendingStore(
        StateError(
          'FileSystemException: cannot open /data/user/0/io.github.wikg1018.sitemark/files/original.jpg',
        ),
      ),
    );

    final deleteResult = await failingService.deleteAll(['capture-1']);
    expect(
      deleteResult.failures['capture-1'],
      CaptureMediaFailure.operationFailed,
    );
    // The failure is an enum reason; even the localized UI text rendered from
    // it must not carry the injected path or exception type.
    final localized = const AppStrings(
      Locale('zh'),
    ).captureMediaFailure(deleteResult.failures['capture-1']!);
    expect(localized, isNot(contains('/data/user/0')));
    expect(localized, isNot(contains('FileSystemException')));
  });

  test(
    'republish failure records enum reason, never raw exception text',
    () async {
      files.existing.add('/rendered/capture-1.jpg');
      platform.publishError = StateError(
        'MediaStore publish failed: /storage/emulated/0/DCIM/capture-1.jpg',
      );

      final result = await service.republish(['capture-1']);
      expect(result.failures['capture-1'], CaptureMediaFailure.operationFailed);
      final localized = const AppStrings(
        Locale('en'),
      ).captureMediaFailure(result.failures['capture-1']!);
      expect(localized, isNot(contains('/storage/emulated/0')));
      expect(localized, isNot(contains('StateError')));
    },
  );

  test('republish updates the actual returned URI', () async {
    files.existing.add('/rendered/capture-1.jpg');
    platform.nextPublishedUri = 'content://media/site-mark/re-saved';
    await service.republish(['capture-1']);
    expect(
      (await database.captureById('capture-1'))?.publishedUri,
      'content://media/site-mark/re-saved',
    );
  });

  // Regression: the new gallery row is finalized but the old-row delete
  // failed. The republish has already SUCCEEDED — the record must point at
  // the new URI and a delete-only cleanup task must be committed in the SAME
  // transaction; the action must not be reported as failed (which would
  // re-publish another duplicate photo).
  test(
    'republish with failed old-row delete updates URI and queues delete-only cleanup',
    () async {
      files.existing.add('/rendered/capture-1.jpg');
      platform.nextPublishedUri = 'content://media/site-mark/2';
      platform.nextSupersededUris = ['content://media/site-mark/1'];

      final result = await service.republish(['capture-1']);

      expect(result.succeededIds, ['capture-1']);
      expect(result.failures, isEmpty);
      expect(
        (await database.captureById('capture-1'))?.publishedUri,
        'content://media/site-mark/2',
      );
      final tasks = await database.pendingSupersededCleanups();
      expect(tasks, hasLength(1));
      expect(tasks.single.publishedUri, 'content://media/site-mark/1');
      expect(tasks.single.captureId, 'capture-1');
    },
  );

  // Regression: every superseded duplicate URI is an INDEPENDENT task (one
  // row per URI), so consecutive saves never overwrite each other's
  // tracking and historical duplicates all converge.
  test(
    'republish tracks every superseded URI as an independent task',
    () async {
      files.existing.add('/rendered/capture-1.jpg');
      platform.nextPublishedUri = 'content://media/site-mark/3';
      platform.nextSupersededUris = [
        'content://media/site-mark/1',
        'content://media/site-mark/2',
      ];

      await service.republish(['capture-1']);

      final tasks = await database.pendingSupersededCleanups();
      expect(tasks.map((task) => task.publishedUri).toSet(), {
        'content://media/site-mark/1',
        'content://media/site-mark/2',
      });
    },
  );

  // Regression: startup recovery for a superseded URI must retry ONLY the
  // stale-row delete — never publish again (which would create yet another
  // duplicate) — and must converge: the task is removed once the delete
  // succeeds.
  test(
    'startup cleanup retries only the superseded delete and never republishes',
    () async {
      files.existing.add('/rendered/capture-1.jpg');
      platform.nextPublishedUri = 'content://media/site-mark/2';
      platform.nextSupersededUris = ['content://media/site-mark/1'];
      await service.republish(['capture-1']);
      expect(platform.publishCount, 1);
      expect(platform.deletedUris, isEmpty);

      await service.cleanupInterrupted();

      expect(platform.publishCount, 1);
      expect(platform.deletedUris, ['content://media/site-mark/1']);
      expect(
        (await database.captureById('capture-1'))?.publishedUri,
        'content://media/site-mark/2',
      );
      expect(await database.pendingSupersededCleanups(), isEmpty);
    },
  );

  // Regression: cleanup tasks are completed independently — finishing task
  // A must never clear sibling task B (the old captureId+kind single-slot
  // marker could do exactly that).
  test('completing one superseded task keeps sibling tasks pending', () async {
    files.existing.add('/rendered/capture-1.jpg');
    platform.nextPublishedUri = 'content://media/site-mark/3';
    platform.nextSupersededUris = [
      'content://media/site-mark/1',
      'content://media/site-mark/2',
    ];
    await service.republish(['capture-1']);

    // Only the delete of URI 1 keeps failing; URI 2 deletes fine.
    platform.failingDeleteUris.add('content://media/site-mark/1');
    await service.cleanupInterrupted();

    expect(platform.deletedUris, ['content://media/site-mark/2']);
    final tasks = await database.pendingSupersededCleanups();
    expect(tasks, hasLength(1));
    expect(tasks.single.publishedUri, 'content://media/site-mark/1');

    // A later launch with a healthy gallery converges the leftover task.
    platform.failingDeleteUris.clear();
    await service.cleanupInterrupted();
    expect(platform.deletedUris, [
      'content://media/site-mark/2',
      'content://media/site-mark/1',
    ]);
    expect(await database.pendingSupersededCleanups(), isEmpty);
  });

  // Regression: a task whose URI is still referenced by the live record
  // (defensive: only reachable via a restored backup) must never delete the
  // photo the record displays.
  test(
    'startup skips a superseded task still referenced by the record',
    () async {
      await database.updatePublishedUri(
        'capture-1',
        'content://media/site-mark/1',
        expectedPreviousUri: null,
        supersededUris: ['content://media/site-mark/1'],
      );

      await service.cleanupInterrupted();

      expect(platform.deletedUris, isEmpty);
      expect(
        (await database.captureById('capture-1'))?.publishedUri,
        'content://media/site-mark/1',
      );
    },
  );

  // Read-only contract parity: completed/archived projects are protected in
  // batch paths too, not just on the detail screen. The capture is created
  // while the project is active and the project is archived afterwards —
  // createPendingCapture itself already rejects read-only projects.
  test('batch delete and clear-originals refuse read-only projects', () async {
    final pending = await database.createPendingCapture(
      id: 'capture-archived',
      projectId: 'project-1',
      originalPath: '/private/archived-original.jpg',
      workLocation: 'B 区',
      workContent: '检查',
      photographer: '张工',
      watermarkLocaleCode: 'zh',
      locationResolution: 'resolved',
    );
    await database.markCaptured(
      captureId: pending.id,
      capturedAt: DateTime(2026, 7, 16, 10),
    );
    await database.markRendering(
      captureId: pending.id,
      originalSha256: digestA,
    );
    await database.markReady(
      captureId: pending.id,
      publishedUri: 'content://media/site-mark/9',
    );
    final archived = await database.updateProjectLifecycleStatus(
      projectId: 'project-1',
      expectedStatus: ProjectLifecycleStatus.active,
      targetStatus: ProjectLifecycleStatus.archived,
    );
    expect(archived, isNotNull);

    final deleted = await service.deleteAll(['capture-archived']);
    expect(deleted.succeededIds, isEmpty);
    expect(
      deleted.failures['capture-archived'],
      CaptureMediaFailure.projectReadOnly,
    );
    expect(await database.captureById('capture-archived'), isNotNull);

    final cleared = await service.clearOriginals(['capture-archived']);
    expect(cleared.succeededIds, isEmpty);
    expect(
      cleared.failures['capture-archived'],
      CaptureMediaFailure.projectReadOnly,
    );
  });

  // Regression: while the stale-row delete keeps failing the task must
  // survive for a later launch — the action itself stays a success.
  test('superseded cleanup task survives a failing gallery delete', () async {
    files.existing.add('/rendered/capture-1.jpg');
    platform.nextPublishedUri = 'content://media/site-mark/2';
    platform.nextSupersededUris = ['content://media/site-mark/1'];
    await service.republish(['capture-1']);

    platform.deleteError = StateError('MediaStore failure');
    await service.cleanupInterrupted();

    expect(platform.publishCount, 1);
    final tasks = await database.pendingSupersededCleanups();
    expect(tasks, hasLength(1));
    expect(tasks.single.publishedUri, 'content://media/site-mark/1');
  });

  // ------------------------------------------------------------------
  // Publish-journal reconciliation (_recoverPublishJournals).
  //
  // The Android publisher journals a finalized publish right after the
  // new MediaStore row is finalized but before the caller's database
  // commit. These tests cover every branch of the startup reconciliation
  // that closes the native→Dart crash window.
  // ------------------------------------------------------------------

  // Regression (crash window): the native side finalized the new row and
  // deleted the old ones, then the process died before Dart committed
  // the new URI — the database still points at an already-deleted URI.
  // Recovery must adopt the journaled URI and queue every stale URI.
  test(
    'startup adopts a journaled publish whose database commit never happened',
    () async {
      platform.recoveredJournals.add(
        RecoveredPublishJournalEntry(
          captureId: 'capture-1',
          contentUri: 'content://media/site-mark/2',
          // The native publisher folds the CALLER'S database URI into the
          // superseded candidates, so a journal of the crashed publish must
          // list the row's current URI — plus any leftover it inherited.
          supersededUris: [
            'content://media/site-mark/1',
            'content://media/site-mark/0',
          ],
        ),
      );

      await service.cleanupInterrupted();

      final record = await database.captureById('capture-1');
      expect(record?.publishedUri, 'content://media/site-mark/2');
      // Both the journal's stale candidate AND the record's orphaned old
      // URI are queued, then deleted on this same startup pass.
      expect(platform.deletedUris.toSet(), {
        'content://media/site-mark/0',
        'content://media/site-mark/1',
      });
      expect(await database.pendingSupersededCleanups(), isEmpty);
      expect(platform.clearedJournalIds, ['capture-1']);
      // Recovery must never re-publish (that would create a duplicate).
      expect(platform.publishCount, 0);
    },
  );

  // Regression: the database commit survived the crash, so the journal
  // is stale bookkeeping — clearing it must be the ONLY effect.
  test('startup only clears a journal whose commit already survived', () async {
    platform.recoveredJournals.add(
      RecoveredPublishJournalEntry(
        captureId: 'capture-1',
        contentUri: 'content://media/site-mark/1',
        supersededUris: const [],
      ),
    );

    await service.cleanupInterrupted();

    expect(platform.clearedJournalIds, ['capture-1']);
    expect(platform.deletedUris, isEmpty);
    expect(
      (await database.captureById('capture-1'))?.publishedUri,
      'content://media/site-mark/1',
    );
    expect(await database.pendingSupersededCleanups(), isEmpty);
  });

  // Regression: a capture still being processed will be re-published by
  // the background processor (overwriting this journal entry), so the
  // recovery must KEEP the journal and touch nothing.
  test('startup keeps a journal for a capture still being processed', () async {
    final second = await database.createPendingCapture(
      id: 'capture-2',
      projectId: 'project-1',
      originalPath: '/private/original-2.jpg',
      workLocation: 'B 区',
      workContent: '桥架检查',
      photographer: '李工',
      watermarkLocaleCode: 'zh',
      locationResolution: 'resolved',
    );
    await database.markCaptured(
      captureId: second.id,
      capturedAt: DateTime(2026, 7, 16, 10),
    );
    platform.recoveredJournals.add(
      RecoveredPublishJournalEntry(
        captureId: 'capture-2',
        contentUri: 'content://media/site-mark/9',
        supersededUris: const [],
      ),
    );

    await service.cleanupInterrupted();

    expect(platform.clearedJournalIds, isEmpty);
    expect(platform.recoveredJournals, hasLength(1));
    expect(platform.deletedUris, isEmpty);
    expect(await database.pendingSupersededCleanups(), isEmpty);
    expect((await database.captureById('capture-2'))?.publishedUri, isNull);
  });

  // Regression: the record behind a journal is gone (deleted by the user
  // after the crash) — nothing will ever reference the journaled URIs, so
  // both the new and the stale URIs become delete-only cleanup work.
  test(
    'startup queues orphaned journal URIs when the record is gone',
    () async {
      await database.deleteCapture('capture-1');
      platform.recoveredJournals.add(
        RecoveredPublishJournalEntry(
          captureId: 'capture-1',
          contentUri: 'content://media/site-mark/2',
          supersededUris: ['content://media/site-mark/1'],
        ),
      );

      await service.cleanupInterrupted();

      expect(platform.deletedUris.toSet(), {
        'content://media/site-mark/1',
        'content://media/site-mark/2',
      });
      expect(await database.pendingSupersededCleanups(), isEmpty);
      expect(platform.clearedJournalIds, ['capture-1']);
    },
  );

  // Regression: a `failed` capture is terminal-without-retry — nothing
  // will ever reference the journaled URI, so it (and its stale
  // candidates) must be queued for delete-only cleanup and the journal
  // cleared.
  test(
    'startup queues a failed capture journal for delete-only cleanup',
    () async {
      final second = await database.createPendingCapture(
        id: 'capture-2',
        projectId: 'project-1',
        originalPath: '/private/original-2.jpg',
        workLocation: 'B 区',
        workContent: '桥架检查',
        photographer: '李工',
        watermarkLocaleCode: 'zh',
        locationResolution: 'resolved',
      );
      await database.markCaptured(
        captureId: second.id,
        capturedAt: DateTime(2026, 7, 16, 10),
      );
      await database.markFailed(captureId: second.id, reason: 'render failure');
      platform.recoveredJournals.add(
        RecoveredPublishJournalEntry(
          captureId: 'capture-2',
          contentUri: 'content://media/site-mark/9',
          supersededUris: ['content://media/site-mark/8'],
        ),
      );

      await service.cleanupInterrupted();

      expect(platform.clearedJournalIds, ['capture-2']);
      expect(platform.deletedUris.toSet(), {
        'content://media/site-mark/8',
        'content://media/site-mark/9',
      });
      expect(await database.pendingSupersededCleanups(), isEmpty);
    },
  );

  // ------------------------------------------------------------------
  // Duplicate photo numbers across the original and a restored project.
  //
  // A backup restore preserves photo numbers (the gallery display name),
  // so the original and the restored record can coexist with the SAME
  // number. Every publish / recovery decision below must be keyed by the
  // capture ID and the record's own publishedUri — never by the number.
  // ------------------------------------------------------------------

  Future<void> insertRestoredDuplicate() async {
    final photoNumber = (await database.captureById('capture-1'))!.photoNumber!;
    await database.createProject(id: 'project-2', name: '恢复的备份项目');
    await database.insertRestoredCapture(
      id: 'capture-2',
      projectId: 'project-2',
      photoNumber: photoNumber,
      originalPath: '/private/original-2.jpg',
      workLocation: 'B 区',
      workContent: '桥架检查',
      photographer: '李工',
      originalSha256: digestA,
      // Restored rows keep their archived timestamps, which can predate
      // the original project's row with the same number.
      createdAt: DateTime(2026, 7, 15, 8),
      capturedAt: DateTime(2026, 7, 15, 8),
    );
  }

  // Regression (cross-layer): re-saving a restored photo must supersede
  // ONLY that record's own identity — the publish call carries the
  // restored record's captureId and its (still null) publishedUri, so the
  // native side can never delete the original project's same-named
  // gallery row.
  test(
    'republish of a restored duplicate passes only its own captureId and URI',
    () async {
      await insertRestoredDuplicate();
      files.existing.add('/rendered/capture-2.jpg');
      platform.nextPublishedUri = 'content://media/site-mark/restored';

      final result = await service.republish(['capture-2']);

      expect(result.succeededIds, ['capture-2']);
      expect(result.failures, isEmpty);
      expect(platform.publishCalls, [('capture-2', null)]);
      // The original project's row is untouched — same photo number, but
      // a different capture that owns its own gallery row.
      final original = await database.captureById('capture-1');
      expect(original?.publishedUri, 'content://media/site-mark/1');
      expect(platform.deletedUris, isEmpty);
    },
  );

  // Regression (cross-layer): journal recovery must locate its row by the
  // journaled captureId. Resolving by photo number would pick the newest
  // same-numbered row (here: the ORIGINAL project's row, because the
  // restored row preserved an older archived timestamp) and write the
  // restored capture's URI into the original capture's record.
  test(
    'journal recovery reconciles by captureId even with a duplicate photo number',
    () async {
      await insertRestoredDuplicate();
      platform.recoveredJournals.add(
        RecoveredPublishJournalEntry(
          captureId: 'capture-2',
          contentUri: 'content://media/site-mark/restored',
          supersededUris: ['content://media/site-mark/stale-restored'],
        ),
      );

      await service.cleanupInterrupted();

      // ONLY the restored row adopts the journaled URI.
      final restored = await database.captureById('capture-2');
      expect(restored?.publishedUri, 'content://media/site-mark/restored');
      // The original row keeps its own URI — never hijacked.
      final original = await database.captureById('capture-1');
      expect(original?.publishedUri, 'content://media/site-mark/1');
      expect(platform.clearedJournalIds, ['capture-2']);
      // Only the journal's own stale candidate is queued and deleted; the
      // original capture's gallery row is never a candidate.
      expect(platform.deletedUris, [
        'content://media/site-mark/stale-restored',
      ]);
      expect(platform.publishCount, 0);
    },
  );

  // Regression: the journal clear after a committed republish is
  // best-effort — its failure must never turn the completed user action
  // into a failure, and the leftover journal converges on the next launch.
  test(
    'republish stays a success when the journal clear fails afterwards',
    () async {
      files.existing.add('/rendered/capture-1.jpg');
      platform.nextPublishedUri = 'content://media/site-mark/2';
      platform.clearJournalError = StateError('journal clear failed');

      final result = await service.republish(['capture-1']);

      expect(result.succeededIds, ['capture-1']);
      expect(result.failures, isEmpty);
      expect(
        (await database.captureById('capture-1'))?.publishedUri,
        'content://media/site-mark/2',
      );

      // Next launch: the stale journal is reconciled (ready row already
      // points at the journaled URI) — clear-only, no delete, no publish.
      platform.clearJournalError = null;
      platform.recoveredJournals.add(
        RecoveredPublishJournalEntry(
          captureId: 'capture-1',
          contentUri: 'content://media/site-mark/2',
          supersededUris: const [],
        ),
      );
      await service.cleanupInterrupted();

      expect(platform.clearedJournalIds, ['capture-1']);
      expect(platform.publishCount, 1);
      expect(platform.deletedUris, isEmpty);
      expect(
        (await database.captureById('capture-1'))?.publishedUri,
        'content://media/site-mark/2',
      );
    },
  );

  // ------------------------------------------------------------------
  // Legacy upgrade: two captures sharing ONE gallery URI.
  //
  // The old app overwrote gallery rows in place by file name, and a backup
  // restore preserves photo numbers — so after upgrading, the original and
  // the restored record can both reference the SAME URI. Re-publishing one
  // of them must never delete the shared photo while the other still
  // displays it.
  // ------------------------------------------------------------------

  test(
    'republish of one capture never deletes a URI another capture shares',
    () async {
      await insertRestoredDuplicate();
      // Simulate the legacy shared state: BOTH records reference URI 1.
      await database.updatePublishedUri(
        'capture-2',
        'content://media/site-mark/1',
        expectedPreviousUri: null,
      );
      files.existing.addAll([
        '/rendered/capture-1.jpg',
        '/rendered/capture-2.jpg',
      ]);

      // Re-publish capture-1: the native side reports the shared URI as a
      // superseded candidate and the queue task commits with the new URI.
      platform.nextPublishedUri = 'content://media/site-mark/2';
      platform.nextSupersededUris = ['content://media/site-mark/1'];
      final first = await service.republish(['capture-1']);
      expect(first.succeededIds, ['capture-1']);

      // The cleanup runs, but the shared URI is still referenced by
      // capture-2 — the whole-database check must keep it alive.
      await service.cleanupInterrupted();
      expect(platform.deletedUris, isEmpty);
      expect(
        (await database.pendingSupersededCleanups()).map(
          (task) => task.publishedUri,
        ),
        ['content://media/site-mark/1'],
      );
      expect(
        (await database.captureById('capture-2'))?.publishedUri,
        'content://media/site-mark/1',
      );

      // Re-publish capture-2 as well: now nothing references URI 1 anymore
      // and the deferred delete converges.
      platform.nextPublishedUri = 'content://media/site-mark/3';
      platform.nextSupersededUris = ['content://media/site-mark/1'];
      final second = await service.republish(['capture-2']);
      expect(second.succeededIds, ['capture-2']);
      await service.cleanupInterrupted();

      expect(platform.deletedUris, ['content://media/site-mark/1']);
      expect(await database.pendingSupersededCleanups(), isEmpty);
      expect(
        (await database.captureById('capture-1'))?.publishedUri,
        'content://media/site-mark/2',
      );
      expect(
        (await database.captureById('capture-2'))?.publishedUri,
        'content://media/site-mark/3',
      );
    },
  );

  // ------------------------------------------------------------------
  // Interleaving: two same-capture publishes completing in REVERSE order.
  //
  // P1 publishes U2 (native done, DB commit pending); while P1 is between
  // its native publish and its commit, P2 publishes U3 and commits FIRST.
  // P1's late commit must not roll the record back to U2: the CAS fails,
  // U2 becomes a delete-only orphan, and the conditional journal clear can
  // never destroy P2's entry.
  // ------------------------------------------------------------------

  test('a late same-capture commit never rolls back a newer publish', () async {
    files.existing.add('/rendered/capture-1.jpg');
    platform.nextPublishedUri = 'content://media/site-mark/2';
    platform.nextSupersededUris = ['content://media/site-mark/1'];
    // While P1's native publish is "in flight", P2 overtakes it: the
    // native journal is overwritten to U3 and P2's database commit lands.
    platform.onPublishStarted = (index) async {
      if (index != 1) return;
      platform.nextPublishedUri = 'content://media/site-mark/3';
      platform.nextSupersededUris = [
        'content://media/site-mark/1',
        'content://media/site-mark/2',
      ];
      platform.recoveredJournals.add(
        RecoveredPublishJournalEntry(
          captureId: 'capture-1',
          contentUri: 'content://media/site-mark/3',
          supersededUris: const [],
        ),
      );
      final overtaken = await service.republish(['capture-1']);
      expect(overtaken.succeededIds, ['capture-1']);
      // Restore P1's outcome so the OUTER publish still returns U2.
      platform.nextPublishedUri = 'content://media/site-mark/2';
      platform.nextSupersededUris = ['content://media/site-mark/1'];
    };

    final result = await service.republish(['capture-1']);

    expect(result.succeededIds, ['capture-1']);
    // The record keeps the NEWER URI — never rolled back to U2.
    expect(
      (await database.captureById('capture-1'))?.publishedUri,
      'content://media/site-mark/3',
    );
    // P1's U2 became an orphan cleanup task; U3 is not a task.
    expect(
      (await database.pendingSupersededCleanups()).map(
        (task) => task.publishedUri,
      ),
      contains('content://media/site-mark/2'),
    );
    expect(
      (await database.pendingSupersededCleanups()).map(
        (task) => task.publishedUri,
      ),
      isNot(contains('content://media/site-mark/3')),
    );
    // P2's conditional clear ran with ITS URI; P1's conditional clear
    // only ever named U2 — it could not have destroyed P2's entry.
    expect(platform.clearedJournalCalls, [
      ('capture-1', 'content://media/site-mark/3'),
      ('capture-1', 'content://media/site-mark/2'),
    ]);

    // The orphan U2 converges; the record's U3 is never deleted.
    platform.onPublishStarted = null;
    await service.cleanupInterrupted();
    expect(
      platform.deletedUris,
      isNot(contains('content://media/site-mark/3')),
    );
    expect(
      (await database.captureById('capture-1'))?.publishedUri,
      'content://media/site-mark/3',
    );
  });

  // Regression: the native publisher can fold several leftover journal
  // URIs into one outcome. If the capture disappears before the CAS commit,
  // every URI in that outcome becomes cleanup work. Keeping only the new URI
  // loses the older gallery rows forever once the journal is cleared.
  test(
    'CAS failure after deletion preserves the complete native cleanup set',
    () async {
      files.existing.add('/rendered/capture-1.jpg');
      platform.nextPublishedUri = 'content://media/site-mark/3';
      platform.nextSupersededUris = [
        'content://media/site-mark/1',
        'content://media/site-mark/2',
        'content://media/site-mark/0',
      ];
      platform.onPublishStarted = (index) async {
        if (index == 1) await database.deleteCapture('capture-1');
      };

      final result = await service.republish(['capture-1']);

      expect(result.succeededIds, ['capture-1']);
      expect(result.failures, isEmpty);
      expect(await database.captureById('capture-1'), isNull);
      expect(
        (await database.pendingSupersededCleanups())
            .map((task) => task.publishedUri)
            .toSet(),
        {
          'content://media/site-mark/0',
          'content://media/site-mark/1',
          'content://media/site-mark/2',
          'content://media/site-mark/3',
        },
      );
      expect(platform.clearedJournalCalls, [
        ('capture-1', 'content://media/site-mark/3'),
      ]);
    },
  );

  // Regression: when startup reconciliation discovers that a ready row has
  // already moved beyond an older journal, both the journal content URI and
  // all inherited superseded URIs are orphan candidates. Clearing the
  // journal after queueing only its content URI drops the inherited set.
  test(
    'superseded journal recovery preserves its complete cleanup set',
    () async {
      final moved = await database.updatePublishedUri(
        'capture-1',
        'content://media/site-mark/3',
        expectedPreviousUri: 'content://media/site-mark/1',
      );
      expect(moved, isTrue);
      platform.recoveredJournals.add(
        RecoveredPublishJournalEntry(
          captureId: 'capture-1',
          contentUri: 'content://media/site-mark/2',
          supersededUris: [
            'content://media/site-mark/1',
            'content://media/site-mark/0',
          ],
        ),
      );

      await service.cleanupInterrupted();

      expect(platform.deletedUris.toSet(), {
        'content://media/site-mark/0',
        'content://media/site-mark/1',
        'content://media/site-mark/2',
      });
      expect(
        platform.deletedUris,
        isNot(contains('content://media/site-mark/3')),
      );
      expect(await database.pendingSupersededCleanups(), isEmpty);
      expect(platform.clearedJournalCalls, [
        ('capture-1', 'content://media/site-mark/2'),
      ]);
    },
  );

  // ------------------------------------------------------------------
  // Interleaving: startup recovery racing a fresh publish.
  //
  // A crashed publish left journal U2 (native done, DB never committed).
  // While recovery is starting, the user's new publish U3 completes and
  // commits. Recovery must NOT adopt the stale U2 and must not queue U3.
  // ------------------------------------------------------------------

  test(
    'recovery does not adopt a journal overtaken by a newer commit',
    () async {
      files.existing.add('/rendered/capture-1.jpg');
      // The crashed P1: native finalized U2, journal written, DB still U1.
      platform.recoveredJournals.add(
        RecoveredPublishJournalEntry(
          captureId: 'capture-1',
          contentUri: 'content://media/site-mark/2',
          supersededUris: ['content://media/site-mark/1'],
        ),
      );
      platform.onRecoveryStarted = () async {
        // Recovery has captured its snapshot; before reconciliation runs,
        // a fresh publish U3 completes AND commits (its native journal
        // overwrote the stale one and was cleared after the commit).
        platform.recoveredJournals.clear();
        platform.recoveredJournals.add(
          RecoveredPublishJournalEntry(
            captureId: 'capture-1',
            contentUri: 'content://media/site-mark/3',
            supersededUris: const [],
          ),
        );
        platform.nextPublishedUri = 'content://media/site-mark/3';
        platform.nextSupersededUris = [
          'content://media/site-mark/1',
          'content://media/site-mark/2',
        ];
        final fresh = await service.republish(['capture-1']);
        expect(fresh.succeededIds, ['capture-1']);
      };

      await service.cleanupInterrupted();

      // The record keeps the NEWER U3 — the stale journal U2 was never
      // adopted (adopting it would have rolled the record back).
      expect(
        (await database.captureById('capture-1'))?.publishedUri,
        'content://media/site-mark/3',
      );
      // The stale journal URI became an orphan task and converged; the
      // record's U3 was never deleted.
      expect(
        platform.deletedUris,
        isNot(contains('content://media/site-mark/3')),
      );
      expect(platform.deletedUris, contains('content://media/site-mark/2'));
      expect(await database.pendingSupersededCleanups(), isEmpty);
    },
  );
}

/// Collects appended events in memory so tests can assert what the service
/// reported to the diagnostics sink without touching the file system.
class _RecordingDiagnosticStore extends DiagnosticEventStore {
  _RecordingDiagnosticStore() : super(directory: Directory('unused'));

  final events = <DiagnosticEvent>[];

  @override
  Future<void> append(DiagnosticEvent event) async => events.add(event);
}

class _MediaFiles implements PrivateFileStore {
  final Set<String> existing = {};
  final List<String> deleted = [];
  final Set<String> failures = {};

  @override
  Future<bool> exists(String path) async => existing.contains(path);

  @override
  Future<void> deleteIfExists(String path) async {
    if (failures.contains(path)) throw StateError('simulated delete failure');
    existing.remove(path);
    deleted.add(path);
  }
}

class _ThrowingMediaCleanupPendingStore
    implements CaptureMediaCleanupPendingStore {
  _ThrowingMediaCleanupPendingStore(this.error);

  final Object error;

  @override
  Future<void> write(PendingCaptureMediaCleanup pending) async => throw error;

  @override
  Future<List<PendingCaptureMediaCleanup>> list() async => const [];

  @override
  Future<void> clear(String captureId, CaptureMediaCleanupKind kind) async {}
}

class _MediaPaths implements CaptureOutputPaths {
  @override
  Future<String> renderedPhotoPath(String captureId) async =>
      '/rendered/$captureId.jpg';
}

class _MediaPlatform implements PlatformServices {
  final Map<String, ImageMetadataResult> metadataByPath = {};
  Object? deleteError;
  Object? publishError;
  Object? clearJournalError;
  String nextPublishedUri = 'content://media/site-mark/1';
  List<String> nextSupersededUris = const [];
  int publishCount = 0;
  final List<String> deletedUris = [];
  final Set<String> failingDeleteUris = {};

  /// (captureId, publishedUri) of every publish call, so tests can assert
  /// exactly WHICH capture and WHICH previous URI the service asked the
  /// native side to supersede.
  final List<(String, String?)> publishCalls = [];

  @override
  Future<ImageMetadataResult> inspectImage(String path) async =>
      metadataByPath[path]!;

  final List<RecoveredPublishJournalEntry> recoveredJournals = [];
  final List<String> clearedJournalIds = [];

  /// (captureId, expectedContentUri) of every conditional journal clear,
  /// so tests can prove an OLDER operation never cleared a NEWER entry.
  final List<(String, String)> clearedJournalCalls = [];

  /// Invoked at the START of every publishJpeg call (before the outcome is
  /// returned), letting tests interleave a concurrent same-capture publish
  /// while an older one is between its native publish and its DB commit.
  Future<void> Function(int publishIndex)? onPublishStarted;

  /// Invoked AFTER the journal snapshot for recovery has been captured,
  /// letting tests commit a concurrent publish before reconciliation runs.
  Future<void> Function()? onRecoveryStarted;

  @override
  Future<PublishJpegOutcome> publishJpeg(
    String sourcePath,
    String displayName,
    String captureId,
    String? publishedUri,
  ) async {
    if (publishError != null) throw publishError!;
    publishCount += 1;
    publishCalls.add((captureId, publishedUri));
    final hook = onPublishStarted;
    if (hook != null) await hook(publishCount);
    return PublishJpegOutcome(
      contentUri: nextPublishedUri,
      supersededUris: nextSupersededUris,
    );
  }

  @override
  Future<List<RecoveredPublishJournalEntry>> recoverPublishJournals() async {
    final journals = List.of(recoveredJournals);
    final hook = onRecoveryStarted;
    if (hook != null) await hook();
    return journals;
  }

  @override
  Future<void> clearPublishJournal(
    String captureId,
    String expectedContentUri,
  ) async {
    if (clearJournalError != null) throw clearJournalError!;
    clearedJournalCalls.add((captureId, expectedContentUri));
    for (final entry in recoveredJournals) {
      if (entry.captureId != captureId) continue;
      // Conditional clear: a newer overwritten entry must survive.
      if (entry.contentUri != expectedContentUri) return;
    }
    clearedJournalIds.add(captureId);
    recoveredJournals.removeWhere((entry) => entry.captureId == captureId);
  }

  @override
  Future<void> deletePublishedImage(String contentUri) async {
    if (deleteError != null) throw deleteError!;
    if (failingDeleteUris.contains(contentUri)) {
      throw StateError('simulated gallery delete failure');
    }
    deletedUris.add(contentUri);
  }

  @override
  Future<LocationPermissionState> getLocationPermissionState() async =>
      LocationPermissionState.denied;

  @override
  Future<LocationPermissionState> requestLocationPermission() async =>
      LocationPermissionState.denied;

  @override
  Future<void> openApplicationSettings() async {}

  @override
  Future<LocationResult> requestCurrentLocation(int timeoutMillis) async =>
      LocationResult(outcome: LocationOutcome.permissionDenied);

  @override
  Future<String> createCameraTarget(String captureId) =>
      throw UnsupportedError('camera not used');

  @override
  Future<CameraCaptureResult> launchCamera(String captureId) =>
      throw UnsupportedError('camera not used');

  @override
  Future<RecoveredCameraCapture?> recoverCameraCapture() async => null;

  @override
  Future<void> finishCameraCapture(String captureId, bool keepOriginal) async {}
}
