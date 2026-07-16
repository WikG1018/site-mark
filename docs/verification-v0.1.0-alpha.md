# v0.1.0-alpha verification record

Verified on 2026-07-16 from a Windows host with Flutter 3.44.6, JDK 17,
Android SDK 36 / NDK 28.2.13676358, and Rust 1.95.0.

## Automated verification

- `flutter analyze`: no issues.
- `flutter test`: 22 tests passed.
- Rust format and Clippy with warnings denied: passed.
- Rust tests: 3 passed, including full-resolution render and ZIP/CSV/manifest
  contents.
- `:app:testDebugUnitTest`: passed, including capture-target path validation.
- Debug and release APK assembly: passed.
- Release APK inspection: `ACCESS_COARSE_LOCATION` and
  `ACCESS_FINE_LOCATION` are the only user-facing permissions. The built APK
  does not contain `CAMERA`, `INTERNET`, background location, or broad media
  permissions.

## Android 16 emulator acceptance

Device: API 36 default x86_64 AVD, 1080 x 2400, Android 16, using the AOSP
synthetic camera.

- SiteMark launched `com.android.camera2/com.android.camera.CaptureActivity`
  through `ACTION_IMAGE_CAPTURE`; the external camera owned the visible camera
  and review UI.
- Accepting the system-camera result returned to SiteMark and completed the
  `captured -> rendering -> ready` flow.
- The private original remained under the app's `files/originals` directory.
- Rust rendered a 1392 x 1856 JPEG with Chinese text and traceability fields.
- Android published `SM-20260715-001.jpg` to `Pictures/SiteMark`.
- The record stored its immutable photo number, timestamp, coordinates, and
  original SHA-256.
- An existing schema-v1 project and completed capture survived in-place upgrade
  to schema v2, which adds project watermark settings.

## Checks still required before a public stable release

- Test at least one physical Android 12 phone and representative Samsung,
  Xiaomi/Redmi, OPPO/OnePlus, vivo, Honor, and Pixel camera apps.
- Exercise precise, approximate, denied, disabled, and timed-out location on
  physical devices.
- Force-kill SiteMark while the manufacturer camera is open and verify the
  recovery marker on physical devices.
- Confirm edit/regeneration replaces the same MediaStore item on each vendor.
- Inspect project ZIP exports with and without originals on a physical phone.
- Configure the GitHub Actions signing secrets and verify the first tagged
  arm64 and universal APK release.

The emulator run proves the Android intent, private-file, Rust render,
MediaStore, persistence, and UI integration. It does not substitute for the
manufacturer-camera compatibility matrix above.
