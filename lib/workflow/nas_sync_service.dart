import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/data/nas_sync_database.dart';
import 'package:sitemark/diagnostics/diagnostic_event.dart';
import 'package:sitemark/diagnostics/diagnostic_recorder.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/domain/nas_sync.dart';
import 'package:sitemark/domain/project_name.dart'
    show ProjectNameConflictException;
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/src/rust/api/image_core.dart' as rust_images;
import 'package:sitemark/src/rust/api/nas.dart' as rust_api;
import 'package:sitemark/src/rust/nas.dart' as rust;
import 'package:uuid/uuid.dart';

/// Where the NAS password lives between uploads. Implementations must keep
/// the secret out of SQLite, backups and diagnostics (decision D-023).
abstract interface class NasCredentialStore {
  Future<String?> read();

  Future<void> write(String password);

  Future<void> delete();
}

/// Keystore/Keychain backed store via flutter_secure_storage.
class SecureStorageNasCredentials implements NasCredentialStore {
  SecureStorageNasCredentials({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'nas.sync.password';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String password) =>
      _storage.write(key: _key, value: password);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

/// Network gate evaluated before every drain cycle.
abstract interface class NasConnectivity {
  Future<bool> allowsUpload({required bool wifiOnly});

  /// Fires when the available interfaces may have changed. The coordinator
  /// re-evaluates the Wi-Fi gate; a wifi-only queue that parked on mobile
  /// must resume when Wi-Fi returns, without waiting for the next photo.
  Stream<void> get changes;
}

class ConnectivityNasConnectivity implements NasConnectivity {
  @override
  Future<bool> allowsUpload({required bool wifiOnly}) async {
    // connectivity_plus stays on 6.x: the 7.x iOS implementation calls
    // NWPath.isUltraConstrained, which only exists in the iOS 26 SDK and
    // breaks every build on Xcode 16 (see ci.yml's macos-15 runner).
    final types = (await Connectivity().checkConnectivity()).toSet();
    if (wifiOnly) {
      return types.contains(ConnectivityResult.wifi) ||
          types.contains(ConnectivityResult.ethernet);
    }
    return types.contains(ConnectivityResult.wifi) ||
        types.contains(ConnectivityResult.ethernet) ||
        types.contains(ConnectivityResult.mobile) ||
        types.contains(ConnectivityResult.vpn);
  }

  @override
  Stream<void> get changes => Connectivity().onConnectivityChanged.map((_) {});
}

/// One upload request, fully resolved: everything the protocol core needs
/// to place the rendered JPEG at `{root}/{projectKey}/{fileName}`.
class NasUploadJob {
  const NasUploadJob({
    required this.config,
    required this.password,
    required this.localPath,
    required this.projectKey,
    required this.fileName,
  });

  final NasSyncConfig config;
  final String password;
  final String localPath;
  final String projectKey;
  final String fileName;
}

/// Uploads one job. Returns the failure category code on failure, or null
/// on success. Implementations translate platform errors into the stable
/// Rust taxonomy and never surface raw messages.
abstract interface class NasUploader {
  Future<String?> upload(NasUploadJob job);
}

/// Default uploader backed by the Rust NAS core via flutter_rust_bridge.
class RustNasUploader implements NasUploader {
  @override
  Future<String?> upload(NasUploadJob job) async {
    try {
      await rust_api.nasUpload(
        request: rust_api.NasUploadRequest(
          config: rust.NasConfig(
            protocol: switch (job.config.protocol) {
              'webdav' => rust.NasProtocol.webdav,
              'sftp' => rust.NasProtocol.sftp,
              _ => rust.NasProtocol.smb,
            },
            host: job.config.host,
            port: job.config.port,
            username: job.config.username,
            password: job.password,
            rootPath: job.config.rootPath,
            secureTls: job.config.secureTls,
            acceptInvalidTls: job.config.acceptInvalidTls,
            knownSftpFingerprint: job.config.knownSftpFingerprint,
          ),
          projectKey: job.projectKey,
          fileName: job.fileName,
          localPath: job.localPath,
        ),
      );
      return null;
    } on rust.NasError catch (error) {
      return error.code.name;
    } on Object {
      // Anything outside the Rust taxonomy (bridge/decode breakage, e.g. a
      // port that survived client validation) must not escape as an
      // unhandled async error — the queue records it and moves on.
      return 'protocol_error';
    }
  }
}

/// Live counts shown on the settings surface.
class NasSyncSnapshot {
  const NasSyncSnapshot({
    required this.active,
    required this.pendingCount,
    required this.failedCount,
    required this.uploadedCount,
    this.lastFailureCode,
    this.hostKeyBlocked = false,
  });

  final bool active;
  final int pendingCount;
  final int failedCount;
  final int uploadedCount;

  /// Most recent failure category among failed/pending rows, if any.
  final String? lastFailureCode;

  /// True when at least one row last failed with `host_key_changed` — the
  /// queue cannot resume until the user re-confirms the fingerprint.
  final bool hostKeyBlocked;

  static const idle = NasSyncSnapshot(
    active: false,
    pendingCount: 0,
    failedCount: 0,
    uploadedCount: 0,
  );

  @override
  String toString() =>
      'NasSyncSnapshot(active: $active, pending: $pendingCount, '
      'failed: $failedCount, uploaded: $uploadedCount, '
      'lastFailure: $lastFailureCode, hostKeyBlocked: $hostKeyBlocked)';
}

/// One remote NAS project folder with photos that can be imported.
class NasImportCandidate {
  const NasImportCandidate({
    required this.projectKey,
    required this.existsLocally,
    required this.localProjectId,
    required this.fileNames,
  });

  /// Sanitized folder name on the NAS (`{root}/{projectKey}/…`).
  final String projectKey;

  /// Whether a local project already uses this key.
  final bool existsLocally;

  /// Local project id when [existsLocally].
  final String? localProjectId;

  /// Remote `.jpg` file names that are not already present locally.
  final List<String> fileNames;

  int get photoCount => fileNames.length;
}

/// Drives the NAS upload queue.
///
/// Observer pattern: nothing in the capture processor knows about NAS. The
/// coordinator listens for config flips and capture-table updates, keeps
/// the queue populated (insert-only), and drains it serially — one upload
/// at a time, gated by connectivity and the per-capture retry budget.
class NasSyncCoordinator {
  NasSyncCoordinator(
    this._database,
    this._credentials,
    this._connectivity,
    this._uploader,
    this._outputPaths, {
    this.diagnostics,
    this.checkLocalNetwork,
    this.onBackgroundNudge,
    this.onFailureNotify,
  });

  final AppDatabase _database;
  final NasCredentialStore _credentials;
  final NasConnectivity _connectivity;
  final NasUploader _uploader;
  final CaptureOutputPaths _outputPaths;

  /// Optional diagnostics sink for upload failures.
  final DiagnosticRecorder? diagnostics;

  /// Non-prompting LAN permission probe. When null, LAN hosts are not
  /// re-checked during drain (tests and non-Android hosts).
  final Future<bool> Function(String host)? checkLocalNetwork;

  /// Invoked after a drain leaves pending work behind (backoff, fatal stop,
  /// connectivity) so the host can arm a background catch-up.
  final Future<void> Function()? onBackgroundNudge;

  /// Posts a local notification when a drain ends with failed rows.
  final Future<void> Function(int failedCount, String? failureCode)?
  onFailureNotify;

  final _stateController = StreamController<NasSyncSnapshot>.broadcast();
  bool _started = false;
  bool _syncing = false;
  bool _rerunQueued = false;
  int _failuresThisDrain = 0;
  NasSyncConfig? _lastSeenConfig;
  StreamSubscription? _configSubscription;
  StreamSubscription? _captureUpdatesSubscription;
  StreamSubscription? _connectivitySubscription;

  Stream<NasSyncSnapshot> get state => _stateController.stream;

  /// Wires the observers and runs the first cycle. Safe to call once per
  /// coordinator lifetime.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _configSubscription = _database.watchNasSyncConfig().listen((config) {
      // A config flip (enable/disable, target change) re-arms the queue.
      unawaited(_onConfigChanged(config));
    });
    _captureUpdatesSubscription = _database
        .tableUpdates(TableUpdateQuery.onTable(_database.captureRecords))
        .listen((_) {
          // A capture becoming ready after enable must be inserted, not
          // only drained — otherwise new photos wait until the next
          // config save or process restart.
          unawaited(_refreshAndDrain(catchUp: true));
        });
    _connectivitySubscription = _connectivity.changes.listen((_) {
      // Wifi-only rows stay pending on mobile; a later Wi-Fi/ethernet
      // path must re-arm the drain without waiting for the next photo.
      unawaited(_refreshAndDrain());
    });
    await _refreshAndDrain(catchUp: true);
  }

  Future<void> dispose() async {
    await _configSubscription?.cancel();
    await _captureUpdatesSubscription?.cancel();
    await _connectivitySubscription?.cancel();
    await _stateController.close();
  }

  /// One-shot drain for the background isolate: no observers, no catch-up
  /// scan. Safe to call without [start].
  Future<void> drainOnce() => _drainQueue();

  /// Lists remote projects and the photos that are not yet on this phone.
  /// Used by the settings import picker before anything is written.
  Future<List<NasImportCandidate>> previewNasImport() async {
    final credentials = await _twoWayCredentials();
    if (credentials == null) return const [];
    final (config, password) = credentials;
    final rustConfig = _rustConfig(config, password);
    final remoteFiles = await rust_api.nasList(config: rustConfig);
    final projects = await _database.getProjects();
    final byKey = {
      for (final project in projects) nasProjectKey(project.name): project,
    };
    final byProjectKey = <String, List<String>>{};
    for (final remote in remoteFiles) {
      if (!remote.fileName.toLowerCase().endsWith('.jpg')) continue;
      final photoNumber = remote.fileName.substring(
        0,
        remote.fileName.length - 4,
      );
      if (photoNumber.isEmpty) continue;
      byProjectKey
          .putIfAbsent(remote.projectKey, () => [])
          .add(remote.fileName);
    }
    final candidates = <NasImportCandidate>[];
    for (final entry in byProjectKey.entries) {
      final project = byKey[entry.key];
      final missing = <String>[];
      for (final fileName in entry.value) {
        final photoNumber = fileName.substring(0, fileName.length - 4);
        if (project != null) {
          final existing = await _captureByPhotoNumber(project.id, photoNumber);
          if (existing != null) continue;
        }
        missing.add(fileName);
      }
      if (missing.isEmpty) continue;
      candidates.add(
        NasImportCandidate(
          projectKey: entry.key,
          existsLocally: project != null,
          localProjectId: project?.id,
          fileNames: missing,
        ),
      );
    }
    candidates.sort((a, b) => a.projectKey.compareTo(b.projectKey));
    return candidates;
  }

  /// Imports the selected remote projects. Creates a local project when the
  /// NAS folder has no matching one. Returns the number of photos imported.
  Future<int> importNasProjects(List<NasImportCandidate> selected) async {
    if (selected.isEmpty) return 0;
    final credentials = await _twoWayCredentials();
    if (credentials == null) return 0;
    final (config, password) = credentials;
    final rustConfig = _rustConfig(config, password);
    var imported = 0;
    for (final candidate in selected) {
      var projectId = candidate.localProjectId;
      if (projectId == null) {
        try {
          final project = await _database.createProject(
            id: const Uuid().v4(),
            name: candidate.projectKey,
          );
          projectId = project.id;
        } on ProjectNameConflictException {
          // Another device/session created the same name; reuse it.
          final projects = await _database.getProjects();
          projectId = projects
              .where(
                (project) =>
                    nasProjectKey(project.name) == candidate.projectKey,
              )
              .map((project) => project.id)
              .firstOrNull;
          if (projectId == null) continue;
        }
      }
      for (final fileName in candidate.fileNames) {
        final photoNumber = fileName.substring(0, fileName.length - 4);
        if (photoNumber.isEmpty) continue;
        final existing = await _captureByPhotoNumber(projectId, photoNumber);
        if (existing != null) continue;
        final captureId = const Uuid().v4();
        final localPath = await _outputPaths.renderedPhotoPath(captureId);
        await rust_api.nasDownload(
          request: rust_api.NasDownloadRequest(
            config: rustConfig,
            projectKey: candidate.projectKey,
            fileName: fileName,
            localPath: localPath,
          ),
        );
        final sha256 = await rust_images.sha256File(path: localPath);
        final now = DateTime.now();
        await _database.insertRestoredCapture(
          id: captureId,
          projectId: projectId,
          photoNumber: photoNumber,
          // The watermarked JPEG is the only artifact NAS keeps; the private
          // original never left the source device.
          originalPath: localPath,
          workLocation: 'NAS',
          workContent: photoNumber,
          photographer: 'NAS',
          originalSha256: sha256,
          createdAt: now,
          capturedAt: now,
          originalDeletedAt: now,
        );
        await _database.upsertNasUploadPending(captureId);
        await _database.markNasUploaded(captureId);
        imported++;
      }
    }
    return imported;
  }

  Future<(NasSyncConfig, String)?> _twoWayCredentials() async {
    final config = await _database.nasSyncConfig();
    if (!config.enabled ||
        NasSyncMode.fromWire(config.syncMode) != NasSyncMode.twoWay) {
      return null;
    }
    String password;
    try {
      password = await _credentials.read() ?? '';
    } on Object {
      return null;
    }
    if (password.isEmpty) return null;
    return (config, password);
  }

  /// Deletes the remote JPEG for [record] when two-way sync is on.
  /// Best-effort: missing files and transport errors are swallowed so the
  /// local delete never fails because of the NAS.
  Future<void> deleteRemoteForCapture(CaptureRecord record) async {
    final photoNumber = record.photoNumber;
    if (photoNumber == null || photoNumber.isEmpty) return;
    final config = await _database.nasSyncConfig();
    if (!config.enabled ||
        NasSyncMode.fromWire(config.syncMode) != NasSyncMode.twoWay) {
      return;
    }
    String password;
    try {
      password = await _credentials.read() ?? '';
    } on Object {
      return;
    }
    if (password.isEmpty) return;
    final project = await _database.projectById(record.projectId);
    if (project == null) return;
    try {
      await rust_api.nasDelete(
        request: rust_api.NasDownloadRequest(
          config: _rustConfig(config, password),
          projectKey: nasProjectKey(project.name),
          fileName: nasRemoteFileName(photoNumber),
          localPath: '',
        ),
      );
    } on Object {
      // Best-effort remote cleanup.
    }
  }

  rust.NasConfig _rustConfig(NasSyncConfig config, String password) {
    return rust.NasConfig(
      protocol: switch (config.protocol) {
        'webdav' => rust.NasProtocol.webdav,
        'sftp' => rust.NasProtocol.sftp,
        _ => rust.NasProtocol.smb,
      },
      host: config.host,
      port: config.port,
      username: config.username,
      password: password,
      rootPath: config.rootPath,
      secureTls: config.secureTls,
      acceptInvalidTls: config.acceptInvalidTls,
      knownSftpFingerprint: config.knownSftpFingerprint,
    );
  }

  Future<CaptureRecord?> _captureByPhotoNumber(
    String projectId,
    String photoNumber,
  ) {
    return (_database.select(_database.captureRecords)..where(
          (row) =>
              row.projectId.equals(projectId) &
              row.photoNumber.equals(photoNumber),
        ))
        .getSingleOrNull();
  }

  /// Retries every failed row explicitly (user action from settings).
  Future<void> retryFailedUploads() async {
    for (final state in await _database.allNasUploadStates()) {
      if (state.status == NasUploadStatus.failed) {
        await _database.resetNasUploadForRetry(state.captureId);
      }
    }
    await _refreshAndDrain();
  }

  Future<void> _onConfigChanged(NasSyncConfig config) async {
    final previous = _lastSeenConfig;
    _lastSeenConfig = config;
    if (previous != null &&
        config.enabled &&
        _remoteTargetChanged(previous, config)) {
      try {
        await _database.requeueUploadedNasUploadsForTargetChange();
      } on Object {
        // Fall through to a normal drain; the next save retries the reset.
      }
    }
    await _refreshAndDrain(catchUp: true);
  }

  static bool _remoteTargetChanged(NasSyncConfig a, NasSyncConfig b) =>
      a.protocol != b.protocol ||
      a.host != b.host ||
      a.port != b.port ||
      a.rootPath != b.rootPath;

  Future<void> _refreshAndDrain({bool catchUp = false}) async {
    try {
      final config = await _database.nasSyncConfig();
      _lastSeenConfig ??= config;
      if (catchUp && config.enabled) {
        await _database.enqueueReadyCapturesForNas();
      }
    } on Object {
      // Database hiccups must never crash observers; the next trigger
      // re-runs the cycle.
      return;
    }
    unawaited(_drainQueue());
  }

  Future<void> _drainQueue() async {
    if (_syncing) {
      _rerunQueued = true;
      return;
    }
    _syncing = true;
    _failuresThisDrain = 0;
    await _emit();
    var pendingLeft = false;
    final deferredThisCycle = <String>{};
    try {
      while (true) {
        final config = await _database.nasSyncConfig();
        if (!config.enabled) break;
        final allowed = await _connectivity.allowsUpload(
          wifiOnly: config.wifiOnly,
        );
        if (!allowed) {
          pendingLeft = true;
          break;
        }
        if (!await _lanReachable(config)) {
          // Permission revoked after save: park the cycle without burning
          // the retry budget on a socket that cannot open.
          pendingLeft = true;
          break;
        }
        final queue = await _database.pendingNasUploads();
        if (queue.isEmpty) break;

        final first = queue.first.captureId;
        if (deferredThisCycle.contains(first)) {
          // Every remaining eligible row already deferred this cycle.
          pendingLeft = true;
          break;
        }
        final outcome = await _uploadOne(config, first);
        await _emit();
        switch (outcome) {
          case _UploadOutcome.deferred:
            deferredThisCycle.add(first);
            break;
          case _UploadOutcome.fatal:
            // Auth/config/host-key: every remaining row would fail the same
            // way. Stop and wait for a user action (retry / re-test).
            pendingLeft = queue.length > 1;
            return;
          case _UploadOutcome.failed:
            // Backoff parks the row out of `pendingNasUploads` for a while.
            // Keep draining other eligible rows; if this was the only one
            // the next query is empty and we exit.
            pendingLeft = true;
            break;
          case _UploadOutcome.succeeded:
            break;
        }
      }
    } finally {
      _syncing = false;
      await _emit();
      // Only alert on failures recorded by *this* drain. Re-notifying on
      // every capture/config tick for rows that already failed would spam.
      if (_failuresThisDrain > 0) {
        await _notifyFailures(await _currentSnapshot());
      }
      if (pendingLeft || _rerunQueued) {
        unawaited(_nudgeBackground());
      }
    }
    if (_rerunQueued) {
      _rerunQueued = false;
      await _drainQueue();
    }
  }

  Future<NasSyncSnapshot> _currentSnapshot() async {
    final states = await _database.allNasUploadStates();
    String? lastFailureCode;
    var hostKeyBlocked = false;
    for (final row in states) {
      final code = row.failureCode;
      if (code == null) continue;
      if (code == 'host_key_changed') hostKeyBlocked = true;
      if (row.status == NasUploadStatus.failed) lastFailureCode = code;
    }
    return NasSyncSnapshot(
      active: false,
      pendingCount: states
          .where((row) => row.status == NasUploadStatus.pending)
          .length,
      failedCount: states
          .where((row) => row.status == NasUploadStatus.failed)
          .length,
      uploadedCount: states
          .where((row) => row.status == NasUploadStatus.uploaded)
          .length,
      lastFailureCode: lastFailureCode,
      hostKeyBlocked: hostKeyBlocked,
    );
  }

  Future<void> _notifyFailures(NasSyncSnapshot snapshot) async {
    try {
      await onFailureNotify?.call(
        snapshot.failedCount,
        snapshot.lastFailureCode,
      );
    } on Object {
      // Notifications are best-effort.
    }
  }

  Future<bool> _lanReachable(NasSyncConfig config) async {
    final check = checkLocalNetwork;
    if (check == null || config.host.isEmpty) return true;
    if (!isLanNasHost(config.host)) return true;
    try {
      return await check(config.host);
    } on Object {
      return false;
    }
  }

  Future<void> _nudgeBackground() async {
    try {
      await onBackgroundNudge?.call();
    } on Object {
      // Background scheduling is best-effort; the next foreground drain
      // still runs.
    }
  }

  /// Uploads one capture. Local errors (missing photo number, missing file,
  /// missing password) map into the Rust failure taxonomy so the settings
  /// surface shows one consistent vocabulary.
  Future<_UploadOutcome> _uploadOne(
    NasSyncConfig config,
    String captureId,
  ) async {
    final capture = await _captureById(captureId);
    if (capture == null) {
      await _recordFailure(captureId, 'path_invalid');
      return _UploadOutcome.failed;
    }
    if (capture.status != CaptureStatus.ready) {
      // The capture changed while queued; keep the job pending and let the
      // processing-completed table update re-trigger the drain.
      await _database.deferNasUpload(captureId);
      return _UploadOutcome.deferred;
    }
    final photoNumber = capture.photoNumber;
    if (photoNumber == null || photoNumber.isEmpty) {
      await _recordFailure(captureId, 'path_invalid');
      return _UploadOutcome.failed;
    }
    final project = await _database.projectById(capture.projectId);
    if (project == null) {
      await _recordFailure(captureId, 'path_invalid');
      return _UploadOutcome.failed;
    }
    final localPath = await _outputPaths.renderedPhotoPath(captureId);
    if (!await File(localPath).exists()) {
      await _recordFailure(captureId, 'local_io');
      return _UploadOutcome.failed;
    }
    String password;
    try {
      password = await _credentials.read() ?? '';
    } on Object {
      // Secure-storage breakage must burn a retry budget like any other
      // failure, not bubble out of the drain loop.
      await _recordFailure(captureId, 'config_invalid');
      return _UploadOutcome.fatal;
    }
    if (password.isEmpty) {
      await _recordFailure(captureId, 'config_invalid');
      return _UploadOutcome.fatal;
    }
    final failureCode = await _uploader.upload(
      NasUploadJob(
        config: config,
        password: password,
        localPath: localPath,
        projectKey: nasProjectKey(project.name),
        fileName: nasRemoteFileName(photoNumber),
      ),
    );
    if (failureCode == null) {
      await _database.markNasUploaded(captureId);
      return _UploadOutcome.succeeded;
    }
    await _recordFailure(captureId, failureCode);
    return isNasFatalFailure(failureCode)
        ? _UploadOutcome.fatal
        : _UploadOutcome.failed;
  }

  Future<void> _recordFailure(String captureId, String failureCode) async {
    _failuresThisDrain++;
    await _database.markNasUploadFailed(captureId, failureCode);
    final state = await databaseSelectState(captureId);
    diagnostics?.record(
      DiagnosticEvent(
        timestamp: DateTime.now(),
        category: DiagnosticCategory.nas,
        outcome: DiagnosticOutcome.failed,
        code: switch (failureCode) {
          'auth_failed' || 'config_invalid' => DiagnosticCode.unexpected,
          'host_key_changed' => DiagnosticCode.permissionDenied,
          'quota_insufficient' => DiagnosticCode.insufficientStorage,
          'local_io' => DiagnosticCode.unexpected,
          _ => DiagnosticCode.unexpected,
        },
        count: 1,
        retryCount: state?.attempts,
      ),
    );
  }

  Future<NasUploadState?> databaseSelectState(String captureId) {
    return (_database.select(
      _database.nasUploadStates,
    )..where((row) => row.captureId.equals(captureId))).getSingleOrNull();
  }

  Future<CaptureRecord?> _captureById(String captureId) {
    return (_database.select(
      _database.captureRecords,
    )..where((row) => row.id.equals(captureId))).getSingleOrNull();
  }

  Future<void> _emit() async {
    if (_stateController.isClosed) return;
    final states = await _database.allNasUploadStates();
    if (_stateController.isClosed) return;
    String? lastFailureCode;
    var hostKeyBlocked = false;
    for (final row in states) {
      final code = row.failureCode;
      if (code == null) continue;
      if (code == 'host_key_changed') hostKeyBlocked = true;
      lastFailureCode ??= code;
      if (row.status == NasUploadStatus.failed) {
        lastFailureCode = code;
      }
    }
    _stateController.add(
      NasSyncSnapshot(
        active: _syncing,
        pendingCount: states
            .where((row) => row.status == NasUploadStatus.pending)
            .length,
        failedCount: states
            .where((row) => row.status == NasUploadStatus.failed)
            .length,
        uploadedCount: states
            .where((row) => row.status == NasUploadStatus.uploaded)
            .length,
        lastFailureCode: lastFailureCode,
        hostKeyBlocked: hostKeyBlocked,
      ),
    );
  }
}

enum _UploadOutcome { succeeded, failed, deferred, fatal }
