import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/background/capture_background_scheduler.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/capture_location_coordinator.dart';
import 'package:sitemark/workflow/capture_workflow.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';
import 'package:sitemark/src/rust/api/image_core.dart';

void main() {
  const digestA =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  late AppDatabase database;
  late _FakePlatformServices platform;
  late _FakeImagePipeline images;
  late _RecordingScheduler scheduler;
  late CaptureLocationCoordinator coordinator;
  late _FakePrivateFileStore fileStore;
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
    fileStore = _FakePrivateFileStore();
    coordinator = CaptureLocationCoordinator(
      database: database,
      platform: platform,
      scheduler: scheduler,
    );
    workflow = CaptureWorkflow(
      database: database,
      platform: platform,
      images: images,
      outputPaths: _FakeOutputPaths(),
      fileStore: fileStore,
      scheduler: scheduler,
      locationCoordinator: coordinator,
      idFactory: () => 'capture-1',
      now: () => DateTime(2026, 7, 16, 9, 32, 18),
    );
  });

  tearDown(() async {
    await database.close();
  });

  /// Drains the microtask queue so the coordinator's fire-and-forget
  /// resolution + enqueue completes before assertions.
  Future<void> drainCoordinator() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  test('capture returns queued before hash render or publish', () async {
    final result = await workflow.capture(
      const CaptureDraft(
        projectId: 'project-1',
        projectName: '东区厂房改造',
        workLocation: 'A 区三层',
        workContent: '风管安装检查',
        photographer: '张工',
        notes: '支架间距复核',
        watermarkLocaleCode: 'zh',
      ),
    );
    await drainCoordinator();

    final record = await database.captureById('capture-1');

    expect(result.outcome, CaptureWorkflowOutcome.queued);
    expect(record?.status, CaptureStatus.captured);
    expect(record?.photoNumber, '东区厂房改造-project--SM-20260716-001');
    expect(scheduler.enqueuedIds, ['capture-1']);
    expect(images.lastRenderRequest, isNull);
    expect(platform.publishedNames, isEmpty);
    expect(platform.finishedCapture, ('capture-1', true));
    // Hashing and publishing are deferred to the background processor.
    expect(record?.originalSha256, isNull);
    expect(record?.publishedUri, isNull);
  });

  test('captures watermark locale code from draft', () async {
    final result = await workflow.capture(
      const CaptureDraft(
        projectId: 'project-1',
        projectName: 'East Plant',
        workLocation: 'Level 3',
        workContent: 'Duct inspection',
        photographer: 'Alex',
        useLocationFallback: false,
        watermarkLocaleCode: 'en',
      ),
    );
    await drainCoordinator();
    expect(result.capture?.watermarkLocaleCode, 'en');
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
          watermarkLocaleCode: 'zh',
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

  test(
    'launchCamera runs before location resolves and workflow returns queued',
    () async {
      // Replace the location future with one we control so we can prove the
      // camera launches before the location read completes.
      final locationCompleter = Completer<LocationResult>();
      platform.locationOverride = locationCompleter.future;

      final result = await workflow.capture(
        const CaptureDraft(
          projectId: 'project-1',
          projectName: '东区厂房改造',
          workLocation: 'A 区三层',
          workContent: '风管安装检查',
          photographer: '张工',
          watermarkLocaleCode: 'zh',
        ),
      );

      // The workflow returned queued and launchCamera was called, but the
      // location future is still pending.
      expect(result.outcome, CaptureWorkflowOutcome.queued);
      expect(platform.events, contains('launchCamera'));
      expect(locationCompleter.isCompleted, isFalse);

      // Complete the location read; the coordinator should now resolve and
      // enqueue the capture in the background.
      locationCompleter.complete(
        LocationResult(
          outcome: LocationOutcome.precise,
          latitude: 24.513,
          longitude: 117.6471,
          accuracyMeters: 8,
          address: '福建省漳州市',
        ),
      );
      await drainCoordinator();

      expect(scheduler.enqueuedIds, ['capture-1']);
      final record = await database.captureById('capture-1');
      expect(record?.locationResolution, 'resolved');
      expect(record?.locationOutcome, 'precise');
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
      watermarkLocaleCode: 'zh',
      createdAt: DateTime(2026, 7, 16, 9, 30),
    );
    platform.recoveredCapture = RecoveredCameraCapture(
      captureId: 'capture-1',
      outputPath: '/private/capture-1.jpg',
      hasContent: true,
    );

    final result = await workflow.recoverPendingCapture();
    await drainCoordinator();

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
        watermarkLocaleCode: 'zh',
      ),
    );
    await drainCoordinator();
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
    // The fake camera target writes to /private/capture-1.jpg; mark it as
    // existing on disk so the regenerateCapture availability check passes.
    fileStore.existing.add('/private/capture-1.jpg');
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
    expect(edited.photoNumber, '东区厂房改造-project--SM-20260716-001');
    // Regeneration re-enqueues for background processing instead of rendering.
    expect(scheduler.enqueuedIds, ['capture-1']);
    expect(images.lastRenderRequest, isNull);
    expect(platform.publishedNames, isEmpty);
    expect(edited.processingAttempts, 0);
    expect(edited.publishedUri, 'content://media/site-mark/1');
    expect(edited.originalSha256, digestA);
  });

  test(
    'regenerateCapture throws when the original is cleared and does not enqueue',
    () async {
      await workflow.capture(
        const CaptureDraft(
          projectId: 'project-1',
          projectName: '东区厂房改造',
          workLocation: 'A 区三层',
          workContent: '风管安装检查',
          photographer: '张工',
          watermarkLocaleCode: 'zh',
        ),
      );
      await drainCoordinator();
      await database.markRendering(
        captureId: 'capture-1',
        originalSha256: digestA,
      );
      await database.markReady(
        captureId: 'capture-1',
        publishedUri: 'content://media/site-mark/1',
      );
      await database.markOriginalDeleted('capture-1');
      scheduler.enqueuedIds.clear();

      await expectLater(
        workflow.regenerateCapture(
          captureId: 'capture-1',
          edits: const CaptureEdits(
            workLocation: 'B 区屋面',
            workContent: '保温整改复查',
            photographer: '李工',
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Original photo is not available',
          ),
        ),
      );
      expect(scheduler.enqueuedIds, isEmpty);
    },
  );

  test('deletes the published image and local capture record', () async {
    await workflow.capture(
      const CaptureDraft(
        projectId: 'project-1',
        projectName: '东区厂房改造',
        workLocation: 'A 区三层',
        workContent: '风管安装检查',
        photographer: '张工',
        watermarkLocaleCode: 'zh',
      ),
    );
    await drainCoordinator();
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
  final List<String> events = [];
  (String, bool)? finishedCapture;
  RecoveredCameraCapture? recoveredCapture;
  String? deletedUri;
  Future<LocationResult>? locationOverride;

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
    events.add('launchCamera');
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
    events.add('requestCurrentLocation');
    final override = locationOverride;
    if (override != null) return override;
    return LocationResult(
      outcome: LocationOutcome.precise,
      latitude: 24.513,
      longitude: 117.6471,
      accuracyMeters: 8,
      address: '福建省漳州市',
    );
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
  Future<ImageMetadataResult> inspectImage(String path) async =>
      ImageMetadataResult(
        width: 0,
        height: 0,
        fileSizeBytes: 0,
        mimeType: 'image/jpeg',
      );
}

class _FakeImagePipeline implements ImagePipeline {
  static const digestA =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  RenderPhotoRequest? lastRenderRequest;

  @override
  Future<ExportProjectResult> export(ExportProjectRequest request) =>
      throw UnimplementedError();

  @override
  Future<ExportProjectResult> exportSelection(ExportSelectionRequest request) =>
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
  final Set<String> existing = {};

  @override
  Future<bool> exists(String path) async => existing.contains(path);

  @override
  Future<void> deleteIfExists(String path) async {
    existing.remove(path);
  }
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
