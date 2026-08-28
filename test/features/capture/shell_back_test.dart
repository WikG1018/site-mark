import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/features/capture/all_captures_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/navigation/root_navigation_scaffold.dart';

/// Regression tests for the root-shell system-back guard.
///
/// The shell claims every system back (see RootNavigationScaffold): branch
/// screens consume backs for selection mode / search / filters through their
/// own PopScopes, and only a back nothing consumed reaches the shell, which
/// then exits the app via [SystemNavigator.pop]. The engine-side predictive
/// back callback must stay registered the whole time, so this suite drives
/// the real `StatefulShellRoute` instead of a bare `MaterialApp` harness.
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

  Future<void> seedReadyCapture() async {
    await database.createProject(id: 'project-1', name: '东区厂房改造');
    final pending = await database.createPendingCapture(
      id: 'capture-1',
      projectId: 'project-1',
      originalPath: '/private/capture-1.jpg',
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
      publishedUri: 'content://media/site-mark/capture-1',
    );
  }

  Future<List<String>> pumpShell(WidgetTester tester) async {
    final platformMethods = <String>[];
    Future<Object?>? record(MethodCall call) async {
      platformMethods.add('${call.method}: ${call.arguments}');
      return null;
    }

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      record,
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    // Resume the lifecycle so WidgetsApp forwards NavigationNotification
    // canHandlePop values to the engine via setFrameworkHandlesBack — the
    // engine-side registration contract the predictive-back path depends on.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    final router = GoRouter(
      initialLocation: '/records',
      routes: [
        StatefulShellRoute(
          builder: (context, state, navigationShell) =>
              RootNavigationScaffold(navigationShell: navigationShell),
          navigatorContainerBuilder: (context, navigationShell, children) =>
              IndexedStack(
                index: navigationShell.currentIndex,
                children: children,
              ),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/records',
                  builder: (context, state) => const AllCapturesScreen(),
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
          onNavigationNotification:
              RootNavigationScaffold.handleSystemBackContract,
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
    return platformMethods;
  }

  testWidgets('system back cancels selection mode instead of exiting', (
    tester,
  ) async {
    await seedReadyCapture();
    final platformMethods = await pumpShell(tester);

    await tester.tap(find.byKey(const Key('edit-captures')));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsWidgets);

    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(handled, isTrue);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byKey(const Key('edit-captures')), findsOneWidget);
    expect(platformMethods.where(_isSystemNavigatorPop), isEmpty);
    _expectEngineKeepsHandlingBack(platformMethods);
    await disposeTree(tester);
  });

  testWidgets('system back closes search before it can exit the app', (
    tester,
  ) async {
    await seedReadyCapture();
    final platformMethods = await pumpShell(tester);

    await tester.tap(find.byKey(const Key('search-captures')));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(handled, isTrue);
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const Key('filter-sheet-trigger')), findsOneWidget);
    expect(platformMethods.where(_isSystemNavigatorPop), isEmpty);
    _expectEngineKeepsHandlingBack(platformMethods);
    await disposeTree(tester);
  });

  testWidgets(
    'system back on the idle root page exits via SystemNavigator.pop',
    (tester) async {
      await seedReadyCapture();
      final platformMethods = await pumpShell(tester);

      final handled = await tester.binding.handlePopRoute();
      await tester.pump();

      // The shell consumed the back and explicitly asked the engine to close
      // the activity — the standard "back exits the app" behavior on a root
      // page, exercised through the same guard that protects selection mode.
      expect(handled, isTrue);
      expect(platformMethods.where(_isSystemNavigatorPop), isNotEmpty);
      _expectEngineKeepsHandlingBack(platformMethods);
      await disposeTree(tester);
    },
  );
}

bool _isSystemNavigatorPop(String platformCall) {
  return platformCall.startsWith('SystemNavigator.pop');
}

/// The shell claims every back, so the framework must tell the engine the
/// app handles system backs at all times — including on an idle root page,
/// where the pre-fix code reported false and left the engine without a
/// predictive-back callback while selection mode re-armed it.
void _expectEngineKeepsHandlingBack(List<String> platformMethods) {
  final handleBackValues = platformMethods
      .where(
        (call) => call.startsWith('SystemNavigator.setFrameworkHandlesBack'),
      )
      .map((call) => call.endsWith(': true'))
      .toList();
  expect(handleBackValues, isNotEmpty);
  expect(handleBackValues, everyElement(isTrue));
}
