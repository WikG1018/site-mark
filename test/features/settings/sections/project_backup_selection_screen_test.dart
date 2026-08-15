import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/project_lifecycle.dart';
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
    await database.updateProjectLifecycleStatus(
      projectId: 'p2',
      expectedStatus: ProjectLifecycleStatus.active,
      targetStatus: ProjectLifecycleStatus.completed,
    );
    await database.updateProjectLifecycleStatus(
      projectId: 'p3',
      expectedStatus: ProjectLifecycleStatus.active,
      targetStatus: ProjectLifecycleStatus.archived,
    );
  });

  tearDown(() => database.close());

  Future<void> pumpScreen(
    WidgetTester tester, {
    ProjectBackupExport? exportProjects,
    Future<ArchiveSaveOutcome> Function(String path)? saveArchive,
    Future<void> Function(String path)? shareFile,
    Set<String> initialProjectIds = const {},
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

  testWidgets('lists projects in every lifecycle status with status labels', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('一号项目'), findsOneWidget);
    expect(find.text('二号项目'), findsOneWidget);
    expect(find.text('三号项目'), findsOneWidget);
    expect(find.byKey(const Key('backup-status-active')), findsOneWidget);
    expect(find.byKey(const Key('backup-status-completed')), findsOneWidget);
    expect(find.byKey(const Key('backup-status-archived')), findsOneWidget);
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
    expect(find.text('备份已分享'), findsOneWidget);
    await disposeScreen(tester);
  });

  testWidgets('project export failure names only the failed project safely', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      initialProjectIds: const {'p2'},
      exportProjects:
          ({
            required projectIds,
            required includeOriginals,
            onProgress,
            allowFailedOmissions = false,
          }) async => throw ProjectBackupExportException(
            projectId: 'p2',
            projectName: '二号项目',
            cause: FileSystemException(
              'private-template-value',
              r'C:\private\database\sitemark.sqlite',
            ),
          ),
    );

    await tester.tap(find.byKey(const Key('backup-continue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exclude-private-originals')));
    await tester.pumpAndSettle();

    expect(find.text('无法备份项目“二号项目”。请重试；若仍失败，请单独选择该项目备份。'), findsOneWidget);
    expect(find.textContaining('private-template-value'), findsNothing);
    expect(find.textContaining(r'C:\private\database'), findsNothing);
    await disposeScreen(tester);
  });

  for (final wrapped in [false, true]) {
    testWidgets(
      '${wrapped ? 'wrapped project' : 'direct'} ENOSPC uses the storage message safely',
      (tester) async {
        final storageError = FileSystemException(
          'private-template-value',
          r'C:\private\database\sitemark.sqlite',
          const OSError('No space left on device', 28),
        );
        await pumpScreen(
          tester,
          initialProjectIds: const {'p2'},
          exportProjects:
              ({
                required projectIds,
                required includeOriginals,
                onProgress,
                allowFailedOmissions = false,
              }) async => throw wrapped
                  ? ProjectBackupExportException(
                      projectId: 'p2',
                      projectName: '二号项目',
                      cause: storageError,
                    )
                  : storageError,
        );

        await tester.tap(find.byKey(const Key('backup-continue')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('exclude-private-originals')));
        await tester.pumpAndSettle();

        expect(find.text('存储空间不足，无法完成操作。请释放空间后重试。'), findsOneWidget);
        expect(find.textContaining('请单独选择'), findsNothing);
        expect(find.textContaining('private-template-value'), findsNothing);
        expect(find.textContaining(r'C:\private\database'), findsNothing);
        await disposeScreen(tester);
      },
    );
  }

  testWidgets('shows a bilingual empty-project backup hint', (tester) async {
    await pumpScreen(tester, locale: const Locale('en'));
    final strings = AppStrings(const Locale('en'));
    expect(find.text(strings.backupEmptyProjectHint), findsOneWidget);
    expect(find.textContaining('空白项目也可以备份'), findsNothing);
    await disposeScreen(tester);
  });

  testWidgets('blocks backup while photos are still processing', (
    tester,
  ) async {
    await database.createPendingCapture(
      id: 'processing',
      projectId: 'p1',
      originalPath: '/processing.jpg',
      workLocation: 'A区',
      workContent: '检查',
      photographer: '张工',
      watermarkLocaleCode: 'zh',
    );
    await pumpScreen(
      tester,
      initialProjectIds: const {'p1'},
      locale: const Locale('en'),
    );
    final strings = AppStrings(const Locale('en'));

    await tester.tap(find.byKey(const Key('backup-continue')));
    await tester.pumpAndSettle();

    expect(find.text(strings.backupWaitForProcessingTitle), findsOneWidget);
    expect(
      find.text(strings.backupWaitForProcessingMessage(1)),
      findsOneWidget,
    );
    expect(find.textContaining('请等待照片处理完成'), findsNothing);
    await tester.tap(find.text(strings.gotIt));
    await tester.pumpAndSettle();
    expect(find.text(strings.includePrivateOriginals), findsNothing);
    await disposeScreen(tester);
  });

  testWidgets('asks before omitting failed records in English', (tester) async {
    final failed = await database.createPendingCapture(
      id: 'failed',
      projectId: 'p1',
      originalPath: '/failed.jpg',
      workLocation: 'A区',
      workContent: '检查',
      photographer: '张工',
      watermarkLocaleCode: 'zh',
    );
    await database.markFailed(captureId: failed.id, reason: 'failure');
    var exported = false;
    await pumpScreen(
      tester,
      initialProjectIds: const {'p1'},
      locale: const Locale('en'),
      exportProjects:
          ({
            required projectIds,
            required includeOriginals,
            onProgress,
            allowFailedOmissions = false,
          }) async {
            exported = true;
            return const ProjectBackupResult(
              kind: ProjectBackupKind.bundle,
              outputZipPath: '/tmp/projects.zip',
              projectCount: 1,
            );
          },
    );
    final strings = AppStrings(const Locale('en'));

    await tester.tap(find.byKey(const Key('backup-continue')));
    await tester.pumpAndSettle();

    expect(find.text(strings.backupFailedRecordsTitle), findsOneWidget);
    expect(find.text(strings.backupFailedRecordsMessage(1)), findsOneWidget);
    expect(find.textContaining('存在处理失败的照片'), findsNothing);

    await tester.tap(find.text(strings.backupReturnToProcess));
    await tester.pumpAndSettle();
    expect(exported, isFalse);
    expect(find.text(strings.includePrivateOriginals), findsNothing);
    await disposeScreen(tester);
  });
}
