import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/project_lifecycle.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> insertReadyCapture({
    required String id,
    required String projectId,
    required DateTime capturedAt,
  }) async {
    final pending = await database.createPendingCapture(
      id: id,
      projectId: projectId,
      originalPath: '/private/$id.jpg',
      workLocation: 'A 区',
      workContent: '检查',
      photographer: '张工',
      watermarkLocaleCode: 'zh',
      createdAt: capturedAt,
    );
    await database.markCaptured(captureId: pending.id, capturedAt: capturedAt);
    await database.markRendering(
      captureId: pending.id,
      originalSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    await database.markReady(
      captureId: pending.id,
      publishedUri: 'content://media/$id',
    );
  }

  test('returns the three newest ready capture ids for each project', () async {
    await database.createProject(id: 'recent', name: '最近项目');
    await database.createProject(id: 'empty', name: '空项目');

    for (var index = 0; index < 4; index++) {
      await insertReadyCapture(
        id: 'capture-$index',
        projectId: 'recent',
        capturedAt: DateTime.utc(2026, 8, 3, 8, index),
      );
    }
    final capturedOnly = await database.createPendingCapture(
      id: 'capture-not-ready',
      projectId: 'recent',
      originalPath: '/private/capture-not-ready.jpg',
      workLocation: 'A 区',
      workContent: '检查',
      photographer: '张工',
      watermarkLocaleCode: 'zh',
      createdAt: DateTime.utc(2026, 8, 3, 9),
    );
    await database.markCaptured(
      captureId: capturedOnly.id,
      capturedAt: DateTime.utc(2026, 8, 3, 9),
    );

    final summaries = await database
        .watchProjectSummaries(status: ProjectLifecycleStatus.active)
        .first;
    final recent = summaries.singleWhere(
      (summary) => summary.project.id == 'recent',
    );
    final empty = summaries.singleWhere(
      (summary) => summary.project.id == 'empty',
    );

    expect(recent.recentCaptureIds, ['capture-3', 'capture-2', 'capture-1']);
    expect(recent.recentCaptureIds, hasLength(3));
    expect(empty.recentCaptureIds, isEmpty);
  });

  test('round-trips opaque ready capture ids without delimiter loss', () async {
    await database.createProject(id: 'opaque', name: '不透明编号');
    final unitSeparatorId = 'unit${String.fromCharCode(31)}separator';
    const escapedId = 'quote"slash\\';
    final ids = [unitSeparatorId, escapedId, ''];
    for (final (index, id) in ids.indexed) {
      await insertReadyCapture(
        id: id,
        projectId: 'opaque',
        capturedAt: DateTime.utc(
          2026,
          8,
          3,
          10,
        ).subtract(Duration(minutes: index)),
      );
    }

    final summary =
        (await database
                .watchProjectSummaries(status: ProjectLifecycleStatus.active)
                .first)
            .single;

    expect(summary.recentCaptureIds, ids);
    expect(summary.recentCaptureIds, hasLength(3));
  });

  test('orders equal capture timestamps by id descending', () async {
    await database.createProject(id: 'ties', name: '同时间项目');
    final capturedAt = DateTime.utc(2026, 8, 3, 11);
    for (final id in ['capture-a', 'capture-c', 'capture-b']) {
      await insertReadyCapture(
        id: id,
        projectId: 'ties',
        capturedAt: capturedAt,
      );
    }

    final summary =
        (await database
                .watchProjectSummaries(status: ProjectLifecycleStatus.active)
                .first)
            .single;

    expect(summary.recentCaptureIds, ['capture-c', 'capture-b', 'capture-a']);
  });

  test(
    'orders active summaries by pin, last capture, created_at, id',
    () async {
      await database.createProject(
        id: 'empty',
        name: '空项目',
        createdAt: DateTime.utc(2026, 8, 1, 8),
      );
      await database.createProject(
        id: 'recent',
        name: '最近项目',
        createdAt: DateTime.utc(2026, 8, 1, 9),
      );
      await database.createProject(
        id: 'pinned',
        name: '置顶项目',
        createdAt: DateTime.utc(2026, 8, 1, 7),
        isPinned: true,
      );
      await database.createProject(
        id: 'done',
        name: '已完成项目',
        createdAt: DateTime.utc(2026, 8, 1, 10),
      );
      await database.createProject(
        id: 'archived',
        name: '归档厂房',
        createdAt: DateTime.utc(2026, 8, 1, 11),
      );
      await database.createProject(
        id: 'restoring',
        name: '恢复中项目',
        createdAt: DateTime.utc(2026, 8, 1, 12),
        restoreOperationId: 'op-1',
      );

      // Pinned project has an older capture than "recent", so pin is the only
      // reason it ranks first. After unpin it falls behind "recent".
      await insertReadyCapture(
        id: 'pinned-ready',
        projectId: 'pinned',
        capturedAt: DateTime(2026, 8, 3, 8),
      );
      await database.createPendingCapture(
        id: 'pinned-pending',
        projectId: 'pinned',
        originalPath: '/private/pinned-pending.jpg',
        workLocation: 'B 区',
        workContent: '待拍',
        photographer: '李工',
        watermarkLocaleCode: 'zh',
        createdAt: DateTime(2026, 8, 3, 12),
      );
      await insertReadyCapture(
        id: 'recent-ready',
        projectId: 'recent',
        capturedAt: DateTime(2026, 8, 3, 10),
      );
      await insertReadyCapture(
        id: 'archived-ready',
        projectId: 'archived',
        capturedAt: DateTime(2026, 8, 3, 8),
      );
      await database.updateProjectLifecycleStatus(
        projectId: 'done',
        expectedStatus: ProjectLifecycleStatus.active,
        targetStatus: ProjectLifecycleStatus.completed,
      );
      await database.updateProjectLifecycleStatus(
        projectId: 'archived',
        expectedStatus: ProjectLifecycleStatus.active,
        targetStatus: ProjectLifecycleStatus.archived,
      );

      final active = await database
          .watchProjectSummaries(status: ProjectLifecycleStatus.active)
          .first;
      expect(active.map((item) => item.project.id), [
        'pinned',
        'recent',
        'empty',
      ]);
      expect(active.first.captureCount, 1);
      expect(active.first.lastCaptureAt, DateTime(2026, 8, 3, 8));
      expect(active[1].captureCount, 1);
      expect(active[1].lastCaptureAt, DateTime(2026, 8, 3, 10));
      expect(active[2].captureCount, 0);
      expect(active[2].lastCaptureAt, isNull);

      final search = await database.watchProjectSummaries(search: '归档厂房').first;
      expect(search.single.project.id, 'archived');
      expect(
        search.single.project.lifecycleStatus,
        ProjectLifecycleStatus.archived,
      );

      final allActiveIds = active.map((item) => item.project.id);
      expect(allActiveIds, isNot(contains('restoring')));
      expect(allActiveIds, isNot(contains('done')));
      expect(allActiveIds, isNot(contains('archived')));

      final beforeUnpin = (await database.projectById('pinned'))!;
      await database.setProjectPinned('pinned', false);
      final afterUnpin = (await database.projectById('pinned'))!;
      expect(afterUnpin.isPinned, isFalse);
      expect(afterUnpin.updatedAt, beforeUnpin.updatedAt);
      final unpinned = await database
          .watchProjectSummaries(status: ProjectLifecycleStatus.active)
          .first;
      expect(unpinned.map((item) => item.project.id), [
        'recent',
        'pinned',
        'empty',
      ]);
    },
  );

  test('stable-sorts equal last capture by created_at then id', () async {
    final sameCapture = DateTime(2026, 8, 3, 15);
    await database.createProject(
      id: 'b-project',
      name: 'B项目',
      createdAt: DateTime.utc(2026, 8, 2, 10),
    );
    await database.createProject(
      id: 'a-project',
      name: 'A项目',
      createdAt: DateTime.utc(2026, 8, 2, 10),
    );
    await database.createProject(
      id: 'older-created',
      name: '更早创建',
      createdAt: DateTime.utc(2026, 8, 2, 9),
    );
    await insertReadyCapture(
      id: 'cap-b',
      projectId: 'b-project',
      capturedAt: sameCapture,
    );
    await insertReadyCapture(
      id: 'cap-a',
      projectId: 'a-project',
      capturedAt: sameCapture,
    );
    await insertReadyCapture(
      id: 'cap-older',
      projectId: 'older-created',
      capturedAt: sameCapture,
    );

    final summaries = await database
        .watchProjectSummaries(status: ProjectLifecycleStatus.active)
        .first;
    expect(summaries.map((item) => item.project.id), [
      'a-project',
      'b-project',
      'older-created',
    ]);
  });
}
