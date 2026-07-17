import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/domain/original_photo_state.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/capture_media_service.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

const digestA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  late AppDatabase database;
  late _MediaFiles files;
  late _MediaPlatform platform;
  late _MediaPaths paths;
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
    service = CaptureMediaService(
      database: database,
      platform: platform,
      outputPaths: paths,
      files: files,
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

  test('delete all keeps the row when published deletion fails', () async {
    platform.deleteError = StateError('MediaStore failure');
    final result = await service.deleteAll(['capture-1']);
    expect(result.failures.keys, ['capture-1']);
    expect(await database.captureById('capture-1'), isNotNull);
  });

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

  @override
  Future<bool> exists(String path) async => existing.contains(path);

  @override
  Future<void> deleteIfExists(String path) async {
    existing.remove(path);
    deleted.add(path);
  }
}

class _MediaPaths implements CaptureOutputPaths {
  @override
  Future<String> renderedPhotoPath(String captureId) async =>
      '/rendered/$captureId.jpg';
}

class _MediaPlatform implements PlatformServices {
  final Map<String, ImageMetadataResult> metadataByPath = {};
  Object? deleteError;
  String nextPublishedUri = 'content://media/site-mark/1';

  @override
  Future<ImageMetadataResult> inspectImage(String path) async =>
      metadataByPath[path]!;

  @override
  Future<String> publishJpeg(String sourcePath, String displayName) async =>
      nextPublishedUri;

  @override
  Future<void> deletePublishedImage(String contentUri) async {
    if (deleteError != null) throw deleteError!;
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
