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
    final service = _service(database: database, images: images, files: files);

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
    expect(
      withOriginal.originalPath,
      '/originals/${withOriginal.id}.jpg',
    );
    expect(
      withOriginal.originalSha256,
      'a' * 64,
    );
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

    // Extraction was asked to place files at the canonical locations.
    expect(images.extractRequests.length, 2);
    expect(
      images.extractRequests[0].renderedDestination,
      '/rendered/${withOriginal.id}.jpg',
    );
    expect(
      images.extractRequests[0].originalDestination,
      '/originals/${withOriginal.id}.jpg',
    );
    expect(images.extractRequests[1].originalDestination, isNull);
  });

  test('importProject rolls everything back when extraction fails', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final images = _ImportImagePipeline(_preview(), failAtIndex: 1);
    final files = _RecordingFileStore();
    final service = _service(database: database, images: images, files: files);

    await expectLater(
      service.importProject(zipPath: '/backups/p.zip', projectName: '东区厂房改造'),
      throwsA(isA<ImagePipelineException>()),
    );

    expect(await database.getProjects(), isEmpty);
    expect(await database.getAllCaptures(), isEmpty);
    // The first photo's extracted files were removed during rollback.
    expect(files.deleted.length, 2);
    expect(files.deleted[0], startsWith('/rendered/'));
    expect(files.deleted[1], startsWith('/originals/'));
  });

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
    final capture = (await database.capturesForProject(result.projectId)).single;
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

    await database.createProject(id: 'p2', name: '东区厂房改造（导入）');
    expect(
      await service.suggestAvailableName('东区厂房改造'),
      '东区厂房改造（导入 2）',
    );
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
}) {
  return ProjectImportService(
    database: database,
    images: images,
    capturePaths: _ImportCapturePaths(),
    originalPaths: _ImportOriginalPaths(),
    fileStore: files,
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
  Future<ExportProjectResult> exportSelection(
    ExportSelectionRequest request,
  ) =>
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

class _RecordingFileStore implements PrivateFileStore {
  final deleted = <String>[];

  @override
  Future<bool> exists(String path) async => true;

  @override
  Future<void> deleteIfExists(String path) async {
    deleted.add(path);
  }
}
