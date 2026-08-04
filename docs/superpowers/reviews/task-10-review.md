# Task 10 Review: Rewrite GlobalSettingsScreen as menu

## Verdict
APPROVED (with one Important UX finding deferred to Task 12)

## Spec compliance
- ✅ Implementation file (`lib/features/settings/global_settings_screen.dart`) is byte-for-byte identical to the brief's Step 3 code block — 42 lines, `StatelessWidget`, 7-entry tuple list, `Card > ListTile` pattern, `context.go(route)` in `onTap`. Verified by reading the file directly.
- ✅ Test file keeps the 2 required generic tests (route reachable, storage caching) and adds the 1 new menu test (`shows 7 settings entries`).
- ✅ Removed 14 old per-section tests as specified.
- ✅ l10n keys unchanged — no new keys added, no keys modified. `storageScope`, `newProjectDefaults`, `appearance`, `language`, `locationLabel`, `completionNotificationTitle`, `about` all reused.
- ✅ No new dependencies; no schema changes.
- ✅ Commit message in English (`feat: rewrite settings screen as secondary menu`); class doc comment in Chinese (domain logic).
- ✅ `flutter analyze` clean.
- ⚠️ Deviation: test expectation for the storage entry changed from brief's `'储存'` to actual `'SiteMark 应用内数据占用（不含系统相册）'`. **Acceptable** — see UX defect section.

## Test quality
- ✅ `shows 7 settings entries` — asserts all 7 ListTile titles render via 7 distinct `find.text(...)` calls. Non-trivial: would fail if any entry were dropped, mislabeled, or misrouted to a non-rendering builder. Matches the brief's corrected Step 1 block (minus the storage-label deviation).
- ✅ `settings route is reachable from the app shell` — wires a `GoRouter` with `/settings` child route, calls `router.go('/settings')`, asserts `GlobalSettingsScreen` is mounted. Non-trivial regression guard for the shell→settings navigation contract.
- ✅ `storage usage stays cached after settings disposal until invalidated` — pure provider test: first listener reads → `loadCount==1`; listener closed + re-listen → still `loadCount==1` (cache hit); `invalidate` → `loadCount==2`. Non-trivial: verifies autoDispose + keepAlive semantics that the old screen relied on.
- Minor: tests hardcode Chinese strings (matches brief's pattern; brittle to l10n copy edits but acceptable for a zh-pinned harness).
- Minor: `shows 7 settings entries` does not assert tap→route behavior. This is per-brief (navigation is deferred to Task 11 because the 7 child routes don't exist yet). Acceptable.

## Code quality findings
- **No findings.** The implementation is 42 lines, uses Dart 3 record tuples (`(IconData, String, String)`) cleanly, no dead code, no premature abstraction, no unused imports. YAGNI satisfied — the screen genuinely needs no state, so `StatelessWidget` is correct. The class doc comment is concise and Chinese as required.

## UX defect evaluation
**Real defect, but must be deferred to Task 12.**

The `storageScope` l10n value (verified at `lib/l10n/app_strings.dart` lines 159-161) is:
- zh: `'SiteMark 应用内数据占用（不含系统相册）'` (24 Chinese chars + punctuation)
- en: `'SiteMark app data usage (system gallery excluded)'`

This is the longest string in the menu by far. The other 6 entries are 2-7 chars (外观, 语言, 定位, 关于, 完成通知, 新建项目水印默认值). Rendered as a `ListTile.title` in a `Card`, the storage entry will wrap to 2 lines (or be truncated by `ListTile`'s default `maxLines: 1` + `TextOverflow.ellipsis`), making the menu visually inconsistent and ugly. The user explicitly asked for `'储存'` (2 chars).

**Why not fix in Task 10:** The binding global constraint says "l10n keys unchanged — reuse existing `AppStrings` keys." Adding a new `storageMenuLabel` key would violate this. The implementer's choice (use the existing `storageScope` value and update the test to match) is the only path that honors all binding constraints. The implementer documented this concern correctly in the report.

**Recommended fix path for Task 12:**
1. Add a new l10n key to `lib/l10n/app_strings.dart`:
   ```dart
   /// 二级菜单中的储存入口短标签。详情页仍使用 [storageScope] 作为标题。
   String get storageMenuLabel => _english ? 'Storage' : '储存';
   ```
2. In `lib/features/settings/global_settings_screen.dart` line 18, swap `strings.storageScope` → `strings.storageMenuLabel`.
3. Update the `shows 7 settings entries` test expectation back to `find.text('储存')`.
4. The `StorageSectionScreen` page title (Task 6) should keep using `storageScope` — the long descriptive label is appropriate there.

This is a one-line impl change + one l10n key + one test string. Task 12 is explicitly the cleanup task, so this fits its scope.

## Cross-task impact
- **Task 11 (register 7 routes in `lib/app.dart`):** Hard landmine. The new screen calls `context.go('/settings/watermark')` etc. in `onTap`. If Task 11 does not register all 7 child routes, tapping any entry except via the test harness will throw a `GoRouter` "no route matched" error at runtime. The `shows 7 settings entries` test does NOT exercise these taps (intentionally), so Task 11's regression suite MUST add a per-entry tap→navigation test. The implementer correctly notes this in the brief's Notes section.
- **Task 12 (cleanup):** Must address the storage label UX defect (see above). Also a good place to consider whether `completionNotificationTitle` ('完成通知', 4 chars) is the right menu label vs. a shorter `notificationMenuLabel` — currently fine, but worth a glance.
- **Task 13 (final verification):** Should run the full `test/features/settings/` suite (currently 25/25) plus a manual smoke test of all 7 menu taps after Task 11 lands.
- **`a11y_test.dart`:** Already passes with the new `Card > ListTile` pattern — the 48dp tap-target guideline is satisfied by `ListTile`'s default height. No landmine there.
- **No callers outside `lib/app.dart` and the test files reference `GlobalSettingsScreen`** — the constructor signature is unchanged (`const GlobalSettingsScreen({super.key})`), so no caller-side breakage.

## Removed tests coverage verification
Cross-checked the 14 removed tests against the section-specific files. The 3 storage tests were line-for-line migrated to `test/features/settings/sections/storage_section_screen_test.dart` (verified by reading that file — same test names, same assertions, same `_RecordingStorageUsageService` / `_RetryingStorageUsageService` doubles). The other 11 removed tests (theme/language, opacity/font-scale/accent/position, dynamic-color, completion-notification ×2, about ×2, fallback version, location ×3, manage-records, repository-link ×2) map to Tasks 3-9 per the brief's coverage table. No coverage gaps identified in the storage migration; the remaining migrations are covered by the implementer's claim that `flutter test test/features/settings/` passes 25/25, which includes all 7 section-specific files.

## Recommendation
APPROVED. The implementation is a faithful, byte-for-byte realization of the brief's Step 3 code; the test file implements the brief's corrected Step 1 block with one well-documented, well-justified deviation on the storage label expectation (the brief's `'储存'` does not exist in `app_strings.dart`, and the binding "l10n keys unchanged" constraint forbids adding it in Task 10). All 3 tests are non-trivial and pass; `flutter analyze` is clean; no tests outside `test/features/settings/` broke; the 14 removed tests are covered by the section-specific files (verified for storage, claimed for the rest). The one real issue is the UX defect: the storage menu entry renders the 24-char `storageScope` string as a ListTile title, which will wrap or truncate and looks inconsistent with the other 6 short entries. This defect cannot be fixed in Task 10 without violating the l10n constraint, so it must be deferred to Task 12 — add a new `storageMenuLabel` l10n key (`'储存'` / `'Storage'`), swap one line in `global_settings_screen.dart`, and revert the test expectation. Task 11 must wire all 7 `/settings/<section>` routes or runtime navigation will throw.
