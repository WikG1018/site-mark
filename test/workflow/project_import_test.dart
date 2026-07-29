import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/src/rust/api/image_core.dart';
import 'package:sitemark/workflow/project_import_service.dart';

void main() {
  test('importProject restores photos with their original fields', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final images = _ImportImagePipeline(_preview());
    final files = _RecordingFileStore();
    final pendingStore = _FakePendingStore();
    final committer = _RecordingCommitter();
    final service = _service(
      database: database,
      images: images,
      files: files,
      pendingStore: pendingStore,
      committer: committer,
    );

    final result = await service.importProject(
      zipPath: '/backups/p.zip',
      projectName: '东区厂房改造',
    );

    expect(result.photoCount, 2);
    expect(result.restoredOriginals, 1);

    final project = await database.projectById(result.projectId);
    expect(project, isNotNull);
    expect(project!.watermarkPosition, 'bottomRight');
    expect(project.watermarkOpacity, 0.66);
    expect(project.watermarkAccentColorArgb, 0xff3366cc);
    expect(project.watermarkFontScale, 1.2);

    final captures = await database.capturesForProject(result.projectId);
    expect(captures.length, 2);

    final withOriginal = captures.firstWhere(
      (capture) => capture.photoNumber == '东区厂房改造-SM-20260716-001',
    );
    expect(withOriginal.status, CaptureStatus.ready);
    expect(withOriginal.publishedUri, isNull);
    expect(withOriginal.workLocation, 'A 区三层');
    expect(withOriginal.workContent, '风管安装检查');
    expect(withOriginal.photographer, '张工');
    expect(withOriginal.notes, '复验合格');
    expect(withOriginal.address, '福建省漳州市');
    expect(withOriginal.latitude, 24.513);
    expect(withOriginal.longitude, 117.6471);
    expect(withOriginal.accuracyMeters, 8.0);
    expect(withOriginal.watermarkLocaleCode, 'en');
    expect(withOriginal.locationResolution, 'resolved');
    expect(withOriginal.originalDeletedAt, isNull);
    expect(withOriginal.originalPath, '/originals/${withOriginal.id}.jpg');
    expect(withOriginal.originalSha256, 'a' * 64);
    final expectedInstant = DateTime.parse(
      '2026-07-16T09:32:18+08:00',
    ).millisecondsSinceEpoch;
    expect(withOriginal.capturedAt!.millisecondsSinceEpoch, expectedInstant);
    expect(withOriginal.createdAt.millisecondsSinceEpoch, expectedInstant);

    final withoutOriginal = captures.firstWhere(
      (capture) => capture.photoNumber == '东区厂房改造-SM-20260716-002',
    );
    expect(withoutOriginal.originalDeletedAt, isNotNull);
    expect(withoutOriginal.locationResolution, 'unavailable');
    expect(withoutOriginal.watermarkLocaleCode, 'zh');

    // Extraction targeted the staging area; commit moved files into place.
    expect(images.extractRequests.length, 2);
    expect(
      images.extractRequests[0].renderedDestination,
      '/staging/rendered/${withOriginal.id}.jpg',
    );
    expect(
      images.extractRequests[0].originalDestination,
      '/staging/originals/${withOriginal.id}.jpg',
    );
    expect(images.extractRequests[1].originalDestination, isNull);
    expect(committer.moves, [
      '/staging/rendered/${withOriginal.id}.jpg'
          ' -> /rendered/${withOriginal.id}.jpg',
      '/staging/originals/${withOriginal.id}.jpg'
          ' -> /originals/${withOriginal.id}.jpg',
      '/staging/rendered/${withoutOriginal.id}.jpg'
          ' -> /rendered/${withoutOriginal.id}.jpg',
    ]);

    // planned -> ownsProject -> committing, then cleared after token release.
    expect(pendingStore.writes, 3);
    expect(pendingStore.cleared, [result.projectId]);
    expect(committer.deletedTrees, ['/staging/${result.projectId}']);
  });

  test('importProject uses a caller-specified target project id', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final service = _service(
      database: database,
      images: _ImportImagePipeline(_preview()),
      files: _RecordingFileStore(),
    );

    final result = await service.importProject(
      zipPath: '/backups/p.zip',
      projectName: '东区厂房改造',
      projectId: 'preallocated-project-id',
    );

    expect(result.projectId, 'preallocated-project-id');
    expect(await database.projectById('preallocated-project-id'), isNotNull);
  });

  test('existing caller-specified target id is never deleted', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'existing-id', name: '保留项目');
    final files = _RecordingFileStore();
    final images = _ImportImagePipeline(_preview());
    final service = _service(database: database, images: images, files: files);

    await expectLater(
      service.importProject(
        zipPath: '/backups/p.zip',
        projectName: '新项目',
        projectId: 'existing-id',
      ),
      throwsA(isA<StateError>()),
    );

    expect((await database.projectById('existing-id'))?.name, '保留项目');
    expect(images.extractRequests, isEmpty);
    expect(files.attemptedDeletes, isEmpty);
  });

  test('double-submit cannot delete the first successful restore', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final files = _RecordingFileStore();
    final images = _ImportImagePipeline(_preview());
    final service = _service(database: database, images: images, files: files);

    await service.importProject(
      zipPath: '/backups/p.zip',
      projectName: '第一次恢复',
      projectId: 'shared-target-id',
    );
    await expectLater(
      service.importProject(
        zipPath: '/backups/p.zip',
        projectName: '第二次恢复',
        projectId: 'shared-target-id',
      ),
      throwsA(isA<StateError>()),
    );

    expect((await database.projectById('shared-target-id'))?.name, '第一次恢复');
    expect(await database.capturesForProject('shared-target-id'), hasLength(2));
    expect(files.attemptedDeletes, isEmpty);
  });

  test('concurrent imports cannot claim the same target id', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final service = _service(
      database: database,
      images: _ImportImagePipeline(_preview()),
      files: _RecordingFileStore(),
    );

    final first = service.importProject(
      zipPath: '/backups/p.zip',
      projectName: '第一次恢复',
      projectId: 'concurrent-target-id',
    );
    final secondExpectation = expectLater(
      service.importProject(
        zipPath: '/backups/p.zip',
        projectName: '第二次恢复',
        projectId: 'concurrent-target-id',
      ),
      throwsA(isA<StateError>()),
    );

    await first;
    await secondExpectation;
    expect((await database.projectById('concurrent-target-id'))?.name, '第一次恢复');
  });

  test('importProject rolls everything back when extraction fails', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final images = _ImportImagePipeline(_preview(), failAtIndex: 1);
    final files = _RecordingFileStore();
    final pendingStore = _FakePendingStore();
    final service = _service(
      database: database,
      images: images,
      files: files,
      pendingStore: pendingStore,
    );

    await expectLater(
      service.importProject(zipPath: '/backups/p.zip', projectName: '东区厂房改造'),
      throwsA(isA<ImagePipelineException>()),
    );

    expect(await database.getProjects(), isEmpty);
    expect(await database.getAllCaptures(), isEmpty);
    // Both staged and final paths of every photo were deleted best-effort.
    expect(files.deleted.length, 8);
    // A fully cleaned pre-create failure clears its non-owning marker.
    expect(pendingStore.writes, 1);
    expect(pendingStore.cleared, hasLength(1));
    expect(pendingStore.pending, isEmpty);
  });

  test('rollback stays best-effort when a delete throws', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final images = _ImportImagePipeline(_preview(), failAtIndex: 1);
    final files = _RecordingFileStore(throwOnDeleteAt: 0);
    final pendingStore = _FakePendingStore();
    final service = _service(
      database: database,
      images: images,
      files: files,
      pendingStore: pendingStore,
    );

    await expectLater(
      service.importProject(zipPath: '/backups/p.zip', projectName: '东区厂房改造'),
      throwsA(isA<ImagePipelineException>()),
    );

    // The first delete threw, yet every later file was still attempted.
    expect(files.attemptedDeletes.length, 8);
    expect(files.deleted.length, 7);
    // The database cleanup ran despite the file failure.
    expect(await database.getProjects(), isEmpty);
  });

  test(
    'corrupt timestamps reject the archive before any work happens',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final broken = ProjectArchivePreview(
        schemaVersion: 2,
        projectName: '东区厂房改造',
        includesOriginals: false,
        photos: [
          ArchivePhotoPreview(
            photoNumber: '东区厂房改造-SM-20260716-001',
            hasOriginal: false,
            originalSha256: 'a' * 64,
            capturedAt: 'garbage-timestamp',
            workLocation: 'A 区三层',
            workContent: '风管安装检查',
            photographer: '张工',
          ),
        ],
      );
      final images = _ImportImagePipeline(broken);
      final service = _service(
        database: database,
        images: images,
        files: _RecordingFileStore(),
      );

      await expectLater(
        service.importProject(zipPath: '/backups/p.zip', projectName: '东区厂房改造'),
        throwsA(isA<InvalidArchiveException>()),
      );
      // Nothing was extracted, staged, or persisted.
      expect(images.extractRequests, isEmpty);
      expect(await database.getProjects(), isEmpty);
    },
  );

  test(
    'cleanupInterruptedImports removes leftovers of a killed import',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final files = _RecordingFileStore();
      final pendingStore = _FakePendingStore();
      final committer = _RecordingCommitter();
      final service = _service(
        database: database,
        images: _ImportImagePipeline(_preview()),
        files: files,
        pendingStore: pendingStore,
        committer: committer,
      );
      // Simulate an interrupted import: a project row, a staging tree, and a
      // pending marker all left behind.
      await database.createProject(
        id: 'dead-project',
        name: '烂尾项目',
        restoreOperationId: 'restore-dead-project',
      );
      pendingStore.pending.add(
        const PendingImport(
          projectId: 'dead-project',
          stagingDirectory: '/staging/dead-project',
          stagedFiles: ['/staging/dead-project/rendered/a.jpg'],
          finalFiles: ['/rendered/a.jpg'],
          phase: PendingImportPhase.ownsProject,
          operationId: 'restore-dead-project',
        ),
      );

      await service.cleanupInterruptedImports();

      expect(await database.getProjects(), isEmpty);
      expect(
        files.deleted,
        containsAll([
          '/staging/dead-project/rendered/a.jpg',
          '/rendered/a.jpg',
        ]),
      );
      expect(committer.deletedTrees, ['/staging/dead-project']);
      expect(pendingStore.pending, isEmpty);
    },
  );

  test(
    'cleanupInterruptedImports keeps the marker when cleanup is incomplete',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final files = _RecordingFileStore(throwOnDeleteAt: 0);
      final pendingStore = _FakePendingStore();
      final service = _service(
        database: database,
        images: _ImportImagePipeline(_preview()),
        files: files,
        pendingStore: pendingStore,
      );
      pendingStore.pending.add(
        const PendingImport(
          projectId: 'dead-project',
          stagingDirectory: '/staging/dead-project',
          stagedFiles: ['/staging/dead-project/rendered/a.jpg'],
          finalFiles: ['/rendered/a.jpg'],
        ),
      );

      await service.cleanupInterruptedImports();

      expect(files.attemptedDeletes.length, 2);
      expect(pendingStore.cleared, isEmpty);
      expect(pendingStore.pending, hasLength(1));
    },
  );

  test('pending import JSON is backward-compatible and safely non-owning', () {
    final legacy = PendingImport.fromJson(const {
      'projectId': 'legacy-id',
      'stagingDirectory': '/staging/legacy-id',
      'stagedFiles': <String>[],
      'finalFiles': <String>[],
    });
    expect(legacy.phase, PendingImportPhase.planned);

    const owning = PendingImport(
      projectId: 'owned-id',
      stagingDirectory: '/staging/owned-id',
      stagedFiles: [],
      finalFiles: [],
      phase: PendingImportPhase.ownsProject,
    );
    expect(
      PendingImport.fromJson(owning.toJson()).phase,
      PendingImportPhase.ownsProject,
    );
    const committing = PendingImport(
      projectId: 'committing-id',
      stagingDirectory: '/staging/committing-id',
      stagedFiles: [],
      finalFiles: [],
      phase: PendingImportPhase.committing,
      operationId: 'commit-operation',
    );
    expect(
      PendingImport.fromJson(committing.toJson()).phase,
      PendingImportPhase.committing,
    );
  });

  test('non-owning startup marker preserves a raced project', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'raced-id', name: '其他恢复创建的项目');
    final files = _RecordingFileStore();
    final committer = _RecordingCommitter();
    final pendingStore = _FakePendingStore()
      ..pending.add(
        const PendingImport(
          projectId: 'raced-id',
          stagingDirectory: '/staging/raced-id',
          stagedFiles: ['/staging/raced-id/photo.jpg'],
          finalFiles: ['/rendered/raced-id.jpg'],
        ),
      );
    final service = _service(
      database: database,
      images: _ImportImagePipeline(_preview()),
      files: files,
      pendingStore: pendingStore,
      committer: committer,
    );

    await service.cleanupInterruptedImports();

    expect(await database.projectById('raced-id'), isNotNull);
    expect(files.attemptedDeletes, isEmpty);
    expect(committer.deletedTrees, isEmpty);
    expect(pendingStore.pending, hasLength(1));
  });

  test(
    'planned marker with matching database token deletes interrupted restore',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.createProject(
        id: 'planned-owned',
        name: '中断恢复',
        restoreOperationId: 'operation-owned',
      );
      final pendingStore = _FakePendingStore()
        ..pending.add(
          const PendingImport(
            projectId: 'planned-owned',
            stagingDirectory: '/staging/planned-owned',
            stagedFiles: [],
            finalFiles: [],
            operationId: 'operation-owned',
          ),
        );
      final service = _service(
        database: database,
        images: _ImportImagePipeline(_preview()),
        files: _RecordingFileStore(),
        pendingStore: pendingStore,
      );

      await service.cleanupInterruptedImports();

      expect(await database.projectById('planned-owned'), isNull);
      expect(pendingStore.pending, isEmpty);
    },
  );

  test('mismatching database token never authorizes cleanup', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(
      id: 'mismatch',
      name: '其他恢复',
      restoreOperationId: 'different-operation',
    );
    final pendingStore = _FakePendingStore()
      ..pending.add(
        const PendingImport(
          projectId: 'mismatch',
          stagingDirectory: '/staging/mismatch',
          stagedFiles: ['/staging/mismatch/a.jpg'],
          finalFiles: ['/rendered/a.jpg'],
          operationId: 'marker-operation',
        ),
      );
    final files = _RecordingFileStore();
    final service = _service(
      database: database,
      images: _ImportImagePipeline(_preview()),
      files: files,
      pendingStore: pendingStore,
    );

    await service.cleanupInterruptedImports();

    expect(await database.projectById('mismatch'), isNotNull);
    expect(files.attemptedDeletes, isEmpty);
    expect(pendingStore.pending, hasLength(1));
  });

  test(
    'immutable marker generations survive a failed rewrite without corrupting the last state',
    () async {
      final root = await Directory.systemTemp.createTemp('sitemark-marker-');
      addTearDown(() => root.delete(recursive: true));
      final store = AppImportPendingStore(documentsDirectory: () async => root);
      const planned = PendingImport(
        projectId: 'atomic-project',
        stagingDirectory: '/staging/atomic-project',
        stagedFiles: [],
        finalFiles: [],
        operationId: 'atomic-operation',
      );
      await store.writePending(planned);

      final failedStore = AppImportPendingStore(
        documentsDirectory: () async => root,
        writer: _FailBeforeCommitMarkerWriter(),
      );
      await expectLater(
        failedStore.writePending(
          planned.withPhase(PendingImportPhase.ownsProject),
        ),
        throwsStateError,
      );

      var listed = await store.listPending();
      expect(listed, hasLength(1));
      expect(listed.single.phase, PendingImportPhase.planned);
      expect(listed.single.operationId, 'atomic-operation');

      final owned = planned.withPhase(PendingImportPhase.ownsProject);
      await store.writePending(owned);
      listed = await store.listPending();
      expect(listed, hasLength(1));
      expect(listed.single.phase, PendingImportPhase.ownsProject);
      expect(listed.single.revision, 1);
    },
  );

  test(
    'successful import ignores a staging-directory cleanup failure',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final pendingStore = _FakePendingStore();
      final committer = _RecordingCommitter(throwOnDeleteTree: true);
      final service = _service(
        database: database,
        images: _ImportImagePipeline(_preview()),
        files: _RecordingFileStore(),
        pendingStore: pendingStore,
        committer: committer,
      );

      final result = await service.importProject(
        zipPath: '/backups/p.zip',
        projectName: '东区厂房改造',
      );

      expect(await database.projectById(result.projectId), isNotNull);
      expect(pendingStore.cleared, [result.projectId]);
      expect(pendingStore.pending, isEmpty);
      expect(committer.deleteTreeAttempts, 1);
    },
  );

  test(
    'committing marker survives token clear failure and startup finalizes without rollback',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.customStatement('''
        CREATE TRIGGER fail_import_token_clear
        BEFORE UPDATE OF restore_operation_id ON projects
        WHEN NEW.restore_operation_id IS NULL
        BEGIN
          SELECT RAISE(ABORT, 'simulated token clear failure');
        END;
      ''');
      final files = _RecordingFileStore();
      final pendingStore = _FakePendingStore();
      final service = _service(
        database: database,
        images: _ImportImagePipeline(_preview()),
        files: files,
        pendingStore: pendingStore,
      );

      await expectLater(
        service.importProject(zipPath: '/backups/p.zip', projectName: '待完成恢复'),
        throwsA(
          isA<ProjectImportFinalizationPendingException>().having(
            (error) => error.projectId,
            'projectId',
            isNotEmpty,
          ),
        ),
      );

      expect(await database.getProjects(), isEmpty);
      expect(await database.getAllProjectsInternal(), hasLength(1));
      expect(pendingStore.pending.single.phase, PendingImportPhase.committing);
      expect(files.attemptedDeletes, isEmpty);

      await database.customStatement('DROP TRIGGER fail_import_token_clear');
      await service.cleanupInterruptedImports();

      expect((await database.getProjects()).single.name, '待完成恢复');
      expect(pendingStore.pending, isEmpty);
      expect(files.attemptedDeletes, isEmpty);
    },
  );

  test(
    'committing marker retries clear after token is already visible',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final files = _RecordingFileStore();
      final pendingStore = _FakePendingStore()..throwOnClear = true;
      final service = _service(
        database: database,
        images: _ImportImagePipeline(_preview()),
        files: files,
        pendingStore: pendingStore,
      );

      await expectLater(
        service.importProject(zipPath: '/backups/p.zip', projectName: '已恢复项目'),
        throwsA(anything),
      );

      expect((await database.getProjects()).single.name, '已恢复项目');
      expect(pendingStore.pending.single.phase, PendingImportPhase.committing);
      expect(files.attemptedDeletes, isEmpty);

      pendingStore.throwOnClear = false;
      await service.cleanupInterruptedImports();

      expect((await database.getProjects()).single.name, '已恢复项目');
      expect(pendingStore.pending, isEmpty);
      expect(files.attemptedDeletes, isEmpty);
    },
  );

  test('v1-style archives restore with default watermark settings', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final preview = ProjectArchivePreview(
      schemaVersion: 1,
      projectName: '旧项目',
      includesOriginals: false,
      photos: [
        ArchivePhotoPreview(
          photoNumber: '旧项目-SM-20240101-001',
          hasOriginal: false,
          originalSha256: 'b' * 64,
          capturedAt: '2024-01-01 08:00:00 +08:00',
          workLocation: 'B 区',
          workContent: '管道试压',
          photographer: '李工',
        ),
      ],
    );
    final service = _service(
      database: database,
      images: _ImportImagePipeline(preview),
      files: _RecordingFileStore(),
    );

    final result = await service.importProject(
      zipPath: '/backups/old.zip',
      projectName: '旧项目',
    );

    final project = await database.projectById(result.projectId);
    expect(project!.watermarkPosition, 'bottomLeft');
    expect(project.watermarkOpacity, 0.78);
    expect(project.watermarkAccentColorArgb, 0xff37c58b);
    expect(project.watermarkFontScale, 1.0);
    final capture = (await database.capturesForProject(
      result.projectId,
    )).single;
    expect(capture.watermarkLocaleCode, 'zh');
    expect(capture.latitude, isNull);
    expect(capture.originalDeletedAt, isNotNull);
  });

  test('suggestAvailableName appends an import suffix until free', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final service = _service(
      database: database,
      images: _ImportImagePipeline(_preview()),
      files: _RecordingFileStore(),
    );

    expect(await service.suggestAvailableName('新项目'), '新项目');

    await database.createProject(id: 'p1', name: '东区厂房改造');
    expect(await service.suggestAvailableName('东区厂房改造'), '东区厂房改造（导入）');

    await database.createProject(
      id: 'p2',
      name: '东区厂房改造（导入）',
      restoreOperationId: 'hidden-restore',
    );
    expect(await service.suggestAvailableName('东区厂房改造'), '东区厂房改造（导入 2）');
  });

  test('parseExportedTimestamp honors the recorded offset', () {
    final parsed = parseExportedTimestamp('2026-07-16 09:32:18 +08:00');
    expect(parsed, isNotNull);
    expect(
      parsed!.millisecondsSinceEpoch,
      DateTime.parse('2026-07-16T09:32:18+08:00').millisecondsSinceEpoch,
    );
    expect(parseExportedTimestamp('2026-07-16 09:32:18'), isNull);
    expect(parseExportedTimestamp('not a timestamp'), isNull);
    expect(parseExportedTimestamp(''), isNull);
  });
}

ProjectImportService _service({
  required AppDatabase database,
  required _ImportImagePipeline images,
  required _RecordingFileStore files,
  _FakePendingStore? pendingStore,
  _RecordingCommitter? committer,
}) {
  return ProjectImportService(
    database: database,
    images: images,
    capturePaths: _ImportCapturePaths(),
    originalPaths: _ImportOriginalPaths(),
    fileStore: files,
    stagingPaths: const _FakeStagingPaths(),
    pendingStore: pendingStore ?? _FakePendingStore(),
    committer: committer ?? _RecordingCommitter(),
    clock: () => DateTime(2026, 7, 27, 12),
  );
}

ProjectArchivePreview _preview() {
  return ProjectArchivePreview(
    schemaVersion: 2,
    projectName: '东区厂房改造',
    includesOriginals: true,
    watermark: const ArchiveWatermarkSettings(
      position: 'bottomRight',
      opacity: 0.66,
      accentColorArgb: 0xff3366cc,
      fontScale: 1.2,
    ),
    photos: [
      ArchivePhotoPreview(
        photoNumber: '东区厂房改造-SM-20260716-001',
        hasOriginal: true,
        originalSha256: 'A' * 64,
        capturedAt: '2026-07-16 09:32:18 +08:00',
        workLocation: 'A 区三层',
        workContent: '风管安装检查',
        photographer: '张工',
        address: '福建省漳州市',
        notes: '复验合格',
        latitude: 24.513,
        longitude: 117.6471,
        accuracyMeters: 8.0,
        watermarkLocaleCode: 'en',
      ),
      ArchivePhotoPreview(
        photoNumber: '东区厂房改造-SM-20260716-002',
        hasOriginal: false,
        originalSha256: 'b' * 64,
        capturedAt: '2026-07-16 10:11:42 +08:00',
        workLocation: 'A 区四层',
        workContent: '风口复核',
        photographer: '张工',
      ),
    ],
  );
}

class _ImportImagePipeline implements ImagePipeline {
  _ImportImagePipeline(this.preview, {this.failAtIndex});

  final ProjectArchivePreview preview;
  final int? failAtIndex;
  final extractRequests = <ExtractArchivePhotoRequest>[];

  @override
  Future<ProjectArchivePreview> readProjectArchive(String zipPath) async =>
      preview;

  @override
  Future<ExtractedArchivePhoto> extractArchivePhoto(
    ExtractArchivePhotoRequest request,
  ) async {
    final index = extractRequests.length;
    extractRequests.add(request);
    if (failAtIndex == index) {
      throw const ImagePipelineException(
        ImagePipelineFailureKind.invalidData,
        'SHA-256 mismatch',
      );
    }
    return ExtractedArchivePhoto(
      renderedPath: request.renderedDestination,
      originalPath: request.originalDestination,
    );
  }

  @override
  Future<ExportProjectResult> export(ExportProjectRequest request) =>
      throw UnimplementedError();

  @override
  Future<ExportProjectResult> exportSelection(ExportSelectionRequest request) =>
      throw UnimplementedError();

  @override
  Future<RenderPhotoResult> render(RenderPhotoRequest request) =>
      throw UnimplementedError();

  @override
  Future<String> sha256(String path) => throw UnimplementedError();
}

class _ImportCapturePaths implements CaptureOutputPaths {
  @override
  Future<String> renderedPhotoPath(String captureId) async =>
      '/rendered/$captureId.jpg';
}

class _ImportOriginalPaths implements OriginalPhotoPaths {
  @override
  Future<String> originalPhotoPath(String captureId) async =>
      '/originals/$captureId.jpg';
}

class _FakeStagingPaths implements ImportStagingPaths {
  const _FakeStagingPaths();

  @override
  Future<String> stagingDirectory(String projectId) async =>
      '/staging/$projectId';

  @override
  Future<String> stagedRenderedPath(String projectId, String captureId) async =>
      '/staging/rendered/$captureId.jpg';

  @override
  Future<String> stagedOriginalPath(String projectId, String captureId) async =>
      '/staging/originals/$captureId.jpg';
}

class _FakePendingStore implements ImportPendingStore {
  final pending = <PendingImport>[];
  final cleared = <String>[];
  var writes = 0;
  bool throwOnClear = false;

  @override
  Future<void> writePending(PendingImport pending) async {
    writes++;
    this.pending.removeWhere((entry) => entry.projectId == pending.projectId);
    this.pending.add(pending);
  }

  @override
  Future<List<PendingImport>> listPending() async => List.of(pending);

  @override
  Future<void> clearPending(String projectId) async {
    if (throwOnClear) throw StateError('marker clear failed');
    cleared.add(projectId);
    pending.removeWhere((entry) => entry.projectId == projectId);
  }
}

class _RecordingCommitter implements ImportFileCommitter {
  _RecordingCommitter({this.throwOnDeleteTree = false});

  final bool throwOnDeleteTree;
  final moves = <String>[];
  final deletedTrees = <String>[];
  var deleteTreeAttempts = 0;

  @override
  Future<void> moveIntoPlace(String stagedPath, String finalPath) async {
    moves.add('$stagedPath -> $finalPath');
  }

  @override
  Future<void> deleteTree(String path) async {
    deleteTreeAttempts++;
    if (throwOnDeleteTree) {
      throw StateError('simulated staging cleanup failure');
    }
    deletedTrees.add(path);
  }
}

class _RecordingFileStore implements PrivateFileStore {
  _RecordingFileStore({this.throwOnDeleteAt});

  final int? throwOnDeleteAt;
  final attemptedDeletes = <String>[];
  final deleted = <String>[];

  @override
  Future<bool> exists(String path) async => true;

  @override
  Future<void> deleteIfExists(String path) async {
    if (throwOnDeleteAt == attemptedDeletes.length) {
      attemptedDeletes.add(path);
      throw StateError('simulated delete failure');
    }
    attemptedDeletes.add(path);
    deleted.add(path);
  }
}

class _FailBeforeCommitMarkerWriter implements AtomicMarkerWriter {
  @override
  Future<void> write(File target, String contents) async {
    await File('${target.path}.tmp-power-loss').writeAsString('{', flush: true);
    throw StateError('simulated power loss before atomic rename');
  }
}
