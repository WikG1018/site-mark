# HarmonyOS album save dialog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. User has already chosen **inline execution** (no subagents). Steps use checkbox (`- [ ]`) syntax.

**Goal:** 拍成后发布 JPEG 走鸿蒙系统相册保存对话框（`PhotoAccessHelper.showAssetsCreationDialog`），体验对齐安卓写入系统相册；无 ACL 时不再把“保存到相册”落到普通文档选择器。

**Architecture:** 不改 Pigeon / 页面。`publishJpeg` 仍返回 `contentUri`。ACL 仍优先 `createAsset`。无 ACL 或 ACL 失败时弹出系统相册保存对话框，把沙箱 JPEG 写进返回的媒体 URI。用户取消对话框视为发布失败。对话框 API 失败才回退沙箱 `files/published`。无相册 dump 不得写系统相册已通。不声称 ACL。

**Tech Stack:** 官方 Flutter 3.44.6 / Dart 3.12.2 跑测试；`@kit.MediaLibraryKit` `showAssetsCreationDialog` + `PhotoCreationConfig`；现有 `sitemark.system.ohos`。

**Predecessor:** [2026-08-19-harmonyos-capture-sandbox-copy.md](2026-08-19-harmonyos-capture-sandbox-copy.md) 已推 `81fdceb`。相机媒体 URI 可拷进 `files/originals`。发布无 ACL 仍走 `DocumentViewPicker.save`。

## Global Constraints

- 不降 `sdk: ^3.12.2`，不改 `version: 1.0.8+23`。
- 不改 `ci.yml` / `release.yml` / `android/` / `pigeons/`，不合 `main`。
- 不要 page-level `if (ohos)`。
- 不实现 ACL 证明、`ohos-arm64`、定位 dump。
- 无相册 dump 不得写系统相册已通。
- 不提交一次性脚本、HAP、`ohos/entry/libs/`、社区 lock、`flutter_*.log`、`tool/ohos/review/`。
- 官方测试搅 lock 后必须 `git checkout -- pubspec.lock`。
- 用户已说做到体验对齐为止：本块绿灯后只 add 产品/文档并 `git push origin ohos`。

## File map

- Modify: `test/platform/ohos_platform_services_test.dart` — `publishJpeg` / 定位解码契约。
- Modify: `packages/sitemark_system_api/ohos/src/main/ets/components/plugin/OhosSystemHost.ets` — 相册保存对话框；删除媒体 URI 不再当 POSIX unlink。
- Docs: `README.md`、`tool/ohos/full_product_gap.md`、`tool/ohos/product_hap_review.md`。

---

### Task 41: Dart publishJpeg / location decode contract

**Files:**
- Modify: `test/platform/ohos_platform_services_test.dart`

- [x] **Step 1: Write the tests**

- `publishJpeg` 通道返回 `file://media/...` + `supersededUris` → `PublishJpegOutcome`
- `requestCurrentLocation` 通道返回 `outcome: 0` + 经纬度 → `LocationOutcome.precise`

- [ ] **Step 2: Run official test**

解码器已存在，预期 GREEN。这不是相册 dump。

---

### Task 42: Native album save dialog

**Files:**
- Modify: `packages/sitemark_system_api/ohos/src/main/ets/components/plugin/OhosSystemHost.ets`
- Docs: `README.md`、`tool/ohos/full_product_gap.md`、`tool/ohos/product_hap_review.md`

- [x] **Step 1: Replace JPEG document picker**

`writePublishedJpeg`：ACL `createAsset` 失败或无 ACL → `showAssetsCreationDialog`。

- `srcFileUris`：沙箱 JPEG 的 `fileUri.getUriFromPath`
- `PhotoCreationConfig`：`title`、`fileNameExtension: 'jpg'`、`photoType: IMAGE`
- 返回媒体 URI 后 `copyFileToUri`
- 空结果 / 用户取消 → 抛错，不要静默沙箱
- 对话框 API 失败 → 沙箱 `files/published/{captureId}.jpg`
- zip 备份仍走 Document picker，不改

`deletePublishedImage`：应用沙箱 `file://` 才 `unlink`；媒体 URI 走 `MediaAssetChangeRequest.deleteAssets`，失败则跳过。不要把 `file://media/` 当 POSIX 路径删。

删除未使用的 `CameraPickerSaveProfile`。

- [x] **Step 2: Honest docs. No album dump.**

- [x] **Step 3: Official tests; restore `pubspec.lock`; commit + push `origin/ohos`**
