## Commit list

60e3326 feat: add notification settings sub-page

## Diff stat

 .../sections/notification_section_screen.dart      |  73 +++++++++++++
 .../sections/notification_section_screen_test.dart | 115 +++++++++++++++++++++
 2 files changed, 188 insertions(+)

## Full diff

diff --git a/lib/features/settings/sections/notification_section_screen.dart b/lib/features/settings/sections/notification_section_screen.dart
new file mode 100644
index 0000000..44e7144
--- /dev/null
+++ b/lib/features/settings/sections/notification_section_screen.dart
@@ -0,0 +1,73 @@
+// lib/features/settings/sections/notification_section_screen.dart
+import 'package:flutter/material.dart';
+import 'package:flutter_riverpod/flutter_riverpod.dart';
+import 'package:sitemark/features/settings/app_setting_controller.dart';
+import 'package:sitemark/features/settings/settings_section_scaffold.dart';
+import 'package:sitemark/l10n/app_strings.dart';
+import 'package:sitemark/platform/notification_service.dart';
+
+class NotificationSectionScreen extends ConsumerWidget {
+  const NotificationSectionScreen({super.key});
+
+  @override
+  Widget build(BuildContext context, WidgetRef ref) {
+    final strings = AppStrings.of(context);
+    final asyncSettings = ref.watch(appSettingControllerProvider);
+    final settings = asyncSettings.value;
+    if (settings == null) {
+      return SettingsSectionScaffold(
+        title: strings.completionNotificationTitle,
+        body: const Center(child: CircularProgressIndicator()),
+      );
+    }
+    return SettingsSectionScaffold(
+      title: strings.completionNotificationTitle,
+      body: Column(
+        crossAxisAlignment: CrossAxisAlignment.stretch,
+        children: [
+          SwitchListTile(
+            key: const Key('completion-notification-switch'),
+            title: Text(strings.completionNotificationTitle),
+            subtitle: Text(strings.completionNotificationSubtitle),
+            value: settings.completionNotificationsEnabled,
+            onChanged: (value) =>
+                _onCompletionNotificationChanged(context, ref, value),
+          ),
+        ],
+      ),
+    );
+  }
+
+  Future<void> _onCompletionNotificationChanged(
+    BuildContext context,
+    WidgetRef ref,
+    bool value,
+  ) async {
+    if (!value) {
+      await ref
+          .read(appSettingControllerProvider.notifier)
+          .update((s) => s.copyWith(completionNotificationsEnabled: false));
+      return;
+    }
+    var granted = true;
+    try {
+      granted = await ref
+          .read(completionNotificationServiceProvider)
+          .requestPermission();
+    } on UnimplementedError {
+      granted = true;
+    }
+    if (!context.mounted) return;
+    if (granted) {
+      await ref
+          .read(appSettingControllerProvider.notifier)
+          .update((s) => s.copyWith(completionNotificationsEnabled: true));
+    } else {
+      ScaffoldMessenger.of(context).showSnackBar(
+        SnackBar(
+          content: Text(AppStrings.of(context).notificationPermissionDenied),
+        ),
+      );
+    }
+  }
+}
diff --git a/test/features/settings/sections/notification_section_screen_test.dart b/test/features/settings/sections/notification_section_screen_test.dart
new file mode 100644
index 0000000..a30d51a
--- /dev/null
+++ b/test/features/settings/sections/notification_section_screen_test.dart
@@ -0,0 +1,115 @@
+// test/features/settings/sections/notification_section_screen_test.dart
+import 'package:drift/native.dart';
+import 'package:flutter/material.dart';
+import 'package:flutter_localizations/flutter_localizations.dart';
+import 'package:flutter_riverpod/flutter_riverpod.dart';
+import 'package:flutter_test/flutter_test.dart';
+import 'package:sitemark/app.dart';
+import 'package:sitemark/data/app_database.dart';
+import 'package:sitemark/features/settings/sections/notification_section_screen.dart';
+import 'package:sitemark/l10n/app_strings.dart';
+import 'package:sitemark/platform/notification_service.dart';
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
+    required CompletionNotificationService notifications,
+  }) async {
+    await database.getAppSettings();
+    await tester.pumpWidget(
+      ProviderScope(
+        overrides: [
+          databaseProvider.overrideWithValue(database),
+          completionNotificationServiceProvider.overrideWithValue(notifications),
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
+          home: const NotificationSectionScreen(),
+        ),
+      ),
+    );
+    await tester.pumpAndSettle();
+  }
+
+  testWidgets('completion notification switch persists when permission is '
+      'granted', (tester) async {
+    final notifications = _FakeCompletionNotificationService(
+      permissionResult: true,
+    );
+    await pumpScreen(tester, notifications: notifications);
+    final toggle = find.byKey(const Key('completion-notification-switch'));
+    await tester.tap(toggle);
+    await tester.pumpAndSettle();
+
+    expect(notifications.requestPermissionCount, 1);
+    expect(
+      (await database.getAppSettings()).completionNotificationsEnabled,
+      isTrue,
+    );
+  });
+
+  testWidgets('completion notification switch stays off and shows a snackbar '
+      'when permission is denied', (tester) async {
+    final notifications = _FakeCompletionNotificationService(
+      permissionResult: false,
+    );
+    await pumpScreen(tester, notifications: notifications);
+    final toggle = find.byKey(const Key('completion-notification-switch'));
+    await tester.tap(toggle);
+    await tester.pumpAndSettle();
+
+    expect(notifications.requestPermissionCount, 1);
+    expect(
+      (await database.getAppSettings()).completionNotificationsEnabled,
+      isFalse,
+    );
+    expect(find.text('通知权限被拒绝，可在系统设置中开启'), findsOneWidget);
+    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
+  });
+}
+
+class _FakeCompletionNotificationService
+    implements CompletionNotificationService {
+  _FakeCompletionNotificationService({this.permissionResult = true});
+
+  bool permissionResult;
+  int requestPermissionCount = 0;
+
+  @override
+  Future<void> initialize(
+    void Function(String deepLinkPath) onTapDeepLink,
+  ) async {}
+
+  @override
+  Future<bool> requestPermission() async {
+    requestPermissionCount++;
+    return permissionResult;
+  }
+
+  @override
+  Future<void> showCaptureReady({
+    required String projectId,
+    required String captureId,
+    required String photoNumber,
+  }) async {}
+
+  @override
+  Future<void> setEnabled(bool enabled) async {}
+}
