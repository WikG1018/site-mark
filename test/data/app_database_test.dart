import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';

void main() {
  const originalHash =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('creates and lists projects newest first', () async {
    await database.createProject(
      id: 'older',
      name: '一号厂房',
      createdAt: DateTime.utc(2026, 7, 15),
    );
    await database.createProject(
      id: 'newer',
      name: '二号厂房',
      createdAt: DateTime.utc(2026, 7, 16),
    );

    final projects = await database.watchProjects().first;

    expect(projects.map((project) => project.name), ['二号厂房', '一号厂房']);
  });

  test('persists constrained project watermark settings', () async {
    await database.createProject(id: 'project', name: '车间改造');

    final updated = await database.updateProjectWatermarkSettings(
      projectId: 'project',
      position: 'bottomRight',
      opacity: 0.64,
      accentColorArgb: 0xff1565c0,
    );

    expect(updated.watermarkPosition, 'bottomRight');
    expect(updated.watermarkOpacity, 0.64);
    expect(updated.watermarkAccentColorArgb, 0xff1565c0);
  });

  test('allocates a daily photo number only after capture succeeds', () async {
    await database.createProject(
      id: 'project',
      name: '车间改造',
      createdAt: DateTime.utc(2026, 7, 16),
    );
    final pending = await database.createPendingCapture(
      id: 'capture-1',
      projectId: 'project',
      originalPath: '/private/capture-1.jpg',
      workLocation: 'A 区',
      workContent: '风管安装',
      photographer: '张工',
      createdAt: DateTime(2026, 7, 16, 9, 30),
    );

    expect(pending.status, CaptureStatus.pendingCamera);
    expect(pending.photoNumber, isNull);

    final captured = await database.markCaptured(
      captureId: pending.id,
      capturedAt: DateTime(2026, 7, 16, 9, 32),
    );

    expect(captured.status, CaptureStatus.captured);
    expect(captured.photoNumber, 'SM-20260716-001');
  });

  test(
    'continues the sequence across ready and failed render records',
    () async {
      await database.createProject(
        id: 'project',
        name: '车间改造',
        createdAt: DateTime.utc(2026, 7, 16),
      );
      for (var index = 1; index <= 2; index++) {
        final pending = await database.createPendingCapture(
          id: 'capture-$index',
          projectId: 'project',
          originalPath: '/private/capture-$index.jpg',
          workLocation: 'A 区',
          workContent: '风管安装',
          photographer: '张工',
          createdAt: DateTime(2026, 7, 16, 9, 30 + index),
        );
        await database.markCaptured(
          captureId: pending.id,
          capturedAt: DateTime(2026, 7, 16, 9, 30 + index),
        );
      }

      final third = await database.createPendingCapture(
        id: 'capture-3',
        projectId: 'project',
        originalPath: '/private/capture-3.jpg',
        workLocation: 'B 区',
        workContent: '保温检查',
        photographer: '李工',
        createdAt: DateTime(2026, 7, 16, 10),
      );
      final captured = await database.markCaptured(
        captureId: third.id,
        capturedAt: DateTime(2026, 7, 16, 10, 1),
      );

      expect(captured.photoNumber, 'SM-20260716-003');
    },
  );

  test('returns pending camera records for startup recovery', () async {
    await database.createProject(
      id: 'project',
      name: '车间改造',
      createdAt: DateTime.utc(2026, 7, 16),
    );
    await database.createPendingCapture(
      id: 'capture-1',
      projectId: 'project',
      originalPath: '/private/capture-1.jpg',
      workLocation: 'A 区',
      workContent: '风管安装',
      photographer: '张工',
      createdAt: DateTime(2026, 7, 16, 9, 30),
    );

    final pending = await database.pendingCameraCaptures();

    expect(pending.map((capture) => capture.id), ['capture-1']);
  });

  test(
    'persists render and publish transitions with traceability metadata',
    () async {
      await database.createProject(
        id: 'project',
        name: '车间改造',
        createdAt: DateTime.utc(2026, 7, 16),
      );
      final pending = await database.createPendingCapture(
        id: 'capture-1',
        projectId: 'project',
        originalPath: '/private/capture-1.jpg',
        workLocation: 'A 区',
        workContent: '风管安装',
        photographer: '张工',
        createdAt: DateTime(2026, 7, 16, 9, 30),
      );
      await database.markCaptured(
        captureId: pending.id,
        capturedAt: DateTime(2026, 7, 16, 9, 32),
      );

      final rendering = await database.markRendering(
        captureId: pending.id,
        originalSha256: originalHash,
      );
      final ready = await database.markReady(
        captureId: pending.id,
        publishedUri: 'content://media/photo/1',
      );

      expect(rendering.status, CaptureStatus.rendering);
      expect(rendering.originalSha256, originalHash);
      expect(ready.status, CaptureStatus.ready);
      expect(ready.publishedUri, 'content://media/photo/1');
    },
  );

  test('rejects illegal persisted state transitions', () async {
    await database.createProject(
      id: 'project',
      name: '车间改造',
      createdAt: DateTime.utc(2026, 7, 16),
    );
    final pending = await database.createPendingCapture(
      id: 'capture-1',
      projectId: 'project',
      originalPath: '/private/capture-1.jpg',
      workLocation: 'A 区',
      workContent: '风管安装',
      photographer: '张工',
    );

    expect(
      () => database.markReady(
        captureId: pending.id,
        publishedUri: 'content://media/photo/1',
      ),
      throwsStateError,
    );
  });

  test('edits descriptive fields without changing capture evidence', () async {
    await database.createProject(id: 'project', name: '车间改造');
    final pending = await database.createPendingCapture(
      id: 'capture-1',
      projectId: 'project',
      originalPath: '/private/capture-1.jpg',
      workLocation: 'A 区',
      workContent: '风管安装',
      photographer: '张工',
    );
    final capturedAt = DateTime(2026, 7, 16, 9, 32);
    await database.markCaptured(captureId: pending.id, capturedAt: capturedAt);
    await database.markRendering(
      captureId: pending.id,
      originalSha256: originalHash,
    );
    await database.markReady(
      captureId: pending.id,
      publishedUri: 'content://media/photo/1',
    );

    final edited = await database.updateCaptureDescription(
      captureId: pending.id,
      workLocation: 'B 区',
      workContent: '保温复查',
      photographer: '李工',
      notes: '整改后复验',
    );

    expect(edited.workLocation, 'B 区');
    expect(edited.workContent, '保温复查');
    expect(edited.photographer, '李工');
    expect(edited.notes, '整改后复验');
    expect(edited.capturedAt, capturedAt);
    expect(edited.originalSha256, originalHash);
    expect(edited.photoNumber, 'SM-20260716-001');
  });
}
