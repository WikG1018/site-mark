import 'dart:async';

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
      final pushFades = tester.widgetList<FadeTransition>(
        find.descendant(
          of: find.byKey(const Key('project-detail-route-clip')),
          matching: find.byType(FadeTransition),
        ),
      );
      expect(pushFades, isNotEmpty);
      expect(pushFades.every((fade) => fade.opacity.value == 1), isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android pop slides the page out with a fade', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final controller = AnimationController(
      vsync: tester,
      duration: AppMotion.medium2,
      value: 1.0,
    );
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: buildCaptureDetailRouteTransition(
            animation: controller,
            child: const SizedBox(key: Key('capture-detail-content')),
          ),
        ),
      );
      controller.value = 0.6;
      unawaited(controller.reverse());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      final slide = tester.widget<SlideTransition>(
        find.descendant(
          of: find.byKey(const Key('android-page-slide')),
          matching: find.byType(SlideTransition),
        ),
      );
      expect(slide.position.value.dx, greaterThan(0.08));
      final fade = tester.widget<FadeTransition>(
        find.descendant(
          of: find.byKey(const Key('android-page-slide')),
          matching: find.byType(FadeTransition),
        ),
      );
      expect(fade.opacity.value, greaterThan(0.0));
      expect(fade.opacity.value, lessThan(1.0));
    } finally {
      controller.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('covered page drifts toward the incoming route on Android', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => buildProjectDetailRouteTransition(
              context: context,
              animation: const AlwaysStoppedAnimation(1),
              secondaryAnimation: const AlwaysStoppedAnimation(0.5),
              child: const SizedBox(key: Key('project-detail-content')),
            ),
          ),
        ),
      );

      final parallax = tester.widget<SlideTransition>(
        find.byKey(const Key('android-page-secondary-slide')),
      );
      expect(parallax.position.value.dx, lessThan(0.0));
      expect(parallax.position.value.dx, greaterThan(-0.04));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('frozen secondary keeps the covered Android page put', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
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

      expect(
        find.byKey(const Key('android-page-secondary-slide')),
        findsNothing,
      );
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
