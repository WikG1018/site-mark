import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/domain/app_links.dart';
import 'package:sitemark/domain/app_storage_usage.dart';
import 'package:sitemark/platform/external_link_service.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/features/settings/global_settings_screen.dart';
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

  /// Pumps the [GlobalSettingsScreen] in a localized Material harness wired to
  /// the in-memory [database] via Riverpod overrides.
  Future<void> pumpSettings(
    WidgetTester tester, {
    AppDatabase? db,
    PlatformServices? platform,
    ExternalLinkService? externalLinks,
    StorageUsageService? storage,
  }) async {
    final resolved = db ?? database;
    // Default to a fake platform so the screen's permission load resolves
    // deterministically instead of hanging on the real platform channel.
    final resolvedPlatform = platform ?? _SettingsTestPlatformServices();
    final resolvedLinks = externalLinks ?? _RecordingExternalLinkService();
    final resolvedStorage =
        storage ??
        _RecordingStorageUsageService(const [
          AppStorageUsage(
            originalBytes: 0,
            renderedBytes: 0,
            exportBytes: 0,
            databaseAndOtherBytes: 0,
          ),
        ]);
    // Open the lazy in-memory database and ensure the singleton settings row
    // before the screen reads it, so the FutureBuilder resolves on the first
    // pumped frame instead of stalling `pumpAndSettle` on the DB open.
    await resolved.getAppSettings();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(resolved),
          platformServicesProvider.overrideWithValue(resolvedPlatform),
          externalLinkServiceProvider.overrideWithValue(resolvedLinks),
          storageUsageServiceProvider.overrideWithValue(resolvedStorage),
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
    await tester.pumpAndSettle();
  }

  testWidgets('theme and language persist through database settings', (
    tester,
  ) async {
    await pumpSettings(tester, db: database);
    await tester.tap(find.byKey(const Key('theme-dark')));
    await tester.tap(find.byKey(const Key('language-en')));
    await tester.pumpAndSettle();

    final settings = await database.getAppSettings();
    expect(settings.themeMode, 'dark');
    expect(settings.localeCode, 'en');
  });

  testWidgets(
    'opacity slider persists on change end within the 0.20-0.95 range',
    (tester) async {
      await pumpSettings(tester, db: database);
      // The default opacity (0.78) already satisfies the 0.20-0.95 bounds, so a
      // bare range check cannot detect a regression where onChangeEnd never
      // persists. Drag the thumb hard to the right end: with divisions: 75 over
      // [0.20, 0.95] the value snaps to exactly 0.95, which differs from 0.78.
      // Asserting 0.95 proves onChangeEnd wrote the dragged value to the DB.
      await tester.timedDrag(
        find.byKey(const Key('opacity-slider')),
        const Offset(500, 0),
        const Duration(milliseconds: 200),
      );
      await tester.pumpAndSettle();

      final settings = await database.getAppSettings();
      expect(settings.defaultWatermarkOpacity, 0.95);
      expect(settings.defaultWatermarkOpacity, lessThanOrEqualTo(0.95));
      expect(settings.defaultWatermarkOpacity, greaterThanOrEqualTo(0.20));
    },
  );

  testWidgets('default font scale persists on release', (tester) async {
    await pumpSettings(tester);
    final sliderFinder = find.byKey(const Key('default-font-scale-slider'));
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(sliderFinder, 200, scrollable: scrollable);
    // scrollUntilVisible stops once the slider is built, but ListView's
    // off-screen cache extent can leave the thumb just below the viewport.
    // ensureVisible scrolls it fully on-screen so the drag hit-tests it.
    await tester.ensureVisible(sliderFinder);
    await tester.pumpAndSettle();
    await tester.timedDrag(
      sliderFinder,
      const Offset(500, 0),
      const Duration(milliseconds: 200),
    );
    await tester.pumpAndSettle();
    expect((await database.getAppSettings()).defaultWatermarkFontScale, 1.60);
  });

  testWidgets('accent swatch selection persists', (tester) async {
    await pumpSettings(tester, db: database);
    await tester.scrollUntilVisible(
      find.byKey(const Key('accent-orange')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('accent-orange')));
    await tester.pumpAndSettle();

    final settings = await database.getAppSettings();
    expect(settings.defaultWatermarkAccentColorArgb, 0xffef6c00);
  });

  testWidgets('watermark position segmented control persists', (tester) async {
    await pumpSettings(tester, db: database);
    await tester.tap(find.byKey(const Key('default-position-bottomRight')));
    await tester.pumpAndSettle();

    final settings = await database.getAppSettings();
    expect(settings.defaultWatermarkPosition, 'bottomRight');
  });

  testWidgets('about section shows fallback version when PackageInfo fails', (
    tester,
  ) async {
    await pumpSettings(tester, db: database);
    await tester.scrollUntilVisible(
      find.textContaining('0.2.0'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('0.2.0'), findsOneWidget);
  });

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
    await pumpSettings(tester, storage: storage);
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('storage-section')),
      300,
      scrollable: scrollable,
    );

    expect(find.text('SiteMark 应用内数据占用（不含系统相册）'), findsOneWidget);
    expect(find.text('10 MB'), findsOneWidget);
    expect(find.text('1 MB'), findsOneWidget);
    expect(find.text('2 MB'), findsOneWidget);
    expect(find.text('3 MB'), findsOneWidget);
    expect(find.text('4 MB'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('storage-refresh')));
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
    await tester.ensureVisible(find.byKey(const Key('clear-local-exports')));
    await tester.tap(find.byKey(const Key('clear-local-exports')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-clear-exports')));
    await tester.pumpAndSettle();
    expect(storage.clearCount, 1);
    expect(storage.loadCount, 4);
  });

  testWidgets('storage error state retries successfully', (tester) async {
    final storage = _RetryingStorageUsageService();
    await pumpSettings(tester, storage: storage);
    await tester.scrollUntilVisible(
      find.byKey(const Key('storage-section')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('无法读取存储占用'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('retry-storage-load')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('retry-storage-load')));
    await tester.pumpAndSettle();

    expect(storage.loadCount, 2);
    expect(find.text('无法读取存储占用'), findsNothing);
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

  testWidgets('storage manage-records entry opens the records route', (
    tester,
  ) async {
    await database.getAppSettings();
    final router = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(
          path: '/settings',
          builder: (context, state) => const GlobalSettingsScreen(),
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
          platformServicesProvider.overrideWithValue(
            _SettingsTestPlatformServices(),
          ),
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
    await tester.scrollUntilVisible(
      find.byKey(const Key('manage-storage-records')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(const Key('manage-storage-records')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manage-storage-records')));
    await tester.pumpAndSettle();

    expect(find.text('records destination'), findsOneWidget);
  });

  testWidgets('about shows and opens the full GitHub repository URL', (
    tester,
  ) async {
    final links = _RecordingExternalLinkService();
    await pumpSettings(tester, db: database, externalLinks: links);
    await tester.scrollUntilVisible(
      find.text(siteMarkRepositoryUrl),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('GitHub 代码仓库'), findsOneWidget);
    expect(find.text(siteMarkRepositoryUrl), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('github-repository-link')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('github-repository-link')));
    await tester.pump();
    expect(links.opened, [siteMarkRepositoryUri]);
  });

  testWidgets('about shows a snackbar when opening the repository fails', (
    tester,
  ) async {
    final links = _RecordingExternalLinkService(result: false);
    await pumpSettings(tester, db: database, externalLinks: links);
    await tester.scrollUntilVisible(
      find.text(siteMarkRepositoryUrl),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(const Key('github-repository-link')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('github-repository-link')));
    await tester.pump();
    expect(find.text('无法打开浏览器'), findsOneWidget);
    expect(links.opened, [siteMarkRepositoryUri]);
  });

  testWidgets('location tile shows disabled when permission is denied', (
    tester,
  ) async {
    await pumpSettings(
      tester,
      platform: _SettingsTestPlatformServices(
        permissionState: LocationPermissionState.denied,
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('location-permission-setting')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('未开启'), findsOneWidget);
  });

  testWidgets('location tile shows enabled when permission is granted', (
    tester,
  ) async {
    await pumpSettings(
      tester,
      platform: _SettingsTestPlatformServices(
        permissionState: LocationPermissionState.granted,
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('location-permission-setting')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('已开启'), findsOneWidget);
  });

  testWidgets('tapping the disabled location tile requests permission', (
    tester,
  ) async {
    final platform = _SettingsTestPlatformServices(
      permissionState: LocationPermissionState.denied,
      requestResult: LocationPermissionState.denied,
    );
    await pumpSettings(tester, platform: platform);
    await tester.scrollUntilVisible(
      find.byKey(const Key('location-permission-setting')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('location-permission-setting')));
    await tester.pumpAndSettle();

    expect(platform.requestLocationPermissionCount, 1);
    final settings = await database.getAppSettings();
    expect(settings.locationPermissionPromptDismissed, isTrue);
  });

  testWidgets('settings route is reachable from the app shell', (tester) async {
    await database.getAppSettings();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
          routes: [
            GoRoute(
              path: 'settings',
              builder: (context, state) => const GlobalSettingsScreen(),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          platformServicesProvider.overrideWithValue(
            _SettingsTestPlatformServices(),
          ),
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
    router.go('/settings');
    await tester.pumpAndSettle();

    expect(find.byType(GlobalSettingsScreen), findsOneWidget);
  });
}

class _SettingsTestPlatformServices implements PlatformServices {
  _SettingsTestPlatformServices({
    this.permissionState = LocationPermissionState.denied,
    this.requestResult = LocationPermissionState.denied,
  });

  LocationPermissionState permissionState;
  LocationPermissionState requestResult;
  int requestLocationPermissionCount = 0;
  int openApplicationSettingsCount = 0;

  @override
  Future<LocationPermissionState> getLocationPermissionState() async =>
      permissionState;

  @override
  Future<LocationPermissionState> requestLocationPermission() async {
    requestLocationPermissionCount++;
    return requestResult;
  }

  @override
  Future<void> openApplicationSettings() async {
    openApplicationSettingsCount++;
  }

  @override
  Future<String> createCameraTarget(String captureId) async =>
      '/private/$captureId.jpg';

  @override
  Future<CameraCaptureResult> launchCamera(String captureId) async =>
      CameraCaptureResult(
        outcome: CameraOutcome.captured,
        outputPath: '/private/$captureId.jpg',
      );

  @override
  Future<RecoveredCameraCapture?> recoverCameraCapture() async => null;

  @override
  Future<void> finishCameraCapture(String captureId, bool keepOriginal) async {}

  @override
  Future<LocationResult> requestCurrentLocation(int timeoutMillis) async =>
      LocationResult(outcome: LocationOutcome.unavailable);

  @override
  Future<String> publishJpeg(String sourcePath, String displayName) async =>
      'content://media/site-mark/1';

  @override
  Future<void> deletePublishedImage(String contentUri) async {}

  @override
  Future<ImageMetadataResult> inspectImage(String path) async =>
      ImageMetadataResult(
        width: 0,
        height: 0,
        fileSizeBytes: 0,
        mimeType: 'image/jpeg',
      );
}

class _RecordingExternalLinkService implements ExternalLinkService {
  _RecordingExternalLinkService({this.result = true});

  final bool result;
  final List<Uri> opened = [];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return result;
  }
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
