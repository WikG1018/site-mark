# Task 8 Review: Create NotificationSectionScreen

## Verdict
APPROVED

## Spec compliance
- ✅ Created `lib/features/settings/sections/notification_section_screen.dart` (73 lines) — matches brief Step 3 verbatim except the single unused import (see Implementer concern evaluation below).
- ✅ Created `test/features/settings/sections/notification_section_screen_test.dart` (115 lines) — matches brief Step 1 verbatim, including the copied `_FakeCompletionNotificationService` double.
- ✅ `NotificationSectionScreen` is a `ConsumerWidget` using `SettingsSectionScaffold` with `title: strings.completionNotificationTitle` and a `Column`-wrapped `SwitchListTile` keyed `completion-notification-switch`.
- ✅ `_onCompletionNotificationChanged` migrates the permission-request + snackbar + persist logic verbatim, including the `try { ... } on UnimplementedError { granted = true; }` defensive block.
- ✅ Replaces original `_apply(...)` with `ref.read(appSettingControllerProvider.notifier).update((s) => s.copyWith(...))` per brief.
- ✅ Uses plain `bool` in `copyWith` — verified against `lib/data/app_database.g.dart:2407` (`bool? completionNotificationsEnabled` in generated `AppSetting.copyWith`, NOT `Value<bool>`).
- ✅ Uses existing l10n keys `completionNotificationTitle`, `completionNotificationSubtitle`, `notificationPermissionDenied` — no new keys.
- ✅ Did NOT modify `global_settings_screen.dart`.
- ✅ Commit message in English (`feat: add notification settings sub-page`); no new dependencies; no schema changes.
- ✅ Deviation from brief: only the removed `import 'package:sitemark/app.dart';` line. No other line changes.

## Test quality
- ✅ Test 1 (`completion notification switch persists when permission is granted`):
  - Asserts `requestPermissionCount == 1` (request count).
  - Asserts `(await database.getAppSettings()).completionNotificationsEnabled` is `isTrue` (persisted).
  - Non-trivial: covers the grant path end-to-end including DB write.
- ✅ Test 2 (`completion notification switch stays off and shows a snackbar when permission is denied`):
  - Asserts `requestPermissionCount == 1` (request count).
  - Asserts DB value `isFalse` (stays off).
  - Asserts snackbar text `通知权限被拒绝，可在系统设置中开启` `findsOneWidget` (snackbar shown).
  - Asserts `tester.widget<SwitchListTile>(toggle).value` is `isFalse` (switch value reflects state).
  - Non-trivial: covers the deny path with both side-effect and widget-state assertions.
- ✅ Test harness uses `ProviderScope` overrides for `databaseProvider` and `completionNotificationServiceProvider`, with `MaterialApp` + zh locale + full l10n delegates — matches the canonical harness pattern.

## Code quality findings
No findings.

Notes (not defects — verbatim per brief):
- `var granted = true;` then reassigning in `try` is slightly awkward but is a faithful migration of the original behavior at `global_settings_screen.dart:153-156`. Preserved intentionally.
- The `if (!context.mounted) return;` guard before the snackbar/persist is the correct async-gap guard.
- `Column` inside `SettingsSectionScaffold`'s `ListView` is safe — no `Expanded`/`Flexible` children, so no unbounded-height layout exception. The 2/2 test pass with `pumpAndSettle` confirms it.

## Implementer concern evaluation
**Legitimate minimal fix.** Verified:
- The screen file uses `appSettingControllerProvider`, `completionNotificationServiceProvider`, `AppStrings.of`, `SettingsSectionScaffold`, `SwitchListTile`, `ScaffoldMessenger`, `SnackBar` — none of these come from `package:sitemark/app.dart`.
- `databaseProvider` (the only symbol one might import `app.dart` for) is only referenced inside `AppSettingController` (`lib/features/settings/app_setting_controller.dart:5,15,39`), not in the screen.
- Therefore the import was genuinely unused and `flutter analyze` was correct to flag it.
- Removing it is the minimal behavior-preserving change to satisfy the brief's "No issues" requirement (Step 5). The implementer did not mask a real defect.

## Cross-task impact
- **Task 10 (rewrite old screen):** When the original `global_settings_screen.dart:142-169` (`_onCompletionNotificationChanged`) and `:514-520` (`SwitchListTile`) are removed, the new `NotificationSectionScreen` already provides the replacement. No interface gap.
- **Task 11 (routes):** `NotificationSectionScreen` has a `const` constructor with `super.key` — ready to drop into a route table.
- **l10n keys:** Tasks 10/12 must NOT remove `completionNotificationTitle`, `completionNotificationSubtitle`, `notificationPermissionDenied` — the new screen depends on them.
- **Duplicate test double:** `_FakeCompletionNotificationService` now exists in both `global_settings_screen_test.dart:702-729` and the new test file. Task 10/12 should remove the old copy when the old notification tests are deleted. Low risk; not a Task 8 issue.
- **Existing tests:** The original 2 notification tests in `global_settings_screen_test.dart:177-225` remain in place per brief; they will exercise the old screen until Task 10/12 removes them. No conflict with the new screen's tests.

## Recommendation
The implementation is spec-compliant, the tests assert behavior non-trivially on both permission paths (grant persists + request count; deny stays off + snackbar + switch value false + request count), and the only deviation (removing the genuinely unused `package:sitemark/app.dart` import) is the minimal behavior-preserving fix required to satisfy the brief's "No issues" analyzer gate. All consumed interfaces (`appSettingControllerProvider`, `AppSettingController.update` signature, `AppSetting.copyWith(completionNotificationsEnabled: bool)`, `CompletionNotificationService.requestPermission() → Future<bool>`, `completionNotificationServiceProvider`, `SettingsSectionScaffold{title, body}`) are verified against project source. No landmines for Tasks 9-13 beyond the expected cleanup of the duplicate test double in Task 10/12. Approve as-is.
