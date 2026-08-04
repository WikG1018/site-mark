# Task 11: Update routes in app.dart

**Source:** `docs/superpowers/plans/2026-07-25-settings-secondary-menu.md` (Task 11)

## Goal
Add 7 nested `GoRoute`s under the existing `settings` route in `lib/app.dart` so the menu entries from Task 10's rewritten `GlobalSettingsScreen` can navigate to their sub-pages. Use the existing `_sharedAxisPage` helper for transitions.

## Files
- Modify: `lib/app.dart` (add 7 imports + replace the single `settings` GoRoute with a nested structure)

## Interfaces
- Consumes: 7 section screens (from Tasks 3, 4, 5, 6, 7, 8, 9), `_sharedAxisPage` helper (already in `app.dart`), `GlobalSettingsScreen` (already imported)
- Produces: nested `settings` GoRoute with 7 children

## Context for the implementer
- The current `lib/app.dart` lines 273-277 define the single `settings` GoRoute:
  ```dart
  GoRoute(
    path: 'settings',
    pageBuilder: (context, state) =>
        _fadeThroughPage(state, const GlobalSettingsScreen()),
  ),
  ```
- Replace it with a nested structure that keeps the parent `settings` route (using `_fadeThroughPage` for the menu) and adds 7 child routes (each using `_sharedAxisPage` for sub-page transitions).
- The 7 child routes map 1:1 to the menu entries from Task 10:
  - `watermark` → `WatermarkDefaultsSectionScreen`
  - `appearance` → `AppearanceSectionScreen`
  - `language` → `LanguageSectionScreen`
  - `storage` → `StorageSectionScreen`
  - `location` → `LocationSectionScreen`
  - `notification` → `NotificationSectionScreen`
  - `about` → `AboutSectionScreen`
- The 7 screen files are at `lib/features/settings/sections/<name>_section_screen.dart`.
- Add 7 imports near the existing `global_settings_screen.dart` import (line 12).
- IMPORTANT: The `records` route (line 269-272) is a TOP-LEVEL route under `/`, NOT under `settings`. Do NOT move it. Task 6's `context.go('/records')` is correct as-is.
- DO NOT add unused imports.

## TDD steps

### Step 1: Update routes

In `lib/app.dart`:

1. Add 7 imports near line 12 (after the existing `global_settings_screen.dart` import):

```dart
import 'package:sitemark/features/settings/sections/about_section_screen.dart';
import 'package:sitemark/features/settings/sections/appearance_section_screen.dart';
import 'package:sitemark/features/settings/sections/language_section_screen.dart';
import 'package:sitemark/features/settings/sections/location_section_screen.dart';
import 'package:sitemark/features/settings/sections/notification_section_screen.dart';
import 'package:sitemark/features/settings/sections/storage_section_screen.dart';
import 'package:sitemark/features/settings/sections/watermark_defaults_section_screen.dart';
```

2. Replace lines 273-277 (the single `settings` GoRoute) with:

```dart
          GoRoute(
            path: 'settings',
            pageBuilder: (context, state) =>
                _fadeThroughPage(state, const GlobalSettingsScreen()),
            routes: [
              GoRoute(
                path: 'watermark',
                pageBuilder: (context, state) => _sharedAxisPage(
                  state,
                  const WatermarkDefaultsSectionScreen(),
                ),
              ),
              GoRoute(
                path: 'appearance',
                pageBuilder: (context, state) => _sharedAxisPage(
                  state,
                  const AppearanceSectionScreen(),
                ),
              ),
              GoRoute(
                path: 'language',
                pageBuilder: (context, state) => _sharedAxisPage(
                  state,
                  const LanguageSectionScreen(),
                ),
              ),
              GoRoute(
                path: 'storage',
                pageBuilder: (context, state) => _sharedAxisPage(
                  state,
                  const StorageSectionScreen(),
                ),
              ),
              GoRoute(
                path: 'location',
                pageBuilder: (context, state) => _sharedAxisPage(
                  state,
                  const LocationSectionScreen(),
                ),
              ),
              GoRoute(
                path: 'notification',
                pageBuilder: (context, state) => _sharedAxisPage(
                  state,
                  const NotificationSectionScreen(),
                ),
              ),
              GoRoute(
                path: 'about',
                pageBuilder: (context, state) => _sharedAxisPage(
                  state,
                  const AboutSectionScreen(),
                ),
              ),
            ],
          ),
```

### Step 2: Run flutter analyze
Run: `flutter analyze lib/app.dart`
Expected: No issues.

### Step 3: Run full test suite
Run: `flutter test`
Expected: All tests pass. (The Task 10 routing test `settings route is reachable from the app shell` uses its own GoRouter and does NOT depend on `lib/app.dart`'s router, so it will continue to pass. The section-specific tests use `MaterialApp(home: ...)` and don't depend on routing either.)

### Step 4: Commit
```
git add lib/app.dart
git commit -m "feat: add nested settings routes"
```

## Notes
- This task only adds routes — no new widgets, no test changes.
- The `_sharedAxisPage` and `_fadeThroughPage` helpers already exist in `lib/app.dart` (used by other routes like `projects/new`, `projects/:projectId`, etc.).
- After this task, the menu entries from Task 10 will navigate correctly at runtime.
- Do NOT add a navigation test in this task — Task 12 (full regression) will verify everything.

## Global Constraints (binding)
- All existing widget test assertions must pass after refactor (234+ tests).
- l10n keys are unchanged.
- No new dependencies; no schema changes.
- Commit messages in English; code comments in Chinese for domain logic, English for technical.
