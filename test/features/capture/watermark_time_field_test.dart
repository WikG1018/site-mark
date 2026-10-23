import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/features/capture/watermark_time_field.dart';
import 'package:sitemark/l10n/app_strings.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    double scale = 1,
    Locale locale = const Locale('zh'),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: StatefulBuilder(
          builder: (context, setState) {
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: WatermarkTimeField(
                    value: DateTime(2024, 2, 3, 4, 5),
                    onChanged: (value) {},
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('narrow large-font timestamp and reset remain readable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pump(tester, scale: 2);
    expect(find.text('2024-02-03 04:05'), findsOneWidget);
    expect(find.text('恢复自动时间'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('date picker can be cancelled without applying changes', (
    tester,
  ) async {
    await pump(tester, locale: const Locale('en'));
    await tester.tap(find.byKey(const Key('watermark-time-field')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.text('2024-02-03 04:05'), findsOneWidget);
  });
  testWidgets('reset returns null instead of replacing original timestamp', (
    tester,
  ) async {
    DateTime? selected = DateTime(2024, 1, 1);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        home: Scaffold(
          body: WatermarkTimeField(
            value: selected,
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('reset-watermark-time')));
    expect(selected, isNull);
  });
}
