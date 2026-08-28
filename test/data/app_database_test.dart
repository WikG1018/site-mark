import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/data/capture_query_repository.dart';
import 'package:sitemark/domain/capture_filter.dart';
import 'package:sitemark/domain/capture_list_query.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/domain/project_lifecycle.dart';
import 'package:sitemark/domain/project_name.dart';

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

  test('in-progress restores stay hidden until ownership clears', () async {
    await database.createProject(id: 'normal', name: '正常项目');
    await database.createProject(
      id: 'restoring',
      name: '恢复中的项目',
      restoreOperationId: 'restore-operation',
    );
    final normalCapture = await database.createPendingCapture(
      id: 'normal-capture',
      projectId: 'normal',
      originalPath: '/private/normal.jpg',
      workLocation: 'A 区',
      workContent: '正常记录',
      photographer: '张工',
      watermarkLocaleCode: 'zh',
    );
    await database.markCaptured(
      captureId: normalCapture.id,
      capturedAt: DateTime(2026, 7, 28, 9),
    );
    final restoringCapture = await database.createPendingCapture(
      id: 'restoring-capture',
      projectId: 'restoring',
      originalPath: '/private/restoring.jpg',
      workLocation: 'B 区',
      workContent: '恢复记录',
      photographer: '李工',
      watermarkLocaleCode: 'zh',
    );
    await database.markCaptured(
      captureId: restoringCapture.id,
      capturedAt: DateTime(2026, 7, 28, 10),
    );

    final projectUpdates = StreamIterator(database.watchProjects());
    final queryRepository = CaptureQueryRepository(database);
    addTearDown(projectUpdates.cancel);
    expect(await projectUpdates.moveNext(), isTrue);
    expect(projectUpdates.current.map((project) => project.id), ['normal']);
    expect((await database.getProjects()).map((project) => project.id), [
      'normal',
    ]);
    expect(
      (await database.getAllProjectsInternal()).map((project) => project.id),
      containsAll(['normal', 'restoring']),
    );
    expect(
      (await queryRepository.loadPage(
        const CaptureListQuery(),
      )).rows.map((summary) => summary.capture.id),
      ['normal-capture'],
    );
    expect(await database.projectById('restoring'), isNotNull);

    await database.clearProjectRestoreOwnership(
      projectId: 'restoring',
      operationId: 'restore-operation',
    );

    expect(await projectUpdates.moveNext(), isTrue);
    expect(
      projectUpdates.current.map((project) => project.id),
      containsAll(['normal', 'restoring']),
    );
    expect(
      (await queryRepository.loadPage(
        const CaptureListQuery(),
      )).rows.map((summary) => summary.capture.id),
      ['restoring-capture', 'normal-capture'],
    );
  });

  test('rejects normalized duplicate project names', () async {
    await database.createProject(id: 'project-a', name: 'Cloud Site');

    expect(
      () => database.createProject(id: 'project-b', name: ' cloud   site '),
      throwsA(
        isA<ProjectNameConflictException>().having(
          (error) => error.kind,
          'kind',
          ProjectNameConflictKind.displayName,
        ),
      ),
    );
  });

  test('rejects duplicate safe project file-name keys', () async {
    await database.createProject(id: 'project-a', name: 'A/B');

    expect(
      () => database.createProject(id: 'project-b', name: 'A:B'),
      throwsA(
        isA<ProjectNameConflictException>().having(
          (error) => error.kind,
          'kind',
          ProjectNameConflictKind.safeFileName,
        ),
      ),
    );
  });

  test('renameProject rejects display and safe-file-name conflicts', () async {
    await database.createProject(id: 'a', name: '东区');
    await database.createProject(id: 'b', name: '西区');
    await expectLater(
      database.renameProject(projectId: 'b', name: '  东区  '),
      throwsA(isA<ProjectNameConflictException>()),
    );
    await database.createProject(id: 'c', name: 'A/B');
    await expectLater(
      database.renameProject(projectId: 'b', name: 'A:B'),
      throwsA(isA<ProjectNameConflictException>()),
    );
  });

  test('renameProject preserves existing capture evidence', () async {
    await database.createProject(id: 'a', name: '东区');
    final pending = await database.createPendingCapture(
      id: 'capture-1',
      projectId: 'a',
      originalPath: '/private/capture-1.jpg',
      workLocation: 'A 区',
      workContent: '风管安装',
      photographer: '张工',
      watermarkLocaleCode: 'zh',
      createdAt: DateTime(2026, 7, 16, 9, 30),
    );
    await database.markCaptured(
      captureId: pending.id,
      capturedAt: DateTime(2026, 7, 16, 9, 32),
    );

    final before = await database.capturesForProject('a');
    final renamed = await database.renameProject(projectId: 'a', name: '东区新名称');
    final after = await database.capturesForProject('a');

    expect(renamed.name, '东区新名称');
    expect(after.single.photoNumber, before.single.photoNumber);
    expect(after.single.originalPath, before.single.originalPath);
  });

  test('persists constrained project watermark settings', () async {
    await database.createProject(id: 'project', name: '车间改造');

    final updated = await database.updateProjectWatermarkSettings(
      projectId: 'project',
      position: 'bottomRight',
      opacity: 0.64,
      accentColorArgb: 0xff1565c0,
      fontScale: 1.0,
    );

    expect(updated.watermarkPosition, 'bottomRight');
    expect(updated.watermarkOpacity, 0.64);
    expect(updated.watermarkAccentColorArgb, 0xff1565c0);
  });

  test(
    'createProject stores provided watermark defaults and falls back to table defaults when omitted',
    () async {
      final withOverrides = await database.createProject(
        id: 'project-a',
        name: '屋面工程',
        watermarkPosition: 'bottomRight',
        watermarkOpacity: 0.64,
        watermarkAccentColorArgb: 0xff1565c0,
      );
      expect(withOverrides.watermarkPosition, 'bottomRight');
      expect(withOverrides.watermarkOpacity, 0.64);
      expect(withOverrides.watermarkAccentColorArgb, 0xff1565c0);

      final withDefaults = await database.createProject(
        id: 'project-b',
        name: '默认项目',
      );
      expect(withDefaults.watermarkPosition, 'bottomLeft');
      expect(withDefaults.watermarkOpacity, 0.78);
      expect(withDefaults.watermarkAccentColorArgb, 0xff37c58b);
    },
  );

  test(
    'changing global watermark defaults does not retroactively update existing projects',
    () async {
      // 1. Create a project that copies the current global defaults
      //    (bottomLeft, 0.78, 0xff37c58b).
      final created = await database.createProject(id: 'project', name: '既有项目');
      expect(created.watermarkPosition, 'bottomLeft');
      expect(created.watermarkOpacity, 0.78);
      expect(created.watermarkAccentColorArgb, 0xff37c58b);

      // 2. Change the global watermark defaults.
      await database.updateAppSettings(
        defaultWatermarkPosition: 'bottomRight',
        defaultWatermarkOpacity: 0.64,
        defaultWatermarkAccentColorArgb: 0xff1565c0,
      );

      // 3. Re-read the project and assert its watermark fields are unchanged:
      //    global defaults affect newly created projects only.
      final reloaded = await database.projectById('project');
      expect(reloaded, isNotNull);
      expect(reloaded!.watermarkPosition, 'bottomLeft');
      expect(reloaded.watermarkOpacity, 0.78);
      expect(reloaded.watermarkAccentColorArgb, 0xff37c58b);
    },
  );

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
      watermarkLocaleCode: 'zh',
      createdAt: DateTime(2026, 7, 16, 9, 30),
    );

    expect(pending.status, CaptureStatus.pendingCamera);
    expect(pending.photoNumber, isNull);

    final captured = await database.markCaptured(
      captureId: pending.id,
      capturedAt: DateTime(2026, 7, 16, 9, 32),
    );

    expect(captured.status, CaptureStatus.captured);
    expect(captured.photoNumber, '车间改造-SM-20260716-001');
  });

  test('allocates one daily sequence across different projects', () async {
    await database.createProject(id: 'project-a', name: '东区');
    await database.createProject(id: 'project-b', name: '西区');

    Future<CaptureRecord> capture(String id, String projectId) async {
      final pending = await database.createPendingCapture(
        id: id,
        projectId: projectId,
        originalPath: '/private/$id.jpg',
        workLocation: '现场',
        workContent: '检查',
        photographer: '张工',
        watermarkLocaleCode: 'zh',
        createdAt: DateTime(2026, 7, 16, 9),
      );
      return database.markCaptured(
        captureId: pending.id,
        capturedAt: DateTime(2026, 7, 16, 9),
      );
    }

    final first = await capture('capture-a', 'project-a');
    final second = await capture('capture-b', 'project-b');

    expect(first.photoNumber, '东区-SM-20260716-001');
    expect(second.photoNumber, '西区-SM-20260716-002');
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
          watermarkLocaleCode: 'zh',
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
        watermarkLocaleCode: 'zh',
        createdAt: DateTime(2026, 7, 16, 10),
      );
      final captured = await database.markCaptured(
        captureId: third.id,
        capturedAt: DateTime(2026, 7, 16, 10, 1),
      );

      expect(captured.photoNumber, '车间改造-SM-20260716-003');
    },
  );

  test('markCaptured keeps an already assigned photo number', () async {
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
      watermarkLocaleCode: 'zh',
      createdAt: DateTime(2026, 7, 16, 9, 30),
    );
    final first = await database.markCaptured(
      captureId: pending.id,
      capturedAt: DateTime(2026, 7, 16, 9, 32),
    );
    expect(first.photoNumber, '车间改造-SM-20260716-001');

    final other = await database.createPendingCapture(
      id: 'capture-2',
      projectId: 'project',
      originalPath: '/private/capture-2.jpg',
      workLocation: 'B 区',
      workContent: '保温检查',
      photographer: '李工',
      watermarkLocaleCode: 'zh',
      createdAt: DateTime(2026, 7, 16, 9, 40),
    );
    await database.markCaptured(
      captureId: other.id,
      capturedAt: DateTime(2026, 7, 16, 9, 41),
    );

    final again = await database.markCaptured(
      captureId: pending.id,
      capturedAt: DateTime(2026, 7, 16, 9, 45),
    );

    expect(again.photoNumber, '车间改造-SM-20260716-001');
    expect(again.status, CaptureStatus.captured);
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
        watermarkLocaleCode: 'zh',
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

  test(
    'watches selected capture summaries through rendering completion',
    () async {
      await database.createProject(id: 'project', name: '车间改造');
      final pending = await database.createPendingCapture(
        id: 'capture-1',
        projectId: 'project',
        originalPath: '/private/capture-1.jpg',
        workLocation: 'A 区',
        workContent: '风管安装',
        photographer: '张工',
        watermarkLocaleCode: 'zh',
      );
      await database.markCaptured(
        captureId: pending.id,
        capturedAt: DateTime(2026, 7, 16, 9, 32),
      );
      await database.markRendering(
        captureId: pending.id,
        originalSha256: originalHash,
      );

      final updates = StreamIterator(
        database.watchCaptureSummariesByIds({'capture-1'}),
      );
      addTearDown(updates.cancel);
      expect(await updates.moveNext(), isTrue);
      expect(updates.current.single.capture.status, CaptureStatus.rendering);

      await database.markReady(
        captureId: pending.id,
        publishedUri: 'content://media/photo/1',
      );

      expect(await updates.moveNext(), isTrue);
      expect(updates.current.single.capture.status, CaptureStatus.ready);
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
      watermarkLocaleCode: 'zh',
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
      watermarkLocaleCode: 'zh',
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
    expect(edited.photoNumber, '车间改造-SM-20260716-001');
  });

  test(
    'inserts default app settings on first open and streams updates',
    () async {
      final settings = await database.watchAppSettings().first;

      expect(settings.themeMode, 'system');
      expect(settings.localeCode, isNull);
      expect(settings.defaultWatermarkPosition, 'bottomLeft');
      expect(settings.defaultWatermarkOpacity, 0.78);
      expect(settings.defaultWatermarkAccentColorArgb, 0xff37c58b);

      final updated = await database.updateAppSettings(
        themeMode: 'dark',
        defaultWatermarkOpacity: 0.6,
      );

      expect(updated.themeMode, 'dark');
      expect(updated.defaultWatermarkOpacity, 0.6);
      expect(updated.defaultWatermarkPosition, 'bottomLeft');

      final streamed = await database.watchAppSettings().first;
      expect(streamed.themeMode, 'dark');
      expect(streamed.defaultWatermarkOpacity, 0.6);
    },
  );

  test(
    'latestCapturedDraft ignores pending camera rows and clears notes',
    () async {
      await database.createProject(
        id: 'project-1',
        name: '东区厂房改造',
        createdAt: DateTime.utc(2026, 7, 16),
      );
      await database.createPendingCapture(
        id: 'pending',
        projectId: 'project-1',
        originalPath: '/private/pending.jpg',
        workLocation: 'X 区',
        workContent: '待拍摄',
        photographer: '王工',
        watermarkLocaleCode: 'zh',
        notes: '占位备注',
        createdAt: DateTime(2026, 7, 16, 12),
      );
      final captured = await database.createPendingCapture(
        id: 'capture-1',
        projectId: 'project-1',
        originalPath: '/private/capture-1.jpg',
        workLocation: 'A 区三层',
        workContent: '风管安装检查',
        photographer: '张工',
        watermarkLocaleCode: 'zh',
        notes: '临时备注',
        createdAt: DateTime(2026, 7, 16, 9, 30),
      );
      await database.markCaptured(
        captureId: captured.id,
        capturedAt: DateTime(2026, 7, 16, 9, 32),
      );

      final draft = await database.latestCapturedDraft('project-1');

      expect(draft?.workLocation, 'A 区三层');
      expect(draft?.workContent, '风管安装检查');
      expect(draft?.photographer, '张工');
      expect(draft?.notes, isNull);
    },
  );

  test(
    'latestCapturedDraft returns null when only pending camera rows exist',
    () async {
      await database.createProject(
        id: 'project-1',
        name: '东区厂房改造',
        createdAt: DateTime.utc(2026, 7, 16),
      );
      await database.createPendingCapture(
        id: 'pending',
        projectId: 'project-1',
        originalPath: '/private/pending.jpg',
        workLocation: 'A 区',
        workContent: '风管',
        photographer: '张工',
        watermarkLocaleCode: 'zh',
      );

      final draft = await database.latestCapturedDraft('project-1');

      expect(draft, isNull);
    },
  );

  test('watchCaptureById streams live detail reactions', () async {
    await database.createProject(
      id: 'project-1',
      name: '东区厂房改造',
      createdAt: DateTime.utc(2026, 7, 16),
    );
    final pending = await database.createPendingCapture(
      id: 'capture-1',
      projectId: 'project-1',
      originalPath: '/private/capture-1.jpg',
      workLocation: 'A 区',
      workContent: '风管',
      photographer: '张工',
      watermarkLocaleCode: 'zh',
      createdAt: DateTime(2026, 7, 16, 9, 30),
    );

    final first = await database.watchCaptureById(pending.id).first;
    expect(first?.status, CaptureStatus.pendingCamera);

    await database.markCaptured(
      captureId: pending.id,
      capturedAt: DateTime(2026, 7, 16, 9, 32),
    );

    final updated = await database.watchCaptureById(pending.id).first;
    expect(updated?.status, CaptureStatus.captured);
    expect(updated?.photoNumber, '东区厂房改造-SM-20260716-001');
  });

  test('watchCaptureById emits null for unknown id', () async {
    final value = await database.watchCaptureById('missing').first;
    expect(value, isNull);
  });

  test(
    'capture summary joins project name and excludes pending camera',
    () async {
      await database.createProject(
        id: 'project-1',
        name: '东区厂房改造',
        createdAt: DateTime.utc(2026, 7, 16),
      );
      await database.createPendingCapture(
        id: 'pending',
        projectId: 'project-1',
        originalPath: '/private/pending.jpg',
        workLocation: 'A 区',
        workContent: '风管',
        photographer: '张工',
        watermarkLocaleCode: 'zh',
        createdAt: DateTime(2026, 7, 16, 9, 30),
      );
      final captured = await database.createPendingCapture(
        id: 'capture-on-july-16',
        projectId: 'project-1',
        originalPath: '/private/capture-1.jpg',
        workLocation: 'A 区三层',
        workContent: '风管安装检查',
        photographer: '张工',
        watermarkLocaleCode: 'zh',
        createdAt: DateTime(2026, 7, 16, 9, 30),
      );
      await database.markCaptured(
        captureId: captured.id,
        capturedAt: DateTime(2026, 7, 16, 9, 32),
      );

      final rows = (await CaptureQueryRepository(
        database,
      ).loadPage(const CaptureListQuery())).rows;

      expect(rows.map((row) => row.capture.id), ['capture-on-july-16']);
      expect(rows.single.projectName, '东区厂房改造');
    },
  );

  test('capture summary filter uses local half-open date range', () async {
    await database.createProject(
      id: 'project-1',
      name: '东区厂房改造',
      createdAt: DateTime.utc(2026, 7, 16),
    );
    final july16 = await database.createPendingCapture(
      id: 'capture-on-july-16',
      projectId: 'project-1',
      originalPath: '/private/capture-1.jpg',
      workLocation: 'A 区三层',
      workContent: '风管安装检查',
      photographer: '张工',
      watermarkLocaleCode: 'zh',
      createdAt: DateTime(2026, 7, 16, 9, 30),
    );
    await database.markCaptured(
      captureId: july16.id,
      capturedAt: DateTime(2026, 7, 16, 9, 32),
    );
    final july15 = await database.createPendingCapture(
      id: 'capture-on-july-15',
      projectId: 'project-1',
      originalPath: '/private/capture-2.jpg',
      workLocation: 'B 区',
      workContent: '保温检查',
      photographer: '李工',
      watermarkLocaleCode: 'zh',
      createdAt: DateTime(2026, 7, 15, 9, 30),
    );
    await database.markCaptured(
      captureId: july15.id,
      capturedAt: DateTime(2026, 7, 15, 9, 32),
    );

    final rows = (await CaptureQueryRepository(database).loadPage(
      const CaptureListQuery(
        filter: CaptureFilter(year: 2026, month: 7, day: 16),
      ),
    )).rows;

    expect(rows.map((row) => row.capture.id), ['capture-on-july-16']);
  });

  test('capture summary respects project filter', () async {
    await database.createProject(
      id: 'project-1',
      name: '东区厂房改造',
      createdAt: DateTime.utc(2026, 7, 16),
    );
    await database.createProject(
      id: 'project-2',
      name: '西区宿舍',
      createdAt: DateTime.utc(2026, 7, 16),
    );
    final a = await database.createPendingCapture(
      id: 'capture-a',
      projectId: 'project-1',
      originalPath: '/private/a.jpg',
      workLocation: 'A 区',
      workContent: '风管',
      photographer: '张工',
      watermarkLocaleCode: 'zh',
      createdAt: DateTime(2026, 7, 16, 9, 30),
    );
    await database.markCaptured(
      captureId: a.id,
      capturedAt: DateTime(2026, 7, 16, 9, 32),
    );
    final b = await database.createPendingCapture(
      id: 'capture-b',
      projectId: 'project-2',
      originalPath: '/private/b.jpg',
      workLocation: 'B 区',
      workContent: '保温',
      photographer: '李工',
      watermarkLocaleCode: 'zh',
      createdAt: DateTime(2026, 7, 16, 10, 30),
    );
    await database.markCaptured(
      captureId: b.id,
      capturedAt: DateTime(2026, 7, 16, 10, 32),
    );

    final rows = (await CaptureQueryRepository(database).loadPage(
      const CaptureListQuery(filter: CaptureFilter(projectId: 'project-1')),
    )).rows;

    expect(rows.map((row) => row.capture.id), ['capture-a']);
  });

  test(
    'capture summary sorts by coalesce(capturedAt, createdAt) descending',
    () async {
      await database.createProject(
        id: 'project-1',
        name: '东区厂房改造',
        createdAt: DateTime.utc(2026, 7, 16),
      );
      final earlier = await database.createPendingCapture(
        id: 'capture-earlier',
        projectId: 'project-1',
        originalPath: '/private/earlier.jpg',
        workLocation: 'A 区',
        workContent: '风管',
        photographer: '张工',
        watermarkLocaleCode: 'zh',
        createdAt: DateTime(2026, 7, 16, 8, 0),
      );
      await database.markCaptured(
        captureId: earlier.id,
        capturedAt: DateTime(2026, 7, 16, 11, 0),
      );
      final later = await database.createPendingCapture(
        id: 'capture-later',
        projectId: 'project-1',
        originalPath: '/private/later.jpg',
        workLocation: 'B 区',
        workContent: '保温',
        photographer: '李工',
        watermarkLocaleCode: 'zh',
        createdAt: DateTime(2026, 7, 16, 9, 0),
      );
      await database.markCaptured(
        captureId: later.id,
        capturedAt: DateTime(2026, 7, 16, 9, 5),
      );

      final rows = (await CaptureQueryRepository(
        database,
      ).loadPage(const CaptureListQuery())).rows;

      expect(rows.map((row) => row.capture.id), [
        'capture-earlier',
        'capture-later',
      ]);
    },
  );

  test(
    'capture summary breaks equal sort timestamp ties by id descending',
    () async {
      await database.createProject(id: 'project-1', name: '东区厂房改造');
      final first = await database.createPendingCapture(
        id: 'capture-a',
        projectId: 'project-1',
        originalPath: '/private/a.jpg',
        workLocation: 'A 区',
        workContent: '风管',
        photographer: '张工',
        watermarkLocaleCode: 'zh',
      );
      final second = await database.createPendingCapture(
        id: 'capture-z',
        projectId: 'project-1',
        originalPath: '/private/z.jpg',
        workLocation: 'B 区',
        workContent: '保温',
        photographer: '李工',
        watermarkLocaleCode: 'zh',
      );
      final sameTimestamp = DateTime(2026, 7, 16, 9, 32);
      await database.markCaptured(
        captureId: first.id,
        capturedAt: sameTimestamp,
      );
      await database.markCaptured(
        captureId: second.id,
        capturedAt: sameTimestamp,
      );

      final rows = (await CaptureQueryRepository(
        database,
      ).loadPage(const CaptureListQuery())).rows;

      expect(rows.map((row) => row.capture.id), ['capture-z', 'capture-a']);
    },
  );

  test('unfiltered summary query returns joined capture data', () async {
    await database.createProject(
      id: 'project-1',
      name: '东区厂房改造',
      createdAt: DateTime.utc(2026, 7, 16),
    );
    final july16 = await database.createPendingCapture(
      id: 'capture-on-july-16',
      projectId: 'project-1',
      originalPath: '/private/capture-1.jpg',
      workLocation: 'A 区三层',
      workContent: '风管安装检查',
      photographer: '张工',
      watermarkLocaleCode: 'zh',
      createdAt: DateTime(2026, 7, 16, 9, 30),
    );
    await database.markCaptured(
      captureId: july16.id,
      capturedAt: DateTime(2026, 7, 16, 9, 32),
    );

    final rows = (await CaptureQueryRepository(
      database,
    ).loadPage(const CaptureListQuery())).rows;

    expect(rows.map((row) => row.capture.id), ['capture-on-july-16']);
    expect(rows.single.projectName, '东区厂房改造');
  });

  test(
    'capturesAwaitingProcessing returns captured and rendering rows',
    () async {
      await database.createProject(
        id: 'project-1',
        name: '东区厂房改造',
        createdAt: DateTime.utc(2026, 7, 16),
      );
      final pending = await database.createPendingCapture(
        id: 'pending',
        projectId: 'project-1',
        originalPath: '/private/pending.jpg',
        workLocation: 'A 区',
        workContent: '风管',
        photographer: '张工',
        watermarkLocaleCode: 'zh',
        createdAt: DateTime(2026, 7, 16, 9, 30),
      );
      final captured = await database.createPendingCapture(
        id: 'captured',
        projectId: 'project-1',
        originalPath: '/private/captured.jpg',
        workLocation: 'B 区',
        workContent: '保温',
        photographer: '李工',
        watermarkLocaleCode: 'zh',
        createdAt: DateTime(2026, 7, 16, 10, 0),
      );
      await database.markCaptured(
        captureId: captured.id,
        capturedAt: DateTime(2026, 7, 16, 10, 1),
      );
      await database.resolveCaptureLocation(
        captureId: captured.id,
        resolution: 'resolved',
        outcome: 'exif',
        latitude: 24.5,
        longitude: 117.6,
      );
      final rendering = await database.createPendingCapture(
        id: 'rendering',
        projectId: 'project-1',
        originalPath: '/private/rendering.jpg',
        workLocation: 'C 区',
        workContent: '验收',
        photographer: '王工',
        watermarkLocaleCode: 'zh',
        createdAt: DateTime(2026, 7, 16, 11, 0),
      );
      await database.markCaptured(
        captureId: rendering.id,
        capturedAt: DateTime(2026, 7, 16, 11, 1),
      );
      await database.markRendering(
        captureId: rendering.id,
        originalSha256: originalHash,
      );
      await database.resolveCaptureLocation(
        captureId: rendering.id,
        resolution: 'resolved',
        outcome: 'exif',
        latitude: 24.5,
        longitude: 117.6,
      );

      final awaiting = await database.capturesAwaitingProcessing();

      expect(awaiting.map((row) => row.id), {'captured', 'rendering'});
      expect(awaiting.any((row) => row.id == pending.id), isFalse);
    },
  );

  test('incrementProcessingAttempts bumps the retry counter', () async {
    await database.createProject(
      id: 'project-1',
      name: '东区厂房改造',
      createdAt: DateTime.utc(2026, 7, 16),
    );
    final pending = await database.createPendingCapture(
      id: 'capture-1',
      projectId: 'project-1',
      originalPath: '/private/capture-1.jpg',
      workLocation: 'A 区',
      workContent: '风管',
      photographer: '张工',
      watermarkLocaleCode: 'zh',
      createdAt: DateTime(2026, 7, 16, 9, 30),
    );
    await database.markCaptured(
      captureId: pending.id,
      capturedAt: DateTime(2026, 7, 16, 9, 32),
    );

    final first = await database.incrementProcessingAttempts(pending.id);
    expect(first.processingAttempts, 1);

    final second = await database.incrementProcessingAttempts(pending.id);
    expect(second.processingAttempts, 2);
  });

  test('resetCaptureForRetry preserves evidence and resets attempts', () async {
    await database.createProject(
      id: 'project-1',
      name: '东区厂房改造',
      createdAt: DateTime.utc(2026, 7, 16),
    );
    final pending = await database.createPendingCapture(
      id: 'capture-1',
      projectId: 'project-1',
      originalPath: '/private/capture-1.jpg',
      workLocation: 'A 区',
      workContent: '风管',
      photographer: '张工',
      watermarkLocaleCode: 'zh',
      createdAt: DateTime(2026, 7, 16, 9, 30),
    );
    await database.markCaptured(
      captureId: pending.id,
      capturedAt: DateTime(2026, 7, 16, 9, 32),
    );
    await database.markRendering(
      captureId: pending.id,
      originalSha256: originalHash,
    );
    await database.markReady(
      captureId: pending.id,
      publishedUri: 'content://media/site-mark/1',
    );
    await database.incrementProcessingAttempts(pending.id);

    final reset = await database.resetCaptureForRetry(pending.id);

    expect(reset.status, CaptureStatus.captured);
    expect(reset.failureReason, isNull);
    expect(reset.originalSha256, originalHash);
    expect(reset.publishedUri, 'content://media/site-mark/1');
    expect(reset.processingAttempts, 0);
  });

  test(
    'CaptureFilter enforces parent-child date invariant at construction',
    () {
      expect(() => CaptureFilter(month: 7), throwsA(isA<AssertionError>()));
      expect(() => CaptureFilter(day: 16), throwsA(isA<AssertionError>()));
    },
  );

  test('CaptureFilter localRange returns half-open date bounds', () {
    const yearOnly = CaptureFilter(year: 2026);
    expect(yearOnly.localRange, isNotNull);
    expect(yearOnly.localRange!.start, DateTime(2026, 1, 1));
    expect(yearOnly.localRange!.end, DateTime(2027, 1, 1));

    const monthOnly = CaptureFilter(year: 2026, month: 7);
    expect(monthOnly.localRange!.start, DateTime(2026, 7, 1));
    expect(monthOnly.localRange!.end, DateTime(2026, 8, 1));

    const dayOnly = CaptureFilter(year: 2026, month: 7, day: 16);
    expect(dayOnly.localRange!.start, DateTime(2026, 7, 16));
    expect(dayOnly.localRange!.end, DateTime(2026, 7, 17));
  });

  test('updateCaptureDescription preserves processingAttempts', () async {
    await database.createProject(
      id: 'project-1',
      name: '东区厂房改造',
      createdAt: DateTime.utc(2026, 7, 16),
    );
    final pending = await database.createPendingCapture(
      id: 'capture-1',
      projectId: 'project-1',
      originalPath: '/private/capture-1.jpg',
      workLocation: 'A 区',
      workContent: '风管',
      photographer: '张工',
      watermarkLocaleCode: 'zh',
      createdAt: DateTime(2026, 7, 16, 9, 30),
    );
    await database.markCaptured(
      captureId: pending.id,
      capturedAt: DateTime(2026, 7, 16, 9, 32),
    );
    await database.incrementProcessingAttempts(pending.id);

    final edited = await database.updateCaptureDescription(
      captureId: pending.id,
      workLocation: 'B 区',
      workContent: '保温',
      photographer: '李工',
    );

    expect(edited.processingAttempts, 1);
  });
  test('persists constrained project and default font scales', () async {
    final project = await database.createProject(
      id: 'project',
      name: '车间改造',
      watermarkFontScale: 1.25,
    );
    expect(project.watermarkFontScale, 1.25);

    final updated = await database.updateProjectWatermarkSettings(
      projectId: 'project',
      position: 'bottomLeft',
      opacity: 0.78,
      accentColorArgb: 0xff37c58b,
      fontScale: 1.60,
    );
    expect(updated.watermarkFontScale, 1.60);
    expect(
      () => database.updateProjectWatermarkSettings(
        projectId: 'project',
        position: 'bottomLeft',
        opacity: 0.78,
        accentColorArgb: 0xff37c58b,
        fontScale: 1.61,
      ),
      throwsArgumentError,
    );

    final settings = await database.updateAppSettings(
      defaultWatermarkFontScale: 0.80,
      locationPermissionPromptDismissed: true,
    );
    expect(settings.defaultWatermarkFontScale, 0.80);
    expect(settings.locationPermissionPromptDismissed, isTrue);
  });

  test(
    'resolves location and distinguishes intentional original cleanup',
    () async {
      await database.createProject(id: 'project', name: '车间改造');
      final pending = await database.createPendingCapture(
        id: 'capture-1',
        projectId: 'project',
        originalPath: '/private/capture-1.jpg',
        workLocation: 'A 区',
        workContent: '风管',
        photographer: '张工',
        watermarkLocaleCode: 'en',
      );
      expect(pending.watermarkLocaleCode, 'en');
      expect(pending.locationResolution, 'pending');

      final located = await database.resolveCaptureLocation(
        captureId: pending.id,
        resolution: 'resolved',
        outcome: 'precise',
        latitude: 24.513,
        longitude: 117.6471,
        accuracyMeters: 8,
      );
      expect(located.locationResolution, 'resolved');
      expect(located.latitude, 24.513);

      final deletedAt = DateTime(2026, 7, 16, 12);
      final cleaned = await database.markOriginalDeleted(
        pending.id,
        deletedAt: deletedAt,
      );
      expect(cleaned.originalDeletedAt, deletedAt);
      expect(cleaned.originalSha256, pending.originalSha256);

      final rows = await database.capturesByIds(['capture-1', 'missing']);
      expect(rows.map((row) => row.id), ['capture-1']);
    },
  );

  group('setPollingPaused', () {
    test('is safe to call repeatedly with the same or alternating value', () {
      database.setPollingPaused(true);
      database.setPollingPaused(true);
      database.setPollingPaused(false);
      database.setPollingPaused(false);
      database.setPollingPaused(true);
      database.setPollingPaused(false);
    });

    test('does not prevent drift watch from emitting on writes', () async {
      await database.createProject(id: 'p1', name: 'Project 1');
      database.setPollingPaused(true);

      final stream = database.watchCaptureSummariesByIds({'c1'});
      final emissions = <List<dynamic>>[];
      final subscription = stream.listen(emissions.add);

      // Wait for the initial drift watch() emission.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions.length, greaterThanOrEqualTo(1));
      expect(emissions.first, isEmpty);

      // Insert and capture a record so it appears in the summary (which
      // excludes pendingCamera rows). The drift watch() should still fire
      // even while polling is paused — the SQLite update hook is independent
      // of the conditional-polling fallback.
      final pending = await database.createPendingCapture(
        id: 'c1',
        projectId: 'p1',
        originalPath: '/test/c1.jpg',
        workLocation: 'Site A',
        workContent: 'Foundation',
        photographer: 'Alice',
        watermarkLocaleCode: 'zh',
        createdAt: DateTime(2026, 7, 15),
      );
      await database.markCaptured(
        captureId: pending.id,
        capturedAt: DateTime(2026, 7, 15, 10),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(emissions.length, greaterThan(1));
      expect(emissions.last.length, 1);

      await subscription.cancel();
    });
  });

  test('blocks pending captures on completed projects', () async {
    await database.createProject(id: 'done', name: '已完成');
    final completed = await database.updateProjectLifecycleStatus(
      projectId: 'done',
      expectedStatus: ProjectLifecycleStatus.active,
      targetStatus: ProjectLifecycleStatus.completed,
    );
    expect(completed!.lifecycleStatus, ProjectLifecycleStatus.completed);

    await expectLater(
      () => database.createPendingCapture(
        id: 'blocked',
        projectId: 'done',
        originalPath: '/private/blocked.jpg',
        workLocation: 'A 区',
        workContent: '检查',
        photographer: '张工',
        watermarkLocaleCode: 'zh',
      ),
      throwsA(
        isA<ProjectReadOnlyException>()
            .having((error) => error.projectId, 'projectId', 'done')
            .having(
              (error) => error.status,
              'status',
              ProjectLifecycleStatus.completed,
            ),
      ),
    );

    expect(
      await database.updateProjectLifecycleStatus(
        projectId: 'done',
        expectedStatus: ProjectLifecycleStatus.active,
        targetStatus: ProjectLifecycleStatus.archived,
      ),
      isNull,
    );
    expect(
      (await database.projectById('done'))!.lifecycleStatus,
      ProjectLifecycleStatus.completed,
    );
  });

  test('watchProjectById emits lifecycle updates', () async {
    await database.createProject(id: 'watched', name: '监听项目');
    final updates = StreamIterator(database.watchProjectById('watched'));
    addTearDown(updates.cancel);

    expect(await updates.moveNext(), isTrue);
    expect(updates.current!.lifecycleStatus, ProjectLifecycleStatus.active);

    await database.updateProjectLifecycleStatus(
      projectId: 'watched',
      expectedStatus: ProjectLifecycleStatus.active,
      targetStatus: ProjectLifecycleStatus.archived,
    );
    expect(await updates.moveNext(), isTrue);
    expect(updates.current!.lifecycleStatus, ProjectLifecycleStatus.archived);
  });

  test('unknown capture status values fall back to failed', () {
    const converter = CaptureStatusConverter();
    expect(converter.fromSql('ready'), CaptureStatus.ready);
    expect(converter.fromSql('unknown-future-status'), CaptureStatus.failed);
    expect(converter.toSql(CaptureStatus.failed), 'failed');
  });
}
