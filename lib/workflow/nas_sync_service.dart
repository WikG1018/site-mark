import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/data/nas_sync_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/domain/nas_sync.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/src/rust/api/nas.dart' as rust_api;
import 'package:sitemark/src/rust/nas.dart' as rust;

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
  });

  final bool active;
  final int pendingCount;
  final int failedCount;
  final int uploadedCount;

  static const idle = NasSyncSnapshot(
    active: false,
    pendingCount: 0,
    failedCount: 0,
    uploadedCount: 0,
  );

  @override
  String toString() =>
      'NasSyncSnapshot(active: $active, pending: $pendingCount, '
      'failed: $failedCount, uploaded: $uploadedCount)';
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
    this._outputPaths,
  );

  final AppDatabase _database;
  final NasCredentialStore _credentials;
  final NasConnectivity _connectivity;
  final NasUploader _uploader;
  final CaptureOutputPaths _outputPaths;

  final _stateController = StreamController<NasSyncSnapshot>.broadcast();
  bool _started = false;
  bool _syncing = false;
  bool _rerunQueued = false;
  final _deferredThisCycle = <String>{};
  StreamSubscription? _configSubscription;
  StreamSubscription? _captureUpdatesSubscription;

  Stream<NasSyncSnapshot> get state => _stateController.stream;

  /// Wires the observers and runs the first cycle. Safe to call once per
  /// coordinator lifetime.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _configSubscription = _database.watchNasSyncConfig().listen((config) {
      // A config flip (enable/disable, target change) re-arms the queue.
      unawaited(_refreshAndDrain(catchUp: true));
    });
    _captureUpdatesSubscription = _database
        .tableUpdates(TableUpdateQuery.onTable(_database.captureRecords))
        .listen((_) {
          // A capture becoming ready after enable must be inserted, not
          // only drained — otherwise new photos wait until the next
          // config save or process restart.
          unawaited(_refreshAndDrain(catchUp: true));
        });
    await _refreshAndDrain(catchUp: true);
  }

  Future<void> dispose() async {
    await _configSubscription?.cancel();
    await _captureUpdatesSubscription?.cancel();
    await _stateController.close();
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

  Future<void> _refreshAndDrain({bool catchUp = false}) async {
    try {
      final config = await _database.nasSyncConfig();
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
    await _emit();
    try {
      while (true) {
        final config = await _database.nasSyncConfig();
        if (!config.enabled) break;
        final allowed = await _connectivity.allowsUpload(
          wifiOnly: config.wifiOnly,
        );
        if (!allowed) break;
        final queue = await _database.pendingNasUploads();
        if (queue.isEmpty) break;

        // Re-query after every item so fresh state (user edits, deletions)
        // is honored and ordering stays deterministic. A capture that is
        // not ready yet (still processing) is deferred, not failed — once
        // every queued item is deferred this cycle, stop and wait for the
        // capture-completed trigger instead of spinning.
        final first = queue.first.captureId;
        if (_deferredThisCycle.contains(first)) break;
        final progressed = await _uploadOne(config, first);
        if (!progressed) _deferredThisCycle.add(first);
        await _emit();
      }
    } finally {
      _deferredThisCycle.clear();
      _syncing = false;
      await _emit();
    }
    if (_rerunQueued) {
      _rerunQueued = false;
      await _drainQueue();
    }
  }

  /// Uploads one capture. Local errors (missing photo number, missing file,
  /// missing password) map into the Rust failure taxonomy so the settings
  /// surface shows one consistent vocabulary. Returns false when the row
  /// was only deferred (capture not ready yet) — the drain treats that as
  /// "no progress" and stops once every queued item defers.
  Future<bool> _uploadOne(NasSyncConfig config, String captureId) async {
    final capture = await _captureById(captureId);
    if (capture == null) {
      await _database.markNasUploadFailed(captureId, 'path_invalid');
      return true;
    }
    if (capture.status != CaptureStatus.ready) {
      // The capture changed while queued; keep the job pending and let the
      // processing-completed table update re-trigger the drain.
      await _database.deferNasUpload(captureId);
      return false;
    }
    final photoNumber = capture.photoNumber;
    if (photoNumber == null || photoNumber.isEmpty) {
      await _database.markNasUploadFailed(captureId, 'path_invalid');
      return true;
    }
    final project = await _database.projectById(capture.projectId);
    if (project == null) {
      await _database.markNasUploadFailed(captureId, 'path_invalid');
      return true;
    }
    final localPath = await _outputPaths.renderedPhotoPath(captureId);
    if (!await File(localPath).exists()) {
      await _database.markNasUploadFailed(captureId, 'local_io');
      return true;
    }
    String password;
    try {
      password = await _credentials.read() ?? '';
    } on Object {
      // Secure-storage breakage must burn a retry budget like any other
      // failure, not bubble out of the drain loop.
      await _database.markNasUploadFailed(captureId, 'config_invalid');
      return true;
    }
    if (password.isEmpty) {
      await _database.markNasUploadFailed(captureId, 'config_invalid');
      return true;
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
    } else {
      await _database.markNasUploadFailed(captureId, failureCode);
    }
    return true;
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
      ),
    );
  }
}
