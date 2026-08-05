import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';
import 'package:sitemark/navigation/root_navigation_dock.dart';

void main() {
  Widget buildDock(
    int selectedIndex,
    ValueChanged<int> onDestinationSelected, {
    bool disableAnimations = false,
  }) => MaterialApp(
    locale: const Locale('zh'),
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [
      AppStrings.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: disableAnimations),
      child: child!,
    ),
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: 360,
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
      findsNothing,
    );
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
}
