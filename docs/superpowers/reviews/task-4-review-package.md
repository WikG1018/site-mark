b64cb1b feat: add language settings sub-page

--- diff stat ---

 .../settings/sections/language_section_screen.dart | 51 ++++++++++++++++++++++
 .../sections/language_section_screen_test.dart     | 46 +++++++++++++++++++
 2 files changed, 97 insertions(+)

--- full diff (U10) ---

diff --git a/lib/features/settings/sections/language_section_screen.dart b/lib/features/settings/sections/language_section_screen.dart
new file mode 100644
index 0000000..6604cf5
--- /dev/null
+++ b/lib/features/settings/sections/language_section_screen.dart
@@ -0,0 +1,51 @@
+// lib/features/settings/sections/language_section_screen.dart
+import 'package:drift/drift.dart' show Value;
+import 'package:flutter/material.dart';
+import 'package:flutter_riverpod/flutter_riverpod.dart';
+import 'package:sitemark/features/settings/app_setting_controller.dart';
+import 'package:sitemark/features/settings/settings_section_scaffold.dart';
+import 'package:sitemark/l10n/app_strings.dart';
+
+class LanguageSectionScreen extends ConsumerWidget {
+  const LanguageSectionScreen({super.key});
+
+  @override
+  Widget build(BuildContext context, WidgetRef ref) {
+    final strings = AppStrings.of(context);
+    final asyncSettings = ref.watch(appSettingControllerProvider);
+    final settings = asyncSettings.value;
+    if (settings == null) {
+      return SettingsSectionScaffold(
+        title: strings.language,
+        body: const Center(child: CircularProgressIndicator()),
+      );
+    }
+    return SettingsSectionScaffold(
+      title: strings.language,
+      body: SegmentedButton<String?>(
+        key: const Key('language-segmented'),
+        style: segmentTapTargetStyle,
+        segments: [
+          ButtonSegment(
+            value: null,
+            label: Text(strings.systemLanguage, key: const Key('language-system')),
+          ),
+          ButtonSegment(
+            value: 'zh',
+            label: Text(strings.chinese, key: const Key('language-zh')),
+          ),
+          ButtonSegment(
+            value: 'en',
+            label: Text(strings.english, key: const Key('language-en')),
+          ),
+        ],
+        selected: {
+          (settings.localeCode?.isEmpty ?? true) ? null : settings.localeCode,
+        },
+        onSelectionChanged: (selection) => ref
+            .read(appSettingControllerProvider.notifier)
+            .update((s) => s.copyWith(localeCode: Value(selection.single ?? ''))),
+      ),
+    );
+  }
+}
diff --git a/test/features/settings/sections/language_section_screen_test.dart b/test/features/settings/sections/language_section_screen_test.dart
new file mode 100644
index 0000000..c78f56a
--- /dev/null
+++ b/test/features/settings/sections/language_section_screen_test.dart
@@ -0,0 +1,46 @@
+// test/features/settings/sections/language_section_screen_test.dart
+import 'package:drift/native.dart';
+import 'package:flutter/material.dart';
+import 'package:flutter_localizations/flutter_localizations.dart';
+import 'package:flutter_riverpod/flutter_riverpod.dart';
+import 'package:flutter_test/flutter_test.dart';
+import 'package:sitemark/app.dart';
+import 'package:sitemark/data/app_database.dart';
+import 'package:sitemark/features/settings/sections/language_section_screen.dart';
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
+  testWidgets('language selection persists', (tester) async {
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
+          home: const LanguageSectionScreen(),
+        ),
+      ),
+    );
+    await tester.pumpAndSettle();
+    await tester.tap(find.byKey(const Key('language-en')));
+    await tester.pumpAndSettle();
+    expect((await database.getAppSettings()).localeCode, 'en');
+  });
+}
