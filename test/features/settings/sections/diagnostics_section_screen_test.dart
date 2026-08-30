import 'package:flutter/foundation.dart';
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

        // The platform-differences card pushed the actions below the fold in
        // the default test viewport; bring the button into view before
        // tapping.
        await tester.ensureVisible(
          find.text(strings.generateAndShareDiagnosticBundle),
        );
        await tester.pumpAndSettle();
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
        await tester.ensureVisible(find.text(strings.clearLocalDiagnostics));
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

  for (final locale in const [Locale('zh'), Locale('en')]) {
    testWidgets(
      '${locale.languageCode} describes platform behavior differences honestly',
      (tester) async {
        await pumpScreen(tester, locale);
        final strings = AppStrings(locale);

        expect(find.text(strings.platformDifferences), findsOneWidget);
        expect(
          find.text(strings.backgroundProcessingDescription),
          findsOneWidget,
        );
        // The unified copy must promise neither "always confirms" nor "never
        // confirms": only iOS pops the system dialog, so both platforms read
        // the same "may confirm" wording.
        expect(
          find.text(strings.photoLibraryDeleteConfirmationNote),
          findsOneWidget,
        );
        expect(find.text(strings.locationAccuracyNote), findsOneWidget);
        // The iOS-specific scheduling note must not leak onto other platforms
        // (asserted by the platform-branch tests below).
        expect(find.text(strings.backgroundProcessingIosNote), findsNothing);
      },
    );
  }

  testWidgets('iOS discloses the opportunistic background scheduling', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pumpScreen(tester, const Locale('zh'));
      final strings = AppStrings(const Locale('zh'));

      expect(find.text(strings.backgroundProcessingIosNote), findsOneWidget);
    } finally {
      // Reset before the binding's invariant check runs (addTearDown fires
      // after it, which would fail the run).
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android does not show the iOS scheduling note', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pumpScreen(tester, const Locale('zh'));
      final strings = AppStrings(const Locale('zh'));

      expect(find.text(strings.backgroundProcessingIosNote), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
