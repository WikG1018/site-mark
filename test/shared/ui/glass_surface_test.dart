import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
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
    const textColor = Color(0xff7b1fa2);
    const iconColor = Color(0xffe65100);
    const nestedIconColor = Color(0xff1565c0);
    await tester.pumpWidget(
      MaterialApp(
        home: GlassSurface(
          child: const Column(
            children: [
              Text(
                'explicit text',
                key: Key('explicit-text'),
                style: TextStyle(color: textColor),
              ),
              Icon(Icons.photo, key: Key('explicit-icon'), color: iconColor),
              IconTheme(
                data: IconThemeData(color: nestedIconColor),
                child: Icon(Icons.settings, key: Key('nested-icon-theme')),
              ),
            ],
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.byKey(const Key('explicit-text')));
    expect(text.style?.color, textColor);
    final icon = tester.widget<Icon>(find.byKey(const Key('explicit-icon')));
    expect(icon.color, iconColor);
    expect(
      IconTheme.of(
        tester.element(find.byKey(const Key('nested-icon-theme'))),
      ).color,
      nestedIconColor,
    );
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
}
