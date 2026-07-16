import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';
import 'package:sitemark/src/rust/api/image_core.dart';
import 'package:sitemark/workflow/capture_processor.dart';

const _digestA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _digestB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  late AppDatabase database;
  late _ProcessorPlatformServices platform;
  late _ProcessorImagePipeline images;
  late CaptureProcessor processor;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.createProject(
      id: 'project-1',
      name: '东区厂房改造',
      createdAt: DateTime(2026, 7, 16, 8),
    );
    platform = _ProcessorPlatformServices();
    images = _ProcessorImagePipeline();
    processor = CaptureProcessor(
      database: database,
      platform: platform,
      images: images,
      outputPaths: _ProcessorOutputPaths(),
    );
  });

  tearDown(() async {
    await database.close();
  });

  /// Seeds a capture that already has `captured` status and the photo number
  /// assigned, with [attempts] prior processing attempts recorded.
  Future<void> seedCaptured({int attempts = 0}) async {
    await database.createPendingCapture(
      id: 'capture-1',
      projectId: 'project-1',
      originalPath: '/private/capture-1.jpg',
      workLocation: 'A 区三层',
      workContent: '风管安装检查',
      photographer: '张工',
      createdAt: DateTime(2026, 7, 16, 9, 30),
    );
    final captured = await database.markCaptured(
      captureId: 'capture-1',
      capturedAt: DateTime(2026, 7, 16, 9, 32, 18),
    );
    for (var i = 0; i < attempts; i++) {
      await database.incrementProcessingAttempts('capture-1');
    }
    expect(captured.photoNumber, 'SM-20260716-001');
  }

  /// Seeds a capture stuck in `rendering` with the original hash already
  /// persisted and [attempts] prior processing attempts recorded. This is the
  /// resume-after-crash scenario.
  Future<void> seedRenderingCapture({int attempts = 1}) async {
    await seedCaptured(attempts: 0);
    await database.markRendering(
      captureId: 'capture-1',
      originalSha256: _digestA,
    );
    for (var i = 0; i < attempts; i++) {
      await database.incrementProcessingAttempts('capture-1');
    }
  }

  test('renders and publishes a freshly captured record', () async {
    await seedCaptured();

    final result = await processor.process('capture-1');

    expect(result, CaptureProcessResult.succeeded);
    final record = await database.captureById('capture-1');
    expect(record?.status, CaptureStatus.ready);
    expect(record?.originalSha256, _digestA);
    expect(record?.publishedUri, 'content://media/site-mark/1');
    expect(record?.processingAttempts, 1);
    expect(platform.publishedNames, ['SM-20260716-001']);
    expect(images.lastRenderRequest?.sourcePath, '/private/capture-1.jpg');
    expect(images.lastRenderRequest?.photoNumber, 'SM-20260716-001');
  });

  test(
    'processor resumes rendering idempotently and publishes once by name',
    () async {
      await seedRenderingCapture(attempts: 1);
      final first = await processor.process('capture-1');
      final second = await processor.process('capture-1');

      expect(first, CaptureProcessResult.succeeded);
      expect(second, CaptureProcessResult.alreadyComplete);
      expect(platform.publishedNames, ['SM-20260716-001']);
      expect(
        (await database.captureById('capture-1'))?.status,
        CaptureStatus.ready,
      );
    },
  );

  test('third transient failure becomes final failure', () async {
    images.renderError = FileSystemException('temporary write failure');
    await seedCaptured(attempts: 0);
    await database.incrementProcessingAttempts('capture-1');
    await database.incrementProcessingAttempts('capture-1');
    expect(await processor.process('capture-1'), CaptureProcessResult.failed);
    final record = await database.captureById('capture-1');
    expect(record?.status, CaptureStatus.failed);
    expect(record?.processingAttempts, 3);
  });

  test(
    'transient failure below threshold returns retry and leaves status',
    () async {
      images.renderError = FileSystemException('temporary write failure');
      await seedCaptured(attempts: 0);

      final result = await processor.process('capture-1');

      expect(result, CaptureProcessResult.retry);
      final record = await database.captureById('capture-1');
      expect(record?.status, CaptureStatus.rendering);
      expect(record?.processingAttempts, 1);
      expect(platform.publishedNames, isEmpty);
    },
  );

  test('second transient failure still retries', () async {
    images.renderError = FileSystemException('temporary write failure');
    await seedCaptured(attempts: 0);
    await database.incrementProcessingAttempts('capture-1');

    final result = await processor.process('capture-1');

    expect(result, CaptureProcessResult.retry);
    final record = await database.captureById('capture-1');
    expect(record?.status, CaptureStatus.rendering);
    expect(record?.processingAttempts, 2);
  });

  test('missing record returns missing', () async {
    expect(
      await processor.process('does-not-exist'),
      CaptureProcessResult.missing,
    );
  });

  test('ready record returns alreadyComplete without re-publishing', () async {
    await seedCaptured(attempts: 0);
    await database.markRendering(
      captureId: 'capture-1',
      originalSha256: _digestA,
    );
    // Simulate a prior successful publish by marking ready.
    // markReady requires a non-empty URI.
    await database.markReady(
      captureId: 'capture-1',
      publishedUri: 'content://media/site-mark/1',
    );
    platform.publishedNames.clear();

    final result = await processor.process('capture-1');

    expect(result, CaptureProcessResult.alreadyComplete);
    expect(platform.publishedNames, isEmpty);
  });

  test('pendingCamera record is rejected as missing', () async {
    await database.createPendingCapture(
      id: 'capture-1',
      projectId: 'project-1',
      originalPath: '/private/capture-1.jpg',
      workLocation: 'A 区三层',
      workContent: '风管安装检查',
      photographer: '张工',
      createdAt: DateTime(2026, 7, 16, 9, 30),
    );

    expect(await processor.process('capture-1'), CaptureProcessResult.missing);
  });

  test('record whose project vanished (cascade) returns missing', () async {
    // The captures.project_id FK is ON DELETE CASCADE, so removing a project
    // also removes its captures. The processor therefore sees no record and
    // returns `missing`; the project-existence guard is a defensive backstop
    // for the non-cascading case.
    await database.createProject(
      id: 'project-2',
      name: '临时项目',
      createdAt: DateTime(2026, 7, 16, 8),
    );
    await database.createPendingCapture(
      id: 'capture-2',
      projectId: 'project-2',
      originalPath: '/private/capture-2.jpg',
      workLocation: 'A 区',
      workContent: '检查',
      photographer: '王工',
      createdAt: DateTime(2026, 7, 16, 10),
    );
    await database.markCaptured(
      captureId: 'capture-2',
      capturedAt: DateTime(2026, 7, 16, 10, 5),
    );
    await database.delete(database.projects).go();

    final result = await processor.process('capture-2');

    expect(result, CaptureProcessResult.missing);
  });

  test('hash mismatch becomes permanent failure', () async {
    await seedRenderingCapture(attempts: 0);
    // The seeded hash is digestA but the fake returns digestB for the original.
    images.sha256ByPath = {'/private/capture-1.jpg': _digestB};

    final result = await processor.process('capture-1');

    expect(result, CaptureProcessResult.failed);
    final record = await database.captureById('capture-1');
    expect(record?.status, CaptureStatus.failed);
    expect(record?.failureReason, isNotNull);
    expect(platform.publishedNames, isEmpty);
  });

  test('original file not found at render time is permanent failure', () async {
    await seedCaptured(attempts: 0);
    images.renderError = PathNotFoundException(
      '/private/capture-1.jpg',
      OSError(),
    );

    final result = await processor.process('capture-1');

    expect(result, CaptureProcessResult.failed);
    final record = await database.captureById('capture-1');
    expect(record?.status, CaptureStatus.failed);
  });

  test(
    'original deleted before hash verification is permanent failure (not retry)',
    () async {
      // Simulate the original file being gone between capture and a resumed
      // process(): `sha256` throws `PathNotFoundException` at step 6. This must
      // be a permanent failure (mark `failed`), not an unhandled exception that
      // leaves the record with incremented attempts but no `failed` marking.
      await seedCaptured(attempts: 0);
      images.sha256Error = PathNotFoundException(
        '/private/capture-1.jpg',
        OSError(),
      );

      final result = await processor.process('capture-1');

      expect(result, CaptureProcessResult.failed);
      final record = await database.captureById('capture-1');
      expect(record?.status, CaptureStatus.failed);
      expect(record?.processingAttempts, 1);
      expect(record?.failureReason, isNotNull);
      expect(platform.publishedNames, isEmpty);
    },
  );

  test(
    'socket error from render is transient (retry) below attempt budget',
    () async {
      // A `SocketException` (dart:io) during render must be classified as
      // transient and retried, not treated as a permanent failure. The previous
      // runtimeType string check (`'_SocketException'`) was a dead branch because
      // the public class's runtimeType is `SocketException`.
      await seedCaptured(attempts: 0);
      images.renderError = SocketException('network down');

      final result = await processor.process('capture-1');

      expect(result, CaptureProcessResult.retry);
      final record = await database.captureById('capture-1');
      expect(record?.status, CaptureStatus.rendering);
      expect(record?.processingAttempts, 1);
      expect(platform.publishedNames, isEmpty);
    },
  );

  test(
    'resumes a partially processed rendering record and verifies hash',
    () async {
      await seedRenderingCapture(attempts: 0);

      final result = await processor.process('capture-1');

      expect(result, CaptureProcessResult.succeeded);
      final record = await database.captureById('capture-1');
      expect(record?.status, CaptureStatus.ready);
      expect(record?.originalSha256, _digestA);
      expect(platform.publishedNames, ['SM-20260716-001']);
    },
  );

  test(
    'manual retry path: failed record reaches ready after resetCaptureForRetry',
    () async {
      // Regression for C1: a `failed` record (attempts=3) cannot be retried by
      // the processor directly (`failed -> rendering` is illegal and attempts
      // >= maxAttempts forces an immediate re-fail). The scheduler's `retry`
      // must call `resetCaptureForRetry` first. This test simulates that
      // sequence (reset then process) and asserts the record reaches `ready`.
      await seedCaptured(attempts: 0);
      await database.markRendering(
        captureId: 'capture-1',
        originalSha256: _digestA,
      );
      await database.markFailed(captureId: 'capture-1', reason: 'transient');
      await database.incrementProcessingAttempts('capture-1');
      await database.incrementProcessingAttempts('capture-1');
      await database.incrementProcessingAttempts('capture-1');
      final failed = (await database.captureById('capture-1'))!;
      expect(failed.status, CaptureStatus.failed);
      expect(failed.processingAttempts, 3);

      // This is exactly what PersistentCaptureBackgroundScheduler.retry now
      // does: reset, then enqueue (which runs the processor).
      await database.resetCaptureForRetry('capture-1');
      final result = await processor.process('capture-1');

      expect(result, CaptureProcessResult.succeeded);
      final record = await database.captureById('capture-1');
      expect(record?.status, CaptureStatus.ready);
      expect(record?.publishedUri, 'content://media/site-mark/1');
      // The reset zeroed attempts; the single successful pass leaves 1.
      expect(record?.processingAttempts, 1);
    },
  );
}

class _ProcessorPlatformServices implements PlatformServices {
  final List<String> publishedNames = [];
  int _publishCounter = 0;

  @override
  Future<String> createCameraTarget(String captureId) async =>
      '/private/$captureId.jpg';

  @override
  Future<void> deletePublishedImage(String contentUri) async {}

  @override
  Future<void> finishCameraCapture(String captureId, bool keepOriginal) async {}

  @override
  Future<CameraCaptureResult> launchCamera(String captureId) async {
    return CameraCaptureResult(
      outcome: CameraOutcome.captured,
      outputPath: '/private/$captureId.jpg',
    );
  }

  @override
  Future<String> publishJpeg(String sourcePath, String displayName) async {
    publishedNames.add(displayName);
    _publishCounter += 1;
    return 'content://media/site-mark/$_publishCounter';
  }

  @override
  Future<RecoveredCameraCapture?> recoverCameraCapture() async => null;

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

class _ProcessorImagePipeline implements ImagePipeline {
  RenderPhotoRequest? lastRenderRequest;
  Object? renderError;
  Object? sha256Error;
  Map<String, String> sha256ByPath = const {};

  @override
  Future<ExportProjectResult> export(ExportProjectRequest request) =>
      throw UnimplementedError();

  @override
  Future<String> sha256(String path) async {
    final error = sha256Error;
    if (error != null) {
      throw error;
    }
    final override = sha256ByPath[path];
    return override ?? _digestA;
  }

  @override
  Future<RenderPhotoResult> render(RenderPhotoRequest request) async {
    final error = renderError;
    if (error != null) {
      throw error;
    }
    lastRenderRequest = request;
    return RenderPhotoResult(
      outputPath: request.outputPath,
      outputSha256: _digestB,
      width: 4000,
      height: 3000,
    );
  }
}

class _ProcessorOutputPaths implements CaptureOutputPaths {
  @override
  Future<String> renderedPhotoPath(String captureId) async =>
      '/private/rendered/$captureId.jpg';
}
