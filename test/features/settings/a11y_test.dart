import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_filter.dart';
import 'package:sitemark/domain/capture_list_query.dart';
import 'package:sitemark/domain/app_storage_usage.dart';
import 'package:sitemark/features/capture/capture_date_filter_bar.dart';
import 'package:sitemark/features/settings/global_settings_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/app_storage_service.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

void main() {
  Future<void> closeRouterFixture(
    WidgetTester tester,
    ProviderContainer container,
    AppDatabase database,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  }

  testWidgets('global settings screen meets the Android tap target guideline', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final settings = await database.getAppSettings();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          platformServicesProvider.overrideWithValue(
            _A11yTestPlatformServices(),
          ),
          storageUsageServiceProvider.overrideWithValue(
            _A11yStorageUsageService(),
          ),
          appSettingsProvider.overrideWith((ref) => Stream.value(settings)),
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

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

    expect(find.byKey(const Key('settings-group-capture')), findsOneWidget);
    for (final tile in tester.widgetList<ListTile>(find.byType(ListTile))) {
      expect(
        tester.getSize(find.byWidget(tile)).height,
        greaterThanOrEqualTo(48),
      );
    }
  });

  for (final locale in const [Locale('zh'), Locale('en')]) {
    testWidgets('real root settings remain usable at 360dp and 3x text in '
        '${locale.languageCode}', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final database = AppDatabase.forTesting(NativeDatabase.memory());
      await database.getAppSettings();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(database),
          storageUsageServiceProvider.overrideWithValue(
            _A11yStorageUsageService(),
          ),
        ],
      );
      try {
        final router = container.read(routerProvider);
        router.go('/settings');
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              locale: locale,
              supportedLocales: AppStrings.supportedLocales,
              localizationsDelegates: const [
                AppStrings.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(3)),
                child: child!,
              ),
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('root-dock')), findsOneWidget);
        expect(tester.takeException(), isNull);
        final aboutEntry = find.byKey(const Key('settings-entry-about'));
        await tester.scrollUntilVisible(
          aboutEntry,
          400,
          scrollable: find.descendant(
            of: find.byType(GlobalSettingsScreen),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.getRect(aboutEntry).bottom,
          lessThanOrEqualTo(
            tester.getRect(find.byKey(const Key('root-dock'))).top,
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(aboutEntry);
        expect(
          router.routeInformationProvider.value.uri.path,
          '/settings/about',
        );
      } finally {
        await closeRouterFixture(tester, container, database);
      }
    });
  }

  testWidgets('capture date filter bar meets the Android tap target '
      'guideline', (tester) async {
    final filter = ValueNotifier(const CaptureFilter());
    const options = CaptureDateOptions(
      years: [2025, 2026],
      months: [6, 7, 8],
      days: [1, 2, 16],
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: ValueListenableBuilder<CaptureFilter>(
            valueListenable: filter,
            builder: (context, value, _) {
              return CaptureDateFilterBar(
                filter: value,
                options: options,
                onChanged: (next) => filter.value = next,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  });
}

class _A11yStorageUsageService implements StorageUsageService {
  @override
  Future<AppStorageUsage> load() async => const AppStorageUsage(
    originalBytes: 1025,
    renderedBytes: 0,
    exportBytes: 0,
    databaseAndOtherBytes: 0,
  );

  @override
  Future<ClearExportsResult> clearExports() => throw UnimplementedError();
}

class _A11yTestPlatformServices implements PlatformServices {
  @override
  Future<LocationPermissionState> getLocationPermissionState() async =>
      LocationPermissionState.denied;

  @override
  Future<LocationPermissionState> requestLocationPermission() async =>
      LocationPermissionState.denied;

  @override
  Future<void> openApplicationSettings() async {}

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
  Future<PublishJpegOutcome> publishJpeg(
    String sourcePath,
    String displayName,
    String captureId,
    String? publishedUri,
  ) async =>
      const PublishJpegOutcome(contentUri: 'content://media/site-mark/1');

  @override
  Future<List<RecoveredPublishJournalEntry>> recoverPublishJournals() async =>
      [];

  @override
  Future<void> clearPublishJournal(
    String captureId,
    String expectedContentUri,
  ) async {}

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
