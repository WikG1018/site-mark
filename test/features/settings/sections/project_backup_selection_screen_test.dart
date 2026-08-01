import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/features/settings/sections/project_backup_selection_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/workflow/project_bundle_service.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.createProject(id: 'p1', name: '一号项目');
    await database.createProject(id: 'p2', name: '二号项目');
    await database.createProject(id: 'p3', name: '三号项目');
  });

  tearDown(() => database.close());

  Future<void> pumpScreen(
    WidgetTester tester, {
    ProjectBackupExport? exportProjects,
    Future<ArchiveSaveOutcome> Function(String path)? saveArchive,
    Future<void> Function(String path)? shareFile,
    Set<String> initialProjectIds = const {},
  }) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: ProjectBackupSelectionScreen(
            exportProjects: exportProjects,
            saveArchive: saveArchive,
            shareFile: shareFile,
            initialProjectIds: initialProjectIds,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> disposeScreen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('select all toggles all projects and then clears selection', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('已选择 0 个项目'), findsOneWidget);
    await tester.tap(find.byKey(const Key('select-all-projects')));
    await tester.pump();
    expect(find.text('已选择 3 个项目'), findsOneWidget);

    await tester.tap(find.byKey(const Key('select-all-projects')));
    await tester.pump();
    expect(find.text('已选择 0 个项目'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeScreen(tester);
  });

  testWidgets('continue is disabled until at least one project is selected', (
    tester,
  ) async {
    await pumpScreen(tester);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '继续'),
    );
    expect(button.onPressed, isNull);
    await disposeScreen(tester);
  });

  testWidgets('preselects a project opened from project details', (
    tester,
  ) async {
    await pumpScreen(tester, initialProjectIds: const {'p2'});

    expect(find.text('已选择 1 个项目'), findsOneWidget);
    final tile = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, '二号项目'),
    );
    expect(tile.value, isTrue);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('backup-continue')))
          .onPressed,
      isNotNull,
    );
    await disposeScreen(tester);
  });

  testWidgets('confirms originals, reports progress, and saves the ZIP', (
    tester,
  ) async {
    final exportCompleter = Completer<ProjectBackupResult>();
    List<String>? exportedIds;
    bool? includedOriginals;
    String? savedPath;
    void Function(int completed, int total)? reportProgress;
    await pumpScreen(
      tester,
      exportProjects:
          ({
            required projectIds,
            required includeOriginals,
            onProgress,
            allowFailedOmissions = false,
          }) {
            exportedIds = projectIds;
            includedOriginals = includeOriginals;
            reportProgress = onProgress;
            return exportCompleter.future;
          },
      saveArchive: (path) async {
        savedPath = path;
        return ArchiveSaveOutcome.saved;
      },
    );

    await tester.tap(find.byKey(const Key('select-all-projects')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('backup-continue')));
    await tester.pumpAndSettle();
    expect(find.text('包含私有原图'), findsWidgets);
    expect(find.textContaining('备份文件会更大'), findsOneWidget);

    await tester.tap(find.byKey(const Key('include-private-originals')));
    await tester.pump();
    expect(find.text('正在备份 0/4'), findsOneWidget);
    expect(exportedIds, hasLength(3));
    expect(includedOriginals, isTrue);

    reportProgress!(1, 4);
    await tester.pump();
    expect(find.text('正在备份 1/4'), findsOneWidget);

    exportCompleter.complete(
      const ProjectBackupResult(
        kind: ProjectBackupKind.bundle,
        outputZipPath: '/tmp/projects.zip',
        projectCount: 3,
      ),
    );
    await tester.pumpAndSettle();
    expect(savedPath, '/tmp/projects.zip');
    expect(find.text('备份已保存'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeScreen(tester);
  });

  testWidgets('cancelled save is not success and keeps save/share actions', (
    tester,
  ) async {
    var saveCalls = 0;
    String? sharedPath;
    await pumpScreen(
      tester,
      exportProjects:
          ({
            required projectIds,
            required includeOriginals,
            onProgress,
            allowFailedOmissions = false,
          }) async => const ProjectBackupResult(
            kind: ProjectBackupKind.bundle,
            outputZipPath: '/tmp/projects.zip',
            projectCount: 3,
          ),
      saveArchive: (path) async {
        saveCalls += 1;
        return ArchiveSaveOutcome.cancelled;
      },
      shareFile: (path) async => sharedPath = path,
    );

    await tester.tap(find.byKey(const Key('select-all-projects')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('backup-continue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exclude-private-originals')));
    await tester.pumpAndSettle();

    expect(saveCalls, 1);
    expect(find.text('备份文件已生成，但尚未保存到所选位置'), findsOneWidget);
    expect(find.byKey(const Key('backup-save-again')), findsOneWidget);
    expect(find.byKey(const Key('backup-share')), findsOneWidget);

    await tester.tap(find.byKey(const Key('backup-save-again')));
    await tester.pumpAndSettle();
    expect(saveCalls, 2);

    await tester.tap(find.byKey(const Key('backup-share')));
    await tester.pumpAndSettle();
    expect(sharedPath, '/tmp/projects.zip');
    await disposeScreen(tester);
  });
}
