# HarmonyOS capture-form degraded watermark hint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. User has already chosen **inline execution** (no subagents). Steps use checkbox (`- [ ]`) syntax.

**Goal:** 拍摄页在 `imagePipelineProvider.isDegraded` 时显示与存储页/拍摄详情相同的「降级水印引擎」提示；非降级不显示。无拍成 dump 不得写水印已对等 Android 像素。

**Architecture:** 复用已有 `imagePipelineProvider` 与 `AppStrings.watermarkEngineDegraded`。`CaptureFormScreen` 把 `ref.watch(imagePipelineProvider).isDegraded` 传给 `_CaptureFormBody`，在相册 fallback 横幅旁画 `Key('watermark-engine-degraded')`。测试通过 `MyApp(imagePipeline: DegradedImagePipeline())` 注入，不改宿主默认 pipeline。

**Predecessor:** [2026-08-20-harmonyos-gallery-access-honesty.md](2026-08-20-harmonyos-gallery-access-honesty.md) 已推。

## Global Constraints

- 不降 SDK，不合 `main`，不改 CI/Android/Pigeon。
- 官方测试搅 lock 后必须 `git checkout -- pubspec.lock`。
- 绿灯后只 add 产品/文档并 `git push origin ohos`。
- 用户已要求直接做到功能体验对齐；本刀 inline TDD，不用子代理。
- 无拍成 dump 不得写水印已对等 Android 像素。

## File map

- Modify: `lib/features/capture/capture_form_screen.dart`
- Modify: `test/features/capture/capture_form_screen_test.dart`
- Docs: `README.md`、`tool/ohos/full_product_gap.md`、`tool/ohos/product_hap_review.md`

---

### Task 49: Capture-form degraded watermark hint

- [x] **Step 1: Failing tests** — 注入 `isDegraded` pipeline 时拍摄页出现 `watermark-engine-degraded` 和「降级水印引擎」；默认 pipeline 不出现
- [x] **Step 2: `_CaptureFormBody` 增加 `showDegradedWatermark`，父组件 `ref.watch(imagePipelineProvider).isDegraded`**
- [x] **Step 3: Official `capture_form_screen_test` **19 绿**; honest docs; commit + push `origin/ohos`**
