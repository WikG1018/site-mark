import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/features/onboarding/privacy_consent_gate.dart';
import 'package:sitemark/l10n/app_strings.dart';

void main() {
  testWidgets('blocks the app until privacy consent is accepted', (tester) async {
    final store = MemoryPrivacyConsentStore(accepted: false);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppStrings.supportedLocales,
        home: PrivacyConsentGate(
          store: store,
          child: const Text('HOME'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsNothing);
    expect(find.text('同意并继续'), findsOneWidget);
  });

  testWidgets('shows home after accept', (tester) async {
    final store = MemoryPrivacyConsentStore(accepted: false);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppStrings.supportedLocales,
        home: PrivacyConsentGate(
          store: store,
          child: const Text('HOME'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    expect(await store.isAccepted(), isTrue);
  });
}
