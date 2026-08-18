# HarmonyOS Product Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. User has already chosen **inline execution** (no subagents). Steps use checkbox (`- [ ]`) syntax.

**Goal:** 在已经能进真实首页的全量 `lib/main.dart` HAP 上，走通「新建项目 / 设置 / 关于」等不依赖真机相机的产品路径；缺的第三方插件改成明确 no-op 或 ohos 桥，并写进差异表。不宣称相机 / ACL / `ohos-arm64` 对等。

**Architecture:** 继续双 SDK：官方 Flutter 只跑测试；社区 Flutter-OH 3.44 只在仓库外编 HAP。页面、`CaptureWorkflow`、`CaptureProcessor` 仍不写 `if (ohos)` 发图/相册分支。插件缺口只在 `OhosPlatformServices` / `SiteMarkSystemPlugin` / 现有 no-op 守卫里补。

**Tech Stack:** Flutter-OH `3.44.9-ohos`、Dart 3.12.2、DevEco SDK API 24、hdc `127.0.0.1:5555`、Drift、Riverpod、GoRouter、`sitemark.system.ohos`。

**Predecessor:** [2026-08-18-harmonyos-full-product-hap.md](2026-08-18-harmonyos-full-product-hap.md) Tasks 6–8 已在模拟器量到首页。本计划从首页接着做。

## Global Constraints

- 不降 `sdk: ^3.12.2`，不改 `version: 1.0.8+23`。
- 不改 `ci.yml` / `release.yml` / `android/`，不合 `main`。
- 入口仍是 `lib/main.dart --dart-define=SITEMARK_OHOS=true`。
- 引擎保持 **degraded**，直到 Rust 真的编出 `ohos-arm64`。
- 构建 HAP 必须非沙箱；hdc 必须带 `-t 127.0.0.1:5555`。
- `Want.parameters` 只用带引号键的 `Record<string, Object>`。ArkTS 禁止 index signature / `arr[i]`。
- 不提交社区 lock 涎动、`oh_modules`、HAP 二进制、`flutter_*.log`。
- 用户可见失败文案不暴露原始异常。
- 无真机：不得用模拟器结论冒充相机 / ACL / 相册替换。

---

### Task 10: 走通空首页上的「新建项目」

**Files:**
- Review: `lib/features/projects/`、`lib/app.dart`
- Modify only if 缺插件导致表单无法保存：`OhosSystemHost.ets` / `SiteMarkSystemPlugin.ets`
- Evidence: `tool/ohos/review/sitemark_layout_new_project.json`、对应 jpeg

**Steps:**

- [ ] **Step 1: 确认产品仍在前台**

```powershell
hdc -t 127.0.0.1:5555 shell "aa dump -a"
```

Expected: `io.github.wikg1018.sitemark` / `EntryAbility` FOREGROUND。若 Offline，先 `emulator.exe -start SiteMarkPhone602`。

- [ ] **Step 2: dump 首页，定位「新建项目」坐标**

从 `uitest dumpLayout` 找「新建项目」bounds，点中心。不要用审查壳文案当成功条件。

- [ ] **Step 3: 填最小项目名并保存**

若弹出权限/文件选择，记入 `full_product_gap.md`，不要假装成功。

- [ ] **Step 4: dump 必须出现项目名，且仍不是审查壳**

把 dump / 截图写进 `tool/ohos/review/`。hilog 若再出 `MissingPluginException`，记下 channel + method，本任务就修这一处。

---

### Task 11: 走通「设置」和「关于」，补缺插件

**Files:**
- `lib/platform/local_notification_service.dart`
- `lib/features/settings/sections/about_section_screen.dart`
- `packages/sitemark_system_api/ohos/src/main/ets/components/plugin/SiteMarkSystemPlugin.ets`
- `tool/ohos/full_product_gap.md`

**Steps:**

- [ ] **Step 1: 点 Dock「设置」，再进「关于」**

记录缺的文案（版本号空白、分享按钮无响应、通知开关抛错）。

- [ ] **Step 2: 缺 `package_info_plus` 时**

在 `SiteMarkSystemPlugin` 增桥 `dev.fluttercommunity.plus/package_info`，返回 `1.0.8` / `23` / `io.github.wikg1018.sitemark`。不要改关于页业务分支。

- [ ] **Step 3: 缺通知插件时**

ohos 上让 `LocalNotificationService` 保持 no-op，设置页不得崩溃。写进差异表。

- [ ] **Step 4: 缺 `share_plus` 时**

第一期设置页分享可禁用或 no-op，文案友好。不要在页面写 `if (ohos)` 发图。

---

### Task 12: 官方测试 + 刷新差异表

**Files:**
- `tool/ohos/full_product_gap.md`
- `tool/ohos/product_hap_review.md`
- `README.md` 顶部状态表

**Steps:**

- [ ] **Step 1: 官方 Flutter 跑相关测试**

```text
C:\Users\Administrator\Development\flutter
flutter test test/platform/rust_initialization_contract_test.dart
```

有设置/通知改动时补聚焦测试。全量 `flutter test` 尽量跑；失败必须分类：本分支回归 vs 基线。

- [ ] **Step 2: 按实测改 README / gap / review**

只写量到的路径。引擎仍写 degraded。

- [ ] **Step 3: Commit（用户再说推）**

只 add 源码、计划、审查记录。不 add lock 涎动、HAP、`ohos/entry/libs/`、`flutter_*.log`。

```text
git commit -m "feat(ohos): walk project create and settings on emulator"
```

推送只去 `origin/ohos`，且仅在用户说「推上去」。

---

## Out of scope

- 签名 release / 应用市场
- 真机相机、定位、ACL
- Rust `ohos-arm64`
- 合进 `main`

## Self-review

1. 从已验证首页接着做，不重做 Task 6–8。
2. 缺插件只桥或 no-op，不改 Capture 状态机。
3. 模拟器成功不等于 Android 对等。
