import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/data/nas_sync_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/domain/nas_sync.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedCapture(
    String id, {
    CaptureStatus status = CaptureStatus.ready,
    String projectId = 'p1',
    String? photoNumber,
  }) async {
    await database
        .into(database.captureRecords)
        .insert(
          CaptureRecordsCompanion.insert(
            id: id,
            projectId: projectId,
            photoNumber: Value(photoNumber),
            workLocation: '施工区',
            workContent: '安装检查',
            photographer: 'Builder',
            originalPath: '/private/$id.jpg',
            status: status,
            createdAt: DateTime(2026, 9, 1),
          ),
        );
  }

  Future<void> seedProject() => database.createProject(id: 'p1', name: '云湖之城');

  group('nas sync config singleton', () {
    test('creates defaults on first use and keeps them stable', () async {
      final first = await database.nasSyncConfig();
      expect(first.id, 'global');
      expect(first.enabled, isFalse);
      expect(first.host, isEmpty);
      expect(first.secureTls, isTrue);
      expect(first.acceptInvalidTls, isFalse);

      final again = await database.nasSyncConfig();
      expect(again.id, 'global');
    });

    test('save round-trips every field', () async {
      await database.saveNasSyncConfig(
        protocol: 'sftp',
        host: 'nas.local',
        port: 2222,
        username: 'builder',
        rootPath: '/volume1/SiteMark',
        secureTls: false,
        acceptInvalidTls: false,
        knownSftpFingerprint: 'SHA256:abc',
        wifiOnly: false,
        enabled: true,
      );
      final saved = await database.nasSyncConfig();
      expect(saved.protocol, 'sftp');
      expect(saved.host, 'nas.local');
      expect(saved.port, 2222);
      expect(saved.username, 'builder');
      expect(saved.rootPath, '/volume1/SiteMark');
      expect(saved.knownSftpFingerprint, 'SHA256:abc');
      expect(saved.wifiOnly, isFalse);
      expect(saved.enabled, isTrue);
      expect(saved.updatedAt, isNotNull);
    });
  });

  group('upload queue', () {
    test(
      'enqueueReadyCapturesForNas enqueues only ready captures once',
      () async {
        await seedProject();
        await seedCapture('ready-1');
        await seedCapture('ready-2');
        await seedCapture('rendering', status: CaptureStatus.rendering);
        await seedCapture('failed', status: CaptureStatus.failed);

        await database.enqueueReadyCapturesForNas();
        // Re-running must not duplicate or reset anything.
        await database.enqueueReadyCapturesForNas();

        final states = await database.allNasUploadStates();
        expect(
          states.map((row) => row.captureId),
          unorderedEquals(['ready-1', 'ready-2']),
        );
        expect(
          states.every((row) => row.status == NasUploadStatus.pending),
          isTrue,
        );
      },
    );

    test('re-enqueue never downgrades an uploaded state', () async {
      await seedProject();
      await seedCapture('done', photoNumber: '003');
      await database.upsertNasUploadPending('done');
      await database.markNasUploaded('done');

      await database.upsertNasUploadPending('done');
      await database.enqueueReadyCapturesForNas();

      final state = (await database.allNasUploadStates()).single;
      expect(state.status, NasUploadStatus.uploaded);
    });

    test(
      'pendingNasUploads excludes exhausted, failed and uploaded rows',
      () async {
        await seedProject();
        await seedCapture('a');
        await seedCapture('b');
        await seedCapture('c');
        await seedCapture('d');
        for (final id in ['a', 'b', 'c', 'd']) {
          await database.upsertNasUploadPending(id);
        }

        // a: uploaded. b: budget exhausted. c: fresh. d: failed directly.
        await database.markNasUploaded('a');
        for (var i = 0; i < kNasMaxUploadAttempts; i++) {
          await database.markNasUploadFailed('b', 'connection_failed');
        }
        await (database.update(
          database.nasUploadStates,
        )..where((row) => row.captureId.equals('d'))).write(
          const NasUploadStatesCompanion(status: Value(NasUploadStatus.failed)),
        );

        final pending = await database.pendingNasUploads();
        expect(pending.map((row) => row.captureId), ['c']);
      },
    );

    test(
      'markNasUploadFailed bumps attempts and parks at the budget',
      () async {
        await seedProject();
        await seedCapture('x');
        await database.upsertNasUploadPending('x');

        await database.markNasUploadFailed('x', 'auth_failed');
        var state = (await database.allNasUploadStates()).single;
        expect(state.attempts, 1);
        expect(state.status, NasUploadStatus.pending);
        expect(state.failureCode, 'auth_failed');
        expect(state.lastAttemptAt, isNotNull);

        for (var i = 0; i < kNasMaxUploadAttempts - 1; i++) {
          await database.markNasUploadFailed('x', 'auth_failed');
        }
        state = (await database.allNasUploadStates()).single;
        expect(state.attempts, kNasMaxUploadAttempts);
        expect(state.status, NasUploadStatus.failed);
        // Exhausted rows are no longer served automatically.
        expect(await database.pendingNasUploads(), isEmpty);
      },
    );

    test('resetNasUploadForRetry re-arms a failed row', () async {
      await seedProject();
      await seedCapture('x');
      await database.upsertNasUploadPending('x');
      for (var i = 0; i < kNasMaxUploadAttempts; i++) {
        await database.markNasUploadFailed('x', 'timeout');
      }
      await database.resetNasUploadForRetry('x');

      final state = (await database.allNasUploadStates()).single;
      expect(state.status, NasUploadStatus.pending);
      expect(state.attempts, 0);
      expect(state.failureCode, isNull);
      expect((await database.pendingNasUploads()).single.captureId, 'x');
    });

    test('markNasUploaded clears the failure code', () async {
      await seedProject();
      await seedCapture('x');
      await database.upsertNasUploadPending('x');
      await database.markNasUploadFailed('x', 'timeout');
      await database.markNasUploaded('x');

      final state = (await database.allNasUploadStates()).single;
      expect(state.status, NasUploadStatus.uploaded);
      expect(state.failureCode, isNull);
      expect(state.uploadedAt, isNotNull);
    });
  });

  group('remote path rules', () {
    test('file name is the photo number plus jpg', () {
      expect(nasRemoteFileName('003'), '003.jpg');
    });

    test('project key reuses the sanitized photo file name', () {
      expect(nasProjectKey('云湖之城'), '云湖之城');
      expect(nasProjectKey('a/b:c'), 'a_b_c');
      expect(nasProjectKey('   '), 'Project');
    });
  });
}
