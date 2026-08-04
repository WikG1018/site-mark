import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/project_lifecycle.dart';
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
                lifecycleStatus: ProjectLifecycleStatus.active,
                isPinned: false,
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
    expect(find.text('使用备份中的水印设置'), findsOneWidget);
    expect(find.text('左下 · 透明度 72% · 字体 110%'), findsOneWidget);
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

  testWidgets('preparation failures show actionable localized snackbars', (
    tester,
  ) async {
    final expectations = <Locale, Map<ProjectBundleRestoreFailure, String>>{
      const Locale('zh'): {
        ProjectBundleRestoreFailure.notSiteMarkBackup:
            '请选择由 SiteMark“备份项目”生成的 ZIP',
        ProjectBundleRestoreFailure.unsupportedVersion: '请先升级 SiteMark',
        ProjectBundleRestoreFailure.corrupted: '请选择其他 SiteMark 备份后重试',
        ProjectBundleRestoreFailure.selectionArchive: '请选择通过“备份项目”生成的 ZIP',
        ProjectBundleRestoreFailure.insufficientStorage: '请释放空间后重试',
      },
      const Locale('en'): {
        ProjectBundleRestoreFailure.notSiteMarkBackup:
            'Choose a ZIP created with Back up projects in SiteMark',
        ProjectBundleRestoreFailure.unsupportedVersion: 'Update SiteMark',
        ProjectBundleRestoreFailure.corrupted:
            'Choose another SiteMark backup and try again',
        ProjectBundleRestoreFailure.selectionArchive:
            'Choose a ZIP created with Back up projects',
        ProjectBundleRestoreFailure.insufficientStorage:
            'Free some space and try again',
      },
    };

    for (final localeEntry in expectations.entries) {
      for (final failureEntry in localeEntry.value.entries) {
        await pumpScreen(
          tester,
          locale: localeEntry.key,
          dependencies: ProjectRestoreFlowDependencies(
            pickZip: () async => '/tmp/not-a-backup.zip',
            prepareRestore: (_) async => throw ProjectBundleRestoreException(
              'raw internal parser failure',
              failure: failureEntry.key,
            ),
            restorePrepared:
                ({
                  required prepared,
                  required projectNames,
                  onProgress,
                }) async => const [],
            discardPrepared: (_) async {},
          ),
        );
        await tester.tap(find.byKey(const Key('restore-projects')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('choose-restore-zip')));
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.textContaining(failureEntry.value),
          ),
          findsOneWidget,
          reason: failureEntry.key.name,
        );
        expect(find.textContaining('raw internal'), findsNothing);
        ScaffoldMessenger.of(
          tester.element(find.byType(Scaffold).first),
        ).clearSnackBars();
        await tester.pumpAndSettle();
      }
    }
  });

  testWidgets('preview explains when a backup has no watermark settings', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      dependencies: ProjectRestoreFlowDependencies(
        pickZip: () async => '/tmp/backup.zip',
        prepareRestore: (_) async => _prepared(includeWatermark: false),
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

    expect(find.text('备份未包含水印设置，将使用默认设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picker failures show friendly copy and re-enable restore', (
    tester,
  ) async {
    var pickerCalls = 0;
    await pumpScreen(
      tester,
      dependencies: ProjectRestoreFlowDependencies(
        pickZip: () async {
          pickerCalls++;
          throw StateError('raw picker platform failure');
        },
        prepareRestore: (_) async => _prepared(),
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

    expect(pickerCalls, 1);
    expect(find.text('无法打开备份文件选择器，请重试'), findsOneWidget);
    expect(find.textContaining('raw picker'), findsNothing);

    await tester.tap(find.byKey(const Key('restore-projects')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('choose-restore-zip')), findsOneWidget);
    expect(pickerCalls, 1);
  });

  testWidgets('picker cancellation stays silent and re-enables restore', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      dependencies: ProjectRestoreFlowDependencies(
        pickZip: () async => null,
        prepareRestore: (_) async => _prepared(),
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
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(find.byKey(const Key('restore-projects')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('choose-restore-zip')), findsOneWidget);
  });

  test('typed restore failures have distinct localized messages', () {
    final strings = AppStrings(const Locale('zh'));
    final expected = <ProjectBundleRestoreFailure, String>{
      ProjectBundleRestoreFailure.notSiteMarkBackup:
          '所选 ZIP 不是 SiteMark 导出的项目备份。请选择由 SiteMark“备份项目”生成的 ZIP。',
      ProjectBundleRestoreFailure.unsupportedVersion:
          '此备份版本高于当前应用支持范围。请先升级 SiteMark，再重新选择该备份。',
      ProjectBundleRestoreFailure.corrupted:
          '备份已损坏或校验不一致。请选择其他 SiteMark 备份后重试。',
      ProjectBundleRestoreFailure.selectionArchive:
          '所选 ZIP 是照片分享包，不含可恢复的项目数据。请选择通过“备份项目”生成的 ZIP。',
      ProjectBundleRestoreFailure.nameConflict:
          '恢复项目名称与现有项目或本次所选名称冲突。请重新开始恢复，并在预览中修改冲突名称后再恢复。',
      ProjectBundleRestoreFailure.insufficientStorage:
          '存储空间不足，无法完成操作。请释放空间后重试。',
      ProjectBundleRestoreFailure.finalizationPending:
          '恢复数据已安全保存，但尚未完成显示。请重启 SiteMark，应用会自动完成恢复。',
      ProjectBundleRestoreFailure.rolledBack:
          '一个或多个项目恢复失败，本次更改已全部回滚。请重新选择原备份进行恢复；若仍失败，请改用单项目备份逐个恢复。',
      ProjectBundleRestoreFailure.general:
          '恢复过程中发生错误，未能完成恢复。请重新选择备份进行恢复；若仍失败，请改用单项目备份逐个恢复。',
    };
    final actual = <String>{};
    for (final entry in expected.entries) {
      final message = describeProjectRestoreError(
        strings,
        ProjectBundleRestoreException(
          'raw internal detail',
          failure: entry.key,
        ),
        preparing: true,
      );
      expect(message, entry.value);
      expect(message, isNot(contains('raw internal')));
      actual.add(message);
    }
    expect(actual, hasLength(expected.length));
  });

  testWidgets('restore failures show actionable localized snackbars', (
    tester,
  ) async {
    final expectations = <Locale, Map<ProjectBundleRestoreFailure, String>>{
      const Locale('zh'): {
        ProjectBundleRestoreFailure.nameConflict: '在预览中修改冲突名称后再恢复',
        ProjectBundleRestoreFailure.rolledBack: '请重新选择原备份进行恢复',
        ProjectBundleRestoreFailure.general: '请重新选择备份进行恢复',
      },
      const Locale('en'): {
        ProjectBundleRestoreFailure.nameConflict:
            'change each conflicting name in the preview, then restore',
        ProjectBundleRestoreFailure.rolledBack:
            'Choose the original backup and restore again',
        ProjectBundleRestoreFailure.general:
            'Choose the backup and restore again',
      },
    };

    for (final localeEntry in expectations.entries) {
      for (final failureEntry in localeEntry.value.entries) {
        await pumpScreen(
          tester,
          locale: localeEntry.key,
          dependencies: ProjectRestoreFlowDependencies(
            pickZip: () async => '/tmp/backup.zip',
            prepareRestore: (_) async => _prepared(),
            restorePrepared:
                ({required prepared, required projectNames, onProgress}) async {
                  throw ProjectBundleRestoreException(
                    'raw internal restore failure',
                    failure: failureEntry.key,
                  );
                },
            discardPrepared: (_) async {},
          ),
        );
        await tester.tap(find.byKey(const Key('restore-projects')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('choose-restore-zip')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('restore-confirm')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.textContaining(failureEntry.value),
          ),
          findsOneWidget,
          reason: failureEntry.key.name,
        );
        expect(find.textContaining('raw internal'), findsNothing);
        ScaffoldMessenger.of(
          tester.element(find.byType(Scaffold).first),
        ).clearSnackBars();
        await tester.pumpAndSettle();
      }
    }
  });

  for (final locale in const [Locale('zh'), Locale('en')]) {
    testWidgets('finalization pending keeps committed restore in '
        '${locale.languageCode}', (tester) async {
      var discardCalls = 0;
      await pumpScreen(
        tester,
        locale: locale,
        dependencies: ProjectRestoreFlowDependencies(
          pickZip: () async => '/tmp/backup.zip',
          prepareRestore: (_) async => _prepared(bundle: true),
          restorePrepared:
              ({required prepared, required projectNames, onProgress}) async {
                throw const ProjectBundleRestoreException(
                  'raw finalization failure',
                  failure: ProjectBundleRestoreFailure.finalizationPending,
                );
              },
          discardPrepared: (_) async => discardCalls++,
        ),
      );

      await tester.tap(find.byKey(const Key('restore-projects')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('choose-restore-zip')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('restore-confirm')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          locale.languageCode == 'zh'
              ? '恢复数据已安全保存，但尚未完成显示。请重启 SiteMark，应用会自动完成恢复。'
              : 'Restore data is safely saved but is not visible yet. Restart SiteMark to finish the restore automatically.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          locale.languageCode == 'zh' ? '已回滚' : 'rolled back',
        ),
        findsNothing,
      );
      expect(find.textContaining('raw finalization'), findsNothing);
      expect(discardCalls, 0);
    });
  }

  testWidgets(
    'successful restore returns home and keeps its success snackbar',
    (tester) async {
      final prepared = _prepared(bundle: true);
      var discardCalls = 0;
      final router = GoRouter(
        initialLocation: '/settings/backup-restore',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) =>
                const Scaffold(key: Key('project-home')),
          ),
          GoRoute(
            path: '/settings/backup-restore',
            builder: (context, state) => BackupRestoreSectionScreen(
              restoreDependencies: ProjectRestoreFlowDependencies(
                pickZip: () async => '/tmp/backup.zip',
                prepareRestore: (_) async => prepared,
                restorePrepared:
                    ({
                      required prepared,
                      required projectNames,
                      onProgress,
                    }) async {
                      onProgress?.call(2, 2);
                      return const [
                        ProjectImportResult(
                          projectId: 'target',
                          projectName: '源项目',
                          photoCount: 1,
                          restoredOriginals: 1,
                          lifecycleStatus: ProjectLifecycleStatus.active,
                          isPinned: false,
                        ),
                        ProjectImportResult(
                          projectId: 'target-2',
                          projectName: '源项目二',
                          photoCount: 0,
                          restoredOriginals: 0,
                          lifecycleStatus: ProjectLifecycleStatus.active,
                          isPinned: false,
                        ),
                      ];
                    },
                discardPrepared: (_) async => discardCalls++,
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(database)],
          child: MaterialApp.router(
            locale: const Locale('zh'),
            supportedLocales: AppStrings.supportedLocales,
            localizationsDelegates: const [
              AppStrings.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('restore-projects')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('choose-restore-zip')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('restore-confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('project-home')), findsOneWidget);
      expect(find.textContaining('恢复完成'), findsWidgets);
      expect(find.textContaining('进行中 2'), findsOneWidget);
      expect(find.textContaining('下次启动'), findsNothing);
      expect(discardCalls, 0);
    },
  );

  testWidgets(
    'mixed restore shows status summary and opens archived projects',
    (tester) async {
      final prepared = _prepared(bundle: true);
      ProjectLifecycleStatus? homeExtra;
      final router = GoRouter(
        initialLocation: '/settings/backup-restore',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) {
              homeExtra = state.extra is ProjectLifecycleStatus
                  ? state.extra! as ProjectLifecycleStatus
                  : null;
              return Scaffold(
                key: const Key('project-home'),
                body: Text(homeExtra?.name ?? 'none'),
              );
            },
          ),
          GoRoute(
            path: '/settings/backup-restore',
            builder: (context, state) => BackupRestoreSectionScreen(
              restoreDependencies: ProjectRestoreFlowDependencies(
                pickZip: () async => '/tmp/backup.zip',
                prepareRestore: (_) async => prepared,
                restorePrepared:
                    ({
                      required prepared,
                      required projectNames,
                      onProgress,
                    }) async {
                      onProgress?.call(3, 3);
                      return const [
                        ProjectImportResult(
                          projectId: 'a',
                          projectName: '进行中',
                          photoCount: 0,
                          restoredOriginals: 0,
                          lifecycleStatus: ProjectLifecycleStatus.active,
                          isPinned: false,
                        ),
                        ProjectImportResult(
                          projectId: 'c',
                          projectName: '已完成',
                          photoCount: 0,
                          restoredOriginals: 0,
                          lifecycleStatus: ProjectLifecycleStatus.completed,
                          isPinned: false,
                        ),
                        ProjectImportResult(
                          projectId: 'z',
                          projectName: '已归档',
                          photoCount: 0,
                          restoredOriginals: 0,
                          lifecycleStatus: ProjectLifecycleStatus.archived,
                          isPinned: true,
                        ),
                      ];
                    },
                discardPrepared: (_) async {},
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(database)],
          child: MaterialApp.router(
            locale: const Locale('zh'),
            supportedLocales: AppStrings.supportedLocales,
            localizationsDelegates: const [
              AppStrings.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('restore-projects')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('choose-restore-zip')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('restore-confirm')));
      await tester.pumpAndSettle();

      expect(find.textContaining('进行中 1'), findsOneWidget);
      expect(find.textContaining('已完成 1'), findsOneWidget);
      expect(find.textContaining('已归档 1'), findsOneWidget);
      expect(find.byKey(const Key('view-archived-projects')), findsOneWidget);

      await tester.tap(find.byKey(const Key('view-archived-projects')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('project-home')), findsOneWidget);
      expect(homeExtra, ProjectLifecycleStatus.archived);
    },
  );
}

PreparedProjectRestore _prepared({
  bool includeWatermark = true,
  bool bundle = false,
}) {
  rust.ProjectArchivePreview preview(String name) => rust.ProjectArchivePreview(
    schemaVersion: 2,
    projectName: name,
    omittedProcessingCount: 0,
    omittedFailedCount: 0,
    isPartial: false,
    includesOriginals: true,
    projectLifecycleStatus: 'active',
    projectIsPinned: false,
    watermark: includeWatermark
        ? const rust.ArchiveWatermarkSettings(
            position: 'bottomLeft',
            opacity: 0.72,
            accentColorArgb: 0xFF009688,
            fontScale: 1.1,
          )
        : null,
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
    templates: const [],
  );
  return PreparedProjectRestore(
    sourceZipPath: '/tmp/backup.zip',
    bundleId: bundle ? 'bundle-id' : null,
    stagingDirectory: bundle ? '/tmp/bundle-staging' : null,
    items: [
      PreparedProjectRestoreItem(
        sourceProjectId: 'source',
        targetProjectId: 'target',
        archivePath: '/tmp/backup.zip',
        preview: preview('源项目'),
      ),
      if (bundle)
        PreparedProjectRestoreItem(
          sourceProjectId: 'source-2',
          targetProjectId: 'target-2',
          archivePath: '/tmp/bundle-staging/source-2.zip',
          preview: preview('源项目二'),
        ),
    ],
  );
}
