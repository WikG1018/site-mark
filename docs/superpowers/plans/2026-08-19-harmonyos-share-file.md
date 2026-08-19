# HarmonyOS native shareFile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. User has already chosen **inline execution** (no subagents). Steps use checkbox (`- [ ]`) syntax.

**Goal:** 备份/导出后点分享弹出鸿蒙系统分享面板，体验对齐安卓 `SharePlus` 分享 zip。

**Architecture:** 不改 Pigeon，不改 `pigeons/system_api.dart`。在已有 `sitemark.system.ohos` 通道上增加 `shareFile`：宿主用 `@kit.ShareKit` `systemShare.ShareController.show` 弹出系统分享面板。Dart 侧新增 `OhosShareFileService`，`app.dart` 按平台注入。不要 page-level `if (ohos)`。无模拟器分享面板 dump 不得写系统分享已通。

**Tech Stack:** 官方 Flutter 3.44.6 / Dart 3.12.2 跑测试；社区 Flutter-OH 编 HAP；`@kit.ShareKit` `systemShare`；`fileUri.getUriFromPath`；UTD `general.zip-archive` / `general.jpeg` / `general.file`。

**Predecessor:** [2026-08-19-harmonyos-inspect-image.md](2026-08-19-harmonyos-inspect-image.md) 已推 `dcd16b1`：拍成后读图走 ImageKit。鸿蒙入口分享仍是 `NoopShareFileService`。

## Global Constraints

- 不降 `sdk: ^3.12.2`，不改 `version: 1.0.8+23`。
- 不改 `ci.yml` / `release.yml` / `android/` / `pigeons/`，不合 `main`。
- 不要 page-level `if (ohos)`。
- 不实现真相机拍成、ACL、`ohos-arm64`、定位出坐标。
- 无分享面板 dump 不得写系统分享已通。
- 不提交一次性脚本、HAP、`ohos/entry/libs/`、社区 lock、`flutter_*.log`、`tool/ohos/review/`。
- 官方测试搅 lock 后必须 `git checkout -- pubspec.lock`。
- 用户已说提交并继续：本块绿灯后只 add 产品/文档并 `git push origin ohos`。

## File map

- Modify: `test/platform/ohos_platform_services_test.dart` — `shareFile` 通道契约。
- Modify: `packages/sitemark_system_api/lib/src/ohos/ohos_system_api.dart` — `shareFile()`。
- Modify: `lib/platform/ohos_platform_services.dart` — `OhosShareFileService`。
- Modify: `lib/app.dart` — `shareFileServiceProvider`。
- Modify: `packages/sitemark_system_api/ohos/src/main/ets/components/plugin/OhosSystemHost.ets` — `shareFile` + 补 ImageKit import。
- Docs: `README.md`、`tool/ohos/full_product_gap.md`、`tool/ohos/product_hap_review.md`。

---

### Task 33: Dart shareFile channel and service

**Files:**
- Modify: `test/platform/ohos_platform_services_test.dart`
- Modify: `packages/sitemark_system_api/lib/src/ohos/ohos_system_api.dart`
- Modify: `lib/platform/ohos_platform_services.dart`
- Modify: `lib/app.dart`

- [x] **Step 1: Write the failing tests**

- [x] **Step 2: Run official test to verify RED**

- [x] **Step 3: Implement Dart channel + OhosShareFileService + provider**

- [x] **Step 4: Run official test to verify GREEN**

---

### Task 34: Native ShareKit host

**Files:**
- Modify: `packages/sitemark_system_api/ohos/src/main/ets/components/plugin/OhosSystemHost.ets`
- Docs: `README.md`、`tool/ohos/full_product_gap.md`、`tool/ohos/product_hap_review.md`

- [x] **Step 1: Wire shareFile + add missing ImageKit import**

- [x] **Step 2: Honest docs. No share-panel dump.**
