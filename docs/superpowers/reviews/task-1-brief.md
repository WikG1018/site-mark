# Task 1: Create AppSettingController

**Source:** `docs/superpowers/plans/2026-07-25-settings-secondary-menu.md` (Task 1)

## Goal
Create a shared Riverpod controller that centralizes `AppSetting` read/persist logic with optimistic updates, to be consumed by all settings sub-pages in later tasks.

## Files
- Create: `lib/features/settings/app_setting_controller.dart`
- Test: `test/features/settings/app_setting_controller_test.dart`

## Interfaces
- Consumes: `databaseProvider` (`AppDatabase`), `AppSetting` type
- Produces: `appSettingControllerProvider` (Riverpod provider), `AppSettingController` class with `update()` method

## Required Behavior (from plan)
1. `build()` loads the singleton `AppSetting` from the database via `db.getAppSettings()`.
2. `update(updater)` applies a functional updater to the current `AppSetting`:
   - Optimistically sets state to the new value.
   - Persists to the database via `db.updateAppSettings(...)` with all 8 fields: `themeMode`, `useDynamicColor`, `localeCode`, `defaultWatermarkPosition`, `defaultWatermarkOpacity`, `defaultWatermarkFontScale`, `defaultWatermarkAccentColorArgb`, `completionNotificationsEnabled`.
   - On persist failure, rolls back state to the previous value.

## Test Cases (from plan)
1. `build loads the singleton AppSetting` — after `database.getAppSettings()`, reading the provider returns `themeMode == 'system'`.
2. `update persists and reflects the new value` — after `update((s) => s.copyWith(themeMode: 'dark'))`, the DB row and the provider state both reflect `'dark'`.

## Plan-Noted Deviation (pre-approved by controller)
The plan specifies `Notifier<AsyncValue<AppSetting>>` + `NotifierProvider` (Riverpod 2.x syntax). The project uses Riverpod 3.x, where `Notifier` does not compile with the installed version. The implementer adapted to `AsyncNotifier<AppSetting>` + `AsyncNotifierProvider`, which is the Riverpod 3.x equivalent. This adaptation was confirmed necessary during implementation.

Also: the plan's imports reference `package:sitemark/data/app_database.dart` for `databaseProvider`, but `databaseProvider` is actually defined in `lib/app.dart` (exported via `package:sitemark/app.dart`). The implementer imported `package:sitemark/app.dart` to resolve the actual location.

## Commit
`adc06c3 feat: add AppSettingController for shared settings state`

## Global Constraints (binding this task)
- All existing widget test assertions must pass after refactor (234+ tests).
- l10n keys are unchanged — reuse existing `AppStrings` keys.
- `AppSetting` type comes from `package:sitemark/data/app_database.dart`.
- `databaseProvider` from `package:sitemark/data/app_database.dart` (NOTE: actual location is `package:sitemark/app.dart` — see deviation above).
- No new dependencies; no schema changes.
- Commit messages in English; code comments follow user language (Chinese for domain logic, English for technical).
