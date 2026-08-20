import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/diagnostics/diagnostic_event.dart';
import 'package:sitemark/diagnostics/diagnostic_recorder.dart';
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
    this.diagnostics,
  }) : pendingStore = pendingStore ?? MemoryCaptureMediaCleanupPendingStore();

  /// Optional diagnostics sink. When attached, superseded-cleanup failures,
  /// stalled tasks, journal recoveries, and reconciliation CAS conflicts
  /// become visible in diagnostic bundles instead of silent loops.
  final DiagnosticRecorder? diagnostics;

  /// Failed delete attempts tolerated per superseded URI before the task is
  /// parked (stalled) and excluded from automatic retries. A URI still
  /// referenced by any record does NOT consume budget — waiting for the
  /// last reference to disappear is normal, not a failure.
  static const maxCleanupRetries = 5;

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
  ///   2. `deleteCapture(id)` (the logical commit point) — which ALSO queues
  ///      the row's `publishedUri` into the superseded-cleanup table in the
  ///      same transaction
  ///   3. remove the private files, then the marker
  ///   4. process the superseded queue: each queued URI is deleted only
  ///      after a whole-database check confirms no record still references
  ///      it (a legacy upgrade can leave a sibling row sharing the URI)
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
    // Run the reference-checked queue now so an unreferenced URI is deleted
    // in the same user action instead of lingering until the next launch.
    await _cleanupSuperseded();
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
        // queue write) can no longer lose the tracking of a duplicate. The
        // update is a compare-and-swap on the previously observed URI: a
        // CAS failure means a NEWER publish of this capture already
        // committed, so this older outcome must NOT overwrite it — its own
        // URI is an orphan and is queued for delete-only cleanup instead.
        final committed = await database.updatePublishedUri(
          id,
          outcome.contentUri,
          expectedPreviousUri: record.publishedUri,
          supersededUris: outcome.supersededUris,
        );
        if (!committed) {
          // CAS failed: a NEWER publish of this capture already committed.
          // If that newer commit happens to hold THIS very URI (e.g. a
          // journal recovery adopted it), there is no orphan at all — only
          // the conditional journal clear remains. Otherwise this older
          // outcome's URI is an orphan queued for delete-only cleanup; the
          // whole-database reference check in _cleanupSuperseded guards
          // the actual delete.
          final fresh = await database.captureById(id);
          await database.enqueueSupersededCleanups(id, [
            ...outcome.supersededUris,
            if (fresh?.publishedUri != outcome.contentUri) outcome.contentUri,
          ]);
          try {
            await platform.clearPublishJournal(id, outcome.contentUri);
          } catch (_) {}
        } else {
          // The database commit survived, so the native publish journal has
          // served its purpose; a crash before this point is reconciled by
          // [recoverPublishJournals] on the next launch. The clear is
          // CONDITIONAL on the journal still recording THIS publish's URI:
          // if a newer same-capture publish already overwrote the journal,
          // clearing must not destroy that newer entry. It is also
          // BEST-EFFORT — a leftover journal never turns the completed
          // republish into a failure (recovery sees `ready` + matching URI
          // and clears it on the next launch).
          try {
            await platform.clearPublishJournal(id, outcome.contentUri);
          } catch (_) {}
        }
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
  /// - `ready` row still points at the URI the journaled publish replaced
  ///   (its previous URI, or null for a first publish) → the commit never
  ///   happened → adopt the journaled URI via CAS and queue deletes for
  ///   every stale candidate (already-deleted rows are an idempotent no-op).
  ///   A CAS failure means a NEWER publish committed after the journal was
  ///   read: the journaled URI is then an orphan queued for delete-only
  ///   cleanup, and the journal is LEFT UNTOUCHED — it may belong to that
  ///   newer (possibly still uncommitted) operation.
  /// - `ready` row points at a URI the journal NEVER replaced → a newer
  ///   publish already committed and the journal is a leftover of an older
  ///   superseded operation. Adopting the older URI would roll the record
  ///   BACK; instead the journaled URI is queued as an orphan and the
  ///   journal cleared conditionally.
  /// - Row is `captured`/`rendering` → the background processor will
  ///   re-publish and overwrite this journal; keep it and let the normal
  ///   flow converge.
  /// - Row is gone or terminal-without-retry (`failed`) → nothing will ever
  ///   reference the journaled URI → queue the new and stale URIs for
  ///   delete-only cleanup and clear the journal.
  ///
  /// Every clear is CONDITIONAL on the journal still recording the entry
  /// being reconciled: an older operation must never clear an entry that a
  /// newer same-capture publish has already overwritten — losing it would
  /// make the newer finalized publish unrecoverable after a crash.
  ///
  /// The journal is keyed by the capture's stable ID, so the row is located
  /// by `captureById` — NEVER by photo number, which a backup restore can
  /// duplicate across projects (reconciling by number could write THIS
  /// capture's URI into ANOTHER capture's row).
  ///
  /// This is a first-class startup window: callers must not fold it into
  /// [cleanupInterrupted], or a hanging album cleanup would skip journal
  /// recovery (and the reverse).
  Future<void> recoverPublishJournals() async {
    final journals = await platform.recoverPublishJournals();
    for (final journal in journals) {
      try {
        final record = await database.captureById(journal.captureId);
        if (record == null) {
          await database.enqueueSupersededCleanups(journal.captureId, [
            journal.contentUri,
            ...journal.supersededUris,
          ]);
          await platform.clearPublishJournal(
            journal.captureId,
            journal.contentUri,
          );
          continue;
        }
        switch (record.status) {
          case CaptureStatus.ready:
            if (record.publishedUri == journal.contentUri) {
              await platform.clearPublishJournal(
                journal.captureId,
                journal.contentUri,
              );
            } else if (record.publishedUri == null ||
                journal.supersededUris.contains(record.publishedUri)) {
              // The row still holds the state this journal was meant to
              // replace — safe to adopt the journaled URI.
              final stale = <String>{
                ...journal.supersededUris,
                if (record.publishedUri != null) record.publishedUri!,
              }.toList();
              final committed = await database.updatePublishedUri(
                record.id,
                journal.contentUri,
                expectedPreviousUri: record.publishedUri,
                supersededUris: stale,
              );
              if (committed) {
                _recordJournalRecovery(DiagnosticOutcome.success);
                await platform.clearPublishJournal(
                  journal.captureId,
                  journal.contentUri,
                );
              } else {
                // A newer publish committed while reconciling; the
                // journaled URI may already equal the committed one.
                _recordJournalRecovery(DiagnosticOutcome.cancelled);
                await _reconcileSupersededJournalOrphan(record.id, journal);
              }
            } else {
              // A newer publish already committed; the journal belongs to
              // an older superseded operation. Never roll the record back.
              await _reconcileSupersededJournalOrphan(record.id, journal);
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
            await platform.clearPublishJournal(
              journal.captureId,
              journal.contentUri,
            );
        }
      } catch (_) {
        // Keep the journal entry for a later launch; siblings still run.
      }
    }
  }

  /// Emits one diagnostic event per reconciled journal entry: `success`
  /// for an adopted (or already-committed) recovery, `cancelled` when the
  /// CAS detected a newer publish had committed and the journal was routed
  /// to orphan cleanup instead. Makes recovery volume and conflict rate
  /// visible in diagnostic bundles.
  void _recordJournalRecovery(DiagnosticOutcome outcome) {
    diagnostics?.record(
      DiagnosticEvent(
        timestamp: DateTime.now(),
        category: DiagnosticCategory.processing,
        outcome: outcome,
        count: 1,
      ),
    );
  }

  /// Resolves a journal whose publish was superseded by a newer committed
  /// one: the journaled URI is an orphan UNLESS the row already points at
  /// it (another path committed the very same URI), and the journal itself
  /// is cleared only while it still records [RecoveredPublishJournalEntry.contentUri].
  Future<void> _reconcileSupersededJournalOrphan(
    String captureId,
    RecoveredPublishJournalEntry journal,
  ) async {
    final fresh = await database.captureById(captureId);
    // Preserve the COMPLETE folded journal set before clearing its only
    // durable native copy. The whole-database reference check in
    // _cleanupSuperseded remains the final guard: a URI any row still
    // references is never deleted.
    await database.enqueueSupersededCleanups(captureId, [
      ...journal.supersededUris,
      if (fresh?.publishedUri != journal.contentUri) journal.contentUri,
    ]);
    await platform.clearPublishJournal(captureId, journal.contentUri);
  }

  Future<void> _cleanupSuperseded() async {
    final tasks = await database.pendingSupersededCleanups();
    for (final task in tasks) {
      try {
        // Check the WHOLE database, not just the task's own capture: a
        // legacy upgrade can leave TWO records sharing one gallery URI, and
        // deleting a URI that ANY row still references would destroy the
        // photo that record displays. A referenced URI keeps its task for a
        // later launch; once the last reference is gone (the sibling row is
        // deleted or re-published), the delete converges. Waiting for a
        // reference to disappear is NOT a failure and never consumes the
        // task's retry budget.
        if (await database.isPublishedUriReferenced(task.publishedUri)) {
          continue;
        }
        try {
          await platform.deletePublishedImage(task.publishedUri);
        } catch (_) {
          // The delete failed (e.g. a remote provider error): count it, and
          // park the task once the budget is exhausted so a permanently
          // failing URI stops being retried on every launch.
          final updated = await database.recordSupersededCleanupFailure(
            task.publishedUri,
            maxRetries: maxCleanupRetries,
          );
          if (updated != null) {
            diagnostics?.record(
              DiagnosticEvent(
                timestamp: DateTime.now(),
                category: DiagnosticCategory.deletion,
                // blocked marks the transition into the stalled state (the
                // task just exhausted its budget); plain failed means the
                // delete failed but budget remains.
                outcome: updated.stalledAt != null
                    ? DiagnosticOutcome.blocked
                    : DiagnosticOutcome.failed,
                code: DiagnosticCode.unexpected,
                retryCount: updated.retryCount,
              ),
            );
          }
          continue;
        }
        await database.completeSupersededCleanup(task.publishedUri);
      } catch (_) {
        // Keep the durable task for a later launch and continue with others.
      }
    }
  }

  Future<bool> _finishCleanup(PendingCaptureMediaCleanup pending) async {
    // The published URI is deliberately NOT deleted here: the database's
    // deleteCapture already queued it (same transaction) into the durable
    // superseded-cleanup table, whose processor checks the WHOLE database
    // for remaining references — a legacy upgrade can leave a sibling row
    // sharing this URI. Deleting it here would bypass that check.
    var cleaned = true;
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
