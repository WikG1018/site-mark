import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/navigation/route_transitions.dart';

void main() {
  testWidgets('capture detail route fades continuously during reverse motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: buildCaptureDetailRouteTransition(
          animation: const AlwaysStoppedAnimation(0.5),
          child: const SizedBox(key: Key('capture-detail-content')),
        ),
      ),
    );

    final fades = tester.widgetList<FadeTransition>(
      find.ancestor(
        of: find.byKey(const Key('capture-detail-content')),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fades, isNotEmpty);
    expect(
      fades.any((fade) => fade.opacity.value > 0 && fade.opacity.value < 1),
      isTrue,
    );
  });

  testWidgets('imperative photo push freezes only the project capture list', (
    tester,
  ) async {
    var freezeProjectList = false;
    late GoRouter router;
    router = GoRouter(
      initialLocation: '/projects/p-1',
      routes: [
        GoRoute(
          path: '/projects/:projectId',
          pageBuilder: (context, state) {
            freezeProjectList = shouldFreezeProjectCaptureList(state);
            return NoTransitionPage<void>(
              child: Scaffold(
                body: Column(
                  children: [
                    TextButton(
                      key: const Key('open-settings'),
                      onPressed: () => context.push('/projects/p-1/settings'),
                      child: const Text('settings'),
                    ),
                    TextButton(
                      key: const Key('open-capture-form'),
                      onPressed: () => context.push('/projects/p-1/capture'),
                      child: const Text('capture'),
                    ),
                    TextButton(
                      key: const Key('open-photo'),
                      onPressed: () =>
                          context.push('/projects/p-1/captures/c-1'),
                      child: const Text('photo'),
                    ),
                  ],
                ),
              ),
            );
          },
          routes: [
            GoRoute(
              path: 'settings',
              builder: (context, state) =>
                  const Scaffold(body: Text('project settings')),
            ),
            GoRoute(
              path: 'capture',
              builder: (context, state) =>
                  const Scaffold(body: Text('capture form')),
            ),
            GoRoute(
              path: 'captures/:captureId',
              builder: (context, state) =>
                  const Scaffold(body: Text('photo detail')),
              routes: [
                GoRoute(
                  path: 'edit',
                  builder: (context, state) =>
                      const Scaffold(body: Text('photo editor')),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    expect(freezeProjectList, isFalse);

    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();
    expect(freezeProjectList, isFalse);
    router.pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-capture-form')));
    await tester.pumpAndSettle();
    expect(freezeProjectList, isFalse);
    router.pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-photo')));
    await tester.pumpAndSettle();
    expect(freezeProjectList, isTrue);

    router.push('/projects/p-1/captures/c-1/edit');
    await tester.pumpAndSettle();
    expect(freezeProjectList, isTrue);
  });

  testWidgets('covered shared-axis capture list stays fully opaque', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => buildSharedAxisRouteTransition(
            context: context,
            animation: const AlwaysStoppedAnimation(1),
            secondaryAnimation: const AlwaysStoppedAnimation(0.5),
            freezeSecondary: true,
            child: const SizedBox(key: Key('capture-list')),
          ),
        ),
      ),
    );

    final fades = tester.widgetList<FadeTransition>(
      find.ancestor(
        of: find.byKey(const Key('capture-list')),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fades, isNotEmpty);
    expect(fades.every((fade) => fade.opacity.value == 1), isTrue);
  });

  testWidgets('covered fade-through capture list stays fully opaque', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => buildFadeThroughRouteTransition(
            context: context,
            animation: const AlwaysStoppedAnimation(1),
            secondaryAnimation: const AlwaysStoppedAnimation(0.5),
            freezeSecondary: true,
            child: const SizedBox(key: Key('capture-list')),
          ),
        ),
      ),
    );

    final fades = tester.widgetList<FadeTransition>(
      find.ancestor(
        of: find.byKey(const Key('capture-list')),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fades, isNotEmpty);
    expect(fades.every((fade) => fade.opacity.value == 1), isTrue);
  });

  testWidgets('reduce-motion skips shared-axis transition widgets', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          );
        },
        home: Builder(
          builder: (context) => buildSharedAxisRouteTransition(
            context: context,
            animation: const AlwaysStoppedAnimation(0.5),
            secondaryAnimation: const AlwaysStoppedAnimation(0.5),
            child: const SizedBox(key: Key('reduced-motion-child')),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('reduced-motion-child')), findsOneWidget);
    expect(find.byType(SharedAxisTransition), findsNothing);
  });
}
