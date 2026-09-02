import 'package:drift/drift.dart';

import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/domain/nas_sync.dart';

/// Maximum automatic attempts per capture before its state parks in
/// `failed`. The user can always retry explicitly, which resets the budget.
const int kNasMaxUploadAttempts = 5;

NasSyncConfig _defaultNasSyncConfig() {
  final now = DateTime.now();
  return NasSyncConfig(
    id: 'global',
    protocol: 'webdav',
    host: '',
    port: null,
    username: '',
    rootPath: '/',
    secureTls: true,
    acceptInvalidTls: false,
    knownSftpFingerprint: null,
    wifiOnly: true,
    enabled: false,
    updatedAt: now,
  );
}

/// Data access for the NAS sync feature (decision D-023).
///
/// The remote surface is deliberately minimal: configuration as one
/// singleton row, and per-capture upload bookkeeping that converges by
/// overwriting. Passwords never pass through here — they live in secure
/// storage and are joined per upload.
extension NasSyncDatabase on AppDatabase {
  /// The singleton configuration row. Read-only: when the row does not
  /// exist yet (sync was never configured), the in-memory defaults are
  /// returned instead of writing. A write on every read would re-trigger
  /// drift's statement-level watch and loop forever.
  Future<NasSyncConfig> nasSyncConfig() async {
    final row = await (select(
      nasSyncConfigs,
    )..where((row) => row.id.equals('global'))).getSingleOrNull();
    return row ?? _defaultNasSyncConfig();
  }

  /// Persists the singleton configuration row (upsert by id).
  Future<void> saveNasSyncConfig({
    required String protocol,
    required String host,
    required int? port,
    required String username,
    required String rootPath,
    required bool secureTls,
    required bool acceptInvalidTls,
    required String? knownSftpFingerprint,
    required bool wifiOnly,
    required bool enabled,
  }) async {
    final now = DateTime.now();
    await into(nasSyncConfigs).insertOnConflictUpdate(
      NasSyncConfigsCompanion.insert(
        id: const Value('global'),
        protocol: Value(protocol),
        host: Value(host),
        port: Value(port),
        username: Value(username),
        rootPath: Value(rootPath),
        secureTls: Value(secureTls),
        acceptInvalidTls: Value(acceptInvalidTls),
        knownSftpFingerprint: Value(knownSftpFingerprint),
        wifiOnly: Value(wifiOnly),
        enabled: Value(enabled),
        updatedAt: Value(now),
      ),
    );
  }

  /// Emits the configuration on every change — the settings screen mirrors
  /// it and the coordinator reacts to enable/disable flips. Before the row
  /// exists, defaults are emitted (as one `null`-to-default mapping, without
  /// writing).
  Stream<NasSyncConfig> watchNasSyncConfig() {
    return (select(nasSyncConfigs)..where((row) => row.id.equals('global')))
        .watchSingleOrNull()
        .map((row) => row ?? _defaultNasSyncConfig());
  }

  /// Enqueues one capture as pending. Insert-only: an existing state (for
  /// example `uploaded`) is never downgraded by a re-enqueue.
  Future<void> upsertNasUploadPending(String captureId) async {
    await into(nasUploadStates).insert(
      NasUploadStatesCompanion.insert(captureId: captureId),
      onConflict: DoNothing(),
    );
  }

  /// Enqueues every currently-ready capture that has no upload state yet —
  /// the catch-up scan run when sync is (re-)enabled and at app start.
  Future<void> enqueueReadyCapturesForNas() async {
    final readyQuery = selectOnly(captureRecords)
      ..addColumns([captureRecords.id])
      ..where(captureRecords.status.equals(CaptureStatus.ready.name));
    final readyIds = await readyQuery
        .map((row) => row.read(captureRecords.id)!)
        .get();
    for (final captureId in readyIds) {
      await upsertNasUploadPending(captureId);
    }
  }

  /// Upload states eligible for automatic processing: pending, with retry
  /// budget left, whose capture is still ready. Oldest attempt first.
  Future<List<NasUploadState>> pendingNasUploads() {
    return (select(nasUploadStates)
          ..where(
            (row) =>
                row.status.equals(NasUploadStatus.pending.name) &
                row.attempts.isSmallerThanValue(kNasMaxUploadAttempts),
          )
          ..orderBy([(row) => OrderingTerm.asc(row.lastAttemptAt)]))
        .get();
  }

  /// Every upload state, newest activity first (settings surface).
  Future<List<NasUploadState>> allNasUploadStates() {
    return (select(nasUploadStates)..orderBy([
          (row) => OrderingTerm.desc(row.lastAttemptAt),
          (row) => OrderingTerm.desc(row.uploadedAt),
        ]))
        .get();
  }

  /// Defers a queued capture whose upload was not attempted (for example
  /// the capture is still processing): only the ordering timestamp moves,
  /// so the row goes to the back of the queue without burning any of the
  /// retry budget.
  Future<void> deferNasUpload(String captureId) async {
    await (update(nasUploadStates)
          ..where((row) => row.captureId.equals(captureId)))
        .write(NasUploadStatesCompanion(lastAttemptAt: Value(DateTime.now())));
  }

  /// Records a failed attempt. The state parks in `failed` once the retry
  /// budget is exhausted; below the budget it stays pending for the next
  /// trigger (new capture, app start, or config change).
  Future<void> markNasUploadFailed(String captureId, String failureCode) async {
    final state = await (select(
      nasUploadStates,
    )..where((row) => row.captureId.equals(captureId))).getSingleOrNull();
    if (state == null) return;
    final attempts = state.attempts + 1;
    await (update(
      nasUploadStates,
    )..where((row) => row.captureId.equals(captureId))).write(
      NasUploadStatesCompanion(
        status: Value(
          attempts >= kNasMaxUploadAttempts
              ? NasUploadStatus.failed
              : NasUploadStatus.pending,
        ),
        attempts: Value(attempts),
        failureCode: Value(failureCode),
        lastAttemptAt: Value(DateTime.now()),
      ),
    );
  }

  /// Records a successful upload. Idempotent: re-uploading the same capture
  /// (for example after a re-render) overwrites the remote file and simply
  /// refreshes this row.
  Future<void> markNasUploaded(String captureId) async {
    await (update(
      nasUploadStates,
    )..where((row) => row.captureId.equals(captureId))).write(
      NasUploadStatesCompanion(
        status: Value(NasUploadStatus.uploaded),
        failureCode: Value(null),
        uploadedAt: Value(DateTime.now()),
        lastAttemptAt: Value(DateTime.now()),
      ),
    );
  }

  /// User-initiated retry: resets the budget and parks the state back in
  /// pending. Only meaningful for failed rows but harmless otherwise.
  Future<void> resetNasUploadForRetry(String captureId) async {
    await (update(
      nasUploadStates,
    )..where((row) => row.captureId.equals(captureId))).write(
      const NasUploadStatesCompanion(
        status: Value(NasUploadStatus.pending),
        attempts: Value(0),
        failureCode: Value(null),
      ),
    );
  }
}
