308cc46 feat: add appearance settings sub-page

--- diff stat ---

 .../sections/appearance_section_screen.dart        | 65 ++++++++++++++++++++++
 .../sections/appearance_section_screen_test.dart   | 57 +++++++++++++++++++
 2 files changed, 122 insertions(+)

--- full diff (U10) ---

diff --git a/lib/features/settings/sections/appearance_section_screen.dart b/lib/features/settings/sections/appearance_section_screen.dart
new file mode 100644
index 0000000..7e79b76
--- /dev/null
+++ b/lib/features/settings/sections/appearance_section_screen.dart
@@ -0,0 +1,65 @@
+// lib/features/settings/sections/appearance_section_screen.dart
+import 'package:flutter/material.dart';
+import 'package:flutter_riverpod/flutter_riverpod.dart';
+import 'package:sitemark/features/settings/app_setting_controller.dart';
+import 'package:sitemark/features/settings/settings_section_scaffold.dart';
+import 'package:sitemark/l10n/app_strings.dart';
+
+class AppearanceSectionScreen extends ConsumerWidget {
+  const AppearanceSectionScreen({super.key});
+
+  @override
+  Widget build(BuildContext context, WidgetRef ref) {
+    final strings = AppStrings.of(context);
+    final asyncSettings = ref.watch(appSettingControllerProvider);
+    final settings = asyncSettings.value;
+    if (settings == null) {
+      return SettingsSectionScaffold(
+        title: strings.appearance,
+        body: const Center(child: CircularProgressIndicator()),
+      );
+    }
+    return SettingsSectionScaffold(
+      title: strings.appearance,
+      body: Column(
+        crossAxisAlignment: CrossAxisAlignment.stretch,
+        children: [
+          Text(strings.theme, style: Theme.of(context).textTheme.titleMedium),
+          const SizedBox(height: 8),
+          SegmentedButton<String>(
+            key: const Key('theme-segmented'),
+            style: segmentTapTargetStyle,
+            segments: [
+              ButtonSegment(
+                value: 'system',
+                label: Text(strings.systemTheme, key: const Key('theme-system')),
+              ),
+              ButtonSegment(
+                value: 'light',
+                label: Text(strings.lightTheme, key: const Key('theme-light')),
+              ),
+              ButtonSegment(
+                value: 'dark',
+                label: Text(strings.darkTheme, key: const Key('theme-dark')),
+              ),
+            ],
+            selected: {settings.themeMode},
+            onSelectionChanged: (selection) => ref
+                .read(appSettingControllerProvider.notifier)
+                .update((s) => s.copyWith(themeMode: selection.single)),
+          ),
+          const SizedBox(height: 8),
+          SwitchListTile(
+            key: const Key('dynamic-color-switch'),
+            title: Text(strings.dynamicColorTitle),
+            subtitle: Text(strings.dynamicColorSubtitle),
+            value: settings.useDynamicColor,
+            onChanged: (value) => ref
+                .read(appSettingControllerProvider.notifier)
+                .update((s) => s.copyWith(useDynamicColor: value)),
+          ),
+        ],
+      ),
+    );
+  }
+}
diff --git a/test/features/settings/sections/appearance_section_screen_test.dart b/test/features/settings/sections/appearance_section_screen_test.dart
new file mode 100644
index 0000000..a5721c2
--- /dev/null
+++ b/test/features/settings/sections/appearance_section_screen_test.dart
@@ -0,0 +1,57 @@
+// test/features/settings/sections/appearance_section_screen_test.dart
+import 'package:drift/native.dart';
+import 'package:flutter/material.dart';
+import 'package:flutter_localizations/flutter_localizations.dart';
+import 'package:flutter_riverpod/flutter_riverpod.dart';
+import 'package:flutter_test/flutter_test.dart';
+import 'package:sitemark/app.dart';
+import 'package:sitemark/data/app_database.dart';
+import 'package:sitemark/features/settings/sections/appearance_section_screen.dart';
+import 'package:sitemark/l10n/app_strings.dart';
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
+  Future<void> pumpScreen(WidgetTester tester) async {
+    await database.getAppSettings();
+    await tester.pumpWidget(
+      ProviderScope(
+        overrides: [databaseProvider.overrideWithValue(database)],
+        child: MaterialApp(
+          locale: const Locale('zh'),
+          supportedLocales: AppStrings.supportedLocales,
+          localizationsDelegates: const [
+            AppStrings.delegate,
+            GlobalMaterialLocalizations.delegate,
+            GlobalWidgetsLocalizations.delegate,
+            GlobalCupertinoLocalizations.delegate,
+          ],
+          home: const AppearanceSectionScreen(),
+        ),
+      ),
+    );
+    await tester.pumpAndSettle();
+  }
+
+  testWidgets('theme selection persists', (tester) async {
+    await pumpScreen(tester);
+    await tester.tap(find.byKey(const Key('theme-dark')));
+    await tester.pumpAndSettle();
+    expect((await database.getAppSettings()).themeMode, 'dark');
+  });
+
+  testWidgets('dynamic color switch persists', (tester) async {
+    await pumpScreen(tester);
+    await tester.tap(find.byKey(const Key('dynamic-color-switch')));
+    await tester.pumpAndSettle();
+    expect((await database.getAppSettings()).useDynamicColor, isTrue);
+  });
+}
