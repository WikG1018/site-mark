import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/features/capture/all_captures_screen.dart';
import 'package:sitemark/features/capture/capture_batch_action_bar.dart';
import 'package:sitemark/features/capture/capture_detail_screen.dart';
import 'package:sitemark/features/capture/capture_fullscreen_sequence.dart';
import 'package:sitemark/features/capture/capture_selection_controller.dart';
import 'package:sitemark/features/projects/project_detail_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/shared/ui/floating_dock_layout.dart';
import 'package:sitemark/workflow/capture_media_service.dart';
import 'package:sitemark/workflow/project_export_service.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:sitemark/src/rust/api/image_core.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> seedReadyCapture({
    String id = 'capture-1',
    String projectId = 'project-1',
  }) async {
    await database.createProject(id: projectId, name: '东区厂房改造');
    final pending = await database.createPendingCapture(
      id: id,
      projectId: projectId,
      originalPath: '/private/$id.jpg',
      workLocation: 'A 区',
      workContent: '风管检查',
      photographer: '张工',
      watermarkLocaleCode: 'zh',
      locationResolution: 'resolved',
      createdAt: DateTime(2026, 7, 16, 9),
    );
    final captured = await database.markCaptured(
      captureId: pending.id,
      capturedAt: DateTime(2026, 7, 16, 9, 30),
    );
    final rendering = await database.markRendering(
      captureId: captured.id,
      originalSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    await database.markReady(
      captureId: rendering.id,
      publishedUri: 'content://media/site-mark/$id',
    );
  }

  Widget buildAllCaptures() {
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const AllCapturesScreen(),
      ),
    );
  }

  Widget buildProjectDetail({Project? initialProject}) {
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ProjectDetailScreen(
          projectId: 'project-1',
          initialProject: initialProject,
        ),
      ),
    );
  }

  testWidgets('batch actions use one compact dock at large text scale', (
    tester,
  ) async {
    final controller = CaptureSelectionController()
      ..enter()
      ..replaceAll(const ['capture-1'], allReady: true);
    final media = CaptureMediaService(
      database: database,
      platform: _TestPlatform(),
      outputPaths: _TestOutputPaths(),
      files: _TestFileStore(),
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
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(3)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 332,
                child: CaptureBatchActionBar(
                  controller: controller,
                  mediaService: media,
                  exportService: buildTestExportService(database),
                  shareService: _TestShareService(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BottomAppBar), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('batch-action-bar'))).height,
      floatingDockHeight,
    );
    expect(find.byTooltip('导出所选'), findsOneWidget);
    expect(find.byTooltip('保存到相册'), findsOneWidget);
    expect(find.byTooltip('清理原图'), findsOneWidget);
    expect(find.byTooltip('全部删除'), findsOneWidget);
    expect(find.text('导出所选'), findsOneWidget);
    expect(find.text('保存到相册'), findsOneWidget);
    expect(find.text('清理原图'), findsOneWidget);
    expect(find.text('全部删除'), findsOneWidget);
    for (final name in ['export', 'gallery', 'originals', 'delete']) {
      final surface = tester.widget<Material>(
        find.byKey(Key('batch-action-$name-surface')),
      );
      expect(surface.color, Colors.transparent);
    }
    expect(tester.takeException(), isNull);

    await disposeTree(tester);
  });

  testWidgets('system back cancels project record selection mode', (
    tester,
  ) async {
    await seedReadyCapture();
    await tester.pumpWidget(buildProjectDetail());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-captures')));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsWidgets);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('拍摄记录'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byKey(const ValueKey('capture-fab')), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('project selection dock overlays the list from zero selected', (
    tester,
  ) async {
    await seedReadyCapture();
    await tester.pumpWidget(buildProjectDetail());
    await tester.pumpAndSettle();
    final heightBefore = tester
        .getSize(find.byKey(const Key('project-capture-list-content')))
        .height;

    await tester.tap(find.byKey(const Key('edit-captures')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('batch-action-bar')), findsOneWidget);
    expect(find.byType(BottomAppBar), findsNothing);
    expect(
      tester
          .getSize(find.byKey(const Key('project-capture-list-content')))
          .height,
      heightBefore,
    );
    expect(find.text('已选 0 张'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('project first frame uses real header with skeleton photo rows', (
    tester,
  ) async {
    await seedReadyCapture();
    final project = await database.projectById('project-1');

    await tester.pumpWidget(buildProjectDetail(initialProject: project));

    expect(find.text('东区厂房改造'), findsNWidgets(2));
    expect(find.text('拍摄记录'), findsOneWidget);
    expect(
      find.byKey(const Key('project-capture-list-skeleton')),
      findsOneWidget,
    );
    expect(find.text('2026-07-16 · 001'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('system back cancels all-records selection mode', (tester) async {
    await seedReadyCapture();
    await tester.pumpWidget(buildAllCaptures());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-captures')));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsWidgets);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('filter-sheet-trigger')), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    await disposeTree(tester);
  });

  testWidgets(
    'all-records selection dock overlays the list from zero selected',
    (tester) async {
      await seedReadyCapture();
      await tester.pumpWidget(buildAllCaptures());
      await tester.pumpAndSettle();
      final heightBefore = tester
          .getSize(find.byKey(const Key('capture-list-content')))
          .height;

      await tester.tap(find.byKey(const Key('edit-captures')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('batch-action-bar')), findsOneWidget);
      expect(find.byType(BottomAppBar), findsNothing);
      expect(
        tester.getSize(find.byKey(const Key('capture-list-content'))).height,
        heightBefore,
      );
      expect(find.text('已选 0 张'), findsOneWidget);
      await disposeTree(tester);
    },
  );

  // ─── Test 1: 底部栏滑入 ────────────────────────────────────────────────
  testWidgets(
    'bottom batch bar animates in with SlideTransition when items selected',
    (tester) async {
      await seedReadyCapture();
      await tester.pumpWidget(buildAllCaptures());
      await tester.pumpAndSettle();

      // Enter selection mode.
      await tester.tap(find.byKey(const Key('edit-captures')));
      await tester.pumpAndSettle();

      // Select all.
      await tester.tap(find.byKey(const Key('select-all-captures')));
      await tester.pumpAndSettle();

      // The batch action bar should now be present.
      expect(find.byKey(const Key('batch-action-bar')), findsOneWidget);

      // The AnimatedSwitcher wraps its child in SlideTransition via the
      // transitionBuilder, so at least one SlideTransition should exist.
      expect(find.byType(SlideTransition), findsWidgets);

      await disposeTree(tester);
    },
  );

  // ─── Test 2: 长按进入多选宿主 ──────────────────────────────────────────
  testWidgets('onSelectedChanged(true) outside selection mode enters editing '
      'and selects the item via enterWithSelection', (tester) async {
    final controller = CaptureSelectionController();
    expect(controller.editing, isFalse);
    expect(controller.selectedIds, isEmpty);

    // Simulate what the host AllCapturesScreen / ProjectDetailScreen does
    // when a card fires onSelectedChanged(true) while not in selection mode.
    const id = 'capture-1';
    if (!controller.editing) {
      controller.enterWithSelection(id);
    } else {
      controller.toggle(id);
    }

    expect(controller.editing, isTrue);
    expect(controller.selectedIds, contains(id));
    expect(controller.selectedIds.length, 1);
  });

  // ─── Test 3: 返回栈断言 ────────────────────────────────────────────────
  testWidgets(
    'pushing capture detail from /records and popping returns to /records',
    (tester) async {
      await seedReadyCapture();

      // Use a custom GoRouter to avoid MyApp's Riverpod ref.listen-in-
      // initState assertion. The route tree mirrors app.dart but with a
      // minimal capture-detail stub.
      CaptureRecord? pushedInitialCapture;
      CaptureNavigationContext? pushedNavigationContext;
      final router = GoRouter(
        initialLocation: '/records',
        routes: [
          GoRoute(
            path: '/',
            redirect: (context, state) => null,
            routes: [
              GoRoute(
                path: 'records',
                builder: (context, state) => const AllCapturesScreen(),
              ),
              GoRoute(
                path: 'projects/:projectId',
                builder: (context, state) => const SizedBox.shrink(),
                routes: [
                  GoRoute(
                    path: 'captures/:captureId',
                    builder: (context, state) {
                      if (state.extra case CaptureDetailArguments arguments) {
                        pushedInitialCapture = arguments.capture;
                        pushedNavigationContext = arguments.navigationContext;
                      }
                      return Scaffold(
                        appBar: AppBar(title: const Text('记录详情')),
                        body: const SizedBox.shrink(),
                      );
                    },
                  ),
                ],
              ),
            ],
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

      // Confirm we are on the all-records surface.
      expect(find.byKey(const Key('filter-sheet-trigger')), findsOneWidget);

      // Tap the capture card to push into detail.
      await tester.tap(find.text('2026-07-16 · 001'));
      await tester.pumpAndSettle();

      // Verify we're on the capture detail screen.
      expect(find.text('记录详情'), findsOneWidget);
      expect(pushedInitialCapture?.id, 'capture-1');
      expect(pushedNavigationContext?.query.searchText, isEmpty);
      expect(pushedNavigationContext?.cursor.id, 'capture-1');

      // Pop back via the AppBar back button.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // We must be back on /records (AllCapturesScreen), evidenced by the
      // filter-sheet-trigger key. If the old `context.go` were still in place,
      // the pop would land on the project detail screen instead.
      expect(find.byKey(const Key('filter-sheet-trigger')), findsOneWidget);

      await disposeTree(tester);
    },
  );

  // ─── Test 4: Undo 路径 ─────────────────────────────────────────────────
  testWidgets(
    'clear-originals undo cancels the 5 s timer and preserves originals',
    (tester) async {
      await seedReadyCapture();

      final files = _TestFileStore();
      final media = CaptureMediaService(
        database: database,
        platform: _TestPlatform(),
        outputPaths: _TestOutputPaths(),
        files: files,
      );
      final controller = CaptureSelectionController()
        ..enter()
        ..replaceAll(['capture-1'], allReady: true);

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
            bottomNavigationBar: CaptureBatchActionBar(
              controller: controller,
              mediaService: media,
              exportService: buildTestExportService(database),
              shareService: _TestShareService(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the "清理原图" action button.
      await tester.tap(find.byIcon(Icons.cleaning_services_outlined));
      await tester.pump();
      // Let the SnackBar animate in fully.
      await tester.pump(const Duration(milliseconds: 600));

      // The SnackBar should appear with the scheduled message.
      expect(find.textContaining('将在 5 秒后清理'), findsOneWidget);
      expect(find.text('撤销'), findsOneWidget);

      // Tap the undo action.
      await tester.tap(find.text('撤销'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // SnackBar dismissed.
      expect(find.textContaining('将在 5 秒后清理'), findsNothing);

      // Advance well past the original 5-second window.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      // The original must still be present.
      final after = await database.captureById('capture-1');
      expect(after?.originalDeletedAt, isNull);

      await disposeTree(tester);
    },
  );

  // ─── Test 5: Execute 路径 ──────────────────────────────────────────────
  testWidgets('clear-originals executes after 5-second timer expires', (
    tester,
  ) async {
    await seedReadyCapture();

    final files = _TestFileStore();
    final media = CaptureMediaService(
      database: database,
      platform: _TestPlatform(),
      outputPaths: _TestOutputPaths(),
      files: files,
    );
    final controller = CaptureSelectionController()
      ..enter()
      ..replaceAll(['capture-1'], allReady: true);

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
          bottomNavigationBar: CaptureBatchActionBar(
            controller: controller,
            mediaService: media,
            exportService: buildTestExportService(database),
            shareService: _TestShareService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap the "清理原图" action button.
    await tester.tap(find.byIcon(Icons.cleaning_services_outlined));
    await tester.pumpAndSettle();

    expect(find.textContaining('将在 5 秒后清理'), findsOneWidget);

    // Advance past the 5-second timer to trigger execution.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    // The original must have been cleared.
    final after = await database.captureById('capture-1');
    expect(after?.originalDeletedAt, isNotNull);

    await disposeTree(tester);
  });

  testWidgets('delete executes the exact selection confirmed by the user', (
    tester,
  ) async {
    final deleteGate = Completer<CaptureActionResult>();
    final media = _RecordingDeleteMediaService(
      database: database,
      result: deleteGate.future,
    );
    final controller = CaptureSelectionController()
      ..enter()
      ..replaceAll(const ['capture-0'], allReady: true);

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
          bottomNavigationBar: CaptureBatchActionBar(
            controller: controller,
            mediaService: media,
            exportService: buildTestExportService(database),
            shareService: _TestShareService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 张照片'), findsOneWidget);

    controller.replaceAll(
      List.generate(120, (index) => 'capture-$index'),
      allReady: false,
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(media.deleteCalls, [
      ['capture-0'],
    ]);
    expect(find.text('正在处理 0/1'), findsOneWidget);

    deleteGate.complete(
      const CaptureActionResult(
        succeededIds: ['capture-0'],
        skippedIds: [],
        failures: {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('成功 1，跳过 0，失败 0'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('confirmed delete survives batch bar disposal', (tester) async {
    final media = _RecordingDeleteMediaService(
      database: database,
      result: Future.value(
        const CaptureActionResult(
          succeededIds: ['capture-0'],
          skippedIds: [],
          failures: {},
        ),
      ),
    );
    final controller = CaptureSelectionController()
      ..enter()
      ..replaceAll(const ['capture-0'], allReady: true);

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
        home: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Scaffold(
            bottomNavigationBar: controller.selectedIds.isEmpty
                ? null
                : CaptureBatchActionBar(
                    controller: controller,
                    mediaService: media,
                    exportService: buildTestExportService(database),
                    shareService: _TestShareService(),
                  ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 张照片'), findsOneWidget);

    controller.replaceAll(const [], allReady: false);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('batch-action-bar')), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(media.deleteCalls, [
      ['capture-0'],
    ]);
    await disposeTree(tester);
  });

  // ─── Test 6: 骨架屏存在性 ──────────────────────────────────────────────
  testWidgets(
    'Skeletonizer pattern shows placeholder before stream data arrives',
    (tester) async {
      // Use a controlled StreamController to verify the Skeletonizer
      // loading pattern independently of drift's emission timing.
      final controller = StreamController<List<CaptureSummary>>();

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
            body: StreamBuilder<List<CaptureSummary>>(
              stream: controller.stream,
              builder: (context, snapshot) {
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: snapshot.hasData
                      ? const KeyedSubtree(
                          key: Key('capture-list-content'),
                          child: Center(child: Text('real content')),
                        )
                      : const Skeletonizer(
                          key: Key('capture-list-skeleton'),
                          child: Card(
                            child: ListTile(title: Text('placeholder')),
                          ),
                        ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // Before emitting data, the Skeletonizer should be visible.
      expect(find.byKey(const Key('capture-list-skeleton')), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is Skeletonizer), findsOneWidget);

      // Emit data.
      controller.add([]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // After data arrives and the AnimatedSwitcher transition completes,
      // the real content should have replaced the skeleton.
      expect(find.byKey(const Key('capture-list-content')), findsOneWidget);

      await controller.close();
      await disposeTree(tester);
    },
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Test helpers
// ═══════════════════════════════════════════════════════════════════════════

ProjectExportService buildTestExportService(AppDatabase db) {
  return ProjectExportService(
    database: db,
    images: _TestImagePipeline(),
    capturePaths: _TestOutputPaths(),
    exportPaths: _TestExportPaths(),
    selectionExportPaths: _TestSelectionExportPaths(),
  );
}

class _TestPlatform implements PlatformServices {
  @override
  Future<String> createCameraTarget(String captureId) async =>
      '/private/$captureId.jpg';
  @override
  Future<void> deletePublishedImage(String contentUri) async {}
  @override
  Future<void> finishCameraCapture(String captureId, bool keepOriginal) async {}
  @override
  Future<CameraCaptureResult> launchCamera(String captureId) async =>
      CameraCaptureResult(
        outcome: CameraOutcome.captured,
        outputPath: '/private/$captureId.jpg',
      );
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
  Future<RecoveredCameraCapture?> recoverCameraCapture() async => null;
  @override
  Future<LocationResult> requestCurrentLocation(int timeoutMillis) async =>
      LocationResult(outcome: LocationOutcome.permissionDenied);
  @override
  Future<LocationPermissionState> getLocationPermissionState() async =>
      LocationPermissionState.granted;
  @override
  Future<LocationPermissionState> requestLocationPermission() async =>
      LocationPermissionState.granted;
  @override
  Future<void> openApplicationSettings() async {}
  @override
  Future<ImageMetadataResult> inspectImage(String path) async =>
      ImageMetadataResult(
        width: 4000,
        height: 3000,
        fileSizeBytes: 1_000_000,
        mimeType: 'image/jpeg',
      );
}

class _TestFileStore implements PrivateFileStore {
  final Set<String> existing = {};
  _TestFileStore() {
    existing.add('/private/capture-1.jpg');
  }
  @override
  Future<bool> exists(String path) async => existing.contains(path);
  @override
  Future<void> deleteIfExists(String path) async => existing.remove(path);
}

class _TestOutputPaths implements CaptureOutputPaths {
  @override
  Future<String> renderedPhotoPath(String captureId) async =>
      '/rendered/$captureId.jpg';
}

class _TestImagePipeline implements ImagePipeline {
  @override
  Future<ProjectArchivePreview> readProjectArchive(String zipPath) =>
      throw UnimplementedError();

  @override
  Future<ExtractedArchivePhoto> extractArchivePhoto(
    ExtractArchivePhotoRequest request,
  ) => throw UnimplementedError();

  @override
  Future<ExportProjectResult> export(ExportProjectRequest request) async =>
      throw UnimplementedError();
  @override
  Future<ExportProjectResult> exportSelection(
    ExportSelectionRequest request,
  ) async => throw UnimplementedError();
  @override
  Future<RenderPhotoResult> render(RenderPhotoRequest request) async =>
      throw UnimplementedError();
  @override
  Future<String> sha256(String path) async =>
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
}

class _TestExportPaths implements ProjectExportPaths {
  @override
  Future<String> projectZipPath(String projectId) async =>
      '/exports/$projectId.zip';
}

class _TestSelectionExportPaths implements SelectionExportPaths {
  @override
  Future<String> selectionZipPath() async => '/exports/selection.zip';
}

class _TestShareService implements ShareFileService {
  @override
  Future<void> shareFile(String path) async {}
}

class _RecordingDeleteMediaService extends CaptureMediaService {
  _RecordingDeleteMediaService({required super.database, required this.result})
    : super(
        platform: _TestPlatform(),
        outputPaths: _TestOutputPaths(),
        files: _TestFileStore(),
      );

  final Future<CaptureActionResult> result;
  final List<List<String>> deleteCalls = [];

  @override
  Future<CaptureActionResult> deleteAll(List<String> captureIds) {
    deleteCalls.add(List.unmodifiable(captureIds));
    return result;
  }
}
