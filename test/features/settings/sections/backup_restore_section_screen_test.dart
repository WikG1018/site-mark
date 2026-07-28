import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/features/projects/project_restore_flow.dart';
import 'package:sitemark/features/settings/sections/backup_restore_section_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/src/rust/api/image_core.dart' as rust;
import 'package:sitemark/workflow/project_bundle_service.dart';
import 'package:sitemark/workflow/project_import_service.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  Future<void> pumpScreen(
    WidgetTester tester, {
    ProjectRestoreFlowDependencies? dependencies,
    Locale locale = const Locale('zh'),
  }) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          locale: locale,
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: BackupRestoreSectionScreen(restoreDependencies: dependencies),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows separate backup and restore actions at 360dp', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(find.byKey(const Key('backup-projects')), findsOneWidget);
    expect(find.byKey(const Key('restore-projects')), findsOneWidget);
    expect(find.textContaining('ZIP'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows complete English backup and restore labels', (
    tester,
  ) async {
    await pumpScreen(tester, locale: const Locale('en'));
    expect(find.text('Backup & restore'), findsOneWidget);
    expect(find.text('Back up projects'), findsOneWidget);
    expect(find.text('Restore projects'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('explains restore before picker and restores edited preview', (
    tester,
  ) async {
    var pickerCalls = 0;
    var restoreCalls = 0;
    var discardCalls = 0;
    Map<String, String>? restoredNames;
    final prepared = _prepared();
    final dependencies = ProjectRestoreFlowDependencies(
      pickZip: () async {
        pickerCalls++;
        return '/tmp/backup.zip';
      },
      prepareRestore: (_) async => prepared,
      restorePrepared:
          ({required prepared, required projectNames, onProgress}) async {
            restoreCalls++;
            restoredNames = projectNames;
            onProgress?.call(1, 1);
            return const [
              ProjectImportResult(
                projectId: 'target',
                projectName: '恢复后的项目',
                photoCount: 1,
                restoredOriginals: 1,
              ),
            ];
          },
      discardPrepared: (_) async => discardCalls++,
    );
    await pumpScreen(tester, dependencies: dependencies);

    await tester.tap(find.byKey(const Key('restore-projects')));
    await tester.pumpAndSettle();
    expect(find.textContaining('SiteMark 导出的'), findsWidgets);
    expect(pickerCalls, 0);

    await tester.tap(find.byKey(const Key('choose-restore-zip')));
    await tester.pumpAndSettle();
    expect(pickerCalls, 1);
    expect(find.text('源项目'), findsWidgets);
    expect(find.text('1 张照片'), findsOneWidget);
    expect(find.textContaining('全部回滚'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('restore-name-source')),
      '恢复后的项目',
    );
    await tester.tap(find.byKey(const Key('restore-confirm')));
    await tester.pumpAndSettle();

    expect(restoreCalls, 1);
    expect(restoredNames, {'source': '恢复后的项目'});
    expect(discardCalls, 0);
    expect(find.textContaining('恢复完成'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('canceling prepared preview discards temporary files once', (
    tester,
  ) async {
    var discardCalls = 0;
    final prepared = _prepared();
    await pumpScreen(
      tester,
      dependencies: ProjectRestoreFlowDependencies(
        pickZip: () async => '/tmp/backup.zip',
        prepareRestore: (_) async => prepared,
        restorePrepared:
            ({required prepared, required projectNames, onProgress}) async =>
                const [],
        discardPrepared: (_) async => discardCalls++,
      ),
    );

    await tester.tap(find.byKey(const Key('restore-projects')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('choose-restore-zip')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(discardCalls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(discardCalls, 1);
  });

  testWidgets('system back cancels preview and discards exactly once', (
    tester,
  ) async {
    var discardCalls = 0;
    final prepared = _prepared();
    await pumpScreen(
      tester,
      dependencies: ProjectRestoreFlowDependencies(
        pickZip: () async => '/tmp/backup.zip',
        prepareRestore: (_) async => prepared,
        restorePrepared:
            ({required prepared, required projectNames, onProgress}) async =>
                const [],
        discardPrepared: (_) async => discardCalls++,
      ),
    );

    await tester.tap(find.byKey(const Key('restore-projects')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('choose-restore-zip')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('restore-confirm')), findsNothing);
    expect(discardCalls, 1);
  });

  testWidgets('disposing the screen during preview discards exactly once', (
    tester,
  ) async {
    var discardCalls = 0;
    final prepared = _prepared();
    await pumpScreen(
      tester,
      dependencies: ProjectRestoreFlowDependencies(
        pickZip: () async => '/tmp/backup.zip',
        prepareRestore: (_) async => prepared,
        restorePrepared:
            ({required prepared, required projectNames, onProgress}) async =>
                const [],
        discardPrepared: (_) async => discardCalls++,
      ),
    );

    await tester.tap(find.byKey(const Key('restore-projects')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('choose-restore-zip')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));

    expect(discardCalls, 1);
  });

  testWidgets('invalid archives use friendly copy without raw exceptions', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      dependencies: ProjectRestoreFlowDependencies(
        pickZip: () async => '/tmp/not-a-backup.zip',
        prepareRestore: (_) async => throw const ProjectBundleRestoreException(
          'raw internal parser failure',
        ),
        restorePrepared:
            ({required prepared, required projectNames, onProgress}) async =>
                const [],
        discardPrepared: (_) async {},
      ),
    );
    await tester.tap(find.byKey(const Key('restore-projects')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('choose-restore-zip')));
    await tester.pumpAndSettle();

    expect(find.text('不是有效的 SiteMark 备份'), findsOneWidget);
    expect(find.textContaining('raw internal'), findsNothing);
  });
}

PreparedProjectRestore _prepared() {
  return const PreparedProjectRestore(
    sourceZipPath: '/tmp/backup.zip',
    items: [
      PreparedProjectRestoreItem(
        sourceProjectId: 'source',
        targetProjectId: 'target',
        archivePath: '/tmp/backup.zip',
        preview: rust.ProjectArchivePreview(
          schemaVersion: 2,
          projectName: '源项目',
          includesOriginals: true,
          photos: [
            rust.ArchivePhotoPreview(
              photoNumber: '001',
              hasOriginal: true,
              originalSha256: 'abc',
              capturedAt: '2026-07-28T00:00:00Z',
              workLocation: '一层',
              workContent: '巡检',
              photographer: '测试',
            ),
          ],
        ),
      ),
    ],
  );
}
