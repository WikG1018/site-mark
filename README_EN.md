# SiteMark

English | [简体中文](README.md)

> An offline-first watermark camera for engineering site records: the Android version is published as a stable release (Latest `v1.0.18`, targetSdk 37 / Android 17), the native HarmonyOS NEXT ArkTS version is published alongside it (unsigned HAP), and the iOS build reuses the same Flutter codebase and is fully adapted (iOS 26/27-style UI, background catch-up, dark mode) — it now waits on an Apple Developer account for signed distribution and has no installable package yet. All product lines live on a single branch.

[![CI](https://github.com/WikG1018/site-mark/actions/workflows/ci.yml/badge.svg)](https://github.com/WikG1018/site-mark/actions/workflows/ci.yml)
![Android 12+](https://img.shields.io/badge/Android-12%2B-3DDC84?logo=android&logoColor=white)
![HarmonyOS native](https://img.shields.io/badge/HarmonyOS-native%20ArkTS-E60012)
[![License](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)
![No ads](https://img.shields.io/badge/Ads-none-176B55)
![NAS sync](https://img.shields.io/badge/NAS_sync-WebDAV%20%2F%20SFTP%20%2F%20SMB-176B55)
[![Latest](https://img.shields.io/badge/latest-v1.0.18-176B55)](https://github.com/WikG1018/site-mark/releases/tag/v1.0.18)
[![HarmonyOS](https://img.shields.io/badge/HarmonyOS-native--v1.0.10-E60012)](https://github.com/WikG1018/site-mark/releases/tag/native-v1.0.10)

**Current stable version (Latest): [`v1.0.18`](https://github.com/WikG1018/site-mark/releases/tag/v1.0.18)**

**Current HarmonyOS native version: [`native-v1.0.10`](https://github.com/WikG1018/site-mark/releases/tag/native-v1.0.10) (HarmonyOS NEXT, unsigned HAP)**

Requires Android 12 (API 31) or later. `v1.0.18` is set as Latest: after a two-finger zoom in fullscreen preview, one-finger pan can reach the right edge of the photo; list pages hide the top and bottom bars on scroll down and show them again on scroll up. The feature baseline remains the optional three-protocol NAS sync (WebDAV/SFTP/SMB, off by default, passwords in system secure storage). Back up important projects regularly — including the private original photos — and copy the backup files outside the app's directories.

## Download

### Stable (Latest, recommended)

| Package | Applies to | Download |
| --- | --- | --- |
| arm64 | Recommended; almost all recent Android phones | [sitemark-v1.0.18-arm64.apk](https://github.com/WikG1018/site-mark/releases/download/v1.0.18/sitemark-v1.0.18-arm64.apk) |
| universal | Use when the processor architecture is unknown or arm64 cannot be installed; larger file | [sitemark-v1.0.18-universal.apk](https://github.com/WikG1018/site-mark/releases/download/v1.0.18/sitemark-v1.0.18-universal.apk) |
| SHA-256 | Verify the integrity of downloaded files | [SHA256SUMS.txt](https://github.com/WikG1018/site-mark/releases/download/v1.0.18/SHA256SUMS.txt) |

### HarmonyOS native (native-v1.0.10)

| Package | Applies to / notes | Download |
| --- | --- | --- |
| HarmonyOS HAP | **Unsigned**; sign it yourself in a DevEco/hdc environment before installing. A production signature requires an AGC release certificate (see `tool/ohos-native/sign-hap.ps1`). The published HAP is a debug build variant (an unsigned release build cannot be installed directly) | [sitemark-native-v1.0.10-unsigned.hap](https://github.com/WikG1018/site-mark/releases/download/native-v1.0.10/sitemark-native-v1.0.10-unsigned.hap) |
| HarmonyOS SHA-256 | Verify the integrity of downloaded files | [SHA256SUMS.txt](https://github.com/WikG1018/site-mark/releases/download/native-v1.0.10/SHA256SUMS.txt) |

> [!WARNING]
> Uninstalling SiteMark deletes the app database, the app-private original photos, and the private watermark files. Watermarked photos already published to the system gallery `Pictures/SiteMark` are usually kept. Before uninstalling, switching devices, or resolving a signature conflict, open "Settings → Backup & restore" first, back up the important projects, and store the ZIP files in a safe place.

## HarmonyOS NEXT native version

`ohos-native/` is an independent Stage + ArkTS + ArkUI implementation. It does not use the community Flutter HarmonyOS adaptation layer and evolves on the same single branch as the Android version. It already runs the main flows — projects, capture processing, record management, watermarking, backup & restore, storage, and diagnostics — on the DevEco NEXT emulator, and it reuses the same Rust core as the Android version for image and ZIP rules.

The current release provides an unsigned HAP of `native-v1.0.10` (see the download table above). **No signed HarmonyOS package is available yet, and the app is not on Huawei AppGallery**; the camera, gallery permissions, and performance still need to be re-verified on HarmonyOS NEXT real devices. Do not interpret the emulator results as an AppGallery release.

- [HarmonyOS native version: overview and build](ohos-native/README.md)
- [Platform deltas and verification boundaries](ohos-native/docs/deltas.md)
- [DevEco and emulator technical probe](tool/ohos-native/probe.md)
- [HarmonyOS native release history](https://github.com/WikG1018/site-mark/releases?q=native-&expanded=false)

## iOS version

iOS shares the Flutter UI, business logic, database schema, and the Rust imaging core with Android; platform capabilities (system camera bridge, optional foreground location, photo publishing and deletion, opportunistic BGTaskScheduler catch-up) live in the in-repo Swift plugin. The UI is fully adapted to iOS 26/27 conventions: large-title navigation, Cupertino action sheets and dialogs, glass-capsule toasts, edge-swipe back, and correct dark mode on every surface.

Two things remain, both blocked on external inputs: signing and TestFlight distribution through GitHub Actions once an Apple Developer account is available (signing material never enters the repository), and on-device verification of the dark launch screen, gesture feel, and real-camera behavior. Until then there is no iOS installable package and no timeline.

## Install and upgrade

1. Prefer the arm64 package; use universal only when the device is incompatible.
2. Open the APK and follow the Android prompt to allow your browser or file manager to "install unknown apps".
3. Official releases share one signature, so they upgrade in place and keep app data.
4. Debug APKs are signed differently from official builds and usually cannot upgrade in place.
5. If Android reports a signature conflict, do not uninstall the old version that holds important data; back up the projects first and confirm the backup files are outside the app's directories.

## Recent updates

See each version's [GitHub Release](https://github.com/WikG1018/site-mark/releases) for the full notes.

- **v1.0.18 / native-v1.0.10** (Latest): after a two-finger zoom in fullscreen preview, one-finger pan can reach the right edge of the photo; list pages hide the top and bottom bars on scroll down and show them again on scroll up.
- **v1.0.17 / native-v1.0.9**: About and first-launch privacy copy aligned with optional NAS sync; HarmonyOS NAS settings form gains spacing and a protocol segmented control; leftover queue, debug INTERNET, Android 17 LAN runtime permission, and fingerprint-persist fixes; wifi-only drains resume when Wi-Fi returns; live HarmonyOS queue counts.
- **v1.0.16**: NAS settings layout polish — field spacing and group rhythm, with the protocol label and segmented button aligned to the global settings conventions (48dp tap target); Android-only, feature parity with v1.0.15.
- **v1.0.15 / native-v1.0.8**: full NAS audit fixes — the settings page gains upload-queue counts and a "Retry failed uploads" entry; testing the connection uses the stored password when the field is left blank; out-of-range ports are rejected before save/test; captures still processing are deferred without burning the retry budget (no busy-spinning); uploader and credential-read failures degrade to categorized errors.
- **v1.0.14 / native-v1.0.7**: all three product lines gain an optional NAS sync (WebDAV/SFTP/SMB, off by default, talking only to the user-configured server, passwords in system secure storage); the Android/iOS database migrates to v14 (NAS config and upload bookkeeping tables), the HarmonyOS RDB to v15; uploads run on a serial queue with a 5-attempt budget, and the first SFTP connection verifies the host key fingerprint.
- **v1.0.13 / native-v1.0.6**: fixed the fullscreen photo viewer, where a photo zoomed with a two-finger pinch could not be dragged with one finger to reach the corners (fixed on both Android and HarmonyOS native); added an English README with language switching.
- **v1.0.12 / native-v1.0.5** (Pre-release): full dual-platform audit fixes (read-only batch bypass, cross-platform watermark domain unification, dark-mode contrast, cold-start notification routing, draft durability).
- **v1.0.11**: targetSdk raised to Android 17 (API 37) with compileSdk 37; reviewed the Android 17 targeted behavior changes (large-screen orientation/resizability rules, tighter background activity launches, local network permission, background audio, MessageQueue, native library loading) — none affect this offline app, runtime behavior matches API 36, and real-device regression passed.
- **v1.0.10** (Pre-release): fixed system back in selection mode on the all-records and project-records pages exiting straight to the launcher; back now first clears the selection (search and filters are handled at the same layer).
- **v1.0.9 / native-v1.0.3** (Pre-release, 2026-08-28, first joint release after the two lines merged onto one branch): Android — notifications follow the in-app language, location-failure diagnostics, export evidence guards, unknown-status tolerance, compileSdk 37; HarmonyOS native — failure reasons stored as codes that refresh with language switches, categorized error copy, atomic export writes + ZIP64 for large files, database migration scaffolding.
- **v1.0.8**: safe gallery replacement, cross-layer journal reconciliation, shared URI protection, bounded cleanup retries.
- **v1.0.7**: restore no longer deletes projects; capture processing is idempotent; decode and gallery defenses tightened.
- **v1.0.6**: recoverable media cleanup; gallery publish rollback.
- **v1.0.0–v1.0.5**: project lifecycle and backup, floating navigation, search and full-screen browsing, publishing pipeline stabilization.

## Feature overview

| Area | Current state |
| --- | --- |
| Top-level navigation | "Projects / All records / Settings" switch through a compact floating dock with a selected background that covers icon and text; list, search, and filter state are preserved per tab while only the current page is drawn; the dock hides on secondary pages such as details |
| Capture | Uses the system/vendor camera; watermarks are generated in the background during continuous shooting; the next shot keeps work location, work content, and photographer and only clears notes; recent-field suggestions and per-project naming templates; new captures are blocked in projects that are not active |
| Records | The thumbnail list shows the currently visible date to the right of the filter buttons and updates while scrolling; details toggle between "Watermarked / Original" and "Site record / File info"; tapping a photo opens adjacent photos in a full-screen viewer; supports edit, delete, and save again |
| Search & filters | Home status filters and cross-status project search; All records and project records support keyword search plus picking project, year, month, and day from a compact bottom sheet, and any applied condition can be removed individually |
| Batch actions | Checkboxes overlay thumbnails without squeezing photos or text; multi-select replaces the top-level dock with a compact floating dock of icons and text; supports select-all/clear over the current filter results, export, save again, clear originals, and deleting whole records |
| Watermark | Project name, site fields, time, and optional location; supports position, opacity, font size, and accent color |
| Projects | Lifecycle, pinning, duplicate/safe filename conflict protection; rename, delete, and per-project watermark settings |
| Settings | The top-level page is grouped into "Capture & records / Data & safety / App", centralizing watermark defaults, location, notifications, backup & restore, storage, NAS sync, diagnostics, language, appearance, and about |
| Data safety | Project backup & restore, original photo SHA-256 verification, restore transaction with file rollback, cleanup after abnormal interruptions |
| NAS sync | Optional feature (off by default): uploads watermarked photos to your own WebDAV / SFTP / SMB server; optional Wi-Fi-only gate, automatic retries with a 5-attempt budget, SFTP host-fingerprint verification (TOFU); passwords stay in system secure storage and never enter backups, diagnostics, or the database |
| Polish | Glass navigation and cards, stable hierarchy-respecting page transitions, image hero animations, back logic without hidden list flicker, reduced-motion support, and record/full-screen image lists that keep loading more |

## Product positioning

I built SiteMark because recording on a jobsite takes more than stamping text on photos: shooting has to feel effortless, background processing has to be dependable, projects need clean archiving, and original-photo details must stay traceable.

I deliberately did not re-implement a camera or embed a third-party camera SDK — manufacturers have spent years tuning their own lenses, and an app-level rework only makes things worse. SiteMark invokes the system/vendor camera through standard platform APIs, leaving focus, HDR, stabilization, and image quality to the system, and does three things itself: engineering fields before the shot, local watermarking after it, and record/project management.

The published APK has no ads, accounts, third-party cloud sync, or analytics uploads; repository links open in the external browser. The only network surface is the NAS sync you configure and enable yourself (WebDAV/SFTP/SMB, see D-023 in `docs/decision-records.md`): uploads go exclusively to the server you enter, and the feature is off by default. Offline remains the default state — the network is an exception the user explicitly opens.

## Quick start

1. Create a project, fill in the description as needed, and adjust "Watermark settings for this project".
2. Fill in work location, work content, photographer, and optional notes; you can pick from the project's recent suggestions or apply a per-project naming template.
3. Request foreground location only when you need it; declining location does not block taking photos.
4. Tap capture and take the photo in the phone's system/vendor camera.
5. Back in SiteMark the photo enters local background processing, and you can keep shooting the next one.
6. Filter by keyword, project, or date in project records or All records; preview, edit, and manage photos.
7. Before uninstalling or switching devices, open "Settings → Backup & restore" and create a backup of one or more projects.

Continuous shooting keeps work location, work content, and photographer and only clears notes. Recent suggestions come from the current project's existing records; naming templates store only the three required fields, up to 100 of them, and notes are never saved or overwritten.

## Watermark and photo naming

The watermark can show:

- Project name;
- Work location;
- Work content;
- Photographer;
- Capture time;
- Location, when granted and successfully obtained.

The photo number is not drawn into the watermark. New photos use this short file name:

```text
{sanitized project name}-SM-{yyyyMMdd}-{app-wide daily sequence}.jpg
```

For example: `云湖之城-SM-20260717-003.jpg`.

Renaming a project only affects the project's display name and photos taken after the rename. Historical photo numbers, file names, file paths, and generated watermarks are not modified.

## Records and original photo management

- **Clear originals**: deletes the app-private original photos and keeps the watermarked photos, gallery photos, and database records.
- **Delete a whole record**: deletes the in-app original photo, the watermark file, and the database record, and tries to delete the photos this record published to the system gallery.
- **Delete a project**: deletes the in-app project, records, and private files, but does not delete system gallery photos or backups already exported.
- **Save again**: republishes the watermarked photo to the Android system gallery.

Record details show the thumbnail, full-screen image, file size, original-photo retention status, time, location, and engineering fields. Project records and All records both support edit mode and batch actions.

## Backup and restore

Entry point: **Settings → Backup & restore**

### Create a backup

- Select a single project or multiple projects;
- Choose whether to include the app-private original photos;
- Blank projects can be backed up too;
- If photos are still processing, the app blocks the backup and asks you to retry later;
- If photos failed processing, the app will not continue by default — you must explicitly choose "Back up completed records only";
- A single project produces a project ZIP that restores independently; multiple projects produce one outer bundle in which every project remains an independent project ZIP.

Each project ZIP contains the project metadata, the project watermark settings, the project lifecycle and pinned state, the per-project naming templates, the completed watermarked JPEGs, a UTF-8 BOM CSV, and a JSON manifest; it also contains the private originals when you choose to include them. Project ZIP schema v5 keeps recording the backup snapshot time and the number of failed records explicitly skipped, and preserves lifecycle and pinned state precisely. The multi-project outer bundle only organizes these project ZIPs, and its schema v1 is unchanged.

### Restore

- Project ZIPs support the current schema v5 and the older v1/v2/v3/v4; these compatible versions do not refer to the multi-project outer bundle; a restored legacy project ZIP has an empty template list, an active lifecycle, and is not pinned;
- Restores photo numbers, capture times, engineering fields, location, watermark settings, original photo SHA-256, plus the lifecycle and pinned state of schema v5;
- v3 additionally restores the project description and the original creation time;
- The archive structure and SHA-256 values are verified before restoring; schema v5 also strictly validates the lifecycle and pinned fields;
- The project stays hidden during the restore; projects, records, and templates are bound by the same restore-ownership constraint and only appear after a successful commit;
- The restore result summarizes the counts of every status; if it contains archived projects you can jump straight to the archive list;
- A failed restore rolls back the database contents, staged files, and already-planned target files;
- When restore ownership or the template set is internally inconsistent, the UI shows a generic restore failure and never exposes internal state;
- After the app exits abnormally, the next launch finishes the committed cleanup or rolls back an incomplete restore;
- Restored photos are not written to the system gallery automatically; publish them with "Save again".

An ordinary share ZIP generated by the record editing page is not a project backup and cannot be used to restore.

## Diagnostics and feedback

Entry point: **Settings → Diagnostics and feedback**

Diagnostics generates a local ZIP that makes troubleshooting easier. The diagnostics bundle currently contains the app version, build number, system version, system language, plus allow-listed backup, restore, and delete outcomes with counts and durations.

Privacy boundaries:

- Diagnostic records stay on the device and are never uploaded automatically;
- They are kept for at most 7 days with a 2 MB cap per event file (this retention policy is the Android implementation; the HarmonyOS native version currently keeps the most recent 200 events);
- No photos, project names, project descriptions, work content, photographers, or notes;
- No location coordinates, addresses, EXIF, photo numbers, file names, file paths, or SHA-256 values;
- No raw exception text or stack traces;
- Diagnostic events cover backup, restore, and delete outcomes (without paths or project content);
- The diagnostics ZIP is only handed to the Android system share sheet after you explicitly confirm.

## Storage locations and uninstall impact

| Data | Default location / behavior | After uninstall |
| --- | --- | --- |
| Project and record database | App-private directory | Deleted |
| Private original photos | App-private directory | Deleted |
| Private watermark files and processing intermediates | App-private directory | Deleted |
| Watermarked gallery photos | `Pictures/SiteMark` | Usually kept |
| Local export/backup ZIPs not copied out | App-private documents directory | Deleted |
| Backups shared or copied elsewhere | The location you chose | Unaffected by uninstalling SiteMark |

"Settings → Storage" reports SiteMark's in-app database, original photos, watermarked photos, export files, and other documents; it does not include the system gallery's usage.

## Privacy and permissions

| Permission | Purpose |
| --- | --- |
| `ACCESS_COARSE_LOCATION`, `ACCESS_FINE_LOCATION` | Optional foreground location; used only when you request it, and declining does not block taking photos |
| `POST_NOTIFICATIONS` | Android 13+ notifications for finished background processing |
| `WAKE_LOCK`, `RECEIVE_BOOT_COMPLETED`, `FOREGROUND_SERVICE` | WorkManager local background processing, retries, and resume |
| `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_LOCAL_NETWORK` | Optional NAS sync (WebDAV/SFTP/SMB); only used to reach the NAS server you configure after enabling the feature. Network state backs the Wi-Fi-only gate; Android 17 LAN NAS declares and runtime-requests the local-network permission |

The released APK does not request:

- `CAMERA`;
- `ACCESS_BACKGROUND_LOCATION`;
- `READ_MEDIA_IMAGES` or the legacy broad storage permission.

Camera permission is held by the external system camera app; SiteMark provides the capture destination through a temporary URI grant. See the [privacy policy](PRIVACY.md) and [security policy](SECURITY.md) for more.

## Current limitations

- The downloadable stable version supports Android 12 and later only; the HarmonyOS NEXT native version is a Pre-release unsigned HAP and is not on any app store yet; the iOS version is fully adapted but has no signed release yet (waiting on an Apple Developer account), so no installable package exists;
- No third-party cloud sync, multi-user collaboration, or importing from the device gallery; NAS sync only targets the server you host yourself;
- The watermark is not a free-drag template;
- Background task timing is still subject to Android and vendor scheduling policies; on iOS, background catch-up is scheduled opportunistically by the system and is not guaranteed to run right after a capture;
- SHA-256 is for local consistency checks and does not represent forensic identification, trusted timestamps, or third-party evidence;
- Compatibility with more vendor cameras still needs feedback from real devices.

## Technical architecture

| Layer | Technology | Responsibility |
| --- | --- | --- |
| App & UI | Flutter, Material 3, Riverpod, GoRouter | Chinese/English UI, theming, navigation, forms, project and record interactions |
| Data | Drift, SQLite | Projects, settings, capture records, per-project templates, status transitions, filters, and database migrations |
| Background work | Kotlin, WorkManager, Dart background isolate | Persistent processing queue, failure retries, launch and restart resume |
| Android integration | Kotlin, Pigeon, Intent, ContentProvider, LocationManager, MediaStore | System camera, optional foreground location, image checks, and gallery publishing |
| iOS integration | Swift, Pigeon, BGTaskScheduler, PHPhotoLibrary | System camera bridge, optional foreground location, image checks, gallery publishing/deletion, opportunistic background catch-up |
| Image & archive | Rust, flutter_rust_bridge | EXIF orientation, full-resolution watermarking, SHA-256, CSV/JSON/ZIP, and backup verification |

The HarmonyOS NEXT native line uses Stage + ArkTS + ArkUI, RelationalStore, Preferences, CameraPicker, and PhotoAccessHelper, and calls the same `sitemark_core` Rust crate through a C ABI + C++ N-API. The two product lines share business semantics and the image/archive algorithms, but not the UI SDK or database files. The iOS line reuses the same Flutter UI, business logic, and Rust core; platform capabilities are provided by the in-repo Swift plugin (Pigeon + BGTaskScheduler), sharing business semantics, the database schema, and backup formats with Android — see section 10 of [Current product boundaries and overall architecture](docs/current-product-architecture.md).

Current maintained product and technical notes:

- [Current product boundaries and overall architecture](docs/current-product-architecture.md)
- [Capture, background processing, and photo storage lifecycle](docs/capture-processing-storage.md)
- [Projects, records, watermarks, and settings](docs/record-watermark-settings.md)
- [Key technical decision records](docs/decision-records.md)
- [Release checklist](docs/release-checklist.md)

`docs/superpowers/` keeps early designs, implementation plans, and review records for historical traceability; they do not describe the current version's behavior.

## Quality baseline

The release gates for the current version include:

- Full Flutter unit and widget tests;
- Rust unit and integration tests;
- `flutter analyze`;
- Rust fmt and Clippy;
- Android plugin unit tests plus Debug/Release APK builds;
- APK package name, version, minSdk, targetSdk, and forbidden-permission checks.

When HarmonyOS native code is involved, the checks additionally cover the HarmonyOS manifest's minimal permission set and dual-ABI configuration, and run Rust Clippy/tests for the `ohos-native` feature separately. ArkTS tests and HAP packaging need the DevEco Studio SDK and are currently verified in a local DevEco environment.

Official packages are built and signed by GitHub Actions triggered by version tags. `v1.0.18` is set as Latest; the HarmonyOS native version remains an unsigned debug-build HAP until the AGC certificate materials are available. Downloads and verification should always follow the actual assets on the corresponding GitHub Release.

## Local build

Verified environment: Flutter 3.44.6, JDK 17, Android SDK 37 (compileSdk / targetSdk 37), NDK 28.2.13676358, and stable Rust. The HarmonyOS native line additionally needs DevEco Studio (with the HarmonyOS SDK).

```bash
flutter pub get
flutter analyze
flutter test
cargo fmt --manifest-path rust/Cargo.toml --check
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path rust/Cargo.toml
flutter build apk --debug
```

HarmonyOS native line (requires DevEco Studio):

```powershell
pwsh -File ./tool/ohos-native/build-rust.ps1              # required on first use of a new worktree
pwsh -File ./tool/ohos-native/build-hap.ps1 -SkipRust -RunTests   # ArkTS tests + unsigned HAP
pwsh -File ./tool/ohos-native/run-host-tests.ps1          # host contract gates
```

Production releases need `android/key.properties` and the matching keystore. Signing files and passwords are never committed to the repository.

## Contributing

Bug reproductions, Android vendor camera compatibility results, privacy reviews, and engineering-record workflow suggestions are welcome. Before starting, read the [contributing guide](CONTRIBUTING.md), the [security policy](SECURITY.md), and the [third-party notices](THIRD_PARTY_NOTICES.md).

## License

[Apache License 2.0](LICENSE)
