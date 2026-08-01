# 工程印记核心稳定化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让拍摄后台处理与项目备份的成功提示和真实持久化状态一致，并建立可验证的发布门禁。

**Architecture:** 前台只等待 WorkManager 注册结果，定位和渲染继续后台化；定位完成后用幂等任务唤醒。可恢复备份统一经过预检，以同盘临时文件生成并原子提交，再通过 Android SAF 流式保存到用户选择的位置。

**Tech Stack:** Flutter/Dart、Riverpod、Drift、WorkManager、Pigeon、Kotlin、Android SAF、Rust ZIP、GitHub Actions。

## Global Constraints

- 不修改 Android 自动备份、设备迁移、`allowBackup`、`dataExtractionRules` 或相关隐私声明。
- 保持 Android 12（API 31）最低版本和系统/厂商相机方案。
- 不等待定位、Rust 渲染或 MediaStore 发布后才允许继续拍摄。
- 不在用户界面、记录或诊断包中暴露原始异常和堆栈。
- 不加入云服务、账号、网络权限或新的在线依赖。
- 所有行为变更先写失败测试，再实现最小代码并验证转绿。

---

### Task 1: 队列注册真实性与待定位任务收口

**Files:**
- Modify: `lib/workflow/capture_workflow.dart`
- Modify: `lib/workflow/capture_location_coordinator.dart`
- Modify: `lib/workflow/capture_processor.dart`
- Modify: `lib/background/capture_background_scheduler.dart`
- Modify: `lib/features/capture/capture_form_screen.dart`
- Modify: `lib/l10n/app_strings.dart`
- Test: `test/workflow/capture_workflow_test.dart`
- Test: `test/workflow/capture_location_coordinator_test.dart`
- Test: `test/workflow/capture_processor_test.dart`
- Test: `test/background/capture_background_scheduler_test.dart`
- Test: `test/widget_test.dart`

**Interfaces:**
- Produces: `CaptureWorkflowOutcome.delayed`，表示原图已安全保留但首次后台注册失败。
- Produces: `CaptureProcessResult.deferred`，表示等待定位且本次 WorkManager 任务正常结束。
- Produces: `CaptureLocationCoordinator.begin(...)` 的有限重试唤醒行为。

- [ ] 写测试：首次 `scheduler.enqueue` 未完成前 `capture()` 不返回，失败时返回 `delayed` 且记录保持 `captured`。
- [ ] 运行 `flutter test test/workflow/capture_workflow_test.dart`，确认新测试因缺少 `delayed` 行为失败。
- [ ] 实现相机返回后的首次队列注册，并加入中英文延迟处理文案。
- [ ] 写测试：待定位处理返回 `deferred`，不增加 `processingAttempts`；dispatcher 把它视为成功。
- [ ] 运行处理器和调度器测试，确认测试先红后绿。
- [ ] 写测试：定位记录已解析时仍会 enqueue；首次 enqueue 失败后按注入的短退避重试成功。
- [ ] 实现协调器有限重试和后台 dispatcher 最外层异常收口。
- [ ] 运行 Task 1 的五组聚焦测试并提交。

### Task 2: 可恢复项目导出统一到备份预检

**Files:**
- Modify: `lib/features/projects/project_detail_screen.dart`
- Modify: `lib/features/settings/sections/project_backup_selection_screen.dart`
- Modify: `lib/app.dart`
- Modify: `lib/l10n/app_strings.dart`
- Test: `test/widget_test.dart`
- Test: `test/features/settings/sections/project_backup_selection_screen_test.dart`
- Test: `test/workflow/project_bundle_service_test.dart`

**Interfaces:**
- Produces: `ProjectBackupSelectionArguments(initialProjectIds: Set<String>)`。
- Consumes: 现有 `ProjectBackupPreflightService` 和 `ProjectBackupService.exportProjects`。

- [ ] 写导航测试：项目详情归档按钮进入备份页面并预选当前项目。
- [ ] 运行导航测试，确认仍调用旧的直接导出流程而失败。
- [ ] 删除项目详情的直接 `ProjectExportService.exportProject` 对话框，改为统一备份路由。
- [ ] 写预选、处理中阻断、失败确认和遗漏计数测试。
- [ ] 实现备份页初始选择参数并补齐中英文文案。
- [ ] 运行 Task 2 聚焦测试并提交。

### Task 3: 临时文件生成、原子提交与中断清理

**Files:**
- Modify: `lib/platform/platform_services.dart`
- Modify: `lib/workflow/project_bundle_service.dart`
- Modify: `lib/workflow/app_startup_recovery.dart`
- Modify: `lib/app.dart`
- Test: `test/workflow/project_bundle_service_test.dart`
- Test: `test/app_lifecycle_test.dart`

**Interfaces:**
- Produces: `ProjectBundlePaths.backupZipPath(String operationId)`。
- Produces: `ProjectBundleFileSystem.commitFile(source, destination)`、`deleteFile(path)` 和 `listExportStagingDirectories()`。
- Produces: `ProjectBackupService.cleanupInterruptedExports()`。

- [ ] 写测试：单项目和多项目都把 Rust 输出指向 staging 临时文件，成功后才返回正式路径。
- [ ] 写测试：导出或提交失败时删除本次临时文件且不触碰既有正式文件。
- [ ] 运行测试，确认当前直接写正式文件而失败。
- [ ] 实现唯一正式路径、同盘 staging、原子 rename 和异常清理。
- [ ] 写启动恢复测试：残留 `bundle-export-*` 目录在启动时清理，单项清理失败不阻断其他恢复。
- [ ] 实现启动清理并运行 Task 3 测试后提交。

### Task 4: Android SAF 流式保存与取消语义

**Files:**
- Modify: `pigeons/system_api.dart`
- Regenerate: `packages/sitemark_system_api/lib/src/system_api.g.dart`
- Regenerate: `packages/sitemark_system_api/android/src/main/kotlin/io/github/wikg1018/sitemark/system/SystemApi.g.kt`
- Modify: `packages/sitemark_system_api/android/src/main/kotlin/io/github/wikg1018/sitemark/system/AndroidSystemApi.kt`
- Modify: `packages/sitemark_system_api/android/src/main/kotlin/io/github/wikg1018/sitemark/system/SiteMarkSystemPlugin.kt`
- Modify: `lib/platform/platform_services.dart`
- Modify: `lib/app.dart`
- Modify: `lib/features/settings/sections/project_backup_selection_screen.dart`
- Modify: `lib/l10n/app_strings.dart`
- Test: `packages/sitemark_system_api/android/src/test/kotlin/io/github/wikg1018/sitemark/system/AndroidSystemApiTest.kt`
- Test: `packages/sitemark_system_api/android/src/test/kotlin/io/github/wikg1018/sitemark/system/SiteMarkSystemPluginTest.kt`
- Test: `test/features/settings/sections/project_backup_selection_screen_test.dart`

**Interfaces:**
- Produces: Pigeon `ArchiveSaveOutcome { saved, cancelled }` 与 `saveArchive(sourcePath, suggestedName)`。
- Produces: Dart `ArchiveSaveService.save(path)`。

- [ ] 写 Kotlin 测试：无 Activity 失败、取消返回 cancelled、成功结果把私有 ZIP 流式写入目标 URI。
- [ ] 写 Flutter 测试：只有 saved 显示完成；cancelled 保留最近 ZIP 并显示“再次保存”和“分享”。
- [ ] 运行测试，确认 API 尚不存在而失败。
- [ ] 扩展 Pigeon API并执行 `dart run pigeon --input pigeons/system_api.dart`。
- [ ] 实现 `ACTION_CREATE_DOCUMENT`、私有路径校验、I/O 线程复制和 Activity result 路由。
- [ ] 实现备份页保存/取消/再次保存/分享状态。
- [ ] 运行 Task 4 Flutter 与 Kotlin 测试并提交。

### Task 5: 稳定错误代码与用户文案

**Files:**
- Create: `lib/domain/capture_failure.dart`
- Modify: `lib/workflow/capture_workflow.dart`
- Modify: `lib/workflow/capture_processor.dart`
- Modify: `lib/features/capture/capture_form_screen.dart`
- Modify: `lib/features/capture/capture_record_card.dart`
- Modify: `lib/features/capture/capture_edit_screen.dart`
- Modify: `lib/l10n/app_strings.dart`
- Test: `test/domain/capture_failure_test.dart`
- Test: `test/workflow/capture_processor_test.dart`
- Test: `test/features/capture/capture_image_preview_test.dart`

**Interfaces:**
- Produces: `CaptureFailureCode` 的稳定持久化值和 `describeCaptureFailure(AppStrings, String?)`。

- [ ] 写测试：底层异常不进入 `failureReason` 或 UI；已知代码映射中英文可操作说明，历史未知文字降级为通用说明。
- [ ] 运行测试并确认当前原始 `error.toString()` 暴露导致失败。
- [ ] 实现错误分类、持久化代码和显示映射。
- [ ] 运行 Task 5 聚焦测试并提交。

### Task 6: CI 与发布门禁

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `.github/workflows/release.yml`
- Modify: `android/app/build.gradle.kts`
- Create: `tool/verify_release_tag.py`
- Create: `tool/test_verify_release_tag.py`
- Modify: `docs/release-checklist.md`

**Interfaces:**
- Produces: `python tool/verify_release_tag.py --tag <tag> --pubspec pubspec.yaml`。

- [ ] 写 Python 测试：标签与版本相符通过，不相符、缺版本和非法标签失败。
- [ ] 运行 Python 测试，确认脚本不存在而失败。
- [ ] 实现版本校验脚本并接入 CI/release。
- [ ] CI 增加 Dart format、Pigeon 生成漂移和 unsigned Release 构建。
- [ ] Release 增加 main 祖先校验、Rust fmt/clippy、缺签名 fail-fast、最终 APK `apksigner`/`aapt2`/ABI/禁止权限/证书一致性检查。
- [ ] 更新无版本绑定的发布清单并运行 Python 测试。
- [ ] 提交 Task 6。

### Task 7: 全量验证、审查和 PR

**Files:**
- Review: all files changed since `origin/main`

- [ ] 运行 `dart format --output=none --set-exit-if-changed lib test packages pigeons`。
- [ ] 运行 `flutter analyze` 和 `flutter test`。
- [ ] 运行 Rust fmt、Clippy 和全部 Rust 测试。
- [ ] 运行 Android `:sitemark_system_api:testDebugUnitTest`。
- [ ] 运行 `flutter build apk --debug` 和无正式签名的 `flutter build apk --release`。
- [ ] 重新生成 Pigeon 并确认 `git diff --exit-code` 无漂移。
- [ ] 审查 `git diff --check`、用户范围、错误路径和生成文件。
- [ ] 修复所有 Critical/Important 审查问题并重新跑受影响测试。
- [ ] 推送 `agent/stability-hardening`，创建面向 `main` 的 ready-for-review PR，等待 GitHub CI 全绿后再报告可合并。

