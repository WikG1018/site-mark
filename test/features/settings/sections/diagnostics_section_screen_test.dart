import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/features/settings/sections/diagnostics_section_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';

void main() {
  Future<void> pumpScreen(WidgetTester tester, Locale locale) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppStrings.supportedLocales,
        locale: locale,
        home: const DiagnosticsSectionScreen(),
      ),
    );
  }

  for (final locale in const [Locale('zh'), Locale('en')]) {
    testWidgets(
      '${locale.languageCode} explains local-only diagnostics and share privacy',
      (tester) async {
        await pumpScreen(tester, locale);
        final strings = AppStrings(locale);

        expect(find.text(strings.diagnosticsAndFeedback), findsOneWidget);
        expect(find.text(strings.privacyProtection), findsOneWidget);
        expect(find.text(strings.diagnosticsStoredLocally), findsOneWidget);
        expect(
          find.text(strings.diagnosticBundlePrivacyNotice),
          findsOneWidget,
        );
        expect(find.text(strings.diagnosticsRetentionHint), findsOneWidget);
        expect(
          find.text(strings.generateAndShareDiagnosticBundle),
          findsOneWidget,
        );
        expect(find.text(strings.clearLocalDiagnostics), findsOneWidget);

        if (locale.languageCode == 'en') {
          expect(find.textContaining('诊断'), findsNothing);
          expect(find.textContaining('隐私保护'), findsNothing);
          expect(find.textContaining('生成并分享诊断包'), findsNothing);
          expect(find.textContaining('清除本机诊断记录'), findsNothing);
        }

        await tester.tap(find.text(strings.generateAndShareDiagnosticBundle));
        await tester.pumpAndSettle();
        expect(find.text(strings.shareDiagnosticBundleTitle), findsOneWidget);
        expect(find.text(strings.shareDiagnosticBundleContent), findsOneWidget);
        expect(find.text(strings.confirmGenerate), findsOneWidget);
        if (locale.languageCode == 'en') {
          expect(find.textContaining('分享诊断包'), findsNothing);
          expect(find.textContaining('确认生成'), findsNothing);
        }

        await tester.tap(find.text(strings.cancel));
        await tester.pumpAndSettle();
        await tester.tap(find.text(strings.clearLocalDiagnostics));
        await tester.pumpAndSettle();
        expect(find.text(strings.clearDiagnosticsTitle), findsOneWidget);
        expect(find.text(strings.clearDiagnosticsContent), findsOneWidget);
        if (locale.languageCode == 'en') {
          expect(find.textContaining('清除诊断记录'), findsNothing);
        }
      },
    );
  }
}
