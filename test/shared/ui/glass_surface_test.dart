import 'package:flutter/widgets.dart';
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
}
