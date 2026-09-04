import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/shared/ui/glass_surface.dart';

void main() {
  testWidgets('glass card never uses a live backdrop blur', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: GlassCard(child: Text('项目卡片'))),
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('Android glass surface skips live backdrop blur', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: GlassSurface(child: Text('content'))),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('iOS glass surface keeps live backdrop blur', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: GlassSurface(child: Text('content'))),
        ),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('glass surface disables blur when animations are disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: GlassSurface(child: Text('content')),
        ),
      ),
    );

    expect(find.text('content'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('glass card keeps a semantic tap target', (tester) async {
    final semantics = tester.ensureSemantics();
    var tapped = false;

    try {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: GlassCard(onTap: () => tapped = true, child: const Text('项目')),
        ),
      );

      final tapTarget = find.descendant(
        of: find.byType(GlassCard),
        matching: find.byType(InkWell),
      );
      expect(tapTarget, findsOneWidget);
      expect(
        tester
            .getSemantics(tapTarget)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );

      await tester.tap(find.text('项目'));
      expect(tapped, isTrue);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('explicit text and icon foregrounds override glass defaults', (
    tester,
  ) async {
    const hostileForeground = Color(0xff00ff00);
    const textColor = Color(0xff7b1fa2);
    const iconColor = Color(0xffe65100);
    const nestedIconColor = Color(0xff1565c0);
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xff005a9c));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: scheme),
        home: DefaultTextStyle(
          style: const TextStyle(color: hostileForeground),
          child: IconTheme(
            data: const IconThemeData(color: hostileForeground),
            child: GlassSurface(
              child: const Column(
                children: [
                  Text('default text', key: Key('default-text')),
                  Text(
                    'explicit text',
                    key: Key('explicit-text'),
                    style: TextStyle(color: textColor),
                  ),
                  Icon(Icons.image, key: Key('default-icon')),
                  Icon(
                    Icons.photo,
                    key: Key('explicit-icon'),
                    color: iconColor,
                  ),
                  IconTheme(
                    data: IconThemeData(color: nestedIconColor),
                    child: Icon(Icons.settings, key: Key('nested-icon-theme')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    Color? renderedForeground(Key key) {
      final richText = find.descendant(
        of: find.byKey(key),
        matching: find.byType(RichText),
      );
      return tester.renderObject<RenderParagraph>(richText).text.style?.color;
    }

    expect(renderedForeground(const Key('default-text')), scheme.onSurface);
    expect(renderedForeground(const Key('explicit-text')), textColor);
    expect(renderedForeground(const Key('default-icon')), scheme.onSurface);
    expect(renderedForeground(const Key('explicit-icon')), iconColor);
    expect(renderedForeground(const Key('nested-icon-theme')), nestedIconColor);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'glass surface provides onSurface foregrounds in $brightness mode',
      (tester) async {
        final scheme = ColorScheme.fromSeed(
          seedColor: const Color(0xff005a9c),
          brightness: brightness,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(colorScheme: scheme),
            home: GlassSurface(
              child: const Column(
                children: [Text('content'), Icon(Icons.photo)],
              ),
            ),
          ),
        );

        final foregrounds = find.descendant(
          of: find.byType(GlassSurface),
          matching: find.byType(DefaultTextStyle),
        );
        expect(foregrounds, findsOneWidget);
        expect(
          tester.widget<DefaultTextStyle>(foregrounds).style.color,
          scheme.onSurface,
        );

        final iconThemes = find.descendant(
          of: find.byType(GlassSurface),
          matching: find.byType(IconTheme),
        );
        expect(iconThemes, findsOneWidget);
        expect(
          tester.widget<IconTheme>(iconThemes).data.color,
          scheme.onSurface,
        );
      },
    );
  }

  testWidgets('boosts surface opacity when blur is disabled', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      const baseOpacity = 0.72;
      final scheme = ColorScheme.fromSeed(seedColor: const Color(0xff005a9c));

      Future<Color?> pumpAndReadSurface({
        required bool disableAnimations,
      }) async {
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: MaterialApp(
              theme: ThemeData(colorScheme: scheme),
              home: const Scaffold(
                body: GlassSurface(
                  opacity: baseOpacity,
                  child: Text('content'),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final decorated = find.descendant(
          of: find.byType(GlassSurface),
          matching: find.byType(DecoratedBox),
        );
        expect(decorated, findsWidgets);
        final outer = tester.widget<DecoratedBox>(decorated.first);
        final decoration = outer.decoration as BoxDecoration;
        return decoration.color;
      }

      final withBlur = await pumpAndReadSurface(disableAnimations: false);
      final withoutBlur = await pumpAndReadSurface(disableAnimations: true);

      expect(withBlur, isNotNull);
      expect(withoutBlur, isNotNull);
      expect(withBlur!.a, closeTo(baseOpacity, 0.001));
      expect(
        withoutBlur!.a,
        closeTo((baseOpacity + 0.10).clamp(0.58, 0.94), 0.001),
      );
      expect(withoutBlur.a, greaterThan(withBlur.a));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('enableOverlay false skips the overlay blend layer', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: GlassSurface(enableOverlay: false, child: Text('content')),
      ),
    );
    await tester.pump();

    final blends = find.descendant(
      of: find.byType(GlassSurface),
      matching: find.byWidgetPredicate((Widget widget) {
        if (widget is! DecoratedBox) return false;
        final decoration = widget.decoration;
        return decoration is BoxDecoration &&
            decoration.backgroundBlendMode == BlendMode.overlay;
      }),
    );
    expect(blends, findsNothing);
  });

  testWidgets('enableOverlay true paints the overlay blend layer', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: GlassSurface(enableOverlay: true, child: Text('content')),
      ),
    );
    await tester.pump();

    final blends = find.descendant(
      of: find.byType(GlassSurface),
      matching: find.byWidgetPredicate((Widget widget) {
        if (widget is! DecoratedBox) return false;
        final decoration = widget.decoration;
        return decoration is BoxDecoration &&
            decoration.backgroundBlendMode == BlendMode.overlay;
      }),
    );
    expect(blends, findsOneWidget);
  });

  testWidgets('overlay tint sits under content, not above it', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: GlassSurface(
          enableOverlay: true,
          child: Text('content', key: Key('glass-content')),
        ),
      ),
    );
    await tester.pump();

    final stack = tester.widget<Stack>(
      find.descendant(
        of: find.byType(GlassSurface),
        matching: find.byType(Stack),
      ),
    );
    final overlayIndex = stack.children.indexWhere((widget) {
      if (widget is! Positioned) return false;
      final child = widget.child;
      if (child is! IgnorePointer) return false;
      final decorated = child.child;
      return decorated is DecoratedBox &&
          decorated.decoration is BoxDecoration &&
          (decorated.decoration as BoxDecoration).backgroundBlendMode ==
              BlendMode.overlay;
    });
    final contentIndex = stack.children.indexWhere(
      (widget) =>
          widget is DefaultTextStyle ||
          find
              .descendant(
                of: find.byWidget(widget),
                matching: find.byKey(const Key('glass-content')),
              )
              .evaluate()
              .isNotEmpty,
    );
    // Fall back: content is wrapped in DefaultTextStyle.merge
    final textStyleIndex = stack.children.indexWhere(
      (widget) => widget is DefaultTextStyle,
    );
    final resolvedContentIndex = contentIndex >= 0
        ? contentIndex
        : textStyleIndex;

    expect(overlayIndex, greaterThanOrEqualTo(0));
    expect(resolvedContentIndex, greaterThanOrEqualTo(0));
    expect(
      overlayIndex,
      lessThan(resolvedContentIndex),
      reason: 'overlay must paint before (under) content in the Stack',
    );
  });

  testWidgets('clamps blur-enabled opacity into the glass band', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final scheme = ColorScheme.fromSeed(seedColor: const Color(0xff005a9c));
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: MaterialApp(
            theme: ThemeData(colorScheme: scheme),
            home: const Scaffold(
              body: GlassSurface(opacity: 1.0, child: Text('content')),
            ),
          ),
        ),
      );
      await tester.pump();

      final decorated = find.descendant(
        of: find.byType(GlassSurface),
        matching: find.byType(DecoratedBox),
      );
      final outer = tester.widget<DecoratedBox>(decorated.first);
      final color = (outer.decoration as BoxDecoration).color;
      expect(color, isNotNull);
      expect(color!.a, closeTo(0.92, 0.001));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
