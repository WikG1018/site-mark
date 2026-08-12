import 'dart:ui' show Locale;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_media_failure.dart';
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
    expect(await pendingStore.list(), hasLength(1));

    platform.deleteError = null;
    await service.cleanupInterrupted();

    expect(platform.deletedUris, ['content://media/site-mark/1']);
    expect(await pendingStore.list(), isEmpty);
  });

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
  String nextPublishedUri = 'content://media/site-mark/1';
  final List<String> deletedUris = [];

  @override
  Future<ImageMetadataResult> inspectImage(String path) async =>
      metadataByPath[path]!;

  @override
  Future<String> publishJpeg(String sourcePath, String displayName) async {
    if (publishError != null) throw publishError!;
    return nextPublishedUri;
  }

  @override
  Future<void> deletePublishedImage(String contentUri) async {
    if (deleteError != null) throw deleteError!;
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
