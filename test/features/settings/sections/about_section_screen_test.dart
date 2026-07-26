import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/app_links.dart';
import 'package:sitemark/features/settings/sections/about_section_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/external_link_service.dart';

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
    ExternalLinkService? externalLinks,
  }) async {
    await database.getAppSettings();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          if (externalLinks != null)
            externalLinkServiceProvider.overrideWithValue(externalLinks),
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
          home: const AboutSectionScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('about section shows fallback version when PackageInfo fails', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(find.text('0.5.1+6'), findsOneWidget);
  });

  testWidgets('about shows and opens the full GitHub repository URL', (
    tester,
  ) async {
    final links = _RecordingExternalLinkService();
    await pumpScreen(tester, externalLinks: links);
    expect(find.text('GitHub 代码仓库'), findsOneWidget);
    expect(find.text(siteMarkRepositoryUrl), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('github-repository-link')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('github-repository-link')));
    await tester.pump();
    expect(links.opened, [siteMarkRepositoryUri]);
  });

  testWidgets('about shows a snackbar when opening the repository fails', (
    tester,
  ) async {
    final links = _RecordingExternalLinkService(result: false);
    await pumpScreen(tester, externalLinks: links);
    await tester.ensureVisible(find.byKey(const Key('github-repository-link')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('github-repository-link')));
    await tester.pump();
    expect(find.text('无法打开浏览器'), findsOneWidget);
    expect(links.opened, [siteMarkRepositoryUri]);
  });
}

class _RecordingExternalLinkService implements ExternalLinkService {
  _RecordingExternalLinkService({this.result = true});

  final bool result;
  final List<Uri> opened = [];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return result;
  }
}
