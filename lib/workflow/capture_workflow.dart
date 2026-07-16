import 'package:sitemark/background/capture_background_scheduler.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';
import 'package:uuid/uuid.dart';

class CaptureDraft {
  const CaptureDraft({
    required this.projectId,
    required this.projectName,
    required this.workLocation,
    required this.workContent,
    required this.photographer,
    this.notes,
  });

  final String projectId;
  final String projectName;
  final String workLocation;
  final String workContent;
  final String photographer;
  final String? notes;
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
/// `queued` means the capture was marked `captured` and enqueued for background
/// rendering/publishing; the UI should not wait for the watermarked result.
enum CaptureWorkflowOutcome { queued, cancelled, failed }

class CaptureWorkflowResult {
  const CaptureWorkflowResult({
    required this.outcome,
    this.capture,
    this.errorMessage,
  });

  final CaptureWorkflowOutcome outcome;
  final CaptureRecord? capture;
  final String? errorMessage;
}

class CaptureWorkflow {
  CaptureWorkflow({
    required this.database,
    required this.platform,
    required this.scheduler,
    required this.images,
    required this.outputPaths,
    PrivateFileStore? fileStore,
    String Function()? idFactory,
    DateTime Function()? now,
  }) : _idFactory = idFactory ?? const Uuid().v4,
       _now = now ?? DateTime.now,
       _fileStore = fileStore ?? DartIoPrivateFileStore();

  final AppDatabase database;
  final PlatformServices platform;
  final CaptureBackgroundScheduler scheduler;
  final ImagePipeline images;
  final CaptureOutputPaths outputPaths;
  final PrivateFileStore _fileStore;
  final String Function() _idFactory;
  final DateTime Function() _now;

  Future<CaptureWorkflowResult> capture(CaptureDraft draft) async {
    final captureId = _idFactory();
    final location = await _safeLocation();
    String? originalPath;
    var keepOriginalOnFailure = false;
    try {
      originalPath = await platform.createCameraTarget(captureId);
      await database.createPendingCapture(
        id: captureId,
        projectId: draft.projectId,
        originalPath: originalPath,
        workLocation: draft.workLocation,
        workContent: draft.workContent,
        photographer: draft.photographer,
        notes: draft.notes,
        createdAt: _now(),
        latitude: location.latitude,
        longitude: location.longitude,
        accuracyMeters: location.accuracyMeters,
        address: location.address,
        locationOutcome: location.outcome.name,
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
            reason: camera.errorMessage ?? 'System camera failed',
          );
          await platform.finishCameraCapture(captureId, false);
          return CaptureWorkflowResult(
            outcome: CaptureWorkflowOutcome.failed,
            capture: failed,
            errorMessage: camera.errorMessage,
          );
        case CameraOutcome.captured:
          keepOriginalOnFailure = true;
          return _captureAndEnqueue(
            captureId: captureId,
            originalPath: originalPath,
          );
      }
    } catch (error) {
      final record = await database.captureById(captureId);
      CaptureRecord? failed;
      if (record != null && record.status != CaptureStatus.ready) {
        try {
          failed = await database.markFailed(
            captureId: captureId,
            reason: error.toString(),
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
        errorMessage: error.toString(),
      );
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
      return await _captureAndEnqueue(
        captureId: recovered.captureId,
        originalPath: recovered.outputPath,
      );
    } catch (error) {
      CaptureRecord failed = record;
      final latest = await database.captureById(recovered.captureId);
      if (latest != null && latest.status != CaptureStatus.ready) {
        try {
          failed = await database.markFailed(
            captureId: recovered.captureId,
            reason: error.toString(),
          );
        } on StateError {
          failed = latest;
        }
      }
      await platform.finishCameraCapture(recovered.captureId, true);
      return CaptureWorkflowResult(
        outcome: CaptureWorkflowOutcome.failed,
        capture: failed,
        errorMessage: error.toString(),
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
    final record = await database.captureById(captureId);
    if (record == null) return;
    if (record.publishedUri != null) {
      await platform.deletePublishedImage(record.publishedUri!);
    }
    final renderedPath = await outputPaths.renderedPhotoPath(captureId);
    for (final path in [record.originalPath, renderedPath]) {
      await _fileStore.deleteIfExists(path);
    }
    await database.deleteCapture(captureId);
  }

  /// Marks the capture `captured`, finishes the camera target keeping the
  /// original, enqueues background processing, and returns the queued result.
  Future<CaptureWorkflowResult> _captureAndEnqueue({
    required String captureId,
    required String originalPath,
  }) async {
    final captured = await database.markCaptured(
      captureId: captureId,
      capturedAt: _now(),
    );
    await platform.finishCameraCapture(captureId, true);
    await scheduler.enqueue(captureId);
    return CaptureWorkflowResult(
      outcome: CaptureWorkflowOutcome.queued,
      capture: captured,
    );
  }

  Future<LocationResult> _safeLocation() async {
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
