import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/features/settings/sections/appearance_section_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    bool supportsDynamicColor = true,
  }) async {
    await database.getAppSettings();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          supportsDynamicColorProvider.overrideWithValue(supportsDynamicColor),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const AppearanceSectionScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('theme selection persists', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('theme-dark')));
    await tester.pumpAndSettle();
    expect((await database.getAppSettings()).themeMode, 'dark');
  });

  testWidgets('dynamic color switch persists', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('dynamic-color-switch')));
    await tester.pumpAndSettle();
    expect((await database.getAppSettings()).useDynamicColor, isTrue);
  });

  testWidgets('shows 9 theme color chips when dynamic color is off', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(find.text('应用主题色'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(9));
  });

  testWidgets('hides theme color chips when dynamic color is on', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('dynamic-color-switch')));
    await tester.pumpAndSettle();
    expect(find.text('应用主题色'), findsNothing);
  });

  testWidgets('tapping a theme color chip persists appSeedColorArgb', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('accent-blue')));
    await tester.pumpAndSettle();
    expect((await database.getAppSettings()).appSeedColorArgb, 0xff1565c0);
  });

  testWidgets('shows English theme color label and chips', (tester) async {
    await database.getAppSettings();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const AppearanceSectionScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('App theme color'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(9));
    // Spot-check one English color label.
    expect(find.text('Blue'), findsOneWidget);
  });

  testWidgets(
    'hides dynamic color switch and shows honesty hint when unsupported',
    (tester) async {
      await pumpScreen(tester, supportsDynamicColor: false);
      expect(find.byKey(const Key('dynamic-color-switch')), findsNothing);
      expect(find.byKey(const Key('dynamic-color-unavailable')), findsOneWidget);
      expect(find.text('鸿蒙暂不支持壁纸动态取色'), findsOneWidget);
      expect(find.text('应用主题色'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNWidgets(9));
    },
  );

  testWidgets(
    'still shows theme chips when unsupported even if useDynamicColor is on',
    (tester) async {
      await database.updateAppSettings(useDynamicColor: true);
      await pumpScreen(tester, supportsDynamicColor: false);
      expect(find.byKey(const Key('dynamic-color-switch')), findsNothing);
      expect(find.text('应用主题色'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNWidgets(9));
    },
  );

  testWidgets(
    'reopening the picker after toggling dynamic color keeps the last selection',
    (tester) async {
      await pumpScreen(tester);
      // Pick a non-default theme color first.
      await tester.tap(find.byKey(const Key('accent-purple')));
      await tester.pumpAndSettle();
      expect((await database.getAppSettings()).appSeedColorArgb, 0xff6a1b9a);

      // Turn on dynamic color — the picker should hide.
      await tester.tap(find.byKey(const Key('dynamic-color-switch')));
      await tester.pumpAndSettle();
      expect(find.text('应用主题色'), findsNothing);

      // Turn dynamic color back off — the picker reappears and the purple
      // chip must still be selected.
      await tester.tap(find.byKey(const Key('dynamic-color-switch')));
      await tester.pumpAndSettle();
      expect(find.text('应用主题色'), findsOneWidget);
      final purpleChip = tester.widget<ChoiceChip>(
        find.descendant(
          of: find.byKey(const Key('accent-purple')),
          matching: find.byType(ChoiceChip),
        ),
      );
      expect(purpleChip.selected, isTrue);
    },
  );
}
