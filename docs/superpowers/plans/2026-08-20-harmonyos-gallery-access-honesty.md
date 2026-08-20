# HarmonyOS gallery access honesty Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. User has already chosen **inline execution** (no subagents). Steps use checkbox (`- [ ]`) syntax.

**Goal:** 无 ACL 成功证明时 `detectGalleryAccess` 返回 `pickerFallback`，存储页和拍摄页显示「未进入系统相册」；媒体权限不得当成 ACL。发布路径仍可尝试 `createAsset`，但不因此把探测标成 `acl`。无相册 dump 不得写系统相册已通。

**Architecture:** 探测与发布解耦。ETS `detectGalleryAccess` 默认 `pickerFallback`（当前无 ACL 持久化证明）。`writePublishedJpeg` 在 READ+WRITE 媒体权限下仍先 `writeAclJpeg`，失败再相册对话框/沙箱。Dart 存储页已有横幅；拍摄页补同类 hint。通道 mock 测 UI，不声称 `createAsset` 已通。

**Predecessor:** [2026-08-20-harmonyos-jpeg-gps-fallback.md](2026-08-20-harmonyos-jpeg-gps-fallback.md) 已推。

## Global Constraints

- 不降 SDK，不合 `main`，不改 CI/Android/Pigeon。
- 官方测试搅 lock 后必须 `git checkout -- pubspec.lock`。
- 绿灯后只 add 产品/文档并 `git push origin ohos`。
- 用户已要求直接做到功能体验对齐；本刀 inline TDD，不用子代理。
- 无相册 dump 不得写系统相册已通。

## File map

- Modify: `packages/sitemark_system_api/ohos/src/main/ets/components/plugin/OhosSystemHost.ets`
- Modify: `lib/features/capture/capture_form_screen.dart`
- Modify: `test/features/settings/sections/storage_section_screen_test.dart`
- Modify: `test/features/capture/capture_form_screen_test.dart`
- Modify: `test/platform/ohos_platform_services_test.dart`
- Docs: `README.md`、`tool/ohos/full_product_gap.md`、`tool/ohos/product_hap_review.md`

---

### Task 48: Honest gallery access probe

- [x] **Step 1: Failing tests** — 通道 `pickerFallback` 时存储页/拍摄页出现 `gallery-picker-fallback-hint`；`acl` 不出现；通道缺失不出现；`OhosSystemApi.detectGalleryAccess` 解码字符串
- [x] **Step 2: ETS 探测默认 `pickerFallback`；发布仍按媒体权限尝试 `createAsset`；拍摄页补横幅**
- [x] **Step 3: Official tests; honest docs; commit + push `origin/ohos`**
