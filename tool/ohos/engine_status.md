# HarmonyOS watermark engine status

status: degraded

## Attempt

- Date: 2026-08-18
- Host: Windows
- Triple: `aarch64-unknown-linux-ohos` (also present: `armv7-unknown-linux-ohos`, `x86_64-unknown-linux-ohos`, `loongarch64-unknown-linux-ohos`)
- Flutter ABI name registered in cargokit: `ohos-arm64`
- Real-device layout compare vs Android v1.0.8: not performed

## Commands

```text
rustup target add aarch64-unknown-linux-ohos
# info: component 'rust-std' for target 'aarch64-unknown-linux-ohos' is up to date

rustc --print target-list | findstr ohos
# aarch64-unknown-linux-ohos
# armv7-unknown-linux-ohos
# loongarch64-unknown-linux-ohos
# x86_64-unknown-linux-ohos

cd rust
cargo build --release --target aarch64-unknown-linux-ohos
```

## cargo result

FAILED. Host rustc knows the OHOS target, but this machine has no OHOS NDK / clang sysroot, so the C toolchain cannot link `cdylib`.

Excerpt:

```text
error: linker `cc` not found
  |
  = note: program not found

error: could not compile `std` (lib) due to 1 previous error
```

No `librust_lib` / `libsitemark_core.so` was produced. HAP cannot package a real `ohos-arm64` watermark engine from this attempt.

## Runtime fallback

- `initializeForegroundRust()` still calls `RustLib.init()` once per isolate.
- On init failure it sets `rustInitFailed = true` in `lib/platform/ohos_capability.dart`.
- `imagePipelineProvider` switches to `DegradedImagePipeline` only when `isOhosBuild && rustInitFailed`.
- `DegradedImagePipeline.isDegraded == true`.
- `render` bakes EXIF orientation then composites a translucent field card via `dart:ui` (`NotoSansSC`, labels matching Rust `labels()`). Not `ohos-arm64` pixel-parity with Rust. No capture dump.
- ZIP `export` / `exportSelection` / `readProjectArchive` / `extractArchivePhoto` throw `ImagePipelineException` with an `invalid_data:` message. Backup/export is also degraded.

Do not claim full Android watermark parity. Task 4 may continue for capture closed-loop only with this degraded engine note.
