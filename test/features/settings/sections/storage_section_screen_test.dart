// test/features/settings/sections/storage_section_screen_test.dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/app_storage_usage.dart';
import 'package:sitemark/features/settings/sections/storage_section_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/workflow/app_storage_service.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    required StorageUsageService storage,
  }) async {
    await database.getAppSettings();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          storageUsageServiceProvider.overrideWithValue(storage),
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
          home: const StorageSectionScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('storage section shows totals, refreshes, and clears exports', (
    tester,
  ) async {
    final storage = _RecordingStorageUsageService([
      const AppStorageUsage(
        originalBytes: 1024 * 1024,
        renderedBytes: 2 * 1024 * 1024,
        exportBytes: 3 * 1024 * 1024,
        databaseAndOtherBytes: 4 * 1024 * 1024,
      ),
      const AppStorageUsage(
        originalBytes: 1024 * 1024,
        renderedBytes: 2 * 1024 * 1024,
        exportBytes: 0,
        databaseAndOtherBytes: 4 * 1024 * 1024,
      ),
    ]);
    await pumpScreen(tester, storage: storage);

    expect(find.text('SiteMark 应用内数据占用（不含系统相册）'), findsOneWidget);
    expect(find.text('10 MB'), findsOneWidget);
    expect(find.text('1 MB'), findsOneWidget);
    expect(find.text('2 MB'), findsOneWidget);
    expect(find.text('3 MB'), findsOneWidget);
    expect(find.text('4 MB'), findsOneWidget);

    await tester.tap(find.byKey(const Key('storage-refresh')));
    await tester.pumpAndSettle();
    expect(storage.loadCount, 2);

    // Restore a non-zero export value to exercise the destructive action.
    storage.values.add(
      const AppStorageUsage(
        originalBytes: 1024 * 1024,
        renderedBytes: 2 * 1024 * 1024,
        exportBytes: 3 * 1024 * 1024,
        databaseAndOtherBytes: 4 * 1024 * 1024,
      ),
    );
    await tester.tap(find.byKey(const Key('storage-refresh')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clear-local-exports')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-clear-exports')));
    await tester.pumpAndSettle();
    expect(storage.clearCount, 1);
    expect(storage.loadCount, 4);
  });

  testWidgets('storage error state retries successfully', (tester) async {
    final storage = _RetryingStorageUsageService();
    await pumpScreen(tester, storage: storage);
    expect(find.text('无法读取存储占用'), findsOneWidget);

    await tester.tap(find.byKey(const Key('retry-storage-load')));
    await tester.pumpAndSettle();

    expect(storage.loadCount, 2);
    expect(find.text('无法读取存储占用'), findsNothing);
  });

  testWidgets('storage manage-records entry opens the records route', (
    tester,
  ) async {
    await database.getAppSettings();
    final router = GoRouter(
      initialLocation: '/settings/storage',
      routes: [
        GoRoute(
          path: '/settings',
          builder: (context, state) => const Scaffold(body: Text('settings')),
          routes: [
            GoRoute(
              path: 'storage',
              builder: (context, state) => const StorageSectionScreen(),
            ),
          ],
        ),
        GoRoute(
          path: '/records',
          builder: (context, state) =>
              const Scaffold(body: Text('records destination')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          storageUsageServiceProvider.overrideWithValue(
            _RecordingStorageUsageService(const [
              AppStorageUsage(
                originalBytes: 0,
                renderedBytes: 0,
                exportBytes: 0,
                databaseAndOtherBytes: 0,
              ),
            ]),
          ),
        ],
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
    await tester.tap(find.byKey(const Key('manage-storage-records')));
    await tester.pumpAndSettle();

    expect(find.text('records destination'), findsOneWidget);
  });

  void mockGalleryAccess(String? mode) {
    const channel = MethodChannel('sitemark.system.ohos');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'detectGalleryAccess') return null;
          return mode;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
  }

  testWidgets('picker fallback shows the gallery honesty hint on storage', (
    tester,
  ) async {
    mockGalleryAccess('pickerFallback');
    await pumpScreen(
      tester,
      storage: _RecordingStorageUsageService(const [
        AppStorageUsage(
          originalBytes: 0,
          renderedBytes: 0,
          exportBytes: 0,
          databaseAndOtherBytes: 0,
        ),
      ]),
    );

    expect(
      find.byKey(const Key('gallery-picker-fallback-hint')),
      findsOneWidget,
    );
    expect(find.textContaining('未进入系统相册'), findsOneWidget);
  });

  testWidgets('acl gallery access hides the storage honesty hint', (
    tester,
  ) async {
    mockGalleryAccess('acl');
    await pumpScreen(
      tester,
      storage: _RecordingStorageUsageService(const [
        AppStorageUsage(
          originalBytes: 0,
          renderedBytes: 0,
          exportBytes: 0,
          databaseAndOtherBytes: 0,
        ),
      ]),
    );

    expect(find.byKey(const Key('gallery-picker-fallback-hint')), findsNothing);
  });
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

class _RetryingStorageUsageService implements StorageUsageService {
  int loadCount = 0;

  @override
  Future<AppStorageUsage> load() async {
    loadCount++;
    if (loadCount == 1) throw StateError('read failed');
    return const AppStorageUsage(
      originalBytes: 0,
      renderedBytes: 0,
      exportBytes: 0,
      databaseAndOtherBytes: 0,
    );
  }

  @override
  Future<ClearExportsResult> clearExports() async {
    return const ClearExportsResult(deletedFiles: 0, freedBytes: 0);
  }
}
