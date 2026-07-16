import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';
import 'package:sitemark/src/rust/api/image_core.dart';
import 'package:sitemark/workflow/capture_workflow.dart';
import 'package:sitemark/background/capture_background_scheduler.dart';

void main() {
  const digestA =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  late AppDatabase database;
  late _FakePlatformServices platform;
  late _FakeImagePipeline images;
  late _RecordingScheduler scheduler;
  late CaptureWorkflow workflow;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.createProject(
      id: 'project-1',
      name: '东区厂房改造',
      createdAt: DateTime(2026, 7, 16, 8),
    );
    platform = _FakePlatformServices();
    images = _FakeImagePipeline();
    scheduler = _RecordingScheduler();
    workflow = CaptureWorkflow(
      database: database,
      platform: platform,
      images: images,
      outputPaths: _FakeOutputPaths(),
      fileStore: _FakePrivateFileStore(),
      scheduler: scheduler,
      idFactory: () => 'capture-1',
      now: () => DateTime(2026, 7, 16, 9, 32, 18),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('capture returns queued before hash render or publish', () async {
    final result = await workflow.capture(
      const CaptureDraft(
        projectId: 'project-1',
        projectName: '东区厂房改造',
        workLocation: 'A 区三层',
        workContent: '风管安装检查',
        photographer: '张工',
        notes: '支架间距复核',
      ),
    );

    final record = await database.captureById('capture-1');

    expect(result.outcome, CaptureWorkflowOutcome.queued);
    expect(record?.status, CaptureStatus.captured);
    expect(record?.photoNumber, 'SM-20260716-001');
    expect(scheduler.enqueuedIds, ['capture-1']);
    expect(images.lastRenderRequest, isNull);
    expect(platform.publishedNames, isEmpty);
    expect(platform.finishedCapture, ('capture-1', true));
    // Hashing and publishing are deferred to the background processor.
    expect(record?.originalSha256, isNull);
    expect(record?.publishedUri, isNull);
  });

  test(
    'removes the pending record when the system camera is cancelled',
    () async {
      platform.cameraOutcome = CameraOutcome.cancelled;

      final result = await workflow.capture(
        const CaptureDraft(
          projectId: 'project-1',
          projectName: '东区厂房改造',
          workLocation: 'A 区三层',
          workContent: '风管安装检查',
          photographer: '张工',
        ),
      );

      final records = await database.watchCapturesForProject('project-1').first;
      expect(result.outcome, CaptureWorkflowOutcome.cancelled);
      expect(records, isEmpty);
      expect(platform.finishedCapture, ('capture-1', false));
      expect(images.lastRenderRequest, isNull);
      expect(scheduler.enqueuedIds, isEmpty);
    },
  );

  test('recovers a non-empty camera target after process recreation', () async {
    await database.createPendingCapture(
      id: 'capture-1',
      projectId: 'project-1',
      originalPath: '/private/capture-1.jpg',
      workLocation: 'A 区三层',
      workContent: '风管安装检查',
      photographer: '张工',
      createdAt: DateTime(2026, 7, 16, 9, 30),
    );
    platform.recoveredCapture = RecoveredCameraCapture(
      captureId: 'capture-1',
      outputPath: '/private/capture-1.jpg',
      hasContent: true,
    );

    final result = await workflow.recoverPendingCapture();

    expect(result?.outcome, CaptureWorkflowOutcome.queued);
    expect(
      (await database.captureById('capture-1'))?.status,
      CaptureStatus.captured,
    );
    expect(platform.finishedCapture, ('capture-1', true));
    expect(scheduler.enqueuedIds, ['capture-1']);
    expect(images.lastRenderRequest, isNull);
  });

  test('regenerates after descriptive edits by re-enqueuing', () async {
    await workflow.capture(
      const CaptureDraft(
        projectId: 'project-1',
        projectName: '东区厂房改造',
        workLocation: 'A 区三层',
        workContent: '风管安装检查',
        photographer: '张工',
      ),
    );
    // Simulate the background processor completing the first capture so the
    // record is ready and eligible for regeneration.
    await database.markRendering(
      captureId: 'capture-1',
      originalSha256: digestA,
    );
    await database.markReady(
      captureId: 'capture-1',
      publishedUri: 'content://media/site-mark/1',
    );
    scheduler.enqueuedIds.clear();

    final edited = await workflow.regenerateCapture(
      captureId: 'capture-1',
      edits: const CaptureEdits(
        workLocation: 'B 区屋面',
        workContent: '保温整改复查',
        photographer: '李工',
        notes: '复验合格',
      ),
    );

    expect(edited.workLocation, 'B 区屋面');
    expect(edited.workContent, '保温整改复查');
    expect(edited.photographer, '李工');
    expect(edited.notes, '复验合格');
    expect(edited.status, CaptureStatus.captured);
    expect(edited.photoNumber, 'SM-20260716-001');
    // Regeneration re-enqueues for background processing instead of rendering.
    expect(scheduler.enqueuedIds, ['capture-1']);
    expect(images.lastRenderRequest, isNull);
    expect(platform.publishedNames, isEmpty);
    expect(edited.processingAttempts, 0);
    expect(edited.publishedUri, 'content://media/site-mark/1');
    expect(edited.originalSha256, digestA);
  });

  test('deletes the published image and local capture record', () async {
    await workflow.capture(
      const CaptureDraft(
        projectId: 'project-1',
        projectName: '东区厂房改造',
        workLocation: 'A 区三层',
        workContent: '风管安装检查',
        photographer: '张工',
      ),
    );
    // Simulate a published capture so delete has a URI to remove.
    await database.markRendering(
      captureId: 'capture-1',
      originalSha256: digestA,
    );
    await database.markReady(
      captureId: 'capture-1',
      publishedUri: 'content://media/site-mark/1',
    );

    await workflow.deleteCapture('capture-1');

    expect(await database.captureById('capture-1'), isNull);
    expect(platform.deletedUri, 'content://media/site-mark/1');
  });
}

class _FakePlatformServices implements PlatformServices {
  CameraOutcome cameraOutcome = CameraOutcome.captured;
  final List<String> publishedNames = [];
  (String, bool)? finishedCapture;
  RecoveredCameraCapture? recoveredCapture;
  String? deletedUri;

  @override
  Future<String> createCameraTarget(String captureId) async =>
      '/private/$captureId.jpg';

  @override
  Future<void> deletePublishedImage(String contentUri) async {
    deletedUri = contentUri;
  }

  @override
  Future<void> finishCameraCapture(String captureId, bool keepOriginal) async {
    finishedCapture = (captureId, keepOriginal);
  }

  @override
  Future<CameraCaptureResult> launchCamera(String captureId) async {
    return CameraCaptureResult(
      outcome: cameraOutcome,
      outputPath: '/private/$captureId.jpg',
    );
  }

  @override
  Future<String> publishJpeg(String sourcePath, String displayName) async {
    publishedNames.add(displayName);
    return 'content://media/site-mark/1';
  }

  @override
  Future<RecoveredCameraCapture?> recoverCameraCapture() async =>
      recoveredCapture;

  @override
  Future<LocationResult> requestCurrentLocation(int timeoutMillis) async {
    return LocationResult(
      outcome: LocationOutcome.precise,
      latitude: 24.513,
      longitude: 117.6471,
      accuracyMeters: 8,
      address: '福建省漳州市',
    );
  }
}

class _FakeImagePipeline implements ImagePipeline {
  static const digestA =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  RenderPhotoRequest? lastRenderRequest;

  @override
  Future<ExportProjectResult> export(ExportProjectRequest request) =>
      throw UnimplementedError();

  @override
  Future<String> sha256(String path) async => digestA;

  @override
  Future<RenderPhotoResult> render(RenderPhotoRequest request) async {
    lastRenderRequest = request;
    return RenderPhotoResult(
      outputPath: request.outputPath,
      outputSha256:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      width: 4000,
      height: 3000,
    );
  }
}

class _FakeOutputPaths implements CaptureOutputPaths {
  @override
  Future<String> renderedPhotoPath(String captureId) async =>
      '/private/rendered/$captureId.jpg';
}

class _FakePrivateFileStore implements PrivateFileStore {
  @override
  Future<void> deleteIfExists(String path) async {}
}

class _RecordingScheduler implements CaptureBackgroundScheduler {
  final List<String> enqueuedIds = [];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> enqueue(String captureId) async {
    enqueuedIds.add(captureId);
  }

  @override
  Future<void> retry(String captureId) async {
    enqueuedIds.add(captureId);
  }

  @override
  Future<void> reconcilePending() async {}
}
