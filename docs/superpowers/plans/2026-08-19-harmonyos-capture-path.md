# HarmonyOS Capture Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. User has already chosen **inline execution** (no subagents). Steps use checkbox (`- [ ]`) syntax.

**Goal:** 在已能保存项目、打开设置的全量 `lib/main.dart` HAP 上，走通「进项目详情 → 打开拍摄表单 → 探测相机/定位失败路径」；应用不得崩溃，不得宣称拍成照片或 ACL / `ohos-arm64` 对等。

**Architecture:** 不改 `CaptureWorkflow` / `CaptureProcessor` 的产品状态机，不在页面写 `if (ohos)` 发图或相册分支。拍摄入口已是 `ProjectDetailScreen` FAB → `/projects/:projectId/capture` → `CaptureFormScreen`。宿主 `OhosSystemHost.launchCamera` / 定位权限已经实现；本计划先用当前 HAP 探测，只有 dump 证明表单打不开、或调用把应用打崩时才改桥/宿主。

**Tech Stack:** Flutter-OH `3.44.9-ohos`、官方 Flutter 3.44.6 / Dart 3.12.2、DevEco SDK API 24、hdc `127.0.0.1:5555`、Drift、Riverpod、GoRouter、`sitemark.system.ohos`。

**Predecessor:** [2026-08-18-harmonyos-product-runtime.md](2026-08-18-harmonyos-product-runtime.md) Tasks 10–12 已推 `origin/ohos` `e408878`。本计划从已保存项目接着做。

## Global Constraints

- 不降 `sdk: ^3.12.2`，不改 `version: 1.0.8+23`。
- 不改 `ci.yml` / `release.yml` / `android/`，不合 `main`。
- 入口仍是 `lib/main.dart --dart-define=SITEMARK_OHOS=true`。
- 引擎保持 **degraded**，直到 Rust 真的编出 `ohos-arm64`。
- 构建 HAP 必须非沙箱；hdc 必须带 `-t 127.0.0.1:5555`。
- `Want.parameters` 只用带引号键的 `Record<string, Object>`。ArkTS 禁止 index signature / `arr[i]`。
- 不提交社区 lock 涎动、`oh_modules`、HAP 二进制、`ohos/entry/libs/`、`flutter_*.log`、一次性审查脚本。
- 用户可见失败文案不暴露原始异常。
- 无真机：模拟器上相机/定位失败是预期；不得把失败路径写成「已拍成」或 Android 对等。
- 不要 page-level `if (ohos)` 发布/相册。
- `test/platform/ohos_platform_services_test.dart` 在无插件测试环境断言 `ohos_not_ready`；这不是「宿主未实现相机」。不要为了「让测试看起来已实现」去改这个断言。

---

### Task 13: 进已有项目详情

**Files:**
- Review: `lib/features/projects/project_list_screen.dart`、`lib/features/projects/project_detail_screen.dart`
- Evidence: `tool/ohos/review/sitemark_layout_task13_home.json`、`tool/ohos/review/sitemark_layout_task13_detail.json`

**Interfaces:**
- Consumes: 当前已装产品 HAP（Task 11 rebuild）。卸载会清隐私同意和项目，能不卸就不卸。
- Produces: 前台项目详情 dump，必须出现项目名和拍摄 FAB（`strings.capture`），且不是审查壳。

- [ ] **Step 1: 拉前台并确认 hdc**

```powershell
$hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
& $hdc -t 127.0.0.1:5555 shell "aa dump -a"
& $hdc -t 127.0.0.1:5555 shell "aa start -a EntryAbility -b io.github.wikg1018.sitemark"
```

Expected: `io.github.wikg1018.sitemark` / `EntryAbility` 能 start。若 Offline，先 `emulator.exe -start SiteMarkPhone602`，不要卸 HAP。

- [ ] **Step 2: dump 当前页**

`uitest dumpLayout`，把 JSON recv 到 `tool/ohos/review/sitemark_layout_task13_home.json`，用 `tool/ohos/parse-layout-nodes.ps1` 抽节点。

判断：
- 隐私门：点同意（历史坐标约 `628,2326`，以本次 dump 为准）。
- 空首页：走 Task 10 最小新建项目（名称 `Task13Demo`），不要卸装。
- 已有项目：点项目名进详情。

- [x] **Step 3: dump 项目详情**

成功条件：标题是项目名；有可点的拍摄 FAB / 「拍摄」文案；仍无审查壳文案。截图 `sitemark_task13_detail.jpeg`。

---

### Task 14: 打开拍摄表单

**Files:**
- Review: `lib/features/capture/capture_form_screen.dart`、`lib/app.dart` 路由 `/projects/:projectId/capture`
- Evidence: `tool/ohos/review/sitemark_layout_task14_form.json`

**Interfaces:**
- Consumes: Task 13 详情页 FAB `context.push('/projects/${projectId}/capture')`
- Produces: `CaptureFormScreen` dump。字段：地点 / 内容 / 拍摄人 / 备注；底部提交按钮；可选定位说明卡。

- [x] **Step 1: 点详情 FAB**

从 Task 13 dump 取拍摄按钮 bounds 中心，`uitest uiInput click x y`。

- [ ] **Step 2: dump 表单**

必须看到拍摄表单标题（`captureFormTitle`）和三个必填相关输入。若崩回桌面或只剩审查壳，记 hilog / 缺插件，本任务只修让表单能打开的那一处（path / sqlite / 定位 `load()`），不要改发图状态机。

- [ ] **Step 3: 填最小必填**

地点 / 内容 / 拍摄人各填一个短词（`工地` / `巡检` / `探测`）。不要点系统相册或发布。

---

### Task 15: 探测定位卡和拍摄提交的失败路径

**Files:**
- Review only unless crash: `packages/sitemark_system_api/ohos/src/main/ets/components/plugin/OhosSystemHost.ets`（`launchCamera`、`requestLocationPermission`）
- Review: `lib/platform/ohos_platform_services.dart`
- Modify only if 调用把 Dart 打崩或表单无法回到可理解失败：宿主返回 `cancelled`/`failed`，或 Dart 把 `PlatformException` 收成 `CaptureWorkflowOutcome.failed`
- Evidence: `tool/ohos/review/sitemark_layout_task15_after_capture.json`、hilog 摘录

**Interfaces:**
- Consumes: `CaptureFormScreen._capture` → `CaptureWorkflow.capture` → `OhosPlatformServices.launchCamera`
- Produces: 系统权限框 / 相机 Ability / 或应用内失败 SnackBar。应用仍活着。

- [ ] **Step 1: 若有定位说明卡，点「开启」一次**

允许系统权限框出现。拒绝或模拟器无定位都算探测完成。回到表单后 dump。不要把「无坐标」写成定位已通。

- [ ] **Step 2: 点底部拍摄提交**

允许出现相机权限框、`cameraPicker`、或 `ohos.want.action.imageCapture`。取消或失败后 dump。

成功标准（满足即可勾选，**不要宣称拍成**）：
1. 应用进程仍在，不是桌面。
2. 结果是权限框、相机 UI、取消回表单、或「拍摄失败」类 SnackBar 之一。
3. hilog 记下 `launchCamera` / permission / `cameraFailed` / `MissingPluginException`。

- [x] **Step 3: 崩溃才改代码**

若 Dart 未捕获异常导致红屏/退出：在现有 `OhosSystemApi._invoke` 或 workflow 失败映射里收口，用户文案仍走 `captureFailed` + `captureFailureMessage`。不要加 page-level `if (ohos)`。

若只是模拟器无相机返回 `failed`/`cancelled`：不改产品代码，只写 gap。

---

### Task 16: 官方测试 + 刷新差异表

**Files:**
- Modify: `tool/ohos/full_product_gap.md`
- Modify: `tool/ohos/product_hap_review.md`
- Modify: `README.md` 顶部状态表（已验证加上「可进拍摄表单」；未完成仍含相机/ACL）
- Test: `test/platform/ohos_platform_services_test.dart`（保持无插件 → `ohos_not_ready`）
- Test: 若改了失败映射，补/跑触及文件的官方测试

**Steps:**

- [x] **Step 1: 官方 Flutter 跑相关测试**

```powershell
$env:PATH = 'C:\Users\Administrator\Development\flutter\bin;' + $env:PATH
Set-Location 'C:\Users\Administrator\Documents\Codex\2026-07-15\new-chat\.worktrees\ohos'
flutter test test/platform/ohos_platform_services_test.dart test/platform/rust_initialization_contract_test.dart test/data/app_database_test.dart
```

Expected: PASS。不要用社区 Flutter 跑官方测试。

- [x] **Step 2: 按实测改 README / gap / review**

相机/定位行必须写「已探测，模拟器失败/未拍成」或「表单可开，宿主调用未崩」，**不能**写成已通。引擎仍 degraded。

- [x] **Step 3: Commit 只在用户再说提交时做**

用户本轮已说「提交并继续」。只 commit 计划 / README / gap / review 文档，再 `git push origin ohos`。不 add HAP、`ohos/entry/libs/`、一次性 `task13-*.ps1`。

## 2026-08-19 实测结果

- Task 13：空首页新建 `Task13Demo`，详情 dump 有标题、`0 张照片`、FAB「拍摄」。
- Task 14：打开 `CaptureFormScreen`（标题「水印内容」），填 `Gongdi` / `Xunjian` / `Tance`。
- Task 15：点「开启定位」弹出系统框「允许 SiteMark 访问你的位置？」；「本次使用允许」后定位卡消失。点「拍摄」弹出「允许访问相机？」；允许后 hilog 有 `CameraPicker::Pick` 与 `saveUri .../originals/<uuid>.jpg`。`files/originals` 为空，未见相机 UI，应用仍在表单前台。**未拍成，未改产品代码。**
- Task 16：官方 Flutter 3.44.6 / Dart 3.12.2，`ohos_platform_services_test` + `rust_initialization_contract_test` + `app_database_test` 全部通过（`+44`）。

---

## Out of scope

- 签名 release / 应用市场
- 真机相机、定位、ACL、`ohos-arm64`
- 发布到系统相册 / picker 托底产品化（代码可保持现状）
- 合进 `main`
- 把 `ohos_platform_services_test` 改成「已实现」假阳性

## Self-review

1. 规格里的相机/相册全量对等不在本计划；本计划只覆盖「表单可开 + 调用不崩」。
2. 无 TBD / 无 page-level 发图分支。
3. 路由、FAB、`launchCamera` 名称与现码一致。
