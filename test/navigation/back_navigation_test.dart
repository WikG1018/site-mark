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
import 'package:sitemark/features/capture/capture_form_screen.dart';
import 'package:sitemark/features/projects/project_detail_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';
import 'package:sitemark/platform/capture_form_draft_store.dart';
import 'package:sitemark/platform/memory_pressure_coordinator.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/capture_template_service.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

void main() {
  testWidgets(
    'production records route closes filter sheet then clears applied project and date filters',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      await _seedBackFilterRecords(database);
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(database)],
      );
      try {
        final router = container.read(routerProvider);
        await _pumpProductionRouter(
          tester,
          container: container,
          router: router,
          locale: const Locale('en'),
        );
        router.go('/records');
        await _pumpBounded(tester);

        expect(find.byType(AllCapturesScreen), findsOneWidget);
        await tester.tap(find.byKey(const Key('filter-sheet-trigger')));
        await _pumpBounded(tester);
        await tester.tap(find.byKey(const Key('filter-project-project-1')));
        await _pumpBounded(tester);
        await tester.tap(find.byKey(const Key('filter-year-2026')));
        await _pumpBounded(tester);
        await tester.tap(find.byKey(const Key('filter-apply')));
        await _pumpBounded(tester);

        expect(find.byKey(const Key('active-filter-project')), findsOneWidget);
        expect(find.byKey(const Key('active-filter-year')), findsOneWidget);
        expect(find.textContaining('Second project location'), findsNothing);

        await tester.tap(find.byKey(const Key('filter-sheet-trigger')));
        await _pumpBounded(tester);
        expect(find.byKey(const Key('filter-cancel')), findsOneWidget);
        await tester.binding.handlePopRoute();
        await _pumpBounded(tester);
        expect(find.byKey(const Key('filter-cancel')), findsNothing);
        expect(find.byKey(const Key('active-filter-project')), findsOneWidget);

        // With a filter applied the back is consumed: the router delegate
        // answers true (the app stays open) and the filter is cleared below.
        expect(await tester.binding.handlePopRoute(), isTrue);
        await _pumpBounded(tester);
        await _pumpUntilFound(
          tester,
          find.textContaining('Second project location'),
        );
        expect(find.byKey(const Key('active-filter-project')), findsNothing);
        expect(find.byKey(const Key('active-filter-year')), findsNothing);
        expect(find.textContaining('Second project location'), findsOneWidget);
        expect(router.routeInformationProvider.value.uri.path, '/records');
        // Nothing left to consume: the back interception is disarmed again.
        expect(_screenPopScope(tester, AllCapturesScreen).canPop, isTrue);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        container.dispose();
        await tester.pump(const Duration(milliseconds: 1));
        await tester.runAsync(database.close);
      }
    },
  );

  testWidgets(
    'system back in filtered selection exits selection then clears filter without exiting the app',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      await _seedBackFilterRecords(database);
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(database)],
      );
      try {
        final router = container.read(routerProvider);
        await _pumpProductionRouter(
          tester,
          container: container,
          router: router,
          locale: const Locale('en'),
        );
        router.go('/records');
        await _pumpBounded(tester);

        await tester.tap(find.byKey(const Key('filter-sheet-trigger')));
        await _pumpBounded(tester);
        await tester.tap(find.byKey(const Key('filter-project-project-1')));
        await _pumpBounded(tester);
        await tester.tap(find.byKey(const Key('filter-apply')));
        await _pumpBounded(tester);
        expect(find.byKey(const Key('active-filter-project')), findsOneWidget);

        // Enter selection mode: the batch action bar replaces the root dock.
        await tester.tap(find.byKey(const Key('edit-captures')));
        await _pumpBounded(tester);
        expect(find.byKey(const Key('batch-bar')), findsOneWidget);

        // System back exits selection only — the filter stays applied and the
        // app stays open (regression: the back used to finish the activity).
        expect(await tester.binding.handlePopRoute(), isTrue);
        await _pumpBounded(tester);
        expect(find.byKey(const Key('batch-bar')), findsNothing);
        expect(find.byKey(const Key('active-filter-project')), findsOneWidget);
        expect(find.byType(AllCapturesScreen), findsOneWidget);
        expect(router.routeInformationProvider.value.uri.path, '/records');

        // Next back clears the filter, again without exiting.
        expect(await tester.binding.handlePopRoute(), isTrue);
        await _pumpBounded(tester);
        expect(find.byKey(const Key('active-filter-project')), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        container.dispose();
        await tester.pump(const Duration(milliseconds: 1));
        await tester.runAsync(database.close);
      }
    },
  );

  testWidgets(
    'production project route clears an applied date filter before navigating back in Chinese',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      await _seedBackFilterRecords(database);
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(database)],
      );
      try {
        final router = container.read(routerProvider);
        await _pumpProductionRouter(
          tester,
          container: container,
          router: router,
          locale: const Locale('zh'),
        );
        unawaited(router.push('/projects/project-1'));
        await _pumpBounded(tester);

        expect(find.byType(ProjectDetailScreen), findsOneWidget);
        await tester.tap(find.byKey(const Key('filter-year')));
        await _pumpBounded(tester);
        await tester.tap(find.text('2026'));
        await _pumpBounded(tester);
        expect(find.textContaining('2025 project location'), findsNothing);

        expect(_screenPopScope(tester, ProjectDetailScreen).canPop, isFalse);
        await tester.binding.handlePopRoute();
        await _pumpBounded(tester);
        await _pumpUntilFound(
          tester,
          find.textContaining('2025 project location'),
        );
        expect(find.byType(ProjectDetailScreen), findsOneWidget);
        expect(find.text('全部年份'), findsOneWidget);
        expect(find.textContaining('2025 project location'), findsOneWidget);
        expect(_screenPopScope(tester, ProjectDetailScreen).canPop, isTrue);
        await tester.binding.handlePopRoute();
        await _pumpBounded(tester);
        expect(find.byType(ProjectDetailScreen), findsNothing);
        expect(router.routeInformationProvider.value.uri.path, '/');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        container.dispose();
        await tester.pump(const Duration(milliseconds: 1));
        await tester.runAsync(database.close);
      }
    },
  );

  testWidgets(
    'system back returns from project detail then closes preserved search',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      await database.createProject(id: 'project-1', name: 'Project');
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(database)],
      );
      try {
        final router = container.read(routerProvider);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              locale: const Locale('en'),
              supportedLocales: AppStrings.supportedLocales,
              localizationsDelegates: const [
                AppStrings.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
              ],
              routerConfig: router,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(AppMotion.pageTransition);
        await tester.pump(const Duration(milliseconds: 1));
        expect(find.text('Projects'), findsOneWidget);
        await tester.tap(find.byKey(const Key('search-projects')));
        await tester.pump();
        expect(find.byKey(const Key('project-search-field')), findsOneWidget);

        unawaited(router.push('/projects/project-1'));
        await tester.pump();
        await tester.pump(AppMotion.pageTransition);
        await tester.pump();
        expect(find.byType(ProjectDetailScreen), findsOneWidget);
        expect(find.byKey(const Key('root-dock')), findsNothing);

        await tester.tap(find.byKey(const Key('project-actions')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('project-action-sheet')), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('project-action-sheet')), findsNothing);
        expect(find.byType(ProjectDetailScreen), findsOneWidget);

        await tester.tap(find.byKey(const Key('search-captures')));
        await tester.pump();
        expect(find.byKey(const Key('capture-search-field')), findsOneWidget);

        await tester.tap(find.byKey(const Key('edit-captures')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('select-all-captures')), findsOneWidget);
        expect(find.byKey(const Key('capture-search-field')), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('select-all-captures')), findsNothing);
        expect(find.byKey(const Key('capture-search-field')), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('capture-search-field')), findsNothing);
        expect(find.byType(ProjectDetailScreen), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pump();
        await tester.pump(AppMotion.pageTransition);
        await tester.pump(const Duration(milliseconds: 1));
        expect(router.routeInformationProvider.value.uri.path, '/');
        expect(find.byType(ProjectDetailScreen), findsNothing);
        expect(find.byKey(const Key('root-dock')), findsOneWidget);
        expect(find.byKey(const Key('project-search-field')), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pump();
        await tester.pump(AppMotion.short4);
        await tester.pump();
        expect(find.byKey(const Key('project-search-field')), findsNothing);
        expect(find.byKey(const Key('root-dock')), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        container.dispose();
        await tester.pump(const Duration(milliseconds: 1));
        await tester.runAsync(database.close);
      }
    },
  );

  testWidgets(
    'system back closes confirmation then template sheet then capture page',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.createProject(id: 'project-1', name: 'Project');
      final template = await CaptureTemplateService(database: database).create(
        projectId: 'project-1',
        name: 'Template',
        workLocation: 'Location',
        workContent: 'Content',
        photographer: 'Photographer',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            captureFormDraftStoreProvider.overrideWithValue(
              MemoryCaptureFormDraftStore(),
            ),
            memoryPressureControllerProvider.overrideWithValue(
              MemoryPressureController(),
            ),
            platformServicesProvider.overrideWithValue(_BackPlatform()),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [
              AppStrings.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: Builder(
              builder: (context) => Scaffold(
                body: FilledButton(
                  key: const Key('open-capture-page'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const CaptureFormScreen(projectId: 'project-1'),
                    ),
                  ),
                  child: const Text('Origin page'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open-capture-page')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('capture-template-button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(Key('capture-template-delete-${template.id}')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byKey(const Key('capture-template-sheet')), findsOneWidget);
      expect(find.byType(CaptureFormScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const Key('capture-template-sheet')), findsOneWidget);
      expect(find.byType(CaptureFormScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('capture-template-sheet')), findsNothing);
      expect(find.byType(CaptureFormScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(CaptureFormScreen), findsNothing);
      expect(find.byKey(const Key('open-capture-page')), findsOneWidget);
    },
  );
}

Future<void> _pumpProductionRouter(
  WidgetTester tester, {
  required ProviderContainer container,
  required GoRouter router,
  required Locale locale,
}) async {
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
        routerConfig: router,
      ),
    ),
  );
  await _pumpBounded(tester);
}

Future<void> _pumpBounded(WidgetTester tester) async {
  await tester.pump();
  for (var frame = 0; frame < 12; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var frame = 0; frame < 40 && finder.evaluate().isEmpty; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

PopScope<dynamic> _screenPopScope(WidgetTester tester, Type screenType) {
  final screen = find.byType(screenType);
  final scope = find.descendant(
    of: screen,
    matching: find.byWidgetPredicate((widget) => widget is PopScope),
  );
  return tester.widget<PopScope<dynamic>>(scope);
}

Future<void> _seedBackFilterRecords(AppDatabase database) async {
  await database.createProject(id: 'project-1', name: 'First project');
  await database.createProject(id: 'project-2', name: 'Second project');

  Future<void> seed({
    required String id,
    required String projectId,
    required String location,
    required DateTime capturedAt,
  }) async {
    final pending = await database.createPendingCapture(
      id: id,
      projectId: projectId,
      originalPath: '/private/$id.jpg',
      workLocation: location,
      workContent: 'Inspection',
      photographer: 'Inspector',
      watermarkLocaleCode: 'en',
      locationResolution: 'resolved',
    );
    await database.markCaptured(captureId: pending.id, capturedAt: capturedAt);
  }

  await seed(
    id: 'capture-2026',
    projectId: 'project-1',
    location: '2026 project location',
    capturedAt: DateTime(2026, 8, 5, 9),
  );
  await seed(
    id: 'capture-2025',
    projectId: 'project-1',
    location: '2025 project location',
    capturedAt: DateTime(2025, 8, 5, 9),
  );
  await seed(
    id: 'capture-project-2',
    projectId: 'project-2',
    location: 'Second project location',
    capturedAt: DateTime(2026, 8, 5, 10),
  );
}

class _BackPlatform implements PlatformServices {
  @override
  Future<String> createCameraTarget(String captureId) async => '/$captureId';

  @override
  Future<void> deletePublishedImage(String contentUri) async {}

  @override
  Future<void> finishCameraCapture(String captureId, bool keepOriginal) async {}

  @override
  Future<LocationPermissionState> getLocationPermissionState() async =>
      LocationPermissionState.granted;

  @override
  Future<ImageMetadataResult> inspectImage(String path) async =>
      ImageMetadataResult(
        width: 0,
        height: 0,
        fileSizeBytes: 0,
        mimeType: 'image/jpeg',
      );

  @override
  Future<CameraCaptureResult> launchCamera(String captureId) async =>
      CameraCaptureResult(
        outcome: CameraOutcome.cancelled,
        outputPath: '/$captureId',
      );

  @override
  Future<void> openApplicationSettings() async {}

  @override
  Future<PublishJpegOutcome> publishJpeg(
    String sourcePath,
    String displayName,
    String captureId,
    String? publishedUri,
  ) async => const PublishJpegOutcome(contentUri: '');

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
      LocationResult(outcome: LocationOutcome.unavailable);

  @override
  Future<LocationPermissionState> requestLocationPermission() async =>
      LocationPermissionState.granted;
}
