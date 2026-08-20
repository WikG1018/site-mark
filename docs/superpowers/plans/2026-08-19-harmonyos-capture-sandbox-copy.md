# HarmonyOS camera sandbox copy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. User has already chosen **inline execution** (no subagents). Steps use checkbox (`- [ ]`) syntax.

**Goal:** 系统相机拍完后，把 `CameraPicker.resultUri`（通常是 `file://media/...`）拷进应用沙箱 `files/originals/{captureId}.jpg`，让 `CaptureWorkflow` 收到 `CAMERA_CAPTURED` 而不是把空文件当成取消。

**Architecture:** 不改 Pigeon，不改 `CaptureWorkflow` / 页面。`createCameraTarget` 仍预创建沙箱空文件。`launchCamera` **不要**把该沙箱路径当作 `PickerProfile.saveUri`（系统相机写不进应用私有目录）。成功后一律用 `fs.openSync(resultUri)` 读媒体 URI，写入沙箱目标。`file://media/` 不得经 `FileUri.path` 变成 `/media/...` 再走 POSIX `copyFile`。无拍成 dump 不得写相机已拍成。

**Tech Stack:** 官方 Flutter 3.44.6 / Dart 3.12.2 跑测试；`@kit.CameraKit` `cameraPicker.pick`；`@kit.CoreFileKit` `fileIo.openSync(uri)`；现有 `sitemark.system.ohos`。

**Predecessor:** [2026-08-19-harmonyos-open-link.md](2026-08-19-harmonyos-open-link.md) 已推 `13a5834`。相机 picker 能开，但 `files/originals` 空 → workflow 当取消。

## Global Constraints

- 不降 `sdk: ^3.12.2`，不改 `version: 1.0.8+23`。
- 不改 `ci.yml` / `release.yml` / `android/` / `pigeons/`，不合 `main`。
- 不要 page-level `if (ohos)`。
- 不实现 ACL、`ohos-arm64`、定位出坐标。
- 无拍成 dump 不得写相机已拍成。
- 不提交一次性脚本、HAP、`ohos/entry/libs/`、社区 lock、`flutter_*.log`、`tool/ohos/review/`。
- 官方测试搅 lock 后必须 `git checkout -- pubspec.lock`。
- 用户已说做到体验对齐为止：本块绿灯后只 add 产品/文档并 `git push origin ohos`。

## File map

- Modify: `test/platform/ohos_platform_services_test.dart` — `launchCamera` 解码契约。
- Modify: `packages/sitemark_system_api/ohos/src/main/ets/components/plugin/OhosSystemHost.ets` — 省略沙箱 `saveUri`；媒体 URI 用 `fs.openSync(uri)` 拷进 originals。
- Docs: `README.md`、`tool/ohos/full_product_gap.md`、`tool/ohos/product_hap_review.md`。

---

### Task 39: Dart launchCamera decode contract

**Files:**
- Modify: `test/platform/ohos_platform_services_test.dart`

**Interfaces:**
- Consumes: `OhosPlatformServices.launchCamera` → `OhosSystemApi.launchCamera` → `_decodeCameraCaptureResult`
- Produces: 通道 map `{outcome, outputPath, errorMessage}` 解码为 `CameraCaptureResult`

- [x] **Step 1: Write the failing tests**

在 `ohos_platform_services_test.dart` 追加：

- `launchCamera` 通道返回 `outcome: 0` + 沙箱路径 → `CameraOutcome.captured`
- `launchCamera` 通道返回 `outcome: 1` → `CameraOutcome.cancelled`
- 缺插件仍映射 `ohos_not_ready`（已有总测，不改断言）

- [ ] **Step 2: Run official test**

解码器已存在，预期 GREEN。这不是宿主拷贝的替代证据。

---

### Task 40: Native media URI → sandbox originals

**Files:**
- Modify: `packages/sitemark_system_api/ohos/src/main/ets/components/plugin/OhosSystemHost.ets`
- Docs: `README.md`、`tool/ohos/full_product_gap.md`、`tool/ohos/product_hap_review.md`

- [x] **Step 1: Fix launchCamera + copyUriToPath**

`PickerProfile` 只设 `cameraPosition`，**省略** `saveUri`。

picker `resultCode === 0` 且 `resultUri` 非空时调用 `materializeCapture(resultUri, target)`：

- 已是沙箱目标且 `stat.size > 0`：直接 `CAMERA_CAPTURED`
- 否则 `copyUriToPath`：`file://media/`、`datashare://`、含 `/media/` 的 `file://` 一律 `fs.openSync(uri, READ_ONLY)` 读，写入 `target`
- 拷完 `hasCaptureContent(target)` 才 `CAMERA_CAPTURED`
- picker 成功但拷失败 / 空文件 → `CAMERA_FAILED`，不要 `CAMERA_CANCELLED`
- picker `resultCode !== 0` 或用户关掉 → `CAMERA_CANCELLED`

`pathFromUri` 只用于应用沙箱 `file://` POSIX 路径，不再处理媒体库 URI。

- [x] **Step 2: Honest docs. No capture dump.**

- [x] **Step 3: Official tests; restore `pubspec.lock`; commit + push `origin/ohos`**
