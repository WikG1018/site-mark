import 'package:sitemark/background/capture_background_scheduler.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_failure.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/domain/project_lifecycle.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/capture_location_coordinator.dart';
import 'package:sitemark/workflow/capture_media_service.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';
import 'package:uuid/uuid.dart';

class CaptureDraft {
  const CaptureDraft({
    required this.projectId,
    required this.projectName,
    required this.workLocation,
    required this.workContent,
    required this.photographer,
    required this.watermarkLocaleCode,
    this.notes,
    this.useLocationFallback = true,
  });

  final String projectId;
  final String projectName;
  final String workLocation;
  final String workContent;
  final String photographer;
  final String? notes;

  /// Whether the capture workflow may attempt a foreground location read.
  ///
  /// Defaults to `true` so callers that do not surface the non-blocking
  /// permission UX keep the historical behaviour. Set to `false` when the host
  /// permission is not `granted` so the capture button path never triggers a
  /// runtime permission request via `requestCurrentLocation`.
  final bool useLocationFallback;

  /// Locale code snapshotted from the host UI at capture time so background
  /// rendering reproduces the watermark in the user's selected language.
  final String watermarkLocaleCode;
}

class CaptureEdits {
  const CaptureEdits({
    required this.workLocation,
    required this.workContent,
    required this.photographer,
    this.notes,
  });

  final String workLocation;
  final String workContent;
  final String photographer;
  final String? notes;
}

/// Outcome of a foreground capture coordination step.
///
/// `queued` means the capture was marked `captured` and WorkManager accepted a
/// background task. `delayed` means the original and database row are durable,
/// but the first queue registration failed; the location coordinator retries
/// the wake-up in the current session and startup recovery remains the fallback.
enum CaptureWorkflowOutcome { queued, delayed, cancelled, failed }

/// Local milestones between a capture-button tap and the request to open the
/// system camera. These diagnostics are opt-in and never contain capture data.
enum CaptureLaunchPhase {
  targetPrepared,
  pendingRecordPersisted,
  cameraLaunchRequested,
}

class CaptureLaunchTiming {
  const CaptureLaunchTiming({required this.phase, required this.elapsed});

  final CaptureLaunchPhase phase;
  final Duration elapsed;
}

typedef CaptureLaunchTimingCallback = void Function(CaptureLaunchTiming timing);

class CaptureWorkflowResult {
  const CaptureWorkflowResult({
    required this.outcome,
    this.capture,
    this.failureCode,
  });

  final CaptureWorkflowOutcome outcome;
  final CaptureRecord? capture;
  final CaptureFailureCode? failureCode;
}

class CaptureWorkflow {
  CaptureWorkflow({
    required this.database,
    required this.platform,
    required this.scheduler,
    required this.images,
    required this.outputPaths,
    required this.locationCoordinator,
    PrivateFileStore? fileStore,
    CaptureMediaService? mediaService,
    String Function()? idFactory,
    DateTime Function()? now,
    this.onLaunchTiming,
  }) : _idFactory = idFactory ?? const Uuid().v4,
       _now = now ?? DateTime.now,
       _fileStore = fileStore ?? DartIoPrivateFileStore() {
    _mediaService =
        mediaService ??
        CaptureMediaService(
          database: database,
          platform: platform,
          outputPaths: outputPaths,
          files: _fileStore,
        );
  }

  final AppDatabase database;
  final PlatformServices platform;
  final CaptureBackgroundScheduler scheduler;
  final ImagePipeline images;
  final CaptureOutputPaths outputPaths;
  final CaptureLocationCoordinator locationCoordinator;
  final PrivateFileStore _fileStore;
  late final CaptureMediaService _mediaService;
  final String Function() _idFactory;
  final DateTime Function() _now;
  final CaptureLaunchTimingCallback? onLaunchTiming;

  Future<CaptureWorkflowResult> capture(CaptureDraft draft) async {
    final captureId = _idFactory();
    final launchStopwatch = onLaunchTiming == null
        ? null
        : (Stopwatch()..start());
    // Start the location read (if permitted) without awaiting it so the camera
    // launches immediately. The coordinator consumes this future only when EXIF
    // GPS is missing.
    final locationFuture = draft.useLocationFallback
        ? _safeLocation(draft.useLocationFallback)
        : null;
    String? originalPath;
    var keepOriginalOnFailure = false;
    try {
      originalPath = await platform.createCameraTarget(captureId);
      _reportLaunchTiming(CaptureLaunchPhase.targetPrepared, launchStopwatch);
      await database.createPendingCapture(
        id: captureId,
        projectId: draft.projectId,
        originalPath: originalPath,
        workLocation: draft.workLocation,
        workContent: draft.workContent,
        photographer: draft.photographer,
        watermarkLocaleCode: draft.watermarkLocaleCode,
        notes: draft.notes,
        createdAt: _now(),
      );
      _reportLaunchTiming(
        CaptureLaunchPhase.pendingRecordPersisted,
        launchStopwatch,
      );
      _reportLaunchTiming(
        CaptureLaunchPhase.cameraLaunchRequested,
        launchStopwatch,
      );
      final camera = await platform.launchCamera(captureId);
      switch (camera.outcome) {
        case CameraOutcome.cancelled:
          await database.deleteCapture(captureId);
          await platform.finishCameraCapture(captureId, false);
          return const CaptureWorkflowResult(
            outcome: CaptureWorkflowOutcome.cancelled,
          );
        case CameraOutcome.failed:
          final failed = await database.markFailed(
            captureId: captureId,
            reason: CaptureFailureCode.cameraUnavailable.storageCode,
          );
          await platform.finishCameraCapture(captureId, false);
          return CaptureWorkflowResult(
            outcome: CaptureWorkflowOutcome.failed,
            capture: failed,
            failureCode: CaptureFailureCode.cameraUnavailable,
          );
        case CameraOutcome.captured:
          keepOriginalOnFailure = true;
          final result = await _captureAndEnqueue(
            captureId: captureId,
            originalPath: originalPath,
          );
          locationCoordinator.begin(captureId, fallback: locationFuture);
          return result;
      }
    } on ProjectReadOnlyException {
      if (originalPath != null) {
        await platform.finishCameraCapture(captureId, false);
      }
      rethrow;
    } catch (error) {
      final record = await database.captureById(captureId);
      CaptureRecord? failed;
      if (record != null && record.status != CaptureStatus.ready) {
        try {
          failed = await database.markFailed(
            captureId: captureId,
            reason: CaptureFailureCode.unexpected.storageCode,
          );
        } on StateError {
          failed = record;
        }
      }
      if (originalPath != null) {
        await platform.finishCameraCapture(captureId, keepOriginalOnFailure);
      }
      return CaptureWorkflowResult(
        outcome: CaptureWorkflowOutcome.failed,
        capture: failed,
        failureCode: CaptureFailureCode.unexpected,
      );
    }
  }

  void _reportLaunchTiming(CaptureLaunchPhase phase, Stopwatch? stopwatch) {
    final callback = onLaunchTiming;
    if (callback == null || stopwatch == null) return;
    try {
      callback(CaptureLaunchTiming(phase: phase, elapsed: stopwatch.elapsed));
    } on Object {
      // Diagnostics must never delay or fail the capture path.
    }
  }

  Future<CaptureWorkflowResult?> recoverPendingCapture() async {
    final recovered = await platform.recoverCameraCapture();
    if (recovered == null) return null;
    final record = await database.captureById(recovered.captureId);
    if (record == null) {
      await platform.finishCameraCapture(recovered.captureId, false);
      return const CaptureWorkflowResult(
        outcome: CaptureWorkflowOutcome.cancelled,
      );
    }
    if (record.status != CaptureStatus.pendingCamera) {
      await platform.finishCameraCapture(recovered.captureId, true);
      if (record.status == CaptureStatus.captured ||
          record.status == CaptureStatus.rendering) {
        try {
          await scheduler.enqueue(recovered.captureId);
        } catch (_) {
          return CaptureWorkflowResult(
            outcome: CaptureWorkflowOutcome.delayed,
            capture: record,
          );
        }
        return CaptureWorkflowResult(
          outcome: CaptureWorkflowOutcome.queued,
          capture: record,
        );
      }
      return CaptureWorkflowResult(
        outcome: record.status == CaptureStatus.failed
            ? CaptureWorkflowOutcome.failed
            : CaptureWorkflowOutcome.queued,
        capture: record,
      );
    }
    if (!recovered.hasContent) {
      await database.deleteCapture(recovered.captureId);
      await platform.finishCameraCapture(recovered.captureId, false);
      return const CaptureWorkflowResult(
        outcome: CaptureWorkflowOutcome.cancelled,
      );
    }
    final project = await database.projectById(record.projectId);
    if (project == null) {
      await database.deleteCapture(recovered.captureId);
      await platform.finishCameraCapture(recovered.captureId, false);
      return const CaptureWorkflowResult(
        outcome: CaptureWorkflowOutcome.cancelled,
      );
    }
    try {
      final result = await _captureAndEnqueue(
        captureId: recovered.captureId,
        originalPath: recovered.outputPath,
      );
      locationCoordinator.begin(recovered.captureId, fallback: null);
      return result;
    } catch (error) {
      CaptureRecord failed = record;
      final latest = await database.captureById(recovered.captureId);
      if (latest != null && latest.status != CaptureStatus.ready) {
        try {
          failed = await database.markFailed(
            captureId: recovered.captureId,
            reason: CaptureFailureCode.unexpected.storageCode,
          );
        } on StateError {
          failed = latest;
        }
      }
      await platform.finishCameraCapture(recovered.captureId, true);
      return CaptureWorkflowResult(
        outcome: CaptureWorkflowOutcome.failed,
        capture: failed,
        failureCode: CaptureFailureCode.unexpected,
      );
    }
  }

  /// Updates editable fields, resets processing state, and re-enqueues the
  /// capture for background re-rendering. The record is returned in the
  /// `captured` status; the caller should observe the `ready` transition via
  /// [AppDatabase.watchCaptureById] rather than waiting inline.
  Future<CaptureRecord> regenerateCapture({
    required String captureId,
    required CaptureEdits edits,
  }) async {
    final record = await database.captureById(captureId);
    if (record == null) throw StateError('Capture record does not exist');
    // Regeneration is allowed from `ready` (re-publish with edits) or `failed`
    // (retry after a permanent failure). Other states are not editable here.
    if (record.status != CaptureStatus.ready &&
        record.status != CaptureStatus.failed) {
      throw StateError('Only completed or failed captures can be regenerated');
    }
    // Regeneration requires the private original to be present on disk so the
    // background processor can re-render the watermark from it. Clearing the
    // original is irreversible; once cleared the row can no longer be
    // regenerated.
    if (record.originalDeletedAt != null ||
        !await _fileStore.exists(record.originalPath)) {
      throw StateError('Original photo is not available');
    }
    // Apply the descriptive edits first so they survive the state reset.
    await database.updateCaptureDescription(
      captureId: captureId,
      workLocation: edits.workLocation,
      workContent: edits.workContent,
      photographer: edits.photographer,
      notes: edits.notes,
    );
    // Reset attempts and state to `captured` so the processor re-renders from
    // scratch (clearing the stale published URI and hash). The edited
    // description fields persist because the reset does not touch them.
    final reset = await database.resetCaptureForRetry(captureId);
    await scheduler.enqueue(captureId);
    return reset;
  }

  Future<void> deleteCapture(String captureId) async {
    await _mediaService.deleteAll([captureId]);
  }

  /// Marks the capture `captured`, finishes the camera target keeping the
  /// original, and waits only for the lightweight WorkManager registration.
  /// Location resolution, rendering and publishing remain asynchronous.
  Future<CaptureWorkflowResult> _captureAndEnqueue({
    required String captureId,
    required String originalPath,
  }) async {
    final captured = await database.markCaptured(
      captureId: captureId,
      capturedAt: _now(),
    );
    await platform.finishCameraCapture(captureId, true);
    try {
      await scheduler.enqueue(captureId);
    } catch (_) {
      return CaptureWorkflowResult(
        outcome: CaptureWorkflowOutcome.delayed,
        capture: captured,
      );
    }
    return CaptureWorkflowResult(
      outcome: CaptureWorkflowOutcome.queued,
      capture: captured,
    );
  }

  Future<LocationResult> _safeLocation(bool useLocationFallback) async {
    // Skip the platform location read when the host permission is not granted
    // so the capture button path never triggers a runtime permission request.
    if (!useLocationFallback) {
      return LocationResult(outcome: LocationOutcome.unavailable);
    }
    try {
      return await platform.requestCurrentLocation(10_000);
    } catch (error) {
      return LocationResult(
        outcome: LocationOutcome.unavailable,
        errorMessage: error.toString(),
      );
    }
  }
}
