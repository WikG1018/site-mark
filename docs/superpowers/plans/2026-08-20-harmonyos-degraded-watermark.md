# HarmonyOS degraded watermark card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. User has already chosen **inline execution** (no subagents). Steps use checkbox (`- [ ]`) syntax.

**Goal:** 鸿蒙 degraded 引擎叠水印时画出与 Android / Rust `labels()` 同字段的半透明卡片（现场记录 · 项目 / 位置 / 内容 / 拍摄人 / 时间 / 非空的地址、坐标、备注），不再只写 `SiteMark` 四个英文字。照片编号不画。

**Architecture:** 不改 Pigeon、不重写 Rust crate、不声称 `ohos-arm64`。`DegradedImagePipeline.render` 仍在主 isolate（`InAppSerialBackgroundWorkClient`）。用 `dart:ui` Canvas / Paragraph 画中文卡片，再 `compositeImage` 到 JPEG。文案与 Rust `labels()` 对齐。`image` 包的 `arial24` 无 CJK，不得继续当产品水印。无拍成 dump 不得写水印已对等 Android 像素。

**Tech Stack:** 官方 Flutter 3.44.6 / Dart 3.12.2；`dart:ui`；现有 `package:image` 编解码。

**Predecessor:** [2026-08-20-harmonyos-album-save-dialog.md](2026-08-20-harmonyos-album-save-dialog.md) 已推 `d4ca1d3`。

## Global Constraints

- 不降 `sdk: ^3.12.2`，不改 `version: 1.0.8+23`。
- 不改 `ci.yml` / `release.yml` / `android/` / `pigeons/`，不合 `main`。
- 不要 page-level `if (ohos)`。
- 不实现 ACL 证明、`ohos-arm64`、定位 dump。
- 无拍成 dump 不得写水印已拍成对等。
- 不提交一次性脚本、HAP、`ohos/entry/libs/`、社区 lock、`flutter_*.log`、`tool/ohos/review/`。
- 官方测试搅 lock 后必须 `git checkout -- pubspec.lock`。
- 用户已说做到体验对齐为止：本块绿灯后只 add 产品/文档并 `git push origin ohos`。

## File map

- Modify: `lib/platform/degraded_image_pipeline.dart`
- Modify: `test/platform/degraded_image_pipeline_test.dart`
- Docs: `README.md`、`tool/ohos/full_product_gap.md`、`tool/ohos/product_hap_review.md`

---

### Task 43: Watermark line contract

**Files:**
- Modify: `lib/platform/degraded_image_pipeline.dart`
- Modify: `test/platform/degraded_image_pipeline_test.dart`

- [x] **Step 1: Write the failing tests**

- `degradedWatermarkLines` 中文 locale 含 `现场记录 ·` / `位置` / `内容` / `拍摄人` / `时间` / `地址` / `坐标` / `备注`
- 空的 address / coordinates / notes 不出现
- 英文 locale 用 `Site record` / `Location` / `Work` / `Photographer` / `Time` 等
- 照片编号不出现

- [x] **Step 2: Implement `degradedWatermarkLines` to match Rust `labels()`**

---

### Task 44: Canvas overlay

**Files:**
- Modify: `lib/platform/degraded_image_pipeline.dart`
- Docs as above

- [x] **Step 1: Replace `drawString('SiteMark')`**

半透明底 + 左侧 accent 条 + 多行标签。位置 `bottomLeft` / `bottomRight`。透明度 / 字号 / accent ARGB 来自 `RenderPhotoRequest`。字体 `NotoSansSC`（`rust/assets/fonts/NotoSansSC-Regular.otf`）。

- [x] **Step 2: Official tests; honest docs; commit + push `origin/ohos`**
