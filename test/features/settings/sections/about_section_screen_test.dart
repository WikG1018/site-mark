import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
    Locale locale = const Locale('zh'),
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
          locale: locale,
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

  for (final locale in const [Locale('zh'), Locale('en')]) {
    testWidgets('about section shows v0.9 fallback in ${locale.languageCode}', (
      tester,
    ) async {
      await pumpScreen(tester, locale: locale);
      expect(
        find.text(locale.languageCode == 'en' ? 'Version' : '版本'),
        findsOneWidget,
      );
      expect(find.text('0.9.0+13'), findsOneWidget);
      expect(
        find.text(
          locale.languageCode == 'en'
              ? 'No ads · No account · No cloud sync · '
                    'No network permission · System camera'
              : '无广告 · 无账号 · 无云同步 · 发布包无网络权限 · 调用系统相机',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          locale.languageCode == 'en'
              ? 'The release APK requests no network permission; GitHub '
                    'links open in an external browser. Foreground location '
                    'is used only when requested, and a diagnostic bundle '
                    'reaches the system share sheet only after confirmation.'
              : '发布包不申请网络权限；GitHub 链接交给外部浏览器。前台定位仅在用户主动请求时使用，'
                    '诊断包仅在用户确认后交给系统分享面板。',
        ),
        findsOneWidget,
      );
    });
  }

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

  testWidgets('about prefers successful package metadata over fallback', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'SiteMark test',
      packageName: 'io.github.wikg1018.sitemark.test',
      version: '9.8.7',
      buildNumber: '654',
      buildSignature: 'test-signature',
    );

    await pumpScreen(tester, locale: const Locale('en'));

    expect(find.text('9.8.7+654'), findsOneWidget);
    expect(find.text('0.9.0+13'), findsNothing);
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
