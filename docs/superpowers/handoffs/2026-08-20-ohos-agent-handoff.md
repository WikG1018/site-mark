# SiteMark 鸿蒙适配交接文档（2026-08-20）

> 交接对象：下一个负责 `ohos` 分支的 Agent（云端环境）。
> 本文档自包含：只依赖本仓库与 GitHub，不依赖任何上一台机器的本地路径。
> 事实基准：`ohos` 分支 Task 60 功能以 `git log origin/ohos -3` 为准（前序 Task 59 `ccf39ec`，2026-08-21）。

## 1. 一句话现状

HarmonyOS NEXT 原生 HAP 适配已推进到 Task 59：产品主链路（隐私门 → 项目 → 拍摄表单 → 记录 → 备份/恢复 → 设置）在鸿蒙上可跑；启动恢复四窗 Dart 侧已并行开工；入队失败 delayed 后拍摄页仍可继续拍；水印引擎处于**降级模式**；相机/相册/分享/通知/外链/文件选择等系统通道均已接线，但**没有模拟器成功 dump 的一律不得宣称已通**。无杀进程 dump，队列仍是应用内内存串行。CI 已覆盖 UI / 降级引擎 / GPS / 通道 / 拍摄工作流 / 定位协调器 / 启动恢复 / widget / lifecycle / 备份导入 / 拍摄失败引导测试。取消拍照不占下一张当日编号；pending 空文件恢复不占号；live 空 URI / materialize 无内容走 cancelled；拒绝定位仍 queued 出片；连拍当日 `001` 然后 `002`。相册保存对话框取消 / 空 destinations 回退沙箱，不把拍摄打成 failed。

## 2. 仓库与分支纪律

- 仓库：https://github.com/WikG1018/site-mark
- `main`：Android 产品主线（v1.0.8，官方 Flutter，发 APK）。**不要动。**
- `ohos`：本任务长期分支。所有提交直接 `git push origin ohos`；**禁止合回 `main`，禁止开 PR 到 main**。
- 基线：从 Android v1.0.8（`847c74b`）拉出；功能体验对齐目标即 Android v1.0.8。

### 硬红线（违反即返工）

1. 不改 `ci.yml` / `release.yml` / `android/` / `pigeons/`。`pigeons/system_api.dart` 是生成源，永不手改。`.github/workflows/ohos.yml` 是本分支自有 workflow，**可以**扩充。
2. 不降 `sdk: ^3.12.2`（见 `pubspec.yaml`）。
3. 不要 page-level `if (ohos)` 分支页面；平台差异用 provider / 服务注入表达（见第 7 节既有模式）。
4. 水印引擎保持 degraded（事实见 `tool/ohos/engine_status.md`）；不重写 Rust 水印 crate，不宣称像素对等。
5. 用户可见文案中英文同步（`lib/l10n/app_strings.dart`）。
6. TDD：先写失败测试再写实现；动大文件前先读它的现有测试。

## 3. 诚实边界（本分支的核心纪律）

「dump」= 模拟器/真机上的实际操作证据（hdc 输出、截图、日志）。**没有 dump 的能力一律不得在代码注释、文档、提交信息里宣称已通**：

| 能力 | 接线现状 | 允许的宣称口径 |
| --- | --- | --- |
| 相机拍成 | `CameraPicker` 省略沙箱 `saveUri`；`file://media/` 拷进沙箱 `files/originals` | 「已接线，无拍成 dump」 |
| 定位坐标 | ImageKit EXIF + Dart JPEG EXIF 回退（`lib/platform/jpeg_gps.dart`） | 「已接线，无坐标 dump」 |
| 系统相册 | 无 ACL 走 `showAssetsCreationDialog`；有媒体写权限仍尝试 `createAsset` | 「保存对话框已接，无相册 dump」 |
| 系统文件选择恢复 | `DocumentViewPicker.select` → 沙箱 `files/imports` | 「已接线，无 picker 成功 dump」 |
| 备份进系统文件管理 | 沙箱 zip + Document picker 弹出 | 「沙箱导出已证，picker 保存未证」 |
| 系统分享 | ShareKit `ShareController.show`（zip/jpeg/png 对应 UTD） | 「已接线，无分享面板 dump」 |
| 系统通知 | NotificationKit 基础文本 + WantAgent deep link | 「已接线，无通知 dump」 |
| 系统外链 | `startAbility` 隐式 Want | 「已接线，无浏览器 dump」 |
| 水印像素 | `DegradedImagePipeline`（dart:ui 字段卡片） | 「降级引擎，非 `ohos-arm64` 像素对等」 |
| 签名 release | 无 | 「无签名 HAP，未上架」 |

已验证过、可以写的事实（模拟器 DevEco `SiteMarkPhone602` x86_64）：隐私门 → 新建项目 → 项目详情 → 拍摄表单 → 全部记录 → 设置/关于 → 备份沙箱 `files/exports/*.zip` + Document picker 弹出。逐任务记录见 `tool/ohos/product_hap_review.md`，总账见 `tool/ohos/full_product_gap.md`。

## 4. 已落地里程碑（Tasks 0–60）

完整计划链见 `README.md` 顶部「后续实施计划」段。近期任务：

| 任务 | 主题 | 提交 | 计划文档（`docs/superpowers/plans/`） |
| --- | --- | --- | --- |
| 39–40 | 相机媒体 URI 拷沙箱 | `81fdceb` | `2026-08-19-harmonyos-capture-sandbox-copy.md` |
| 41–42 | 相册保存对话框 | `f61475b` | `2026-08-20-harmonyos-album-save-dialog.md` |
| 43–44 | 降级水印字段卡片 | `d431470` | `2026-08-20-harmonyos-degraded-watermark.md` |
| 45 | EXIF orientation 烘焙 | `47892ca` | `2026-08-20-harmonyos-degraded-exif-bake.md` |
| 46 | 应用内队列指数退避 | `0688363` | `2026-08-20-harmonyos-queue-retry.md` |
| 47 | JPEG EXIF GPS 回退 | `80a1b48` | `2026-08-20-harmonyos-jpeg-gps-fallback.md` |
| 48 | 相册探测诚实化 | `9956843` | `2026-08-20-harmonyos-gallery-access-honesty.md` |
| 49 | 拍摄页降级水印提示 | `f3f80d2` | `2026-08-20-harmonyos-capture-degraded-watermark-hint.md` |
| 50 | 动态取色诚实化 | `754afe3` | `2026-08-20-harmonyos-dynamic-color-honesty.md` |
| 51–52 | CI 扩容 + captureId 删除锁 | `3b76d90` | `2026-08-20-harmonyos-ci-and-captureid-delete.md` |
| 53 | 杀进程四窗互不阻塞 | `9328d05` | `2026-08-20-harmonyos-kill-process-four-windows.md` |
| 54 | capture_workflow 进 CI + delayed 继续拍 | `bf0cb6c` | `2026-08-20-harmonyos-capture-workflow-ci-delayed.md` |
| 55 | widget / lifecycle / 备份导入进 CI | `d742817` | `2026-08-20-harmonyos-ci-widget-lifecycle-backup.md` |
| 56 | 取消拍照不占号 + 失败引导进 CI | `6484a86` | `2026-08-20-harmonyos-cancel-no-photo-number.md` |
| 57 | 拒绝定位仍出片 + 连拍 001→002 | `7b82a42` | `2026-08-20-harmonyos-denied-location-burst-numbers.md` |
| 58 | 空相机文件不占号 + live 空内容当取消 | `2f1a058` | `2026-08-20-harmonyos-empty-camera-no-photo-number.md` |
| 59 | 相册保存取消托底沙箱，不 markFailed | `ccf39ec` | `2026-08-20-harmonyos-album-cancel-sandbox.md` |

早期任务（0–38）：系统宿主与通道、隐私同意、串行队列、HAP 工程与全量 `lib/main.dart` 编译、备份导出/读回、原生 Document picker 选档、ImageKit 读图、ShareKit、NotificationKit、startAbility 外链——链路与证据见 `README.md` 与 `tool/ohos/product_hap_review.md`。

## 5. 测试与 CI（云端 Agent 的主战场）

- CI：`.github/workflows/ohos.yml`，push 到 `ohos` 即触发；ubuntu-latest + 官方 Flutter **3.44.6**，`flutter pub get` + 指定测试子集。
- 云端跑测试就是标准命令：`flutter test <文件或目录>`。无需任何本机技巧（此前 Windows 本机的沙箱终端问题属机器特例，云端不复现）。
- 官方 Flutter 3.44.6 全绿的测试文件（Tasks 51–60 起已全部进 `ohos.yml`；Task 60 新测试在 `packages/sitemark_system_api/test/`，本刀未改 workflow）：

| 测试文件 | 计数 |
| --- | --- |
| `test/platform/degraded_image_pipeline_test.dart` | 19 绿 |
| `test/platform/ohos_background_work_client_test.dart` | 6 绿 |
| `test/platform/jpeg_gps_test.dart` | 6 绿 |
| `test/platform/ohos_platform_services_test.dart` | 33 绿（含分享取消不 throw） |
| `packages/sitemark_system_api/test/` | CI 覆盖；`gallery_store_test` 8 绿；`publish_fallback_policy_test` 4 绿；`share_cancel_policy_test` 2 绿；`capture_session_store_test` 3 绿（含空文件 `hasContent: false`） |
| `test/features/settings/sections/storage_section_screen_test.dart` | 5 绿 |
| `test/features/settings/sections/appearance_section_screen_test.dart` | 9 绿 |
| `test/features/capture/capture_form_screen_test.dart` | 20 绿（含 delayed 后仍可再拍） |
| `test/features/capture/capture_failure_guidance_test.dart` | CI 覆盖；错误只显示稳定类别 |
| `test/workflow/capture_processor_test.dart` | CI 覆盖 |
| `test/workflow/capture_workflow_test.dart` | 21 绿；入队失败 delayed；取消拍照不占下一张 `001`；pending 空文件恢复不占号；拒绝定位仍 queued 出片；连拍当日 `001` 然后 `002` |
| `test/workflow/capture_location_coordinator_test.dart` | 9 绿；无 EXIF + permissionDenied 仍 enqueue |
| `test/workflow/capture_media_service_test.dart` | CI 覆盖；含恢复同编号删除锁；日记对账走独立 `recoverPublishJournals()` |
| `test/workflow/app_startup_recovery_test.dart` | CI 覆盖；相机挂起时队列 / 日记 / 相册窗仍开工 |
| `test/background/capture_background_scheduler_test.dart` | CI 覆盖 |
| `test/widget_test.dart` | 33 绿；生产启动清理 imports 再相机恢复、项目 CRUD |
| `test/app_lifecycle_test.dart` | 9 绿；首帧后初始化后台队列，paused/hidden 委托 |
| `test/workflow/project_import_test.dart` | CI 覆盖；规格「备份导入」 |
| `test/workflow/project_export_test.dart` | CI 覆盖 |
| `test/features/settings/sections/backup_restore_section_screen_test.dart` | CI 覆盖；与 import/export 合计官方 84 绿 |
| `test/features/onboarding/privacy_consent_gate_test.dart` | CI 覆盖 |

- dart_style 版本随 Flutter 走，CI 固定 3.44.6；用别的 Flutter 版本 format 后直接提交会有格式差异风险。

## 6. 云端做不了什么（需要本地 Windows 环境）

- **模拟器/真机 dump**：需要 Windows + DevEco Studio + 模拟器。上一台机器用模拟器 `SiteMarkPhone602`（x86_64）。云端 Agent 拿不到 → 第 3 节的 dump 门控项在云端**无法推进**，只能做代码 / 测试 / 文档 / 诚实化。
- **HAP 构建**：需要 DevEco Studio + 社区 Flutter OH 3.44（gitcode `CPF-Flutter/flutter_flutter`，分支 oh-3.44.9-dev）+ 官方 Flutter 3.44.6 双 SDK。构建流程已固化在已跟踪脚本 `tool/ohos/build-product-hap.ps1`（assemble → 注入 NativeAssetsManifest → 编 sqlite → build hap → 替换 so → 校验 kernel → 安装启动），但脚本内写死了上一台机器的绝对路径，换机需替换为本地安装路径。
- `libsqlite3.so` **不在 Git 里**也不需要在：`tool/ohos/compile-ohos-sqlite3.ps1` 会从 sqlite.org 下载 amalgamation 3500200，用 DevEco 自带 OHOS NDK clang 按 `x86_64-linux-ohos` / `aarch64-linux-ohos` 重编；`replace-ohos-sqlite3.ps1` 再塞进 HAP。`ohos/entry/libs/` 只是构建中间产物。
- 社区插件版本覆盖在 `tool/ohos/community-overlay/`（两个 pubspec 覆盖文件）。
- 已知 HAP 编译风险（下次重编时优先检查）：ETS 侧 `NotificationRequest.wantAgent` 写法、`EntryAbility` 对 `sitemark_system_api` 的 import。**Task 46–59 的 Dart 侧改动尚未重编进任何 HAP**。
- Rust 水印引擎 `ohos-arm64`：本机无 OHOS NDK clang sysroot，cargo 链接失败，所以走降级管线。编译尝试记录见 `tool/ohos/engine_status.md`。

## 7. 鸿蒙侧架构速览（改代码前必读）

| 关注点 | 位置 | 说明 |
| --- | --- | --- |
| 平台判定 | `lib/platform/ohos_capability.dart` | `isOhosBuild = bool.fromEnvironment('SITEMARK_OHOS') \|\| Platform.operatingSystem == 'ohos'`；HAP 构建传 `--dart-define=SITEMARK_OHOS=true`；`rustInitFailed` 标记 rust init 失败 |
| 系统通道 | `packages/sitemark_system_api/` | Pigeon JSON 通道 `sitemark.system.ohos`；Dart 服务在 `lib/src/ohos/`，ETS 宿主 `ohos/src/main/ets/components/plugin/OhosSystemHost.ets` |
| 降级引擎 | `lib/platform/degraded_image_pipeline.dart` | `isDegraded => true`；`render` = `bakeOrientation` + `dart:ui` 半透明字段卡片（对齐 Rust `labels()`）；`export`/`readProjectArchive` 等用 `package:archive` + `crypto` 实现 schema 5 zip 自读自恢复 |
| pipeline 注入 | `lib/app.dart` 的 `imagePipelineProvider` | ohos 或 rust init 失败 → `DegradedImagePipeline`；`MyApp(imagePipeline:)` 供测试注入 |
| 动态取色 | `lib/app.dart` 的 `supportsDynamicColorProvider` | 默认 `!isOhosBuild`；外观页据此隐藏「跟随系统取色」开关并显示「鸿蒙暂不支持壁纸动态取色」 |
| 后台队列 | `lib/platform/ohos_background_work_client.dart` | 应用内串行队列；`retry`/抛错 30s × 2^(n-1) 指数退避，最多 3 次调度重试；`failed` 不重排。**不是** WorkScheduler 进程保活。进程被杀后只靠冷启动 `reconcilePending` 对账 Drift 行 |
| 启动四窗 | `lib/workflow/app_startup_recovery.dart` | 回调式：先串行清理 exports/imports/bundles/deletions，再 `Future.wait` 相册待清理 / 发布日记 / 相机 / 定位 / 队列。一窗挂起或抛错不得跳过其余窗。日记抽出为 `CaptureMediaService.recoverPublishJournals()`，不得折回 `cleanupInterrupted`。无杀进程 dump |
| GPS 回退 | `lib/platform/jpeg_gps.dart` | 宿主 GPS 皆空时解析 JPEG EXIF（度分秒 3 rational 或单值十进制度；S/W 取负） |
| UI 诚实提示 | 三个语义 Key | `watermark-engine-degraded`（存储页/拍摄详情/拍摄表单）、`gallery-picker-fallback`（存储页/拍摄表单）、`dynamic-color-unavailable`（外观页） |
| 相册诚实化 | `OhosSystemHost.ets` 的 `detectGalleryAccess` | 无 ACL 证明固定返回 `pickerFallback`；READ+WRITE 媒体权限不算 ACL；发布路径 `hasMediaWritePermission()` 才尝试 `createAsset` |
| 相册删除 | `ProbingGalleryStore.delete` / 宿主 `deletePublishedImage` | 按 URI 身份：沙箱 `file://` 走 picker/unlink，其余走 ACL `deleteAssets`。备份恢复同编号不得串 URI |
| 入口接线 | `lib/main.dart` | 鸿蒙下分享/通知/外链/选档/存档均接 `Ohos*Service`，不再覆盖成 no-op |
| HAP 工程 | `ohos/` | DevEco/hvigor 工程；包名 `io.github.wikg1018.sitemark`；`path_provider` / `package_info_plus` 由 `SiteMarkSystemPlugin` 桥接（返回 1.0.8 / 23） |

测试注入技巧（容易踩）：测试里**不要** import `degraded_image_pipeline.dart`，也不要无前缀 import `image_core.dart`——rust 类型会挡住 pigeon 类型。做法：写 `implements ImagePipeline` 的 fake + `import '.../rust/api/image_core.dart' as rust` + 显式 import `package:sitemark_system_api/sitemark_system_api.dart`。

## 8. 工作方式（用户偏好，接手即遵守）

- 用户中文沟通；已授权「直接做到功能体验对齐为止」——不要停在问方案，选定缺口 → 写计划 → TDD → 提交推送。
- 标准流程：选缺口 → 写 `docs/superpowers/plans/YYYY-MM-DD-<feature>.md`（带勾选框）→ 失败测试（看它红）→ 最小实现（看它绿）→ 诚实更新 `README.md` / `tool/ohos/full_product_gap.md` / `tool/ohos/product_hap_review.md` → commit → `git push origin ohos`。
- 提交风格：`fix(ohos): ...` / `feat(ohos): ...` / `docs(ohos): ...`（见 `git log origin/ohos -20`）。
- 用户要求由 Agent 直接负责，不使用子代理。
- 不提交：HAP、`ohos/entry/libs/`、构建缓存、一次性模拟器脚本、社区 pubspec lock、测试日志、审查 dump 临时文件。
- 用户没有真机；此前的模拟器验证全部在上一台本地 Windows 环境完成。云端 Agent 若要 dump 类证据，需要用户提供本地环境配合。

## 9. 下一步建议（Task 61 起）

优先做**不依赖 dump** 的体验/诚实缺口（云端可闭环）：

1. 对照规格 `docs/superpowers/specs/2026-08-17-harmonyos-next-adaptation-design.md` 剩余「必须/不得」项，继续找可 TDD 的缺口（相册 ACL 精确替换仍无 dump）。不要再把「四窗串行阻塞」「CI 缺 widget/lifecycle/备份导入」「取消拍照不占号」「空相机文件不占号 / live 空内容当取消」「拒绝定位仍出片 / 连拍编号」「相册保存取消再 throw 打成 failed」或「分享取消再 throw 打成失败」当缺口——已锁。
2. 若用户能提供本地环境：按第 6 节重编 HAP（注意 wantAgent / EntryAbility import 风险；**Task 46–60 的 Dart 侧改动尚未重编进任何 HAP**），做拍成 / 坐标 / 相册 / 分享 / 通知 / 外链 dump 走查，逐项解除第 3 节的门控。杀进程四窗没有模拟器 dump，不得写进程被杀后四窗已在真机/模拟器验证。

**已完成、不要重做：** Task 51 CI 扩容；Task 52 备份恢复同编号不得串 URI、删除按 URI/`captureId`；Task 53 启动四窗并行开工（回调 API，日记已抽出）；Task 54 delayed 继续拍 + `capture_workflow_test` 进 CI；Task 55 widget / lifecycle / 备份导入进 CI；Task 56 取消拍照不占号 + `capture_failure_guidance_test` 进 CI；Task 57 拒绝定位仍出片 + 连拍 `001` 然后 `002` + `capture_location_coordinator_test` 进 CI；Task 58 pending 空文件恢复不占号 + live 空 URI / materialize 无内容走 `cameraCancelled`；Task 59 相册保存对话框取消 / 空 destinations 回退沙箱，不 markFailed；Task 60 分享面板用户取消不报失败（Dart `ShareCancelPolicy` + ETS catch；空源 / `ohos_not_ready` / 其它错误仍 throw）。

**明确放弃的假缺口（不要重做）**：last-known 定位（Android 也没有）、逆地理（Android `address` 也是 null）、叠水印后 JPEG 写回 GPS（Rust 也不写）、通知点击接线（`deliverNotificationTap` 已有）、照片编号入水印（Rust `labels()` 也不画）、WorkScheduler / `startBackgroundRunning` 当 WorkManager 对等。

## 10. 文档索引

| 文档 | 用途 |
| --- | --- |
| `README.md`（ohos 分支） | 分支现状 + 完整计划链 + 诚实声明 |
| `tool/ohos/full_product_gap.md` | 已接通 vs 未接通总账 |
| `tool/ohos/product_hap_review.md` | 模拟器审查逐任务记录 |
| `tool/ohos/engine_status.md` | 引擎 degraded 事实与 rust 编译尝试 |
| `tool/ohos/appgallery_checklist.md` | 应用市场材料清单 |
| `tool/ohos/toolchain_probe.md` | 工具链探测记录 |
| `docs/superpowers/specs/2026-08-17-harmonyos-next-adaptation-design.md` | 适配规格（冲突时的设计事实源） |
| `NEXT_AGENT_PROMPT.md` | 常驻 Agent 入口（产品边界与工程约定） |
