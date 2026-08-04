# Task 9: Create AboutSectionScreen

**Source:** `docs/superpowers/plans/2026-07-25-settings-secondary-menu.md` (Task 9)

## Goal
Migrate `_AboutSection` + `_loadPackageInfo` + `_openRepository` from `global_settings_screen.dart` into its own sub-page. Uses `PackageInfo.fromPlatform()` and `externalLinkServiceProvider`. Does NOT use `appSettingControllerProvider`.

## Files
- Create: `lib/features/settings/sections/about_section_screen.dart`
- Test: `test/features/settings/sections/about_section_screen_test.dart`

## Interfaces
- Consumes: `externalLinkServiceProvider` (from `lib/app.dart`), `PackageInfo.fromPlatform()` (from `package:package_info_plus/package_info_plus.dart`), `siteMarkRepositoryUri` + `siteMarkRepositoryUrl` (from `package:sitemark/domain/app_links.dart`), `AppStrings`, fallback constants `_fallbackVersion = '0.4.0'` and `_fallbackBuild = '4'`
- Produces: `AboutSectionScreen` widget (used by Task 11 routes)

## Context for the implementer
- The existing `global_settings_screen.dart:118-131` defines `_loadPackageInfo`. Migrate verbatim into a `ConsumerStatefulWidget`.
- The existing `global_settings_screen.dart:177-194` defines `_openRepository`. Migrate verbatim.
- The existing `global_settings_screen.dart:744-805` defines `_AboutSection` (StatelessWidget). Migrate verbatim — keep all keys: `github-repository-link`.
- The fallback constants `_fallbackVersion = '0.4.0'` and `_fallbackBuild = '4'` are at `global_settings_screen.dart:16-17`. Define them in the new file (or inline). They are needed because `PackageInfo.fromPlatform()` throws in unit tests without a platform plugin.
- The screen uses `SettingsSectionScaffold`. The body is the `_AboutSection` (or its content, inlined).
- `externalLinkServiceProvider` is defined at `lib/app.dart:135` as `Provider<ExternalLinkService>`.
- `ExternalLinkService` is an `abstract interface class` at `lib/platform/external_link_service.dart:3` with one method: `Future<bool> open(Uri uri)`.
- The existing `global_settings_screen_test.dart` defines 3 about tests at lines 227-237 (fallback version), 421-439 (open repo URL success), 441-457 (open repo URL failure). Migrate them with minimal adjustments (no scrolling needed because the screen body is just the about content).
- The `_RecordingExternalLinkService` test double is at `global_settings_screen_test.dart:638-649`. Copy verbatim.
- l10n keys (all verified): `about`, `version`, `privacyStatements`, `privacySummary`, `repository`, `license`, `licenseValue`, `licenses`, `appName`, `openLinkFailed`.

## TDD steps

### Step 1: Write the failing test

```dart
// test/features/settings/sections/about_section_screen_test.dart
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
    expect(find.textContaining('0.4.0'), findsOneWidget);
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
```

### Step 2: Run test to verify it fails
Run: `flutter test test/features/settings/sections/about_section_screen_test.dart`
Expected: FAIL — file does not exist.

### Step 3: Write minimal implementation

```dart
// lib/features/settings/sections/about_section_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/domain/app_links.dart';
import 'package:sitemark/features/settings/settings_section_scaffold.dart';
import 'package:sitemark/l10n/app_strings.dart';

/// Fallback version/build used when [PackageInfo.fromPlatform] fails (e.g. in
/// unit tests where no platform plugin is available).
const _fallbackVersion = '0.4.0';
const _fallbackBuild = '4';

class AboutSectionScreen extends ConsumerStatefulWidget {
  const AboutSectionScreen({super.key});

  @override
  ConsumerState<AboutSectionScreen> createState() =>
      _AboutSectionScreenState();
}

class _AboutSectionScreenState extends ConsumerState<AboutSectionScreen> {
  String _version = _fallbackVersion;
  String _buildNumber = _fallbackBuild;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = info.version.isEmpty ? _fallbackVersion : info.version;
        _buildNumber = info.buildNumber.isEmpty
            ? _fallbackBuild
            : info.buildNumber;
      });
    } catch (_) {
      // 无平台插件时保留 fallback 常量；关于区块仍可正常渲染。
    }
  }

  Future<void> _openRepository(BuildContext context) async {
    try {
      final opened = await ref
          .read(externalLinkServiceProvider)
          .open(siteMarkRepositoryUri);
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).openLinkFailed)),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).openLinkFailed)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SettingsSectionScaffold(
      title: strings.about,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(strings.version),
            trailing: Text('$_version+$_buildNumber'),
          ),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: Text(strings.privacyStatements),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              strings.privacySummary,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          ListTile(
            key: const Key('github-repository-link'),
            leading: const Icon(Icons.source_outlined),
            title: Text(strings.repository),
            subtitle: const Text(siteMarkRepositoryUrl),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => _openRepository(context),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(strings.license),
            subtitle: Text(strings.licenseValue),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: strings.appName,
              applicationVersion: '$_version+$_buildNumber',
            ),
            icon: const Icon(Icons.article_outlined),
            label: Text(strings.licenses),
          ),
        ],
      ),
    );
  }
}
```

### Step 4: Run test to verify it passes
Run: `flutter test test/features/settings/sections/about_section_screen_test.dart`
Expected: PASS (3/3)

### Step 5: Run flutter analyze
Run: `flutter analyze lib/features/settings/sections/about_section_screen.dart test/features/settings/sections/about_section_screen_test.dart`
Expected: No issues.

### Step 6: Commit
```
git add lib/features/settings/sections/about_section_screen.dart test/features/settings/sections/about_section_screen_test.dart
git commit -m "feat: add about settings sub-page"
```

## Notes
- The screen uses `SettingsSectionScaffold`. The body is the `_AboutSection` content inlined directly (no separate `_AboutSection` widget — the section header is dropped because the AppBar now carries the `about` title, mirroring Task 6's storage approach).
- The fallback version `'0.4.0'` and build `'4'` MUST match the constants in `global_settings_screen.dart:16-17` so the test `find.textContaining('0.4.0')` passes.
- The `_loadPackageInfo` is async and runs in `initState`. In tests, `PackageInfo.fromPlatform()` throws (no platform plugin), so the catch block leaves the fallback values in place. The test `pumpAndSettle()` will resolve the future.
- Do NOT modify `global_settings_screen.dart` in this task.
- The existing `global_settings_screen_test.dart` about tests (lines 227-237, 421-457) will remain in place. Task 10/12 will remove them when the old screen is rewritten.

## Global Constraints (binding)
- All existing widget test assertions must pass after refactor (234+ tests).
- l10n keys are unchanged — reuse existing `AppStrings` keys.
- No new dependencies; no schema changes.
- Commit messages in English; code comments in Chinese for domain logic, English for technical.
