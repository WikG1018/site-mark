import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/background/capture_background_scheduler.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/domain/project_lifecycle.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/capture_location_coordinator.dart';
import 'package:sitemark/workflow/capture_workflow.dart';
import 'package:sitemark/workflow/gallery_import_service.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

void main() {
  late AppDatabase database;
  late _Gallery api;
  late _Scheduler scheduler;
  late _Files files;
  late GalleryImportService service;
  const draft = CaptureDraft(
    projectId: 'p',
    projectName: 'Test',
    workLocation: 'A',
    workContent: 'Inspection',
    photographer: 'B',
    watermarkLocaleCode: 'en',
  );
  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.createProject(id: 'p', name: 'Test');
    api = _Gallery();
    scheduler = _Scheduler();
    files = _Files();
    var id = 0;
    service = GalleryImportService(
      database: database,
      api: api,
      paths: _Paths(),
      scheduler: scheduler,
      files: files,
      locations: CaptureLocationCoordinator(
        database: database,
        platform: _Platform(),
        scheduler: scheduler,
      ),
      idFactory: () => 'c${++id}',
      now: () => DateTime(2026, 10, 22),
    );
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await database.close();
  });
  test('cancel does not create a record', () async {
    final result = await service.pickAndImport(draft);
    expect(result.cancelled, isTrue);
    expect(await database.capturesForProject('p'), isEmpty);
  });
  test(
    'database commit failure keeps the copy task for startup recovery',
    () async {
      api.selected = ['content://one'];
      await database.customStatement(
        "CREATE TRIGGER fail_import BEFORE UPDATE ON captures BEGIN SELECT RAISE(ABORT, 'test failure'); END;",
      );
      await expectLater(service.pickAndImport(draft), throwsA(anything));
      expect(
        (await database.captureById('c1'))!.status,
        CaptureStatus.pendingCamera,
      );
      expect(
        await database.select(database.galleryImportTasks).get(),
        hasLength(1),
      );
      expect(api.released, isEmpty);
      await database.customStatement('DROP TRIGGER fail_import');
      await service.recover();
      expect(
        (await database.captureById('c1'))!.status,
        CaptureStatus.captured,
      );
      expect(await database.select(database.galleryImportTasks).get(), isEmpty);
      expect(api.released, ['content://one']);
    },
  );
  test(
    'project deleted during copy does not leave an orphan original',
    () async {
      api.selected = ['content://one'];
      api.onCopy = () async {
        await database.deleteProjectCascade('p');
      };
      final result = await service.pickAndImport(draft);
      expect(result.imported, 0);
      expect(await database.select(database.galleryImportTasks).get(), isEmpty);
      expect(files.deleted, contains('/private/c1.jpg'));
      expect(api.released, ['content://one']);
    },
  );
  test(
    'orphan recovery removes only its private original and partial file',
    () async {
      await database
          .into(database.galleryImportTasks)
          .insert(
            GalleryImportTasksCompanion.insert(
              captureId: 'orphan',
              sourceUri: 'content://one',
            ),
          );
      await service.recover();
      expect(files.deleted, [
        '/private/orphan.jpg',
        '/private/orphan.jpg.part',
      ]);
      expect(api.copies, 0);
      expect(api.released, ['content://one']);
    },
  );
  test(
    'multiple images use independent EXIF time and no device location',
    () async {
      api.selected = ['content://one', 'content://two'];
      final progress = <(int, int)>[];
      final result = await service.pickAndImport(
        draft,
        onProgress: (completed, total) => progress.add((completed, total)),
      );
      expect(result.imported, 2);
      expect(result.failed, 0);
      expect(progress, [(0, 2), (1, 2), (2, 2)]);
      final one = (await database.captureById('c1'))!;
      final two = (await database.captureById('c2'))!;
      expect(one.captureSource, 'gallery');
      expect(one.capturedAt, DateTime(2024, 1, 2, 3, 4));
      expect(one.sourceCapturedAt, one.capturedAt);
      expect(two.capturedAt, DateTime(2026, 10, 22));
      expect(two.sourceCapturedAt, isNull);
      expect(one.status, CaptureStatus.captured);
      expect(await database.select(database.galleryImportTasks).get(), isEmpty);
      expect(api.released, containsAll(api.selected));
    },
  );
  test('one unreadable image does not roll back successful images', () async {
    api.selected = ['content://bad', 'content://two'];
    final result = await service.pickAndImport(draft);
    expect(result.imported, 1);
    expect(result.failed, 1);
    expect(await database.captureById('c1'), isNull);
    expect((await database.captureById('c2'))!.status, CaptureStatus.captured);
  });
  test(
    'interrupted copy resumes using durable source and description',
    () async {
      await database.createPendingCapture(
        id: 'c1',
        projectId: 'p',
        originalPath: '/private/c1.jpg',
        workLocation: 'A',
        workContent: 'Inspection',
        photographer: 'B',
        watermarkLocaleCode: 'en',
        captureSource: 'gallery',
        watermarkTime: DateTime(2020, 1, 1),
      );
      await database
          .into(database.galleryImportTasks)
          .insert(
            GalleryImportTasksCompanion.insert(
              captureId: 'c1',
              sourceUri: 'content://one',
            ),
          );
      await service.recover();
      final record = (await database.captureById('c1'))!;
      expect(record.status, CaptureStatus.captured);
      expect(record.watermarkTime, DateTime(2020, 1, 1));
      expect(record.sourceCapturedAt, DateTime(2024, 1, 2, 3, 4));
      await service.recover();
      expect(api.copies, 1);
    },
  );
  test(
    'completed project refuses imports and releases selected grants',
    () async {
      await (database.update(
        database.projects,
      )..where((p) => p.id.equals('p'))).write(
        const ProjectsCompanion(
          lifecycleStatus: Value(ProjectLifecycleStatus.completed),
        ),
      );
      api.selected = ['content://one'];
      await expectLater(
        service.pickAndImport(draft),
        throwsA(isA<ProjectReadOnlyException>()),
      );
      expect(api.copies, 0);
      expect(api.released, ['content://one']);
      expect(await database.capturesForProject('p'), isEmpty);
    },
  );
}

class _Gallery extends GalleryImportApi {
  List<String> selected = [];
  final released = <String>[];
  int copies = 0;
  Future<void> Function()? onCopy;
  @override
  Future<List<String>> pickImages() async => selected;
  @override
  Future<void> releaseImages(List<String> values) async {
    released.addAll(values);
  }

  @override
  Future<GalleryImageCopy> copyImage(String uri, String id) async {
    copies++;
    await onCopy?.call();
    if (uri.endsWith('bad')) throw StateError('unreadable');
    return GalleryImageCopy(
      originalPath: '/private/$id.jpg',
      capturedAtMillis: uri.endsWith('one')
          ? DateTime(2024, 1, 2, 3, 4).millisecondsSinceEpoch
          : null,
    );
  }
}

class _Paths implements OriginalPhotoPaths {
  @override
  Future<String> originalPhotoPath(String id) async => '/private/$id.jpg';
}

class _Files implements PrivateFileStore {
  final deleted = <String>[];
  @override
  Future<bool> exists(String path) async => true;
  @override
  Future<void> deleteIfExists(String path) async {
    deleted.add(path);
  }
}

class _Scheduler implements CaptureBackgroundScheduler {
  @override
  Future<void> enqueue(String id) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Platform implements PlatformServices {
  @override
  Future<ImageMetadataResult> inspectImage(String path) async =>
      ImageMetadataResult(
        width: 10,
        height: 10,
        fileSizeBytes: 10,
        mimeType: 'image/jpeg',
      );
  // Any attempt to use current location / camera is an unexpected call.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
