import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/features/settings/accent_choice_chip.dart';
import 'package:sitemark/features/settings/settings_section_scaffold.dart';
import 'package:sitemark/l10n/app_strings.dart';

void main() {
  testWidgets('AccentChoiceChip renders label and color', (tester) async {
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
        home: Material(
          child: AccentChoiceChip(
            argb: 0xff37c58b,
            label: '绿色',
            selected: true,
            onSelected: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('绿色'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsOneWidget);
  });

  test('accentSwatches has 9 entries with unique keys', () {
    expect(accentSwatches.length, 9);
    final keys = accentSwatches.map((s) => s.key).toSet();
    expect(keys.length, 9);
  });

  test('accentLabel maps every swatch to a non-empty string', () {
    final strings = AppStrings(const Locale('zh'));
    for (final swatch in accentSwatches) {
      final label = accentLabel(strings, swatch.argb);
      expect(label, isNotEmpty, reason: 'swatch ${swatch.labelKey} 映射为空');
    }
  });
}
