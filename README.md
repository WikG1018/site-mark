# SiteMark 工程印记

SiteMark is an open-source, offline-first engineering watermark camera for
Android 12 and newer. It invokes the phone manufacturer's camera, preserves the
original photo privately, and publishes a traceable engineering-watermarked
copy without ads or analytics.

SiteMark 是一款面向 Android 12 及以上设备的开源、离线工程水印相机。它调用手机厂商
原相机完成拍摄，在应用私有空间保留原图，并生成可归档、可导出的工程水印成片；不含
广告、统计 SDK、账号或云服务。

Development status: `v0.1.0-alpha`.

## Why SiteMark / 为什么做工程印记

- Uses Android's external system-camera intent, so users keep the tuning,
  lenses, HDR, stabilization, and controls supplied by the phone maker.
- No in-app camera permission, ads, analytics, account, cloud, or Google Play
  Services dependency.
- Stores originals in app-private storage and publishes only completed
  watermarked JPEGs to `Pictures/SiteMark`.
- Keeps a SHA-256 traceability digest for the original and exports a UTF-8-BOM
  CSV plus a versioned JSON manifest.
- Applies per-project constrained watermark settings for left/right placement,
  card opacity, and accent color.
- Supports Simplified Chinese and English.

## Core flow / 核心流程

1. Create a project and enter the work location, work content, and
   photographer.
2. Optionally grant one foreground location request. Denial never blocks the
   camera.
3. SiteMark opens the manufacturer's camera and gives it a narrowly scoped
   content URI for one private original.
4. Rust applies EXIF orientation, renders the full-resolution watermark, and
   computes SHA-256.
5. Android publishes the JPEG to MediaStore. Descriptive fields can later be
   corrected and regenerated without changing the capture evidence.
6. Export the project as a ZIP with completed photos, CSV, manifest, and
   optional originals.

## Privacy and permissions

Release builds request only foreground coarse/fine location. They do **not**
request `CAMERA`, `INTERNET`, background location, broad media access, or
storage permissions. The camera receives temporary access to a single output
URI through Android's URI grant mechanism.

## Architecture

- Flutter: Material 3 UI, localization, Riverpod orchestration, GoRouter, and
  Drift/SQLite persistence.
- Kotlin: system-camera intent, process-death recovery marker,
  `LocationManager`, the narrow capture `ContentProvider`, and MediaStore.
- Rust: EXIF orientation, full-resolution JPEG watermark rendering, hashing,
  CSV/manifest generation, and ZIP export over file paths via
  flutter_rust_bridge.

## Build locally

Requirements: Flutter 3.44.6, JDK 17, Android SDK 36 with NDK
28.2.13676358, and stable Rust with Android targets.

```bash
flutter pub get
flutter analyze
flutter test
cargo test --manifest-path rust/Cargo.toml
flutter build apk --debug
```

Release signing uses an ignored `android/key.properties` file:

```properties
storeFile=../release.jks
storePassword=change-me
keyAlias=sitemark
keyPassword=change-me
```

Tagged GitHub releases build signed arm64 and universal APKs and publish
`SHA256SUMS.txt`. See [the release checklist](docs/release-checklist.md).

Current automated and emulator evidence is recorded in the
[v0.1.0-alpha verification record](docs/verification-v0.1.0-alpha.md).

See the [design](docs/superpowers/specs/2026-07-16-sitemark-design.md) and
[implementation plan](docs/superpowers/plans/2026-07-16-sitemark-v0.1.0.md).

Privacy: [English / 简体中文](PRIVACY.md) · [Contributing](CONTRIBUTING.md) ·
[Security](SECURITY.md) · [Third-party notices](THIRD_PARTY_NOTICES.md)

## License

Apache License 2.0.
