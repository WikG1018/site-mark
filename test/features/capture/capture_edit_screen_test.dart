import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/background/capture_background_scheduler.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/features/capture/capture_edit_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/capture_location_coordinator.dart';
import 'package:sitemark/workflow/capture_workflow.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  Future<void> pumpEdit(
    WidgetTester tester, {
    required String captureId,
    CaptureWorkflow? workflow,
    Locale locale = const Locale('zh'),
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          if (workflow != null)
            captureWorkflowProvider.overrideWithValue(workflow),
        ],
        child: MaterialApp(
          locale: locale,
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: CaptureEditScreen(projectId: 'project-1', captureId: captureId),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('missing capture shows not-found instead of a spinner', (
    tester,
  ) async {
    await pumpEdit(tester, captureId: 'missing');

    expect(find.byKey(const Key('capture-not-found')), findsOneWidget);
    expect(find.text('拍摄记录不存在或已删除'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('capture lookup error shows an explicit load-failed state', (
    tester,
  ) async {
    final failing = _ThrowingCaptureDatabase();
    addTearDown(failing.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(failing)],
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const CaptureEditScreen(
            projectId: 'project-1',
            captureId: 'capture-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('capture-load-error')), findsOneWidget);
    expect(
      find.text(AppStrings(const Locale('en')).captureLoadFailed),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('successful save pops back to the previous route', (
    tester,
  ) async {
    await database.createProject(id: 'project-1', name: '东区厂房改造');
    final pending = await database.createPendingCapture(
      id: 'capture-1',
      projectId: 'project-1',
      originalPath: '/private/original.jpg',
      workLocation: 'A 区',
      workContent: '风管检查',
      photographer: '张工',
      watermarkLocaleCode: 'zh',
    );
    await database.markCaptured(
      captureId: pending.id,
      capturedAt: DateTime(2026, 8, 4, 9),
    );
    await database.markRendering(
      captureId: pending.id,
      originalSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    await database.markReady(
      captureId: pending.id,
      publishedUri: 'content://media/site-mark/1',
    );
    final workflow = _StubCaptureWorkflow(database);
    final router = GoRouter(
      initialLocation: '/records',
      routes: [
        GoRoute(
          path: '/records',
          builder: (context, state) => const Scaffold(
            body: Text('all-records', key: Key('all-records')),
          ),
          routes: [
            GoRoute(
              path: 'edit',
              builder: (context, state) => const CaptureEditScreen(
                projectId: 'project-1',
                captureId: 'capture-1',
              ),
            ),
          ],
        ),
        GoRoute(
          path: '/projects/:projectId/captures/:captureId',
          builder: (context, state) => const Scaffold(
            body: Text('detail-fallback', key: Key('detail-fallback')),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          captureWorkflowProvider.overrideWithValue(workflow),
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
    await router.push('/records/edit');
    await tester.pumpAndSettle();

    await tester.tap(find.text('重新生成水印'));
    await tester.pumpAndSettle();

    expect(workflow.regenerateCalls, 1);
    expect(find.byKey(const Key('all-records')), findsOneWidget);
    expect(find.byKey(const Key('detail-fallback')), findsNothing);
    expect(find.byType(CaptureEditScreen), findsNothing);
  });
}

class _ThrowingCaptureDatabase extends AppDatabase {
  _ThrowingCaptureDatabase() : super.forTesting(NativeDatabase.memory());

  @override
  Future<CaptureRecord?> captureById(String captureId) {
    return Future<CaptureRecord?>.error(StateError('lookup failed'));
  }
}

class _StubCaptureWorkflow implements CaptureWorkflow {
  _StubCaptureWorkflow(this.database);

  @override
  final AppDatabase database;
  var regenerateCalls = 0;

  @override
  PlatformServices get platform => throw UnimplementedError();

  @override
  CaptureBackgroundScheduler get scheduler => throw UnimplementedError();

  @override
  ImagePipeline get images => throw UnimplementedError();

  @override
  CaptureOutputPaths get outputPaths => throw UnimplementedError();

  @override
  CaptureLocationCoordinator get locationCoordinator =>
      throw UnimplementedError();

  @override
  CaptureLaunchTimingCallback? get onLaunchTiming => null;

  @override
  Future<CaptureWorkflowResult> capture(CaptureDraft draft) {
    throw UnimplementedError();
  }

  @override
  Future<CaptureWorkflowResult?> recoverPendingCapture() {
    throw UnimplementedError();
  }

  @override
  Future<CaptureRecord> regenerateCapture({
    required String captureId,
    required CaptureEdits edits,
  }) async {
    regenerateCalls += 1;
    return (await database.captureById(captureId))!;
  }

  @override
  Future<void> deleteCapture(String captureId) {
    throw UnimplementedError();
  }
}
