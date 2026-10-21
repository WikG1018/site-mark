import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/app_links.dart';
import 'package:sitemark/domain/release_check.dart';
import 'package:sitemark/features/settings/sections/about_section_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/external_link_service.dart';
import 'package:sitemark/platform/github_release_client.dart';
import 'package:sitemark/platform/release_check_mode_store.dart';

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
    ReleaseLookup? lookup,
    ReleaseCheckModeStore? modeStore,
    Locale locale = const Locale('zh'),
  }) async {
    await database.getAppSettings();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          releaseCheckModeStoreProvider.overrideWithValue(
            modeStore ?? MemoryReleaseCheckModeStore(),
          ),
          if (lookup != null) releaseLookupProvider.overrideWithValue(lookup),
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
    testWidgets('about section shows v1.0 fallback in ${locale.languageCode}', (
      tester,
    ) async {
      await pumpScreen(tester, locale: locale);
      expect(
        find.text(locale.languageCode == 'en' ? 'Version' : '版本'),
        findsOneWidget,
      );
      expect(find.text('1.0.31+46'), findsOneWidget);
      expect(
        find.text(locale.languageCode == 'en' ? 'Check for updates' : '检查更新'),
        findsOneWidget,
      );
      expect(
        find.text(
          locale.languageCode == 'en'
              ? 'No ads · No account · No third-party cloud · '
                    'Optional NAS sync · System camera'
              : '无广告 · 无账号 · 无第三方云同步 · 可选 NAS 同步 · 调用系统相机',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          locale.languageCode == 'en'
              ? 'Offline by default. Network is used only when you open it: NAS '
                    'sync (WebDAV, SFTP or SMB) connects only to the server you '
                    'configure. Check for updates on the About page reads the '
                    'public GitHub release version first by default; in '
                    'Automatic mode it tries a fixed public mirror only if '
                    'GitHub cannot be reached, and you can switch to Official '
                    'only or Mirror first. It does not upload photos or an '
                    'account. GitHub links open in an external browser. '
                    'Foreground location is used only when requested, and a '
                    'diagnostic bundle reaches the system share sheet only '
                    'after confirmation.'
              : '默认离线。网络只在你主动打开时使用：NAS 同步（WebDAV/SFTP/SMB）只连接你配置的服务器；'
                    '关于页的检查更新默认先读取 GitHub 公开版本号，自动模式下连不上才试固定的公开镜像，'
                    '也可以改成仅官方或优先镜像，不上传照片或账号。GitHub 链接交给外部浏览器。'
                    '前台定位仅在用户主动请求时使用，诊断包仅在用户确认后交给系统分享面板。',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('无网络权限'), findsNothing);
      expect(find.textContaining('不申请网络权限'), findsNothing);
      expect(find.textContaining('No network permission'), findsNothing);
      expect(find.textContaining('no network permission'), findsNothing);
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
    expect(find.text('1.0.29+44'), findsNothing);
  });

  testWidgets('about does not check for updates until the tile is tapped', (
    tester,
  ) async {
    final lookup = _FakeReleaseLookup();
    await pumpScreen(tester, lookup: lookup);
    expect(lookup.checks, 0);
    expect(find.text('正在检查…'), findsNothing);
    expect(find.text('已是最新版本'), findsNothing);
    expect(find.text('无法检查更新。请检查网络后再试。'), findsNothing);
  });

  testWidgets('check reports up to date without an open button', (
    tester,
  ) async {
    final lookup = _FakeReleaseLookup(
      outcome: const ReleaseCheckOutcome(
        status: ReleaseCheckStatus.upToDate,
        versionLabel: '1.0.29',
        tag: 'v1.0.29',
        source: ReleaseSource.official,
      ),
    );
    await pumpScreen(tester, lookup: lookup);
    await tester.tap(find.byKey(const Key('check-for-updates')));
    await tester.pumpAndSettle();
    expect(lookup.checks, 1);
    expect(lookup.modes, [ReleaseCheckMode.auto]);
    expect(find.text('已是最新版本'), findsOneWidget);
    expect(find.byKey(const Key('open-release-page')), findsNothing);
  });

  testWidgets('an update opens the Uri from the lookup', (tester) async {
    final page = Uri.parse(
      'https://gh.llkk.cc/https://github.com/WikG1018/site-mark/releases/tag/v1.0.30',
    );
    final links = _RecordingExternalLinkService();
    final lookup = _FakeReleaseLookup(
      outcome: const ReleaseCheckOutcome(
        status: ReleaseCheckStatus.updateAvailable,
        versionLabel: '1.0.30',
        tag: 'v1.0.30',
        source: ReleaseSource.apiMirror,
      ),
      page: page,
    );
    await pumpScreen(tester, lookup: lookup, externalLinks: links);
    await tester.tap(find.byKey(const Key('check-for-updates')));
    await tester.pumpAndSettle();
    expect(find.text('发现新版本 1.0.30'), findsOneWidget);
    expect(find.text('已是最新版本'), findsNothing);
    expect(find.byKey(const Key('ios-release-note')), findsNothing);

    await tester.tap(find.byKey(const Key('open-release-page')));
    await tester.pumpAndSettle();
    expect(links.opened, [page]);

    await tester.tap(find.byKey(const Key('check-for-updates')));
    await tester.pumpAndSettle();
    expect(links.opened, [page, page]);
    expect(lookup.checks, 1);
  });

  testWidgets('a thrown check does not claim the app is up to date', (
    tester,
  ) async {
    final lookup = _FakeReleaseLookup(throwOnCheck: true);
    await pumpScreen(tester, lookup: lookup);
    await tester.tap(find.byKey(const Key('check-for-updates')));
    await tester.pumpAndSettle();
    expect(find.text('无法检查更新。请检查网络后再试。'), findsOneWidget);
    expect(find.text('已是最新版本'), findsNothing);
    expect(find.byKey(const Key('open-release-page')), findsNothing);
  });

  testWidgets('changing the source does not send a request', (tester) async {
    final lookup = _FakeReleaseLookup();
    final modes = MemoryReleaseCheckModeStore();
    await pumpScreen(tester, lookup: lookup, modeStore: modes);
    await tester.tap(find.text('仅官方'));
    await tester.pumpAndSettle();
    expect(lookup.checks, 0);
    expect(modes.mode, ReleaseCheckMode.official);
    await tester.tap(find.text('优先镜像'));
    await tester.pumpAndSettle();
    expect(lookup.checks, 0);
    expect(modes.mode, ReleaseCheckMode.mirror);
  });

  testWidgets('iOS still opens the release page and says no iOS package', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final page = Uri.parse(
        'https://github.com/WikG1018/site-mark/releases/tag/v1.0.30',
      );
      final links = _RecordingExternalLinkService();
      final lookup = _FakeReleaseLookup(
        outcome: const ReleaseCheckOutcome(
          status: ReleaseCheckStatus.updateAvailable,
          versionLabel: '1.0.30',
          tag: 'v1.0.30',
          source: ReleaseSource.official,
        ),
        page: page,
      );
      await pumpScreen(tester, lookup: lookup, externalLinks: links);
      await tester.tap(find.byKey(const Key('check-for-updates')));
      await tester.pumpAndSettle();
      expect(find.text('iOS 安装包尚未提供，发布页目前只有 Android 安装包。'), findsOneWidget);
      await tester.tap(find.byKey(const Key('open-release-page')));
      await tester.pumpAndSettle();
      expect(links.opened, [page]);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
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

class _FakeReleaseLookup implements ReleaseLookup {
  _FakeReleaseLookup({this.outcome, this.page, this.throwOnCheck = false});

  final ReleaseCheckOutcome? outcome;
  final Uri? page;
  final bool throwOnCheck;
  int checks = 0;
  final List<ReleaseCheckMode> modes = [];

  @override
  Future<ReleaseCheckOutcome> check({
    required String localVersion,
    required ReleaseCheckMode mode,
  }) async {
    checks += 1;
    modes.add(mode);
    if (throwOnCheck) throw StateError('network');
    return outcome ?? const ReleaseCheckOutcome.failed();
  }

  @override
  Future<Uri?> resolveReleasePage(ReleaseCheckOutcome outcome) async => page;
}
