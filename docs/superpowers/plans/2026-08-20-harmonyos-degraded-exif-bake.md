# HarmonyOS degraded EXIF bake Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. User has already chosen **inline execution** (no subagents). Steps use checkbox (`- [ ]`) syntax.

**Goal:** 降级 `render` 在叠水印前按 EXIF orientation 烘焙像素，与 Rust `apply_orientation` 体验一致，避免竖拍图横着叠卡片。同时删除恢复页未使用的 `FilePicker` 路径，避免鸿蒙误走非原生选文件。

**Architecture:** 不改 Pigeon、不重写 Rust crate、不声称 `ohos-arm64`。`package:image` 的 `bakeOrientation` 在 JPEG decode 后、卡片叠图前调用。无拍成 dump 不得写方向已对等 Android 像素。

**Predecessor:** [2026-08-20-harmonyos-degraded-watermark.md](2026-08-20-harmonyos-degraded-watermark.md) 已推。

## Global Constraints

- 不降 SDK，不合 `main`，不改 CI/Android/Pigeon。
- 官方测试搅 lock 后必须 `git checkout -- pubspec.lock`。
- 绿灯后只 add 产品/文档并 `git push origin ohos`。

## File map

- Modify: `lib/platform/degraded_image_pipeline.dart`
- Modify: `test/platform/degraded_image_pipeline_test.dart`
- Modify: `lib/features/projects/project_restore_flow.dart`
- Docs: `README.md`、`tool/ohos/full_product_gap.md`、`tool/ohos/product_hap_review.md`、`tool/ohos/engine_status.md`

---

### Task 45: Bake EXIF orientation before overlay

- [x] **Step 1: Failing test** — JPEG EXIF orientation 6（48×32）render 后宽高为 32×48
- [x] **Step 2: `img.bakeOrientation` after decode, before card overlay**
- [x] **Step 3: Remove unused `_pickRestoreZip` / `file_picker` import**
- [x] **Step 4: Official tests; honest docs; commit + push `origin/ohos`**
