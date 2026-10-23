import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/app_theme.dart';
import 'package:sitemark/motion.dart';
import 'package:sitemark/navigation/root_navigation_dock.dart';

void main() {
  setUpAll(() async {
    final fonts = FontLoader('MiSans')
      ..addFont(rootBundle.load('assets/fonts/MiSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/MiSans-Medium.ttf'));
    await fonts.load();
  });

  Widget buildDock(
    int selectedIndex,
    ValueChanged<int> onDestinationSelected, {
    bool disableAnimations = false,
    bool highContrast = false,
    double width = 360,
    double textScale = 1,
    Locale locale = const Locale('zh'),
    TextDirection direction = TextDirection.ltr,
    Brightness brightness = Brightness.light,
  }) => MaterialApp(
    locale: locale,
    theme: brightness == Brightness.light
        ? buildLightTheme(seedColor: const Color(0xff176b55))
        : buildDarkTheme(seedColor: const Color(0xff176b55)),
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [
      AppStrings.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: disableAnimations,
        highContrast: highContrast,
        textScaler: TextScaler.linear(textScale),
      ),
      child: Directionality(textDirection: direction, child: child!),
    ),
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: width,
          height: 68,
          child: RootNavigationDock(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
          ),
        ),
      ),
    ),
  );

  testWidgets('dock uses one glass indicator that moves with selection', (
    tester,
  ) async {
    var selected = 0;
    void select(int value) => selected = value;

    await tester.pumpWidget(buildDock(selected, select));
    const indicatorKey = Key('root-dock-glass-indicator');
    expect(find.byKey(indicatorKey), findsOneWidget);
    expect(
      find.byKey(const Key('root-destination-projects-selected-surface')),
      findsNothing,
    );

    final before = tester.getCenter(find.byKey(indicatorKey));
    await tester.tap(find.byKey(const Key('root-destination-records')));
    await tester.pumpWidget(buildDock(selected, select));
    await tester.pump(AppMotion.rootSwitch ~/ 2);

    final during = tester.getCenter(find.byKey(indicatorKey));
    final target = tester.getCenter(
      find.byKey(const Key('root-destination-records')),
    );
    expect(during.dx, greaterThan(before.dx));
    expect(during.dx, lessThan(target.dx));

    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.byKey(indicatorKey)).dx,
      closeTo(target.dx, 1),
    );
    expect(
      find.descendant(
        of: find.byType(RootNavigationDock),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );
  });

  testWidgets('dock has a compact pill shell with only one blur pass', (
    tester,
  ) async {
    await tester.pumpWidget(buildDock(1, (_) {}, width: 600));
    final shell = find.byKey(const Key('root-dock-surface'));
    expect(shell, findsOneWidget);
    expect(tester.getSize(shell).height, 64);
    expect(tester.getSize(shell).width, lessThanOrEqualTo(360));
    for (final key in [
      const Key('root-dock-surface'),
      const Key('root-dock-glass-indicator'),
    ]) {
      final clip = tester.widget<ClipRRect>(
        find
            .descendant(of: find.byKey(key), matching: find.byType(ClipRRect))
            .first,
      );
      expect((clip.borderRadius as BorderRadius).topLeft.x, greaterThan(32));
    }
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).backgroundBlendMode != null,
      ),
      findsNothing,
    );
  });

  for (final locale in [const Locale('zh'), const Locale('en')]) {
    testWidgets('narrow $locale dock keeps full labels inside the lens', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildDock(1, (_) {}, width: 288, textScale: 2, locale: locale),
      );
      final indicator = tester.getRect(
        find.byKey(const Key('root-dock-glass-indicator')),
      );
      final content = tester.getRect(
        find.byKey(const Key('root-destination-records-content')),
      );
      expect(indicator.contains(content.topLeft), isTrue);
      expect(indicator.contains(content.bottomRight), isTrue);
      expect(content.center.dy, closeTo(indicator.center.dy, .5));
      for (final name in ['projects', 'records', 'settings']) {
        final button = find.byKey(Key('root-destination-$name'));
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        final label = find
            .descendant(of: button, matching: find.byType(RichText))
            .last;
        expect(
          tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
          isFalse,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('indicator follows the actual destination in RTL', (
    tester,
  ) async {
    await tester.pumpWidget(buildDock(0, (_) {}, direction: TextDirection.rtl));
    final lens = tester.getCenter(
      find.byKey(const Key('root-dock-glass-indicator')),
    );
    final target = tester.getCenter(
      find.byKey(const Key('root-destination-projects')),
    );
    expect(lens.dx, closeTo(target.dx, 1));
  });

  testWidgets('rapid reversal continues from the visible indicator position', (
    tester,
  ) async {
    await tester.pumpWidget(buildDock(0, (_) {}));
    await tester.pumpWidget(buildDock(2, (_) {}));
    await tester.pump(AppMotion.rootSwitch ~/ 3);
    final before = tester.getCenter(
      find.byKey(const Key('root-dock-glass-indicator')),
    );
    final widthBefore = tester
        .getSize(find.byKey(const Key('root-dock-glass-indicator')))
        .width;
    await tester.pumpWidget(buildDock(0, (_) {}));
    final interrupted = tester.getCenter(
      find.byKey(const Key('root-dock-glass-indicator')),
    );
    expect(interrupted.dx, closeTo(before.dx, .5));
    expect(
      tester.getSize(find.byKey(const Key('root-dock-glass-indicator'))).width,
      closeTo(widthBefore, .5),
    );
    await tester.pumpAndSettle();
    final target = tester.getCenter(
      find.byKey(const Key('root-destination-projects')),
    );
    expect(
      tester.getCenter(find.byKey(const Key('root-dock-glass-indicator'))).dx,
      closeTo(target.dx, 1),
    );
  });

  testWidgets('colorless lens stretches in motion then settles exactly', (
    tester,
  ) async {
    await tester.pumpWidget(buildDock(0, (_) {}));
    final lens = find.byKey(const Key('root-dock-glass-indicator'));
    final resting = tester.getSize(lens);
    final fill = tester.widget<DecoratedBox>(
      find.byKey(const Key('glass-lens-fill')),
    );
    final color = (fill.decoration as BoxDecoration).color!;
    expect(color.r, color.g);
    expect(color.g, color.b);
    expect(color.a, lessThan(1));
    await tester.pumpWidget(buildDock(2, (_) {}));
    await tester.pump(AppMotion.rootSwitch ~/ 2);
    expect(tester.getSize(lens).width, greaterThan(resting.width));
    expect(tester.getSize(lens).height, lessThan(resting.height));
    await tester.pumpAndSettle();
    expect(tester.getSize(lens), resting);
  });

  testWidgets('press deforms the selected lens and cancel restores it', (
    tester,
  ) async {
    await tester.pumpWidget(buildDock(0, (_) {}));
    final lens = find.byKey(const Key('root-dock-glass-indicator'));
    final resting = tester.getSize(lens);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('root-destination-projects'))),
    );
    await tester.pump();
    await tester.pump(AppMotion.short4);
    expect(tester.getSize(lens).height, lessThan(resting.height));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.getSize(lens), resting);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'glass label contrast is readable on black and white in $brightness',
      (tester) async {
        await tester.pumpWidget(buildDock(0, (_) {}, brightness: brightness));
        final context = tester.element(find.byType(RootNavigationDock));
        final scheme = Theme.of(context).colorScheme;
        BoxDecoration decoration(String key) =>
            tester.widget<DecoratedBox>(find.byKey(Key(key))).decoration
                as BoxDecoration;
        final body = decoration('glass-navigation-fill').color!;
        final lens = decoration('glass-lens-fill').color!;
        final bodySheen =
            (decoration('glass-navigation-sheen').gradient! as LinearGradient)
                .colors;
        final lensSheen =
            (decoration('glass-lens-sheen').gradient! as LinearGradient).colors;
        double contrast(Color a, Color b) {
          final x = a.computeLuminance();
          final y = b.computeLuminance();
          return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
        }

        for (final background in [Colors.black, Colors.white]) {
          for (final sheen in bodySheen) {
            final surface = Color.alphaBlend(
              sheen,
              Color.alphaBlend(body, background),
            );
            expect(
              contrast(scheme.onSurfaceVariant, surface),
              greaterThanOrEqualTo(4.5),
            );
            for (final reflection in lensSheen) {
              final selected = Color.alphaBlend(
                reflection,
                Color.alphaBlend(lens, surface),
              );
              expect(
                contrast(scheme.onSurface, selected),
                greaterThanOrEqualTo(4.5),
              );
            }
          }
        }
      },
    );
  }

  testWidgets('high contrast keeps navigation readable without live blur', (
    tester,
  ) async {
    await tester.pumpWidget(buildDock(1, (_) {}, highContrast: true));
    expect(find.byType(BackdropFilter), findsNothing);
    final fill = tester.widget<DecoratedBox>(
      find.byKey(const Key('glass-navigation-fill')),
    );
    expect((fill.decoration as BoxDecoration).color!.a, 1);
  });

  testWidgets('reduce motion places the glass indicator immediately', (
    tester,
  ) async {
    var selected = 0;
    void select(int value) => selected = value;

    await tester.pumpWidget(
      buildDock(selected, select, disableAnimations: true),
    );
    await tester.tap(find.byKey(const Key('root-destination-settings')));
    await tester.pumpWidget(
      buildDock(selected, select, disableAnimations: true),
    );
    await tester.pump();

    final indicator = tester.getCenter(
      find.byKey(const Key('root-dock-glass-indicator')),
    );
    final target = tester.getCenter(
      find.byKey(const Key('root-destination-settings')),
    );
    expect(indicator.dx, closeTo(target.dx, 1));
  });

  testWidgets('reduced motion keeps lens shape still during a press', (
    tester,
  ) async {
    await tester.pumpWidget(buildDock(0, (_) {}, disableAnimations: true));
    final lens = find.byKey(const Key('root-dock-glass-indicator'));
    final resting = tester.getSize(lens);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('root-destination-projects'))),
    );
    await tester.pump();
    await tester.pump(AppMotion.short4);
    expect(tester.getSize(lens), resting);
    expect(find.byType(BackdropFilter), findsNothing);
    await gesture.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets('destination tap triggers selection haptic feedback', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    var selected = 0;
    await tester.pumpWidget(buildDock(selected, (value) => selected = value));

    await tester.tap(find.byKey(const Key('root-destination-records')));
    await tester.pump();

    expect(selected, 1);
    expect(
      calls.any(
        (call) =>
            call.method == 'HapticFeedback.vibrate' &&
            call.arguments == 'HapticFeedbackType.selectionClick',
      ),
      isTrue,
      reason: 'dock tap should fire HapticFeedback.selectionClick',
    );
  });

  testWidgets('re-tapping the selected destination skips haptic feedback', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    var selected = 0;
    await tester.pumpWidget(buildDock(selected, (value) => selected = value));

    await tester.tap(find.byKey(const Key('root-destination-projects')));
    await tester.pump();

    expect(selected, 0);
    expect(
      calls.any(
        (call) =>
            call.method == 'HapticFeedback.vibrate' &&
            call.arguments == 'HapticFeedbackType.selectionClick',
      ),
      isFalse,
      reason: 're-tapping the current tab must not fire selectionClick',
    );
  });
}
