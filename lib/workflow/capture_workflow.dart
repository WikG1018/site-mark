import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/platform/system_api.g.dart';
import 'package:sitemark/src/rust/api/image_core.dart';
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

enum CaptureWorkflowOutcome { ready, cancelled, failed }

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
          return _renderAndPublish(
            captureId: captureId,
            originalPath: originalPath,
            draft: draft,
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
      return await _renderAndPublish(
        captureId: recovered.captureId,
        originalPath: recovered.outputPath,
        draft: CaptureDraft(
          projectId: project.id,
          projectName: project.name,
          workLocation: record.workLocation,
          workContent: record.workContent,
          photographer: record.photographer,
          notes: record.notes,
        ),
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

  Future<CaptureRecord> regenerateCapture({
    required String captureId,
    required CaptureEdits edits,
  }) async {
    final record = await database.captureById(captureId);
    if (record == null) throw StateError('Capture record does not exist');
    if (record.status != CaptureStatus.ready) {
      throw StateError('Only completed captures can be regenerated');
    }
    final project = await database.projectById(record.projectId);
    if (project == null) throw StateError('Project does not exist');
    final expectedHash = record.originalSha256;
    if (expectedHash == null) throw StateError('Original hash is missing');
    final actualHash = await images.sha256(record.originalPath);
    if (actualHash.toLowerCase() != expectedHash.toLowerCase()) {
      throw StateError('Original photo hash verification failed');
    }
    final renderedPath = await outputPaths.renderedPhotoPath(captureId);
    final rendered = await images.render(
      RenderPhotoRequest(
        sourcePath: record.originalPath,
        outputPath: renderedPath,
        projectName: project.name,
        workLocation: edits.workLocation,
        workContent: edits.workContent,
        photographer: edits.photographer,
        photoNumber: record.photoNumber!,
        capturedAt: _formatLocalTimestamp(record.capturedAt!),
        address: record.address,
        coordinates: _coordinates(record),
        notes: edits.notes,
        position: _watermarkPosition(project),
        opacity: project.watermarkOpacity,
        accentColorArgb: project.watermarkAccentColorArgb,
      ),
    );
    await platform.publishJpeg(rendered.outputPath, record.photoNumber!);
    return database.updateCaptureDescription(
      captureId: captureId,
      workLocation: edits.workLocation,
      workContent: edits.workContent,
      photographer: edits.photographer,
      notes: edits.notes,
    );
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

  Future<CaptureWorkflowResult> _renderAndPublish({
    required String captureId,
    required String originalPath,
    required CaptureDraft draft,
  }) async {
    final project = await database.projectById(draft.projectId);
    if (project == null) throw StateError('Project does not exist');
    final capturedAt = _now();
    final captured = await database.markCaptured(
      captureId: captureId,
      capturedAt: capturedAt,
    );
    final originalSha256 = await images.sha256(originalPath);
    await database.markRendering(
      captureId: captureId,
      originalSha256: originalSha256,
    );
    final renderedPath = await outputPaths.renderedPhotoPath(captureId);
    final renderResult = await images.render(
      RenderPhotoRequest(
        sourcePath: originalPath,
        outputPath: renderedPath,
        projectName: draft.projectName,
        workLocation: draft.workLocation,
        workContent: draft.workContent,
        photographer: draft.photographer,
        photoNumber: captured.photoNumber!,
        capturedAt: _formatLocalTimestamp(capturedAt),
        address: captured.address,
        coordinates: _coordinates(captured),
        notes: draft.notes,
        position: _watermarkPosition(project),
        opacity: project.watermarkOpacity,
        accentColorArgb: project.watermarkAccentColorArgb,
      ),
    );
    final publishedUri = await platform.publishJpeg(
      renderResult.outputPath,
      captured.photoNumber!,
    );
    final ready = await database.markReady(
      captureId: captureId,
      publishedUri: publishedUri,
    );
    await platform.finishCameraCapture(captureId, true);
    return CaptureWorkflowResult(
      outcome: CaptureWorkflowOutcome.ready,
      capture: ready,
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

  String? _coordinates(CaptureRecord capture) {
    if (capture.latitude == null || capture.longitude == null) return null;
    return '${capture.latitude!.toStringAsFixed(6)}, '
        '${capture.longitude!.toStringAsFixed(6)}'
        '${capture.accuracyMeters == null ? '' : ' · ±${capture.accuracyMeters!.round()}m'}';
  }

  WatermarkPosition _watermarkPosition(Project project) {
    return project.watermarkPosition == 'bottomRight'
        ? WatermarkPosition.bottomRight
        : WatermarkPosition.bottomLeft;
  }

  String _formatLocalTimestamp(DateTime value) {
    final offset = value.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final absoluteMinutes = offset.inMinutes.abs();
    final offsetHours = (absoluteMinutes ~/ 60).toString().padLeft(2, '0');
    final offsetMinutes = (absoluteMinutes % 60).toString().padLeft(2, '0');
    String two(int part) => part.toString().padLeft(2, '0');
    return '${value.year.toString().padLeft(4, '0')}-'
        '${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)} '
        '$sign$offsetHours:$offsetMinutes';
  }
}
