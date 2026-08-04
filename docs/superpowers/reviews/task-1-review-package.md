adc06c3 feat: add AppSettingController for shared settings state

--- diff stat ---

 lib/features/settings/app_setting_controller.dart  | 65 ++++++++++++++++++++++
 .../settings/app_setting_controller_test.dart      | 44 +++++++++++++++
 2 files changed, 109 insertions(+)

--- full diff (U10) ---

diff --git a/lib/features/settings/app_setting_controller.dart b/lib/features/settings/app_setting_controller.dart
new file mode 100644
index 0000000..d2961a8
--- /dev/null
+++ b/lib/features/settings/app_setting_controller.dart
@@ -0,0 +1,65 @@
+import 'dart:async';
+
+import 'package:flutter_riverpod/flutter_riverpod.dart';
+import 'package:sitemark/app.dart';
+import 'package:sitemark/data/app_database.dart';
+
+/// Centralizes [AppSetting] read/persist logic for all settings sub-pages.
+///
+/// Sub-pages `ref.watch(appSettingControllerProvider)` for auto-rebuild on
+/// change. Call [update] with a functional updater to modify the setting:
+/// the controller optimistic-updates the state, then persists to the database.
+class AppSettingController extends AsyncNotifier<AppSetting> {
+  @override
+  Future<AppSetting> build() {
+    final db = ref.read(databaseProvider);
+    return db.getAppSettings();
+  }
+
+  /// Updates the [AppSetting] optimistically, then persists to the database.
+  /// If persistence fails, the state rolls back to the previous value.
+  ///
+  /// Overrides Riverpod's built-in [AsyncNotifier.update] to interleave the
+  /// database write between the optimistic state set and the return.
+  @override
+  Future<AppSetting> update(
+    FutureOr<AppSetting> Function(AppSetting current) updater, {
+    FutureOr<AppSetting> Function(Object error, StackTrace stackTrace)?
+        onError,
+  }) async {
+    final current = state.value;
+    if (current == null) {
+      // State is loading/error; defer to the default behavior so callers
+      // wiring `onError` still get the expected contract.
+      return super.update(updater, onError: onError);
+    }
+    final next = await updater(current);
+    state = AsyncData(next);
+    try {
+      final db = ref.read(databaseProvider);
+      await db.updateAppSettings(
+        themeMode: next.themeMode,
+        useDynamicColor: next.useDynamicColor,
+        localeCode: next.localeCode,
+        defaultWatermarkPosition: next.defaultWatermarkPosition,
+        defaultWatermarkOpacity: next.defaultWatermarkOpacity,
+        defaultWatermarkFontScale: next.defaultWatermarkFontScale,
+        defaultWatermarkAccentColorArgb: next.defaultWatermarkAccentColorArgb,
+        completionNotificationsEnabled: next.completionNotificationsEnabled,
+      );
+      return next;
+    } catch (e, st) {
+      // Roll back to the previous value on persist failure.
+      state = AsyncData(current);
+      if (onError != null) {
+        return await onError(e, st);
+      }
+      rethrow;
+    }
+  }
+}
+
+final appSettingControllerProvider =
+    AsyncNotifierProvider<AppSettingController, AppSetting>(
+  AppSettingController.new,
+);
diff --git a/test/features/settings/app_setting_controller_test.dart b/test/features/settings/app_setting_controller_test.dart
new file mode 100644
index 0000000..61fa47b
--- /dev/null
+++ b/test/features/settings/app_setting_controller_test.dart
@@ -0,0 +1,44 @@
+// ignore_for_file: lines_longer_than_80_chars
+import 'package:drift/native.dart';
+import 'package:flutter_riverpod/flutter_riverpod.dart';
+import 'package:flutter_test/flutter_test.dart';
+import 'package:sitemark/app.dart';
+import 'package:sitemark/data/app_database.dart';
+import 'package:sitemark/features/settings/app_setting_controller.dart';
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
+  test('build loads the singleton AppSetting', () async {
+    await database.getAppSettings();
+    final container = ProviderContainer(
+      overrides: [databaseProvider.overrideWithValue(database)],
+    );
+    addTearDown(container.dispose);
+    final result = await container.read(appSettingControllerProvider.future);
+    expect(result.themeMode, 'system');
+  });
+
+  test('update persists and reflects the new value', () async {
+    await database.getAppSettings();
+    final container = ProviderContainer(
+      overrides: [databaseProvider.overrideWithValue(database)],
+    );
+    addTearDown(container.dispose);
+    await container.read(appSettingControllerProvider.future);
+    await container
+        .read(appSettingControllerProvider.notifier)
+        .update((s) => s.copyWith(themeMode: 'dark'));
+    final fromDb = await database.getAppSettings();
+    expect(fromDb.themeMode, 'dark');
+    expect(container.read(appSettingControllerProvider).value?.themeMode, 'dark');
+  });
+}
