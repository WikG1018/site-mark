# SiteMark release checklist

## Automated

- `flutter analyze`
- `flutter test` (unit/widget tests)
- `flutter test integration_test/` (requires a device or emulator)
- `dart run build_runner build --delete-conflicting-outputs`
- `dart run pigeon --input pigeons/system_api.dart`
- `dart format --output=none --set-exit-if-changed lib test integration_test`
- `cargo fmt --check --manifest-path rust/Cargo.toml`
- `cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings`
- `cargo test --manifest-path rust/Cargo.toml`
- `android/gradlew :app:testDebugUnitTest`
- Build universal and arm64 release APKs with the release keystore.
- Confirm the merged release manifest has no `INTERNET`, `CAMERA`, background
  location, or broad media permission. `INTERNET` and `ACCESS_NETWORK_STATE`
  are stripped via `tools:node="remove"` in the main, `debug`, and `profile`
  variant manifests, so the app enforces no-network across all build variants
  (see `docs/verification-v0.2.0-alpha.md` Permissions section; the debug APK
  itself carries no `INTERNET`).
- Generate SHA-256 files for every APK.

## v0.2.0-alpha artifacts

- Version bumped to `0.2.0+2` in `pubspec.yaml` and `android/local.properties`.
- Debug Alpha APK built, copied to
  `C:\Users\Administrator\Documents\水印相机\SiteMark-v0.2.0-alpha-debug.apk`,
  with recorded size and SHA-256 in `docs/verification-v0.2.0-alpha.md`.
- Package ID `io.github.wikg1018.sitemark`, versionName `0.2.0`, versionCode
  `2`, minSdk 31, targetSdk 36, verified via `aapt dump badging`.
- APK signature verified via `apksigner` (debug-signed, APK Signature Scheme v2).

## Device acceptance

- Test at least one Android 12 device and one Android 16 emulator/device.
- `adb install -r` the debug APK over the existing v0.1.0 debug build and
  confirm projects and records survive the in-place upgrade.
- Shoot 10 photos consecutively; after each camera return confirm the form is
  immediately usable, the three descriptive fields remain, and notes clear.
- Observe the list transition waiting -> processing -> ready and the thumbnail
  swap from original to watermarked image.
- Swipe SiteMark from recent tasks while an item is processing; reopen and
  confirm it reaches ready.
- Reboot with a queued item; reopen after boot and confirm reconciliation
  completes it.
- Confirm `Pictures/SiteMark` contains exactly one JPEG per photo number.
- Verify project and global year/month/day filters, settings persistence,
  new-project defaults, Chinese/English, and light/dark/system themes.
- Deny location, cancel the system camera, and inject a render failure; confirm
  capture remains usable and the final failure exposes retry.
- Confirm the manufacturer camera opens and saves a full-resolution target.
- Deny location, allow approximate location, and allow precise location.
- Kill SiteMark while the camera is open and verify startup recovery.
- Edit a completed record and verify the same MediaStore image is replaced.
- Export with and without originals and inspect JPEG, BOM CSV, and manifest.
- Delete a record and verify private and published copies are removed.

Background start time is system-controlled; Android "Force stop" pauses
scheduled work until the app is reopened.

Document device models, Android versions, timestamps, observed queue results,
and known OS scheduling delays in the release notes. Record the evidence and
any remaining gates in `docs/verification-v0.2.0-alpha.md`.
