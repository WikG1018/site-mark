# SiteMark 流畅度优化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完成记录列表、水印滑块、图片预览、数据监听、存储统计和数据库查询的全链路流畅度优化。

**Architecture:** 保持现有 Flutter/Riverpod/Drift 架构，通过稳定 Future/Stream、内存筛选、异步文件检查、尺寸受控图片解码和 SQLite 索引消除重复工作。每项修改均先增加能够复现重复调用或缺失索引的失败测试。

**Tech Stack:** Flutter 3.44、Dart、Riverpod、Drift/SQLite、Android/Kotlin、Rust/flutter_rust_bridge。

## Global Constraints

- 不改变现有用户功能、文案、离线边界和系统相机方案。
- 不新增运行时第三方依赖。
- 旧照片和 v4 数据库必须无损升级。
- 生产代码修改前必须先运行对应失败测试。

---

### Task 1: 稳定水印设置和页面数据源

**Files:**
- Modify: `lib/features/projects/project_watermark_settings_screen.dart`
- Modify: `lib/features/projects/project_detail_screen.dart`
- Modify: `lib/features/capture/all_captures_screen.dart`
- Create: `lib/domain/capture_summary_filter.dart`
- Test: `test/features/projects/project_watermark_settings_screen_test.dart`
- Test: `test/domain/capture_summary_filter_test.dart`
- Test: `test/features/capture/capture_filter_ui_test.dart`

**Interfaces:**
- Produces: `filterCaptureSummaries(List<CaptureSummary>, CaptureFilter)`，供两个记录页面在单一汇总流上计算显示结果。

- [x] 写失败测试：重复拖动水印滑块只调用一次项目读取。
- [x] 写失败测试：纯函数正确处理项目、年、月、日半开区间筛选，且不修改输入列表。
- [x] 写失败测试：全部记录和项目详情的筛选结果仍与现有行为一致。
- [x] 缓存项目 Future 和页面 Stream；删除嵌套的第二/第三个照片 StreamBuilder。
- [x] 运行上述测试并提交。

### Task 2: 缓存卡片媒体状态并异步检查文件

**Files:**
- Modify: `lib/features/capture/capture_record_card.dart`
- Modify: `lib/features/capture/capture_image_preview.dart`
- Modify: `lib/platform/platform_services.dart`
- Test: `test/features/capture/capture_record_card_test.dart`
- Test: `test/features/capture/capture_image_preview_test.dart`
- Test: `test/platform/platform_services_test.dart`

**Interfaces:**
- Produces: `FutureOr<bool> Function(String)` 文件存在性接口；`AppCaptureOutputPaths` 内部共享目录 Future。

- [x] 写失败测试：父组件重建不会重复读取同一照片的原图状态和输出路径。
- [x] 写失败测试：文件存在性可异步返回，加载时显示稳定占位。
- [x] 写失败测试：多个照片路径请求只解析、创建一次目录。
- [x] 将卡片和预览改为有状态缓存；仅在相关照片字段变化时失效。
- [x] 运行上述测试并提交。

### Task 3: 限制详情图片解码尺寸

**Files:**
- Modify: `lib/features/capture/capture_image_preview.dart`
- Test: `test/features/capture/capture_image_preview_test.dart`

**Interfaces:**
- Produces: 普通详情预览的 `cacheWidth` 计算函数；全屏查看仍保留原图解码。

- [x] 写失败测试：普通详情预览具有受控 `cacheWidth`，列表缩略图仍为 192，全屏图片不限制。
- [x] 根据布局宽度和 DPR 计算并限制解码宽度。
- [x] 运行测试并提交。

### Task 4: 缓存并并发计算存储占用

**Files:**
- Modify: `lib/app.dart`
- Modify: `lib/workflow/app_storage_service.dart`
- Test: `test/workflow/app_storage_service_test.dart`
- Test: `test/features/settings/global_settings_screen_test.dart`

**Interfaces:**
- Produces: 非 `autoDispose` 的 `storageUsageProvider`；固定上限的文件长度并发计算。

- [x] 写失败测试：离开并返回设置页不会自动重新统计，手动刷新仍会重新统计。
- [x] 写失败测试：多文件统计结果正确且最大并发数不超过设计上限。
- [x] 实现 Provider 缓存和有界并发读取。
- [x] 运行测试并提交。

### Task 5: 添加数据库性能索引和大数据量回归

**Files:**
- Modify: `lib/data/app_database.dart`
- Modify: `lib/data/app_database.g.dart`（由 Drift 生成）
- Modify: `test/data/app_database_migration_test.dart`
- Modify: `test/data/app_database_test.dart`

**Interfaces:**
- Produces: schema v5；`capture_records_status_idx`、`capture_records_sort_idx`、`capture_records_project_sort_idx`。

- [x] 写失败迁移测试：v4 升级后数据保留且三个索引存在。
- [x] 写失败新库测试：新建 v5 数据库立即具有三个索引。
- [x] 增加 v5 迁移和幂等建索引逻辑，运行 Drift 代码生成。
- [x] 增加 1000 条记录筛选测试并验证结果。
- [x] 运行数据库测试并提交。

### Task 6: 性能回归场景与拍照分段计时

**Files:**
- Modify: `integration_test/simple_test.dart`
- Modify: `lib/workflow/capture_workflow.dart`
- Test: `test/workflow/capture_workflow_test.dart`

**Interfaces:**
- Produces: 可注入的捕获阶段计时回调，仅记录本地阶段名称与耗时，不采集用户内容。

- [x] 写失败测试：拍照工作流依次报告目标文件、待拍记录和系统相机启动请求（调用前）三个阶段。
- [x] 实现零网络、默认关闭的本地诊断计时接口。
- [x] 增加 1000 条记录滚动、筛选、全选和详情打开的 Profile 集成场景。
- [x] 运行工作流测试；Profile 集成场景已在 API 36 模拟器受 Dart VM Service 端口权限限制阻塞，保留命令供可用真机或模拟器运行。

### Task 7: 全量验证和发布准备

**Files:**
- Modify: `docs/superpowers/plans/2026-07-19-sitemark-smoothness.md`（勾选结果）

- [x] 运行 `dart format --output=none --set-exit-if-changed lib test integration_test`。
- [x] 运行 `flutter analyze` 和 `flutter test`。
- [x] 运行 Rust fmt、clippy、单元及集成测试。
- [x] 运行 Android 单元测试并构建 debug APK。
- [ ] 在模拟器 Profile 模式运行性能场景，记录帧数据但不把模拟器绝对耗时作为真机门槛。当前 API 36 模拟器禁止 Dart VM Service 创建本地监听端口，需在真机或允许 VM Service 的模拟器补跑。
- [ ] 检查 git diff、提交完整变更，并按用户指定方式推送 PR。
