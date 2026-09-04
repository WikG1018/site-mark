import 'package:animations/animations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/navigation/route_transitions.dart';
import 'package:sitemark/motion.dart';

void main() {
  test('root and page transition durations use the visual-system timings', () {
    expect(AppMotion.rootSwitch, const Duration(milliseconds: 240));
    expect(AppMotion.pageTransition, const Duration(milliseconds: 260));
  });

  testWidgets('capture detail route fades continuously during reverse motion', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
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
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'project detail route uses a clipped slide and fade instead of shared axis',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => buildProjectDetailRouteTransition(
                context: context,
                animation: const AlwaysStoppedAnimation(0.5),
                child: const SizedBox(key: Key('project-detail-content')),
              ),
            ),
          ),
        );

        expect(find.byKey(const Key('project-detail-content')), findsOneWidget);
        expect(
          find.byKey(const Key('project-detail-route-clip')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('project-detail-route-slide')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('project-detail-route-fade')),
          findsOneWidget,
        );
        expect(find.byType(SharedAxisTransition), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('Android project detail slides without a full-page fade', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => buildProjectDetailRouteTransition(
              context: context,
              animation: const AlwaysStoppedAnimation(0.5),
              child: const SizedBox(key: Key('project-detail-content')),
            ),
          ),
        ),
      );

      expect(
        find.byKey(const Key('project-detail-route-slide')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('project-detail-route-fade')), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android shared-axis routes slide without SharedAxis layers', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => buildSharedAxisRouteTransition(
              context: context,
              animation: const AlwaysStoppedAnimation(0.5),
              secondaryAnimation: const AlwaysStoppedAnimation(0),
              child: const SizedBox(key: Key('shared-axis-content')),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('shared-axis-content')), findsOneWidget);
      expect(find.byType(SharedAxisTransition), findsNothing);
      expect(find.byKey(const Key('android-page-slide')), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('reduce-motion skips the project detail transition widgets', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Builder(
          builder: (context) => buildProjectDetailRouteTransition(
            context: context,
            animation: const AlwaysStoppedAnimation(0.5),
            child: const SizedBox(key: Key('reduced-project-detail')),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('reduced-project-detail')), findsOneWidget);
    expect(find.byKey(const Key('project-detail-route-clip')), findsNothing);
    expect(find.byKey(const Key('project-detail-route-slide')), findsNothing);
    expect(find.byKey(const Key('project-detail-route-fade')), findsNothing);
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
