import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/project_deletion_service.dart';

void main() {
  test(
    'deleteProject removes private files and rows but never published URIs',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await _seedPublishedCapture(database);
      final files = _RecordingPrivateFileStore();
      final service = ProjectDeletionService(
        database: database,
        capturePaths: const _FakeCaptureOutputPaths(),
        files: files,
        pendingStore: _MemoryProjectDeletionPendingStore(),
      );

      final result = await service.deleteProject('project-1');

      expect(await database.projectById('project-1'), isNull);
      expect(await database.captureById('capture-1'), isNull);
      expect(
        files.deleted,
        containsAll(['/private/original.jpg', '/rendered/capture-1.jpg']),
      );
      expect(files.deleted, isNot(contains('content://media/published')));
      expect(result.cleanupPending, isFalse);
    },
  );

  test(
    'failed private cleanup keeps a marker, retries every path, then clears it',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await _seedPublishedCapture(database);
      final files = _RecordingPrivateFileStore()
        ..failOnceFor.add('/private/original.jpg');
      final pendingStore = _MemoryProjectDeletionPendingStore();
      final service = ProjectDeletionService(
        database: database,
        capturePaths: const _FakeCaptureOutputPaths(),
        files: files,
        pendingStore: pendingStore,
      );

      final result = await service.deleteProject('project-1');

      expect(result.cleanupPending, isTrue);
      expect(files.attemptedDeletes, [
        '/private/original.jpg',
        '/rendered/capture-1.jpg',
      ]);
      expect(pendingStore.pending, hasLength(1));

      await service.cleanupInterruptedDeletions();

      expect(files.attemptedDeletes, [
        '/private/original.jpg',
        '/rendered/capture-1.jpg',
        '/private/original.jpg',
        '/rendered/capture-1.jpg',
      ]);
      expect(pendingStore.pending, isEmpty);
    },
  );

  test(
    'preview reports the project name, all captures, and retained originals',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await _seedPublishedCapture(database);
      await database.createPendingCapture(
        id: 'capture-2',
        projectId: 'project-1',
        originalPath: '/private/already-cleared.jpg',
        workLocation: 'B 区',
        workContent: '复核',
        photographer: '李工',
        watermarkLocaleCode: 'zh',
      );
      await database.markOriginalDeleted('capture-2');
      final service = ProjectDeletionService(
        database: database,
        capturePaths: const _FakeCaptureOutputPaths(),
        files: _RecordingPrivateFileStore(),
        pendingStore: _MemoryProjectDeletionPendingStore(),
      );

      final preview = await service.preview('project-1');

      expect(preview.projectName, '东区厂房改造');
      expect(preview.captureCount, 2);
      expect(preview.privateOriginalCount, 1);
    },
  );

  test('pending store writes only project ID and private file paths', () async {
    final documents = await Directory.systemTemp.createTemp(
      'sitemark-deletion-store-',
    );
    addTearDown(() => documents.delete(recursive: true));
    final store = AppProjectDeletionPendingStore(
      documentsDirectory: () async => documents,
    );
    const pending = PendingProjectDeletion(
      projectId: 'project-1',
      paths: ['/private/original.jpg', '/rendered/capture-1.jpg'],
    );

    await store.write(pending);

    final marker = File(
      '${documents.path}${Platform.pathSeparator}cleanup'
      '${Platform.pathSeparator}project-project-1.json',
    );
    expect(jsonDecode(await marker.readAsString()), {
      'projectId': 'project-1',
      'paths': ['/private/original.jpg', '/rendered/capture-1.jpg'],
    });
    final restored = (await store.list()).single;
    expect(restored.projectId, pending.projectId);
    expect(restored.paths, pending.paths);

    await store.clear('project-1');

    expect(await marker.exists(), isFalse);
  });

  test(
    'marker clear failure reports pending cleanup after rows are removed',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await _seedPublishedCapture(database);
      final pendingStore = _MemoryProjectDeletionPendingStore()
        ..throwOnClear = true;
      final service = ProjectDeletionService(
        database: database,
        capturePaths: const _FakeCaptureOutputPaths(),
        files: _RecordingPrivateFileStore(),
        pendingStore: pendingStore,
      );

      final result = await service.deleteProject('project-1');

      expect(await database.projectById('project-1'), isNull);
      expect(result.cleanupPending, isTrue);
      expect(pendingStore.pending, hasLength(1));
    },
  );

  test(
    'cascade failure leaves the project and private files untouched on cleanup',
    () async {
      final database = _FailingCascadeDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await _seedPublishedCapture(database);
      final files = _RecordingPrivateFileStore();
      final pendingStore = _MemoryProjectDeletionPendingStore();
      final service = ProjectDeletionService(
        database: database,
        capturePaths: const _FakeCaptureOutputPaths(),
        files: files,
        pendingStore: pendingStore,
      );

      await expectLater(
        service.deleteProject('project-1'),
        throwsA(isA<StateError>()),
      );
      expect(await database.projectById('project-1'), isNotNull);
      expect(await database.captureById('capture-1'), isNotNull);
      expect(files.attemptedDeletes, isEmpty);
      expect(pendingStore.pending, hasLength(1));

      await service.cleanupInterruptedDeletions();

      expect(await database.projectById('project-1'), isNotNull);
      expect(await database.captureById('capture-1'), isNotNull);
      expect(files.attemptedDeletes, isEmpty);
      expect(pendingStore.pending, hasLength(1));
    },
  );
}

Future<void> _seedPublishedCapture(AppDatabase database) async {
  await database.createProject(id: 'project-1', name: '东区厂房改造');
  await database.createPendingCapture(
    id: 'capture-1',
    projectId: 'project-1',
    originalPath: '/private/original.jpg',
    workLocation: 'A 区',
    workContent: '检查',
    photographer: '张工',
    watermarkLocaleCode: 'zh',
  );
  await database.markCaptured(
    captureId: 'capture-1',
    capturedAt: DateTime(2026, 7, 28, 9),
  );
  await database.resolveCaptureLocation(
    captureId: 'capture-1',
    resolution: 'unavailable',
    outcome: 'unavailable',
  );
  await database.markRendering(
    captureId: 'capture-1',
    originalSha256: 'a' * 64,
  );
  await database.markReady(
    captureId: 'capture-1',
    publishedUri: 'content://media/published',
  );
}

class _FakeCaptureOutputPaths implements CaptureOutputPaths {
  const _FakeCaptureOutputPaths();

  @override
  Future<String> renderedPhotoPath(String captureId) async =>
      '/rendered/$captureId.jpg';
}

class _RecordingPrivateFileStore implements PrivateFileStore {
  final attemptedDeletes = <String>[];
  final deleted = <String>[];
  final failOnceFor = <String>{};

  @override
  Future<void> deleteIfExists(String path) async {
    attemptedDeletes.add(path);
    if (failOnceFor.remove(path)) {
      throw StateError('simulated delete failure');
    }
    deleted.add(path);
  }

  @override
  Future<bool> exists(String path) async => true;
}

class _MemoryProjectDeletionPendingStore
    implements ProjectDeletionPendingStore {
  final pending = <PendingProjectDeletion>[];
  var throwOnClear = false;

  @override
  Future<void> clear(String projectId) async {
    if (throwOnClear) throw StateError('simulated marker clear failure');
    pending.removeWhere((entry) => entry.projectId == projectId);
  }

  @override
  Future<List<PendingProjectDeletion>> list() async => List.of(pending);

  @override
  Future<void> write(PendingProjectDeletion item) async {
    pending.add(item);
  }
}

class _FailingCascadeDatabase extends AppDatabase {
  _FailingCascadeDatabase(super.executor) : super.forTesting();

  @override
  Future<int> deleteProjectCascade(String projectId) {
    throw StateError('simulated cascade failure');
  }
}
