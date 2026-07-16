import 'dart:io';

import 'package:flutter/services.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/src/rust/api/image_core.dart';

/// Outcome of a single background processing pass for one capture.
///
/// The dispatcher returns `false` to WorkManager only for [retry]; every other
/// result resolves the work item so later captures in the serial chain run.
enum CaptureProcessResult {
  /// The capture was rendered and published; the record is now `ready`.
  succeeded,

  /// The record was already `ready` (or otherwise terminal); nothing to do.
  alreadyComplete,

  /// A transient failure occurred and the attempt budget is not yet exhausted.
  /// WorkManager should reschedule the work.
  retry,

  /// A permanent failure occurred (missing data, hash mismatch, or the third
  /// transient failure). The record is marked `failed`.
  failed,

  /// The record or its project no longer exists, or the record is in a state
  /// the background processor does not own (e.g. `pendingCamera`).
  missing,
}

/// Renders and publishes a single capture from the persistent queue.
///
/// [process] is idempotent: re-running it on a `ready` record returns
/// [CaptureProcessResult.alreadyComplete] without re-rendering or
/// re-publishing. The processing order is fixed by the SiteMark plan and must
/// not be reordered:
///
/// 1. Return [CaptureProcessResult.missing] if the record or project is gone.
/// 2. Return [CaptureProcessResult.alreadyComplete] for `ready`.
/// 3. Reject `pendingCamera` (foreground recovery owns it).
/// 4. Increment `processingAttempts` in one transaction.
/// 5. Verify original path, captured time, and photo number; permanent failure
///    otherwise.
/// 6. Compute SHA-256 when missing, or verify the current original against the
///    stored digest. A mismatch is a permanent failure (tampered original).
/// 7. Mark `rendering`, render to `rendered/<captureId>.jpg`, then publish using
///    the photo number (overwriting a same-named MediaStore entry).
/// 8. Mark `ready` with the returned URI.
/// 9. Return [CaptureProcessResult.retry] for IO/system failures while attempts
///    are below 3; on the third attempt mark `failed` and return
///    [CaptureProcessResult.failed].
final class CaptureProcessor {
  CaptureProcessor({
    required this.database,
    required this.platform,
    required this.images,
    required this.outputPaths,
  });

  final AppDatabase database;
  final PlatformServices platform;
  final ImagePipeline images;
  final CaptureOutputPaths outputPaths;

  /// Maximum number of processing attempts before a transient failure becomes
  /// permanent. The third failed attempt (i.e. `processingAttempts >= 3` after
  /// the increment in step 4) marks the record `failed`.
  static const int maxAttempts = 3;

  Future<CaptureProcessResult> process(String captureId) async {
    final record = await database.captureById(captureId);
    if (record == null) return CaptureProcessResult.missing;

    // Step 1: the project must still exist. The FK cascade usually removes the
    // capture with the project, but this guard is defensive.
    final project = await database.projectById(record.projectId);
    if (project == null) return CaptureProcessResult.missing;

    // Step 2: an already-ready record needs no further work.
    if (record.status == CaptureStatus.ready) {
      return CaptureProcessResult.alreadyComplete;
    }

    // Step 3: pendingCamera is owned by foreground camera recovery.
    if (record.status == CaptureStatus.pendingCamera) {
      return CaptureProcessResult.missing;
    }

    // Step 4: increment the attempt counter in a single transaction.
    final attempted = await database.incrementProcessingAttempts(captureId);
    final attempts = attempted.processingAttempts;

    // Step 5: verify the captured-time/photo-number/path evidence is present.
    // These are permanent failures regardless of attempt budget.
    final permanentMissing = _validateEvidence(attempted);
    if (permanentMissing != null) {
      await _failPermanently(captureId, permanentMissing);
      return CaptureProcessResult.failed;
    }

    // Step 6: hash the original (or verify it against the stored digest). A
    // missing original at this point (e.g. deleted between capture and a
    // resumed `process()`) is a permanent failure, consistent with render-time
    // handling: `PathNotFoundException` from `sha256` means the evidence file
    // is gone, so mark `failed` rather than letting it propagate unhandled
    // (which would leave the record with incremented attempts but no `failed`
    // marking).
    final _HashResult hashResult;
    try {
      hashResult = await _resolveOriginalSha256(attempted);
    } on PathNotFoundException catch (error) {
      await _failPermanently(captureId, error.toString());
      return CaptureProcessResult.failed;
    }
    if (hashResult.isMismatch) {
      await _failPermanently(
        captureId,
        'Original photo hash verification failed; the file was modified',
      );
      return CaptureProcessResult.failed;
    }

    // Steps 7-8: mark rendering, render, publish, mark ready. Transient errors
    // here are retried until the attempt budget is exhausted.
    try {
      final rendering = await database.markRendering(
        captureId: captureId,
        originalSha256: hashResult.sha256,
      );
      final renderedPath = await outputPaths.renderedPhotoPath(captureId);
      final renderResult = await images.render(
        RenderPhotoRequest(
          sourcePath: rendering.originalPath,
          outputPath: renderedPath,
          projectName: project.name,
          workLocation: rendering.workLocation,
          workContent: rendering.workContent,
          photographer: rendering.photographer,
          photoNumber: rendering.photoNumber!,
          capturedAt: _formatLocalTimestamp(rendering.capturedAt!),
          address: rendering.address,
          coordinates: _coordinates(rendering),
          notes: rendering.notes,
          position: _watermarkPosition(project),
          opacity: project.watermarkOpacity,
          accentColorArgb: project.watermarkAccentColorArgb,
        ),
      );
      final publishedUri = await platform.publishJpeg(
        renderResult.outputPath,
        rendering.photoNumber!,
      );
      await database.markReady(
        captureId: captureId,
        publishedUri: publishedUri,
      );
      return CaptureProcessResult.succeeded;
    } catch (error) {
      // Step 9: classify the error and decide retry vs. final failure.
      //
      // `PathNotFoundException` on the original at render time is a permanent
      // failure (the evidence file is gone). `FileSystemException` write
      // failures and other IO/system errors are transient and retried.
      if (_isTransient(error) && attempts < maxAttempts) {
        return CaptureProcessResult.retry;
      }
      await _failPermanently(captureId, error.toString());
      return CaptureProcessResult.failed;
    }
  }

  /// Returns a non-null reason string when required evidence is missing.
  String? _validateEvidence(CaptureRecord record) {
    if (record.originalPath.trim().isEmpty) {
      return 'Original photo path is missing';
    }
    if (record.capturedAt == null) {
      return 'Captured timestamp is missing';
    }
    if (record.photoNumber == null || record.photoNumber!.trim().isEmpty) {
      return 'Photo number is missing';
    }
    return null;
  }

  /// Resolves the SHA-256 digest of the original photo.
  ///
  /// When the record has no stored digest, it is computed and stored later via
  /// `markRendering`. When a digest is already present (a resumed `rendering`
  /// record), the current file is re-hashed and compared; a mismatch means the
  /// original was tampered with and is a permanent failure.
  Future<_HashResult> _resolveOriginalSha256(CaptureRecord record) async {
    final stored = record.originalSha256;
    final current = await images.sha256(record.originalPath);
    if (stored == null || stored.isEmpty) {
      return _HashResult(sha256: current.toLowerCase(), isMismatch: false);
    }
    return _HashResult(
      sha256: stored.toLowerCase(),
      isMismatch: current.toLowerCase() != stored.toLowerCase(),
    );
  }

  Future<void> _failPermanently(String captureId, String reason) async {
    try {
      await database.markFailed(captureId: captureId, reason: reason);
    } on StateError {
      // The record transitioned concurrently (e.g. another worker marked it
      // ready). There is nothing more to do; the caller's result still holds.
    }
  }

  bool _isTransient(Object error) {
    // `PathNotFoundException` extends `FileSystemException`, but a missing
    // original at render time is a permanent failure (evidence is gone), so it
    // must be checked before the broader `FileSystemException` branch.
    if (error is PathNotFoundException) return false;
    if (error is FileSystemException) return true;
    // `SocketException` (dart:io) is a public class whose runtimeType is
    // `SocketException`, not `_SocketException`; the previous runtimeType
    // string check was a dead branch. Use a proper `is` check so socket errors
    // during render/publish are retried.
    if (error is SocketException) return true;
    if (error is PlatformException) return true;
    if (error is OSError) return true;
    return false;
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

class _HashResult {
  _HashResult({required this.sha256, required this.isMismatch});

  final String sha256;
  final bool isMismatch;
}
