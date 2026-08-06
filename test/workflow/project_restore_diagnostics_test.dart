import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/diagnostics/diagnostic_event.dart';
import 'package:sitemark/diagnostics/diagnostic_event_store.dart';
import 'package:sitemark/diagnostics/diagnostic_recorder.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/project_bundle_service.dart';
import 'package:sitemark/workflow/project_import_service.dart';
import 'package:sitemark/src/rust/api/image_core.dart' as rust;

class _FailingBundlePipeline implements ProjectBundlePipeline {
  @override
  Future<rust.ExportProjectResult> exportBundle(
    rust.ExportProjectBundleRequest request,
  ) => throw UnimplementedError();

  @override
  Future<void> extractBundleEntry(
    rust.ExtractProjectBundleEntryRequest request,
  ) => throw UnimplementedError();

  @override
  Future<rust.ProjectBundlePreview> readBundle(String zipPath) async {
    throw const ImagePipelineException(
      ImagePipelineFailureKind.invalidData,
      'invalid_data: not a site mark backup',
    );
  }
}

class _FailingImporter implements ProjectArchiveImporter {
  @override
  Future<ProjectImportResult> importProject({
    required String zipPath,
    required String projectName,
    String? projectId,
    String? restoreOperationId,
    bool retainRestoreOwnership = false,
    void Function(int completed, int total)? onProgress,
  }) => throw UnimplementedError();

  @override
  Future<rust.ProjectArchivePreview> inspect(String zipPath) async {
    throw const ImagePipelineException(
      ImagePipelineFailureKind.invalidData,
      'invalid_data: not a project archive',
    );
  }
}

class _UnusedPaths implements ProjectBundlePaths {
  @override
  Future<String> backupStagingArchivePath(String stagingDirectory) async =>
      '/tmp/x';

  @override
  Future<String> backupZipPath(String operationId) async => '/tmp/x.zip';

  @override
  Future<String> exportStagingDirectory(String bundleId) async => '/tmp/s';

  @override
  Future<List<String>> exportStagingDirectories() async => const [];

  @override
  Future<String> projectArchivePath(
    String stagingDirectory,
    String projectId,
  ) async => '/tmp/p.zip';

  @override
  Future<String> restoreStagingDirectory(String bundleId) async => '/tmp/r';
}

class _UnusedFiles implements ProjectBundleFileSystem {
  @override
  Future<void> commitFile(String sourcePath, String destinationPath) async {}

  @override
  Future<void> deleteTree(String path) async {}

  @override
  Future<void> ensureDirectory(String path) async {}
}

class _EmptyPendingStore implements BundleRestorePendingStore {
  @override
  Future<void> clear(String bundleId) async {}

  @override
  Future<List<PendingBundleRestore>> list() async => const [];

  @override
  Future<void> write(PendingBundleRestore pending) async {}
}

class _UnusedRollback implements ProjectBundleRollback {
  @override
  Future<void> handoff(String projectId, String operationId) async {}
}

void main() {
  test(
    'prepareRestore records restore diagnostics without path leakage',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final diagnosticRoot = await Directory.systemTemp.createTemp(
        'sitemark-restore-diag-',
      );
      addTearDown(() => diagnosticRoot.delete(recursive: true));
      final store = DiagnosticEventStore(directory: diagnosticRoot);
      final service = ProjectBundleService(
        database: database,
        bundles: _FailingBundlePipeline(),
        importer: _FailingImporter(),
        paths: _UnusedPaths(),
        files: _UnusedFiles(),
        pendingStore: _EmptyPendingStore(),
        rollback: _UnusedRollback(),
        diagnostics: DiagnosticRecorder(store),
      );

      await expectLater(
        service.prepareRestore('/private/secret-backup.zip'),
        throwsA(isA<ProjectBundleRestoreException>()),
      );

      List<DiagnosticEvent> events = const [];
      for (var attempt = 0; attempt < 20 && events.isEmpty; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        events = await store.readRecent();
      }

      expect(events, hasLength(1));
      final event = events.single;
      expect(event.category, DiagnosticCategory.restore);
      expect(event.outcome, DiagnosticOutcome.failed);
      expect(event.code, DiagnosticCode.invalidArchive);
      expect(event.encode(), isNot(contains('/private/')));
      expect(event.encode(), isNot(contains('secret-backup')));
    },
  );
}
