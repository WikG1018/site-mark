import 'package:drift/drift.dart'
    show ApplyInterceptor, QueryExecutor, QueryInterceptor, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
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
      watermarkLocaleCode: 'zh',
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
      selectionExportPaths: _SelectionOutputPaths(),
    );

    final result = await service.exportProject(
      projectId: 'project-1',
      includeOriginals: true,
    );

    expect(result.outputZipPath, '/exports/project-1.zip');
    expect(images.request?.projectName, '东区厂房改造');
    expect(images.request?.photos.single.photoNumber, '东区厂房改造-SM-20260716-001');
    expect(
      images.request?.photos.single.watermarkedPath,
      '/rendered/capture-1.jpg',
    );
    expect(images.request?.photos.single.originalPath, '/private/original.jpg');

    final staged = await service.exportProject(
      projectId: 'project-1',
      includeOriginals: false,
      outputZipPath: '/imports/bundle/projects/project-1.zip',
    );
    expect(staged.outputZipPath, '/imports/bundle/projects/project-1.zip');
    expect(
      images.request?.outputZipPath,
      '/imports/bundle/projects/project-1.zip',
    );
  });

  test('exportSelection groups captures by project into one ZIP', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'project-a', name: '东区厂房改造');
    await database.createProject(id: 'project-b', name: '西区市政给水');
    await _seedReadyCapture(
      database: database,
      id: 'capture-a',
      projectId: 'project-a',
      capturedAt: DateTime(2026, 7, 16, 9, 32),
    );
    await _seedReadyCapture(
      database: database,
      id: 'capture-b',
      projectId: 'project-b',
      capturedAt: DateTime(2026, 7, 16, 10, 11),
    );
    final images = _ExportImagePipeline();
    final service = ProjectExportService(
      database: database,
      images: images,
      capturePaths: _ExportCapturePaths(),
      exportPaths: _ExportOutputPaths(),
      selectionExportPaths: _SelectionOutputPaths(),
    );

    final result = await service.exportSelection(
      captureIds: const ['capture-a', 'capture-b'],
      includeOriginals: false,
    );

    expect(result.outputZipPath, '/exports/sitemark-selection.zip');
    expect(images.selectionRequest, isNotNull);
    expect(images.selectionRequest!.projects.length, 2);
    expect(images.selectionRequest!.projects[0].projectId, 'project-a');
    expect(images.selectionRequest!.projects[0].projectName, '东区厂房改造');
    expect(
      images.selectionRequest!.projects[0].photos.single.photoNumber,
      '东区厂房改造-SM-20260716-001',
    );
    expect(images.selectionRequest!.projects[1].projectId, 'project-b');
    expect(
      images.selectionRequest!.projects[1].photos.single.photoNumber,
      '西区市政给水-SM-20260716-002',
    );
    expect(images.selectionRequest!.includeOriginals, isFalse);
  });

  test('exportSelection rejects captures that are not ready', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'project-a', name: '东区厂房改造');
    await database.createPendingCapture(
      id: 'capture-pending',
      projectId: 'project-a',
      originalPath: '/private/original.jpg',
      workLocation: 'A 区',
      workContent: '风管检查',
      photographer: '张工',
      watermarkLocaleCode: 'zh',
      locationResolution: 'resolved',
    );
    final service = ProjectExportService(
      database: database,
      images: _ExportImagePipeline(),
      capturePaths: _ExportCapturePaths(),
      exportPaths: _ExportOutputPaths(),
      selectionExportPaths: _SelectionOutputPaths(),
    );

    expect(
      () => service.exportSelection(
        captureIds: const ['capture-pending'],
        includeOriginals: false,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'exportSelection loads 1200 selected captures in bounded queries',
    () async {
      final variableGuard = _LegacySqliteVariableGuard();
      final database = AppDatabase.forTesting(
        NativeDatabase.memory().interceptWith(variableGuard),
      );
      addTearDown(database.close);
      await database.createProject(id: 'project-a', name: '东区厂房改造');
      final ids = List.generate(1200, (index) => 'capture-$index');
      await database.batch((batch) {
        batch.insertAll(database.captureRecords, [
          for (var index = 0; index < ids.length; index++)
            CaptureRecordsCompanion.insert(
              id: ids[index],
              projectId: 'project-a',
              photoNumber: Value('SM-20260716-${index + 1}'),
              workLocation: 'A 区',
              workContent: '风管检查',
              photographer: '张工',
              originalPath: '/private/${ids[index]}.jpg',
              publishedUri: Value('content://media/${ids[index]}'),
              originalSha256: const Value(
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              ),
              status: CaptureStatus.ready,
              createdAt: DateTime(2026, 7, 16).add(Duration(seconds: index)),
              capturedAt: Value(
                DateTime(2026, 7, 16).add(Duration(seconds: index)),
              ),
              watermarkLocaleCode: const Value('zh'),
              locationResolution: const Value('resolved'),
            ),
        ]);
      });
      final images = _ExportImagePipeline();
      final service = ProjectExportService(
        database: database,
        images: images,
        capturePaths: _ExportCapturePaths(),
        exportPaths: _ExportOutputPaths(),
        selectionExportPaths: _SelectionOutputPaths(),
      );

      final result = await service.exportSelection(
        captureIds: ids,
        includeOriginals: false,
      );

      expect(result.photoCount, 1200);
      expect(images.selectionRequest?.projects.single.photos, hasLength(1200));
      expect(variableGuard.multiVariableSelects, hasLength(greaterThan(1)));
      expect(
        variableGuard.multiVariableSelects,
        everyElement(lessThanOrEqualTo(999)),
      );
    },
  );
}

Future<void> _seedReadyCapture({
  required AppDatabase database,
  required String id,
  required String projectId,
  required DateTime capturedAt,
}) async {
  final pending = await database.createPendingCapture(
    id: id,
    projectId: projectId,
    originalPath: '/private/$id.jpg',
    workLocation: 'A 区',
    workContent: '风管检查',
    photographer: '张工',
    watermarkLocaleCode: 'zh',
    locationResolution: 'resolved',
  );
  await database.markCaptured(captureId: pending.id, capturedAt: capturedAt);
  await database.markRendering(
    captureId: pending.id,
    originalSha256:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  );
  await database.markReady(
    captureId: pending.id,
    publishedUri: 'content://media/site-mark/$id',
  );
}

class _ExportImagePipeline implements ImagePipeline {
  ExportProjectRequest? request;
  ExportSelectionRequest? selectionRequest;

  @override
  Future<ProjectArchivePreview> readProjectArchive(String zipPath) =>
      throw UnimplementedError();

  @override
  Future<ExtractedArchivePhoto> extractArchivePhoto(
    ExtractArchivePhotoRequest request,
  ) => throw UnimplementedError();

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
  Future<ExportProjectResult> exportSelection(
    ExportSelectionRequest request,
  ) async {
    selectionRequest = request;
    return ExportProjectResult(
      outputZipPath: request.outputZipPath,
      archiveSha256:
          'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
      photoCount: request.projects.fold<int>(
        0,
        (sum, p) => sum + p.photos.length,
      ),
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

class _SelectionOutputPaths implements SelectionExportPaths {
  @override
  Future<String> selectionZipPath() async => '/exports/sitemark-selection.zip';
}

class _LegacySqliteVariableGuard extends QueryInterceptor {
  final List<int> multiVariableSelects = [];

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (args.length > 1) multiVariableSelects.add(args.length);
    if (args.length > 999) {
      throw StateError('too many SQL variables: ${args.length}');
    }
    return super.runSelect(executor, statement, args);
  }
}
