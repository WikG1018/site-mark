// test/features/settings/sections/watermark_defaults_section_screen_test.dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/shared/theme/accent_choice_chip.dart';
import 'package:sitemark/features/settings/sections/watermark_defaults_section_screen.dart';
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
          home: const WatermarkDefaultsSectionScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('watermark position persists', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('default-position-bottomRight')));
    await tester.pumpAndSettle();
    expect(
      (await database.getAppSettings()).defaultWatermarkPosition,
      'bottomRight',
    );
  });

  testWidgets('opacity slider persists on change end', (tester) async {
    await pumpScreen(tester);
    await tester.timedDrag(
      find.byKey(const Key('opacity-slider')),
      const Offset(500, 0),
      const Duration(milliseconds: 200),
    );
    await tester.pumpAndSettle();
    expect((await database.getAppSettings()).defaultWatermarkOpacity, 0.95);
  });

  testWidgets('font scale slider persists on release', (tester) async {
    await pumpScreen(tester);
    final slider = find.byKey(const Key('default-font-scale-slider'));
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    await tester.timedDrag(
      slider,
      const Offset(500, 0),
      const Duration(milliseconds: 200),
    );
    await tester.pumpAndSettle();
    expect((await database.getAppSettings()).defaultWatermarkFontScale, 1.60);
  });

  testWidgets('accent swatch selection persists', (tester) async {
    await pumpScreen(tester);
    await tester.ensureVisible(find.byKey(const Key('accent-orange')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('accent-orange')));
    await tester.pumpAndSettle();
    expect(
      (await database.getAppSettings()).defaultWatermarkAccentColorArgb,
      0xffef6c00,
    );
  });

  testWidgets('shows 9 accent chips', (tester) async {
    await pumpScreen(tester);
    expect(find.byType(AccentChoiceChip), findsNWidgets(9));
  });
}
