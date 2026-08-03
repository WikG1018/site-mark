import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/domain/project_lifecycle.dart';
import 'package:sitemark/workflow/project_lifecycle_service.dart';

void main() {
  late AppDatabase database;
  late ProjectLifecycleService service;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    service = ProjectLifecycleService(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedProject(
    String id, {
    ProjectLifecycleStatus status = ProjectLifecycleStatus.active,
  }) async {
    await database.createProject(id: id, name: '项目-$id');
    if (status != ProjectLifecycleStatus.active) {
      await database.updateProjectLifecycleStatus(
        projectId: id,
        expectedStatus: ProjectLifecycleStatus.active,
        targetStatus: status,
      );
    }
  }

  Future<void> seedCapture(
    String id,
    String projectId,
    CaptureStatus status,
  ) async {
    final pending = await database.createPendingCapture(
      id: id,
      projectId: projectId,
      originalPath: '/private/$id.jpg',
      workLocation: 'A 区',
      workContent: '检查',
      photographer: '张工',
      watermarkLocaleCode: 'zh',
    );
    if (status == CaptureStatus.pendingCamera) {
      return;
    }
    await database.markCaptured(
      captureId: pending.id,
      capturedAt: DateTime(2026, 8, 3, 10),
    );
    if (status == CaptureStatus.captured) {
      return;
    }
    await database.markRendering(
      captureId: pending.id,
      originalSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    if (status == CaptureStatus.rendering) {
      return;
    }
    if (status == CaptureStatus.failed) {
      await database.markFailed(captureId: pending.id, reason: 'render failed');
      return;
    }
    await database.markReady(
      captureId: pending.id,
      publishedUri: 'content://media/$id',
    );
  }

  test('preview reports zero processing for clean active project', () async {
    await seedProject('active');
    final preview = await service.preview(
      'active',
      ProjectLifecycleStatus.completed,
    );
    expect(preview.processingCount, 0);
    expect(preview.failedCount, 0);
    expect(preview.expectedStatus, ProjectLifecycleStatus.active);
    expect(preview.targetStatus, ProjectLifecycleStatus.completed);
  });

  test('blocks transition while captures are processing', () async {
    await seedProject('busy');
    await seedCapture('p1', 'busy', CaptureStatus.pendingCamera);
    await seedCapture('c1', 'busy', CaptureStatus.captured);
    final preview = await service.preview(
      'busy',
      ProjectLifecycleStatus.completed,
    );
    expect(preview.processingCount, 2);
    await expectLater(
      () => service.transition(preview, confirmFailed: false),
      throwsA(
        isA<ProjectLifecycleProcessingException>().having(
          (error) => error.processingCount,
          'processingCount',
          2,
        ),
      ),
    );
  });

  test('requires confirmation when only failed captures remain', () async {
    await seedProject('failed-only');
    await seedCapture('f1', 'failed-only', CaptureStatus.failed);
    final preview = await service.preview(
      'failed-only',
      ProjectLifecycleStatus.completed,
    );
    expect(preview.failedCount, 1);
    await expectLater(
      () => service.transition(preview, confirmFailed: false),
      throwsA(isA<ProjectLifecycleConfirmationRequiredException>()),
    );
    final completed = await service.transition(preview, confirmFailed: true);
    expect(completed.lifecycleStatus, ProjectLifecycleStatus.completed);
  });

  test('allows every legal lifecycle transition', () async {
    await seedProject('legal');
    Future<void> move(
      ProjectLifecycleStatus from,
      ProjectLifecycleStatus to,
    ) async {
      final preview = await service.preview('legal', to);
      expect(preview.expectedStatus, from);
      final project = await service.transition(preview, confirmFailed: false);
      expect(project.lifecycleStatus, to);
    }

    await move(ProjectLifecycleStatus.active, ProjectLifecycleStatus.completed);
    await move(ProjectLifecycleStatus.completed, ProjectLifecycleStatus.active);
    await move(ProjectLifecycleStatus.active, ProjectLifecycleStatus.archived);
    await move(ProjectLifecycleStatus.archived, ProjectLifecycleStatus.active);
    await move(ProjectLifecycleStatus.active, ProjectLifecycleStatus.completed);
    await move(
      ProjectLifecycleStatus.completed,
      ProjectLifecycleStatus.archived,
    );
  });

  test('rejects same-status and disallowed transitions', () async {
    await seedProject('illegal');
    await expectLater(
      () => service.preview('illegal', ProjectLifecycleStatus.active),
      throwsA(isA<ProjectLifecycleInvalidTransitionException>()),
    );

    await database.updateProjectLifecycleStatus(
      projectId: 'illegal',
      expectedStatus: ProjectLifecycleStatus.active,
      targetStatus: ProjectLifecycleStatus.archived,
    );
    await expectLater(
      () => service.preview('illegal', ProjectLifecycleStatus.completed),
      throwsA(isA<ProjectLifecycleInvalidTransitionException>()),
    );
  });

  test('detects conflict when status changes after preview', () async {
    await seedProject('race');
    final preview = await service.preview(
      'race',
      ProjectLifecycleStatus.completed,
    );
    await database.updateProjectLifecycleStatus(
      projectId: 'race',
      expectedStatus: ProjectLifecycleStatus.active,
      targetStatus: ProjectLifecycleStatus.archived,
    );
    await expectLater(
      () => service.transition(preview, confirmFailed: false),
      throwsA(isA<ProjectLifecycleConflictException>()),
    );
  });

  test('recounts processing inside the transition transaction', () async {
    await seedProject('late-processing');
    final preview = await service.preview(
      'late-processing',
      ProjectLifecycleStatus.completed,
    );
    expect(preview.processingCount, 0);
    await seedCapture('late', 'late-processing', CaptureStatus.rendering);
    await expectLater(
      () => service.transition(preview, confirmFailed: false),
      throwsA(isA<ProjectLifecycleProcessingException>()),
    );
  });
}
