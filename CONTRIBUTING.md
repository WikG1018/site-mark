# Contributing to SiteMark

Thank you for helping improve SiteMark.

1. Open an issue describing the behavior or defect before a large change.
2. Keep the Android release manifest free of INTERNET, CAMERA, background
   location, broad storage, advertising, and analytics permissions/dependencies.
3. Add a failing focused test before changing product behavior.
4. Run Flutter formatting, analysis and tests, then Rust formatting, Clippy and
   tests before opening a pull request.
5. Do not commit signing keys, `key.properties`, precise real-world test
   locations, customer project names, or private photos.
6. Update both Chinese and English strings when adding user-visible copy.

## Motion consistency

Any custom animation in `lib/` must take its duration and curve exclusively
from the `AppMotion` tokens in `lib/motion.dart` (`short4`/`medium2`/
`medium4`/`long2` and `emphasized`/`emphasizedDecelerate`/
`emphasizedAccelerate`/`standard`). Do not introduce hard-coded durations,
`Cubic` values, or ad-hoc curves outside that file; extend `AppMotion` first
if a new token is genuinely needed.

By submitting a contribution, you agree that it is licensed under Apache-2.0.
