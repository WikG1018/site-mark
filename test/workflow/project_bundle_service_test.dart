import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart'
    show ApplyInterceptor, QueryExecutor, QueryInterceptor;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/project_lifecycle.dart';
import 'package:sitemark/diagnostics/diagnostic_event.dart';
import 'package:sitemark/diagnostics/diagnostic_event_store.dart';
import 'package:sitemark/diagnostics/diagnostic_recorder.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/src/rust/api/image_core.dart' as rust;
import 'package:sitemark/workflow/project_bundle_service.dart';
import 'package:sitemark/workflow/project_deletion_service.dart';
import 'package:sitemark/workflow/project_export_service.dart';
import 'package:sitemark/workflow/project_import_service.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test(
    'production paths create export staging but only describe restore staging',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'sitemark-bundle-paths-',
      );
      addTearDown(() => root.delete(recursive: true));
      final paths = AppProjectBundlePaths(documentsDirectory: () async => root);

      final restorePath = await paths.restoreStagingDirectory('restore-id');
      expect(await Directory(restorePath).exists(), isFalse);

      final exportPath = await paths.exportStagingDirectory('export-id');
      expect(await Directory(exportPath).exists(), isTrue);
      expect(await paths.exportStagingDirectories(), [exportPath]);

      final stagedArchive = await paths.backupStagingArchivePath(exportPath);
      expect(stagedArchive, endsWith('sitemark-backup.tmp.zip'));
      final firstBackup = await paths.backupZipPath('operation-1');
      final secondBackup = await paths.backupZipPath('operation-2');
      expect(firstBackup, isNot(secondBackup));
    },
  );

  test('production file commit never overwrites an existing backup', () async {
    final root = await Directory.systemTemp.createTemp('sitemark-commit-');
    addTearDown(() => root.delete(recursive: true));
    final source = File('${root.path}${Platform.pathSeparator}source.zip');
    final destination = File(
      '${root.path}${Platform.pathSeparator}exports'
      '${Platform.pathSeparator}backup.zip',
    );
    await source.writeAsString('new backup');
    final files = DartProjectBundleFileSystem();

    await files.commitFile(source.path, destination.path);

    expect(await destination.readAsString(), 'new backup');
    expect(await source.exists(), isFalse);
    await source.writeAsString('replacement');
    await expectLater(
      files.commitFile(source.path, destination.path),
      throwsA(isA<StateError>()),
    );
    expect(await destination.readAsString(), 'new backup');
  });

  group('ProjectBackupService', () {
    test('rejects empty and duplicate project selections', () async {
      final service = ProjectBackupService(
        projectExporter: _FakeProjectExporter(),
        database: AppDatabase.forTesting(NativeDatabase.memory()),
        bundles: _FakeBundlePipeline(),
        paths: _FakeBundlePaths(),
        files: _FakeBundleFiles(),
        idGenerator: () => 'bundle-1',
      );
      addTearDown(service.database.close);

      await expectLater(
        service.exportProjects(projectIds: const [], includeOriginals: false),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        service.exportProjects(
          projectIds: const ['p1', 'p1'],
          includeOriginals: false,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'one selected project commits a staged archive to a unique final path',
      () async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        await database.createProject(id: 'p1', name: '东区');
        final exporter = _FakeProjectExporter();
        final bundles = _FakeBundlePipeline();
        final files = _FakeBundleFiles();
        final service = ProjectBackupService(
          projectExporter: exporter,
          database: database,
          bundles: bundles,
          paths: _FakeBundlePaths(),
          files: files,
          idGenerator: () => 'bundle-1',
        );

        final result = await service.exportProjects(
          projectIds: const ['p1'],
          includeOriginals: true,
        );

        expect(result.kind, ProjectBackupKind.singleProject);
        expect(result.outputZipPath, '/exports/sitemark-backup-bundle-1.zip');
        expect(
          exporter.requests.single.outputZipPath,
          '/imports/bundle-export-bundle-1/projects/p1.zip',
        );
        expect(bundles.exportRequests, isEmpty);
        expect(files.committedFiles, [
          (
            '/imports/bundle-export-bundle-1/projects/p1.zip',
            '/exports/sitemark-backup-bundle-1.zip',
          ),
        ]);
        expect(files.deletedTrees, ['/imports/bundle-export-bundle-1']);
      },
    );

    test(
      'multiple projects create one bundle and always clean staging',
      () async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        await database.createProject(id: 'p1', name: '东区');
        await database.createProject(id: 'p2', name: '西区');
        final exporter = _FakeProjectExporter();
        final bundles = _FakeBundlePipeline();
        final files = _FakeBundleFiles();
        final progress = <String>[];
        final service = ProjectBackupService(
          projectExporter: exporter,
          database: database,
          bundles: bundles,
          paths: _FakeBundlePaths(),
          files: files,
          idGenerator: () => 'bundle-1',
        );

        final result = await service.exportProjects(
          projectIds: const ['p1', 'p2'],
          includeOriginals: false,
          onProgress: (completed, total) => progress.add('$completed/$total'),
        );

        expect(result.kind, ProjectBackupKind.bundle);
        expect(result.outputZipPath, '/exports/sitemark-backup-bundle-1.zip');
        expect(exporter.requests.map((request) => request.outputZipPath), [
          '/imports/bundle-export-bundle-1/projects/p1.zip',
          '/imports/bundle-export-bundle-1/projects/p2.zip',
        ]);
        expect(bundles.exportRequests.single.projects, hasLength(2));
        expect(
          bundles.exportRequests.single.outputZipPath,
          '/imports/bundle-export-bundle-1/sitemark-backup.tmp.zip',
        );
        expect(bundles.exportRequests.single.projects[0].projectName, '东区');
        expect(progress, ['1/3', '2/3', '3/3']);
        expect(files.deletedTrees, ['/imports/bundle-export-bundle-1']);
        expect(files.committedFiles, [
          (
            '/imports/bundle-export-bundle-1/sitemark-backup.tmp.zip',
            '/exports/sitemark-backup-bundle-1.zip',
          ),
        ]);
      },
    );

    test(
      'bundle exports each project with its own ordered template values',
      () async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        await database.createProject(id: 'p1', name: '东区');
        await database.createProject(id: 'p2', name: '西区');
        await database.insertCaptureTemplate(
          CaptureTemplatesCompanion.insert(
            id: 'p1-old',
            projectId: 'p1',
            name: '东区早班',
            nameKey: '东区早班',
            workLocation: 'A 区',
            workContent: '风管检查',
            photographer: '张工',
            createdAt: DateTime.utc(2026, 7, 14, 1),
            updatedAt: DateTime.utc(2026, 7, 14, 2),
          ),
        );
        await database.insertCaptureTemplate(
          CaptureTemplatesCompanion.insert(
            id: 'p1-new',
            projectId: 'p1',
            name: '东区晚班',
            nameKey: '东区晚班',
            workLocation: 'B 区',
            workContent: '水压复核',
            photographer: '李工',
            createdAt: DateTime.utc(2026, 7, 15, 1),
            updatedAt: DateTime.utc(2026, 7, 15, 2),
          ),
        );
        await database.insertCaptureTemplate(
          CaptureTemplatesCompanion.insert(
            id: 'p2-only',
            projectId: 'p2',
            name: '西区班组',
            nameKey: '西区班组',
            workLocation: 'C 区',
            workContent: '给水检查',
            photographer: '王工',
            createdAt: DateTime.utc(2026, 7, 16, 1),
            updatedAt: DateTime.utc(2026, 7, 16, 2),
          ),
        );
        final images = _RecordingProjectImagePipeline();
        final exporter = ProjectExportService(
          database: database,
          images: images,
          capturePaths: _BundleCapturePaths(),
          exportPaths: _BundleProjectExportPaths(),
          selectionExportPaths: _BundleSelectionPaths(),
        );
        final service = ProjectBackupService(
          projectExporter: exporter,
          database: database,
          bundles: _FakeBundlePipeline(),
          paths: _FakeBundlePaths(),
          files: _FakeBundleFiles(),
          idGenerator: () => 'bundle-templates',
        );

        await service.exportProjects(
          projectIds: const ['p1', 'p2'],
          includeOriginals: false,
        );

        expect(images.requests.map((request) => request.projectId), [
          'p1',
          'p2',
        ]);
        expect(
          images.requests[0].templates
              .map(
                (template) => [
                  template.name,
                  template.workLocation,
                  template.workContent,
                  template.photographer,
                ],
              )
              .toList(),
          const [
            ['东区晚班', 'B 区', '水压复核', '李工'],
            ['东区早班', 'A 区', '风管检查', '张工'],
          ],
        );
        expect(
          images.requests[1].templates
              .map(
                (template) => [
                  template.name,
                  template.workLocation,
                  template.workContent,
                  template.photographer,
                ],
              )
              .toList(),
          const [
            ['西区班组', 'C 区', '给水检查', '王工'],
          ],
        );
      },
    );

    for (final projectIds in const [
      ['p1'],
      ['p1', 'p2'],
    ]) {
      test(
        '${projectIds.length == 1 ? 'single' : 'multi'} project template read '
        'failure identifies the exact project and never writes a bundle',
        () async {
          final failedProjectId = projectIds.last;
          final interceptor = _ProjectTemplateReadFailure(failedProjectId);
          final database = AppDatabase.forTesting(
            NativeDatabase.memory().interceptWith(interceptor),
          );
          addTearDown(database.close);
          await database.createProject(id: 'p1', name: '东区');
          if (projectIds.length > 1) {
            await database.createProject(id: 'p2', name: '西区');
          }
          interceptor.enabled = true;
          final images = _RecordingProjectImagePipeline();
          final bundles = _FakeBundlePipeline();
          final files = _FakeBundleFiles();
          final diagnosticRoot = await Directory.systemTemp.createTemp(
            'sitemark-backup-diagnostics-',
          );
          addTearDown(() => diagnosticRoot.delete(recursive: true));
          final diagnosticStore = DiagnosticEventStore(
            directory: diagnosticRoot,
          );
          final service = ProjectBackupService(
            projectExporter: ProjectExportService(
              database: database,
              images: images,
              capturePaths: _BundleCapturePaths(),
              exportPaths: _BundleProjectExportPaths(),
              selectionExportPaths: _BundleSelectionPaths(),
            ),
            database: database,
            bundles: bundles,
            paths: _FakeBundlePaths(),
            files: files,
            diagnostics: DiagnosticRecorder(diagnosticStore),
            idGenerator: () => 'bundle-template-read-failure',
          );

          ProjectBackupExportException? failure;
          try {
            await service.exportProjects(
              projectIds: projectIds,
              includeOriginals: false,
            );
          } catch (error) {
            expect(error, isA<ProjectBackupExportException>());
            failure = error as ProjectBackupExportException;
          }

          expect(failure, isNotNull);
          expect(failure!.projectId, failedProjectId);
          expect(failure.projectName, projectIds.length == 1 ? '东区' : '西区');
          expect(failure.cause, same(interceptor.failure));
          expect(failure.toString(), isNot(contains('private-template-value')));
          expect(failure.toString(), isNot(contains(r'C:\private\database')));
          expect(
            images.requests.map((request) => request.projectId),
            projectIds.length == 1 ? isEmpty : ['p1'],
          );
          expect(bundles.exportRequests, isEmpty);
          expect(files.committedFiles, isEmpty);
          expect(files.deletedTrees, [
            '/imports/bundle-export-bundle-template-read-failure',
          ]);

          List<DiagnosticEvent> events = const [];
          for (var attempt = 0; attempt < 20 && events.isEmpty; attempt++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            events = await diagnosticStore.readRecent();
          }
          expect(events, hasLength(1));
          final event = events.single;
          expect(event.category, DiagnosticCategory.backup);
          expect(event.outcome, DiagnosticOutcome.failed);
          expect(event.code, DiagnosticCode.unexpected);
          expect(event.count, 1);
          expect(event.toJson().keys.toSet(), {
            'timestamp',
            'category',
            'outcome',
            'code',
            'duration_ms',
            'count',
          });
          final encoded = event.encode();
          expect(encoded, isNot(contains('private-template-value')));
          expect(encoded, isNot(contains(r'C:\private\database')));
          expect(encoded, isNot(contains('东区')));
          expect(encoded, isNot(contains('西区')));
        },
      );
    }

    test(
      'project ENOSPC records storage diagnostic without private context',
      () async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        await database.createProject(id: 'p1', name: '私有项目名称');
        final storageError = FileSystemException(
          'private-template-value',
          r'C:\private\database\sitemark.sqlite',
          const OSError('No space left on device', 28),
        );
        final diagnosticRoot = await Directory.systemTemp.createTemp(
          'sitemark-backup-storage-diagnostics-',
        );
        addTearDown(() => diagnosticRoot.delete(recursive: true));
        final diagnosticStore = DiagnosticEventStore(directory: diagnosticRoot);
        final service = ProjectBackupService(
          projectExporter: _FakeProjectExporter(
            failProjectId: 'p1',
            failure: storageError,
          ),
          database: database,
          bundles: _FakeBundlePipeline(),
          paths: _FakeBundlePaths(),
          files: _FakeBundleFiles(),
          diagnostics: DiagnosticRecorder(diagnosticStore),
          idGenerator: () => 'bundle-storage-failure',
        );

        await expectLater(
          service.exportProjects(
            projectIds: const ['p1'],
            includeOriginals: false,
          ),
          throwsA(
            isA<ProjectBackupExportException>().having(
              (error) => error.cause,
              'cause',
              same(storageError),
            ),
          ),
        );

        List<DiagnosticEvent> events = const [];
        for (var attempt = 0; attempt < 20 && events.isEmpty; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          events = await diagnosticStore.readRecent();
        }
        expect(events, hasLength(1));
        final event = events.single;
        expect(event.category, DiagnosticCategory.backup);
        expect(event.outcome, DiagnosticOutcome.failed);
        expect(event.code, DiagnosticCode.insufficientStorage);
        expect(event.count, 1);
        expect(event.toJson().keys.toSet(), {
          'timestamp',
          'category',
          'outcome',
          'code',
          'duration_ms',
          'count',
        });
        final encoded = event.encode();
        expect(encoded, isNot(contains('private-template-value')));
        expect(encoded, isNot(contains(r'C:\private\database')));
        expect(encoded, isNot(contains('私有项目名称')));
      },
    );

    test('bundle export failure still cleans staging', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.createProject(id: 'p1', name: '东区');
      await database.createProject(id: 'p2', name: '西区');
      final files = _FakeBundleFiles();
      final service = ProjectBackupService(
        projectExporter: _FakeProjectExporter(failProjectId: 'p2'),
        database: database,
        bundles: _FakeBundlePipeline(),
        paths: _FakeBundlePaths(),
        files: files,
        idGenerator: () => 'bundle-2',
      );

      await expectLater(
        service.exportProjects(
          projectIds: const ['p1', 'p2'],
          includeOriginals: false,
        ),
        throwsA(isA<StateError>()),
      );

      expect(files.deletedTrees, ['/imports/bundle-export-bundle-2']);
      expect(files.committedFiles, isEmpty);
    });

    test('final path failure still cleans staging', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.createProject(id: 'p1', name: '东区');
      final files = _FakeBundleFiles();
      final service = ProjectBackupService(
        projectExporter: _FakeProjectExporter(),
        database: database,
        bundles: _FakeBundlePipeline(),
        paths: _FakeBundlePaths(failBackupPath: true),
        files: files,
        idGenerator: () => 'bundle-path-failure',
      );

      await expectLater(
        service.exportProjects(
          projectIds: const ['p1'],
          includeOriginals: false,
        ),
        throwsA(isA<StateError>()),
      );

      expect(files.deletedTrees, [
        '/imports/bundle-export-bundle-path-failure',
      ]);
    });

    test('cleans every interrupted export staging directory', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final paths = _FakeBundlePaths()
        ..interruptedExportDirectories = [
          '/imports/bundle-export-old-1',
          '/imports/bundle-export-old-2',
        ];
      final files = _FakeBundleFiles();
      final service = ProjectBackupService(
        projectExporter: _FakeProjectExporter(),
        database: database,
        bundles: _FakeBundlePipeline(),
        paths: paths,
        files: files,
      );

      await service.cleanupInterruptedExports();

      expect(files.deletedTrees, paths.interruptedExportDirectories);
    });
  });

  group('ProjectBundleService', () {
    test(
      'prepare classifies archive failures without exposing parser text',
      () async {
        final cases =
            <
              (
                Object bundleFailure,
                Object singleFailure,
                ProjectBundleRestoreFailure expected,
              )
            >[
              (
                const ImagePipelineException(
                  ImagePipelineFailureKind.invalidData,
                  'not a bundle',
                ),
                const ImagePipelineException(
                  ImagePipelineFailureKind.invalidData,
                  'not a project archive',
                ),
                ProjectBundleRestoreFailure.notSiteMarkBackup,
              ),
              (
                const ImagePipelineException(
                  ImagePipelineFailureKind.invalidData,
                  'unsupported schema version 99',
                ),
                const ImagePipelineException(
                  ImagePipelineFailureKind.invalidData,
                  'not a project archive',
                ),
                ProjectBundleRestoreFailure.unsupportedVersion,
              ),
              (
                const ImagePipelineException(
                  ImagePipelineFailureKind.invalidData,
                  'archive checksum mismatch',
                ),
                const ImagePipelineException(
                  ImagePipelineFailureKind.invalidData,
                  'not a project archive',
                ),
                ProjectBundleRestoreFailure.corrupted,
              ),
              (
                const ImagePipelineException(
                  ImagePipelineFailureKind.invalidData,
                  'not a bundle',
                ),
                const ImagePipelineException(
                  ImagePipelineFailureKind.invalidData,
                  'selection archive: cannot restore',
                ),
                ProjectBundleRestoreFailure.selectionArchive,
              ),
              (
                const ImagePipelineException(
                  ImagePipelineFailureKind.transientIo,
                  'No space left on device',
                ),
                StateError('unused'),
                ProjectBundleRestoreFailure.insufficientStorage,
              ),
            ];

        for (final item in cases) {
          final database = AppDatabase.forTesting(NativeDatabase.memory());
          final service = _bundleService(
            database: database,
            bundles: _FakeBundlePipeline(readFailure: item.$1),
            importer: _FakeProjectImporter(inspectFailure: item.$2),
          );
          await expectLater(
            service.prepareRestore('/backups/input.zip'),
            throwsA(
              isA<ProjectBundleRestoreException>().having(
                (error) => error.failure,
                'failure',
                item.$3,
              ),
            ),
          );
          await database.close();
        }
      },
    );

    test(
      'prepare validates, extracts and previews every inner archive',
      () async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        final events = <String>[];
        final pending = _FakeBundlePendingStore(
          onWrite: () => events.add('marker'),
        );
        final files = _FakeBundleFiles(onEnsure: () => events.add('ensure'));
        var markerSeenBeforeExtract = false;
        final bundles = _FakeBundlePipeline(
          preview: _bundlePreview(),
          onExtract: () {
            events.add('extract');
            markerSeenBeforeExtract = pending.items.isNotEmpty;
          },
        );
        final importer = _FakeProjectImporter();
        final service = _bundleService(
          database: database,
          bundles: bundles,
          importer: importer,
          pending: pending,
          files: files,
        );

        final prepared = await service.prepareRestore('/backups/bundle.zip');

        expect(prepared.isBundle, isTrue);
        expect(prepared.items, hasLength(2));
        expect(prepared.items[0].sourceProjectId, 'p1');
        expect(prepared.items[0].targetProjectId, 'target-1');
        expect(prepared.items[0].preview.photos, hasLength(1));
        expect(bundles.extractRequests.map((request) => request.outputPath), [
          '/imports/bundle-restore-bundle-prepare/projects/p1.zip',
          '/imports/bundle-restore-bundle-prepare/projects/p2.zip',
        ]);
        expect(importer.inspected, hasLength(2));
        expect(markerSeenBeforeExtract, isTrue);
        expect(pending.writes, 1);
        expect(pending.items.single.plannedProjectIds, isEmpty);
        expect(pending.items.single.operationId, prepared.bundleId);
        expect(events, ['marker', 'ensure', 'extract', 'extract']);
      },
    );

    test(
      'single-project archives still prepare without bundle staging',
      () async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        final bundles = _FakeBundlePipeline(
          readFailure: const ImagePipelineException(
            ImagePipelineFailureKind.invalidData,
            'not bundle',
          ),
        );
        final importer = _FakeProjectImporter();
        final files = _FakeBundleFiles();
        final service = _bundleService(
          database: database,
          bundles: bundles,
          importer: importer,
          files: files,
        );

        final prepared = await service.prepareRestore('/backups/single.zip');

        expect(prepared.isBundle, isFalse);
        expect(prepared.items.single.archivePath, '/backups/single.zip');
        expect(files.deletedTrees, isEmpty);
        expect((service.pendingStore as _FakeBundlePendingStore).writes, 0);
      },
    );

    test(
      'prepared marker cleanup removes staging without handing off projects',
      () async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        final pending = _FakeBundlePendingStore();
        final files = _FakeBundleFiles();
        final rollback = _FakeProjectRollback();
        final service = _bundleService(
          database: database,
          bundles: _FakeBundlePipeline(preview: _bundlePreview()),
          importer: _FakeProjectImporter(),
          pending: pending,
          files: files,
          rollback: rollback,
        );
        final prepared = await service.prepareRestore('/backups/bundle.zip');

        await service.cleanupInterruptedBundleRestores();

        expect(files.deletedTrees, [prepared.stagingDirectory]);
        expect(pending.items, isEmpty);
        expect(rollback.projectIds, isEmpty);
      },
    );

    test('discardPrepared deletes staging then clears its marker', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final pending = _FakeBundlePendingStore();
      final files = _FakeBundleFiles();
      final service = _bundleService(
        database: database,
        bundles: _FakeBundlePipeline(preview: _bundlePreview()),
        importer: _FakeProjectImporter(),
        pending: pending,
        files: files,
      );
      final prepared = await service.prepareRestore('/backups/bundle.zip');
      expect(pending.items, hasLength(1));

      await service.discardPrepared(prepared);

      expect(files.deletedTrees, [prepared.stagingDirectory]);
      expect(pending.items, isEmpty);
    });

    test(
      'prepare failure retains marker when staging cleanup fails and startup retries',
      () async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        final pending = _FakeBundlePendingStore();
        final files = _FakeBundleFiles(
          failPath: '/imports/bundle-restore-bundle-prepare',
        );
        final service = _bundleService(
          database: database,
          bundles: _FakeBundlePipeline(
            preview: _bundlePreview(),
            extractFailureAt: 1,
          ),
          importer: _FakeProjectImporter(),
          pending: pending,
          files: files,
        );

        await expectLater(
          service.prepareRestore('/backups/bundle.zip'),
          throwsA(isA<ProjectBundleRestoreException>()),
        );
        expect(pending.items, hasLength(1));
        expect(pending.items.single.plannedProjectIds, isEmpty);

        files.failPath = null;
        await service.cleanupInterruptedBundleRestores();

        expect(pending.items, isEmpty);
        expect(files.deletedTrees, [
          '/imports/bundle-restore-bundle-prepare',
          '/imports/bundle-restore-bundle-prepare',
        ]);
      },
    );

    test(
      'prepare failure retains marker when marker clear fails and startup retries',
      () async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        final pending = _FakeBundlePendingStore(throwOnClear: true);
        final files = _FakeBundleFiles();
        final service = _bundleService(
          database: database,
          bundles: _FakeBundlePipeline(
            preview: _bundlePreview(),
            extractFailureAt: 1,
          ),
          importer: _FakeProjectImporter(),
          pending: pending,
          files: files,
        );

        await expectLater(
          service.prepareRestore('/backups/bundle.zip'),
          throwsA(isA<ProjectBundleRestoreException>()),
        );
        expect(pending.items, hasLength(1));

        pending.throwOnClear = false;
        await service.cleanupInterruptedBundleRestores();

        expect(pending.items, isEmpty);
      },
    );

    test('batch name conflicts are rejected before first import', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.createProject(
        id: 'existing',
        name: '已有项目',
        restoreOperationId: 'hidden-restore',
      );
      final importer = _FakeProjectImporter();
      final service = _bundleService(
        database: database,
        bundles: _FakeBundlePipeline(preview: _bundlePreview()),
        importer: importer,
      );
      final prepared = await service.prepareRestore('/backups/bundle.zip');

      await expectLater(
        service.restorePrepared(
          prepared: prepared,
          projectNames: const {'p1': '已有项目', 'p2': '新项目'},
        ),
        throwsA(
          isA<ProjectBundleRestoreException>().having(
            (error) => error.failure,
            'failure',
            ProjectBundleRestoreFailure.nameConflict,
          ),
        ),
      );
      await expectLater(
        service.restorePrepared(
          prepared: prepared,
          projectNames: const {'p1': 'A/B', 'p2': 'A:B'},
        ),
        throwsA(
          isA<ProjectBundleRestoreException>().having(
            (error) => error.failure,
            'failure',
            ProjectBundleRestoreFailure.nameConflict,
          ),
        ),
      );

      expect(importer.imports, isEmpty);
    });

    test('item two failure rolls back every planned target id', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final pending = _FakeBundlePendingStore();
      final rollback = _FakeProjectRollback();
      final importer = _FakeProjectImporter(failSource: 'p2.zip');
      final service = _bundleService(
        database: database,
        bundles: _FakeBundlePipeline(preview: _bundlePreview()),
        importer: importer,
        pending: pending,
        rollback: rollback,
      );
      final prepared = await service.prepareRestore('/backups/bundle.zip');

      await expectLater(
        service.restorePrepared(
          prepared: prepared,
          projectNames: const {'p1': '东区', 'p2': '西区'},
        ),
        throwsA(
          isA<ProjectBundleRestoreException>().having(
            (error) => error.failure,
            'failure',
            ProjectBundleRestoreFailure.rolledBack,
          ),
        ),
      );

      expect(rollback.projectIds, ['target-1']);
      expect(pending.items, isEmpty);
      expect(importer.markerSeenBeforeFirstImport, isTrue);
    });

    test(
      'restore-state failures are classified as general, not corrupted',
      () async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        final importer = _FakeProjectImporter(
          failSource: 'p1.zip',
          importFailure: const ProjectRestoreStateException(
            ProjectRestoreStateFailure.ownershipLost,
          ),
        );
        final service = _bundleService(
          database: database,
          bundles: _FakeBundlePipeline(preview: _bundlePreview()),
          importer: importer,
        );
        final prepared = await service.prepareRestore('/backups/bundle.zip');

        await expectLater(
          service.restorePrepared(
            prepared: prepared,
            projectNames: const {'p1': '东区', 'p2': '西区'},
          ),
          throwsA(
            isA<ProjectBundleRestoreException>().having(
              (error) => error.failure,
              'failure',
              ProjectBundleRestoreFailure.general,
            ),
          ),
        );
      },
    );

    test(
      'item two ENOSPC keeps storage classification after rollback',
      () async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        final pending = _FakeBundlePendingStore();
        final rollback = _FakeProjectRollback();
        final importer = _FakeProjectImporter(
          failSource: 'p2.zip',
          importFailure: const ImagePipelineException(
            ImagePipelineFailureKind.transientIo,
            'No space left on device',
          ),
        );
        final service = _bundleService(
          database: database,
          bundles: _FakeBundlePipeline(preview: _bundlePreview()),
          importer: importer,
          pending: pending,
          rollback: rollback,
        );
        final prepared = await service.prepareRestore('/backups/bundle.zip');

        await expectLater(
          service.restorePrepared(
            prepared: prepared,
            projectNames: const {'p1': '东区', 'p2': '西区'},
          ),
          throwsA(
            isA<ProjectBundleRestoreException>().having(
              (error) => error.failure,
              'failure',
              ProjectBundleRestoreFailure.insufficientStorage,
            ),
          ),
        );

        expect(rollback.projectIds, ['target-1']);
        expect(pending.items, isEmpty);
      },
    );

    test(
      'single import finalization pending is not reported as rolled back',
      () async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        final rollback = _FakeProjectRollback();
        final importer = _FakeProjectImporter(
          failSource: 'single.zip',
          importFailure: const ProjectImportFinalizationPendingException(
            projectId: 'target-1',
            cause: 'token clear failed',
          ),
        );
        final service = _bundleService(
          database: database,
          bundles: _FakeBundlePipeline(
            readFailure: const ImagePipelineException(
              ImagePipelineFailureKind.invalidData,
              'not bundle',
            ),
          ),
          importer: importer,
          rollback: rollback,
        );
        final prepared = await service.prepareRestore('/backups/single.zip');

        await expectLater(
          service.restorePrepared(
            prepared: prepared,
            projectNames: const {'single': '待完成恢复'},
          ),
          throwsA(
            isA<ProjectBundleRestoreException>().having(
              (error) => error.failure,
              'failure',
              ProjectBundleRestoreFailure.finalizationPending,
            ),
          ),
        );

        expect(rollback.projectIds, isEmpty);
      },
    );

    test(
      'standalone committed import waits for startup finalization without rollback',
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
        final importPending = _IntegrationImportPendingStore();
        final committer = _IntegrationImportCommitter();
        final importer = ProjectImportService(
          database: database,
          images: _IntegrationImportPipeline(_archivePreview('源项目')),
          capturePaths: _IntegrationCapturePaths(),
          originalPaths: _IntegrationOriginalPaths(),
          fileStore: _IntegrationPrivateFiles(),
          stagingPaths: _IntegrationStagingPaths(),
          pendingStore: importPending,
          committer: committer,
        );
        final rollback = _FakeProjectRollback();
        final service = _bundleService(
          database: database,
          bundles: _FakeBundlePipeline(),
          importer: importer,
          rollback: rollback,
        );
        final prepared = PreparedProjectRestore(
          sourceZipPath: '/backups/single.zip',
          items: [
            PreparedProjectRestoreItem(
              sourceProjectId: 'source',
              targetProjectId: 'integration-target',
              archivePath: '/backups/single.zip',
              preview: _archivePreview('源项目'),
            ),
          ],
        );

        await expectLater(
          service.restorePrepared(
            prepared: prepared,
            projectNames: const {'source': '待完成恢复'},
          ),
          throwsA(
            isA<ProjectBundleRestoreException>().having(
              (error) => error.failure,
              'failure',
              ProjectBundleRestoreFailure.finalizationPending,
            ),
          ),
        );

        expect(committer.moves, hasLength(2));
        expect(await database.getProjects(), isEmpty);
        expect(await database.getAllProjectsInternal(), hasLength(1));
        expect(importPending.items.single.phase, PendingImportPhase.committing);
        expect(rollback.projectIds, isEmpty);

        await database.customStatement('DROP TRIGGER fail_import_token_clear');
        await importer.cleanupInterruptedImports();

        expect((await database.getProjects()).single.name, '待完成恢复');
        expect(importPending.items, isEmpty);
        expect(rollback.projectIds, isEmpty);
      },
    );

    test('restore progress is monotonic across projects', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final pending = _FakeBundlePendingStore();
      final service = _bundleService(
        database: database,
        bundles: _FakeBundlePipeline(preview: _bundlePreview()),
        importer: _FakeProjectImporter(),
        pending: pending,
      );
      final prepared = await service.prepareRestore('/backups/bundle.zip');
      final progress = <String>[];

      await service.restorePrepared(
        prepared: prepared,
        projectNames: const {'p1': '东区', 'p2': '西区'},
        onProgress: (completed, total) => progress.add('$completed/$total'),
      );

      expect(progress, ['1/2', '2/2']);
      expect(pending.writtenPhases.last, PendingBundleRestorePhase.committing);
      expect(await database.getProjects(), hasLength(2));
    });

    test(
      'restorePrepared preserves mixed lifecycle statuses and pins',
      () async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        final pending = _FakeBundlePendingStore();
        final importer = _FakeProjectImporter(
          lifecycleByName: {
            '进行中项目': ProjectLifecycleStatus.active,
            '已完成项目': ProjectLifecycleStatus.completed,
            '归档项目': ProjectLifecycleStatus.archived,
          },
          pinByName: {'进行中项目': false, '已完成项目': true, '归档项目': true},
        );
        final service = _bundleService(
          database: database,
          bundles: _FakeBundlePipeline(
            preview: rust.ProjectBundlePreview(
              schemaVersion: 1,
              createdAt: '2026-08-03T12:00:00+08:00',
              projects: [
                rust.ProjectBundleEntryPreview(
                  projectId: 'p1',
                  projectName: '进行中项目',
                  archivePath: 'projects/p1.zip',
                  archiveSha256: 'a' * 64,
                ),
                rust.ProjectBundleEntryPreview(
                  projectId: 'p2',
                  projectName: '已完成项目',
                  archivePath: 'projects/p2.zip',
                  archiveSha256: 'b' * 64,
                ),
                rust.ProjectBundleEntryPreview(
                  projectId: 'p3',
                  projectName: '归档项目',
                  archivePath: 'projects/p3.zip',
                  archiveSha256: 'c' * 64,
                ),
              ],
            ),
          ),
          importer: importer,
          pending: pending,
        );
        final prepared = await service.prepareRestore('/backups/bundle.zip');
        final results = await service.restorePrepared(
          prepared: prepared,
          projectNames: const {'p1': '进行中项目', 'p2': '已完成项目', 'p3': '归档项目'},
        );

        expect(results.map((r) => r.lifecycleStatus), [
          ProjectLifecycleStatus.active,
          ProjectLifecycleStatus.completed,
          ProjectLifecycleStatus.archived,
        ]);
        expect(results.map((r) => r.isPinned), [false, true, true]);
        final projects = await database.getProjects();
        expect(projects, hasLength(3));
        Project byName(String name) =>
            projects.firstWhere((project) => project.name == name);
        expect(byName('进行中项目').lifecycleStatus, ProjectLifecycleStatus.active);
        expect(
          byName('已完成项目').lifecycleStatus,
          ProjectLifecycleStatus.completed,
        );
        expect(byName('已完成项目').isPinned, isTrue);
        expect(byName('归档项目').lifecycleStatus, ProjectLifecycleStatus.archived);
        expect(byName('归档项目').isPinned, isTrue);
      },
    );

    test(
      'interrupted cleanup attempts every planned id before clearing',
      () async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        await database.createProject(
          id: 'new-p1',
          name: '恢复东区',
          restoreOperationId: 'bundle-operation',
        );
        await database.createProject(
          id: 'new-p2',
          name: '恢复西区',
          restoreOperationId: 'bundle-operation',
        );
        final pending = _FakeBundlePendingStore()
          ..items.add(
            const PendingBundleRestore(
              bundleId: 'b1',
              stagingDirectory: '/staging/b1',
              plannedProjectIds: ['new-p1', 'new-p2'],
              ownedProjectIds: ['new-p1', 'new-p2'],
              operationId: 'bundle-operation',
            ),
          );
        final rollback = _FakeProjectRollback();
        final files = _FakeBundleFiles();
        final service = _bundleService(
          database: database,
          bundles: _FakeBundlePipeline(),
          importer: _FakeProjectImporter(),
          pending: pending,
          rollback: rollback,
          files: files,
        );

        await service.cleanupInterruptedBundleRestores();

        expect(rollback.projectIds, ['new-p1', 'new-p2']);
        expect(files.deletedTrees, ['/staging/b1']);
        expect(pending.items, isEmpty);
      },
    );

    test(
      'database token finds completed children even before owned list rewrite',
      () async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        await database.createProject(
          id: 'new-p1',
          name: '恢复东区',
          restoreOperationId: 'bundle-operation',
        );
        await database.createProject(
          id: 'new-p2',
          name: '恢复西区',
          restoreOperationId: 'bundle-operation',
        );
        final pending = _FakeBundlePendingStore()
          ..items.add(
            const PendingBundleRestore(
              bundleId: 'b-gap',
              stagingDirectory: '/staging/b-gap',
              plannedProjectIds: ['new-p1', 'new-p2'],
              operationId: 'bundle-operation',
            ),
          );
        final deletions = ProjectDeletionService(
          database: database,
          capturePaths: _DeletionCapturePaths(),
          files: _DeletionFiles(),
          pendingStore: _DeletionPendingStore(),
        );
        final service = _bundleService(
          database: database,
          bundles: _FakeBundlePipeline(),
          importer: _FakeProjectImporter(),
          pending: pending,
          rollback: ProjectDeletionBundleRollback(
            database: database,
            deletions: deletions,
          ),
        );

        await service.cleanupInterruptedBundleRestores();

        expect(await database.getProjects(), isEmpty);
        expect(pending.items, isEmpty);
      },
    );

    test(
      'committing marker retries token clear without rolling projects back',
      () async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        await database.createProject(
          id: 'committing-project',
          name: '提交中项目',
          restoreOperationId: 'commit-operation',
        );
        await database.customStatement('''
          CREATE TRIGGER fail_restore_token_clear
          BEFORE UPDATE OF restore_operation_id ON projects
          WHEN NEW.restore_operation_id IS NULL
          BEGIN
            SELECT RAISE(ABORT, 'simulated token clear failure');
          END;
        ''');
        final pending = _FakeBundlePendingStore()
          ..items.add(
            const PendingBundleRestore(
              bundleId: 'commit-bundle',
              stagingDirectory: '/staging/commit-bundle',
              plannedProjectIds: ['committing-project'],
              operationId: 'commit-operation',
              phase: PendingBundleRestorePhase.committing,
            ),
          );
        final rollback = _FakeProjectRollback();
        final service = _bundleService(
          database: database,
          bundles: _FakeBundlePipeline(),
          importer: _FakeProjectImporter(),
          pending: pending,
          rollback: rollback,
        );

        await service.cleanupInterruptedBundleRestores();

        expect(pending.items, hasLength(1));
        expect(await database.getProjects(), isEmpty);
        expect(rollback.projectIds, isEmpty);

        await database.customStatement('DROP TRIGGER fail_restore_token_clear');
        await service.cleanupInterruptedBundleRestores();

        expect((await database.getProjects()).map((project) => project.id), [
          'committing-project',
        ]);
        expect(pending.items, isEmpty);
        expect(rollback.projectIds, isEmpty);
      },
    );

    test(
      'completed bundle reports finalization pending until startup publishes it',
      () async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        await database.customStatement('''
          CREATE TRIGGER fail_restore_token_clear
          BEFORE UPDATE OF restore_operation_id ON projects
          WHEN NEW.restore_operation_id IS NULL
          BEGIN
            SELECT RAISE(ABORT, 'simulated token clear failure');
          END;
        ''');
        final pending = _FakeBundlePendingStore();
        final files = _FakeBundleFiles();
        final rollback = _FakeProjectRollback();
        final service = _bundleService(
          database: database,
          bundles: _FakeBundlePipeline(preview: _bundlePreview()),
          importer: _FakeProjectImporter(),
          pending: pending,
          files: files,
          rollback: rollback,
        );
        final prepared = await service.prepareRestore('/backups/bundle.zip');

        await expectLater(
          service.restorePrepared(
            prepared: prepared,
            projectNames: const {'p1': '恢复东区', 'p2': '恢复西区'},
          ),
          throwsA(
            isA<ProjectBundleRestoreException>().having(
              (error) => error.failure,
              'failure',
              ProjectBundleRestoreFailure.finalizationPending,
            ),
          ),
        );

        expect(await database.getProjects(), isEmpty);
        expect(await database.getAllProjectsInternal(), hasLength(2));
        expect(
          pending.items.single.phase,
          PendingBundleRestorePhase.committing,
        );
        expect(files.deletedTrees, [prepared.stagingDirectory]);
        expect(rollback.projectIds, isEmpty);

        await database.customStatement('DROP TRIGGER fail_restore_token_clear');
        await service.cleanupInterruptedBundleRestores();

        expect((await database.getProjects()).map((project) => project.name), [
          '恢复东区',
          '恢复西区',
        ]);
        expect(pending.items, isEmpty);
        expect(rollback.projectIds, isEmpty);
      },
    );

    test(
      'completed bundle returns success when immediate finalization retry works',
      () async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        final pending = _FakeBundlePendingStore(clearFailuresRemaining: 1);
        final rollback = _FakeProjectRollback();
        final service = _bundleService(
          database: database,
          bundles: _FakeBundlePipeline(preview: _bundlePreview()),
          importer: _FakeProjectImporter(),
          pending: pending,
          rollback: rollback,
        );
        final prepared = await service.prepareRestore('/backups/bundle.zip');

        final results = await service.restorePrepared(
          prepared: prepared,
          projectNames: const {'p1': '恢复东区', 'p2': '恢复西区'},
        );

        expect(results.map((result) => result.projectName), ['恢复东区', '恢复西区']);
        expect((await database.getProjects()).map((project) => project.name), [
          '恢复东区',
          '恢复西区',
        ]);
        expect(pending.items, isEmpty);
        expect(rollback.projectIds, isEmpty);
      },
    );

    test(
      'completed bundle records success (not blocked) when finalization retry succeeds',
      () async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        final pending = _FakeBundlePendingStore(clearFailuresRemaining: 1);
        final rollback = _FakeProjectRollback();
        final diagnosticRoot = await Directory.systemTemp.createTemp(
          'sitemark-restore-retry-diag-',
        );
        addTearDown(() => diagnosticRoot.delete(recursive: true));
        final diagnosticStore = DiagnosticEventStore(
          directory: diagnosticRoot,
        );
        var generatedId = 0;
        final service = ProjectBundleService(
          database: database,
          bundles: _FakeBundlePipeline(preview: _bundlePreview()),
          importer: _FakeProjectImporter(),
          paths: _FakeBundlePaths(),
          files: _FakeBundleFiles(),
          pendingStore: pending,
          rollback: rollback,
          diagnostics: DiagnosticRecorder(diagnosticStore),
          idGenerator: () => 'retry-bundle-${generatedId++}',
        );
        final prepared = await service.prepareRestore('/backups/bundle.zip');

        final results = await service.restorePrepared(
          prepared: prepared,
          projectNames: const {'p1': '恢复东区', 'p2': '恢复西区'},
        );

        expect(results, hasLength(2));
        expect(pending.items, isEmpty);

        List<DiagnosticEvent> events = const [];
        for (var attempt = 0; attempt < 20 && events.isEmpty; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          events = await diagnosticStore.readRecent();
        }
        expect(events, hasLength(1));
        // Retry succeeded → the restore is fully committed, so the diagnostic
        // must be success, not blocked.
        expect(events.single.outcome, DiagnosticOutcome.success);
        expect(events.single.category, DiagnosticCategory.restore);
      },
    );

    test(
      'committing marker retries marker clear after tokens are already visible',
      () async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        await database.createProject(id: 'visible-project', name: '已提交项目');
        final pending = _FakeBundlePendingStore(throwOnClear: true)
          ..items.add(
            const PendingBundleRestore(
              bundleId: 'commit-bundle',
              stagingDirectory: '/staging/commit-bundle',
              plannedProjectIds: ['visible-project'],
              operationId: 'commit-operation',
              phase: PendingBundleRestorePhase.committing,
            ),
          );
        final rollback = _FakeProjectRollback();
        final service = _bundleService(
          database: database,
          bundles: _FakeBundlePipeline(),
          importer: _FakeProjectImporter(),
          pending: pending,
          rollback: rollback,
        );

        await service.cleanupInterruptedBundleRestores();

        expect(await database.projectById('visible-project'), isNotNull);
        expect(pending.items, hasLength(1));
        expect(rollback.projectIds, isEmpty);

        pending.throwOnClear = false;
        await service.cleanupInterruptedBundleRestores();

        expect(await database.projectById('visible-project'), isNotNull);
        expect(pending.items, isEmpty);
        expect(rollback.projectIds, isEmpty);
      },
    );

    test('deletion handoff refuses a mismatching restore token', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.createProject(
        id: 'protected-project',
        name: '保留项目',
        restoreOperationId: 'other-operation',
      );
      final deletionFiles = _DeletionFiles();
      final rollback = ProjectDeletionBundleRollback(
        database: database,
        deletions: ProjectDeletionService(
          database: database,
          capturePaths: _DeletionCapturePaths(),
          files: deletionFiles,
          pendingStore: _DeletionPendingStore(),
        ),
      );

      await rollback.handoff('protected-project', 'bundle-operation');

      expect(await database.projectById('protected-project'), isNotNull);
      expect(deletionFiles.deleted, isEmpty);
    });

    test(
      'bundle marker rewrite failure leaves the last valid generation readable',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'sitemark-bundle-marker-',
        );
        addTearDown(() => root.delete(recursive: true));
        final store = AppBundleRestorePendingStore(
          documentsDirectory: () async => root,
        );
        const planned = PendingBundleRestore(
          bundleId: 'atomic-bundle',
          stagingDirectory: '/staging/atomic-bundle',
          plannedProjectIds: ['p1'],
          operationId: 'atomic-operation',
        );
        await store.write(planned);

        final failedStore = AppBundleRestorePendingStore(
          documentsDirectory: () async => root,
          writer: _FailBeforeCommitMarkerWriter(),
        );
        await expectLater(
          failedStore.write(planned.withOwnedProject('p1')),
          throwsStateError,
        );

        var listed = await store.list();
        expect(listed, hasLength(1));
        expect(listed.single.ownedProjectIds, isEmpty);
        await store.write(planned.withOwnedProject('p1'));
        listed = await store.list();
        expect(listed.single.ownedProjectIds, ['p1']);
        expect(listed.single.revision, 1);
      },
    );

    test(
      'empty preparation marker round-trips through the app store',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'sitemark-empty-bundle-marker-',
        );
        addTearDown(() => root.delete(recursive: true));
        final store = AppBundleRestorePendingStore(
          documentsDirectory: () async => root,
        );
        const marker = PendingBundleRestore(
          bundleId: 'preparing-bundle',
          stagingDirectory: '/staging/preparing-bundle',
          plannedProjectIds: [],
          operationId: 'preparing-bundle',
          phase: PendingBundleRestorePhase.preparing,
        );

        await store.write(marker);

        final listed = await store.list();
        expect(listed, hasLength(1));
        expect(listed.single.plannedProjectIds, isEmpty);
        expect(listed.single.phase, PendingBundleRestorePhase.preparing);
      },
    );

    test('legacy bundle markers default to rollback-safe restoring phase', () {
      final legacy = PendingBundleRestore.fromJson(const {
        'bundleId': 'legacy',
        'stagingDirectory': '/staging/legacy',
        'plannedProjectIds': <String>[],
      });
      expect(legacy.phase, PendingBundleRestorePhase.restoring);
    });

    test(
      'rollback failure keeps the bundle marker for startup retry',
      () async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        await database.createProject(
          id: 'new-p1',
          name: '恢复东区',
          restoreOperationId: 'bundle-operation',
        );
        await database.createProject(
          id: 'new-p2',
          name: '恢复西区',
          restoreOperationId: 'bundle-operation',
        );
        final pending = _FakeBundlePendingStore()
          ..items.add(
            const PendingBundleRestore(
              bundleId: 'b1',
              stagingDirectory: '/staging/b1',
              plannedProjectIds: ['new-p1', 'new-p2'],
              ownedProjectIds: ['new-p1', 'new-p2'],
              operationId: 'bundle-operation',
            ),
          );
        final rollback = _FakeProjectRollback(failProjectId: 'new-p1');
        final service = _bundleService(
          database: database,
          bundles: _FakeBundlePipeline(),
          importer: _FakeProjectImporter(),
          pending: pending,
          rollback: rollback,
        );

        await service.cleanupInterruptedBundleRestores();

        expect(rollback.projectIds, ['new-p1', 'new-p2']);
        expect(pending.items, hasLength(1));
      },
    );

    test('staging cleanup failure keeps the marker for retry', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final pending = _FakeBundlePendingStore()
        ..items.add(
          const PendingBundleRestore(
            bundleId: 'b1',
            stagingDirectory: '/staging/b1',
            plannedProjectIds: ['new-p1', 'new-p2'],
            ownedProjectIds: ['new-p1', 'new-p2'],
          ),
        );
      final service = _bundleService(
        database: database,
        bundles: _FakeBundlePipeline(),
        importer: _FakeProjectImporter(),
        pending: pending,
        files: _FakeBundleFiles(failPath: '/staging/b1'),
      );

      await service.cleanupInterruptedBundleRestores();

      expect(pending.items, hasLength(1));
    });

    test(
      'preparation marker write failure creates no staging directory',
      () async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        final pending = _FakeBundlePendingStore(throwOnWrite: true);
        final files = _FakeBundleFiles();
        final importer = _FakeProjectImporter();
        final bundles = _FakeBundlePipeline(preview: _bundlePreview());
        final service = _bundleService(
          database: database,
          bundles: bundles,
          importer: importer,
          pending: pending,
          files: files,
        );
        await expectLater(
          service.prepareRestore('/backups/bundle.zip'),
          throwsA(isA<ProjectBundleRestoreException>()),
        );

        expect(importer.imports, isEmpty);
        expect(bundles.extractRequests, isEmpty);
        expect(files.ensureDirectories, isEmpty);
        expect(files.deletedTrees, isEmpty);
      },
    );

    test('create-directory failure retains preparation marker', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final pending = _FakeBundlePendingStore();
      final files = _FakeBundleFiles(failEnsure: true);
      final bundles = _FakeBundlePipeline(preview: _bundlePreview());
      final service = _bundleService(
        database: database,
        bundles: bundles,
        importer: _FakeProjectImporter(),
        pending: pending,
        files: files,
      );

      await expectLater(
        service.prepareRestore('/backups/bundle.zip'),
        throwsA(isA<ProjectBundleRestoreException>()),
      );

      expect(files.ensureDirectories, [
        '/imports/bundle-restore-bundle-prepare',
      ]);
      expect(bundles.extractRequests, isEmpty);
      expect(pending.items, hasLength(1));
      expect(pending.items.single.phase, PendingBundleRestorePhase.preparing);

      await service.cleanupInterruptedBundleRestores();
      expect(pending.items, isEmpty);
    });

    test('concurrent submit of one prepared restore is rejected', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final gate = Completer<void>();
      final importer = _FakeProjectImporter(importGate: gate);
      final service = _bundleService(
        database: database,
        bundles: _FakeBundlePipeline(preview: _bundlePreview()),
        importer: importer,
      );
      final prepared = await service.prepareRestore('/backups/bundle.zip');

      final first = service.restorePrepared(
        prepared: prepared,
        projectNames: const {'p1': '东区', 'p2': '西区'},
      );
      while (importer.imports.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      final secondExpectation = expectLater(
        service.restorePrepared(
          prepared: prepared,
          projectNames: const {'p1': '东区', 'p2': '西区'},
        ),
        throwsA(isA<ProjectBundleRestoreException>()),
      );
      gate.complete();

      await first;
      await secondExpectation;
    });

    test(
      'sequential reuse cannot roll back first successful projects',
      () async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        final pending = _FakeBundlePendingStore();
        final importer = _DatabaseProjectImporter(database);
        final deletionFiles = _DeletionFiles();
        final deletions = ProjectDeletionService(
          database: database,
          capturePaths: _DeletionCapturePaths(),
          files: deletionFiles,
          pendingStore: _DeletionPendingStore(),
        );
        final service = _bundleService(
          database: database,
          bundles: _FakeBundlePipeline(preview: _bundlePreview()),
          importer: importer,
          pending: pending,
          rollback: ProjectDeletionBundleRollback(
            database: database,
            deletions: deletions,
          ),
        );
        final prepared = await service.prepareRestore('/backups/bundle.zip');

        await service.restorePrepared(
          prepared: prepared,
          projectNames: const {'p1': '第一次东区', 'p2': '第一次西区'},
        );
        final writesAfterFirst = pending.writes;

        await expectLater(
          service.restorePrepared(
            prepared: prepared,
            projectNames: const {'p1': '第二次东区', 'p2': '第二次西区'},
          ),
          throwsA(isA<ProjectBundleRestoreException>()),
        );

        expect(await database.getProjects(), hasLength(2));
        expect(await database.getAllCaptures(), hasLength(2));
        expect(deletionFiles.deleted, isEmpty);
        expect(pending.writes, writesAfterFirst);
      },
    );

    test('caller prepared existing target is rejected before marker', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.createProject(id: 'existing-target', name: '原项目');
      final pending = _FakeBundlePendingStore();
      final service = _bundleService(
        database: database,
        bundles: _FakeBundlePipeline(),
        importer: _FakeProjectImporter(),
        pending: pending,
      );
      final prepared = PreparedProjectRestore(
        sourceZipPath: '/backups/single.zip',
        items: [
          PreparedProjectRestoreItem(
            sourceProjectId: 'single',
            targetProjectId: 'existing-target',
            archivePath: '/backups/single.zip',
            preview: _archivePreview('原项目'),
          ),
        ],
      );

      await expectLater(
        service.restorePrepared(
          prepared: prepared,
          projectNames: const {'single': '恢复项目'},
        ),
        throwsA(isA<ProjectBundleRestoreException>()),
      );

      expect((await database.projectById('existing-target'))?.name, '原项目');
      expect(pending.writes, 0);
    });

    test('unowned existing target is preserved with its marker', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.createProject(id: 'unowned-target', name: '保留项目');
      final pending = _FakeBundlePendingStore()
        ..items.add(
          const PendingBundleRestore(
            bundleId: 'b-unowned',
            stagingDirectory: '/staging/b-unowned',
            plannedProjectIds: ['unowned-target'],
          ),
        );
      final rollback = _FakeProjectRollback();
      final service = _bundleService(
        database: database,
        bundles: _FakeBundlePipeline(),
        importer: _FakeProjectImporter(),
        pending: pending,
        rollback: rollback,
      );

      await service.cleanupInterruptedBundleRestores();

      expect(await database.projectById('unowned-target'), isNotNull);
      expect(rollback.projectIds, isEmpty);
      expect((service.files as _FakeBundleFiles).deletedTrees, isEmpty);
      expect(pending.items, hasLength(1));
    });
  });
}

ProjectBundleService _bundleService({
  required AppDatabase database,
  required _FakeBundlePipeline bundles,
  required ProjectArchiveImporter importer,
  _FakeBundlePendingStore? pending,
  ProjectBundleRollback? rollback,
  _FakeBundleFiles? files,
}) {
  final store = pending ?? _FakeBundlePendingStore();
  if (importer is _FakeProjectImporter) {
    importer.pendingStore = store;
    importer.database = database;
  }
  var nextTarget = 0;
  return ProjectBundleService(
    database: database,
    bundles: bundles,
    importer: importer,
    paths: _FakeBundlePaths(),
    files: files ?? _FakeBundleFiles(),
    pendingStore: store,
    rollback: rollback ?? _FakeProjectRollback(),
    idGenerator: () {
      nextTarget++;
      return nextTarget == 1 ? 'bundle-prepare' : 'target-${nextTarget - 1}';
    },
  );
}

rust.ProjectBundlePreview _bundlePreview() => const rust.ProjectBundlePreview(
  schemaVersion: 1,
  createdAt: '2026-07-28T00:00:00Z',
  projects: [
    rust.ProjectBundleEntryPreview(
      projectId: 'p1',
      projectName: '东区',
      archivePath: 'projects/p1.zip',
      archiveSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    ),
    rust.ProjectBundleEntryPreview(
      projectId: 'p2',
      projectName: '西区',
      archivePath: 'projects/p2.zip',
      archiveSha256:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    ),
  ],
);

rust.ProjectArchivePreview _archivePreview(String name) =>
    rust.ProjectArchivePreview(
      schemaVersion: 2,
      projectName: name,
      omittedProcessingCount: 0,
      omittedFailedCount: 0,
      isPartial: false,
      includesOriginals: true,
      projectLifecycleStatus: 'active',
      projectIsPinned: false,
      photos: [
        rust.ArchivePhotoPreview(
          photoNumber: '$name-SM-20260728-001',
          hasOriginal: true,
          originalSha256: 'a' * 64,
          capturedAt: '2026-07-28 08:00:00 +08:00',
          workLocation: '现场',
          workContent: '检查',
          photographer: '张工',
        ),
      ],
      templates: const [],
    );

class _ExportCall {
  const _ExportCall(this.projectId, this.includeOriginals, this.outputZipPath);

  final String projectId;
  final bool includeOriginals;
  final String? outputZipPath;
}

class _RecordingProjectImagePipeline implements ImagePipeline {
  final requests = <rust.ExportProjectRequest>[];

  @override
  Future<rust.ExportProjectResult> export(
    rust.ExportProjectRequest request,
  ) async {
    requests.add(request);
    return rust.ExportProjectResult(
      outputZipPath: request.outputZipPath,
      archiveSha256: 'c' * 64,
      photoCount: request.photos.length,
    );
  }

  @override
  Future<rust.ProjectArchivePreview> readProjectArchive(String zipPath) =>
      throw UnimplementedError();

  @override
  Future<rust.ExtractedArchivePhoto> extractArchivePhoto(
    rust.ExtractArchivePhotoRequest request,
  ) => throw UnimplementedError();

  @override
  Future<rust.ExportProjectResult> exportSelection(
    rust.ExportSelectionRequest request,
  ) => throw UnimplementedError();

  @override
  Future<rust.RenderPhotoResult> render(rust.RenderPhotoRequest request) =>
      throw UnimplementedError();

  @override
  Future<String> sha256(String path) => throw UnimplementedError();
}

class _ProjectTemplateReadFailure extends QueryInterceptor {
  _ProjectTemplateReadFailure(this.projectId)
    : failure = SqliteException(
        extendedResultCode: SqlExtendedError.SQLITE_IOERR_READ,
        message: 'private-template-value',
        causingStatement: r'C:\private\database\sitemark.sqlite',
      );

  final String projectId;
  final SqliteException failure;
  bool enabled = false;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (enabled &&
        statement.toLowerCase().contains('capture_templates') &&
        args.contains(projectId)) {
      throw failure;
    }
    return super.runSelect(executor, statement, args);
  }
}

class _BundleCapturePaths implements CaptureOutputPaths {
  @override
  Future<String> renderedPhotoPath(String captureId) async =>
      '/rendered/$captureId.jpg';
}

class _BundleProjectExportPaths implements ProjectExportPaths {
  @override
  Future<String> projectZipPath(String projectId) async =>
      '/exports/$projectId.zip';
}

class _BundleSelectionPaths implements SelectionExportPaths {
  @override
  Future<String> selectionZipPath() async => '/exports/selection.zip';
}

class _FakeProjectExporter implements ProjectArchiveExporter {
  _FakeProjectExporter({this.failProjectId, this.failure});

  final String? failProjectId;
  final Object? failure;
  final requests = <_ExportCall>[];

  @override
  Future<rust.ExportProjectResult> exportProject({
    required String projectId,
    required bool includeOriginals,
    String? outputZipPath,
    DateTime? snapshotAt,
    int omittedProcessingCount = 0,
    int omittedFailedCount = 0,
  }) async {
    requests.add(_ExportCall(projectId, includeOriginals, outputZipPath));
    if (projectId == failProjectId) {
      throw failure ?? StateError('export failed');
    }
    return rust.ExportProjectResult(
      outputZipPath: outputZipPath ?? '/exports/$projectId.zip',
      archiveSha256: 'c' * 64,
      photoCount: 1,
    );
  }
}

class _FakeBundlePipeline implements ProjectBundlePipeline {
  _FakeBundlePipeline({
    this.preview,
    this.readFailure,
    this.onExtract,
    this.extractFailureAt,
  });

  final rust.ProjectBundlePreview? preview;
  final Object? readFailure;
  final void Function()? onExtract;
  final int? extractFailureAt;
  final exportRequests = <rust.ExportProjectBundleRequest>[];
  final extractRequests = <rust.ExtractProjectBundleEntryRequest>[];

  @override
  Future<rust.ExportProjectResult> exportBundle(
    rust.ExportProjectBundleRequest request,
  ) async {
    exportRequests.add(request);
    return rust.ExportProjectResult(
      outputZipPath: request.outputZipPath,
      archiveSha256: 'd' * 64,
      photoCount: request.projects.length,
    );
  }

  @override
  Future<void> extractBundleEntry(
    rust.ExtractProjectBundleEntryRequest request,
  ) async {
    onExtract?.call();
    extractRequests.add(request);
    if (extractRequests.length == extractFailureAt) {
      throw StateError('extract failed');
    }
  }

  @override
  Future<rust.ProjectBundlePreview> readBundle(String zipPath) async {
    if (readFailure case final failure?) throw failure;
    return preview ?? _bundlePreview();
  }
}

class _FakeBundlePaths implements ProjectBundlePaths {
  _FakeBundlePaths({this.failBackupPath = false});

  final bool failBackupPath;
  List<String> interruptedExportDirectories = const [];

  @override
  Future<String> backupZipPath(String operationId) async {
    if (failBackupPath) throw StateError('backup path failed');
    return '/exports/sitemark-backup-$operationId.zip';
  }

  @override
  Future<String> backupStagingArchivePath(String stagingDirectory) async =>
      '$stagingDirectory/sitemark-backup.tmp.zip';

  @override
  Future<List<String>> exportStagingDirectories() async =>
      interruptedExportDirectories;

  @override
  Future<String> exportStagingDirectory(String bundleId) async =>
      '/imports/bundle-export-$bundleId';

  @override
  Future<String> projectArchivePath(
    String stagingDirectory,
    String projectId,
  ) async => '$stagingDirectory/projects/$projectId.zip';

  @override
  Future<String> restoreStagingDirectory(String bundleId) async =>
      '/imports/bundle-restore-$bundleId';
}

class _FakeBundleFiles implements ProjectBundleFileSystem {
  _FakeBundleFiles({this.failPath, this.onEnsure, this.failEnsure = false});

  String? failPath;
  final void Function()? onEnsure;
  final bool failEnsure;
  final ensureDirectories = <String>[];
  final deletedTrees = <String>[];
  final committedFiles = <(String, String)>[];

  @override
  Future<void> commitFile(String sourcePath, String destinationPath) async {
    committedFiles.add((sourcePath, destinationPath));
  }

  @override
  Future<void> ensureDirectory(String path) async {
    ensureDirectories.add(path);
    onEnsure?.call();
    if (failEnsure) throw StateError('ensure failed');
  }

  @override
  Future<void> deleteTree(String path) async {
    deletedTrees.add(path);
    if (path == failPath) throw StateError('delete failed');
  }
}

class _FakeBundlePendingStore implements BundleRestorePendingStore {
  _FakeBundlePendingStore({
    this.throwOnWrite = false,
    this.throwOnClear = false,
    this.clearFailuresRemaining = 0,
    this.onWrite,
  });

  final bool throwOnWrite;
  bool throwOnClear;
  int clearFailuresRemaining;
  final void Function()? onWrite;
  final items = <PendingBundleRestore>[];
  final writtenPhases = <PendingBundleRestorePhase>[];
  var writes = 0;

  @override
  Future<void> clear(String bundleId) async {
    if (clearFailuresRemaining > 0) {
      clearFailuresRemaining--;
      throw StateError('one-shot marker clear failure');
    }
    if (throwOnClear) throw StateError('marker clear failed');
    items.removeWhere((item) => item.bundleId == bundleId);
  }

  @override
  Future<List<PendingBundleRestore>> list() async => List.of(items);

  @override
  Future<void> write(PendingBundleRestore pending) async {
    if (throwOnWrite) throw StateError('marker write failed');
    onWrite?.call();
    writes++;
    writtenPhases.add(pending.phase);
    items.removeWhere((item) => item.bundleId == pending.bundleId);
    items.add(pending);
  }
}

class _FakeProjectRollback implements ProjectBundleRollback {
  _FakeProjectRollback({this.failProjectId});

  final String? failProjectId;
  final projectIds = <String>[];

  @override
  Future<void> handoff(String projectId, String operationId) async {
    projectIds.add(projectId);
    if (projectId == failProjectId) throw StateError('rollback failed');
  }
}

class _IntegrationImportPipeline implements ImagePipeline {
  _IntegrationImportPipeline(this.preview);

  final rust.ProjectArchivePreview preview;

  @override
  Future<rust.ProjectArchivePreview> readProjectArchive(String zipPath) async =>
      preview;

  @override
  Future<rust.ExtractedArchivePhoto> extractArchivePhoto(
    rust.ExtractArchivePhotoRequest request,
  ) async => rust.ExtractedArchivePhoto(
    renderedPath: request.renderedDestination,
    originalPath: request.originalDestination,
  );

  @override
  Future<rust.ExportProjectResult> export(rust.ExportProjectRequest request) =>
      throw UnimplementedError();

  @override
  Future<rust.ExportProjectResult> exportSelection(
    rust.ExportSelectionRequest request,
  ) => throw UnimplementedError();

  @override
  Future<rust.RenderPhotoResult> render(rust.RenderPhotoRequest request) =>
      throw UnimplementedError();

  @override
  Future<String> sha256(String path) => throw UnimplementedError();
}

class _IntegrationCapturePaths implements CaptureOutputPaths {
  @override
  Future<String> renderedPhotoPath(String captureId) async =>
      '/rendered/$captureId.jpg';
}

class _IntegrationOriginalPaths implements OriginalPhotoPaths {
  @override
  Future<String> originalPhotoPath(String captureId) async =>
      '/originals/$captureId.jpg';
}

class _IntegrationStagingPaths implements ImportStagingPaths {
  @override
  Future<String> stagingDirectory(String projectId) async =>
      '/staging/$projectId';

  @override
  Future<String> stagedOriginalPath(String projectId, String captureId) async =>
      '/staging/$projectId/originals/$captureId.jpg';

  @override
  Future<String> stagedRenderedPath(String projectId, String captureId) async =>
      '/staging/$projectId/rendered/$captureId.jpg';
}

class _IntegrationImportPendingStore implements ImportPendingStore {
  final items = <PendingImport>[];

  @override
  Future<void> clearPending(String projectId) async {
    items.removeWhere((item) => item.projectId == projectId);
  }

  @override
  Future<List<PendingImport>> listPending() async => List.of(items);

  @override
  Future<void> writePending(PendingImport pending) async {
    items.removeWhere((item) => item.projectId == pending.projectId);
    items.add(pending);
  }
}

class _IntegrationImportCommitter implements ImportFileCommitter {
  final moves = <String>[];

  @override
  Future<void> deleteTree(String path) async {}

  @override
  Future<void> moveIntoPlace(String stagedPath, String finalPath) async {
    moves.add('$stagedPath -> $finalPath');
  }
}

class _IntegrationPrivateFiles implements PrivateFileStore {
  @override
  Future<void> deleteIfExists(String path) async {}

  @override
  Future<bool> exists(String path) async => true;
}

class _FakeProjectImporter implements ProjectArchiveImporter {
  _FakeProjectImporter({
    this.failSource,
    this.importGate,
    this.inspectFailure,
    this.importFailure,
    this.lifecycleByName = const {},
    this.pinByName = const {},
  });

  final String? failSource;
  final Completer<void>? importGate;
  final Object? inspectFailure;
  final Object? importFailure;
  final Map<String, ProjectLifecycleStatus> lifecycleByName;
  final Map<String, bool> pinByName;
  final inspected = <String>[];
  final imports = <String>[];
  _FakeBundlePendingStore? pendingStore;
  AppDatabase? database;
  bool markerSeenBeforeFirstImport = false;

  @override
  Future<rust.ProjectArchivePreview> inspect(String zipPath) async {
    inspected.add(zipPath);
    if (inspectFailure case final failure?) throw failure;
    final name = zipPath.contains('p2') ? '西区' : '东区';
    return _archivePreview(name);
  }

  @override
  Future<ProjectImportResult> importProject({
    required String zipPath,
    required String projectName,
    String? projectId,
    String? restoreOperationId,
    bool retainRestoreOwnership = false,
    void Function(int completed, int total)? onProgress,
  }) async {
    if (imports.isEmpty) {
      markerSeenBeforeFirstImport = pendingStore?.items.isNotEmpty ?? false;
    }
    imports.add(zipPath);
    await importGate?.future;
    if (zipPath.endsWith(failSource ?? '\u0000')) {
      throw importFailure ?? StateError('item import failed');
    }
    final status =
        lifecycleByName[projectName] ?? ProjectLifecycleStatus.active;
    final pinned = pinByName[projectName] ?? false;
    await database?.createProject(
      id: projectId!,
      name: projectName,
      restoreOperationId: restoreOperationId,
      lifecycleStatus: status,
      isPinned: pinned,
    );
    onProgress?.call(1, 1);
    return ProjectImportResult(
      projectId: projectId!,
      projectName: projectName,
      photoCount: 1,
      restoredOriginals: 1,
      lifecycleStatus: status,
      isPinned: pinned,
    );
  }
}

class _DatabaseProjectImporter implements ProjectArchiveImporter {
  _DatabaseProjectImporter(this.database);

  final AppDatabase database;

  @override
  Future<rust.ProjectArchivePreview> inspect(String zipPath) async {
    return _archivePreview(zipPath.contains('p2') ? '西区' : '东区');
  }

  @override
  Future<ProjectImportResult> importProject({
    required String zipPath,
    required String projectName,
    String? projectId,
    String? restoreOperationId,
    bool retainRestoreOwnership = false,
    void Function(int completed, int total)? onProgress,
  }) async {
    await database.createProject(
      id: projectId!,
      name: projectName,
      restoreOperationId: restoreOperationId,
    );
    await database.createPendingCapture(
      id: '$projectId-capture',
      projectId: projectId,
      originalPath: '/originals/$projectId.jpg',
      workLocation: '现场',
      workContent: '检查',
      photographer: '张工',
      watermarkLocaleCode: 'zh',
      locationResolution: 'resolved',
    );
    onProgress?.call(1, 1);
    return ProjectImportResult(
      projectId: projectId,
      projectName: projectName,
      photoCount: 1,
      restoredOriginals: 1,
      lifecycleStatus: ProjectLifecycleStatus.active,
      isPinned: false,
    );
  }
}

class _DeletionCapturePaths implements CaptureOutputPaths {
  @override
  Future<String> renderedPhotoPath(String captureId) async =>
      '/rendered/$captureId.jpg';
}

class _DeletionFiles implements PrivateFileStore {
  final deleted = <String>[];

  @override
  Future<void> deleteIfExists(String path) async {
    deleted.add(path);
  }

  @override
  Future<bool> exists(String path) async => true;
}

class _FailBeforeCommitMarkerWriter implements AtomicMarkerWriter {
  @override
  Future<void> write(File target, String contents) async {
    await File('${target.path}.tmp-power-loss').writeAsString('{', flush: true);
    throw StateError('simulated power loss before atomic rename');
  }
}

class _DeletionPendingStore implements ProjectDeletionPendingStore {
  @override
  Future<void> clear(String projectId) async {}

  @override
  Future<List<PendingProjectDeletion>> list() async => const [];

  @override
  Future<void> write(PendingProjectDeletion pending) async {}
}
