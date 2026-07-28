import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/src/rust/api/image_core.dart' as rust;
import 'package:sitemark/workflow/project_bundle_service.dart';
import 'package:sitemark/workflow/project_export_service.dart';
import 'package:sitemark/workflow/project_import_service.dart';

void main() {
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
      'one selected project keeps the existing single-project archive',
      () async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        final exporter = _FakeProjectExporter();
        final bundles = _FakeBundlePipeline();
        final service = ProjectBackupService(
          projectExporter: exporter,
          database: database,
          bundles: bundles,
          paths: _FakeBundlePaths(),
          files: _FakeBundleFiles(),
          idGenerator: () => 'bundle-1',
        );

        final result = await service.exportProjects(
          projectIds: const ['p1'],
          includeOriginals: true,
        );

        expect(result.kind, ProjectBackupKind.singleProject);
        expect(result.outputZipPath, '/exports/p1.zip');
        expect(exporter.requests.single.outputZipPath, isNull);
        expect(bundles.exportRequests, isEmpty);
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
        expect(result.outputZipPath, '/exports/sitemark-backup.zip');
        expect(exporter.requests.map((request) => request.outputZipPath), [
          '/imports/bundle-export-bundle-1/projects/p1.zip',
          '/imports/bundle-export-bundle-1/projects/p2.zip',
        ]);
        expect(bundles.exportRequests.single.projects, hasLength(2));
        expect(bundles.exportRequests.single.projects[0].projectName, '东区');
        expect(progress, ['1/3', '2/3', '3/3']);
        expect(files.deletedTrees, ['/imports/bundle-export-bundle-1']);
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
    });
  });

  group('ProjectBundleService', () {
    test(
      'prepare validates, extracts and previews every inner archive',
      () async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        final bundles = _FakeBundlePipeline(preview: _bundlePreview());
        final importer = _FakeProjectImporter();
        final service = _bundleService(
          database: database,
          bundles: bundles,
          importer: importer,
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
      },
    );

    test('batch name conflicts are rejected before first import', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.createProject(id: 'existing', name: '已有项目');
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
        throwsA(isA<ProjectBundleRestoreException>()),
      );
      await expectLater(
        service.restorePrepared(
          prepared: prepared,
          projectNames: const {'p1': 'A/B', 'p2': 'A:B'},
        ),
        throwsA(isA<ProjectBundleRestoreException>()),
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
        throwsA(isA<ProjectBundleRestoreException>()),
      );

      expect(rollback.projectIds, ['target-1', 'target-2']);
      expect(pending.items, isEmpty);
      expect(importer.markerSeenBeforeFirstImport, isTrue);
    });

    test('restore progress is monotonic across projects', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final service = _bundleService(
        database: database,
        bundles: _FakeBundlePipeline(preview: _bundlePreview()),
        importer: _FakeProjectImporter(),
      );
      final prepared = await service.prepareRestore('/backups/bundle.zip');
      final progress = <String>[];

      await service.restorePrepared(
        prepared: prepared,
        projectNames: const {'p1': '东区', 'p2': '西区'},
        onProgress: (completed, total) => progress.add('$completed/$total'),
      );

      expect(progress, ['1/2', '2/2']);
    });

    test(
      'interrupted cleanup attempts every planned id before clearing',
      () async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        final pending = _FakeBundlePendingStore()
          ..items.add(
            const PendingBundleRestore(
              bundleId: 'b1',
              stagingDirectory: '/staging/b1',
              plannedProjectIds: ['new-p1', 'new-p2'],
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
      'rollback failure keeps the bundle marker for startup retry',
      () async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        final pending = _FakeBundlePendingStore()
          ..items.add(
            const PendingBundleRestore(
              bundleId: 'b1',
              stagingDirectory: '/staging/b1',
              plannedProjectIds: ['new-p1', 'new-p2'],
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
  });
}

ProjectBundleService _bundleService({
  required AppDatabase database,
  required _FakeBundlePipeline bundles,
  required _FakeProjectImporter importer,
  _FakeBundlePendingStore? pending,
  _FakeProjectRollback? rollback,
  _FakeBundleFiles? files,
}) {
  final store = pending ?? _FakeBundlePendingStore();
  importer.pendingStore = store;
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

class _ExportCall {
  const _ExportCall(this.projectId, this.includeOriginals, this.outputZipPath);

  final String projectId;
  final bool includeOriginals;
  final String? outputZipPath;
}

class _FakeProjectExporter implements ProjectArchiveExporter {
  _FakeProjectExporter({this.failProjectId});

  final String? failProjectId;
  final requests = <_ExportCall>[];

  @override
  Future<rust.ExportProjectResult> exportProject({
    required String projectId,
    required bool includeOriginals,
    String? outputZipPath,
  }) async {
    requests.add(_ExportCall(projectId, includeOriginals, outputZipPath));
    if (projectId == failProjectId) throw StateError('export failed');
    return rust.ExportProjectResult(
      outputZipPath: outputZipPath ?? '/exports/$projectId.zip',
      archiveSha256: 'c' * 64,
      photoCount: 1,
    );
  }
}

class _FakeBundlePipeline implements ProjectBundlePipeline {
  _FakeBundlePipeline({this.preview, this.readFailure});

  final rust.ProjectBundlePreview? preview;
  final Object? readFailure;
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
    extractRequests.add(request);
  }

  @override
  Future<rust.ProjectBundlePreview> readBundle(String zipPath) async {
    if (readFailure case final failure?) throw failure;
    return preview ?? _bundlePreview();
  }
}

class _FakeBundlePaths implements ProjectBundlePaths {
  @override
  Future<String> backupZipPath() async => '/exports/sitemark-backup.zip';

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
  _FakeBundleFiles({this.failPath});

  final String? failPath;
  final deletedTrees = <String>[];

  @override
  Future<void> deleteTree(String path) async {
    deletedTrees.add(path);
    if (path == failPath) throw StateError('delete failed');
  }
}

class _FakeBundlePendingStore implements BundleRestorePendingStore {
  final items = <PendingBundleRestore>[];

  @override
  Future<void> clear(String bundleId) async {
    items.removeWhere((item) => item.bundleId == bundleId);
  }

  @override
  Future<List<PendingBundleRestore>> list() async => List.of(items);

  @override
  Future<void> write(PendingBundleRestore pending) async {
    items.add(pending);
  }
}

class _FakeProjectRollback implements ProjectBundleRollback {
  _FakeProjectRollback({this.failProjectId});

  final String? failProjectId;
  final projectIds = <String>[];

  @override
  Future<void> handoff(String projectId) async {
    projectIds.add(projectId);
    if (projectId == failProjectId) throw StateError('rollback failed');
  }
}

class _FakeProjectImporter implements ProjectArchiveImporter {
  _FakeProjectImporter({this.failSource});

  final String? failSource;
  final inspected = <String>[];
  final imports = <String>[];
  _FakeBundlePendingStore? pendingStore;
  bool markerSeenBeforeFirstImport = false;

  @override
  Future<rust.ProjectArchivePreview> inspect(String zipPath) async {
    inspected.add(zipPath);
    final name = zipPath.contains('p2') ? '西区' : '东区';
    return rust.ProjectArchivePreview(
      schemaVersion: 2,
      projectName: name,
      includesOriginals: true,
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
    );
  }

  @override
  Future<ProjectImportResult> importProject({
    required String zipPath,
    required String projectName,
    String? projectId,
    void Function(int completed, int total)? onProgress,
  }) async {
    if (imports.isEmpty) {
      markerSeenBeforeFirstImport = pendingStore?.items.isNotEmpty ?? false;
    }
    imports.add(zipPath);
    if (zipPath.endsWith(failSource ?? '\u0000')) {
      throw StateError('item import failed');
    }
    onProgress?.call(1, 1);
    return ProjectImportResult(
      projectId: projectId!,
      projectName: projectName,
      photoCount: 1,
      restoredOriginals: 1,
    );
  }
}
