# SiteMark 工程印记 Design

## Product

SiteMark is an Android 12+ engineering-record camera. It contains no ads,
analytics, account system, cloud service, or Google Play Services dependency.
Users create a project, prepare a capture batch, invoke the device maker's
camera, and receive a full-resolution photo with a deterministic engineering
watermark.

The first release is local-only and bilingual (Simplified Chinese and English).
It does not support gallery imports, PDF reports, free-form template editing,
iOS, or team collaboration.

## Capture flow

1. Select a project and enter location within the project, work content,
   photographer, and optional notes.
2. Request foreground location in context. Approximate, denied, and timeout
   results do not block capture and are recorded explicitly.
3. Persist a pending capture record, then invoke the system camera with a
   writable content URI.
4. Recover the pending target after process recreation if the camera app caused
   Flutter to be killed.
5. Preserve the original privately, render the watermarked image in Rust, and
   publish the result to `Pictures/SiteMark` through MediaStore.
6. Allow descriptive fields to be corrected and the same published image to be
   replaced. Capture time, location result, and original hash remain immutable.

## Architecture

- Flutter owns UI, localization, navigation, workflow state, and Drift/SQLite.
- Kotlin owns system-camera intent handling, process-death recovery, Android
  LocationManager access, format normalization, and MediaStore operations.
- Rust receives paths and structured requests over flutter_rust_bridge. It owns
  EXIF orientation, watermark rendering, SHA-256 verification, and ZIP/CSV
  export. Full images never cross FFI as Dart byte arrays.

The capture state machine is `pendingCamera -> captured -> rendering -> ready`
or `failed`. Recovery runs at startup and removes cancelled or empty targets.

## Watermark and export

The default template is a bottom-left translucent information card. It includes
the on-site marker, project, work location, work content, photographer, photo
number, local timestamp and offset, address when available, coordinates, and
accuracy. Project settings may change left/right placement, opacity, accent
color, logo, and field visibility but cannot freely drag fields.

Rendered output is full-resolution sRGB JPEG at quality 92. The ZIP export
contains watermarked photos, UTF-8-BOM CSV, and a versioned manifest. Originals
are optional. The full original SHA-256 is stored in the database and CSV.

The hash is traceability metadata, not a claim of forensic tamper resistance.

## Distribution

The repository is `WikG1018/site-mark`, the application ID is
`io.github.wikg1018.sitemark`, and the license is Apache-2.0. Release builds do
not request INTERNET, CAMERA, background location, or broad media permissions.
Tagged releases publish signed arm64 and universal APKs plus SHA-256 files.

