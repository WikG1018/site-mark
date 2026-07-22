import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/features/capture/capture_record_card.dart';
import 'package:sitemark/main.dart';
import 'package:sitemark/platform/platform_services.dart';

const _runProfileScenario = bool.fromEnvironment('SITEMARK_PROFILE_TEST');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('profiles a 1000-record field workflow', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await _seedRecords(database);

    await binding.watchPerformance(() async {
      await tester.pumpWidget(
        MyApp(
          database: database,
          initialLocale: const Locale('zh'),
          outputPaths: const _PerformanceOutputPaths(),
          privateFileStore: const _MissingFileStore(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('全部记录'));
      await tester.pumpAndSettle();
      expect(find.byType(CaptureRecordCard), findsWidgets);

      await tester.fling(find.byType(ListView), const Offset(0, -1800), 3000);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('filter-year')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('edit-captures')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('select-all-captures')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('select-all-captures')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit-captures')));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(CaptureRecordCard).first);
      await tester.pumpAndSettle();
      expect(find.text('记录详情'), findsOneWidget);
    }, reportKey: 'records_1000_field_workflow');
  }, skip: !_runProfileScenario);
}

Future<void> _seedRecords(AppDatabase database) async {
  const projectId = 'performance-project';
  final capturedAt = DateTime(2026, 7, 19, 8);
  await database.createProject(id: projectId, name: '性能测试工程');
  await database.batch((batch) {
    for (var index = 0; index < 1000; index++) {
      final sequence = (index + 1).toString().padLeft(3, '0');
      batch.insert(
        database.captureRecords,
        CaptureRecordsCompanion.insert(
          id: 'performance-${index.toString().padLeft(4, '0')}',
          projectId: projectId,
          photoNumber: Value('性能测试工程-SM-20260719-$sequence'),
          workLocation: '施工区 ${(index % 20) + 1}',
          workContent: '安装质量检查',
          photographer: '测试员',
          originalPath: '/private/performance-$index.jpg',
          status: CaptureStatus.ready,
          createdAt: capturedAt.add(Duration(seconds: index)),
          capturedAt: Value(capturedAt.add(Duration(seconds: index))),
        ),
      );
    }
  });
}

class _PerformanceOutputPaths implements CaptureOutputPaths {
  const _PerformanceOutputPaths();

  @override
  Future<String> renderedPhotoPath(String captureId) async =>
      '/private/rendered/$captureId.jpg';
}

class _MissingFileStore implements PrivateFileStore {
  const _MissingFileStore();

  @override
  Future<void> deleteIfExists(String path) async {}

  @override
  Future<bool> exists(String path) async => false;
}
