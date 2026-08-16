import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/features/settings/sections/location_section_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

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
    required _SettingsTestPlatformServices platform,
  }) async {
    await database.getAppSettings();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          platformServicesProvider.overrideWithValue(platform),
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
          home: const LocationSectionScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('location tile shows disabled when permission is denied', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      platform: _SettingsTestPlatformServices(
        permissionState: LocationPermissionState.denied,
      ),
    );
    expect(find.text('未开启'), findsOneWidget);
  });

  testWidgets('location tile shows enabled when permission is granted', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      platform: _SettingsTestPlatformServices(
        permissionState: LocationPermissionState.granted,
      ),
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
    await pumpScreen(tester, platform: platform);
    await tester.tap(find.byKey(const Key('location-permission-setting')));
    await tester.pumpAndSettle();

    expect(platform.requestLocationPermissionCount, 1);
    final settings = await database.getAppSettings();
    expect(settings.locationPermissionPromptDismissed, isTrue);
  });
}

// Verbatim copy from global_settings_screen_test.dart — needed because
// PlatformServices is a large interface and the full stub is already filled in.
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
  Future<PublishJpegOutcome> publishJpeg(
    String sourcePath,
    String displayName,
  ) async => const PublishJpegOutcome(contentUri: 'content://media/site-mark/1');

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
