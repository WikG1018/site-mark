import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/workflow/project_backup_preflight.dart';

void main() {
  late AppDatabase database;
  late ProjectBackupPreflightService service;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    service = ProjectBackupPreflightService(database);
  });

  tearDown(() => database.close());

  test('classifies an empty project without treating it as an error', () async {
    await database.createProject(id: 'empty', name: '空白项目');

    final result = await service.inspect(const ['empty']);

    expect(result.projects.single.disposition, ProjectBackupDisposition.empty);
    expect(result.projects.single.readyCount, 0);
    expect(result.projects.single.processingCount, 0);
    expect(result.projects.single.failedCount, 0);
  });

  test('classifies processing and failed records and aggregates counts',
      () async {
    await database.createProject(id: 'mixed', name: '混合项目');
    await database.createPendingCapture(
      id: 'processing',
      projectId: 'mixed',
      originalPath: '/processing.jpg',
      workLocation: 'A区',
      workContent: '检查',
      photographer: '张工',
      watermarkLocaleCode: 'zh',
    );
    final failed = await database.createPendingCapture(
      id: 'failed',
      projectId: 'mixed',
      originalPath: '/failed.jpg',
      workLocation: 'A区',
      workContent: '检查',
      photographer: '张工',
      watermarkLocaleCode: 'zh',
    );
    await database.markFailed(captureId: failed.id, reason: 'failure');

    final result = await service.inspect(const ['mixed']);

    expect(result.projects.single.disposition, ProjectBackupDisposition.failed);
    expect(result.projects.single.processingCount, 1);
    expect(result.projects.single.failedCount, 1);
    expect(result.processingCount, 1);
    expect(result.failedCount, 1);
  });

  test('rejects duplicate selections and represents a missing project',
      () async {
    expect(
      () => service.inspect(const ['a', 'a']),
      throwsA(isA<ArgumentError>()),
    );

    final result = await service.inspect(const ['missing']);
    expect(result.projects.single.disposition, ProjectBackupDisposition.missing);
  });
}
