import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/features/settings/global_settings_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  /// Pumps the [GlobalSettingsScreen] in a localized Material harness wired to
  /// the in-memory [database] via Riverpod overrides.
  Future<void> pumpSettings(WidgetTester tester, {AppDatabase? db}) async {
    final resolved = db ?? database;
    // Open the lazy in-memory database and ensure the singleton settings row
    // before the screen reads it, so the FutureBuilder resolves on the first
    // pumped frame instead of stalling `pumpAndSettle` on the DB open.
    await resolved.getAppSettings();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(resolved)],
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const GlobalSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('theme and language persist through database settings', (
    tester,
  ) async {
    await pumpSettings(tester, db: database);
    await tester.tap(find.byKey(const Key('theme-dark')));
    await tester.tap(find.byKey(const Key('language-en')));
    await tester.pumpAndSettle();

    final settings = await database.getAppSettings();
    expect(settings.themeMode, 'dark');
    expect(settings.localeCode, 'en');
  });

  testWidgets(
    'opacity slider persists on change end within the 0.20-0.95 range',
    (tester) async {
      await pumpSettings(tester, db: database);
      // The default opacity (0.78) already satisfies the 0.20-0.95 bounds, so a
      // bare range check cannot detect a regression where onChangeEnd never
      // persists. Drag the thumb hard to the right end: with divisions: 75 over
      // [0.20, 0.95] the value snaps to exactly 0.95, which differs from 0.78.
      // Asserting 0.95 proves onChangeEnd wrote the dragged value to the DB.
      await tester.timedDrag(
        find.byKey(const Key('opacity-slider')),
        const Offset(500, 0),
        const Duration(milliseconds: 200),
      );
      await tester.pumpAndSettle();

      final settings = await database.getAppSettings();
      expect(settings.defaultWatermarkOpacity, 0.95);
      expect(settings.defaultWatermarkOpacity, lessThanOrEqualTo(0.95));
      expect(settings.defaultWatermarkOpacity, greaterThanOrEqualTo(0.20));
    },
  );

  testWidgets('accent swatch selection persists', (tester) async {
    await pumpSettings(tester, db: database);
    await tester.scrollUntilVisible(
      find.byKey(const Key('accent-orange')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('accent-orange')));
    await tester.pumpAndSettle();

    final settings = await database.getAppSettings();
    expect(settings.defaultWatermarkAccentColorArgb, 0xffef6c00);
  });

  testWidgets('watermark position segmented control persists', (tester) async {
    await pumpSettings(tester, db: database);
    await tester.tap(find.byKey(const Key('default-position-bottomRight')));
    await tester.pumpAndSettle();

    final settings = await database.getAppSettings();
    expect(settings.defaultWatermarkPosition, 'bottomRight');
  });

  testWidgets('about section shows fallback version when PackageInfo fails', (
    tester,
  ) async {
    await pumpSettings(tester, db: database);
    await tester.scrollUntilVisible(
      find.textContaining('0.2.0'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('0.2.0'), findsOneWidget);
  });

  testWidgets('about section exposes the repository name and license', (
    tester,
  ) async {
    await pumpSettings(tester, db: database);
    await tester.scrollUntilVisible(
      find.text('WikG1018/site-mark'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('WikG1018/site-mark'), findsOneWidget);
    expect(find.text('Apache-2.0'), findsOneWidget);
  });

  testWidgets('settings route is reachable from the app shell', (tester) async {
    await database.getAppSettings();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
          routes: [
            GoRoute(
              path: 'settings',
              builder: (context, state) => const GlobalSettingsScreen(),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp.router(
          locale: const Locale('zh'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: router,
        ),
      ),
    );
    router.go('/settings');
    await tester.pumpAndSettle();

    expect(find.byType(GlobalSettingsScreen), findsOneWidget);
  });
}
