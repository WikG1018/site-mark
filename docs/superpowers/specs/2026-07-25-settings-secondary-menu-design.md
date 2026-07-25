# Settings Secondary Menu Refactor Design

## Background

The current `GlobalSettingsScreen` (`lib/features/settings/global_settings_screen.dart`, 805 lines) crams 6 sections into a single `ListView`. As the app grew, the screen became overloaded and hard to navigate. This refactor splits it into a secondary menu structure: a main settings page with entry tiles, each navigating to a dedicated sub-page.

## Goals

- Split the monolithic settings screen into 7 independent sub-pages.
- Introduce a shared `AppSettingController` (Riverpod Notifier) to centralize read/persist logic.
- Preserve all existing functionality and UX (no behavior changes, pure structural refactor).
- Keep each file small and focused for testability.

## Non-Goals

- Redesigning the visual appearance of individual controls.
- Adding new settings or removing existing ones.
- Changing the database schema or persistence layer.

## Architecture

### Shared Controller: `AppSettingController`

A Riverpod `Notifier` that wraps the current scattered `databaseProvider` read + `_apply` persist pattern.

```dart
@riverpod
class AppSettingController extends _$AppSettingController {
  @override
  Future<AppSetting> build() => ref.read(databaseProvider).appSetting();

  Future<void> update(AppSetting Function(AppSetting current) updater) async {
    final db = ref.read(databaseProvider);
    final current = state.valueOrNull ?? await db.appSetting();
    final next = updater(current);
    state = AsyncData(next);
    await db.updateAppSetting(next);
  }
}
```

**Key decisions:**
- `AsyncValue<AppSetting>` exposes state; sub-pages `ref.watch(appSettingControllerProvider)` for auto-rebuild.
- `update` accepts a functional updater (compute new value from current) to avoid read-modify-write races.
- Optimistic update: `state = AsyncData(next)` before persisting for immediate UI response.
- On persist failure, `state = AsyncError(...)` rolls back UI.

**File:** `lib/features/settings/app_setting_controller.dart`

### File Structure

```
lib/features/settings/
├── global_settings_screen.dart          # Main menu: 7 ListTile entries only
├── app_setting_controller.dart          # Shared Riverpod controller
└── sections/
    ├── appearance_section_screen.dart    # Theme + dynamic color
    ├── language_section_screen.dart      # Language selection
    ├── watermark_defaults_section_screen.dart  # Position/opacity/font/accent
    ├── storage_section_screen.dart       # Storage detail + manage + clear
    ├── location_section_screen.dart      # Location permission
    ├── notification_section_screen.dart  # Completion notification toggle
    └── about_section_screen.dart         # Version/privacy/repo/license
```

### Main Menu: `GlobalSettingsScreen`

A `ConsumerWidget` rendering a `ListView` of 7 `ListTile` entries inside a `Card`. Each tile shows only the title (no subtitle) and a trailing `Icons.chevron_right`. Tapping navigates via `context.go('/settings/<section>')`.

**Entry order and icons:**

| # | Title (l10n key) | Icon | Route |
|---|---|---|---|
| 1 | 新建项目水印默认值 (`newProjectDefaults`) | `Icons.water_drop_outlined` | `/settings/watermark` |
| 2 | 外观 (`appearance`) | `Icons.palette_outlined` | `/settings/appearance` |
| 3 | 语言 (`language`) | `Icons.language` | `/settings/language` |
| 4 | 储存 (`storageScope`) | `Icons.storage_outlined` | `/settings/storage` |
| 5 | 定位 (`locationLabel`) | `Icons.location_on_outlined` | `/settings/location` |
| 6 | 通知 (`completionNotificationTitle`) | `Icons.notifications_outlined` | `/settings/notification` |
| 7 | 关于 (`about`) | `Icons.info_outline` | `/settings/about` |

### Sub-Pages

Each sub-page is a `ConsumerStatefulWidget` (or `ConsumerWidget` where no local state is needed) with its own `Scaffold` and `AppBar`. Content is migrated verbatim from the current `global_settings_screen.dart` sections — no logic changes.

**Appearance (`appearance_section_screen.dart`):**
- Theme `SegmentedButton` (system/light/dark)
- Dynamic color `SwitchListTile`

**Language (`language_section_screen.dart`):**
- Language `SegmentedButton` (system/zh/en)

**Watermark Defaults (`watermark_defaults_section_screen.dart`):**
- Position `SegmentedButton` (bottomLeft/bottomRight)
- Opacity `Slider` (0.20–0.95) with `_dragValue` follow logic
- Font scale `Slider` (0.80–1.60) with `_fontScaleDragValue` follow logic
- Accent color `ChoiceChip` Wrap (green/blue/orange)

**Storage (`storage_section_screen.dart`):**
- `_StorageSection` migrated wholesale: detail rows, manage records, clear exports, refresh, error/loading states, clear confirmation dialog.

**Location (`location_section_screen.dart`):**
- `_LocationPermissionTile` migrated with `WidgetsBindingObserver` for `resumed` permission refresh.

**Notification (`notification_section_screen.dart`):**
- Completion notification `SwitchListTile` with permission request logic.

**About (`about_section_screen.dart`):**
- `_AboutSection` migrated: version, privacy statements, repository link, license, licenses button.

### Routing

Nested `GoRoute` in `lib/app.dart`:

```
/settings                        → GlobalSettingsScreen (entry list)
  /settings/watermark            → WatermarkDefaultsSectionScreen
  /settings/appearance           → AppearanceSectionScreen
  /settings/language             → LanguageSectionScreen
  /settings/storage              → StorageSectionScreen
  /settings/location             → LocationSectionScreen
  /settings/notification         → NotificationSectionScreen
  /settings/about                → AboutSectionScreen
```

Page transitions use the existing `_fadeThroughPage` helper for M3 consistency.

### Data Flow

1. `AppSettingController.build()` reads `AppSetting` from `databaseProvider`.
2. Sub-pages `ref.watch(appSettingControllerProvider)` → rebuild on change.
3. User interacts (e.g., taps theme) → `ref.read(appSettingControllerProvider.notifier).update((s) => s.copyWith(theme: 'dark'))`.
4. Controller optimistic-updates `state`, then persists via `databaseProvider`.
5. Non-setting sub-pages (storage, location, notification, about) keep their existing data sources (storage calculation, permission query, etc.) — only the `AppSetting`-backed controls use the controller.

## Error Handling

- `AppSettingController.update`: if `db.updateAppSetting` throws, `state` becomes `AsyncError`; UI shows the previous value via `AsyncValue.previous`. Sub-pages already handle `AsyncValue` with `when`/`valueOrNull`.
- Storage, location, notification sub-pages retain their existing error handling (SnackBars, retry buttons).

## Testing

- **Controller unit test:** verify `update` performs optimistic update + persists; verify persist failure rolls back.
- **Main menu test:** verify 7 `ListTile` entries exist with correct titles; verify tapping navigates to the correct route.
- **Sub-page tests:** split current `global_settings_screen_test.dart` tests into per-section test files; each verifies the same behaviors as before (theme persists, opacity slider, storage rows, location tile, notification toggle, about section).
- **Regression:** all existing test assertions (234+ tests) must pass after refactor.

## Migration Notes

- Existing helper components (`_SectionHeader`, `_AccentChoice`, `_StorageRow`, `_StorageSection`, `_LocationPermissionTile`, `_AboutSection`) move into their respective section files or shared widgets as appropriate.
- The `_fallbackVersion`/`_fallbackBuild` constants and `_accentSwatches` list move to the files that use them.
- `_segmentTapTargetStyle` moves to `appearance_section_screen.dart` (used by theme + language segmented buttons; language screen can import it or duplicate the one-liner).
- l10n keys are unchanged — no new keys needed except potentially section AppBar titles (already exist: `appearance`, `language`, `newProjectDefaults`, `storageScope`, `locationLabel`, `completionNotificationTitle`, `about`).

## Scope

This is a single, focused refactor. No decomposition needed — all changes are within the settings feature and `app.dart` routing.
