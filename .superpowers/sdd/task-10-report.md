# Task 10 final acceptance report

Date: 2026-08-04
Branch: `design/ui-refresh-v2`
Baseline: `9b53b720b084a834c2a8866af15964912748d7da`

## Delivered changes

- Added `adaptiveSkeletonCount` with finite-input validation, ceiling division,
  configurable minimum/maximum clamping, and an explicit `0 <= min <= max`
  contract. `CapturePagedList` also rejects a skeleton maximum below its
  adaptive minimum.
- Made the project list and paged capture list derive their first-frame
  skeleton count from the available viewport through `LayoutBuilder`.
- Kept the project and capture content-container `Element` stable while the
  surface moves from loading to data/empty state.
- Added reason-plus-next-step guidance for every typed project restore failure
  shown by the real restore Snackbar flow in Chinese and English.
- Added shared, state-matched photo-processing guidance to capture cards and
  details. Permanent evidence failures never offer a misleading processing
  retry; transient and unknown processing failures only offer it when the
  original is actually retained.
- Added regression coverage for final rendered text/icon foregrounds under a
  hostile inherited theme, explicit foreground overrides, and the tappable
  semantics action on `GlassCard`.
- Synchronized the README feature table with the implemented primary
  navigation, filters, continuous capture, photo details, settings groups,
  glass surfaces, and reduced-motion behavior. Version and download links were
  not changed.

## TDD evidence

RED was established before production changes:

- The helper test failed because `adaptive_skeleton_count.dart` did not exist.
- Project loading rendered the fixed five rows instead of the expected seven.
- Capture loading rendered the fixed six rows instead of the expected seven.
- Localization snapshots exposed the old messages that lacked a concrete
  reason or recovery action.
- Independent-review tests then exposed five restore messages without a
  concrete next step, a detail screen with no failure guidance, and
  `originalModified` incorrectly satisfying the old original-present retry
  condition.
- Invalid `min`/`max` combinations returned a plausible count instead of
  rejecting an undefined contract, and `CapturePagedList` accepted maxima of
  `-1` and `1`.

GREEN coverage includes:

- Ceiling boundaries, min/max clamping, custom bounds, zero/negative values,
  `NaN`, positive infinity, negative infinity, invalid bounds, and invalid
  paged-list constructor maxima.
- Real Chinese and English app roots at 360 dp width with 2x text scaling,
  switching across Projects, All records, and Settings without overflow.
- Stable content-container `Element` identity across loading-to-ready changes.
- Final `RenderParagraph` foregrounds for glass defaults, explicit
  `TextStyle`/`Icon.color`, and nested `IconTheme` overrides.
- `GlassCard` exposes `SemanticsAction.tap` and remains physically tappable.
- Real restore Snackbar flows for every typed failure class, in both locales,
  without leaking raw exceptions.
- Real capture detail and card surfaces for `originalMissing`,
  `originalModified`, `processingFailed`, and legacy/unknown failures.

## Copy audit

| Area | Reason present | Next step present | Result |
| --- | --- | --- | --- |
| Permission | Yes | Open system settings / retry | Existing copy accepted |
| Backup creation | Yes | Retry / isolate one project / save or share again | UI copy accepted |
| Restore preparation | Typed reason | Choose a SiteMark project backup, upgrade the app, choose a compatible archive, or free storage as appropriate | Nine typed mappings covered by zh/en contracts and real Snackbar tests |
| Restore execution | Typed reason | Rename conflicts in preview, restart after safe finalization, restore again, or use single-project backups as appropriate | Real Snackbar tests cover name conflict, rollback, general failure, and finalization pending |
| Photo original missing | Original evidence file is gone | Return to the project and retake; keep or delete the failed record | Shown in list and detail; retry hidden |
| Photo original modified | Capture-time checksum no longer matches | Keep the current original as evidence and retake, or delete the failed record | Shown in list and detail; retry hidden |
| Photo processing/unknown | Processing failed while original may remain | Retry only when the original is retained; otherwise retake | Error-code contract and detail controls tested |
| Capture list | Local-record read failure | Retry | Message fixed |

## Design-decision acceptance

| Decision | Evidence | Result |
| --- | --- | --- |
| B1 | Root navigation tests cover the floating three-destination Dock, state preservation, and hiding it on secondary routes | PASS |
| D1 | Project-list hierarchy, detail navigation, stable loading surface, and adaptive placeholders are covered | PASS |
| F1 | Record search/filter sheets, removable active conditions, and date grouping remain covered by the full suite | PASS |
| P2 | Processed/original selection, detail tabs, adjacent full-screen paging, and Hero behavior remain covered by the full suite | PASS |
| S1 | Settings root exposes the three intended groups and passes the real-root 2x-text test | PASS |
| R1 | Targeted back-navigation suite covers project detail/search and capture confirmation/template/capture precedence | PASS |
| V2 | Glass regressions and reduced-motion route behavior are covered | PASS |

The three root branches and reduced-motion transitions were also rerun as a
targeted final check: 14 tests passed.

## Verification gates

| Gate | Result |
| --- | --- |
| `dart format --output=none --set-exit-if-changed lib test` | PASS, 191 files checked, 0 changed |
| Selected Task 10 and independent-review widget/unit tests | PASS, 82 tests |
| `flutter analyze` | PASS, no issues |
| `flutter test` | PASS, 853 tests |
| `cargo fmt --manifest-path rust/Cargo.toml -- --check` | PASS |
| `cargo test --manifest-path rust/Cargo.toml` | PASS, 54 tests |
| `android/gradlew.bat testDebugUnitTest` | PASS, 285 actionable tasks |
| `flutter build apk --debug` | PASS |
| `git diff --check` | PASS |

The Android unit gate requires a complete JDK 21 because Robolectric for API
36 does not run on Java 17. DevEco's Java 21 runtime was also insufficient
because it omits `jlink`. The passing run used a process-local Microsoft
OpenJDK 21.0.12 at
`C:\tmp\sitemark-jdk21\expanded\jdk-21.0.12+8`; repository and global Java
configuration were not changed.

## APK

- Path: `C:\tmp\sitemark-pr30-review\build\app\outputs\flutter-apk\app-debug.apk`
- Size: 265,843,928 bytes
- SHA-256: `38FEA9E1519DDA0DC8D1D17A1DB5B75AACC36FA0C7B8088F116FECFD4981B330`

## Device acceptance

`adb devices -l` reports only `emulator-5554` (`Android_SDK_built_for_x86_64`,
Android 16/API 36). No authorized Xiaomi 15 physical device is connected, so
no true-device acceptance is claimed.

Manual Xiaomi 15 checklist still required:

1. Install the debug APK without removing production data; verify launch and
   upgrade behavior.
2. Switch Projects / All records / Settings repeatedly and confirm scroll,
   search, and filters are preserved.
3. Exercise system back from detail, search, filters, capture template, and
   confirmation layers.
4. Confirm select all / cancel all acts on the current filter result.
5. Capture continuously: project part, work content, and photographer remain;
   notes clear for the next photo; background processing refreshes the list.
6. Verify processed/original switching, both detail tabs, Hero entry/return,
   and adjacent-photo full-screen swipes without a blank first frame.
7. Check all three settings groups and their secondary pages.
8. Check glass readability in light/dark themes and bright outdoor conditions,
   200% text without clipping, and system reduced-motion behavior.
9. Deny camera/location/storage permissions and exercise backup corruption and
   low-storage paths; confirm each message explains the cause and recovery.

No push or pull request was created.
