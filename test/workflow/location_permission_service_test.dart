import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/location_permission_service.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

void main() {
  late AppDatabase database;
  late _FakePlatformServices platform;
  late LocationPermissionService service;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    // Ensure the singleton `global` settings row exists before each load so
    // the service does not race the lazy database open.
    await database.getAppSettings();
    platform = _FakePlatformServices();
    service = LocationPermissionService(database: database, platform: platform);
  });

  tearDown(() async {
    await database.close();
  });

  test('granted permission never shows the explanation', () async {
    platform.permissionState = LocationPermissionState.granted;

    final state = await service.load();

    expect(state.permission, LocationPermissionState.granted);
    expect(state.locationEnabled, isTrue);
    expect(state.showExplanation, isFalse);
    expect(state.openSettings, isFalse);
  });

  test('denied permission shows the explanation when not dismissed', () async {
    platform.permissionState = LocationPermissionState.denied;

    final state = await service.load();

    expect(state.permission, LocationPermissionState.denied);
    expect(state.locationEnabled, isFalse);
    expect(state.showExplanation, isTrue);
    expect(state.openSettings, isFalse);
  });

  test(
    'permanently denied permission surfaces the open-settings call to action',
    () async {
      platform.permissionState = LocationPermissionState.permanentlyDenied;

      final state = await service.load();

      expect(state.permission, LocationPermissionState.permanentlyDenied);
      expect(state.showExplanation, isTrue);
      expect(state.openSettings, isTrue);
    },
  );

  test('dismissed denied permission stays hidden after reload', () async {
    platform.permissionState = LocationPermissionState.denied;
    await service.dismiss();

    final state = await service.load();

    expect(state.permission, LocationPermissionState.denied);
    expect(state.showExplanation, isFalse);
    final settings = await database.getAppSettings();
    expect(settings.locationPermissionPromptDismissed, isTrue);
  });

  test('request with non-granted result persists dismissal', () async {
    platform.permissionState = LocationPermissionState.denied;
    platform.requestResult = LocationPermissionState.denied;

    final state = await service.request();

    expect(state.permission, LocationPermissionState.denied);
    expect(state.showExplanation, isFalse);
    final settings = await database.getAppSettings();
    expect(settings.locationPermissionPromptDismissed, isTrue);
    expect(platform.requestCount, 1);
  });

  test(
    'request with granted result leaves the dismissal flag untouched',
    () async {
      platform.permissionState = LocationPermissionState.denied;
      platform.requestResult = LocationPermissionState.granted;

      final state = await service.request();

      expect(state.permission, LocationPermissionState.granted);
      expect(state.locationEnabled, isTrue);
      expect(state.showExplanation, isFalse);
      final settings = await database.getAppSettings();
      expect(settings.locationPermissionPromptDismissed, isFalse);
    },
  );

  test('openSettings delegates to the platform bridge', () async {
    await service.openSettings();
    expect(platform.openSettingsCount, 1);
  });
}

class _FakePlatformServices implements PlatformServices {
  LocationPermissionState permissionState = LocationPermissionState.denied;
  LocationPermissionState requestResult = LocationPermissionState.denied;
  int requestCount = 0;
  int openSettingsCount = 0;

  @override
  Future<LocationPermissionState> getLocationPermissionState() async =>
      permissionState;

  @override
  Future<LocationPermissionState> requestLocationPermission() async {
    requestCount++;
    return requestResult;
  }

  @override
  Future<void> openApplicationSettings() async {
    openSettingsCount++;
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
