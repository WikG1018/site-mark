import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/features/capture/capture_fullscreen_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';

/// Host page that pushes [CaptureFullscreenScreen] the same way the detail
/// preview does, so pop-based dismissal lands back on a stable route. The
/// photo path intentionally does not exist: the viewer's errorBuilder renders
/// the broken-image placeholder while every gesture under test still targets
/// the surrounding viewer chrome.
class _Host extends StatelessWidget {
  const _Host();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  const CaptureFullscreenScreen(path: '/nonexistent-photo.jpg'),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    );
  }
}

Future<void> pumpHost(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _Host(),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(find.byType(CaptureFullscreenScreen), findsOneWidget);
}

double viewerScale(WidgetTester tester) {
  return tester
      .widget<InteractiveViewer>(find.byType(InteractiveViewer))
      .transformationController!
      .value
      .getMaxScaleOnAxis();
}

Future<void> doubleTapViewer(WidgetTester tester) async {
  final target = find.byType(InteractiveViewer);
  await tester.tap(target);
  await tester.pump(const Duration(milliseconds: 80));
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('double tap zooms to 2x and back to 1x', (tester) async {
    await pumpHost(tester);
    expect(viewerScale(tester), closeTo(1, 0.001));
    expect(find.bySemanticsLabel('全屏查看照片'), findsOneWidget);

    await doubleTapViewer(tester);
    expect(viewerScale(tester), closeTo(2, 0.001));

    await doubleTapViewer(tester);
    expect(viewerScale(tester), closeTo(1, 0.001));
  });

  testWidgets('vertical drag past the threshold dismisses the viewer', (
    tester,
  ) async {
    await pumpHost(tester);
    await tester.drag(find.byType(InteractiveViewer), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.byType(CaptureFullscreenScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('fast fling below the distance threshold still dismisses', (
    tester,
  ) async {
    await pumpHost(tester);
    await tester.fling(
      find.byType(InteractiveViewer),
      const Offset(0, 80),
      1500,
    );
    await tester.pumpAndSettle();
    expect(find.byType(CaptureFullscreenScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('short drag animates back instead of dismissing', (tester) async {
    await pumpHost(tester);
    await tester.drag(find.byType(InteractiveViewer), const Offset(0, 60));
    await tester.pumpAndSettle();
    expect(find.byType(CaptureFullscreenScreen), findsOneWidget);
  });

  testWidgets('tap toggles chrome and the close button pops', (tester) async {
    await pumpHost(tester);
    final chrome = find.descendant(
      of: find.byType(CaptureFullscreenScreen),
      matching: find.byType(AnimatedOpacity),
    );
    expect(tester.widget<AnimatedOpacity>(chrome).opacity, 0);

    await tester.tap(find.byType(InteractiveViewer));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(chrome).opacity, 1);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(CaptureFullscreenScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}
