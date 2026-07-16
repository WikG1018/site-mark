# SiteMark PR #2 审查修复设计

## 目标

在保留 PR #2 已完成的 v0.2.0 功能基础上，修复正式审查发现的生产恢复、原图完整性、后台错误重试、相册清理、筛选级联和 CI 覆盖问题，并吸收已经合并到 `main` 的 PR #3 Android 启动图标。完成后 PR #2 必须通过全部自动化检查，GitHub 显示无冲突且达到可合并状态；最终合并仍由仓库维护者操作。

## 集成策略

- 使用普通 merge 将最新 `origin/main` 合入 PR #2 分支，不改写 PR #2 现有提交历史，也不使用强制推送。
- `AndroidManifest.xml` 以 PR #2 的离线权限和本地 Flutter 插件架构为主体，仅加入 PR #3 的 `android:roundIcon="@mipmap/ic_launcher_round"`。
- 不恢复旧的应用层 `.CaptureContentProvider`；Provider 继续由 `packages/sitemark_system_api` 插件清单声明。
- 图标设计文档保留 PR #3 的共享声明式场景、Pillow PNG 和 SVG 派生说明。
- `pubspec.yaml`、`pubspec.lock` 和发布清单保留 v0.2.0 依赖，同时加入 `flutter_launcher_icons` 和图标验证步骤。

## 启动恢复

生产启动不再通过 `MyApp` 的默认参数关闭 WorkManager 恢复。`main()` 仍负责在 `runApp` 前初始化 WorkManager，`SiteMarkApp` 启动时按顺序执行：

1. 恢复系统相机留下的待确认记录。
2. 查询数据库中的 `captured` 和 `rendering` 记录。
3. 将遗漏记录重新追加到持久化串行队列。

测试通过 `startupRecoveryEnabledProvider` 明确关闭启动恢复；不再保留一个可能误用于生产的默认关闭开关，也不在界面启动阶段重复初始化 WorkManager。

## 原图哈希与相册 URI

`resetCaptureForRetry` 只重置状态、失败原因和尝试次数，不清除以下证据和外部资源引用：

- 已存在的 `originalSha256`：重新生成和人工重试必须再次校验同一原图；哈希不匹配的记录不能通过重试建立新基准。
- 已存在的 `publishedUri`：旧成片在新成片成功覆盖前继续可追踪；若重新生成失败，删除记录仍能删除旧的 MediaStore 照片。

从未成功计算哈希或从未发布过的记录继续保持相应字段为 `null`。新成片发布成功后，`markReady` 用实际返回的 URI 更新记录。

## 后台错误分类

Rust 图像层继续使用现有 `Result<_, String>` 桥接签名，避免为本次修复扩大生成代码变更；但错误字符串改为稳定的机器前缀：

- `not_found:`：原始证据文件不存在，永久失败。
- `io:`：打开、读取、创建目录、写入或编码过程中发生临时 I/O 错误，最多自动尝试三次。
- `invalid_data:`：请求参数或图片内容无效，永久失败。

`RustImagePipeline` 将这些前缀转换为带 `kind` 的 Dart `ImagePipelineException`。`CaptureProcessor` 在哈希和渲染两个阶段统一处理该异常：临时错误在尝试次数小于三时返回 `retry`，第三次标记失败；缺失文件和无效数据立即标记失败。未知异常保持保守的永久失败处理，平台发布错误继续沿用现有 Dart/PlatformException 分类。

## 项目与日期级联筛选

全部记录页面仍使用未过滤记录生成项目列表；选择项目后，传给年、月、日筛选器的数据先按 `projectId` 收窄。这样年份只来自当前项目，月份只来自当前项目和选定年份，日期只来自当前项目、年份和月份。切换项目继续清空已有日期选择，避免保留无效子条件。

## CI 与仓库卫生

GitHub Actions 必须运行实际包含测试的任务：

- 安装 `tool/icon-requirements.txt`。
- 运行两个 Python 图标测试模块和图标资源验证器。
- 运行 `:sitemark_system_api:testDebugUnitTest`，不再以 `:app:testDebugUnitTest` 的 `NO-SOURCE` 结果代表 Kotlin 测试通过。
- 保留 Flutter analyze/test、Rust fmt/clippy/test 和 debug APK 构建。
- 发布工作流执行同样的图标资源验证和 Kotlin 插件测试，再进入签名构建。

仓库忽略 Python `__pycache__`，图标文档补充依赖安装命令，确保按文档运行生成器后工作树保持干净。

## 测试策略

所有行为修改按测试先行执行：

1. 启动配置测试先证明生产默认不会关闭恢复。
2. 数据库和工作流测试先证明重试保留哈希与 URI，并证明篡改原图在重试后仍失败。
3. 处理器测试分别覆盖哈希阶段和渲染阶段的 `notFound`、`transientIo`、`invalidData`，并验证第三次失败边界。
4. Rust 测试验证稳定错误前缀。
5. 筛选 Widget 测试验证选择项目后不显示其他项目的年份。
6. CI 配置通过本地对应命令复核，确认 Kotlin 任务实际执行 7 项测试。

最终验收包括 Flutter 全量测试与静态分析、Rust fmt/clippy/test、Kotlin 插件测试、Python 图标测试与资源验证、debug APK 构建、禁止权限检查、`git diff --check`、GitHub CI 通过以及 PR 无合并冲突。

## 非目标

- 不改变水印视觉、记录字段、数据库 schema 版本或 MediaStore 命名规则。
- 不新增网络、账号、云同步、广告、分析或后台定位。
- 不替仓库维护者执行 PR #2 的最终合并。
