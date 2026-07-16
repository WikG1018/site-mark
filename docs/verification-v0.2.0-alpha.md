# v0.2.0-alpha verification record

Verified on 2026-07-16 from a Windows host. This record covers the full v0.2.0
plan (Tasks 1-8): persistent background capture processing, capture-field
retention for consecutive shooting, image previews, date-filtered records,
global settings, and the enlarged engineering watermark typography.

## Toolchain versions

| Tool | Version |
| --- | --- |
| Flutter | 3.44.6 (stable, revision ee80f08bbf) |
| Dart | 3.12.2 (stable) |
| Rust / rustc | 1.95.0 (59807616e 2026-04-14) |
| Cargo | 1.95.0 (f2d3ce0bd 2026-03-21) |
| JDK | OpenJDK 17.0.19 LTS (Microsoft build 17.0.19+10-LTS) |
| Android SDK | compileSdk 36, build-tools 36.0.0 |
| Gradle | 9.1.0 (via Flutter plugin) |
| App version | `0.2.0+2` |

Key dependency versions (from `pubspec.lock`): drift 2.34.2, drift_flutter
0.3.1, flutter_rust_bridge 2.12.0, flutter_riverpod 3.3.2, go_router 17.3.0,
workmanager 0.9.0+3, sqlite3 3.4.0, package_info_plus 10.2.0, uuid 4.6.0,
path_provider 2.1.6, share_plus 13.2.1, pigeon 27.1.2, build_runner 2.15.1,
drift_dev 2.34.0, flutter_lints 6.0.0.

## Automated verification

Every command below exited 0 on the Windows host.

| Command | Result |
| --- | --- |
| `flutter pub get` | exit 0, dependencies resolved |
| `dart run build_runner build --delete-conflicting-outputs` | exit 0, 81 outputs, no uncommitted generated diff (`app_database.g.dart` unchanged) |
| `dart run pigeon --input pigeons/system_api.dart` | exit 0, no uncommitted generated diff |
| `dart format --output=none --set-exit-if-changed lib test integration_test` | exit 0, 41 files, 0 changed |
| `flutter analyze` | exit 0, no issues found |
| `flutter test` | exit 0, **87 tests passed** |
| `cargo fmt --manifest-path rust/Cargo.toml -- --check` | exit 0, formatted |
| `cargo test --manifest-path rust/Cargo.toml` | exit 0, **6 tests passed** |
| `cd android && ./gradlew.bat test` | exit 0, BUILD SUCCESSFUL (`:app:testDebugUnitTest`, `:workmanager_android:testDebugUnitTest`) |
| `flutter build apk --debug` | exit 0, `build/app/outputs/flutter-apk/app-debug.apk` built |

### Dart test highlights (87 passing)

- **Schema v2 -> v3 migration** (`app_database_migration_test.dart`, 3 tests):
  preserves captures and inserts default app settings, allows increments and
  retries on upgraded rows, and a fresh database still inserts default app
  settings on first open.
- **Idempotency and retry** (`capture_processor_test.dart`, 14 tests): the
  processor is idempotent on `ready`, increments `processingAttempts`,
  classifies transient vs. permanent failures, marks `failed` on the third
  attempt, and re-publishes the same MediaStore entry on regeneration.
- **Serial background queue** (`capture_background_scheduler_test.dart`, 6
  tests): enqueue appends to the serial render queue with the capture tag and
  input, retry re-enqueues with the same queue/tag, and reconciliation
  enqueues every captured/rendering row once while skipping ready/failed.
- **Filters** (`app_database_test.dart` + `capture_filter_ui_test.dart`): the
  capture summary uses the local half-open date range, respects the project
  filter, sorts by `coalesce(capturedAt, createdAt)` descending, and the
  cascading year/month/day filter enforces the parent-child invariant.
- **Settings persistence** (`global_settings_screen_test.dart`, 7 tests): theme
  and language persist through database settings, the About section exposes
  the repository name and license, and new projects copy current global
  watermark defaults.
- **Watermark geometry** (`rust/tests/core_test.rs`): the watermark typography
  is exactly 20% larger and fits verified landscape and portrait outputs.
- **Field retention** (`widget_test.dart`): queued capture stays on the form,
  clears notes, re-enables the button, and prefills the three carry-forward
  fields while leaving notes blank.

### Integration test

`integration_test/simple_test.dart` was extended with the
`capture queues, remains ready, and appears in filtered records` test. It
reuses the inline-scheduler and fake platform/image/sharing layer from
`test/widget_test.dart`: create project, open the capture form, enter the
three required fields, tap the camera (fake returns `captured`), assert the
`照片已加入后台处理，可继续拍摄` snackbar and a still-present capture button,
open all-records, select the 2026-07-16 date filter, and assert
`SM-20260716-001` appears.

> Note: integration tests run under `IntegrationTestWidgetsFlutterBinding`,
> which requires a device or emulator (`flutter test integration_test/`). It
> is **not** executed in this headless host environment. `flutter analyze`
> confirms it compiles cleanly with no issues. Execution is deferred to the
> device-acceptance step below.

## Alpha APK verification

- File: `C:\Users\Administrator\Documents\水印相机\SiteMark-v0.2.0-alpha-debug.apk`
- Size: 223,205,143 bytes (~213 MB; debug build bundles native libraries for
  multiple ABIs and includes debug symbols).
- SHA-256: `a084de57a60c0dd962f548a35db8a4a2d13aaee3e6e904a44e8edaca6d54ae16`
  (re-verified after the security-boundary fix that strips `INTERNET` and
  `ACCESS_NETWORK_STATE` from the debug build; matches `certutil -hashfile`
  on the Windows Chinese-named path and `sha256sum` on the ASCII copy.)
- Build type: **debug-signed** (the existing phone-test APK is debug-signed and
  no release keystore is configured). This is a testing artifact, not a
  production-signed release.

### Package identity (`aapt dump badging`)

- Package name: `io.github.wikg1018.sitemark`
- versionCode: `2`
- versionName: `0.2.0`
- minSdkVersion: `31` (Android 12)
- targetSdkVersion: `36` (Android 16)
- application-label: `SiteMark`

### Permissions

The HARD security boundary for SiteMark (see the design spec and
`NEXT_AGENT_PROMPT`) is: **no ads, analytics, accounts, cloud sync, remote
APIs, Google Play Services, or INTERNET permission.** The debug APK was
re-verified after stripping the two network permissions that were being merged
in by the `workmanager` dependency chain.

Debug APK declares (via `aapt dump permissions`, post-fix):

- `ACCESS_COARSE_LOCATION` - required, optional foreground approximate location.
- `ACCESS_FINE_LOCATION` - required, optional foreground precise location.
- `POST_NOTIFICATIONS` - contributed by the `workmanager_android` plugin; kept
  (does not grant network access).
- `WAKE_LOCK` - contributed by `androidx.work:work-runtime` (a transitive
  dependency of `workmanager_android`) for local on-device background CPU wake
  locks. Kept (does not grant network access).
- `RECEIVE_BOOT_COMPLETED` - contributed by `androidx.work:work-runtime` for
  boot reconciliation / restart recovery of pending local work. Kept (does not
  grant network access).
- `FOREGROUND_SERVICE` - contributed by `androidx.work:work-runtime`; may be
  needed by WorkManager. Kept (does not grant network access).
- `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` - Android 13+ runtime receiver
  hardening, generated by the build. Kept (internal, not a network permission).

Permissions **stripped** at manifest-merge time (verified absent from the
merged and packaged debug manifests and from `aapt dump permissions`):

- `INTERNET` - **removed.** Flutter's default `debug`/`profile` variant
  manifests declare it for hot reload / breakpoints; it is stripped via
  `tools:node="remove"` in `android/app/src/main/AndroidManifest.xml` and the
  `debug`/`profile` variant manifests so the debug APK itself carries no
  network permission. Hot reload over USB still works via the local Dart VM
  service socket, which does not require the `INTERNET` permission.
- `ACCESS_NETWORK_STATE` - **removed.** Declared by
  `androidx.work:work-runtime`'s manifest; stripped via
  `tools:node="remove"` in `android/app/src/main/AndroidManifest.xml` so it
  never reaches the shipped APK.

The debug APK does **not** declare `CAMERA`, `ACCESS_BACKGROUND_LOCATION`,
`READ_MEDIA_IMAGES`, `READ_EXTERNAL_STORAGE`, or `WRITE_EXTERNAL_STORAGE`. The
camera is owned by the external system camera app; SiteMark only provides a
one-time URI target. `INTERNET` and `ACCESS_NETWORK_STATE` are now also absent
from the debug build, matching the offline boundary the Release build already
satisfied.

### Signature (`apksigner verify`)

- Verifies: true.
- Signed using APK Signature Scheme v2 (v1 JAR signing false, v3/v4 false).
- Signer certificate DN: `C=US, O=Android, CN=Android Debug` (debug keystore).
- Signer certificate SHA-256:
  `5554171fd41b9a6317b261249d50a0c5c80a2762c7ed8750143581a6c9556b8f`.
- Key algorithm: RSA, 2048-bit.

## Device acceptance — PENDING user real-device confirmation

There is **no physical Android device** in this verification environment, so
the eight device-acceptance steps below were **not** executed here. They are
listed as pending real-device confirmation with the shortest test steps for a
user to run on an Android 12+ device that already has the v0.1.0 debug APK
installed. None of these results were observed; all are awaiting confirmation.

1. **In-place upgrade** — `adb install -r
   C:\Users\Administrator\Documents\水印相机\SiteMark-v0.2.0-alpha-debug.apk`;
   open SiteMark and confirm existing projects and records remain.
2. **Ten-shot consecutive capture** — open a project, tap 拍摄, fill the three
   fields, tap 调用系统相机, accept the photo, and repeat 10 times. After each
   camera return, confirm the form is immediately usable, the three fields
   (工程部位/工作内容/拍摄人) remain, and 备注 clears.
3. **Queue transition and thumbnail swap** — shoot a photo and watch the record
   list transition 等待相机 -> 处理中 -> 已完成; confirm the thumbnail swaps from
   the original to the watermarked image once ready.
4. **Swipe-away during processing** — with at least one item in 处理中, swipe
   SiteMark from recent tasks, reopen, and confirm the item reaches 已完成.
5. **Reboot with a queued item** — leave one item queued, reboot the device,
   reopen SiteMark after boot, and confirm reconciliation completes it.
6. **MediaStore output** — open `Pictures/SiteMark` and confirm it contains
   exactly one JPEG per photo number (e.g. `SM-20260716-001.jpg`).
7. **Filters, settings, locales, themes** — verify project and global
   year/month/day filters, settings persistence across restart, new-project
   watermark defaults, Chinese/English, and light/dark/system themes.
8. **Failure and retry paths** — deny location, cancel the system camera, and
   inject a render failure; confirm capture remains usable and the final
   failure exposes a retry action.

Record for each step: device model, Android version, timestamp, observed queue
result, and any known OS scheduling delay (background start time is
system-controlled; Android "Force stop" pauses scheduled work until the app is
reopened).

## Screenshots - PENDING real-device access

The brief required 4 phone screenshots to be captured and posted at handoff.
There is **no physical Android device and no emulator** in this verification
environment, so the screenshots could **not** be captured here. No fake
screenshot files were created. The 4 required screenshots are deferred to the
real-device acceptance step and will be captured on an Android 12+ device
running the v0.2.0-alpha debug APK:

1. **All records with filters** - the all-records list showing the cascading
   year/month/day date filter applied (e.g. a 2026-07-16 filter surfacing
   `SM-20260716-001`).
2. **Project thumbnails** - a project's record list showing the
   `CaptureRecordCard` preview/thumbnail swapped from the original to the
   watermarked image once a record reaches ready.
3. **Settings / About** - the global settings screen scrolled to the About
   section exposing the repository name and license.
4. **Retained capture form** - the capture form immediately after a camera
   return, showing the three carry-forward fields
   (工程部位/工作内容/拍摄人) still populated, 备注 cleared, and the capture
   button re-enabled for the next consecutive shot.

Each screenshot will be captured during user device acceptance and posted at
handoff once a real device is available.

## Final Acceptance Checklist status

- Five reported issues have a corresponding passing automated test: **automated:
  passed** (idempotency, retry, filter, settings, watermark geometry). Device
  check: **pending user confirmation**.
- Database migration v2 -> v3 preserves existing phone data: **automated:
  passed** (3 migration tests). Device: **pending user confirmation**.
- Ten-shot consecutive capture does not wait for prior rendering: **automated:
  passed** (queued-capture widget test). Device: **pending user confirmation**.
- Background retry is serialized, bounded to three attempts, and idempotent in
  MediaStore: **automated: passed** (processor + scheduler tests). Device:
  **pending user confirmation**.
- Project and global lists share the same preview card and date semantics:
  **automated: passed** (shared `CaptureRecordCard` + filter tests). Device:
  **pending user confirmation**.
- Theme, language, and new-project defaults persist; existing project settings
  are untouched: **automated: passed** (settings + new-project-defaults tests).
  Device: **pending user confirmation**.
- Watermark typography is exactly 20% larger and fits verified
  landscape/portrait outputs: **automated: passed** (2 Rust geometry tests).
  Device: **pending user confirmation**.
- Test APK updates the existing debug build without uninstalling: **pending user
  confirmation** (debug-signed, same applicationId; `adb install -r` required).
- README, verification evidence, APK name, size, and SHA-256 match v0.2.0+2:
  **passed** (this document, README, and the APK artifact above).
