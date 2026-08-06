import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/diagnostics/diagnostic_event.dart';
import 'package:sitemark/diagnostics/diagnostic_event_store.dart';
import 'package:sitemark/diagnostics/diagnostic_recorder.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/project_deletion_service.dart';
import 'package:sitemark/workflow/project_import_service.dart';

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
      '${Platform.pathSeparator}${_markerName('project-1', 0)}',
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
    'interrupted or corrupt next generation keeps the last valid marker',
    () async {
      final documents = await Directory.systemTemp.createTemp(
        'sitemark-deletion-generations-',
      );
      addTearDown(() => documents.delete(recursive: true));
      final store = AppProjectDeletionPendingStore(
        documentsDirectory: () async => documents,
      );
      const original = PendingProjectDeletion(
        projectId: 'project-1',
        paths: ['/private/original-a.jpg'],
      );
      await store.write(original);

      final interruptedStore = AppProjectDeletionPendingStore(
        documentsDirectory: () async => documents,
        writer: _FailBeforeCommitMarkerWriter(),
      );
      await expectLater(
        interruptedStore.write(
          const PendingProjectDeletion(
            projectId: 'project-1',
            paths: ['/private/original-b.jpg'],
          ),
        ),
        throwsStateError,
      );
      final cleanup = Directory(
        '${documents.path}${Platform.pathSeparator}cleanup',
      );
      await File(
        '${cleanup.path}${Platform.pathSeparator}${_markerName('project-1', 1)}',
      ).writeAsString('{', flush: true);

      final listed = await store.list();

      expect(listed, hasLength(1));
      expect(listed.single.projectId, 'project-1');
      expect(listed.single.paths, original.paths);
    },
  );

  test('completed next generation replaces the previous marker', () async {
    final documents = await Directory.systemTemp.createTemp(
      'sitemark-deletion-next-generation-',
    );
    addTearDown(() => documents.delete(recursive: true));
    final store = AppProjectDeletionPendingStore(
      documentsDirectory: () async => documents,
    );
    await store.write(
      const PendingProjectDeletion(
        projectId: 'project-1',
        paths: ['/private/original-a.jpg'],
      ),
    );

    await store.write(
      const PendingProjectDeletion(
        projectId: 'project-1',
        paths: ['/private/original-b.jpg'],
      ),
    );

    final listed = await store.list();
    expect(listed, hasLength(1));
    expect(listed.single.paths, ['/private/original-b.jpg']);
    final cleanup = Directory(
      '${documents.path}${Platform.pathSeparator}cleanup',
    );
    final generations = await cleanup
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .length;
    expect(generations, 2);
  });

  test(
    'clear removes every project generation but keeps unrelated markers',
    () async {
      final documents = await Directory.systemTemp.createTemp(
        'sitemark-deletion-clear-generations-',
      );
      addTearDown(() => documents.delete(recursive: true));
      final store = AppProjectDeletionPendingStore(
        documentsDirectory: () async => documents,
      );
      await store.write(
        const PendingProjectDeletion(
          projectId: 'project-1',
          paths: ['/private/original-a.jpg'],
        ),
      );
      await store.write(
        const PendingProjectDeletion(
          projectId: 'project-1',
          paths: ['/private/original-b.jpg'],
        ),
      );
      await store.write(
        const PendingProjectDeletion(
          projectId: 'other-project',
          paths: ['/private/other.jpg'],
        ),
      );

      await store.clear('project-1');

      final listed = await store.list();
      expect(listed, hasLength(1));
      expect(listed.single.projectId, 'other-project');
      final cleanup = Directory(
        '${documents.path}${Platform.pathSeparator}cleanup',
      );
      final names = await cleanup
          .list()
          .where((entity) => entity is File)
          .map((entity) => entity.uri.pathSegments.last)
          .toList();
      expect(names, [_markerName('other-project', 0)]);
    },
  );

  test(
    'corrupt-only marker is reported and recovers with a later generation',
    () async {
      final documents = await Directory.systemTemp.createTemp(
        'sitemark-deletion-corrupt-only-',
      );
      addTearDown(() => documents.delete(recursive: true));
      final cleanup = Directory(
        '${documents.path}${Platform.pathSeparator}cleanup',
      );
      await cleanup.create(recursive: true);
      await File(
        '${cleanup.path}${Platform.pathSeparator}${_markerName('project-1', 0)}',
      ).writeAsString('{', flush: true);
      final store = AppProjectDeletionPendingStore(
        documentsDirectory: () async => documents,
      );

      await expectLater(
        store.list(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('project-1'),
          ),
        ),
      );

      const recovered = PendingProjectDeletion(
        projectId: 'project-1',
        paths: ['/private/recovered.jpg'],
      );
      await store.write(recovered);
      final listed = await store.list();
      expect(listed, hasLength(1));
      expect(listed.single.paths, recovered.paths);
    },
  );

  test('legacy marker remains readable and clearable', () async {
    final documents = await Directory.systemTemp.createTemp(
      'sitemark-deletion-legacy-',
    );
    addTearDown(() => documents.delete(recursive: true));
    final cleanup = Directory(
      '${documents.path}${Platform.pathSeparator}cleanup',
    );
    await cleanup.create(recursive: true);
    final legacy = File(
      '${cleanup.path}${Platform.pathSeparator}project-project-1.json',
    );
    await legacy.writeAsString(
      jsonEncode({
        'projectId': 'project-1',
        'paths': ['/private/legacy.jpg'],
      }),
      flush: true,
    );
    final store = AppProjectDeletionPendingStore(
      documentsDirectory: () async => documents,
    );

    final listed = await store.list();
    expect(listed.single.paths, ['/private/legacy.jpg']);

    await store.clear('project-1');
    expect(await legacy.exists(), isFalse);
  });

  test(
    'colliding legacy-safe IDs keep separate generations and clear',
    () async {
      final documents = await Directory.systemTemp.createTemp(
        'sitemark-deletion-collision-',
      );
      addTearDown(() => documents.delete(recursive: true));
      final store = AppProjectDeletionPendingStore(
        documentsDirectory: () async => documents,
      );
      await store.write(
        const PendingProjectDeletion(
          projectId: 'a/b',
          paths: ['/private/slash-a.jpg'],
        ),
      );
      await store.write(
        const PendingProjectDeletion(
          projectId: 'a?b',
          paths: ['/private/question.jpg'],
        ),
      );
      await store.write(
        const PendingProjectDeletion(
          projectId: 'a/b',
          paths: ['/private/slash-b.jpg'],
        ),
      );

      final listed = await store.list();
      expect(
        {for (final pending in listed) pending.projectId: pending.paths},
        {
          'a/b': ['/private/slash-b.jpg'],
          'a?b': ['/private/question.jpg'],
        },
      );

      await store.clear('a/b');

      final remaining = await store.list();
      expect(remaining, hasLength(1));
      expect(remaining.single.projectId, 'a?b');
      expect(remaining.single.paths, ['/private/question.jpg']);
    },
  );

  test(
    'legacy project ID ending in revision text is not a generation',
    () async {
      final documents = await Directory.systemTemp.createTemp(
        'sitemark-deletion-r-suffix-',
      );
      addTearDown(() => documents.delete(recursive: true));
      final cleanup = Directory(
        '${documents.path}${Platform.pathSeparator}cleanup',
      );
      await cleanup.create(recursive: true);
      final legacy = File(
        '${cleanup.path}${Platform.pathSeparator}project-foo-r3.json',
      );
      await legacy.writeAsString(
        jsonEncode({
          'projectId': 'foo-r3',
          'paths': ['/private/legacy-r3.jpg'],
        }),
        flush: true,
      );
      final store = AppProjectDeletionPendingStore(
        documentsDirectory: () async => documents,
      );

      final listed = await store.list();
      expect(listed, hasLength(1));
      expect(listed.single.projectId, 'foo-r3');
      expect(listed.single.paths, ['/private/legacy-r3.jpg']);

      await store.clear('foo');
      expect(await legacy.exists(), isTrue);
      await store.clear('foo-r3');
      expect(await legacy.exists(), isFalse);
    },
  );

  test(
    'previous generation filename remains readable by JSON identity',
    () async {
      final documents = await Directory.systemTemp.createTemp(
        'sitemark-deletion-previous-generation-',
      );
      addTearDown(() => documents.delete(recursive: true));
      final cleanup = Directory(
        '${documents.path}${Platform.pathSeparator}cleanup',
      );
      await cleanup.create(recursive: true);
      final previousGeneration = File(
        '${cleanup.path}${Platform.pathSeparator}project-foo-r3.json',
      );
      await previousGeneration.writeAsString(
        jsonEncode({
          'projectId': 'foo',
          'paths': ['/private/previous-r3.jpg'],
        }),
        flush: true,
      );
      final store = AppProjectDeletionPendingStore(
        documentsDirectory: () async => documents,
      );

      final listed = await store.list();
      expect(listed, hasLength(1));
      expect(listed.single.projectId, 'foo');
      expect(listed.single.paths, ['/private/previous-r3.jpg']);

      await store.clear('foo-r3');
      expect(await previousGeneration.exists(), isTrue);
      await store.clear('foo');
      expect(await previousGeneration.exists(), isFalse);
    },
  );

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

  test(
    'deleteProject records success diagnostics without path details',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await _seedPublishedCapture(database);
      final diagnosticRoot = await Directory.systemTemp.createTemp(
        'sitemark-deletion-diag-',
      );
      addTearDown(() async {
        if (await diagnosticRoot.exists()) {
          await diagnosticRoot.delete(recursive: true);
        }
      });
      final store = DiagnosticEventStore(directory: diagnosticRoot);
      final service = ProjectDeletionService(
        database: database,
        capturePaths: const _FakeCaptureOutputPaths(),
        files: _RecordingPrivateFileStore(),
        pendingStore: _MemoryProjectDeletionPendingStore(),
        diagnostics: DiagnosticRecorder(store),
      );

      final result = await service.deleteProject('project-1');
      List<DiagnosticEvent> events = const [];
      for (var attempt = 0; attempt < 20 && events.isEmpty; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        events = await store.readRecent();
      }

      expect(result.cleanupPending, isFalse);
      expect(events, hasLength(1));
      final event = events.single;
      expect(event.category, DiagnosticCategory.deletion);
      expect(event.outcome, DiagnosticOutcome.success);
      expect(event.code, DiagnosticCode.none);
      expect(event.count, 1);
      expect(event.encode(), isNot(contains('/private/')));
      expect(event.encode(), isNot(contains('project-1')));
    },
  );

  test('cascade failure records failed deletion diagnostics', () async {
    final database = _FailingCascadeDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await _seedPublishedCapture(database);
    final diagnosticRoot = await Directory.systemTemp.createTemp(
      'sitemark-deletion-diag-fail-',
    );
    addTearDown(() async {
      if (await diagnosticRoot.exists()) {
        await diagnosticRoot.delete(recursive: true);
      }
    });
    final store = DiagnosticEventStore(directory: diagnosticRoot);
    final service = ProjectDeletionService(
      database: database,
      capturePaths: const _FakeCaptureOutputPaths(),
      files: _RecordingPrivateFileStore(),
      pendingStore: _MemoryProjectDeletionPendingStore(),
      diagnostics: DiagnosticRecorder(store),
    );

    await expectLater(
      service.deleteProject('project-1'),
      throwsA(isA<StateError>()),
    );
    List<DiagnosticEvent> events = const [];
    for (var attempt = 0; attempt < 20 && events.isEmpty; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      events = await store.readRecent();
    }

    expect(events, hasLength(1));
    final event = events.single;
    expect(event.category, DiagnosticCategory.deletion);
    expect(event.outcome, DiagnosticOutcome.failed);
    expect(event.code, DiagnosticCode.unexpected);
    expect(event.encode(), isNot(contains('simulated cascade')));
  });
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

String _markerName(String projectId, int revision) {
  final encoded = base64Url.encode(utf8.encode(projectId)).replaceAll('=', '');
  return 'deletion-v2-$encoded-g$revision.json';
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

class _FailBeforeCommitMarkerWriter implements AtomicMarkerWriter {
  @override
  Future<void> write(File target, String contents) async {
    await File('${target.path}.tmp-power-loss').writeAsString('{', flush: true);
    throw StateError('simulated power loss before atomic rename');
  }
}
