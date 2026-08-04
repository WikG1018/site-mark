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
- Added shared, state-matched photo-processing guidance. List cards use a short
  reason plus "open the record" action and never promise retry. Detail guidance
  derives retry availability from the final failure code, original-photo state,
  and project lifecycle, so Retry processing is named only when its button is
  present.
- Made narrow cards switch to a stacked layout for large text, keeping failed
  records readable and tappable at 360 dp with 2x text scaling in both locales.
- Kept failure guidance visible when media inspection fails. An unknown
  original-photo state never enables retry; the detail explains that inspection
  is unavailable and offers only safe keep/reopen/menu-delete next steps.
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
- The first final-action tests found processing-failure copy that promised
  retry even when the original was missing, and the English 360 dp / 2x failed
  card produced a 906-pixel bottom overflow. After shortening the list copy,
  the same test still exposed the underlying narrow-column layout before the
  card switched to its large-text stacked layout.
- The final media-inspection regression produced zero failure-guidance widgets
  in both locales when `CaptureMediaService.inspect()` threw, confirming that
  `info == null` incorrectly suppressed the entire banner.

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
- Chinese and English detail cases for retained/active, missing/active,
  cleared/active, and retained/read-only processing failures, including exact
  agreement between guidance and Retry processing button presence.
- Chinese and English failed-card tests at 360 dp / 2x, covering no overflow,
  no list-level retry promise, and tap-through to the detail/actions surface.
- The real `finalizationPending` restore Snackbar in both locales, not only a
  localization snapshot.
- Real Chinese and English detail screens with an injected media-inspection
  exception: reason and recovery guidance remain visible, raw errors stay
  hidden, the detail menu remains available, and Retry processing is absent.

## Copy audit

| Area | Reason present | Next step present | Result |
| --- | --- | --- | --- |
| Permission | Yes | Open system settings / retry | Existing copy accepted |
| Backup creation | Yes | Retry / isolate one project / save or share again | UI copy accepted |
| Restore preparation | Typed reason | Choose a SiteMark project backup, upgrade the app, choose a compatible archive, or free storage as appropriate | Nine typed mappings covered by zh/en contracts and real Snackbar tests |
| Restore execution | Typed reason | Rename conflicts in preview, restart after safe finalization, restore again, or use single-project backups as appropriate | Real zh/en Snackbar tests cover name conflict, rollback, general failure, and finalization pending |
| Capture-card failure summary | Code-specific short reason | Open the record to see available actions | Lists do not claim retry or menu availability without final state/lifecycle data |
| Photo original missing | Original evidence file is gone | Detail says retake; keep or use the top-right menu to delete | Retry hidden |
| Photo original modified | Capture-time checksum no longer matches | Detail says preserve evidence and retake, or use the top-right menu to delete | Retry hidden |
| Photo processing/unknown | Processing failed while original state and project lifecycle may vary | Detail offers retry only for a retryable code with retained original in an active project; otherwise gives the actual missing, cleared, or read-only recovery | Guidance/button agreement tested in zh/en |
| Photo media state unavailable | Media inspection could not determine the original state | Keep the record and reopen details later to check again, or use the active-project detail menu to delete | Retry hidden; real inspect-exception path tested in zh/en |
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
| `dart format --output=none --set-exit-if-changed lib test` | PASS, 193 files checked, 0 changed |
| Selected final media-inspection widget/unit tests | PASS, 32 tests |
| `flutter analyze` | PASS, no issues |
| `flutter test` | PASS, 862 tests |
| `cargo fmt --manifest-path rust/Cargo.toml -- --check` | PASS |
| `cargo test --manifest-path rust/Cargo.toml` | PASS, 54 tests |
| `android/gradlew.bat testDebugUnitTest` | PASS, 285 actionable tasks |
| `flutter build apk --debug` | PASS |
| `git diff --check` | PASS |

Rust and Android unit gates were not rerun for this final Dart-only increment.
Their immediately preceding Task 10 results above remain fresh: Rust passed 54
tests and Android passed with the process-local JDK 21. The APK was rebuilt
after the Dart changes, and its size/hash below are from that fresh artifact.

The Android unit gate requires a complete JDK 21 because Robolectric for API
36 does not run on Java 17. DevEco's Java 21 runtime was also insufficient
because it omits `jlink`. The passing run used a process-local Microsoft
OpenJDK 21.0.12 at
`C:\tmp\sitemark-jdk21\expanded\jdk-21.0.12+8`; repository and global Java
configuration were not changed.

## APK

- Path: `C:\tmp\sitemark-pr30-review\build\app\outputs\flutter-apk\app-debug.apk`
- Size: 265,845,247 bytes
- SHA-256: `82A4DC5C1EE1D3A7CC01C1C7A08434F70F3D12F1F585634A8A3A9A83E7E65A90`

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
