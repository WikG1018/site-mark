# SiteMark release checklist

## Automated

- `flutter analyze`
- `flutter test`
- `cargo fmt --check --manifest-path rust/Cargo.toml`
- `cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings`
- `cargo test --manifest-path rust/Cargo.toml`
- `android/gradlew :app:testDebugUnitTest`
- Build universal and arm64 release APKs with the release keystore.
- Confirm the merged release manifest has no `INTERNET`, `CAMERA`, background
  location, or broad media permission.
- Generate SHA-256 files for every APK.

## Device acceptance

- Test at least one Android 12 device and one Android 16 emulator/device.
- Confirm the manufacturer camera opens and saves a full-resolution target.
- Deny location, allow approximate location, and allow precise location.
- Kill SiteMark while the camera is open and verify startup recovery.
- Edit a completed record and verify the same MediaStore image is replaced.
- Export with and without originals and inspect JPEG, BOM CSV, and manifest.
- Delete a record and verify private and published copies are removed.

Document device models and known camera-app quirks in the release notes.
Record the evidence and any remaining gates in
`docs/verification-v0.1.0-alpha.md`.
