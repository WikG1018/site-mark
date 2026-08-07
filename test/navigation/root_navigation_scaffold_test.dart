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

  Widget buildBranchContainer(
    int currentIndex, {
    bool disableAnimations = false,
  }) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: disableAnimations),
      child: child!,
    ),
    home: RootBranchContainer(
      currentIndex: currentIndex,
      children: const [
        SizedBox(key: Key('indexed-branch-0')),
        SizedBox(key: Key('indexed-branch-1')),
        SizedBox(key: Key('indexed-branch-2')),
      ],
    ),
  );

  Offstage branchOffstage(WidgetTester tester, int index) =>
      tester.widget<Offstage>(
        find.byKey(Key('root-branch-offstage-$index'), skipOffstage: false),
      );

  FractionalTranslation branchTranslation(WidgetTester tester, int index) =>
      tester.widget<FractionalTranslation>(
        find.byKey(Key('root-branch-translation-$index'), skipOffstage: false),
      );

  void expectRecordsBranchOffstage(WidgetTester tester) {
    expect(find.byType(AllCapturesScreen, skipOffstage: false), findsOneWidget);
    expect(branchOffstage(tester, 1).offstage, isTrue);
  }

  Future<void> expectDirectionalBranchSwitch(
    WidgetTester tester, {
    required int fromIndex,
    required int toIndex,
  }) async {
    await runWithRouter(tester, (_) async {
      await tester.pumpWidget(buildBranchContainer(fromIndex));
      await tester.pumpWidget(buildBranchContainer(toIndex));
      // Emphasized curve front-loads motion; sample early while both pages
      // still share the viewport under a full-width pan.
      await tester.pump(const Duration(milliseconds: 16));

      final direction = toIndex > fromIndex ? 1 : -1;
      final fromDx =
          branchTranslation(tester, fromIndex).translation.dx * direction;
      final toDx =
          branchTranslation(tester, toIndex).translation.dx * direction;

      // Source slides opposite the switch direction; destination enters with it.
      expect(fromDx, lessThan(0));
      expect(toDx, greaterThan(0));
      // Full-width pan: translation is a fraction of one screen width.
      expect(fromDx.abs(), lessThanOrEqualTo(1.0));
      expect(toDx, lessThanOrEqualTo(1.0));
      // Outgoing and incoming stay edge-to-edge (one continuous take).
      // from = -progress, to = 1 - progress  =>  from + to == 0? No:
      // fromDx = -progress (signed by direction already applied),
      // toDx   = (1 - progress)  =>  fromDx + toDx == 1 - 2*progress.
      // Edge-to-edge means |from| + |to| == 1.0.
      expect(fromDx.abs() + toDx, closeTo(1.0, 0.001));

      await tester.pumpAndSettle();
      expect(branchOffstage(tester, fromIndex).offstage, isTrue);
      expect(branchOffstage(tester, toIndex).offstage, isFalse);
      expect(branchTranslation(tester, toIndex).translation, Offset.zero);
    });
  }

  // Regression: rapid dock switching (0→1→2) must not snap the intermediate
  // page back to center, and must not leave a background gap on the left.
  // Before the fix, _controller.forward(from: 0) reset the animation, causing
  // branch 1 to jump from its mid-slide offset to 0 before branch 2 began
  // entering; branch 0 was also offstaged immediately even though it still
  // covered the left half of the viewport, briefly exposing the scaffold
  // background. The interruptible animation continues each page from its
  // actual on-screen position and keeps on-screen pages visible until they
  // exit.
  testWidgets(
    'rapid dock switch keeps viewport covered and does not snap to center',
    (tester) async {
      await tester.pumpWidget(buildBranchContainer(0));
      await tester.pump();

      // Start 0→1 transition.
      await tester.pumpWidget(buildBranchContainer(1));
      await tester.pump(const Duration(milliseconds: 16));

      // Branch 1 is mid-slide; record its position.
      final midSlideDx = branchTranslation(tester, 1).translation.dx;
      expect(midSlideDx, greaterThan(0));
      expect(midSlideDx, lessThan(1));

      // Interrupt with 1→2 before the first animation finishes.
      await tester.pumpWidget(buildBranchContainer(2));
      await tester.pump(const Duration(milliseconds: 16));

      // Branch 1 (now the outgoing page) must NOT have snapped to 0.
      // It should be at or beyond its mid-slide position, sliding out.
      final interruptedDx = branchTranslation(tester, 1).translation.dx;
      expect(
        interruptedDx,
        lessThanOrEqualTo(midSlideDx),
        reason:
            'Branch 1 must continue sliding out from its mid-slide '
            'position, not snap back to center (0).',
      );

      // Branch 2 should be entering from the right.
      final branch2Dx = branchTranslation(tester, 2).translation.dx;
      expect(branch2Dx, greaterThan(0));
      expect(branch2Dx, lessThanOrEqualTo(1));

      // Branch 0 (the old "from") must stay visible while still on-screen,
      // otherwise the left side of the viewport would show the scaffold
      // background through the gap branch 1 leaves behind.
      expect(
        branchOffstage(tester, 0).offstage,
        isFalse,
        reason:
            'Branch 0 must remain visible mid-interrupt to cover the '
            'viewport left side.',
      );
      final branch0Dx = branchTranslation(tester, 0).translation.dx;
      expect(
        branch0Dx,
        lessThanOrEqualTo(0),
        reason: 'Branch 0 should be on the left side, exiting.',
      );
      expect(
        branch0Dx,
        greaterThan(-1),
        reason: 'Branch 0 should still be partially on-screen.',
      );

      // The visible pages must together cover the full [0,1] viewport with
      // no gap: adjacent pages sit one screen-width apart (|dx1 - dx0| <= 1).
      expect(
        (branchTranslation(tester, 1).translation.dx - branch0Dx).abs(),
        lessThanOrEqualTo(1.0),
        reason:
            'Branches 0 and 1 must stay edge-to-edge so no background '
            'gap appears between them.',
      );

      // Let the animation finish.
      await tester.pumpAndSettle();
      expect(branchOffstage(tester, 1).offstage, isTrue);
      expect(branchOffstage(tester, 2).offstage, isFalse);
      expect(branchTranslation(tester, 2).translation, Offset.zero);
    },
  );

  // Regression: reverse jump (0->2->1) must not send the old "from" page
  // (branch 0, on the left) across the screen to the right. Before the fix,
  // the exit target for "other" on-screen pages used `-direction`, which for
  // a reverse jump (direction = -1) became +1 — sending branch 0 from its
  // left-side exit position across the viewport into branch 1's entry path.
  // The exit direction must follow the page's current side: left page exits
  // left, right page exits right.
  testWidgets('reverse jump does not send outgoing page across the screen', (
    tester,
  ) async {
    await tester.pumpWidget(buildBranchContainer(0));
    await tester.pump();

    // Start 0→2 transition (skip branch 1).
    await tester.pumpWidget(buildBranchContainer(2));
    await tester.pump(const Duration(milliseconds: 16));

    // Branch 0 is exiting left; record its position.
    final branch0MidDx = branchTranslation(tester, 0).translation.dx;
    expect(
      branch0MidDx,
      lessThan(0),
      reason: 'Branch 0 should be on the left, exiting.',
    );

    // Interrupt with 2→1 (reverse direction) before the first animation
    // finishes.
    await tester.pumpWidget(buildBranchContainer(1));
    await tester.pump(const Duration(milliseconds: 16));

    // Branch 0 must still be on the left and moving further left — NOT
    // crossing to the right side.
    final branch0InterruptDx = branchTranslation(tester, 0).translation.dx;
    expect(
      branch0InterruptDx,
      lessThanOrEqualTo(0),
      reason: 'Branch 0 must stay on the left side after reverse jump.',
    );
    expect(
      branch0InterruptDx,
      lessThanOrEqualTo(branch0MidDx),
      reason:
          'Branch 0 must continue exiting left, not reverse direction '
          'and cross the screen to the right.',
    );

    // Branch 2 (outgoing) exits right.
    final branch2Dx = branchTranslation(tester, 2).translation.dx;
    expect(
      branch2Dx,
      greaterThanOrEqualTo(0),
      reason: 'Branch 2 should be on the right, exiting.',
    );

    // Branch 1 (incoming) enters from the left.
    final branch1Dx = branchTranslation(tester, 1).translation.dx;
    expect(
      branch1Dx,
      lessThanOrEqualTo(0),
      reason: 'Branch 1 should enter from the left.',
    );

    // Let the animation finish.
    await tester.pumpAndSettle();
    expect(branchOffstage(tester, 0).offstage, isTrue);
    expect(branchOffstage(tester, 2).offstage, isTrue);
    expect(branchOffstage(tester, 1).offstage, isFalse);
    expect(branchTranslation(tester, 1).translation, Offset.zero);
  });

  testWidgets('dock switches three preserved root branches', (tester) async {
    await runWithRouter(tester, (_) async {
      expect(find.byKey(const Key('root-dock')), findsOneWidget);
      expect(find.text('项目'), findsOneWidget);
      expect(find.byType(ProjectListScreen), findsOneWidget);
      expect(find.byKey(const Key('new-project-fab')), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(
        find.byKey(const Key('root-dock-glass-indicator')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('root-destination-records')));
      await tester.pump();
      await tester.pump(AppMotion.rootSwitch);
      await tester.pump();
      expect(find.byType(AllCapturesScreen), findsOneWidget);
      expect(
        find.byKey(const Key('root-dock-glass-indicator')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('new-project-fab')), findsNothing);

      await tester.tap(find.byKey(const Key('root-destination-settings')));
      await tester.pump();
      await tester.pump(AppMotion.rootSwitch);
      await tester.pump();
      expect(find.byType(GlobalSettingsScreen), findsOneWidget);
      expect(
        find.byKey(const Key('root-dock-glass-indicator')),
        findsOneWidget,
      );
    });
  });

  testWidgets('project detail stays inside the projects branch navigator', (
    tester,
  ) async {
    await runWithRouter(tester, (_) async {
      await tester.tap(find.byKey(const Key('root-destination-records')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('root-destination-projects')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('project-card-project-1')));
      await tester.pumpAndSettle();

      final detailContext = tester.element(find.byType(ProjectDetailScreen));
      expect(
        Navigator.of(detailContext),
        isNot(same(rootNavigatorKey.currentState)),
      );
    });
  });

  testWidgets(
    'records never paint while project detail returns after a dock round trip',
    (tester) async {
      await runWithRouter(tester, (router) async {
        await tester.tap(find.byKey(const Key('root-destination-records')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('root-destination-projects')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('project-card-project-1')));
        await tester.pumpAndSettle();

        router.pop();
        await tester.pump();
        expectRecordsBranchOffstage(tester);
        await tester.pump(AppMotion.pageTransition ~/ 2);
        expectRecordsBranchOffstage(tester);
        await tester.pumpAndSettle();
        expectRecordsBranchOffstage(tester);
      });
    },
  );

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

  testWidgets('all-records selection replaces the root dock in place', (
    tester,
  ) async {
    await runWithRouter(tester, (_) async {
      await tester.tap(find.byKey(const Key('root-destination-records')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('root-dock')), findsOneWidget);

      await tester.tap(find.byKey(const Key('edit-captures')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('root-dock')), findsNothing);
      expect(find.byKey(const Key('batch-action-bar')), findsOneWidget);

      await tester.tap(find.byKey(const Key('edit-captures')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('batch-action-bar')), findsNothing);
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
      // Real product path: project list push, not go().
      unawaited(router.push('/projects/project-1'));
      await tester.pump();
      await tester.pump(AppMotion.pageTransition);
      await tester.pump();

      expect(find.byType(ProjectDetailScreen), findsOneWidget);
      // Imperative push keeps routeInformationProvider.uri on '/'. Dock must
      // still hide based on the real top route, not that stale URI.
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(
        RootNavigationScaffold.visiblePathOf(router),
        '/projects/project-1',
      );
      expect(find.byKey(const Key('root-dock')), findsNothing);
      expect(find.byKey(const ValueKey('capture-fab')), findsOneWidget);
    });
  });

  testWidgets(
    'returning from capture detail keeps home dock off project detail',
    (tester) async {
      await runWithRouter(tester, (router) async {
        unawaited(router.push('/projects/project-1'));
        await tester.pump();
        await tester.pump(AppMotion.pageTransition);
        await tester.pump();
        expect(find.byKey(const Key('root-dock')), findsNothing);
        expect(find.byKey(const ValueKey('capture-fab')), findsOneWidget);

        // Capture detail is a root-navigator route. Returning must restore
        // project chrome only — never the home dock.
        unawaited(router.push('/projects/project-1/captures/capture-missing'));
        await tester.pump();
        await tester.pump(AppMotion.pageTransition);
        await tester.pump();
        expect(find.byKey(const Key('root-dock')), findsNothing);
        // Provider URI may still look like the shell root during push stack.
        expect(
          RootNavigationScaffold.visiblePathOf(router),
          contains('/captures/'),
        );

        router.pop();
        await tester.pump();
        await tester.pump(AppMotion.pageTransition);
        await tester.pump();

        expect(
          RootNavigationScaffold.visiblePathOf(router),
          '/projects/project-1',
        );
        expect(find.byType(ProjectDetailScreen), findsOneWidget);
        expect(find.byKey(const Key('root-dock')), findsNothing);
        expect(find.byKey(const ValueKey('capture-fab')), findsOneWidget);
      });
    },
  );

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
              of: find.byKey(
                const Key('inactive-branch-action'),
                skipOffstage: false,
              ),
              matching: find.byType(TickerMode, skipOffstage: false),
            )
            .evaluate()
            .map((element) => element.widget)
            .whereType<TickerMode>();
        expect(inactiveTickerModes.any((ticker) => !ticker.enabled), isTrue);
        expect(find.bySemanticsLabel('Active action'), findsOneWidget);
        expect(find.bySemanticsLabel('Inactive action'), findsNothing);

        await tester.tap(find.byKey(const Key('active-branch-action')));
        await tester.tap(
          find.byKey(const Key('inactive-branch-action'), skipOffstage: false),
          warnIfMissed: false,
        );
        expect(activeTaps, 1);
        expect(inactiveTaps, 0);
      } finally {
        semantics.dispose();
      }
    });
  });

  testWidgets('root pages slide right when switching from branch 2 to 0', (
    tester,
  ) async {
    await expectDirectionalBranchSwitch(tester, fromIndex: 2, toIndex: 0);
  });

  testWidgets('root pages slide left when switching from branch 0 to 1', (
    tester,
  ) async {
    await expectDirectionalBranchSwitch(tester, fromIndex: 0, toIndex: 1);
  });

  testWidgets('reduce motion isolates the new root branch immediately', (
    tester,
  ) async {
    await runWithRouter(tester, (_) async {
      await tester.pumpWidget(buildBranchContainer(0, disableAnimations: true));
      await tester.pumpWidget(buildBranchContainer(1, disableAnimations: true));
      await tester.pump();

      expect(branchOffstage(tester, 0).offstage, isTrue);
      expect(branchOffstage(tester, 1).offstage, isFalse);
      expect(branchTranslation(tester, 1).translation, Offset.zero);
    });
  });
}
