import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    Locale locale = const Locale('zh'),
  }) async {
    await database.createProject(id: 'project-1', name: '东区厂房改造');
    await tester.pumpWidget(
      MyApp(
        database: database,
        initialLocale: locale,
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

  List<MethodCall> recordPlatformCalls(WidgetTester tester) {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    return calls;
  }

  int lightImpactCount(List<MethodCall> calls) => calls
      .where(
        (call) =>
            call.method == 'HapticFeedback.vibrate' &&
            call.arguments == 'HapticFeedbackType.lightImpact',
      )
      .length;

  Future<void> enterRequiredFields(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('work-location')), 'A 区三层');
    await tester.enterText(find.byKey(const Key('work-content')), '设备安装检查');
    await tester.enterText(find.byKey(const Key('photographer')), '张工');
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
      expect(
        find.descendant(
          of: find.byKey(const Key('location-permission-prompt')),
          matching: find.byType(Card),
        ),
        findsNothing,
      );
      expect(
        tester
            .getSize(find.byKey(const Key('location-permission-prompt')))
            .height,
        lessThanOrEqualTo(64),
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

  for (final locale in const [Locale('zh'), Locale('en')]) {
    testWidgets(
      '${locale.languageCode} compact form keeps required fields and submit action visible at 360dp/3x',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 3;
        tester.view.padding = const FakeViewPadding(top: 72, bottom: 48);
        tester.view.viewPadding = const FakeViewPadding(top: 72, bottom: 48);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.resetPadding();
          tester.view.resetViewPadding();
        });
        final platform = _CaptureFormPlatform(
          permissionState: LocationPermissionState.granted,
        );

        await pumpCaptureForm(tester, platform: platform, locale: locale);

        expect(find.byKey(const Key('work-location')), findsOneWidget);
        expect(find.byKey(const Key('work-content')), findsOneWidget);
        expect(find.byKey(const Key('photographer')), findsOneWidget);
        expect(find.byKey(const Key('notes')), findsNothing);
        expect(find.byKey(const Key('notes-expander')), findsOneWidget);
        final visibleHeight =
            tester.view.physicalSize.height / tester.view.devicePixelRatio;
        final buttonRect = tester.getRect(
          find.byKey(const Key('capture-button')),
        );
        final formTop = tester
            .getTopLeft(find.byKey(const Key('capture-form')))
            .dy;
        for (final key in const [
          Key('work-location'),
          Key('work-content'),
          Key('photographer'),
        ]) {
          final rect = tester.getRect(find.byKey(key));
          expect(rect.top, greaterThanOrEqualTo(formTop));
          expect(rect.bottom, lessThanOrEqualTo(buttonRect.top));
          expect(rect.height, greaterThanOrEqualTo(48));
        }
        expect(buttonRect.bottom, lessThanOrEqualTo(visibleHeight));

        await tester.tap(find.byKey(const Key('notes-expander')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('notes')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await disposeApp(tester);
      },
    );
  }

  testWidgets(
    'keyboard and system insets keep submit action visible without covering the focused field',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      tester.view.padding = const FakeViewPadding(top: 72, bottom: 48);
      tester.view.viewPadding = const FakeViewPadding(top: 72, bottom: 48);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
        tester.view.resetViewPadding();
        tester.view.resetViewInsets();
      });
      final platform = _CaptureFormPlatform(
        permissionState: LocationPermissionState.granted,
      );
      await pumpCaptureForm(tester, platform: platform);

      await tester.tap(find.byKey(const Key('photographer')));
      await tester.pump();
      final photographer = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('photographer')),
          matching: find.byType(EditableText),
        ),
      );
      expect(photographer.focusNode.hasFocus, isTrue);
      tester.view.viewInsets = const FakeViewPadding(bottom: 720);
      await tester.pumpAndSettle();

      final visibleHeight =
          (tester.view.physicalSize.height - tester.view.viewInsets.bottom) /
          tester.view.devicePixelRatio;
      final buttonRect = tester.getRect(
        find.byKey(const Key('capture-button')),
      );
      final focusedFieldRect = tester.getRect(
        find.byKey(const Key('photographer')),
      );
      expect(buttonRect.bottom, lessThanOrEqualTo(visibleHeight));
      expect(visibleHeight - buttonRect.bottom, inInclusiveRange(0, 32));
      expect(buttonRect.top, greaterThanOrEqualTo(focusedFieldRect.bottom));
      expect(photographer.focusNode.hasFocus, isTrue);

      FocusManager.instance.primaryFocus?.unfocus();
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();

      final restoredButtonRect = tester.getRect(
        find.byKey(const Key('capture-button')),
      );
      final restoredVisibleHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(
        restoredVisibleHeight - restoredButtonRect.bottom,
        inInclusiveRange(0, 32),
      );
      expect(photographer.focusNode.hasFocus, isFalse);
      expect(tester.takeException(), isNull);
      await disposeApp(tester);
    },
  );

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

  testWidgets(
    'invalid capture does not emit haptic feedback or start workflow',
    (tester) async {
      final platformCalls = recordPlatformCalls(tester);
      final platform = _CaptureFormPlatform(
        permissionState: LocationPermissionState.granted,
      );
      await pumpCaptureForm(tester, platform: platform);

      await tester.tap(find.byKey(const Key('capture-button')));
      await tester.pump();

      expect(lightImpactCount(platformCalls), 0);
      expect(platform.launchCameraCount, 0);
      await disposeApp(tester);
    },
  );

  testWidgets('valid capture emits one haptic and starts one workflow', (
    tester,
  ) async {
    final platformCalls = recordPlatformCalls(tester);
    final platform = _CaptureFormPlatform(
      permissionState: LocationPermissionState.granted,
    );
    await pumpCaptureForm(tester, platform: platform);
    await enterRequiredFields(tester);

    await tester.tap(find.byKey(const Key('capture-button')));
    await tester.pumpAndSettle();

    expect(lightImpactCount(platformCalls), 1);
    expect(platform.launchCameraCount, 1);
    await disposeApp(tester);
  });

  testWidgets(
    'rapid valid taps before rebuild emit one haptic and start one workflow',
    (tester) async {
      final platformCalls = recordPlatformCalls(tester);
      final platform = _CaptureFormPlatform(
        permissionState: LocationPermissionState.granted,
      );
      await pumpCaptureForm(tester, platform: platform);
      await enterRequiredFields(tester);
      final button = find.byKey(const Key('capture-button')).hitTestable();

      await tester.tap(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(lightImpactCount(platformCalls), 1);
      expect(platform.launchCameraCount, 1);
      await disposeApp(tester);
    },
  );

  testWidgets('disabled working button cannot add haptic or workflow calls', (
    tester,
  ) async {
    final platformCalls = recordPlatformCalls(tester);
    final platform = _CaptureFormPlatform(
      permissionState: LocationPermissionState.granted,
    );
    final cameraResult = Completer<CameraCaptureResult>();
    platform.cameraResult = cameraResult;
    await pumpCaptureForm(tester, platform: platform);
    await enterRequiredFields(tester);

    await tester.tap(find.byKey(const Key('capture-button')));
    await tester.pump();
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('capture-button')))
          .onPressed,
      isNull,
    );
    expect(lightImpactCount(platformCalls), 1);
    expect(platform.launchCameraCount, 1);

    await tester.tap(
      find.byKey(const Key('capture-button')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(lightImpactCount(platformCalls), 1);
    expect(platform.launchCameraCount, 1);
    cameraResult.complete(
      CameraCaptureResult(
        outcome: CameraOutcome.cancelled,
        outputPath: '/private/cancelled.jpg',
      ),
    );
    await tester.pumpAndSettle();
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
  Completer<CameraCaptureResult>? cameraResult;

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
    final pending = cameraResult;
    if (pending != null) return pending.future;
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
