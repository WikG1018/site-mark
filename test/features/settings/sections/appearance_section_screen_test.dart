// test/features/settings/sections/appearance_section_screen_test.dart
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

  Future<void> pumpScreen(WidgetTester tester) async {
    await database.getAppSettings();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
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
}
