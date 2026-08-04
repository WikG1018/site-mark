import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/app_storage_usage.dart';
import 'package:sitemark/features/settings/global_settings_screen.dart';
import 'package:sitemark/features/settings/sections/backup_restore_section_screen.dart';
import 'package:sitemark/features/settings/sections/project_backup_selection_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';
import 'package:sitemark/shared/ui/glass_surface.dart';
import 'package:sitemark/workflow/app_storage_service.dart';

void main() {
  late AppDatabase database;
  late bool databaseClosed;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    databaseClosed = false;
  });

  tearDown(() async {
    if (!databaseClosed) await database.close();
  });

  Future<void> closeRouterFixture(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
    // Drift schedules a zero-duration cleanup timer when watched queries are
    // cancelled. Flush it before closing on the real event loop.
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
    databaseClosed = true;
  }

  /// Pumps the [GlobalSettingsScreen] in a localized Material harness wired to
  /// the in-memory [database] via Riverpod overrides.
  Future<void> pumpSettings(
    WidgetTester tester, {
    StorageUsageService? storage,
    Stream<AppSetting>? settingsStream,
    bool settle = true,
  }) async {
    final initialSettings = await database.getAppSettings();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          storageUsageServiceProvider.overrideWithValue(
            storage ??
                _RecordingStorageUsageService(const [
                  AppStorageUsage(
                    originalBytes: 1025,
                    renderedBytes: 0,
                    exportBytes: 0,
                    databaseAndOtherBytes: 0,
                  ),
                ]),
          ),
          appSettingsProvider.overrideWith(
            (ref) => settingsStream ?? Stream.value(initialSettings),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const GlobalSettingsScreen(),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets('groups all settings and shows current summaries', (
    tester,
  ) async {
    await database.getAppSettings();
    await database.updateAppSettings(
      localeCode: 'zh',
      completionNotificationsEnabled: true,
    );
    await pumpSettings(tester);

    expect(find.byKey(const Key('settings-group-capture')), findsOneWidget);
    expect(find.byKey(const Key('settings-group-data')), findsOneWidget);
    expect(find.byKey(const Key('settings-group-app')), findsOneWidget);
    expect(find.text('拍摄与记录'), findsOneWidget);
    expect(find.text('数据与安全'), findsOneWidget);
    expect(find.text('应用'), findsOneWidget);
    expect(find.text('新建项目水印默认值'), findsOneWidget);
    expect(find.byKey(const Key('backup-restore-menu')), findsOneWidget);
    expect(find.text('备份与恢复'), findsOneWidget);
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('语言'), findsOneWidget);
    expect(find.text('储存'), findsOneWidget);
    expect(find.text('定位'), findsOneWidget);
    expect(find.text('完成通知'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
    expect(find.text('简体中文'), findsOneWidget);
    expect(find.text('已开启'), findsOneWidget);
    expect(find.text('1.0 KB'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('uses three rounded glass lists separated between rows', (
    tester,
  ) async {
    await pumpSettings(tester);

    expect(find.byType(GlassSurface), findsNWidgets(3));
    expect(find.byType(Divider), findsNWidgets(6));
    for (final surface in tester.widgetList<GlassSurface>(
      find.byType(GlassSurface),
    )) {
      expect(surface.borderRadius, const BorderRadius.all(Radius.circular(20)));
    }
  });

  testWidgets('keeps unfinished async summaries blank without a spinner', (
    tester,
  ) async {
    final storageCompleter = Completer<AppStorageUsage>();
    await pumpSettings(
      tester,
      storage: _PendingStorageUsageService(storageCompleter.future),
      settle: false,
    );

    expect(find.byKey(const Key('settings-group-data')), findsOneWidget);
    final storageTile = tester.widget<ListTile>(
      find.ancestor(of: find.text('储存'), matching: find.byType(ListTile)),
    );
    expect(storageTile.subtitle, isNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('provider errors leave summaries blank without crashing', (
    tester,
  ) async {
    await pumpSettings(
      tester,
      storage: _FailingStorageUsageService(),
      settingsStream: Stream<AppSetting>.error(StateError('settings failed')),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('settings-group-app')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('refreshes language and notification summaries live', (
    tester,
  ) async {
    await database.getAppSettings();
    await database.updateAppSettings(
      localeCode: 'zh',
      completionNotificationsEnabled: false,
    );
    final settingsStream = StreamController<AppSetting>();
    addTearDown(settingsStream.close);
    final initialSettings = await database.getAppSettings();
    await pumpSettings(tester, settingsStream: settingsStream.stream);
    settingsStream.add(initialSettings);
    await tester.pumpAndSettle();
    expect(find.text('简体中文'), findsOneWidget);
    expect(find.text('未开启'), findsOneWidget);

    await database.updateAppSettings(
      localeCode: 'en',
      completionNotificationsEnabled: true,
    );
    settingsStream.add(await database.getAppSettings());
    await tester.pumpAndSettle();

    expect(find.text('English'), findsOneWidget);
    expect(find.text('已开启'), findsOneWidget);
  });

  testWidgets('settings route is reachable from the app shell', (tester) async {
    await database.getAppSettings();
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
    try {
      final router = container.read(routerProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
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
      router.go('/settings');
      await tester.pump();
      await tester.pump(AppMotion.rootSwitch);
      await tester.pump();

      expect(find.byType(GlobalSettingsScreen), findsOneWidget);
      expect(find.byKey(const Key('root-dock')), findsOneWidget);
      expect(
        find.byKey(const Key('root-destination-settings')),
        findsOneWidget,
      );
    } finally {
      await closeRouterFixture(tester, container);
    }
  });

  testWidgets('backup and nested selection routes are registered', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
    try {
      final router = container.read(routerProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
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

      router.go('/settings/backup-restore');
      await tester.pump();
      await tester.pump(AppMotion.pageTransition);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byType(BackupRestoreSectionScreen), findsOneWidget);
      expect(find.byKey(const Key('root-dock')), findsNothing);

      router.go('/settings/backup-restore/backup');
      await tester.pump();
      await tester.pump(AppMotion.pageTransition);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byType(ProjectBackupSelectionScreen), findsOneWidget);
      expect(find.byKey(const Key('root-dock')), findsNothing);
    } finally {
      await closeRouterFixture(tester, container);
    }
  });

  test(
    'storage usage stays cached after settings disposal until invalidated',
    () async {
      final storage = _RecordingStorageUsageService(const [
        AppStorageUsage(
          originalBytes: 1,
          renderedBytes: 2,
          exportBytes: 3,
          databaseAndOtherBytes: 4,
        ),
      ]);
      final container = ProviderContainer(
        overrides: [storageUsageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);

      final firstListener = container.listen(
        storageUsageProvider,
        (_, _) {},
        fireImmediately: true,
      );
      await container.read(storageUsageProvider.future);
      expect(storage.loadCount, 1);

      firstListener.close();
      await container.pump();

      final reenteredListener = container.listen(
        storageUsageProvider,
        (_, _) {},
        fireImmediately: true,
      );
      await container.read(storageUsageProvider.future);
      expect(storage.loadCount, 1);

      container.invalidate(storageUsageProvider);
      await container.read(storageUsageProvider.future);
      expect(storage.loadCount, 2);
      reenteredListener.close();
    },
  );
}

class _RecordingStorageUsageService implements StorageUsageService {
  _RecordingStorageUsageService(this.values);

  final List<AppStorageUsage> values;
  int loadCount = 0;
  int clearCount = 0;

  @override
  Future<AppStorageUsage> load() async {
    final index = loadCount < values.length ? loadCount : values.length - 1;
    loadCount++;
    return values[index];
  }

  @override
  Future<ClearExportsResult> clearExports() async {
    clearCount++;
    final current = values.last;
    values.add(
      AppStorageUsage(
        originalBytes: current.originalBytes,
        renderedBytes: current.renderedBytes,
        exportBytes: 0,
        databaseAndOtherBytes: current.databaseAndOtherBytes,
      ),
    );
    return const ClearExportsResult(deletedFiles: 1, freedBytes: 1024);
  }
}

class _PendingStorageUsageService implements StorageUsageService {
  _PendingStorageUsageService(this.pending);

  final Future<AppStorageUsage> pending;

  @override
  Future<AppStorageUsage> load() => pending;

  @override
  Future<ClearExportsResult> clearExports() => throw UnimplementedError();
}

class _FailingStorageUsageService implements StorageUsageService {
  @override
  Future<AppStorageUsage> load() => Future.error(StateError('storage failed'));

  @override
  Future<ClearExportsResult> clearExports() => throw UnimplementedError();
}
