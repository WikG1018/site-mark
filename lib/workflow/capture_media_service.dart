import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_file_info.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/domain/original_photo_state.dart';
import 'package:sitemark/platform/platform_services.dart';

/// Outcome of a batched media operation against a list of capture IDs.
///
/// [succeededIds] are processed in order; [skippedIds] were no-ops (e.g.
/// already-cleared originals); [failures] maps a capture ID to the error
/// message produced while processing that row. Failed rows are preserved so
/// the caller can retry them.
class CaptureActionResult {
  const CaptureActionResult({
    required this.succeededIds,
    required this.skippedIds,
    required this.failures,
  });

  final List<String> succeededIds;
  final List<String> skippedIds;
  final Map<String, String> failures;
}

class CaptureMediaService {
  CaptureMediaService({
    required this.database,
    required this.platform,
    required this.outputPaths,
    required this.files,
  });

  final AppDatabase database;
  final PlatformServices platform;
  final CaptureOutputPaths outputPaths;
  final PrivateFileStore files;

  Future<OriginalPhotoState> originalState(CaptureRecord record) async {
    if (record.originalDeletedAt != null) {
      return OriginalPhotoState.cleared;
    }
    return await files.exists(record.originalPath)
        ? OriginalPhotoState.retained
        : OriginalPhotoState.missing;
  }

  Future<CaptureFileInfo> inspect(CaptureRecord record) async {
    final state = await originalState(record);
    final watermarkedPath = await outputPaths.renderedPhotoPath(record.id);
    return CaptureFileInfo(
      originalState: state,
      original: await _inspectPath(record.originalPath),
      watermarked: await _inspectPath(watermarkedPath),
    );
  }

  /// Deletes the retained original file for each capture and marks the row
  /// cleared. Permits `ready` and `failed` rows; already-cleared rows are
  /// skipped; unexpectedly missing originals are recorded as failures. The
  /// watermarked file, published image, photo number, and SHA-256 evidence
  /// are preserved.
  Future<CaptureActionResult> clearOriginals(List<String> captureIds) async {
    final succeeded = <String>[];
    final skipped = <String>[];
    final failures = <String, String>{};
    for (final id in captureIds) {
      try {
        final record = await database.captureById(id);
        if (record == null) {
          failures[id] = 'Capture record does not exist';
          continue;
        }
        if (record.status != CaptureStatus.ready &&
            record.status != CaptureStatus.failed) {
          failures[id] =
              'Only ready or failed captures can have originals cleared';
          continue;
        }
        if (record.originalDeletedAt != null) {
          skipped.add(id);
          continue;
        }
        if (!await files.exists(record.originalPath)) {
          failures[id] = 'Original photo is unexpectedly missing';
          continue;
        }
        await files.deleteIfExists(record.originalPath);
        await database.markOriginalDeleted(id);
        succeeded.add(id);
      } catch (error) {
        failures[id] = error.toString();
      }
    }
    return CaptureActionResult(
      succeededIds: succeeded,
      skippedIds: skipped,
      failures: failures,
    );
  }

  /// Removes the published image, original file, rendered file, and database
  /// row for each capture in [captureIds]. Permits `ready` and `failed` rows.
  /// The exact deletion order per row is:
  ///   1. `deletePublishedImage(publishedUri)` (when set)
  ///   2. `deleteIfExists(originalPath)`
  ///   3. `deleteIfExists(renderedPhotoPath(id))`
  ///   4. `deleteCapture(id)`
  /// Per-record exceptions are caught, the row is preserved for retry, and
  /// processing continues with later IDs.
  Future<CaptureActionResult> deleteAll(List<String> captureIds) async {
    final succeeded = <String>[];
    final skipped = <String>[];
    final failures = <String, String>{};
    for (final id in captureIds) {
      try {
        final record = await database.captureById(id);
        if (record == null) {
          failures[id] = 'Capture record does not exist';
          continue;
        }
        if (record.status != CaptureStatus.ready &&
            record.status != CaptureStatus.failed) {
          failures[id] = 'Only ready or failed captures can be deleted';
          continue;
        }
        if (record.publishedUri != null) {
          await platform.deletePublishedImage(record.publishedUri!);
        }
        await files.deleteIfExists(record.originalPath);
        await files.deleteIfExists(await outputPaths.renderedPhotoPath(id));
        await database.deleteCapture(id);
        succeeded.add(id);
      } catch (error) {
        failures[id] = error.toString();
      }
    }
    return CaptureActionResult(
      succeededIds: succeeded,
      skippedIds: skipped,
      failures: failures,
    );
  }

  /// Re-publishes the watermarked JPEG for each `ready` capture and persists
  /// the returned MediaStore URI. Requires the rendered file to exist on disk.
  /// Captures in any status other than `ready` are recorded as failures.
  Future<CaptureActionResult> republish(List<String> captureIds) async {
    final succeeded = <String>[];
    final skipped = <String>[];
    final failures = <String, String>{};
    for (final id in captureIds) {
      try {
        final record = await database.captureById(id);
        if (record == null) {
          failures[id] = 'Capture record does not exist';
          continue;
        }
        if (record.status != CaptureStatus.ready) {
          failures[id] = 'Only ready captures can be republished';
          continue;
        }
        final renderedPath = await outputPaths.renderedPhotoPath(id);
        if (!await files.exists(renderedPath)) {
          failures[id] = 'Rendered photo is missing';
          continue;
        }
        final uri = await platform.publishJpeg(
          renderedPath,
          record.photoNumber!,
        );
        await database.updatePublishedUri(id, uri);
        succeeded.add(id);
      } catch (error) {
        failures[id] = error.toString();
      }
    }
    return CaptureActionResult(
      succeededIds: succeeded,
      skippedIds: skipped,
      failures: failures,
    );
  }

  Future<PhotoFileInfo?> _inspectPath(String path) async {
    if (!await files.exists(path)) return null;
    final metadata = await platform.inspectImage(path);
    return PhotoFileInfo(
      path: path,
      fileSizeBytes: metadata.fileSizeBytes,
      width: metadata.width,
      height: metadata.height,
      mimeType: metadata.mimeType,
    );
  }
}
