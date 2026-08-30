# SiteMark Agent 执行入口

> 把本文件交给负责后续实现的 Agent 作为默认入口。  
> 它描述**当前仓库的事实、边界和工作方式**，不是某一版本的任务清单。

## 0. 仓库结构：单分支、双产品线

仓库自 2026-08-28 起回到**单分支**演进：`main` 同时承载 Android 稳定线（Flutter）与 HarmonyOS NEXT **原生**实现（Stage + ArkTS + ArkUI，位于 `ohos-native/`，不使用 Flutter 鸿蒙适配层）。原 `ohos-native` 开发分支已并回 `main` 并删除；接到任务时：

- **事实源顺序：** [`ohos-native/README.md`](ohos-native/README.md) → [`ohos-native/docs/deltas.md`](ohos-native/docs/deltas.md)（平台差异与转正条件）→ 最新一篇 `ohos-native/docs/verification-*.md`。与本文件冲突时以上述文档和代码为准。
- **构建与门禁（本地 DevEco）：** 公共 CI runner 没有 DevEco/HarmonyOS SDK，ArkTS 编译、全量测试和 HAP 构建**只能在本机完成**：
  1. `pwsh -File ./tool/ohos-native/build-rust.ps1`（新工作树首次必须；生成 `arm64-v8a` / `x86_64` 原生库）
  2. `pwsh -File ./tool/ohos-native/build-hap.ps1 -SkipRust -RunTests`（ArkTS 全量测试 + debug unsigned HAP）
  3. `pwsh -File ./tool/ohos-native/run-host-tests.ps1`（数据库契约、返回接线等主机门禁）
- **防假绿：** ArkTS 测试报告必须通过 `verify-test-result.Tests.ps1` 校验；缺失、畸形或失败数非零的汇总一律视为门禁失败，不得只看测试进程退出码。
- **CI 覆盖边界：** GitHub Actions 只跑主机门禁 + Dart/Rust 回归，**不编译 HAP**。每个触碰鸿蒙代码的 PR 必须按模板附本地 `build-hap.ps1 -RunTests` 的证据，否则无法确认 ArkTS 可编译。
- **设备结论红线：** `hdc list targets` 为 `[Empty]` 时不存在任何真机/模拟器验收。视觉走查、CameraPicker、相册交互、RDB 恢复和性能结论只能来自真实设备；不得用模拟器、单元测试或 debug 探针冒充设备结论。
- **原生标识：** 包名 `io.github.wikg1018.sitemark.native`；目标 SDK HarmonyOS 6.1.1 / API 24（兼容 API 17）；版本号见 `ohos-native/AppScope/app.json5`（`versionName` / `versionCode`）。

## 1. 产品与仓库现状

| 项 | 当前值 |
| --- | --- |
| 产品 | SiteMark（工程印记）：离线优先的工程水印相机（Android 稳定 + HarmonyOS NEXT 原生开发中） |
| 仓库 | https://github.com/WikG1018/site-mark |
| 应用 ID | Android `io.github.wikg1018.sitemark`；鸿蒙原生 `io.github.wikg1018.sitemark.native` |
| 默认基础分支 | `main`（唯一开发分支，Android 与鸿蒙原生同线演进；见第 0 节） |
| 当前版本 | 鸿蒙原生见 `ohos-native/AppScope/app.json5`（`1.0.6`）；Android 见 `pubspec.yaml`（`1.0.13+28`） |
| 平台 | Android 12+（API 31+）稳定发布；HarmonyOS NEXT（ArkTS 原生）验证中；iOS 适配进行中（Phase 0–2b 已合入，下一步 Phase 3，交接见 `docs/superpowers/handoffs/2026-08-30-ios-adaptation-handoff.md`） |
| 数据库 | 鸿蒙 RDB 契约测试见 `tool/test_ohos_capture_database_contract*`；Android Drift schema 见 `lib/data/app_database.dart` |
| 语言 | 简体中文 + English；用户可见文案必须双语同步 |

**默认起点：** 以远端 `main` 的最新提交为准，不要假设本文件中的版本号永远正确——先读 `pubspec.yaml` 和 `git log origin/main -5`。

历史阶段性计划保留在 `docs/superpowers/`，只供追溯；**当前行为**以：

1. `docs/current-product-architecture.md`
2. `docs/decision-records.md`
3. `docs/release-checklist.md`
4. 仓库现有代码与测试

为准。

## 2. 事实源优先级

发生冲突时按以下顺序处理：

1. 用户在**当前会话**中的明确新指令  
2. 已批准且与本任务对应的设计规格（`docs/superpowers/specs/` 中用户点名的那份）  
3. 对应实施计划（`docs/superpowers/plans/`）  
4. 本入口文件  
5. 仓库现有实现与旧版文档  

不得静默改变已锁定的产品边界。若计划会导致数据丢失、安全回退、无法编译或 Android 上不可行，必须暂停并给出证据和最小修订方案。

## 3. 不得突破的产品与安全边界

这些决策已写入 `docs/decision-records.md`，默认视为硬约束：

- **系统/厂商相机**：通过 `ACTION_IMAGE_CAPTURE`；不申请 `CAMERA`，不内置相机 SDK。  
- **无网络发布面**：发布 APK 不申请 `INTERNET` / `ACCESS_NETWORK_STATE`；无账号、广告、分析、云同步、远程 API。  
- **定位**：仅前台、可拒绝；不申请后台定位。优先原图 EXIF GPS。  
- **存储**：原图与中间文件在应用私有目录；水印成片经 MediaStore 到 `Pictures/SiteMark`。不申请广泛媒体权限。  
- **后台处理**：全分辨率串行队列（WorkManager）；幂等、可恢复；强行停止后需用户再打开应用。  
- **图像核心**：Rust + flutter_rust_bridge；跨 FFI 只传路径与结构化参数。  
- **SQLite 为状态事实源**：Drift/SQLite；schema 变更必须可迁移且不丢用户数据。  
- **不做**：iOS、图库导入、自由拖拽水印、多人协作、云备份。

## 4. 工程约定

### 代码与生成物

- 不手工编辑 Drift（`*.g.dart`）、Pigeon 或 flutter_rust_bridge 生成文件；改源定义后重新生成并提交结果。  
- 用户可见字符串同时更新中英文（`lib/l10n/app_strings.dart`）。  
- 用户可见错误**禁止**拼接 `error.toString()` 或底层路径；使用分类码 + 友好文案（参考 `describeImportError`、`describeProjectRestoreError`、`CaptureFailureCode`）。  
- 诊断事件（`lib/diagnostics/`）不得包含工程内容、照片路径、位置或可识别项目名称。

### 动效

任何自定义动画的时长与曲线只能来自 `lib/motion.dart` 的 `AppMotion`（见 `CONTRIBUTING.md`）。需要新 token 时先扩展 `AppMotion`，不要在业务文件里写死 `Duration` / `Cubic`。

### 测试与验证

- 改产品行为前先写失败的聚焦测试（TDD）。  
- 本地至少跑与改动相关的测试；完整门禁对齐 `docs/release-checklist.md` 第二节。  
- 常用命令（Windows 上 `flutter`/`dart` 以本机 PATH 或 `android/local.properties` 中的 SDK 为准）：

```text
dart format --output=none --set-exit-if-changed lib test pigeons packages/sitemark_system_api/lib
flutter analyze
flutter test
cargo fmt --manifest-path rust/Cargo.toml -- --check
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path rust/Cargo.toml
```

- **格式化版本陷阱（硬约定）：** CI 固定 Flutter `3.44.6`（其 Dart SDK 内置 dart_style `3.1.8`），本机常见的 Flutter `3.44.9` 使用 dart_style `3.1.12`，格式化结果与 CI **不同**（record 字面量换行、文件末尾换行），曾多次导致格式门禁失败。提交任何 Dart 改动前，必须直接调用 Flutter `3.44.6` SDK 目录中的 `bin/dart format`；`dart pub global activate dart_style 3.1.8` 不会替换当前 SDK 的 `dart format`，不能作为版本锁定手段。若无法取得对应 SDK，则让 CI 执行格式校验，不要用不同版本自动重写后直接提交。
- CI 当前跑 `flutter test`，**不**默认跑 `integration_test/`；改导航/拍摄主路径时仍应本地或 emulator 跑相关集成测试。  
- 真机结论不得用模拟器或单元测试冒充；未完成的真机项必须写明。

### Git 与 PR

- 从最新 `main` 开专题分支；一个 PR 一个主题。  
- 提交信息说明**为什么**；推送前看 `git status` 与 diff，不要 `git add -A` 吞入无关改动。  
- 默认不合并 PR、不打正式 Release、不 force-push `main`、不改写他人历史。  
- 不提交签名密钥、`key.properties`、真实工程照片、精确真实坐标或客户项目名。

### 明确不要做的“优化”

- 不要批量把 `Theme.of(context)` 错误提升成自引用局部变量。  
- 不要给非 const 的 `BorderRadius.circular` 等工厂构造函数强加 `const`（以当前 Flutter SDK 为准）。  
- 不要在未跑 `dart analyze` / 相关测试的情况下做大范围机械重构。

## 5. 架构速览（改代码前先定位）

| 层 | 位置 | 职责 |
| --- | --- | --- |
| UI / 导航 | `lib/features/`、`lib/navigation/`、`lib/app.dart` | 页面、根 Dock、路由 |
| 数据 | `lib/data/` | Drift、查询、迁移 |
| 工作流 | `lib/workflow/` | 拍摄队列、备份/恢复/删除、导入导出 |
| 后台 | `lib/background/` | WorkManager 调度 |
| 平台桥 | `packages/sitemark_system_api/`、`pigeons/` | 相机、定位、MediaStore、SAF |
| 图像 / 归档核心 | `rust/`、`lib/src/rust/` | 水印、哈希、ZIP |
| 诊断 | `lib/diagnostics/` | 本地诊断事件与导出包 |
| 测试 | `test/`、`integration_test/` | 单元/组件；集成需设备或 emulator |

大文件与高风险路径（改前必读现有测试）：

- `lib/workflow/project_bundle_service.dart`、`project_import_service.dart`、`project_deletion_service.dart`
- `lib/workflow/capture_processor.dart`、`capture_workflow.dart`
- `lib/data/app_database.dart`
- `lib/features/projects/project_detail_screen.dart`

## 6. 接到任务后的标准流程

1. 读本文件（含第 0 节）+ 用户点名的 spec/plan（若有）+ 相关现有代码/测试。  
2. `git status -sb`、当前分支、与 `origin/ohos-native` 的关系；工作区有不明改动则先停。  
3. 用简短消息说明：理解的目标、将改的文件、验证方式；无冲突则直接开干。  
4. 红—绿测试 → 最小实现 → analyze + 相关测试 → 审查 diff → 提交 → 推送/更新 PR。  
5. 阻塞时报告：复现命令、完整错误、已验证事实、已尝试方案、推荐的最小选择。

## 7. 发布与维护（背景）

- 发布步骤与自动化门禁：`docs/release-checklist.md`。  
- **`v1.0.13` 是 Latest**（全屏查看器单指拖动修复随本版发布）；`native-v1.0.6` 为当前鸿蒙原生发布（未签名 HAP）。后续发版按清单完成拍照/后台与备份恢复**真机**回归，并覆盖有代表性的厂商相机（小米/OPPO/vivo/三星/Pixel 等）。
- **iOS 第三条产品线：** Phase 0–2b 已合入 `main`（PR #119–#122）。接替 Agent 从 [`docs/superpowers/handoffs/2026-08-30-ios-adaptation-handoff.md`](docs/superpowers/handoffs/2026-08-30-ios-adaptation-handoff.md) 开工，下一步是 Phase 3（Dart 接线 / BGTaskScheduler / 诊断页与 l10n）。Phase 4（TestFlight）在用户提供 Apple Developer 账号之前不启动。  
- Agent **默认不**创建 GitHub Release、不上传签名密钥、不在未授权时合并 `main`。

## 8. 历史文档怎么用

| 路径 | 用途 |
| --- | --- |
| `docs/superpowers/specs/*` | 某次功能的产品设计（点名任务时必读对应文件） |
| `docs/superpowers/plans/*` | 某次功能的任务拆解（可能已完成；对照代码判断是否过时） |
| `docs/verification-*.md` | 历史版本验收记录 |
| `NEXT_AGENT_PROMPT.md`（本文件） | **常驻** Agent 入口；随产品边界变化更新，不绑死单一里程碑 |

若发现本文件与 `docs/current-product-architecture.md` 或 `decision-records.md` 冲突，以架构/决策文档和代码为准，并在同一 PR 中修正本文件。

## 9. 立即开始

1. 确认 `ohos-native` 分支与 `ohos-native/AppScope/app.json5` 版本；读第 0 节的事实源。  
2. 阅读用户当前任务与相关 spec/plan。  
3. 建立简短任务清单并开始第一个可验证步骤。  
4. 除第 2 节与第 3 节的阻塞条件外，自主推进到可审查的 PR 状态。
