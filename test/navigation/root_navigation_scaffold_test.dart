import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/features/capture/all_captures_screen.dart';
import 'package:sitemark/features/projects/project_detail_screen.dart';
import 'package:sitemark/features/projects/project_list_screen.dart';
import 'package:sitemark/features/settings/global_settings_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';
import 'package:sitemark/navigation/root_chrome_controller.dart';
import 'package:sitemark/navigation/root_navigation_scaffold.dart';

void main() {
  late AppDatabase database;
  late ProviderContainer container;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.createProject(id: 'project-1', name: 'Project 1');
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
  });

  Future<GoRouter> pumpRouter(WidgetTester tester) async {
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
    await tester.pump();
    await tester.pump(AppMotion.pageTransition);
    await tester.pump();
    return router;
  }

  Future<void> runWithRouter(
    WidgetTester tester,
    Future<void> Function(GoRouter router) body,
  ) async {
    GoRouter? router;
    try {
      router = await pumpRouter(tester);
      await body(router);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      container.dispose();
      // Drift schedules a zero-duration cleanup timer when the last watched
      // query is cancelled. Flush it before Flutter checks test invariants.
      await tester.pump(const Duration(milliseconds: 1));
      await tester.runAsync(database.close);
    }
  }

  double renderedBranchOpacity(WidgetTester tester, Key branchKey) {
    final animatedOpacity = find.ancestor(
      of: find.byKey(branchKey),
      matching: find.byType(AnimatedOpacity),
    );
    expect(animatedOpacity, findsOneWidget);
    final fadeTransition = find.descendant(
      of: animatedOpacity,
      matching: find.byType(FadeTransition),
    );
    expect(fadeTransition, findsOneWidget);
    return tester.widget<FadeTransition>(fadeTransition).opacity.value;
  }

  Future<void> expectCompletedReverseTransition(
    WidgetTester tester, {
    required int fromIndex,
  }) async {
    Widget buildContainer(int currentIndex) => MaterialApp(
      home: RootBranchContainer(
        currentIndex: currentIndex,
        children: const [
          SizedBox(key: Key('opacity-branch-0')),
          SizedBox(key: Key('opacity-branch-1')),
          SizedBox(key: Key('opacity-branch-2')),
        ],
      ),
    );

    await runWithRouter(tester, (_) async {
      await tester.pumpWidget(buildContainer(fromIndex));
      expect(
        renderedBranchOpacity(tester, Key('opacity-branch-$fromIndex')),
        1,
      );

      await tester.pumpWidget(buildContainer(0));
      await tester.pump(AppMotion.rootSwitch);
      await tester.pump();

      expect(renderedBranchOpacity(tester, const Key('opacity-branch-0')), 1);
      expect(renderedBranchOpacity(tester, const Key('opacity-branch-1')), 0);
      expect(renderedBranchOpacity(tester, const Key('opacity-branch-2')), 0);
    });
  }

  testWidgets('dock switches three preserved root branches', (tester) async {
    await runWithRouter(tester, (_) async {
      expect(find.byKey(const Key('root-dock')), findsOneWidget);
      expect(find.text('项目'), findsOneWidget);
      expect(find.byType(ProjectListScreen), findsOneWidget);
      expect(find.byKey(const Key('new-project-fab')), findsOneWidget);

      await tester.tap(find.byKey(const Key('root-destination-records')));
      await tester.pump();
      await tester.pump(AppMotion.rootSwitch);
      await tester.pump();
      expect(find.byType(AllCapturesScreen), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      expect(find.byKey(const Key('new-project-fab')), findsNothing);

      await tester.tap(find.byKey(const Key('root-destination-settings')));
      await tester.pump();
      await tester.pump(AppMotion.rootSwitch);
      await tester.pump();
      expect(find.byType(GlobalSettingsScreen), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );
    });
  });

  testWidgets('root dock overlays content and selection mode hides it', (
    tester,
  ) async {
    await runWithRouter(tester, (_) async {
      await tester.tap(find.byKey(const Key('root-destination-records')));
      await tester.pumpAndSettle();
      final rootScaffold = tester.widget<Scaffold>(
        find.ancestor(
          of: find.byKey(const Key('root-dock')),
          matching: find.byType(Scaffold),
        ),
      );
      expect(rootScaffold.bottomNavigationBar, isNull);

      container.read(allCapturesSelectionModeProvider.notifier).setActive(true);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('root-dock')), findsNothing);

      container
          .read(allCapturesSelectionModeProvider.notifier)
          .setActive(false);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('root-dock')), findsOneWidget);
    });
  });

  testWidgets('switching branches preserves project search state', (
    tester,
  ) async {
    await runWithRouter(tester, (_) async {
      await tester.tap(find.byKey(const Key('search-projects')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('project-search-field')),
        'Project 1',
      );

      await tester.tap(find.byKey(const Key('root-destination-records')));
      await tester.pump();
      await tester.pump(AppMotion.rootSwitch);
      await tester.pump();
      await tester.tap(find.byKey(const Key('root-destination-projects')));
      await tester.pump();
      await tester.pump(AppMotion.rootSwitch);
      await tester.pump();

      expect(find.byKey(const Key('project-search-field')), findsOneWidget);
      expect(find.text('Project 1'), findsWidgets);
    });
  });

  testWidgets('secondary routes hide dock', (tester) async {
    await runWithRouter(tester, (router) async {
      router.go('/projects/project-1');
      await tester.pump();
      await tester.pump(AppMotion.pageTransition);
      await tester.pump();

      expect(find.byType(ProjectDetailScreen), findsOneWidget);
      expect(find.byKey(const Key('root-dock')), findsNothing);
    });
  });

  testWidgets('inactive root branches disable ticks, taps, and semantics', (
    tester,
  ) async {
    await runWithRouter(tester, (_) async {
      var activeTaps = 0;
      var inactiveTaps = 0;
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: RootBranchContainer(
              currentIndex: 0,
              children: [
                Center(
                  child: FilledButton(
                    key: const Key('active-branch-action'),
                    onPressed: () => activeTaps += 1,
                    child: const Text('Active action'),
                  ),
                ),
                Align(
                  alignment: Alignment.topLeft,
                  child: FilledButton(
                    key: const Key('inactive-branch-action'),
                    onPressed: () => inactiveTaps += 1,
                    child: const Text('Inactive action'),
                  ),
                ),
              ],
            ),
          ),
        );

        final inactiveTickerModes = find
            .ancestor(
              of: find.byKey(const Key('inactive-branch-action')),
              matching: find.byType(TickerMode),
            )
            .evaluate()
            .map((element) => element.widget)
            .whereType<TickerMode>();
        expect(inactiveTickerModes.any((ticker) => !ticker.enabled), isTrue);
        expect(find.bySemanticsLabel('Active action'), findsOneWidget);
        expect(find.bySemanticsLabel('Inactive action'), findsNothing);

        await tester.tap(find.byKey(const Key('active-branch-action')));
        await tester.tap(
          find.byKey(const Key('inactive-branch-action')),
          warnIfMissed: false,
        );
        expect(activeTaps, 1);
        expect(inactiveTaps, 0);
      } finally {
        semantics.dispose();
      }
    });
  });

  testWidgets('switching branch 2 to 0 completes both opacity transitions', (
    tester,
  ) async {
    await expectCompletedReverseTransition(tester, fromIndex: 2);
  });

  testWidgets('switching branch 1 to 0 completes both opacity transitions', (
    tester,
  ) async {
    await expectCompletedReverseTransition(tester, fromIndex: 1);
  });
}
