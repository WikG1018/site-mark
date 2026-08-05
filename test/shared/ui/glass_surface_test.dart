import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/shared/ui/glass_surface.dart';

void main() {
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
    const baseOpacity = 0.72;
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xff005a9c));

    Future<Color?> pumpAndReadSurface({required bool disableAnimations}) async {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: MaterialApp(
            theme: ThemeData(colorScheme: scheme),
            home: const Scaffold(
              body: GlassSurface(opacity: baseOpacity, child: Text('content')),
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
      matching: find.byWidgetPredicate((widget) {
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
      matching: find.byWidgetPredicate((widget) {
        if (widget is! DecoratedBox) return false;
        final decoration = widget.decoration;
        return decoration is BoxDecoration &&
            decoration.backgroundBlendMode == BlendMode.overlay;
      }),
    );
    expect(blends, findsOneWidget);
  });
}
