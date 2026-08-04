# Final UI review fix report

Date: 2026-08-05
Branch: `design/ui-refresh-v2`
Review baseline: `f97db0378000a80ea0766dca0ac9cb6574c520aa`

## Scope

This increment addresses the final review findings only. It does not change
the release version, download links, database schema, watermark content,
backup format, or project lifecycle rules.

## RED and GREEN evidence

### I1 - active filters participate in system Back LIFO

- RED: production `routerProvider` / `StatefulShellRoute` tests applied an
  English All Records project-plus-year filter and a Chinese project-detail
  year filter. Both rendered `PopScope.canPop == true`, so Back could leave the
  page instead of clearing the applied query.
- GREEN: All Records and project detail now use the established precedence
  `selection/edit -> search -> filters -> page`. A currently open filter
  overlay is still popped by the real router first. The next Back removes the
  active UI condition and refreshes the query; only the following Back may
  navigate or exit.
- Coverage: chips disappear, unfiltered records return, project/date filters
  are covered in English/Chinese, and project detail navigates only after the
  date filter is cleared.

### I2 - restored KILL notes stay visible

- RED: at 360 dp and 2x text scaling, a real non-empty KILL draft restored the
  controller value but rendered no `notes` `TextFormField`.
- GREEN: the notes component initializes from and listens to its real
  controller. A non-empty restored value expands the actual field; mounted
  guards protect asynchronous restoration. The test edits and clears the
  visible field, collapses it, and verifies the submitted capture draft has no
  notes. No overflow exception is produced.

### I3 - file inspection error and retry

- RED: ready/failed records in Chinese/English exposed no file-info error
  surface after `inspect()` failed; the page remained on a spinner.
- GREEN: file info now distinguishes loading, localized error, and data. The
  error explains the local inspection reason and a safe next step without raw
  exception text. The real Check again button invalidates the cached Future,
  key, and media-service identity before calling `inspect()` again. Record or
  project replacement also invalidates the cache. `FutureBuilder` is bound to
  the replacement Future and ignores callbacks from an older Future, so a late
  result cannot replace the newer request.
- Coverage: ready/failed x Chinese/English, error -> real retry tap -> metadata
  success, two inspection calls, and raw exception non-disclosure.

## Documentation corrections

- Removed the obsolete README Actual results screenshot block rather than
  presenting old UI as current. Feature text remains; version and download
  links are unchanged.
- Removed the two trailing spaces from the design document.
- Corrected the Task 10 report so its filter-Back and diff-check status is not
  presented as final acceptance.

## Fresh verification gates

| Gate | Final result |
| --- | --- |
| Focused Flutter regression (`back_navigation`, `capture_field_reuse`, `capture_detail_screen`) | PASS, 107 tests |
| `dart format --output=none --set-exit-if-changed lib test` | PASS, 193 files checked, 0 changed |
| `flutter analyze` | PASS, no issues found |
| `flutter test` | PASS, 869 tests |
| `cargo fmt --manifest-path rust/Cargo.toml -- --check` | PASS |
| `cargo test --manifest-path rust/Cargo.toml` | PASS, 54 tests |
| JDK 21 `android/gradlew.bat testDebugUnitTest --no-daemon` | PASS, 285 actionable tasks |
| Fresh `flutter build apk --debug` | PASS |
| Working tree, staged changes, and baseline `git diff --check` before commit | PASS |
| Post-commit `git diff --check f97db03..HEAD` | PASS |

Fresh debug APK:

- Path: `build/app/outputs/flutter-apk/app-debug.apk`
- Size: 265,853,505 bytes (253.54 MiB)
- SHA-256: `4A80E3A8F12A3D4E2D1B026206691EB1C337A1C1268490A840C75B9C38A83844`

`adb devices -l` reported only `emulator-5554` as an attached device. This
report does not claim an emulator E2E pass or a Xiaomi 15 physical-device
pass. The earlier bounded integration-test attempt was stopped after it hung;
it is not counted as passing.
