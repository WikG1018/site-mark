# Contributing to SiteMark

Thank you for helping improve SiteMark.

1. Open an issue describing the behavior or defect before a large change.
2. Keep the Android release manifest free of CAMERA, background location,
   broad storage, advertising, and analytics permissions/dependencies.
   `INTERNET`, `ACCESS_NETWORK_STATE`, and `ACCESS_LOCAL_NETWORK` exist only
   for the opt-in NAS sync (D-023) and must stay in the release APK. Android 17
   LAN NAS also runtime-requests `ACCESS_LOCAL_NETWORK` from the settings
   screen.
3. Add a failing focused test before changing product behavior.
4. Run Flutter formatting, analysis and tests, then Rust formatting, Clippy and
   tests before opening a pull request.
5. Do not commit signing keys, `key.properties`, precise real-world test
   locations, customer project names, or private photos.
6. Update both Chinese and English strings when adding user-visible copy.

## Agent / automated contributors

If you are an automated coding agent, start with
[`NEXT_AGENT_PROMPT.md`](NEXT_AGENT_PROMPT.md). It is the standing entry point for
product boundaries, verification, and git expectations. Current behavior is
defined by `docs/current-product-architecture.md` and
`docs/decision-records.md`; historical specs live under `docs/superpowers/`.

## Motion consistency

Any custom animation in `lib/` must take its duration and curve exclusively
from the `AppMotion` tokens in `lib/motion.dart` (`short4`/`medium2`/
`medium4`/`long2` and `emphasized`/`emphasizedDecelerate`/
`emphasizedAccelerate`/`standard`). Do not introduce hard-coded durations,
`Cubic` values, or ad-hoc curves outside that file; extend `AppMotion` first
if a new token is genuinely needed.

## User-visible errors

Do not show raw `error.toString()`, file paths, or OS error codes in the UI.
Map failures to stable codes and bilingual friendly copy (see import/restore
error helpers and `CaptureFailureCode`). Diagnostic events must not include
engineering content, photo paths, locations, or project names.

By submitting a contribution, you agree that it is licensed under Apache-2.0.
