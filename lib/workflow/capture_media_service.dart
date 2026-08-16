import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_file_info.dart';
import 'package:sitemark/domain/capture_media_failure.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/domain/original_photo_state.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/capture_media_cleanup_store.dart';

/// Outcome of a batched media operation against a list of capture IDs.
///
/// [succeededIds] are processed in order; [skippedIds] were no-ops (e.g.
/// already-cleared originals); [failures] maps a capture ID to the reason
/// processing failed for that row. Failed rows are preserved so the caller
/// can retry them. Reasons are enums — user-facing wording is owned by the
/// UI, so raw exceptions and private paths can never reach the user.
class CaptureActionResult {
  const CaptureActionResult({
    required this.succeededIds,
    required this.skippedIds,
    required this.failures,
  });

  final List<String> succeededIds;
  final List<String> skippedIds;
  final Map<String, CaptureMediaFailure> failures;
}

class CaptureMediaService {
  CaptureMediaService({
    required this.database,
    required this.platform,
    required this.outputPaths,
    required this.files,
    CaptureMediaCleanupPendingStore? pendingStore,
  }) : pendingStore = pendingStore ?? MemoryCaptureMediaCleanupPendingStore();

  final AppDatabase database;
  final PlatformServices platform;
  final CaptureOutputPaths outputPaths;
  final PrivateFileStore files;
  final CaptureMediaCleanupPendingStore pendingStore;

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
    final failures = <String, CaptureMediaFailure>{};
    for (final id in captureIds) {
      try {
        final record = await database.captureById(id);
        if (record == null) {
          failures[id] = CaptureMediaFailure.recordMissing;
          continue;
        }
        if (record.status != CaptureStatus.ready &&
            record.status != CaptureStatus.failed) {
          failures[id] = CaptureMediaFailure.clearStatusNotAllowed;
          continue;
        }
        if (record.originalDeletedAt != null) {
          skipped.add(id);
          continue;
        }
        if (!await files.exists(record.originalPath)) {
          failures[id] = CaptureMediaFailure.originalMissing;
          continue;
        }
        final pending = PendingCaptureMediaCleanup(
          captureId: id,
          kind: CaptureMediaCleanupKind.clearOriginal,
          paths: [record.originalPath],
        );
        await pendingStore.write(pending);
        await database.markOriginalDeleted(id);
        await _finishCleanup(pending);
        succeeded.add(id);
      } catch (_) {
        failures[id] = CaptureMediaFailure.operationFailed;
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
  /// The exact durable deletion order per row is:
  ///   1. persist an app-private cleanup marker
  ///   2. `deleteCapture(id)` (the logical commit point)
  ///   3. remove the published image and private files, then the marker
  /// A crash or media cleanup failure after the commit point is retried by
  /// [cleanupInterrupted]. Per-record exceptions remain isolated. Once the
  /// database commit succeeds, leftover media cleanup is durable and
  /// therefore does not turn the user's completed action into a failure.
  Future<CaptureActionResult> deleteAll(List<String> captureIds) async {
    final succeeded = <String>[];
    final skipped = <String>[];
    final failures = <String, CaptureMediaFailure>{};
    for (final id in captureIds) {
      try {
        final record = await database.captureById(id);
        if (record == null) {
          failures[id] = CaptureMediaFailure.recordMissing;
          continue;
        }
        if (record.status != CaptureStatus.ready &&
            record.status != CaptureStatus.failed) {
          failures[id] = CaptureMediaFailure.deleteStatusNotAllowed;
          continue;
        }
        final pending = PendingCaptureMediaCleanup(
          captureId: id,
          kind: CaptureMediaCleanupKind.deleteCapture,
          paths: [record.originalPath, await outputPaths.renderedPhotoPath(id)],
          publishedUri: record.publishedUri,
        );
        await pendingStore.write(pending);
        await database.deleteCapture(id);
        await _finishCleanup(pending);
        succeeded.add(id);
      } catch (_) {
        failures[id] = CaptureMediaFailure.operationFailed;
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
    final failures = <String, CaptureMediaFailure>{};
    for (final id in captureIds) {
      try {
        final record = await database.captureById(id);
        if (record == null) {
          failures[id] = CaptureMediaFailure.recordMissing;
          continue;
        }
        if (record.status != CaptureStatus.ready) {
          failures[id] = CaptureMediaFailure.republishStatusNotAllowed;
          continue;
        }
        final renderedPath = await outputPaths.renderedPhotoPath(id);
        if (!await files.exists(renderedPath)) {
          failures[id] = CaptureMediaFailure.renderedPhotoMissing;
          continue;
        }
        // Key the publish by THIS capture's ID and pass its exact previous
        // URI: a backup restore preserves photo numbers, so another record
        // (even in another project) may own a same-named gallery row that
        // must never be superseded by this publish.
        final outcome = await platform.publishJpeg(
          renderedPath,
          record.photoNumber!,
          id,
          record.publishedUri,
        );
        // The new URI and a delete-only cleanup task per stale duplicate URI
        // commit in ONE database transaction: a process death (or a failed
        // queue write) can no longer lose the tracking of a duplicate. A
        // failure here retries the whole republish later — it must not be
        // swallowed, or an untracked duplicate would linger forever.
        await database.updatePublishedUri(
          id,
          outcome.contentUri,
          supersededUris: outcome.supersededUris,
        );
        // The database commit survived, so the native publish journal has
        // served its purpose; a crash before this point is reconciled by
        // [_recoverPublishJournals] on the next launch. This clear is
        // BEST-EFFORT: a stale journal never turns the completed republish
        // into a failure — recovery sees `ready` + matching URI and clears
        // the journal on the next launch.
        try {
          await platform.clearPublishJournal(id);
        } catch (_) {}
        succeeded.add(id);
      } catch (_) {
        failures[id] = CaptureMediaFailure.operationFailed;
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

  /// Resumes media cleanup whose user-visible database commit survived a
  /// process death. Each marker is isolated so one bad file cannot block the
  /// remaining recovery work.
  ///
  /// Superseded-URI deletes come from the durable `capture_media_cleanups`
  /// table (one row per stale URI, committed transactionally with the new
  /// `publishedUri`). Recovery retries ONLY the delete — never a re-publish —
  /// and completes each task independently, so sibling tasks survive a
  /// failing or succeeding neighbor.
  Future<void> cleanupInterrupted() async {
    final pendings = await pendingStore.list();
    for (final pending in pendings) {
      try {
        final record = await database.captureById(pending.captureId);
        final committed = switch (pending.kind) {
          CaptureMediaCleanupKind.clearOriginal =>
            record == null || record.originalDeletedAt != null,
          CaptureMediaCleanupKind.deleteCapture => record == null,
        };
        if (!committed) {
          // The database commit never happened. Preserve media that the live
          // row can still reference and discard only the pre-commit marker.
          await pendingStore.clear(pending.captureId, pending.kind);
          continue;
        }
        await _finishCleanup(pending);
      } catch (_) {
        // Keep the durable marker for a later launch and continue with others.
      }
    }
    await _recoverPublishJournals();
    await _cleanupSuperseded();
  }

  /// Reconciles natively journaled publishes against the database.
  ///
  /// The journal entry is written by the Android publisher AFTER the new
  /// MediaStore row is finalized but BEFORE the superseded rows are deleted.
  /// It closes the crash window that the Drift transaction cannot cover —
  /// the gap between the native publish and the Dart database commit:
  ///
  /// - Row already points at the journaled URI → the commit survived and
  ///   only the journal is stale → clear it.
  /// - `ready` row still points at an older URI → the commit never
  ///   happened → adopt the journaled URI and queue deletes for every
  ///   stale candidate (already-deleted rows are an idempotent no-op).
  /// - Row is `captured`/`rendering` → the background processor will
  ///   re-publish and overwrite this journal; keep it and let the normal
  ///   flow converge.
  /// - Row is gone or terminal-without-retry (`failed`) → nothing will ever
  ///   reference the journaled URI → queue the new and stale URIs for
  ///   delete-only cleanup and clear the journal.
  ///
  /// The journal is keyed by the capture's stable ID, so the row is located
  /// by `captureById` — NEVER by photo number, which a backup restore can
  /// duplicate across projects (reconciling by number could write THIS
  /// capture's URI into ANOTHER capture's row).
  Future<void> _recoverPublishJournals() async {
    final journals = await platform.recoverPublishJournals();
    for (final journal in journals) {
      try {
        final record = await database.captureById(journal.captureId);
        if (record == null) {
          await database.enqueueSupersededCleanups(journal.captureId, [
            journal.contentUri,
            ...journal.supersededUris,
          ]);
          await platform.clearPublishJournal(journal.captureId);
          continue;
        }
        switch (record.status) {
          case CaptureStatus.ready:
            if (record.publishedUri == journal.contentUri) {
              await platform.clearPublishJournal(journal.captureId);
            } else {
              final stale = <String>{
                ...journal.supersededUris,
                if (record.publishedUri != null) record.publishedUri!,
              }.toList();
              await database.updatePublishedUri(
                record.id,
                journal.contentUri,
                supersededUris: stale,
              );
              await platform.clearPublishJournal(journal.captureId);
            }
          case CaptureStatus.captured:
          case CaptureStatus.rendering:
            // The background processor owns these states and will
            // re-publish, overwriting this journal entry; keep it.
            break;
          case CaptureStatus.failed:
          case CaptureStatus.pendingCamera:
            // Nothing will reference the journaled URI anymore — queue it
            // (and its stale candidates) for delete-only cleanup.
            await database.enqueueSupersededCleanups(record.id, [
              journal.contentUri,
              ...journal.supersededUris,
            ]);
            await platform.clearPublishJournal(journal.captureId);
        }
      } catch (_) {
        // Keep the journal entry for a later launch; siblings still run.
      }
    }
  }

  Future<void> _cleanupSuperseded() async {
    final tasks = await database.pendingSupersededCleanups();
    for (final task in tasks) {
      try {
        final record = await database.captureById(task.captureId);
        // The task commits atomically with the replacement URI, so a live
        // record must never reference the task's URI. This guard is
        // defensive against restored backups re-pointing a record at an old
        // URI: deleting it would destroy the photo the record displays.
        if (record != null && record.publishedUri == task.publishedUri) {
          continue;
        }
        try {
          await platform.deletePublishedImage(task.publishedUri);
        } catch (_) {
          // Keep the task for a later launch; siblings still run.
          continue;
        }
        await database.completeSupersededCleanup(task.publishedUri);
      } catch (_) {
        // Keep the durable task for a later launch and continue with others.
      }
    }
  }

  Future<bool> _finishCleanup(PendingCaptureMediaCleanup pending) async {
    var cleaned = true;
    if (pending.kind == CaptureMediaCleanupKind.deleteCapture &&
        pending.publishedUri != null) {
      try {
        await platform.deletePublishedImage(pending.publishedUri!);
      } catch (_) {
        cleaned = false;
      }
    }
    for (final path in pending.paths) {
      try {
        await files.deleteIfExists(path);
      } catch (_) {
        cleaned = false;
      }
    }
    if (cleaned) {
      try {
        await pendingStore.clear(pending.captureId, pending.kind);
      } catch (_) {
        // The marker is harmless and cleanup is idempotent on the next launch.
      }
    }
    return cleaned;
  }
}
