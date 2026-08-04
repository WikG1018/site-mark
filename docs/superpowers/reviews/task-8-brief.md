# Task 8: Create NotificationSectionScreen

**Source:** `docs/superpowers/plans/2026-07-25-settings-secondary-menu.md` (Task 8)

## Goal
Migrate the completion notification `SwitchListTile` + `_onCompletionNotificationChanged` permission request logic from `global_settings_screen.dart` into its own sub-page. Uses `appSettingControllerProvider` for the `completionNotificationsEnabled` field.

## Files
- Create: `lib/features/settings/sections/notification_section_screen.dart`
- Test: `test/features/settings/sections/notification_section_screen_test.dart`

## Interfaces
- Consumes: `appSettingControllerProvider` (from Task 1), `completionNotificationServiceProvider` (from `lib/platform/notification_service.dart`), `AppStrings`, `databaseProvider`
- Produces: `NotificationSectionScreen` widget (used by Task 11 routes)

## Context for the implementer
- The existing `global_settings_screen.dart:142-169` defines `_onCompletionNotificationChanged`. Migrate its permission-request + snackbar + persist logic verbatim, replacing `_apply(...)` with `ref.read(appSettingControllerProvider.notifier).update((s) => s.copyWith(...))`.
- The existing `global_settings_screen.dart:514-520` defines the `SwitchListTile`. Migrate verbatim, keeping the key `completion-notification-switch`.
- The screen uses `SettingsSectionScaffold`. The body is a `Column` containing the `SwitchListTile`.
- `CompletionNotificationService` is an abstract class defined at `lib/platform/notification_service.dart:8-27`. Its `requestPermission()` returns `Future<bool>`. The provider `completionNotificationServiceProvider` is at line 30 of the same file.
- The existing `global_settings_screen_test.dart:177-225` defines 2 notification tests. Migrate them with minimal adjustments (replace `pumpSettings` with `pumpScreen`, no scrolling needed).
- The `_FakeCompletionNotificationService` test double is at `global_settings_screen_test.dart:702-729`. Copy verbatim into the new test file.
- l10n keys (all verified): `completionNotificationTitle`, `completionNotificationSubtitle`, `notificationPermissionDenied`.
- IMPORTANT: `AppSetting.copyWith` for `completionNotificationsEnabled` (a non-nullable bool) takes a plain `bool`, NOT `Value<bool>`. Same pattern as Task 3's `useDynamicColor`.

## TDD steps

### Step 1: Write the failing test

```dart
// test/features/settings/sections/notification_section_screen_test.dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/features/settings/sections/notification_section_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/notification_service.dart';

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
    required CompletionNotificationService notifications,
  }) async {
    await database.getAppSettings();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          completionNotificationServiceProvider.overrideWithValue(notifications),
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
          home: const NotificationSectionScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('completion notification switch persists when permission is '
      'granted', (tester) async {
    final notifications = _FakeCompletionNotificationService(
      permissionResult: true,
    );
    await pumpScreen(tester, notifications: notifications);
    final toggle = find.byKey(const Key('completion-notification-switch'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(notifications.requestPermissionCount, 1);
    expect(
      (await database.getAppSettings()).completionNotificationsEnabled,
      isTrue,
    );
  });

  testWidgets('completion notification switch stays off and shows a snackbar '
      'when permission is denied', (tester) async {
    final notifications = _FakeCompletionNotificationService(
      permissionResult: false,
    );
    await pumpScreen(tester, notifications: notifications);
    final toggle = find.byKey(const Key('completion-notification-switch'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(notifications.requestPermissionCount, 1);
    expect(
      (await database.getAppSettings()).completionNotificationsEnabled,
      isFalse,
    );
    expect(find.text('通知权限被拒绝，可在系统设置中开启'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
  });
}

class _FakeCompletionNotificationService
    implements CompletionNotificationService {
  _FakeCompletionNotificationService({this.permissionResult = true});

  bool permissionResult;
  int requestPermissionCount = 0;

  @override
  Future<void> initialize(
    void Function(String deepLinkPath) onTapDeepLink,
  ) async {}

  @override
  Future<bool> requestPermission() async {
    requestPermissionCount++;
    return permissionResult;
  }

  @override
  Future<void> showCaptureReady({
    required String projectId,
    required String captureId,
    required String photoNumber,
  }) async {}

  @override
  Future<void> setEnabled(bool enabled) async {}
}
```

### Step 2: Run test to verify it fails
Run: `flutter test test/features/settings/sections/notification_section_screen_test.dart`
Expected: FAIL — file does not exist.

### Step 3: Write minimal implementation

```dart
// lib/features/settings/sections/notification_section_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/features/settings/app_setting_controller.dart';
import 'package:sitemark/features/settings/settings_section_scaffold.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/notification_service.dart';

class NotificationSectionScreen extends ConsumerWidget {
  const NotificationSectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppStrings.of(context);
    final asyncSettings = ref.watch(appSettingControllerProvider);
    final settings = asyncSettings.value;
    if (settings == null) {
      return SettingsSectionScaffold(
        title: strings.completionNotificationTitle,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return SettingsSectionScaffold(
      title: strings.completionNotificationTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            key: const Key('completion-notification-switch'),
            title: Text(strings.completionNotificationTitle),
            subtitle: Text(strings.completionNotificationSubtitle),
            value: settings.completionNotificationsEnabled,
            onChanged: (value) =>
                _onCompletionNotificationChanged(context, ref, value),
          ),
        ],
      ),
    );
  }

  Future<void> _onCompletionNotificationChanged(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    if (!value) {
      await ref
          .read(appSettingControllerProvider.notifier)
          .update((s) => s.copyWith(completionNotificationsEnabled: false));
      return;
    }
    var granted = true;
    try {
      granted = await ref
          .read(completionNotificationServiceProvider)
          .requestPermission();
    } on UnimplementedError {
      granted = true;
    }
    if (!context.mounted) return;
    if (granted) {
      await ref
          .read(appSettingControllerProvider.notifier)
          .update((s) => s.copyWith(completionNotificationsEnabled: true));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context).notificationPermissionDenied),
        ),
      );
    }
  }
}
```

### Step 4: Run test to verify it passes
Run: `flutter test test/features/settings/sections/notification_section_screen_test.dart`
Expected: PASS (2/2)

### Step 5: Run flutter analyze
Run: `flutter analyze lib/features/settings/sections/notification_section_screen.dart test/features/settings/sections/notification_section_screen_test.dart`
Expected: No issues.

### Step 6: Commit
```
git add lib/features/settings/sections/notification_section_screen.dart test/features/settings/sections/notification_section_screen_test.dart
git commit -m "feat: add notification settings sub-page"
```

## Notes
- The screen uses `appSettingControllerProvider` for the `completionNotificationsEnabled` field (non-nullable bool). Use `s.copyWith(completionNotificationsEnabled: value)` — plain value, not `Value<T>` wrapper.
- The `try { ... } on UnimplementedError { granted = true; }` block mirrors the existing behavior at `global_settings_screen.dart:153-156`. It handles the case where the provider is not overridden (production fallback).
- `_onCompletionNotificationChanged` is a method on the `ConsumerWidget` (not a stateful method). It takes `BuildContext` and `WidgetRef` as parameters because `ConsumerWidget.build` does not retain `ref` outside its scope. This is a minor refactor from the original `ConsumerState` pattern but is functionally identical.
- Do NOT modify `global_settings_screen.dart` in this task.
- The existing `global_settings_screen_test.dart` notification tests (lines 177-225) will remain in place. Task 10/12 will remove them when the old screen is rewritten.

## Global Constraints (binding)
- All existing widget test assertions must pass after refactor (234+ tests).
- l10n keys are unchanged — reuse existing `AppStrings` keys.
- No new dependencies; no schema changes.
- Commit messages in English; code comments in Chinese for domain logic, English for technical.
