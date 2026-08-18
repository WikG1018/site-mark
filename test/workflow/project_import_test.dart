import 'dart:io';

import 'package:drift/drift.dart'
    show ApplyInterceptor, QueryExecutor, QueryInterceptor;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/domain/project_lifecycle.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/src/rust/api/image_core.dart';
import 'package:sitemark/workflow/project_import_service.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('v4 restore normalizes lifecycle to active and unpinned', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final service = _service(
      database: database,
      images: _ImportImagePipeline(
        ProjectArchivePreview(
          schemaVersion: 4,
          projectName: '旧备份',
          omittedProcessingCount: 0,
          omittedFailedCount: 0,
          isPartial: false,
          includesOriginals: false,
          projectLifecycleStatus: 'archived',
          projectIsPinned: true,
          photos: const [],
          templates: const [],
        ),
      ),
      files: _RecordingFileStore(),
    );

    final result = await service.importProject(
      zipPath: '/backups/v4.zip',
      projectName: '旧备份',
    );

    expect(result.lifecycleStatus, ProjectLifecycleStatus.active);
    expect(result.isPinned, isFalse);
    final project = await database.projectById(result.projectId);
    expect(project!.lifecycleStatus, ProjectLifecycleStatus.active);
    expect(project.isPinned, isFalse);
  });

  test('v5 restore preserves lifecycle status and pin flag', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final service = _service(
      database: database,
      images: _ImportImagePipeline(
        ProjectArchivePreview(
          schemaVersion: 5,
          projectName: '归档备份',
          omittedProcessingCount: 0,
          omittedFailedCount: 0,
          isPartial: false,
          includesOriginals: false,
          projectLifecycleStatus: 'archived',
          projectIsPinned: true,
          photos: const [],
          templates: const [],
        ),
      ),
      files: _RecordingFileStore(),
    );

    final result = await service.importProject(
      zipPath: '/backups/v5.zip',
      projectName: '归档备份',
    );

    expect(result.lifecycleStatus, ProjectLifecycleStatus.archived);
    expect(result.isPinned, isTrue);
    final project = await database.projectById(result.projectId);
    expect(project!.lifecycleStatus, ProjectLifecycleStatus.archived);
    expect(project.isPinned, isTrue);
  });

  test('v5 rejects illegal lifecycle status in Dart validation', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final service = _service(
      database: database,
      images: _ImportImagePipeline(
        ProjectArchivePreview(
          schemaVersion: 5,
          projectName: '非法状态',
          omittedProcessingCount: 0,
          omittedFailedCount: 0,
          isPartial: false,
          includesOriginals: false,
          projectLifecycleStatus: 'deleted',
          projectIsPinned: false,
          photos: const [],
          templates: const [],
        ),
      ),
      files: _RecordingFileStore(),
    );

    await expectLater(
      service.importProject(zipPath: '/backups/bad.zip', projectName: '非法状态'),
      throwsA(isA<InvalidArchiveException>()),
    );
    expect(await database.getAllProjectsInternal(), isEmpty);
  });

  test('v4 restore inserts templates with new UUIDs and exact values', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final service = _service(
      database: database,
      images: _ImportImagePipeline(
        _previewWithTemplates([
          _archiveTemplate(
            name: '早班',
            workLocation: 'A 区',
            workContent: '风管检查',
            photographer: '张工',
            createdAt: '2026-07-15 08:00:00 +08:00',
            updatedAt: '2026-07-15 09:00:00 +08:00',
          ),
          _archiveTemplate(
            name: '晚班',
            workLocation: 'B 区',
            workContent: '水压复核',
            photographer: '李工',
            createdAt: '2026-07-16 08:30:00 +08:00',
            updatedAt: '2026-07-16 10:45:00 +08:00',
          ),
        ]),
      ),
      files: _RecordingFileStore(),
    );

    final result = await service.importProject(
      zipPath: '/backups/templates.zip',
      projectName: '模板项目',
    );

    final templates = await database.captureTemplatesForProject(
      result.projectId,
    );
    expect(templates, hasLength(2));
    expect(
      templates.map((template) => template.id),
      everyElement(
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      ),
    );
    expect(templates.map((template) => template.id).toSet(), hasLength(2));
    expect(
      templates
          .map(
            (template) => [
              template.name,
              template.nameKey,
              template.workLocation,
              template.workContent,
              template.photographer,
            ],
          )
          .toList(),
      const [
        ['晚班', '晚班', 'B 区', '水压复核', '李工'],
        ['早班', '早班', 'A 区', '风管检查', '张工'],
      ],
    );
    expect(
      templates[0].createdAt.millisecondsSinceEpoch,
      DateTime.parse('2026-07-16T08:30:00+08:00').millisecondsSinceEpoch,
    );
    expect(
      templates[0].updatedAt.millisecondsSinceEpoch,
      DateTime.parse('2026-07-16T10:45:00+08:00').millisecondsSinceEpoch,
    );
  });

  final invalidTemplateCases =
      <
        ({
          String label,
          List<ArchiveCaptureTemplate> templates,
          int schemaVersion,
        })
      >[
        (
          label: 'more than 100 templates',
          templates: List.generate(
            101,
            (index) => _archiveTemplate(name: 'Template $index'),
          ),
          schemaVersion: 4,
        ),
        (
          label: 'a name not normalized by the Rust preview',
          templates: [_archiveTemplate(name: '  Night\t Shift  ')],
          schemaVersion: 4,
        ),
        (
          label: 'a field not trimmed by the Rust preview',
          templates: [_archiveTemplate(name: 'Night', workLocation: ' A 区 ')],
          schemaVersion: 4,
        ),
        (
          label: 'duplicate ASCII-insensitive names',
          templates: [
            _archiveTemplate(name: 'ABC'),
            _archiveTemplate(name: 'abc'),
          ],
          schemaVersion: 4,
        ),
        (
          label: 'an empty name',
          templates: [_archiveTemplate(name: '')],
          schemaVersion: 4,
        ),
        (
          label: 'an empty work location',
          templates: [_archiveTemplate(name: 'Night', workLocation: '')],
          schemaVersion: 4,
        ),
        (
          label: 'an empty work content',
          templates: [_archiveTemplate(name: 'Night', workContent: '')],
          schemaVersion: 4,
        ),
        (
          label: 'an empty photographer',
          templates: [_archiveTemplate(name: 'Night', photographer: '')],
          schemaVersion: 4,
        ),
        (
          label: 'an overlong name by Unicode scalar count',
          templates: [_archiveTemplate(name: '😀' * 81)],
          schemaVersion: 4,
        ),
        (
          label: 'an overlong work location by Unicode scalar count',
          templates: [
            _archiveTemplate(name: 'Night', workLocation: '😀' * 161),
          ],
          schemaVersion: 4,
        ),
        (
          label: 'an overlong work content by Unicode scalar count',
          templates: [_archiveTemplate(name: 'Night', workContent: '😀' * 241)],
          schemaVersion: 4,
        ),
        (
          label: 'an overlong photographer by Unicode scalar count',
          templates: [_archiveTemplate(name: 'Night', photographer: '😀' * 81)],
          schemaVersion: 4,
        ),
        for (final field in [
          'name',
          'work location',
          'work content',
          'photographer',
        ])
          (
            label: 'U+0000 in $field',
            templates: [
              _archiveTemplate(
                name: field == 'name' ? 'Night\u0000' : 'Night',
                workLocation: field == 'work location' ? 'A\u0000' : 'A 区',
                workContent: field == 'work content' ? '检查\u0000' : '风管检查',
                photographer: field == 'photographer' ? '张\u0000' : '张工',
              ),
            ],
            schemaVersion: 4,
          ),
        (
          label: 'an invalid created timestamp',
          templates: [
            _archiveTemplate(name: 'Night', createdAt: 'not-a-timestamp'),
          ],
          schemaVersion: 4,
        ),
        (
          label: 'an invalid calendar date in the updated timestamp',
          templates: [
            _archiveTemplate(
              name: 'Night',
              updatedAt: '2026-02-29 09:00:00 +08:00',
            ),
          ],
          schemaVersion: 4,
        ),
        (
          label: 'templates attached to a legacy preview',
          templates: [_archiveTemplate(name: 'Night')],
          schemaVersion: 3,
        ),
        (
          label: 'a preview newer than schema v5',
          templates: const [],
          schemaVersion: 6,
        ),
      ];
  for (final invalid in invalidTemplateCases) {
    test('rejects ${invalid.label} before creating a project', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final images = _ImportImagePipeline(
        _previewWithTemplates(
          invalid.templates,
          schemaVersion: invalid.schemaVersion,
        ),
      );
      final pendingStore = _FakePendingStore();
      final service = _service(
        database: database,
        images: images,
        files: _RecordingFileStore(),
        pendingStore: pendingStore,
      );

      await expectLater(
        service.importProject(
          zipPath: '/backups/invalid-template.zip',
          projectName: '损坏模板项目',
        ),
        throwsA(isA<InvalidArchiveException>()),
      );

      expect(await database.getAllProjectsInternal(), isEmpty);
      expect(await database.select(database.captureTemplates).get(), isEmpty);
      expect(images.extractRequests, isEmpty);
      expect(pendingStore.writes, 0);
    });
  }

  final archiveCompatibilityMatrix =
      <
        ({
          String label,
          int schemaVersion,
          List<ArchivePhotoPreview> photos,
          List<ArchiveCaptureTemplate> templates,
        })
      >[
        (
          label: 'v1 photos without templates',
          schemaVersion: 1,
          photos: _preview().photos,
          templates: const [],
        ),
        (
          label: 'v2 photos without templates',
          schemaVersion: 2,
          photos: _preview().photos,
          templates: const [],
        ),
        (
          label: 'v3 empty archive',
          schemaVersion: 3,
          photos: const [],
          templates: const [],
        ),
        (
          label: 'v4 empty archive',
          schemaVersion: 4,
          photos: const [],
          templates: const [],
        ),
        (
          label: 'v4 photos without templates',
          schemaVersion: 4,
          photos: _preview().photos,
          templates: const [],
        ),
        (
          label: 'v4 templates without photos',
          schemaVersion: 4,
          photos: const [],
          templates: [_archiveTemplate(name: '模板单独恢复')],
        ),
        (
          label: 'v4 photos with templates',
          schemaVersion: 4,
          photos: _preview().photos,
          templates: [_archiveTemplate(name: '照片模板共同恢复')],
        ),
      ];
  for (final archiveCase in archiveCompatibilityMatrix) {
    test('archive compatibility matrix: ${archiveCase.label}', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final images = _ImportImagePipeline(
        _previewWithTemplates(
          archiveCase.templates,
          photos: archiveCase.photos,
          schemaVersion: archiveCase.schemaVersion,
        ),
      );
      final service = _service(
        database: database,
        images: images,
        files: _RecordingFileStore(),
      );

      final result = await service.importProject(
        zipPath: '/backups/v${archiveCase.schemaVersion}.zip',
        projectName: archiveCase.label,
      );

      expect(
        await database.captureTemplatesForProject(result.projectId),
        hasLength(archiveCase.templates.length),
      );
      expect(
        await database.capturesForProject(result.projectId),
        hasLength(archiveCase.photos.length),
      );
      expect(images.extractRequests, hasLength(archiveCase.photos.length));
      expect(await database.getAllProjectsInternal(), hasLength(1));
    });
  }

  test(
    'template insert failure rolls back project records files and templates',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.customStatement('''
      CREATE TRIGGER fail_second_restored_template
      BEFORE INSERT ON capture_templates
      WHEN NEW.name = '失败'
      BEGIN
        SELECT RAISE(ABORT, 'simulated template insert failure');
      END;
    ''');
      final files = _RecordingFileStore();
      final service = _service(
        database: database,
        images: _ImportImagePipeline(
          _previewWithTemplates([
            _archiveTemplate(name: '成功'),
            _archiveTemplate(name: '失败'),
          ], photos: _preview().photos),
        ),
        files: files,
      );

      await expectLater(
        service.importProject(
          zipPath: '/backups/template-failure.zip',
          projectName: '应回滚项目',
        ),
        throwsA(isA<InvalidArchiveException>()),
      );

      expect(await database.getAllProjectsInternal(), isEmpty);
      expect(await database.getAllCaptures(), isEmpty);
      expect(await database.select(database.captureTemplates).get(), isEmpty);
      expect(files.attemptedDeletes, hasLength(8));
    },
  );

  test(
    'second template failure removes real staged and final files plus marker',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'sitemark-template-real-rollback-',
      );
      addTearDown(() => root.delete(recursive: true));
      final documents = Directory(
        '${root.path}${Platform.pathSeparator}documents',
      );
      final support = Directory('${root.path}${Platform.pathSeparator}support');
      await documents.create(recursive: true);
      await support.create(recursive: true);

      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.customStatement('''
        CREATE TRIGGER fail_second_real_restored_template
        BEFORE INSERT ON capture_templates
        WHEN NEW.name = '失败'
        BEGIN
          SELECT RAISE(ABORT, 'simulated second template failure');
        END;
      ''');
      final images = _WritingImportImagePipeline(
        _previewWithTemplates([
          _archiveTemplate(name: '成功'),
          _archiveTemplate(name: '失败'),
        ], photos: _preview().photos),
      );
      final pendingStore = AppImportPendingStore(
        documentsDirectory: () async => documents,
      );
      final service = ProjectImportService(
        database: database,
        images: images,
        capturePaths: AppCaptureOutputPaths(
          documentsDirectory: () async => documents,
        ),
        originalPaths: AppOriginalPhotoPaths(
          supportDirectory: () async => support,
        ),
        fileStore: DartIoPrivateFileStore(),
        stagingPaths: AppImportStagingPaths(
          documentsDirectory: () async => documents,
        ),
        pendingStore: pendingStore,
        committer: DartImportFileCommitter(),
        clock: () => DateTime(2026, 7, 27, 12),
      );

      await expectLater(
        service.importProject(
          zipPath: '/backups/template-real-failure.zip',
          projectName: '真实文件回滚项目',
          projectId: 'real-file-rollback',
        ),
        throwsA(isA<InvalidArchiveException>()),
      );

      expect(images.extractRequests, hasLength(2));
      for (final request in images.extractRequests) {
        expect(await File(request.renderedDestination).exists(), isFalse);
        if (request.originalDestination case final original?) {
          expect(await File(original).exists(), isFalse);
        }
      }
      expect(
        await Directory(
          '${documents.path}${Platform.pathSeparator}imports'
          '${Platform.pathSeparator}staging-real-file-rollback',
        ).exists(),
        isFalse,
      );
      expect(
        await _filesBelow(Directory('${documents.path}/rendered')),
        isEmpty,
      );
      expect(
        await _filesBelow(Directory('${support.path}/originals')),
        isEmpty,
      );
      expect(await pendingStore.listPending(), isEmpty);
      expect(await database.getAllProjectsInternal(), isEmpty);
      expect(await database.getAllCaptures(), isEmpty);
      expect(await database.select(database.captureTemplates).get(), isEmpty);
    },
  );

  test(
    'template insert IO failure propagates without archive relabeling',
    () async {
      final interceptor = _TemplateInsertIoFailure();
      final database = AppDatabase.forTesting(
        NativeDatabase.memory().interceptWith(interceptor),
      );
      addTearDown(database.close);
      interceptor.enabled = true;
      final service = _service(
        database: database,
        images: _ImportImagePipeline(
          _previewWithTemplates([_archiveTemplate(name: 'IO failure')]),
        ),
        files: _RecordingFileStore(),
      );

      await expectLater(
        service.importProject(
          zipPath: '/backups/template-io.zip',
          projectName: '应保留 IO 错误',
        ),
        throwsA(same(interceptor.failure)),
      );

      expect(await database.getAllProjectsInternal(), isEmpty);
      expect(await database.select(database.captureTemplates).get(), isEmpty);
    },
  );

  test('lost restore ownership is a stable restore-state failure', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.customStatement('''
      CREATE TRIGGER clear_restore_ownership_after_project_insert
      AFTER INSERT ON projects
      WHEN NEW.restore_operation_id IS NOT NULL
      BEGIN
        UPDATE projects
        SET restore_operation_id = NULL
        WHERE id = NEW.id;
      END;
    ''');
    final pendingStore = _FakePendingStore();
    final service = _service(
      database: database,
      images: _ImportImagePipeline(
        _previewWithTemplates([_archiveTemplate(name: 'Ownership')]),
      ),
      files: _RecordingFileStore(),
      pendingStore: pendingStore,
    );

    await expectLater(
      service.importProject(
        zipPath: '/backups/template-ownership.zip',
        projectName: '所有权竞态项目',
      ),
      throwsA(
        isA<ProjectRestoreStateException>().having(
          (error) => error.failure,
          'failure',
          ProjectRestoreStateFailure.ownershipLost,
        ),
      ),
    );

    expect(await database.getAllProjectsInternal(), hasLength(1));
    expect(await database.select(database.captureTemplates).get(), isEmpty);
    expect(pendingStore.pending, hasLength(1));
  });

  test(
    'restored template count mismatch is a stable restore-state failure',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.customStatement('''
      CREATE TRIGGER remove_first_restored_template
      AFTER INSERT ON capture_templates
      WHEN NEW.name = '第二条'
      BEGIN
        DELETE FROM capture_templates WHERE name = '第一条';
      END;
    ''');
      final pendingStore = _FakePendingStore();
      final service = _service(
        database: database,
        images: _ImportImagePipeline(
          _previewWithTemplates([
            _archiveTemplate(name: '第一条'),
            _archiveTemplate(name: '第二条'),
          ]),
        ),
        files: _RecordingFileStore(),
        pendingStore: pendingStore,
      );

      await expectLater(
        service.importProject(
          zipPath: '/backups/template-count-mismatch.zip',
          projectName: '模板集合竞态项目',
        ),
        throwsA(
          isA<ProjectRestoreStateException>().having(
            (error) => error.failure,
            'failure',
            ProjectRestoreStateFailure.templateSetMismatch,
          ),
        ),
      );

      expect(await database.getAllProjectsInternal(), isEmpty);
      expect(await database.select(database.captureTemplates).get(), isEmpty);
      expect(pendingStore.pending, isEmpty);
    },
  );

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
        omittedProcessingCount: 0,
        omittedFailedCount: 0,
        isPartial: false,
        includesOriginals: false,
        projectLifecycleStatus: 'active',
        projectIsPinned: false,
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
        templates: const [],
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
    'restore-owned startup cleanup cascades to restored templates',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      const operationId = 'restore-with-template';
      await database.createProject(
        id: 'dead-template-project',
        name: '含模板烂尾项目',
        restoreOperationId: operationId,
      );
      await database.insertRestoredCaptureTemplates(
        projectId: 'dead-template-project',
        restoreOperationId: operationId,
        templates: [
          CaptureTemplatesCompanion.insert(
            id: 'restored-template-id',
            projectId: 'dead-template-project',
            name: '现场模板',
            nameKey: '现场模板',
            workLocation: 'A 区',
            workContent: '风管检查',
            photographer: '张工',
            createdAt: DateTime.utc(2026, 7, 15, 8),
            updatedAt: DateTime.utc(2026, 7, 15, 9),
          ),
        ],
      );
      final pendingStore = _FakePendingStore()
        ..pending.add(
          const PendingImport(
            projectId: 'dead-template-project',
            stagingDirectory: '/staging/dead-template-project',
            stagedFiles: [],
            finalFiles: [],
            phase: PendingImportPhase.ownsProject,
            operationId: operationId,
          ),
        );
      final service = _service(
        database: database,
        images: _ImportImagePipeline(_preview()),
        files: _RecordingFileStore(),
        pendingStore: pendingStore,
      );

      await service.cleanupInterruptedImports();

      expect(await database.getAllProjectsInternal(), isEmpty);
      expect(await database.select(database.captureTemplates).get(), isEmpty);
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
    const filesPlaced = PendingImport(
      projectId: 'files-placed-id',
      stagingDirectory: '/staging/files-placed-id',
      stagedFiles: [],
      finalFiles: ['/rendered/a.jpg'],
      phase: PendingImportPhase.filesPlaced,
      operationId: 'files-placed-operation',
    );
    expect(
      PendingImport.fromJson(filesPlaced.toJson()).phase,
      PendingImportPhase.filesPlaced,
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
    'committing restart finalization never inserts restored templates twice',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.customStatement('''
        CREATE TRIGGER fail_template_project_token_clear
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
        images: _ImportImagePipeline(
          _previewWithTemplates([_archiveTemplate(name: '只恢复一次')]),
        ),
        files: files,
        pendingStore: pendingStore,
      );

      await expectLater(
        service.importProject(
          zipPath: '/backups/template-finalization.zip',
          projectName: '待收尾模板项目',
        ),
        throwsA(isA<ProjectImportFinalizationPendingException>()),
      );

      final hiddenProject = (await database.getAllProjectsInternal()).single;
      final beforeRestart = await database.captureTemplatesForProject(
        hiddenProject.id,
      );
      expect(beforeRestart, hasLength(1));
      final restoredId = beforeRestart.single.id;
      expect(pendingStore.pending.single.phase, PendingImportPhase.committing);
      expect(files.attemptedDeletes, isEmpty);

      await database.customStatement(
        'DROP TRIGGER fail_template_project_token_clear',
      );
      await service.cleanupInterruptedImports();
      await service.cleanupInterruptedImports();

      expect((await database.getProjects()).single.id, hiddenProject.id);
      final afterRestart = await database.captureTemplatesForProject(
        hiddenProject.id,
      );
      expect(afterRestart, hasLength(1));
      expect(afterRestart.single.id, restoredId);
      expect(pendingStore.pending, isEmpty);
      expect(files.attemptedDeletes, isEmpty);
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
    'filesPlaced marker keeps restored rows and final files on startup cleanup',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      const projectId = 'placed-project';
      const operationId = 'restore-placed-project';
      await database.createProject(
        id: projectId,
        name: '已落盘项目',
        restoreOperationId: operationId,
      );
      await database.insertRestoredCapture(
        id: 'placed-capture',
        projectId: projectId,
        photoNumber: '已落盘项目-SM-20260716-001',
        originalPath: '/originals/placed-capture.jpg',
        workLocation: 'A 区',
        workContent: '检查',
        photographer: '张工',
        watermarkLocaleCode: 'zh',
        originalSha256: 'c' * 64,
        createdAt: DateTime(2026, 7, 16, 9),
        capturedAt: DateTime(2026, 7, 16, 9),
      );
      final files = _RecordingFileStore();
      final committer = _RecordingCommitter();
      final pendingStore = _FakePendingStore()
        ..pending.add(
          const PendingImport(
            projectId: projectId,
            stagingDirectory: '/staging/placed-project',
            stagedFiles: [
              '/staging/placed-project/rendered/placed-capture.jpg',
            ],
            finalFiles: [
              '/rendered/placed-capture.jpg',
              '/originals/placed-capture.jpg',
            ],
            phase: PendingImportPhase.filesPlaced,
            operationId: operationId,
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

      expect(await database.projectById(projectId), isNotNull);
      expect(
        (await database.projectById(projectId))!.restoreOperationId,
        operationId,
      );
      expect(await database.capturesForProject(projectId), hasLength(1));
      expect(
        files.attemptedDeletes,
        isNot(
          containsAll([
            '/rendered/placed-capture.jpg',
            '/originals/placed-capture.jpg',
          ]),
        ),
      );
      expect(files.deleted, isEmpty);
    },
  );

  test(
    'retainRestoreOwnership child persist filesPlaced and cleanup keeps ownership',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      const projectId = 'bundle-child';
      const operationId = 'bundle-operation';
      final files = _RecordingFileStore();
      final pendingStore = _FakePendingStore();
      final service = _service(
        database: database,
        images: _ImportImagePipeline(_preview()),
        files: files,
        pendingStore: pendingStore,
      );

      final result = await service.importProject(
        zipPath: '/backups/p.zip',
        projectName: '子项目恢复',
        projectId: projectId,
        restoreOperationId: operationId,
        retainRestoreOwnership: true,
      );

      expect(result.projectId, projectId);
      expect(
        pendingStore.writtenPhases,
        contains(PendingImportPhase.filesPlaced),
      );
      expect(
        pendingStore.pending,
        anyOf(
          isEmpty,
          everyElement(
            predicate<PendingImport>(
              (pending) => pending.phase == PendingImportPhase.filesPlaced,
            ),
          ),
        ),
      );
      if (pendingStore.pending.isEmpty) {
        pendingStore.pending.add(
          const PendingImport(
            projectId: projectId,
            stagingDirectory: '/staging/bundle-child',
            stagedFiles: [],
            finalFiles: ['/rendered/child.jpg', '/originals/child.jpg'],
            phase: PendingImportPhase.filesPlaced,
            operationId: operationId,
          ),
        );
      }

      await service.cleanupInterruptedImports();

      final project = await database.projectById(projectId);
      expect(project, isNotNull);
      expect(project!.restoreOperationId, operationId);
      expect(await database.capturesForProject(projectId), isNotEmpty);
      expect(pendingStore.pending, isNotEmpty);
      expect(pendingStore.pending.single.phase, PendingImportPhase.filesPlaced);
      expect(files.deleted, isEmpty);
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
      omittedProcessingCount: 0,
      omittedFailedCount: 0,
      isPartial: false,
      includesOriginals: false,
      projectLifecycleStatus: 'active',
      projectIsPinned: false,
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
      templates: const [],
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
    expect(parseExportedTimestamp('2024-02-29 23:59:59 -23:59'), isNotNull);
    for (final invalid in [
      '1900-02-29 09:32:18 +08:00',
      '2026-02-29 09:32:18 +08:00',
      '2026-00-01 09:32:18 +08:00',
      '2026-13-01 09:32:18 +08:00',
      '2026-01-00 09:32:18 +08:00',
      '2026-04-31 09:32:18 +08:00',
      '2026-07-16 24:00:00 +08:00',
      '2026-07-16 23:60:00 +08:00',
      '2026-07-16 23:59:60 +08:00',
      '2026-07-16 23:59:59 +24:00',
      '2026-07-16 23:59:59 +23:60',
      '2026-07-16 23:59:59 08:00',
      '2026-07-16 23:59:59 +08:00 trailing',
    ]) {
      expect(parseExportedTimestamp(invalid), isNull, reason: invalid);
    }
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

ArchiveCaptureTemplate _archiveTemplate({
  required String name,
  String workLocation = 'A 区',
  String workContent = '风管检查',
  String photographer = '张工',
  String createdAt = '2026-07-15 08:00:00 +08:00',
  String updatedAt = '2026-07-15 09:00:00 +08:00',
}) => ArchiveCaptureTemplate(
  name: name,
  workLocation: workLocation,
  workContent: workContent,
  photographer: photographer,
  createdAt: createdAt,
  updatedAt: updatedAt,
);

ProjectArchivePreview _previewWithTemplates(
  List<ArchiveCaptureTemplate> templates, {
  List<ArchivePhotoPreview> photos = const [],
  int schemaVersion = 4,
}) => ProjectArchivePreview(
  schemaVersion: schemaVersion,
  projectName: '模板项目',
  projectDescription: '字段复用测试',
  projectCreatedAt: '2026-07-14T08:00:00.000Z',
  snapshotAt: '2026-07-16T08:00:00.000Z',
  omittedProcessingCount: 0,
  omittedFailedCount: 0,
  isPartial: false,
  includesOriginals: photos.any((photo) => photo.hasOriginal),
  projectLifecycleStatus: 'active',
  projectIsPinned: false,
  photos: photos,
  templates: templates,
);

ProjectArchivePreview _preview() {
  return ProjectArchivePreview(
    schemaVersion: 2,
    projectName: '东区厂房改造',
    omittedProcessingCount: 0,
    omittedFailedCount: 0,
    isPartial: false,
    includesOriginals: true,
    projectLifecycleStatus: 'active',
    projectIsPinned: false,
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
    templates: const [],
  );
}

class _ImportImagePipeline implements ImagePipeline {
  _ImportImagePipeline(this.preview, {this.failAtIndex});

  final ProjectArchivePreview preview;
  final int? failAtIndex;
  final extractRequests = <ExtractArchivePhotoRequest>[];

  @override
  bool get isDegraded => false;

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

class _WritingImportImagePipeline implements ImagePipeline {
  _WritingImportImagePipeline(this.preview);

  final ProjectArchivePreview preview;
  final extractRequests = <ExtractArchivePhotoRequest>[];

  @override
  bool get isDegraded => false;

  @override
  Future<ProjectArchivePreview> readProjectArchive(String zipPath) async =>
      preview;

  @override
  Future<ExtractedArchivePhoto> extractArchivePhoto(
    ExtractArchivePhotoRequest request,
  ) async {
    extractRequests.add(request);
    final rendered = File(request.renderedDestination);
    await rendered.parent.create(recursive: true);
    await rendered.writeAsBytes(const [1, 2, 3], flush: true);
    if (request.originalDestination case final originalPath?) {
      final original = File(originalPath);
      await original.parent.create(recursive: true);
      await original.writeAsBytes(const [4, 5, 6], flush: true);
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

Future<List<File>> _filesBelow(Directory directory) async {
  if (!await directory.exists()) return const [];
  final files = <File>[];
  await for (final entity in directory.list(recursive: true)) {
    if (entity is File) files.add(entity);
  }
  return files;
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
  final writtenPhases = <PendingImportPhase>[];
  final cleared = <String>[];
  var writes = 0;
  bool throwOnClear = false;

  @override
  Future<void> writePending(PendingImport pending) async {
    writes++;
    writtenPhases.add(pending.phase);
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

class _TemplateInsertIoFailure extends QueryInterceptor {
  final failure = SqliteException(
    extendedResultCode: SqlExtendedError.SQLITE_IOERR_WRITE,
    message: 'simulated template database write failure',
  );
  bool enabled = false;

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (enabled && statement.toLowerCase().contains('capture_templates')) {
      throw failure;
    }
    return super.runInsert(executor, statement, args);
  }
}

class _FailBeforeCommitMarkerWriter implements AtomicMarkerWriter {
  @override
  Future<void> write(File target, String contents) async {
    await File('${target.path}.tmp-power-loss').writeAsString('{', flush: true);
    throw StateError('simulated power loss before atomic rename');
  }
}
