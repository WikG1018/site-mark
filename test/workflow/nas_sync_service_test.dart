import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/data/nas_sync_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/domain/nas_sync.dart';
import 'package:sitemark/domain/project_name.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/nas_sync_service.dart';

class _FakeCredentials implements NasCredentialStore {
  _FakeCredentials([this.password]);

  String? password;

  @override
  Future<String?> read() async => password;

  @override
  Future<void> write(String password) async {
    this.password = password;
  }

  @override
  Future<void> delete() async {
    password = null;
  }
}

class _FakeConnectivity implements NasConnectivity {
  _FakeConnectivity(this.allowed);

  bool allowed;
  final _changes = StreamController<void>.broadcast();

  @override
  Future<bool> allowsUpload({required bool wifiOnly}) async => allowed;

  @override
  Stream<void> get changes => _changes.stream;

  void becomeAllowed() {
    allowed = true;
    _changes.add(null);
  }
}

class _FakeUploader implements NasUploader {
  _FakeUploader({this.failures});

  /// Codes returned for uploads, consumed in order; null entries succeed.
  final List<String?>? failures;
  final List<NasUploadJob> jobs = [];

  @override
  Future<String?> upload(NasUploadJob job) async {
    jobs.add(job);
    final list = failures;
    if (list != null && list.isNotEmpty) {
      return list.removeAt(0);
    }
    return null;
  }
}

void main() {
  late AppDatabase database;
  late Directory documents;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    documents = await Directory.systemTemp.createTemp('nas-sync-test');
  });

  tearDown(() async {
    await database.close();
    await documents.delete(recursive: true);
  });

  Future<void> seedReadyCapture(
    String id, {
    CaptureStatus status = CaptureStatus.ready,
  }) async {
    try {
      await database.createProject(id: 'p1', name: '云湖之城');
    } on ProjectNameConflictException {
      // Already created by an earlier capture in this test.
    }
    await database
        .into(database.captureRecords)
        .insert(
          CaptureRecordsCompanion.insert(
            id: id,
            projectId: 'p1',
            photoNumber: const Value('003'),
            workLocation: '施工区',
            workContent: '安装检查',
            photographer: 'Builder',
            originalPath: '/private/$id.jpg',
            status: status,
            createdAt: DateTime(2026, 9, 1),
          ),
        );
    await Directory('${documents.path}/rendered').create(recursive: true);
    await File('${documents.path}/rendered/$id.jpg').writeAsBytes([1, 2, 3]);
  }

  NasSyncCoordinator buildCoordinator({
    NasCredentialStore? credentials,
    required NasConnectivity connectivity,
    required NasUploader uploader,
  }) {
    return NasSyncCoordinator(
      database,
      credentials ?? _FakeCredentials('secret'),
      connectivity,
      uploader,
      AppCaptureOutputPaths(documentsDirectory: () async => documents),
    );
  }

  /// Waits until the queue reaches a steady state (no active syncing and
  /// the predicate holds). Keeps ONE subscription so events emitted between
  /// checks are never missed.
  Future<void> pumpUntil(
    NasSyncCoordinator coordinator,
    bool Function(NasSyncSnapshot) predicate,
  ) async {
    final received = <NasSyncSnapshot>[];
    final subscription = coordinator.state.listen(received.add);
    try {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        final last = received.isEmpty ? null : received.last;
        if (last != null && !last.active && predicate(last)) return;
      }
      fail('queue never settled: $received');
    } finally {
      await subscription.cancel();
    }
  }

  test('defers a capture that is not ready without burning attempts', () async {
    // The deferral path guards the drain against spinning forever when a
    // queued capture leaves the ready state between enqueue and upload.
    await seedReadyCapture('a', status: CaptureStatus.rendering);
    await database.upsertNasUploadPending('a');
    final uploader = _FakeUploader();
    final coordinator = buildCoordinator(
      connectivity: _FakeConnectivity(true),
      uploader: uploader,
    );
    addTearDown(coordinator.dispose);

    await database.saveNasSyncConfig(
      protocol: 'webdav',
      host: 'nas.local',
      port: null,
      username: 'builder',
      rootPath: '/SiteMark',
      secureTls: false,
      acceptInvalidTls: false,
      knownSftpFingerprint: null,
      wifiOnly: true,
      enabled: true,
    );
    await coordinator.start();
    await pumpUntil(coordinator, (s) => !s.active && s.pendingCount == 1);

    expect(uploader.jobs, isEmpty);
    final states = await database.allNasUploadStates();
    expect(states.single.status, NasUploadStatus.pending);
    expect(states.single.attempts, 0);
    expect(states.single.lastAttemptAt, isNotNull);
  });

  test('enqueues a capture that becomes ready after sync is enabled', () async {
    await seedReadyCapture('a');
    final uploader = _FakeUploader();
    final coordinator = buildCoordinator(
      connectivity: _FakeConnectivity(true),
      uploader: uploader,
    );
    addTearDown(coordinator.dispose);
    await database.saveNasSyncConfig(
      protocol: 'webdav',
      host: 'nas.local',
      port: null,
      username: 'builder',
      rootPath: '/SiteMark',
      secureTls: false,
      acceptInvalidTls: false,
      knownSftpFingerprint: null,
      wifiOnly: true,
      enabled: true,
    );
    final first = pumpUntil(coordinator, (s) => s.uploadedCount >= 1);
    await coordinator.start();
    await first;

    final second = pumpUntil(coordinator, (s) => s.uploadedCount >= 2);
    await seedReadyCapture('b');
    await second;
    expect(uploader.jobs, hasLength(2));
  });

  test('uploads every ready capture serially when enabled', () async {
    await seedReadyCapture('a');
    await seedReadyCapture('b');
    final uploader = _FakeUploader();
    final coordinator = buildCoordinator(
      connectivity: _FakeConnectivity(true),
      uploader: uploader,
    );
    addTearDown(coordinator.dispose);

    await database.saveNasSyncConfig(
      protocol: 'webdav',
      host: 'nas.local',
      port: null,
      username: 'builder',
      rootPath: '/SiteMark',
      secureTls: false,
      acceptInvalidTls: false,
      knownSftpFingerprint: null,
      wifiOnly: true,
      enabled: true,
    );
    await coordinator.start();
    await pumpUntil(coordinator, (s) => s.uploadedCount == 2);

    expect(uploader.jobs, hasLength(2));
    for (final job in uploader.jobs) {
      expect(job.config.host, 'nas.local');
      expect(job.password, 'secret');
      expect(job.projectKey, '云湖之城');
      expect(job.fileName, '003.jpg');
      expect(File(job.localPath).existsSync(), isTrue);
    }
  });

  test('does nothing while disabled', () async {
    await seedReadyCapture('a');
    final uploader = _FakeUploader();
    final coordinator = buildCoordinator(
      connectivity: _FakeConnectivity(true),
      uploader: uploader,
    );
    addTearDown(coordinator.dispose);
    await coordinator.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(uploader.jobs, isEmpty);
    expect((await database.allNasUploadStates()), isEmpty);
  });

  test('wifi-only gate keeps rows pending on mobile connections', () async {
    await seedReadyCapture('a');
    final uploader = _FakeUploader();
    final coordinator = buildCoordinator(
      connectivity: _FakeConnectivity(false),
      uploader: uploader,
    );
    addTearDown(coordinator.dispose);
    await database.saveNasSyncConfig(
      protocol: 'webdav',
      host: 'nas.local',
      port: null,
      username: 'builder',
      rootPath: '/SiteMark',
      secureTls: false,
      acceptInvalidTls: false,
      knownSftpFingerprint: null,
      wifiOnly: true,
      enabled: true,
    );
    await coordinator.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(uploader.jobs, isEmpty);
    final states = await database.allNasUploadStates();
    expect(states.single.status, NasUploadStatus.pending);
  });

  test('drains pending uploads when connectivity becomes allowed', () async {
    await seedReadyCapture('a');
    final uploader = _FakeUploader();
    final connectivity = _FakeConnectivity(false);
    final coordinator = buildCoordinator(
      connectivity: connectivity,
      uploader: uploader,
    );
    addTearDown(coordinator.dispose);
    await database.saveNasSyncConfig(
      protocol: 'webdav',
      host: 'nas.local',
      port: null,
      username: 'builder',
      rootPath: '/SiteMark',
      secureTls: false,
      acceptInvalidTls: false,
      knownSftpFingerprint: null,
      wifiOnly: true,
      enabled: true,
    );
    final parked = pumpUntil(
      coordinator,
      (s) => !s.active && s.pendingCount == 1,
    );
    await coordinator.start();
    await parked;
    expect(uploader.jobs, isEmpty);

    final uploaded = pumpUntil(coordinator, (s) => s.uploadedCount >= 1);
    connectivity.becomeAllowed();
    await uploaded;
    expect(uploader.jobs, hasLength(1));
  });

  test('missing password parks the upload in config_invalid', () async {
    await seedReadyCapture('a');
    final uploader = _FakeUploader();
    final coordinator = buildCoordinator(
      credentials: _FakeCredentials(null),
      connectivity: _FakeConnectivity(true),
      uploader: uploader,
    );
    addTearDown(coordinator.dispose);
    await database.saveNasSyncConfig(
      protocol: 'webdav',
      host: 'nas.local',
      port: null,
      username: 'builder',
      rootPath: '/SiteMark',
      secureTls: false,
      acceptInvalidTls: false,
      knownSftpFingerprint: null,
      wifiOnly: true,
      enabled: true,
    );
    await coordinator.start();
    await pumpUntil(coordinator, (s) => s.active == false);

    expect(uploader.jobs, isEmpty);
    expect(
      (await database.allNasUploadStates()).single.failureCode,
      'config_invalid',
    );
  });

  test('missing rendered file parks the upload in local_io', () async {
    await seedReadyCapture('a');
    await File('${documents.path}/rendered/a.jpg').delete();
    final uploader = _FakeUploader();
    final coordinator = buildCoordinator(
      connectivity: _FakeConnectivity(true),
      uploader: uploader,
    );
    addTearDown(coordinator.dispose);
    await database.saveNasSyncConfig(
      protocol: 'webdav',
      host: 'nas.local',
      port: null,
      username: 'builder',
      rootPath: '/SiteMark',
      secureTls: false,
      acceptInvalidTls: false,
      knownSftpFingerprint: null,
      wifiOnly: true,
      enabled: true,
    );
    await coordinator.start();
    await pumpUntil(coordinator, (s) => s.active == false);

    expect(uploader.jobs, isEmpty);
    expect(
      (await database.allNasUploadStates()).single.failureCode,
      'local_io',
    );
  });

  test('uploader failures count toward the retry budget', () async {
    await seedReadyCapture('a');
    final uploader = _FakeUploader(
      failures: [
        'auth_failed',
        'auth_failed',
        'auth_failed',
        'auth_failed',
        'auth_failed',
      ],
    );
    final coordinator = buildCoordinator(
      connectivity: _FakeConnectivity(true),
      uploader: uploader,
    );
    addTearDown(coordinator.dispose);
    await database.saveNasSyncConfig(
      protocol: 'webdav',
      host: 'nas.local',
      port: null,
      username: 'builder',
      rootPath: '/SiteMark',
      secureTls: false,
      acceptInvalidTls: false,
      knownSftpFingerprint: null,
      wifiOnly: true,
      enabled: true,
    );
    await coordinator.start();
    await pumpUntil(coordinator, (s) => s.failedCount == 1);

    expect(uploader.jobs, hasLength(5));
    final state = (await database.allNasUploadStates()).single;
    expect(state.status, NasUploadStatus.failed);
    expect(state.attempts, 5);
    expect(await database.pendingNasUploads(), isEmpty);

    // An explicit retry re-arms and succeeds (failure list exhausted).
    await coordinator.retryFailedUploads();
    await pumpUntil(coordinator, (s) => s.uploadedCount == 1);
    expect(uploader.jobs, hasLength(6));
  });
}
