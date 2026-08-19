# HarmonyOS degraded restore import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. User has already chosen **inline execution** (no subagents). Steps use checkbox (`- [ ]`) syntax.

**Goal:** 让鸿蒙降级管线能读自己写出的 schema 5 单项目 zip（以及 schema 1 bundle），`ProjectRestoreFlow` / `ProjectImportService` 不再因 `readProjectArchive` / `extractArchivePhoto` 故意抛 `invalid_data:` 而失败。

**Architecture:** 不改备份页状态机，不写 page-level `if (ohos)`。恢复仍走 `FilePicker` → `projectBundleService.prepareRestore` → `images.readProjectArchive` / `extractArchivePhoto`。本轮只补 `DegradedImagePipeline` 与 `DegradedProjectBundlePipeline` 的读档/解压，对齐当前 Rust 契约：单项目 schema 1–5 可恢复；多项目 selection zip 不可恢复；bundle 走 `bundle.json` + `projects/{id}.zip`。`file_picker` 在模拟器上能否弹出不作为本轮必证项。

**Tech Stack:** 官方 Flutter 3.44.6 / Dart 3.12.2 跑测试；`package:archive` 4.0.9；`package:crypto`；社区 Flutter-OH 3.44 编 HAP；DevEco 模拟器 `SiteMarkPhone602`。

**Predecessor:** [2026-08-19-harmonyos-save-archive.md](2026-08-19-harmonyos-save-archive.md) Tasks 21–24 已推 `b4f860f`：沙箱 schema 5 zip + picker 弹出。恢复方法仍 throw。

## Global Constraints

- 不降 `sdk: ^3.12.2`，不改 `version: 1.0.8+23`。
- 不改 `ci.yml` / `release.yml` / `android/`，不合 `main`。
- 不要 page-level `if (ohos)`。
- 不实现真相机、`inspectImage`、ACL、`ohos-arm64`、原生 `pickArchive`。
- 不得宣称系统文件管理里的 zip 已能选中恢复，除非模拟器 dump 证明 `FilePicker` 真返回路径。沙箱 zip 自读自恢复可以写。
- 不提交一次性脚本、HAP、`ohos/entry/libs/`、社区 lock、`flutter_*.log`、`tool/ohos/review/`。
- 用户可见失败文案不暴露原始异常（产品层已有；本轮不改文案表）。
- 官方测试搅 lock 后必须 `git checkout -- pubspec.lock`。

## File map

- Modify: `test/platform/degraded_image_pipeline_test.dart` — 把“restore 仍 throw”改成 export→read→extract 闭环。
- Modify: `lib/platform/degraded_image_pipeline.dart` — 实现 `readProjectArchive` / `extractArchivePhoto` / `readBundle` / `extractBundleEntry`。
- Docs: `README.md`、`tool/ohos/full_product_gap.md`、`tool/ohos/product_hap_review.md`。
- 不改: `lib/features/projects/project_restore_flow.dart`、`lib/workflow/project_import_service.dart`、`pigeons/`、`android/`。

---

### Task 25: Failing restore tests

**Files:**
- Test: `test/platform/degraded_image_pipeline_test.dart`

**Interfaces:**
- Consumes: `DegradedImagePipeline.export` / `readProjectArchive` / `extractArchivePhoto`；`DegradedProjectBundlePipeline.exportBundle` / `readBundle` / `extractBundleEntry`
- Produces: 失败断言（当前仍 throw `degraded zip ... is not implemented`）

- [x] **Step 1: Replace the throw-only restore test**

删除 `restore ZIP methods still throw invalid_data:`。追加：

1. `readProjectArchive reads a schema 5 zip written by export`
2. `readProjectArchive rejects a multi-project selection zip`
3. `extractArchivePhoto writes the rendered jpeg`
4. `readBundle and extractBundleEntry restore an inner project zip`
5. `readProjectArchive rejects a missing zip with not_found:`

空项目 zip 必须可读：`schemaVersion == 5`，`projectName == 'n'`，`photos` 空，`projectLifecycleStatus == 'active'`。有照片的 zip 必须解出与源文件相同的 JPEG 字节。selection zip（`exportSelection`）必须 `invalid_data:`。缺失文件必须 `not_found:`。

- [ ] **Step 2: Run official tests and confirm RED**

```
C:\Users\Administrator\Development\flutter\bin\cache\dart-sdk\bin\dart.exe --packages=C:\Users\Administrator\Development\flutter\packages\flutter_tools\.dart_tool\package_config.json C:\Users\Administrator\Development\flutter\bin\cache\flutter_tools.snapshot test test/platform/degraded_image_pipeline_test.dart --reporter expanded
```

Expected: 新测试 FAIL，因为 `readProjectArchive` 仍 throw `degraded zip readProjectArchive is not implemented`。

- [ ] **Step 3: Restore official lock if pub get touched it**

`git checkout -- pubspec.lock`

---

### Task 26: Implement degraded read/extract

**Files:**
- Modify: `lib/platform/degraded_image_pipeline.dart`

**Interfaces:**
- Produces:
  - `Future<ProjectArchivePreview> readProjectArchive(String zipPath)`
  - `Future<ExtractedArchivePhoto> extractArchivePhoto(ExtractArchivePhotoRequest)`
  - `Future<ProjectBundlePreview> readBundle(String zipPath)`
  - `Future<void> extractBundleEntry(ExtractProjectBundleEntryRequest)`

- [x] **Step 1: Minimal implementation**

规则（对齐 `rust/src/api/image_core.rs`，本轮只覆盖降级自己写出的格式）：

- 打开 zip：文件不存在 → `not_found:open ZIP`；解码失败 → `invalid_data:open ZIP`。
- 单项目：必须有 `manifest.json`。若顶层有 `projects` 数组且没有可用的 `project_name`，视为 selection zip → `invalid_data:validate archive: Only single-project archives are restorable`。
- `schema_version` 必须是 1–5 的 int。
- `project_name` 必填非空。
- schema ≤ 4：`projectLifecycleStatus = active`，`projectIsPinned = false`。schema 5：lifecycle 必须是 `active|completed|archived`。
- `isPartial = omitted_processing_count + omitted_failed_count > 0`。
- 每张照片：`photo_number` 走 `_safePhotoNumberComponent`；`hasOriginal` = `includes_originals && original_sha256 非空`。
- `extractArchivePhoto`：先 `readProjectArchive`；按号找照片；解 `photos/{safe}.jpg` 到 `{dest}.tmp` 再 rename；若 `originalDestination != null`，解 `originals/{safe}.*`，SHA-256 必须匹配 `original_sha256`，失败删临时文件。
- bundle：必须有 `bundle.json`，`kind == sitemark-project-bundle`，`schema_version == 1`；`extractBundleEntry` 按 `archivePath` 解到 `{output}.tmp` 再 rename。

- [x] **Step 2: Re-run official tests GREEN**

同一条 `dart ... test test/platform/degraded_image_pipeline_test.dart`。Expected: PASS。然后 `git checkout -- pubspec.lock`。

---

### Task 27: Docs + optional emulator smoke

**Files:**
- Modify: `README.md`、`tool/ohos/full_product_gap.md`、`tool/ohos/product_hap_review.md`

- [x] **Step 1: 按实测改文档**

写清：降级管线可自读自恢复 schema 5 zip / schema 1 bundle。若模拟器 `FilePicker` 未弹出，只写“引擎可读沙箱 zip”，不得写“系统文件选择恢复已通”。

- [x] **Step 2: 若模拟器在线，用已有沙箱 zip 做只读核对**

官方测试已覆盖 export→read→extract 闭环（14 项全绿）。本轮不重编 HAP，不把 `FilePicker` 选系统文件写成已通。

---

### Task 28: Commit only if user later says 提交

- [x] 用户已说「提交并继续」：只 add 产品代码 + 本计划 + 审查文档，`git push origin ohos`，不合 `main`。
