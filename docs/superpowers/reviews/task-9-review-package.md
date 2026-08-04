## Commit list

750c4a6 feat: add about settings sub-page

## Diff stat

 .../settings/sections/about_section_screen.dart    | 117 +++++++++++++++++++++
 .../sections/about_section_screen_test.dart        |  99 +++++++++++++++++
 2 files changed, 216 insertions(+)

## Full diff

diff --git a/lib/features/settings/sections/about_section_screen.dart b/lib/features/settings/sections/about_section_screen.dart
new file mode 100644
index 0000000..20b4405
--- /dev/null
+++ b/lib/features/settings/sections/about_section_screen.dart
@@ -0,0 +1,117 @@
+import 'package:flutter/material.dart';
+import 'package:flutter_riverpod/flutter_riverpod.dart';
+import 'package:package_info_plus/package_info_plus.dart';
+import 'package:sitemark/app.dart';
+import 'package:sitemark/domain/app_links.dart';
+import 'package:sitemark/features/settings/settings_section_scaffold.dart';
+import 'package:sitemark/l10n/app_strings.dart';
+
+/// Fallback version/build used when [PackageInfo.fromPlatform] fails (e.g. in
+/// unit tests where no platform plugin is available).
+const _fallbackVersion = '0.4.0';
+const _fallbackBuild = '4';
+
+class AboutSectionScreen extends ConsumerStatefulWidget {
+  const AboutSectionScreen({super.key});
+
+  @override
+  ConsumerState<AboutSectionScreen> createState() =>
+      _AboutSectionScreenState();
+}
+
+class _AboutSectionScreenState extends ConsumerState<AboutSectionScreen> {
+  String _version = _fallbackVersion;
+  String _buildNumber = _fallbackBuild;
+
+  @override
+  void initState() {
+    super.initState();
+    _loadPackageInfo();
+  }
+
+  Future<void> _loadPackageInfo() async {
+    try {
+      final info = await PackageInfo.fromPlatform();
+      if (!mounted) return;
+      setState(() {
+        _version = info.version.isEmpty ? _fallbackVersion : info.version;
+        _buildNumber = info.buildNumber.isEmpty
+            ? _fallbackBuild
+            : info.buildNumber;
+      });
+    } catch (_) {
+      // 无平台插件时保留 fallback 常量；关于区块仍可正常渲染。
+    }
+  }
+
+  Future<void> _openRepository(BuildContext context) async {
+    try {
+      final opened = await ref
+          .read(externalLinkServiceProvider)
+          .open(siteMarkRepositoryUri);
+      if (!opened && context.mounted) {
+        ScaffoldMessenger.of(context).showSnackBar(
+          SnackBar(content: Text(AppStrings.of(context).openLinkFailed)),
+        );
+      }
+    } catch (_) {
+      if (context.mounted) {
+        ScaffoldMessenger.of(context).showSnackBar(
+          SnackBar(content: Text(AppStrings.of(context).openLinkFailed)),
+        );
+      }
+    }
+  }
+
+  @override
+  Widget build(BuildContext context) {
+    final strings = AppStrings.of(context);
+    return SettingsSectionScaffold(
+      title: strings.about,
+      body: Column(
+        crossAxisAlignment: CrossAxisAlignment.start,
+        children: [
+          ListTile(
+            leading: const Icon(Icons.info_outline),
+            title: Text(strings.version),
+            trailing: Text('$_version+$_buildNumber'),
+          ),
+          ListTile(
+            leading: const Icon(Icons.shield_outlined),
+            title: Text(strings.privacyStatements),
+          ),
+          Padding(
+            padding: const EdgeInsets.symmetric(horizontal: 16),
+            child: Text(
+              strings.privacySummary,
+              style: Theme.of(context).textTheme.bodySmall,
+            ),
+          ),
+          ListTile(
+            key: const Key('github-repository-link'),
+            leading: const Icon(Icons.source_outlined),
+            title: Text(strings.repository),
+            subtitle: const Text(siteMarkRepositoryUrl),
+            trailing: const Icon(Icons.open_in_new),
+            onTap: () => _openRepository(context),
+          ),
+          ListTile(
+            leading: const Icon(Icons.description_outlined),
+            title: Text(strings.license),
+            subtitle: Text(strings.licenseValue),
+          ),
+          const SizedBox(height: 8),
+          FilledButton.tonalIcon(
+            onPressed: () => showLicensePage(
+              context: context,
+              applicationName: strings.appName,
+              applicationVersion: '$_version+$_buildNumber',
+            ),
+            icon: const Icon(Icons.article_outlined),
+            label: Text(strings.licenses),
+          ),
+        ],
+      ),
+    );
+  }
+}
diff --git a/test/features/settings/sections/about_section_screen_test.dart b/test/features/settings/sections/about_section_screen_test.dart
new file mode 100644
index 0000000..1e5d9e4
--- /dev/null
+++ b/test/features/settings/sections/about_section_screen_test.dart
@@ -0,0 +1,99 @@
+import 'package:drift/native.dart';
+import 'package:flutter/material.dart';
+import 'package:flutter_localizations/flutter_localizations.dart';
+import 'package:flutter_riverpod/flutter_riverpod.dart';
+import 'package:flutter_test/flutter_test.dart';
+import 'package:sitemark/app.dart';
+import 'package:sitemark/data/app_database.dart';
+import 'package:sitemark/domain/app_links.dart';
+import 'package:sitemark/features/settings/sections/about_section_screen.dart';
+import 'package:sitemark/l10n/app_strings.dart';
+import 'package:sitemark/platform/external_link_service.dart';
+
+void main() {
+  late AppDatabase database;
+
+  setUp(() {
+    database = AppDatabase.forTesting(NativeDatabase.memory());
+  });
+
+  tearDown(() async {
+    await database.close();
+  });
+
+  Future<void> pumpScreen(
+    WidgetTester tester, {
+    ExternalLinkService? externalLinks,
+  }) async {
+    await database.getAppSettings();
+    await tester.pumpWidget(
+      ProviderScope(
+        overrides: [
+          databaseProvider.overrideWithValue(database),
+          if (externalLinks != null)
+            externalLinkServiceProvider.overrideWithValue(externalLinks),
+        ],
+        child: MaterialApp(
+          locale: const Locale('zh'),
+          supportedLocales: AppStrings.supportedLocales,
+          localizationsDelegates: const [
+            AppStrings.delegate,
+            GlobalMaterialLocalizations.delegate,
+            GlobalWidgetsLocalizations.delegate,
+            GlobalCupertinoLocalizations.delegate,
+          ],
+          home: const AboutSectionScreen(),
+        ),
+      ),
+    );
+    await tester.pumpAndSettle();
+  }
+
+  testWidgets('about section shows fallback version when PackageInfo fails', (
+    tester,
+  ) async {
+    await pumpScreen(tester);
+    expect(find.textContaining('0.4.0'), findsOneWidget);
+  });
+
+  testWidgets('about shows and opens the full GitHub repository URL', (
+    tester,
+  ) async {
+    final links = _RecordingExternalLinkService();
+    await pumpScreen(tester, externalLinks: links);
+    expect(find.text('GitHub 代码仓库'), findsOneWidget);
+    expect(find.text(siteMarkRepositoryUrl), findsOneWidget);
+
+    await tester.ensureVisible(find.byKey(const Key('github-repository-link')));
+    await tester.pumpAndSettle();
+    await tester.tap(find.byKey(const Key('github-repository-link')));
+    await tester.pump();
+    expect(links.opened, [siteMarkRepositoryUri]);
+  });
+
+  testWidgets('about shows a snackbar when opening the repository fails', (
+    tester,
+  ) async {
+    final links = _RecordingExternalLinkService(result: false);
+    await pumpScreen(tester, externalLinks: links);
+    await tester.ensureVisible(find.byKey(const Key('github-repository-link')));
+    await tester.pumpAndSettle();
+    await tester.tap(find.byKey(const Key('github-repository-link')));
+    await tester.pump();
+    expect(find.text('无法打开浏览器'), findsOneWidget);
+    expect(links.opened, [siteMarkRepositoryUri]);
+  });
+}
+
+class _RecordingExternalLinkService implements ExternalLinkService {
+  _RecordingExternalLinkService({this.result = true});
+
+  final bool result;
+  final List<Uri> opened = [];
+
+  @override
+  Future<bool> open(Uri uri) async {
+    opened.add(uri);
+    return result;
+  }
+}
