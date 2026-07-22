import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/background/capture_background_scheduler.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/features/capture/capture_record_card.dart';
import 'package:sitemark/main.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/capture_processor.dart';
import 'package:sitemark/workflow/capture_workflow.dart';
import 'package:sitemark/platform/notification_service.dart';
import 'package:sitemark/workflow/app_startup_recovery.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';
import 'package:sitemark/src/rust/api/image_core.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('production startup runs camera, location, and queue recovery', (
    tester,
  ) async {
    final events = <String>[];
    final recovery = AppStartupRecovery(
      recoverCamera: () async => events.add('camera'),
      resolveLocations: () async => events.add('location'),
      reconcileQueue: () async => events.add('queue'),
    );

    await tester.pumpWidget(
      MyApp(
        database: database,
        initialLocale: const Locale('zh'),
        startupRecovery: recovery,
        completionNotificationService: _FakeCompletionNotificationService(),
      ),
    );
    await tester.pump();

    expect(events, ['camera', 'location', 'queue']);
    await disposeApp(tester);
  });

  /// Seeds a fully `ready` capture under `project-1` so the carry-forward draft
  /// returned by `latestCapturedDraft` reflects these descriptive fields.
  Future<void> seedReadyCapture({
    String workLocation = 'A 区三层',
    String workContent = '风管安装检查',
    String photographer = '张工',
    String notes = '上一张备注',
  }) async {
    await database.createProject(id: 'project-1', name: '东区厂房改造');
    final pending = await database.createPendingCapture(
      id: 'seed-capture',
      projectId: 'project-1',
      originalPath: '/private/seed-capture.jpg',
      workLocation: workLocation,
      workContent: workContent,
      photographer: photographer,
      watermarkLocaleCode: 'zh',
      notes: notes,
      createdAt: DateTime(2026, 7, 16, 9, 30),
    );
    final captured = await database.markCaptured(
      captureId: pending.id,
      capturedAt: DateTime(2026, 7, 16, 9, 32),
    );
    final rendering = await database.markRendering(
      captureId: captured.id,
      originalSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    await database.markReady(
      captureId: rendering.id,
      publishedUri: 'content://media/site-mark/seed',
    );
  }

  /// Pumps [MyApp] wired with the standard widget-test fakes and navigates from
  /// the project list into the capture form for `project-1`. [workflowResult]
  /// documents the expected outcome of the next capture (the real workflow
  /// returns `queued` because the fake camera always reports `captured`).
  Future<void> openCaptureForm(
    WidgetTester tester, {
    CaptureWorkflowResult? workflowResult,
    _WidgetTestPlatformServices? platformOverride,
  }) async {
    final images = _WidgetTestImagePipeline();
    final share = _WidgetTestShareService();
    final platform = platformOverride ?? _WidgetTestPlatformServices();
    final outputPaths = _WidgetTestOutputPaths();
    final scheduler = _InlineProcessingScheduler(
      database: database,
      platform: platform,
      images: images,
      outputPaths: outputPaths,
    );
    await tester.pumpWidget(
      MyApp(
        database: database,
        initialLocale: const Locale('zh'),
        platformServices: platform,
        imagePipeline: images,
        outputPaths: outputPaths,
        projectExportPaths: _WidgetTestProjectExportPaths(),
        shareService: share,
        privateFileStore: _WidgetTestPrivateFileStore(),
        backgroundScheduler: scheduler,
        completionNotificationService: _FakeCompletionNotificationService(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('东区厂房改造'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('拍摄'));
    await tester.pumpAndSettle();
  }

  /// Reads the current text of the [TextFormField] found by [key].
  String fieldText(WidgetTester tester, Key key) {
    final field = tester.widget<TextFormField>(find.byKey(key));
    return field.controller!.text;
  }

  /// Pumps [MyApp] with the standard widget-test fakes and a single ready
  /// capture under `project-1` so the all-records surface has content to show.
  Future<void> pumpAppWithRecords(WidgetTester tester) async {
    await seedReadyCapture();
    final images = _WidgetTestImagePipeline();
    final share = _WidgetTestShareService();
    final platform = _WidgetTestPlatformServices();
    final outputPaths = _WidgetTestOutputPaths();
    final scheduler = _InlineProcessingScheduler(
      database: database,
      platform: platform,
      images: images,
      outputPaths: outputPaths,
    );
    await tester.pumpWidget(
      MyApp(
        database: database,
        initialLocale: const Locale('zh'),
        platformServices: platform,
        imagePipeline: images,
        outputPaths: outputPaths,
        projectExportPaths: _WidgetTestProjectExportPaths(),
        shareService: share,
        privateFileStore: _WidgetTestPrivateFileStore(),
        backgroundScheduler: scheduler,
        completionNotificationService: _FakeCompletionNotificationService(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Sentinel documenting that the next capture should resolve to `queued`.
  final queuedResult = const CaptureWorkflowResult(
    outcome: CaptureWorkflowOutcome.queued,
  );

  testWidgets('shows the project-first empty state', (tester) async {
    await tester.pumpWidget(
      MyApp(
        database: database,
        initialLocale: const Locale('zh'),
        completionNotificationService: _FakeCompletionNotificationService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('工程印记'), findsOneWidget);
    expect(find.text('还没有项目'), findsOneWidget);
    expect(find.text('新建项目'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('creates a project and returns to the project list', (
    tester,
  ) async {
    await tester.pumpWidget(
      MyApp(
        database: database,
        initialLocale: const Locale('zh'),
        completionNotificationService: _FakeCompletionNotificationService(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('新建项目'));
    await tester.pumpAndSettle();

    expect(find.text('创建项目'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('project-name')), '东区厂房改造');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('东区厂房改造'), findsOneWidget);
    expect(find.text('还没有项目'), findsNothing);
    await disposeApp(tester);
  });

  testWidgets('ships an English interface', (tester) async {
    await tester.pumpWidget(
      MyApp(
        database: database,
        initialLocale: const Locale('en'),
        completionNotificationService: _FakeCompletionNotificationService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SiteMark'), findsOneWidget);
    expect(find.text('No projects yet'), findsOneWidget);
    expect(find.text('New project'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('edits constrained project watermark settings', (tester) async {
    await database.createProject(id: 'project-1', name: '东区厂房改造');
    await tester.pumpWidget(
      MyApp(
        database: database,
        initialLocale: const Locale('zh'),
        completionNotificationService: _FakeCompletionNotificationService(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('东区厂房改造'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('此项目水印设置'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.tune_outlined));
    // Pump until the watermark settings screen's FutureBuilder resolves and
    // the slider is visible.
    await tester.pumpAndSettle();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('此项目水印设置'), findsOneWidget);
    expect(find.byKey(const Key('watermark-preview')), findsOneWidget);
    // The slider is below the fold in the ListView; scroll it into view.
    await tester.scrollUntilVisible(
      find.byKey(const Key('project-font-scale-slider')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('project-font-scale-slider')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('右下'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('右下'));
    await tester.scrollUntilVisible(
      find.byKey(const Key('accent-blue')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('accent-blue')));
    await tester.scrollUntilVisible(
      find.text('保存'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final project = await database.projectById('project-1');
    expect(project?.watermarkPosition, 'bottomRight');
    expect(project?.watermarkAccentColorArgb, 0xff1565c0);
    await disposeApp(tester);
  });

  testWidgets('captures a project record through the system camera workflow', (
    tester,
  ) async {
    final images = _WidgetTestImagePipeline();
    final share = _WidgetTestShareService();
    final platform = _WidgetTestPlatformServices();
    final outputPaths = _WidgetTestOutputPaths();
    await database.createProject(id: 'project-1', name: '东区厂房改造');
    // A scheduler that runs the real CaptureProcessor inline so the widget test
    // observes the ready transition without a real WorkManager isolate.
    final scheduler = _InlineProcessingScheduler(
      database: database,
      platform: platform,
      images: images,
      outputPaths: outputPaths,
    );
    await tester.pumpWidget(
      MyApp(
        database: database,
        initialLocale: const Locale('zh'),
        platformServices: platform,
        imagePipeline: images,
        outputPaths: outputPaths,
        projectExportPaths: _WidgetTestProjectExportPaths(),
        shareService: share,
        privateFileStore: _WidgetTestPrivateFileStore(),
        backgroundScheduler: scheduler,
        completionNotificationService: _FakeCompletionNotificationService(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('东区厂房改造'));
    await tester.pumpAndSettle();
    expect(find.text('拍摄记录'), findsOneWidget);

    await tester.tap(find.text('拍摄'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('work-location')), 'A 区三层');
    await tester.enterText(find.byKey(const Key('work-content')), '风管安装检查');
    await tester.enterText(find.byKey(const Key('photographer')), '张工');
    await tester.tap(find.text('调用系统相机'));
    await tester.pumpAndSettle();

    // The capture form now stays open for consecutive shooting and surfaces a
    // queue-confirmation snackbar instead of navigating away. Return to the
    // project detail to observe the inline-processed, ready record.
    expect(find.text('照片已加入后台处理，可继续拍摄'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byType(CaptureRecordCard), findsOneWidget);
    expect(find.textContaining('SM-'), findsNothing);
    expect(find.text('已完成'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.archive_outlined));
    await tester.pumpAndSettle();
    expect(find.text('导出项目资料'), findsOneWidget);
    await tester.tap(find.text('生成并分享'));
    await tester.pumpAndSettle();
    expect(share.lastPath, '/exports/project-1.zip');

    await tester.tap(find.byType(CaptureRecordCard));
    await tester.pumpAndSettle();
    // The detail screen now leads with a large image preview, so the evidence
    // card is below the fold and must be scrolled into view before asserting.
    await tester.scrollUntilVisible(
      find.text('原图 SHA-256'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('原图 SHA-256'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('edit-work-location')),
      'B 区屋面',
    );
    await tester.enterText(
      find.byKey(const Key('edit-work-content')),
      '保温整改复查',
    );
    await tester.enterText(find.byKey(const Key('edit-photographer')), '李工');
    await tester.tap(find.text('重新生成水印'));
    await tester.pumpAndSettle();
    expect(find.textContaining('B 区屋面'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(platform.deletedUri, 'content://media/site-mark/1');
    expect(find.text('暂无拍摄记录'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets(
    'prefills three fields from latest capture and leaves notes blank',
    (tester) async {
      await seedReadyCapture(
        workLocation: 'A 区三层',
        workContent: '风管安装检查',
        photographer: '张工',
        notes: '上一张备注',
      );
      await openCaptureForm(tester);

      expect(fieldText(tester, const Key('work-location')), 'A 区三层');
      expect(fieldText(tester, const Key('work-content')), '风管安装检查');
      expect(fieldText(tester, const Key('photographer')), '张工');
      expect(fieldText(tester, const Key('notes')), '');
      await disposeApp(tester);
    },
  );

  testWidgets(
    'queued capture stays on form, clears notes, and re-enables button',
    (tester) async {
      // Seed a prior ready capture so the three carry-forward fields are
      // prefilled; the consecutive shot only needs per-photo notes.
      await seedReadyCapture(
        workLocation: 'A 区三层',
        workContent: '风管安装检查',
        photographer: '张工',
      );
      await openCaptureForm(tester, workflowResult: queuedResult);
      await tester.enterText(find.byKey(const Key('notes')), '本张备注');
      await tester.tap(find.byKey(const Key('capture-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('capture-form')), findsOneWidget);
      expect(fieldText(tester, const Key('notes')), '');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('capture-button')))
            .onPressed,
        isNotNull,
      );
      expect(find.text('照片已加入后台处理，可继续拍摄'), findsOneWidget);
      await disposeApp(tester);
    },
  );

  testWidgets('home opens all records with project and date filters', (
    tester,
  ) async {
    await pumpAppWithRecords(tester);

    await tester.tap(find.byTooltip('全部记录'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('project-filter')), findsOneWidget);
    expect(find.byKey(const Key('filter-year')), findsOneWidget);
    expect(find.byType(CaptureRecordCard), findsWidgets);
    await disposeApp(tester);
  });

  /// Drives the new-project form to create a project named [name] using the
  /// shared widget-test fakes. Used by the global-defaults copy test below.
  Future<void> createProjectThroughUi(
    WidgetTester tester, {
    required String name,
  }) async {
    await tester.pumpWidget(
      MyApp(
        database: database,
        initialLocale: const Locale('zh'),
        completionNotificationService: _FakeCompletionNotificationService(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('新建项目'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('project-name')), name);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
  }

  testWidgets('new project copies current global watermark defaults', (
    tester,
  ) async {
    await database.updateAppSettings(
      defaultWatermarkPosition: 'bottomRight',
      defaultWatermarkOpacity: 0.64,
      defaultWatermarkAccentColorArgb: 0xff1565c0,
    );
    await createProjectThroughUi(tester, name: '屋面工程');
    final project = (await database.getProjects()).single;
    expect(project.watermarkPosition, 'bottomRight');
    expect(project.watermarkOpacity, 0.64);
    expect(project.watermarkAccentColorArgb, 0xff1565c0);
    await disposeApp(tester);
  });

  testWidgets('duplicate project name stays on form and shows an error', (
    tester,
  ) async {
    await database.createProject(id: 'existing', name: 'Cloud Site');
    await tester.pumpWidget(
      MyApp(
        database: database,
        initialLocale: const Locale('zh'),
        completionNotificationService: _FakeCompletionNotificationService(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('新建项目'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('project-name')),
      ' cloud   site ',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('project-name')), findsOneWidget);
    expect(find.text('已存在同名项目'), findsOneWidget);
    expect((await database.getProjects()), hasLength(1));
    await disposeApp(tester);
  });

  testWidgets('granted location hides the explanation card', (tester) async {
    await database.createProject(id: 'project-1', name: '东区厂房改造');
    final platform = _WidgetTestPlatformServices()
      ..permissionState = LocationPermissionState.granted;
    await openCaptureForm(tester, platformOverride: platform);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('location-permission-prompt')), findsNothing);
    expect(find.byKey(const Key('location-permission-enable')), findsNothing);
    await disposeApp(tester);
  });

  testWidgets(
    'capture button never triggers a runtime location permission request',
    (tester) async {
      await database.createProject(id: 'project-1', name: '东区厂房改造');
      final platform = _WidgetTestPlatformServices()
        ..permissionState = LocationPermissionState.denied;
      await openCaptureForm(tester, platformOverride: platform);
      await tester.pumpAndSettle();

      // The non-blocking explanation card is shown because permission is
      // denied and the user has not dismissed it.
      expect(
        find.byKey(const Key('location-permission-prompt')),
        findsOneWidget,
      );
      expect(platform.requestLocationPermissionCount, 0);

      await tester.enterText(find.byKey(const Key('work-location')), 'A 区');
      await tester.enterText(find.byKey(const Key('work-content')), '检查');
      await tester.enterText(find.byKey(const Key('photographer')), '张工');
      await tester.scrollUntilVisible(
        find.byKey(const Key('capture-button')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('capture-button')));
      await tester.pumpAndSettle();

      // The capture button path must never request runtime permission or
      // fire a location read when permission is not granted.
      expect(platform.requestLocationPermissionCount, 0);
      expect(platform.requestCurrentLocationCount, 0);
      expect(find.text('照片已加入后台处理，可继续拍摄'), findsOneWidget);
      await disposeApp(tester);
    },
  );

  testWidgets('enable-location tap requests permission and dismisses on deny', (
    tester,
  ) async {
    await database.createProject(id: 'project-1', name: '东区厂房改造');
    final platform = _WidgetTestPlatformServices()
      ..permissionState = LocationPermissionState.denied
      ..requestResult = LocationPermissionState.denied;
    await openCaptureForm(tester, platformOverride: platform);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('location-permission-prompt')), findsOneWidget);
    await tester.tap(find.byKey(const Key('location-permission-enable')));
    await tester.pumpAndSettle();

    expect(platform.requestLocationPermissionCount, 1);
    // A denied result persists the dismissal and hides the card.
    expect(find.byKey(const Key('location-permission-prompt')), findsNothing);
    final settings = await database.getAppSettings();
    expect(settings.locationPermissionPromptDismissed, isTrue);
    await disposeApp(tester);
  });

  testWidgets(
    'dismiss icon hides the explanation card and persists dismissal',
    (tester) async {
      await database.createProject(id: 'project-1', name: '东区厂房改造');
      final platform = _WidgetTestPlatformServices()
        ..permissionState = LocationPermissionState.denied;
      await openCaptureForm(tester, platformOverride: platform);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('location-permission-dismiss')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('location-permission-prompt')), findsNothing);
      final settings = await database.getAppSettings();
      expect(settings.locationPermissionPromptDismissed, isTrue);
      await disposeApp(tester);
    },
  );

  // Task 4: capture list edit mode and batch action bar.

  testWidgets('project detail edit mode shows checkboxes and batch bar', (
    tester,
  ) async {
    await pumpAppWithRecords(tester);
    await tester.tap(find.text('东区厂房改造'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('edit-captures')));
    await tester.pumpAndSettle();

    expect(find.byType(Checkbox), findsWidgets);
    expect(find.byKey(const Key('batch-action-bar')), findsNothing);

    await tester.tap(find.byKey(const Key('select-all-captures')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('batch-action-bar')), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('all records edit mode shows checkboxes and batch bar', (
    tester,
  ) async {
    await pumpAppWithRecords(tester);
    await tester.tap(find.byTooltip('全部记录'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('edit-captures')));
    await tester.pumpAndSettle();

    expect(find.byType(Checkbox), findsWidgets);

    await tester.tap(find.byKey(const Key('select-all-captures')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('batch-action-bar')), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('changing date filter clears project detail selection', (
    tester,
  ) async {
    await pumpAppWithRecords(tester);
    await tester.tap(find.text('东区厂房改造'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('edit-captures')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('select-all-captures')));
    await tester.pumpAndSettle();

    bool anyChecked() => tester
        .widgetList<Checkbox>(find.byType(Checkbox))
        .any((cb) => cb.value == true);
    expect(anyChecked(), isTrue);

    await tester.tap(find.byKey(const Key('filter-year')));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, '2026'));
    await tester.pumpAndSettle();

    expect(anyChecked(), isFalse);
    await disposeApp(tester);
  });

  testWidgets('project detail batch bar fits at 360dp', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpAppWithRecords(tester);
    await tester.tap(find.text('东区厂房改造'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-captures')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('select-all-captures')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('batch-action-bar')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeApp(tester);
  });
}

class _FakeCompletionNotificationService
    implements CompletionNotificationService {
  @override
  Future<void> initialize(void Function(String deepLinkPath) onTapDeepLink) =>
      Future.value();

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> showCaptureReady({
    required String projectId,
    required String captureId,
    required String photoNumber,
  }) => Future.value();

  @override
  Future<void> setEnabled(bool enabled) => Future.value();
}

class _WidgetTestPlatformServices implements PlatformServices {
  String? deletedUri;
  LocationPermissionState permissionState = LocationPermissionState.granted;
  LocationPermissionState requestResult = LocationPermissionState.denied;
  int requestLocationPermissionCount = 0;
  int requestCurrentLocationCount = 0;
  int openApplicationSettingsCount = 0;

  @override
  Future<String> createCameraTarget(String captureId) async =>
      '/private/$captureId.jpg';

  @override
  Future<void> deletePublishedImage(String contentUri) async {
    deletedUri = contentUri;
  }

  @override
  Future<void> finishCameraCapture(String captureId, bool keepOriginal) async {}

  @override
  Future<CameraCaptureResult> launchCamera(String captureId) async {
    return CameraCaptureResult(
      outcome: CameraOutcome.captured,
      outputPath: '/private/$captureId.jpg',
    );
  }

  @override
  Future<String> publishJpeg(String sourcePath, String displayName) async =>
      'content://media/site-mark/1';

  @override
  Future<RecoveredCameraCapture?> recoverCameraCapture() async => null;

  @override
  Future<LocationResult> requestCurrentLocation(int timeoutMillis) async {
    requestCurrentLocationCount++;
    return LocationResult(outcome: LocationOutcome.permissionDenied);
  }

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
  Future<ImageMetadataResult> inspectImage(String path) async =>
      ImageMetadataResult(
        width: 0,
        height: 0,
        fileSizeBytes: 0,
        mimeType: 'image/jpeg',
      );
}

class _WidgetTestImagePipeline implements ImagePipeline {
  @override
  Future<ExportProjectResult> export(ExportProjectRequest request) async {
    return ExportProjectResult(
      outputZipPath: request.outputZipPath,
      archiveSha256:
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
      photoCount: request.photos.length,
    );
  }

  @override
  Future<ExportProjectResult> exportSelection(ExportSelectionRequest request) =>
      throw UnimplementedError();

  @override
  Future<RenderPhotoResult> render(RenderPhotoRequest request) async {
    return RenderPhotoResult(
      outputPath: request.outputPath,
      outputSha256:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      width: 4000,
      height: 3000,
    );
  }

  @override
  Future<String> sha256(String path) async =>
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
}

class _WidgetTestOutputPaths implements CaptureOutputPaths {
  @override
  Future<String> renderedPhotoPath(String captureId) async =>
      '/private/rendered/$captureId.jpg';
}

class _WidgetTestProjectExportPaths implements ProjectExportPaths {
  @override
  Future<String> projectZipPath(String projectId) async =>
      '/exports/$projectId.zip';
}

class _WidgetTestShareService implements ShareFileService {
  String? lastPath;

  @override
  Future<void> shareFile(String path) async {
    lastPath = path;
  }
}

class _WidgetTestPrivateFileStore implements PrivateFileStore {
  @override
  Future<bool> exists(String path) async => true;

  @override
  Future<void> deleteIfExists(String path) async {}
}

/// A [CaptureBackgroundScheduler] that runs the real [CaptureProcessor] inline
/// on each enqueue/retry, simulating immediate WorkManager completion so widget
/// tests can observe the `ready` transition without a background isolate.
class _InlineProcessingScheduler implements CaptureBackgroundScheduler {
  _InlineProcessingScheduler({
    required this.database,
    required this.platform,
    required this.images,
    required this.outputPaths,
  });

  final AppDatabase database;
  final PlatformServices platform;
  final ImagePipeline images;
  final CaptureOutputPaths outputPaths;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> enqueue(String captureId) async {
    final processor = CaptureProcessor(
      database: database,
      platform: platform,
      images: images,
      outputPaths: outputPaths,
    );
    await processor.process(captureId);
  }

  @override
  Future<void> retry(String captureId) async {
    // Mirror the production scheduler: reset state/attempts before re-enqueueing
    // so a `failed` record re-processes from a clean `captured` baseline.
    await database.resetCaptureForRetry(captureId);
    await enqueue(captureId);
  }

  @override
  Future<void> reconcilePending() async {
    final pending = await database.capturesAwaitingProcessing();
    for (final record in pending) {
      await enqueue(record.id);
    }
  }
}
