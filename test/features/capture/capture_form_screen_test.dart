import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/project_lifecycle.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/capture_form_draft_store.dart';
import 'package:sitemark/platform/notification_service.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

void main() {
  const fixedLocationHint = '拍摄前仅请求一次前台位置；拒绝授权也可以继续拍摄。';

  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> pumpCaptureForm(
    WidgetTester tester, {
    required _CaptureFormPlatform platform,
  }) async {
    await database.createProject(id: 'project-1', name: '东区厂房改造');
    await tester.pumpWidget(
      MyApp(
        database: database,
        initialLocale: const Locale('zh'),
        platformServices: platform,
        completionNotificationService: _NoOpCompletionNotificationService(),
        captureFormDraftStore: MemoryCaptureFormDraftStore(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('东区厂房改造'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('capture-fab')));
    await tester.pumpAndSettle();
  }

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets(
    'first-use denied state shows only the contextual location prompt',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final platform = _CaptureFormPlatform(
        permissionState: LocationPermissionState.denied,
      );

      await pumpCaptureForm(tester, platform: platform);

      expect(
        find.byKey(const Key('location-permission-prompt')),
        findsOneWidget,
      );
      expect(find.text(fixedLocationHint), findsNothing);
      expect(platform.requestLocationPermissionCount, 0);
      expect(tester.takeException(), isNull);
      await disposeApp(tester);
    },
  );

  testWidgets('granted state hides the contextual location prompt', (
    tester,
  ) async {
    final platform = _CaptureFormPlatform(
      permissionState: LocationPermissionState.granted,
    );

    await pumpCaptureForm(tester, platform: platform);

    expect(find.byKey(const Key('location-permission-prompt')), findsNothing);
    expect(find.text(fixedLocationHint), findsNothing);
    expect(platform.requestLocationPermissionCount, 0);
    await disposeApp(tester);
  });

  testWidgets('dismissed state keeps the contextual prompt hidden', (
    tester,
  ) async {
    await database.updateAppSettings(locationPermissionPromptDismissed: true);
    final platform = _CaptureFormPlatform(
      permissionState: LocationPermissionState.denied,
    );

    await pumpCaptureForm(tester, platform: platform);

    expect(find.byKey(const Key('location-permission-prompt')), findsNothing);
    expect(find.text(fixedLocationHint), findsNothing);
    expect(platform.requestLocationPermissionCount, 0);
    await disposeApp(tester);
  });

  testWidgets('capture button does not request location permission', (
    tester,
  ) async {
    final platform = _CaptureFormPlatform(
      permissionState: LocationPermissionState.denied,
    );
    await pumpCaptureForm(tester, platform: platform);

    await tester.enterText(find.byKey(const Key('work-location')), 'A 区三层');
    await tester.enterText(find.byKey(const Key('work-content')), '设备安装检查');
    await tester.enterText(find.byKey(const Key('photographer')), '张工');
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('capture-button')).hitTestable());
    await tester.pumpAndSettle();

    expect(platform.requestLocationPermissionCount, 0);
    expect(platform.launchCameraCount, 1);
    await disposeApp(tester);
  });

  testWidgets('camera failure shows guidance without raw platform text', (
    tester,
  ) async {
    final platform = _CaptureFormPlatform(
      permissionState: LocationPermissionState.denied,
      cameraOutcome: CameraOutcome.failed,
      cameraErrorMessage: 'ActivityNotFoundException: vendor detail',
    );
    await pumpCaptureForm(tester, platform: platform);

    await tester.enterText(find.byKey(const Key('work-location')), 'A 区三层');
    await tester.enterText(find.byKey(const Key('work-content')), '设备安装检查');
    await tester.enterText(find.byKey(const Key('photographer')), '张工');
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('capture-button')).hitTestable());
    await tester.pumpAndSettle();

    expect(find.textContaining('系统相机暂不可用'), findsOneWidget);
    expect(find.textContaining('vendor detail'), findsNothing);
    await disposeApp(tester);
  });

  testWidgets(
    'completed project deep-link capture form is read only and never opens camera',
    (tester) async {
      await database.createProject(id: 'completed', name: '已完成项目');
      await database.updateProjectLifecycleStatus(
        projectId: 'completed',
        expectedStatus: ProjectLifecycleStatus.active,
        targetStatus: ProjectLifecycleStatus.completed,
      );
      final platform = _CaptureFormPlatform(
        permissionState: LocationPermissionState.denied,
      );
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(database),
          platformServicesProvider.overrideWithValue(platform),
          completionNotificationServiceProvider.overrideWithValue(
            _NoOpCompletionNotificationService(),
          ),
          captureFormDraftStoreProvider.overrideWithValue(
            MemoryCaptureFormDraftStore(),
          ),
          startupRecoveryEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);
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
      router.go('/projects/completed/capture');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('capture-read-only')), findsOneWidget);
      expect(find.textContaining('项目当前不可拍摄'), findsOneWidget);
      expect(find.byKey(const Key('capture-button')), findsNothing);
      expect(platform.launchCameraCount, 0);
      await disposeApp(tester);
    },
  );
}

class _NoOpCompletionNotificationService
    implements CompletionNotificationService {
  @override
  Future<void> initialize(void Function(String deepLinkPath) onTapDeepLink) =>
      Future.value();

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> setEnabled(bool enabled) => Future.value();

  @override
  Future<void> showCaptureReady({
    required String projectId,
    required String captureId,
    required String photoNumber,
  }) => Future.value();
}

class _CaptureFormPlatform implements PlatformServices {
  _CaptureFormPlatform({
    required this.permissionState,
    this.cameraOutcome = CameraOutcome.cancelled,
    this.cameraErrorMessage,
  });

  final LocationPermissionState permissionState;
  final CameraOutcome cameraOutcome;
  final String? cameraErrorMessage;
  int requestLocationPermissionCount = 0;
  int launchCameraCount = 0;

  @override
  Future<LocationPermissionState> getLocationPermissionState() async =>
      permissionState;

  @override
  Future<LocationPermissionState> requestLocationPermission() async {
    requestLocationPermissionCount++;
    return LocationPermissionState.denied;
  }

  @override
  Future<void> openApplicationSettings() async {}

  @override
  Future<String> createCameraTarget(String captureId) async =>
      '/private/$captureId.jpg';

  @override
  Future<CameraCaptureResult> launchCamera(String captureId) async {
    launchCameraCount++;
    return CameraCaptureResult(
      outcome: cameraOutcome,
      outputPath: '/private/$captureId.jpg',
      errorMessage: cameraErrorMessage,
    );
  }

  @override
  Future<RecoveredCameraCapture?> recoverCameraCapture() async => null;

  @override
  Future<void> finishCameraCapture(String captureId, bool keepOriginal) async {}

  @override
  Future<LocationResult> requestCurrentLocation(int timeoutMillis) async =>
      LocationResult(outcome: LocationOutcome.permissionDenied);

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
