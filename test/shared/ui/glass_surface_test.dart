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
    var tapped = false;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GlassCard(onTap: () => tapped = true, child: const Text('项目')),
      ),
    );

    await tester.tap(find.text('项目'));
    expect(tapped, isTrue);
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
