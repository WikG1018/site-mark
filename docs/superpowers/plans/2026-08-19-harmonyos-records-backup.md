# HarmonyOS Records and Backup Probe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. User has already chosen **inline execution** (no subagents). Steps use checkbox (`- [ ]`) syntax.

**Goal:** 在已能进拍摄表单的全量 HAP 上，走通「全部记录空列表 → 设置/数据与备份 → 备份项目到 `saveArchive` 失败路径」；应用不得崩溃，不得宣称备份已导出或相册 ACL 已通。

**Architecture:** 不改记录页 / 备份页的产品状态机，不在页面写 `if (ohos)`。`AllCapturesScreen` 已挂 `/records`。备份入口是设置 → `backupAndRestore` → 选项目 → `exportProjects` → `archiveSaveService.saveArchive`。宿主 `inspectImage` / `saveArchive` 仍 `throw new Error('ohos_not_ready')`。本计划先探测：空记录页必须能开；备份必须停在可理解 SnackBar（`backupSaveFailed` / `backupGeneratedNotSaved`），不得红屏。只有 dump 证明页面打不开或调用把应用打崩时才改桥。

**Tech Stack:** 当前已装未签名 HAP、hdc `127.0.0.1:5555`、Drift、Riverpod、GoRouter、`sitemark.system.ohos`。

**Predecessor:** [2026-08-19-harmonyos-capture-path.md](2026-08-19-harmonyos-capture-path.md) 已推 `origin/ohos` `9d6f4af`。本计划从已有 `Task13Demo` 接着做。

## Global Constraints

- 不降 `sdk: ^3.12.2`，不改 `version: 1.0.8+23`。
- 不改 `ci.yml` / `release.yml` / `android/`，不合 `main`。
- 不要 page-level `if (ohos)` 发布/相册/备份。
- 宿主 `inspectImage` / `saveArchive` 保持 `ohos_not_ready`，除非探测证明 Dart 未捕获导致崩溃。
- 无真机：不得宣称备份 zip 已进系统文件、相册 ACL、`ohos-arm64`。
- 不提交一次性脚本、HAP、`ohos/entry/libs/`、社区 lock。
- 用户可见失败文案不暴露原始异常。
- 提交只在用户再说「提交」时做。

---

### Task 17: 打开全部记录空列表

**Files:**
- Review: `lib/features/capture/all_captures_screen.dart`、`lib/navigation/root_navigation_scaffold.dart`（`/records`）
- Evidence: `tool/ohos/review/sitemark_layout_task17_records.json`

**Interfaces:**
- Consumes: 当前已装 HAP + `Task13Demo`（0 张照片）
- Produces: 「全部记录」dump。允许空列表文案；必须不是审查壳。

- [ ] **Step 1: 拉前台**

```powershell
$hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
& $hdc -t 127.0.0.1:5555 shell "aa start -a EntryAbility -b io.github.wikg1018.sitemark"
```

- [x] **Step 2: 点底部「全部记录」**

历史坐标约 `[442,2396][814,2606]` 中心 `628,2501`，以本次 dump 为准。

- [ ] **Step 3: dump 记录页**

成功：标题是全部记录；列表空或「暂无记录」类文案；应用仍 FOREGROUND。截图 `sitemark_task17_records.jpeg`。

---

### Task 18: 打开数据与备份并选项目

**Files:**
- Review: `lib/features/settings/global_settings_screen.dart`、`lib/features/settings/sections/backup_restore_section_screen.dart`、`lib/features/settings/sections/project_backup_selection_screen.dart`
- Evidence: `tool/ohos/review/sitemark_layout_task18_backup.json`

**Interfaces:**
- Consumes: 设置分组 `settings-group-data` / `backup-restore-menu` → `/settings/backup-restore` → `/settings/backup-restore/backup`
- Produces: 备份选项目页 dump，列表含 `Task13Demo`。

- [ ] **Step 1: 回设置 Tab，点「数据与备份」再点「备份项目」**
- [ ] **Step 2: dump 选项目页，勾选 `Task13Demo`**

不要点恢复。恢复会走 `file_picker`，本任务不宣称导入。

---

### Task 19: 探测 `saveArchive` 失败路径

**Files:**
- Review only unless crash: `OhosSystemHost.ets` `case 'inspectImage' / 'saveArchive'`、`project_backup_selection_screen.dart` `_saveBackup`
- Evidence: `tool/ohos/review/sitemark_layout_task19_after_backup.json`、hilog 摘录

**Interfaces:**
- Consumes: `_startBackup` → `exportProjects` → `saveArchive(path)`
- Produces: SnackBar `backupSaveFailed` 或 `backupGeneratedNotSaved`；应用仍在备份页。

- [x] **Step 1: 点开始备份**

若弹出「是否包含原图」，点排除原图（`exclude-private-originals`）。

- [ ] **Step 2: dump 结果**

成功标准（满足即可，**不要宣称备份已保存**）：
1. 进程仍在，不是桌面。
2. 结果是进度框后 SnackBar，或明确失败文案。
3. hilog 可有 `ohos_not_ready` / `saveArchive`。

- [ ] **Step 3: 崩溃才改代码**

若红屏：只在现有 `OhosSystemApi._invoke` 或 `_describeBackupError` 收口，用户文案仍走 `backupSaveFailed`。不要实现真 `saveArchive` picker（那是后续产品任务）。

---

### Task 20: 官方测试 + 刷新差异表

**Files:**
- Modify: `tool/ohos/full_product_gap.md`、`tool/ohos/product_hap_review.md`、`README.md`
- Test: `test/platform/ohos_platform_services_test.dart`（保持无插件 → `ohos_not_ready`）

- [x] **Step 1: 官方 Flutter 跑相关测试**（`+43` 通过）

```powershell
$dart = 'C:\Users\Administrator\Development\flutter\bin\cache\dart-sdk\bin\dart.exe'
$snap = 'C:\Users\Administrator\Development\flutter\bin\cache\flutter_tools.snapshot'
$pkg = 'C:\Users\Administrator\Development\flutter\packages\flutter_tools\.dart_tool\package_config.json'
Set-Location 'C:\Users\Administrator\Documents\Codex\2026-07-15\new-chat\.worktrees\ohos'
& $dart --packages=$pkg $snap test test/platform/ohos_platform_services_test.dart test/data/app_database_test.dart --reporter expanded
```

- [x] **Step 2: 按实测改 README / gap / review**

全部记录可写「空列表可开」。备份必须写「已探测，saveArchive 未就绪 / 未导出」。

- [x] **Step 3: Commit 只在用户再说提交时做**（用户已说「提交」：只推四份文档，不合 `main`）

---

## 实测结果（2026-08-19，SiteMarkPhone602）

- Task 17：全部记录空列表可开（「暂无记录」/「还没有拍摄记录」）。
- Task 18：设置 → 备份与恢复 → 备份项目，列表含 `Task13Demo`。
- Task 19：不包含原图后 `files/exports` 被创建且无 zip；`saveArchive` 仍 `ohos_not_ready`；应用未崩。
- Task 20：官方测试 `ohos_platform_services_test` + `app_database_test` `+43` 通过。产品代码未改。

---

## Out of scope

- 实现 `saveArchive` / `inspectImage` picker
- 恢复导入、相册 ACL、拍成照片
- 合进 `main`

## Self-review

1. 规格里的备份/相册全量对等不在本计划。
2. 无 page-level `if (ohos)`。
3. 路由 `/records`、`/settings/backup-restore/backup` 与现码一致。
