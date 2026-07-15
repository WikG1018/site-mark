import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/src/rust/api/image_core.dart';
import 'package:sitemark/workflow/project_export_service.dart';

void main() {
  test('builds a project ZIP request from completed capture records', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'project-1', name: '东区厂房改造');
    final pending = await database.createPendingCapture(
      id: 'capture-1',
      projectId: 'project-1',
      originalPath: '/private/original.jpg',
      workLocation: 'A 区三层',
      workContent: '风管安装检查',
      photographer: '张工',
    );
    await database.markCaptured(
      captureId: pending.id,
      capturedAt: DateTime(2026, 7, 16, 9, 32),
    );
    await database.markRendering(
      captureId: pending.id,
      originalSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    await database.markReady(
      captureId: pending.id,
      publishedUri: 'content://media/site-mark/1',
    );
    final images = _ExportImagePipeline();
    final service = ProjectExportService(
      database: database,
      images: images,
      capturePaths: _ExportCapturePaths(),
      exportPaths: _ExportOutputPaths(),
    );

    final result = await service.exportProject(
      projectId: 'project-1',
      includeOriginals: true,
    );

    expect(result.outputZipPath, '/exports/project-1.zip');
    expect(images.request?.projectName, '东区厂房改造');
    expect(images.request?.photos.single.photoNumber, 'SM-20260716-001');
    expect(
      images.request?.photos.single.watermarkedPath,
      '/rendered/capture-1.jpg',
    );
    expect(images.request?.photos.single.originalPath, '/private/original.jpg');
  });
}

class _ExportImagePipeline implements ImagePipeline {
  ExportProjectRequest? request;

  @override
  Future<ExportProjectResult> export(ExportProjectRequest request) async {
    this.request = request;
    return ExportProjectResult(
      outputZipPath: request.outputZipPath,
      archiveSha256:
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
      photoCount: request.photos.length,
    );
  }

  @override
  Future<RenderPhotoResult> render(RenderPhotoRequest request) =>
      throw UnimplementedError();

  @override
  Future<String> sha256(String path) => throw UnimplementedError();
}

class _ExportCapturePaths implements CaptureOutputPaths {
  @override
  Future<String> renderedPhotoPath(String captureId) async =>
      '/rendered/$captureId.jpg';
}

class _ExportOutputPaths implements ProjectExportPaths {
  @override
  Future<String> projectZipPath(String projectId) async =>
      '/exports/$projectId.zip';
}
