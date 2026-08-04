# Task 7 Review: Create LocationSectionScreen

**Commit reviewed:** `776f7c3` — `feat: add location settings sub-page`
**Files:** `lib/features/settings/sections/location_section_screen.dart` (125 lines, new), `test/features/settings/sections/location_section_screen_test.dart` (156 lines, new)

## Verdict
APPROVED

## Spec compliance
- ✅ File created at the specified path `lib/features/settings/sections/location_section_screen.dart`.
- ✅ Test created at the specified path `test/features/settings/sections/location_section_screen_test.dart`.
- ✅ `LocationSectionScreen` is a `ConsumerStatefulWidget`; state mixes in `WidgetsBindingObserver`.
- ✅ `didChangeAppLifecycleState` refreshes on `resumed` (logic verbatim from `global_settings_screen.dart:75-82`, comments translated to Chinese per the brief's Step 3 block).
- ✅ `_loadPermission` migrated verbatim (logic identical to `global_settings_screen.dart:84-101`).
- ✅ `_onLocationTapped` migrated verbatim (logic identical to `global_settings_screen.dart:103-116`).
- ✅ `_LocationPermissionTile` migrated verbatim (logic identical to `global_settings_screen.dart:677-709`).
- ✅ Uses `SettingsSectionScaffold` with `title: strings.locationLabel`; body is just the tile.
- ✅ Consumes `locationPermissionServiceProvider` only; does NOT touch `appSettingControllerProvider`.
- ✅ `global_settings_screen.dart` was NOT modified.
- ✅ Domain-logic comments in Chinese (lifecycle, catch fallback, openSettings branch, tile doc); technical identifiers untouched.
- ✅ Commit message in English.
- ✅ `_SettingsTestPlatformServices` copied verbatim from `global_settings_screen_test.dart:574-636`.
- ✅ Only the two specified files were staged; no scope creep.
- ✅ TDD cycle followed: RED (file-not-found) → GREEN (3/3) → analyze clean.

## Test quality
- ✅ "location tile shows disabled when permission is denied" — asserts `find.text('未开启')` `findsOneWidget`. Direct, unambiguous.
- ✅ "location tile shows enabled when permission is granted" — asserts `find.text('已开启')` `findsOneWidget`. Direct, unambiguous.
- ✅ "tapping the disabled location tile requests permission" — asserts both `platform.requestLocationPermissionCount == 1` (request fired exactly once) AND `settings.locationPermissionPromptDismissed` `isTrue` (dismissal flag persisted). Matches the brief's two-pronged requirement. The `requestResult: denied` setup exercises the `result != granted` branch in `LocationPermissionService.request()` where the flag is written — a meaningful assertion, not a tautology.
- No missing cases — these are exactly the 3 the brief required. No scrolling needed because the screen body is just the tile, as the brief anticipated.

## Code quality findings
No findings.

- The `_loadPermission` catch-block fallback is unreachable in tests (the fake never throws) and largely unreachable in production, but it is verbatim from the original screen and the brief explicitly mandates verbatim migration. Not a defect.
- The `_SettingsTestPlatformServices` duplicate is intentional and explicitly deferred to Task 12 per the brief. Not a defect.
- No YAGNI violations, no dead code, no premature abstractions, no copy-paste bugs (the tile's `onTap: current == null || enabled ? null : onTap` correctly disables the tap when loading or already enabled).

## Implementer concern evaluation
The missing `import 'package:sitemark/app.dart';` is a **documentation gap in the brief**, not a design issue. Verified directly:
- `databaseProvider` is defined at `lib/app.dart:34`.
- `platformServicesProvider` is defined at `lib/app.dart:88`.
- `locationPermissionServiceProvider` is defined at `lib/app.dart:96`.
- The original `global_settings_screen_test.dart` does import `app.dart` at line 7.
- The brief's Step 1 code block simply omitted it.

The implementer's fix is appropriate and minimal: a single import line placed alphabetically between `flutter_test/flutter_test.dart` and `sitemark/data/app_database.dart`, matching the import ordering used by the parallel Task 6 file `storage_section_screen_test.dart:8`. This is the only deviation from the brief's Step 1 code block, and it is a strict prerequisite for compilation. The implementation file itself was used verbatim from the brief's Step 3 block — no deviations there.

## Cross-task impact
No landmines for Tasks 8-13.

- **Task 10** (rewrite old screen): The old location tests at `global_settings_screen_test.dart:459-518` will need to be removed when the old screen loses the location tile. Task 7 does not touch that file, so the old tests still pass and the refactor surface is isolated. Task 10/12 can delete them cleanly.
- **Task 11** (routes): `LocationSectionScreen` has a `const` constructor with `super.key`, ready to wire into a `GoRoute`. No interface gaps.
- **Task 12** (test double triage): The `_SettingsTestPlatformServices` duplicate is well-marked with a comment ("Verbatim copy from global_settings_screen_test.dart — needed because..."). Task 12 can extract it to a shared `test/helpers/` module without ambiguity.
- No shared interfaces were altered; no schema changes; no new dependencies. The new screen consumes existing providers exactly as the brief specified.

## Recommendation
The task should be marked complete. The implementation is a faithful verbatim migration per the brief's Step 3 code block (lifecycle, `_loadPermission`, `_onLocationTapped`, and `_LocationPermissionTile` all match the original `global_settings_screen.dart` logic, with comments translated to Chinese as the brief's Step 3 block dictates). All 3 required tests pass and assert meaningful behavior (disabled text, enabled text, request-count + dismissal-flag persistence). `flutter analyze` is clean on both new files. `global_settings_screen.dart` was not touched. The single deviation — adding the missing `package:sitemark/app.dart` import to the test file — is a minimal, correct fix for a brief documentation gap (the providers `databaseProvider` and `platformServicesProvider` both live in `lib/app.dart`), and the placement matches the Task 6 storage test's import ordering. No defects to fix.
