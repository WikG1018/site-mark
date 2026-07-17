import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/background/capture_background_scheduler.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/capture_location_coordinator.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

void main() {
  late AppDatabase database;
  late _CoordinatorPlatform platform;
  late _RecordingScheduler scheduler;
  late CaptureLocationCoordinator coordinator;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.createProject(
      id: 'project-1',
      name: '东区厂房改造',
      createdAt: DateTime(2026, 7, 16, 8),
    );
    platform = _CoordinatorPlatform();
    scheduler = _RecordingScheduler();
    coordinator = CaptureLocationCoordinator(
      database: database,
      platform: platform,
      scheduler: scheduler,
    );
  });

  tearDown(() async {
    await database.close();
  });

  /// Seeds a `captured` record with `locationResolution: 'pending'` so the
  /// coordinator is responsible for resolving its location source.
  Future<void> seedPendingLocationCapture({
    String id = 'capture-1',
    String originalPath = '/private/capture-1.jpg',
  }) async {
    await database.createPendingCapture(
      id: id,
      projectId: 'project-1',
      originalPath: originalPath,
      workLocation: 'A 区三层',
      workContent: '风管安装检查',
      photographer: '张工',
      watermarkLocaleCode: 'zh',
      createdAt: DateTime(2026, 7, 16, 9, 30),
    );
    await database.markCaptured(
      captureId: id,
      capturedAt: DateTime(2026, 7, 16, 9, 32, 18),
    );
  }

  test(
    'EXIF GPS wins and enqueues without waiting for the fallback future',
    () async {
      await seedPendingLocationCapture();
      platform.exifLatitude = 24.513;
      platform.exifLongitude = 117.6471;
      // A fallback that never completes: the coordinator must NOT await it
      // when EXIF already provides valid GPS.
      final neverCompleter = Completer<LocationResult>();

      await coordinator.resolve(
        'capture-1',
        fallback: neverCompleter.future,
        enqueue: true,
      );

      final record = await database.captureById('capture-1');
      expect(record?.locationResolution, 'resolved');
      expect(record?.locationOutcome, 'exif');
      expect(record?.latitude, 24.513);
      expect(record?.longitude, 117.6471);
      expect(scheduler.enqueuedIds, ['capture-1']);
      // The fallback was never awaited, so it is still pending.
      expect(neverCompleter.isCompleted, isFalse);
    },
  );

  test(
    'missing EXIF falls back to the record-scoped location future',
    () async {
      await seedPendingLocationCapture();
      // No EXIF GPS configured on the fake platform.
      final fallback = Future.value(
        LocationResult(
          outcome: LocationOutcome.precise,
          latitude: 31.2304,
          longitude: 121.4737,
          accuracyMeters: 12,
          address: '上海市',
        ),
      );

      await coordinator.resolve('capture-1', fallback: fallback, enqueue: true);

      final record = await database.captureById('capture-1');
      expect(record?.locationResolution, 'resolved');
      expect(record?.locationOutcome, 'precise');
      expect(record?.latitude, 31.2304);
      expect(record?.longitude, 121.4737);
      expect(record?.accuracyMeters, 12);
      expect(record?.address, '上海市');
      expect(scheduler.enqueuedIds, ['capture-1']);
    },
  );

  test(
    'no EXIF and no usable fallback becomes unavailable and still enqueues',
    () async {
      await seedPendingLocationCapture();
      // Fallback reports permission denied (not a usable fix).
      final fallback = Future.value(
        LocationResult(outcome: LocationOutcome.permissionDenied),
      );

      await coordinator.resolve('capture-1', fallback: fallback, enqueue: true);

      final record = await database.captureById('capture-1');
      expect(record?.locationResolution, 'unavailable');
      expect(record?.locationOutcome, 'permissionDenied');
      expect(record?.latitude, isNull);
      expect(record?.longitude, isNull);
      expect(scheduler.enqueuedIds, ['capture-1']);
    },
  );

  test('null fallback with no EXIF marks unavailable and enqueues', () async {
    await seedPendingLocationCapture();

    await coordinator.resolve('capture-1', fallback: null, enqueue: true);

    final record = await database.captureById('capture-1');
    expect(record?.locationResolution, 'unavailable');
    expect(record?.locationOutcome, 'unavailable');
    expect(scheduler.enqueuedIds, ['capture-1']);
  });

  test('already-resolved records are skipped entirely', () async {
    await seedPendingLocationCapture();
    // Manually resolve the record before the coordinator runs.
    await database.resolveCaptureLocation(
      captureId: 'capture-1',
      resolution: 'resolved',
      outcome: 'exif',
      latitude: 24.513,
      longitude: 117.6471,
    );
    platform.exifLatitude = 99.9;
    platform.exifLongitude = 99.9;

    await coordinator.resolve('capture-1', fallback: null, enqueue: true);

    // The coordinator must not overwrite the existing resolution.
    final record = await database.captureById('capture-1');
    expect(record?.locationResolution, 'resolved');
    expect(record?.latitude, 24.513);
    expect(record?.longitude, 117.6471);
    // And must not enqueue because the record was already resolved.
    expect(scheduler.enqueuedIds, isEmpty);
  });

  test(
    'reconcilePendingLocations resolves pending rows without enqueuing',
    () async {
      await seedPendingLocationCapture(id: 'capture-1');
      await seedPendingLocationCapture(id: 'capture-2');
      platform.exifLatitude = 24.513;
      platform.exifLongitude = 117.6471;

      await coordinator.reconcilePendingLocations();

      final first = await database.captureById('capture-1');
      final second = await database.captureById('capture-2');
      expect(first?.locationResolution, 'resolved');
      expect(second?.locationResolution, 'resolved');
      // Reconciliation only resolves location; queue reconciliation enqueues.
      expect(scheduler.enqueuedIds, isEmpty);
    },
  );

  test('inspectImage failure falls back to the record-scoped future', () async {
    await seedPendingLocationCapture();
    platform.inspectError = StateError('exif read failed');
    final fallback = Future.value(
      LocationResult(
        outcome: LocationOutcome.approximate,
        latitude: 35.6762,
        longitude: 139.6503,
        accuracyMeters: 1500,
      ),
    );

    await coordinator.resolve('capture-1', fallback: fallback, enqueue: true);

    final record = await database.captureById('capture-1');
    expect(record?.locationResolution, 'resolved');
    expect(record?.locationOutcome, 'approximate');
    expect(record?.latitude, 35.6762);
    expect(record?.longitude, 139.6503);
    expect(scheduler.enqueuedIds, ['capture-1']);
  });

  test('begin fire-and-forgets resolution and enqueue', () async {
    await seedPendingLocationCapture();
    platform.exifLatitude = 24.513;
    platform.exifLongitude = 117.6471;

    // begin() returns immediately (void); the resolution runs in the
    // background. Drain the microtask queue to let it complete.
    coordinator.begin('capture-1', fallback: null);
    // Drain the fire-and-forget microtask chain.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final record = await database.captureById('capture-1');
    expect(record?.locationResolution, 'resolved');
    expect(scheduler.enqueuedIds, ['capture-1']);
  });
}

class _CoordinatorPlatform implements PlatformServices {
  double? exifLatitude;
  double? exifLongitude;
  Object? inspectError;

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
  Future<String> publishJpeg(String sourcePath, String displayName) async =>
      'content://media/site-mark/1';

  @override
  Future<RecoveredCameraCapture?> recoverCameraCapture() async => null;

  @override
  Future<LocationResult> requestCurrentLocation(int timeoutMillis) async {
    return LocationResult(outcome: LocationOutcome.unavailable);
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
  Future<ImageMetadataResult> inspectImage(String path) async {
    final error = inspectError;
    if (error != null) throw error;
    return ImageMetadataResult(
      width: 0,
      height: 0,
      fileSizeBytes: 0,
      mimeType: 'image/jpeg',
      latitude: exifLatitude,
      longitude: exifLongitude,
    );
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
