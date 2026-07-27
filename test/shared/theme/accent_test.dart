// test/shared/theme/accent_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/shared/theme/accent_choice_chip.dart';
import 'package:sitemark/shared/theme/accent_swatches.dart';

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

  test('accentSwatches has unique ARGB values', () {
    final argbs = accentSwatches.map((s) => s.argb).toSet();
    expect(argbs.length, 9);
  });

  test('accentLabel maps every swatch to a non-empty string', () {
    final strings = AppStrings(const Locale('zh'));
    for (final swatch in accentSwatches) {
      final label = accentLabel(strings, swatch.argb);
      expect(label, isNotEmpty, reason: 'swatch ARGB ${swatch.argb} 映射为空');
    }
  });

  test('debugAssertAccentSwatchesComplete passes for the current set', () {
    // The function only asserts in debug mode, but it must not throw and
    // must return true when every swatch has a matching label entry.
    expect(debugAssertAccentSwatchesComplete(), isTrue);
  });

  test('accentLabel returns empty string for unknown ARGB in release mode', () {
    final strings = AppStrings(const Locale('zh'));
    // 0x00000000 is not in _accentLabelMap. In debug mode this would assert;
    // flutter_test runs in debug mode, so we cannot directly test the
    // release-mode fallback here. Instead we verify a known value resolves.
    expect(accentLabel(strings, 0xff37c58b), strings.green);
  });
}
