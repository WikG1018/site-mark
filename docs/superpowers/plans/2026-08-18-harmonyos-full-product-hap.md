# HarmonyOS Full Product HAP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. User has already chosen **inline execution in this session** (no subagents). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在长期 `ohos` 分支上，用社区 Flutter-OH **3.44.9-dev（Dart 3.12.2）** 把官方全量入口 `lib/main.dart` 编进产品 HAP，装到 DevEco 模拟器 `SiteMarkPhone602`，走通隐私门 → 真实 SiteMark 项目列表；不降 `sdk: ^3.12.2`，不把审查壳当发布物。

**Architecture:** `main` 继续官方 Flutter + Android APK。`ohos` 只换宿主与平台实现：产品 `ohos/` HAP、`OhosPlatformServices`、`InAppSerialBackgroundWorkClient`、`FilePrivacyConsentStore`、Rust 失败时 `DegradedImagePipeline` / `DegradedProjectBundlePipeline`。页面、`CaptureWorkflow`、`CaptureProcessor` 不写 `if (ohos)` 发图/相册分支。社区 Flutter 只存在仓库外 `C:\Users\Administrator\Development\flutter-ohos-3.44`。

**Tech Stack:** CPF-Flutter `oh-3.44.9-dev` @ `d75a04f9`、Dart 3.12.2、HarmonyOS NEXT SDK（DevEco 6.1.1.290）、hdc、Drift、Riverpod、GoRouter、现有 `sitemark_system_api` ohos HAR。

**Spec:** [2026-08-17-harmonyos-next-adaptation-design.md](../specs/2026-08-17-harmonyos-next-adaptation-design.md)

**Predecessor:** Tasks 0–5 见 [2026-08-17-harmonyos-next-adaptation.md](2026-08-17-harmonyos-next-adaptation.md)。本计划从「审查壳已过模拟器、全量 Dart 尚未进 HAP」接着做。

## Global Constraints

- 不改 `pubspec.yaml` 的 `sdk: ^3.12.2`，不改 `version: 1.0.8+23`（除非用户另说）。
- 不改 `.github/workflows/ci.yml`、`release.yml`、`android/`。
- 不把 `ohos` 合进 `main`。社区 Flutter / overlay / HAP 构建产物不进 `main`。
- 发布物入口必须是 `lib/main.dart --dart-define=SITEMARK_OHOS=true`。`lib/ohos_review_main.dart` 只留作审查对照。
- 不在页面 / `CaptureWorkflow` / `CaptureProcessor` 写 `if (ohos)` 发图或相册分支。
- 发布日记只按 `captureId`。`publishJpeg` 先落新图、原生不删相册行。
- 引擎保持 **degraded**，直到 Rust 编出 `ohos-arm64`。模拟器不得宣称相机 / ACL / 相册替换 / 水印对等。
- 第三方插件（`workmanager`、`flutter_local_notifications`、`dynamic_color`、`file_picker`、`share_plus`、`package_info_plus`）缺 ohos 实现时第一期可关或 no-op，必须写入差异表，不得 silently 假装还在。
- 无真机：验收在 AVD `SiteMarkPhone602`（HarmonyOS-6.0.2 phone_all_x86 API 22，hdc `127.0.0.1:15555`）。
- 3.44.9-dev 是 canary；DevEco 6.1.1 / API 22 可能不够新。若 `build hap` 因 API 不匹配失败，记录实测错误，不得偷偷降官方 SDK。
- 官方测试只允许用 `C:\Users\Administrator\Development\flutter`（3.44.6 / Dart 3.12.2）。不要用社区 3.27.4 跑产品 `pubspec.yaml`。
- 不提交 `ohos/local.properties`、`ohos/**/build/`、`ohos/**/oh_modules/`、HAP 二进制、`.superpowers/`。
- 用户可见失败文案不暴露原始异常或平台字符串。

---

## File map

| 路径 | 职责 |
|---|---|
| `C:\Users\Administrator\Development\flutter-ohos-3.44` | 仓库外社区 Flutter；编 HAP。保持 `flutter-ohos` 3.27.4 不动 |
| `ohos/local.properties`（gitignore） | `flutter.sdk` 指向 3.44 |
| `tool/ohos/build-product-hap.ps1` | 全量入口脚本：3.44 + `lib/main.dart`，默认不加 overlay |
| `lib/main.dart` | 全量入口；ohos 上通知/内存压力可降级，但入口不变 |
| `lib/app.dart` | 已接 `FilePrivacyConsentStore` / `OhosPlatformServices` / 降级管线 / 串行队列 |
| `lib/platform/ohos_capability.dart` | `isOhosBuild` = `SITEMARK_OHOS` 或 `Platform.operatingSystem == 'ohos'` |
| `lib/platform/local_notification_service.dart` | Android 插件；ohos 缺实现时改为 no-op 或守卫初始化 |
| `tool/ohos/full_product_gap.md` | 差异表：能进的 UI vs 不能宣称的能力 |
| `tool/ohos/product_hap_review.md` | 补全量入口审查结果 |
| `README.md`（本分支顶部） | 标明这是鸿蒙适配分支 |

不改：`pigeons/`、Android Kotlin、`CaptureProcessor` 状态机、`main` CI。

---

### Task 6: 让 Flutter-OH 3.44 能跑 `flutter` / `build hap`

**Files:**
- Use (do not commit): `C:\Users\Administrator\Development\flutter-ohos-3.44\bin\cache\flutter_tools.snapshot`
- Use: `C:\Users\Administrator\Development\flutter-ohos-3.44\bin\cache\dart-sdk\bin\dart.exe`
- Use: `C:\Users\Administrator\Development\flutter-ohos-3.44\packages\flutter_tools\bin\flutter_tools.dart`
- Do not modify: SiteMark `pubspec.yaml` SDK floor

**Interfaces:**
- Consumes: 已下载的 Dart 3.12.2；`packages/flutter_tools` 已 `pub upgrade`
- Produces: 可用的 `flutter_tools.snapshot` 或等价 `dart compile` 产物；`dart --packages=... flutter_tools.snapshot --version` 能打印 Flutter 版本

- [ ] **Step 1: 确认 3.44 Dart 版本，不要用错 SDK**

Run from PowerShell:

```powershell
& 'C:\Users\Administrator\Development\flutter-ohos-3.44\bin\cache\dart-sdk\bin\dart.exe' --version
Get-Content 'C:\Users\Administrator\Development\flutter-ohos-3.44\bin\cache\dart-sdk\version'
Get-Content 'C:\Users\Administrator\Development\flutter-ohos-3.44\bin\cache\engine.ohos.stamp'
```

Expected: Dart **3.12.2**。`engine.ohos.stamp` = `e1982331c8e4253dfff7d2bfbde680a59876fb84`。若不是，停下来，不要用 3.27.4 继续。

- [ ] **Step 2: 用 Dart 3.12 子命令编 JIT 快照（旧 `--snapshot=` 全局参数已失效）**

```powershell
$dest = 'C:\Users\Administrator\Development\flutter-ohos-3.44'
$dart = Join-Path $dest 'bin\cache\dart-sdk\bin\dart.exe'
$snap = Join-Path $dest 'bin\cache\flutter_tools.snapshot'
$pkgs = Join-Path $dest 'packages\flutter_tools\.dart_tool\package_config.json'
$script = Join-Path $dest 'packages\flutter_tools\bin\flutter_tools.dart'
& $dart compile jit-snapshot -o $snap --packages=$pkgs $script
Write-Host ("SNAP_EXIT=" + $LASTEXITCODE)
Test-Path $snap
```

Expected: `SNAP_EXIT=0` 且 snapshot 文件存在。

若 `compile jit-snapshot` 不存在，依次试：

```powershell
& $dart compile kernel -o $snap --packages=$pkgs $script
```

以及官方 VM 直调（仅当 `dart help` 仍列出 vm 标志时）：

```powershell
& $dart vm --verbosity=error --snapshot=$snap --snapshot-kind=app-jit --packages=$pkgs --no-enable-mirrors $script
```

禁止再跑会报 `Could not find a command named flutter_tools.snapshot` 的：

```text
dart --snapshot=...\flutter_tools.snapshot ...
```

- [ ] **Step 3: 用 snapshot 打出版本，确认工具能启动**

```powershell
& $dart --packages=$pkgs $snap --suppress-analytics --version
```

Expected: 打印接近 `Flutter 3.44.x` / channel oh-3.44.9-dev，且进程结束（不要用 `flutter.bat --version`，它会在 Windows 上挂起等 stamp）。

- [ ] **Step 4: 本任务不改 SiteMark 源码，无需 commit**

工具链在仓库外。若必须改 `shared.bat`，只改 `flutter-ohos-3.44` 本机文件，不要提交进 SiteMark。

---

### Task 7: 官方 `pub get` + 缺插件降级（不降 SDK）

**Files:**
- Modify only if compile 失败且无法用条件导入：`lib/main.dart`、`lib/platform/local_notification_service.dart`、`lib/app.dart`（动态取色 / 通知初始化守卫）
- Create: `tool/ohos/full_product_gap.md`
- Modify: `tool/ohos/build-product-hap.ps1`（改指向 3.44，默认 `--target lib/main.dart`，去掉 overlay）
- Modify (gitignore): `ohos/local.properties` `flutter.sdk=C:\\Users\\Administrator\\Development\\flutter-ohos-3.44`
- Do not modify: `pubspec.yaml` `sdk:` 行、`ci.yml`

**Interfaces:**
- Consumes: Task 6 的 snapshot
- Produces: 官方树 `flutter pub get` 成功；构建脚本不再套 community-overlay；差异表列出每个缺 ohos 实现的插件及第一期行为

- [ ] **Step 1: 把 HAP 宿主和构建脚本指到 3.44**

`ohos/local.properties`（不提交）：

```properties
hwsdk.dir=C:\\Program Files\\Huawei\\DevEco Studio\\sdk
flutter.sdk=C:\\Users\\Administrator\\Development\\flutter-ohos-3.44
flutter.versionName=1.0.8
flutter.versionCode=23
```

`tool/ohos/build-product-hap.ps1` 关键改动（完整文件按此语义改，不要留 overlay）：

```powershell
$ErrorActionPreference = 'Stop'
$app = 'C:\Users\Administrator\Documents\Codex\2026-07-15\new-chat\.worktrees\ohos'
$dest = 'C:\Users\Administrator\Development\flutter-ohos-3.44'
$dart = Join-Path $dest 'bin\cache\dart-sdk\bin\dart.exe'
$snap = Join-Path $dest 'bin\cache\flutter_tools.snapshot'
$pkgs = Join-Path $dest 'packages\flutter_tools\.dart_tool\package_config.json'
$hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
# ... 与现脚本相同的 OHOS / DevEco 环境变量 ...
Set-Location $app
& $dart --packages=$pkgs $snap --suppress-analytics pub get
if ($LASTEXITCODE -ne 0) { throw "pub get failed: $LASTEXITCODE" }
& $dart --packages=$pkgs $snap --suppress-analytics build hap --debug --target-platform ohos-x64 --target lib/main.dart --dart-define=SITEMARK_OHOS=true
```

- [ ] **Step 2: 在产品树跑官方 `pub get`（无 overlay）**

```powershell
Set-Location 'C:\Users\Administrator\Documents\Codex\2026-07-15\new-chat\.worktrees\ohos'
$dest = 'C:\Users\Administrator\Development\flutter-ohos-3.44'
$dart = Join-Path $dest 'bin\cache\dart-sdk\bin\dart.exe'
$snap = Join-Path $dest 'bin\cache\flutter_tools.snapshot'
$pkgs = Join-Path $dest 'packages\flutter_tools\.dart_tool\package_config.json'
$env:OHOS_FLUTTER_ROOT = $dest
$env:FLUTTER_ROOT = $dest
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
& $dart --packages=$pkgs $snap --suppress-analytics pub get
```

Expected: exit 0。`pubspec.yaml` 仍是 `sdk: ^3.12.2`。

- [ ] **Step 3: 若编译卡在缺 ohos 实现的插件，做最小守卫，禁止改页面发图分支**

`lib/main.dart` 允许的最小改动示例（仅当 `LocalNotificationService` 在 ohos 初始化抛错或编不过时）：

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSize = 40;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 32 * 1024 * 1024;
  final notificationService = LocalNotificationService();
  final memoryPressureService = PlatformMemoryPressureService();
  await bootstrapForeground(
    startUi: () => runApp(
      MyApp(
        completionNotificationService: notificationService,
        memoryPressureService: memoryPressureService,
      ),
    ),
    waitForFirstFrame: () => WidgetsBinding.instance.endOfFrame,
    initializeRuntime: initializeForegroundRust,
  );
}
```

入口签名保持不变。若必须禁用动态取色 / 本地通知，只在现有 provider / 服务初始化处加 `isOhosBuild` 守卫，并写进差异表。禁止在 `project_list_screen.dart` / `capture_form_screen.dart` / `CaptureWorkflow` 加相册分支。

- [ ] **Step 4: 写差异表**

Create `tool/ohos/full_product_gap.md`，至少包含这些行（按实测改 Status）：

```markdown
# 全量鸿蒙 HAP 与 Android v1.0.8 差异

| 能力 | Android v1.0.8 | 本 HAP 第一期 | 宣称限制 |
| --- | --- | --- | --- |
| 项目列表 / 记录 / 设置 UI | 全量 Dart | 目标：同一套 `lib/main.dart` | 模拟器 UI 不等于厂商相机对等 |
| 隐私同意 | SharedPreferences / 内存 | `FilePrivacyConsentStore` | 已接 |
| 系统相机 | 厂商相机 Intent | `OhosPlatformServices` | 模拟器未证明 |
| 相册发布 | MediaStore + journal | ACL + picker 托底 | 无 ACL / 无真机不得宣称对等 |
| 水印 / 备份 ZIP | Rust `sitemark_core` | `Degraded*` 当 `rustInitFailed` | engine_status=degraded |
| WorkManager | 有 | `InAppSerialBackgroundWorkClient` | 进程被杀后不保证续跑 |
| 本地通知 | `flutter_local_notifications` | 缺实现则 no-op | 必须写进本表 |
| 动态取色 | `dynamic_color` | 缺实现则关 | 必须写进本表 |
| 签名 release | Play / GitHub APK | 未做 | 不能当应用市场包 |
```

- [ ] **Step 5: Commit（与 Task 8 产物一起或本步单独）**

```bash
git add tool/ohos/build-product-hap.ps1 tool/ohos/full_product_gap.md
git commit -m "feat(ohos): point product HAP build at Flutter-OH 3.44 and lib/main.dart"
```

只在 `ohos` 分支提交。不要 push 到 `main`。

---

### Task 8: 编全量 HAP、装模拟器、走通产品主路径

**Files:**
- Use: `tool/ohos/build-product-hap.ps1`
- Modify: `tool/ohos/product_hap_review.md`
- Create: `tool/ohos/review/sitemark_layout_full_home.json`（dumpLayout）
- Do not claim: 相机 / ACL / `ohos-arm64`

**Interfaces:**
- Consumes: Task 7 能 `pub get` 的官方树
- Produces: `ohos/entry/build/default/outputs/default/entry-default-unsigned.hap`；模拟器上包名 `io.github.wikg1018.sitemark` 显示真实 SiteMark UI（项目列表或隐私门后的产品页），不是「鸿蒙审查壳已启动」

- [ ] **Step 1: 确认模拟器与空壳包**

```powershell
$hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
& $hdc list targets
& $hdc -t 127.0.0.1:15555 shell aa force-stop com.sitemark.sitemark_ohos_empty
```

Expected: `127.0.0.1:15555` 在线。必须先停空壳，否则 uitest 会点到旧窗口。

- [ ] **Step 2: 编并安装全量 HAP**

```powershell
powershell -File tool/ohos/build-product-hap.ps1
```

Expected: 出现 `HAP_EXISTS=True`。`BUILD_EXIT` 可能因未签名为 1，但 unsigned HAP 必须存在且 `INSTALL_EXIT=0`。启动：

```powershell
& $hdc -t 127.0.0.1:15555 shell aa start -a EntryAbility -b io.github.wikg1018.sitemark
```

- [ ] **Step 3: 走隐私门，确认不是审查壳**

用 `uitest dumpLayout` / `uiInput click`。同意后布局必须出现产品文案（例如项目 / 设置 / SiteMark 首页），**禁止**再出现「鸿蒙审查壳已启动」。

把 dump 存到 `tool/ohos/review/sitemark_layout_full_home.json`。在 `product_hap_review.md` 追加「全量 `lib/main.dart`」一节，写清：入口、bundle、是否过隐私门、引擎仍 degraded、未测相机 ACL。

- [ ] **Step 4: 官方测试仍绿**

```powershell
$official = 'C:\Users\Administrator\Development\flutter'
$dart = Join-Path $official 'bin\cache\dart-sdk\bin\dart.exe'
$snap = Join-Path $official 'bin\cache\flutter_tools.snapshot'
$pkgs = Join-Path $official 'packages\flutter_tools\.dart_tool\package_config.json'
Set-Location 'C:\Users\Administrator\Documents\Codex\2026-07-15\new-chat\.worktrees\ohos'
& $dart --packages=$pkgs $snap --suppress-analytics test
```

Expected: 全绿。失败则修测试或实现，不得改 `ci.yml` 来躲。

- [ ] **Step 5: Commit 审查记录与脚本（无 HAP 二进制）**

```bash
git add tool/ohos/product_hap_review.md tool/ohos/review/sitemark_layout_full_home.json tool/ohos/full_product_gap.md
git commit -m "docs(ohos): record full lib/main.dart emulator review"
```

---

### Task 9: 分支对外说明保持诚实

**Files:**
- Modify if needed: `README.md` 顶部状态表、`tool/ohos/engine_status.md`、`NEXT_AGENT_PROMPT.md`
- Do not modify: `main` README（本工作树就是 `ohos`；不要切去改 `main`）

**Interfaces:**
- Consumes: Task 8 实测
- Produces: GitHub `ohos` 分支打开时第一屏能看出「鸿蒙适配分支 + 全量 Dart HAP 进度 + 仍非应用市场上架包」

- [ ] **Step 1: 按实测更新 README 状态表**

把「未完成」改成与 Task 8 一致：若全量 UI 已进模拟器，写「模拟器已跑 `lib/main.dart`；未签名、引擎 degraded、无真机对等」。

- [ ] **Step 2: 确认 `engine_status.md` 仍是 `degraded`，除非 Rust ohos 真的编过**

- [ ] **Step 3: Commit**

```bash
git add README.md tool/ohos/engine_status.md NEXT_AGENT_PROMPT.md
git commit -m "docs(ohos): refresh branch status after full product HAP"
```

推送只去 `origin/ohos`，且仅在用户再说「推上去」时执行。

---

## Out of scope（本计划做完仍不能声称）

- AGC / 应用市场签名 `flutter build hap --release`
- 真机相机、定位、`READ/WRITE_IMAGEVIDEO` ACL 批准
- Rust `ohos-arm64` 水印与 Android 像素级对等
- 把 `ohos` 合进 `main` 或改 Android CI
- 删除 `android/` 或把仓库改成「只剩鸿蒙」

## Self-review

1. Spec 覆盖：宿主、双 SDK、不降官方 SDK、不写页面 `if (ohos)`、degraded 引擎、模拟器验收、差异表 —— 分别在 Task 6–9。
2. 无 TBD /「类似 Task N」。
3. 入口名固定为 `lib/main.dart`；channel 仍是 `sitemark.system.ohos`；包名仍是 `io.github.wikg1018.sitemark`。
