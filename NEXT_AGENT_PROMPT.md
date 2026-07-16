# SiteMark v0.2.0 新 Agent 完整执行提示词

> 将本文件完整提供给负责后续代码实现的 Agent。本文是执行入口；产品与技术细节以本文指定的设计规格和实施计划为准。

## 你的角色

你是 SiteMark v0.2.0 的主实施 Agent。你的任务不是重新讨论需求，而是审查现有方案后，完整实现、测试、验证并交付已经批准的代码改动。

除非遇到本文“必须停止”的情况，否则请自主推进所有任务，不要因为普通实现细节反复询问用户，也不要只完成脚手架或部分功能后停止。

## 仓库与当前状态

- GitHub 仓库：`https://github.com/WikG1018/site-mark`
- 本机现有仓库：`C:\Users\Administrator\Documents\Codex\2026-07-15\new-chat`
- 应用 ID：`io.github.wikg1018.sitemark`
- 当前实现分支：`feat/sitemark-v0.1.0`
- 目标基础分支：`main`
- 当前 Draft PR：`https://github.com/WikG1018/site-mark/pull/2`
- 文档基准提交：`6258dadc452f7eb286729b099a1763ae728eacac`
- 目标版本：`0.2.0+2`
- 平台范围：Android 12/API 31 及以上

如果上述本机目录不存在，请克隆仓库并检出远端 `feat/sitemark-v0.1.0`。如果远端分支比本文记录的提交更新，以远端最新提交为起点，但必须先检查新增提交是否属于本项目。

## 开始前必须执行

1. 调用并遵守 `using-superpowers`。
2. 检查仓库中所有适用的 `AGENTS.md`，遵守作用域最深的指令。
3. 完整读取以下两份文件，不得只看摘要：
   - `docs/superpowers/specs/2026-07-16-sitemark-v0.2.0-ux-upgrade-design.md`
   - `docs/superpowers/plans/2026-07-16-sitemark-v0.2.0-ux-upgrade.md`
4. 检查 `git status -sb`、当前分支、远端、最近提交和 Draft PR #2。
5. 使用 `using-git-worktrees` 检查执行环境：
   - 如果当前 checkout 是本任务专用、分支正确且工作区干净，可以继续使用。
   - 如果存在其他用户改动或共享工作，创建隔离 worktree；不得覆盖、暂存或提交无关改动。
6. 若支持子 Agent，使用 `subagent-driven-development` 按实施计划逐任务执行并在每个任务后做规格和代码质量审查；若不支持，则使用 `executing-plans`。
7. 实现功能或修复前使用 `test-driven-development`；遇到失败或异常先使用 `systematic-debugging`。
8. 建立与实施计划 Task 1–8 一一对应的进度清单，一次只允许一个任务处于 `in_progress`。

开始实现前，先用一条简短消息向用户说明：已经读取设计与计划、当前执行方式、将从 Task 1 开始。除非发现关键矛盾，不需要再次请求批准。

## 唯一事实源与优先级

发生冲突时按以下顺序处理：

1. 用户在当前会话中的明确新指令。
2. 已批准的设计规格。
3. 详细实施计划。
4. 本提示词的执行规则。
5. 仓库现有实现和旧版文档。

设计规格决定产品行为和范围，实施计划决定接口、文件、测试、任务顺序和提交边界。不得静默改变已经确认的产品选择。若现有计划存在会导致数据丢失、安全问题、无法编译或 Android 平台不可行的错误，必须暂停对应任务，给出具体代码或官方文档证据，并向用户提出最小修订方案。

## 必须实现的五项用户反馈

1. 水印字体整体增大 20%，并同步调整行高、内边距、强调条和卡片高度；长文本不得越出卡片或照片。
2. 同一项目再次拍摄时，保留上一次的工作地点、工作内容和拍摄人；备注始终清空。
3. 系统相机返回后立即将照片加入持久后台队列，不等待哈希、水印渲染和 MediaStore 发布；用户可马上再次拍摄。
4. 项目记录和全部记录均显示图片缩略图，详情显示可缩放大图；处理状态变化时预览自动从原图切换为最终水印图。
5. 首页增加“全部记录”和“设置”：
   - 项目内支持年、月、日筛选。
   - 全部记录支持项目、年、月、日筛选。
   - 设置包含主题、语言、新项目默认水印和关于信息。

## 已锁定的产品行为

- 继续调用手机厂商/系统相机，不做 App 内相机，不使用第三方相机界面。
- 每张照片拍完后回到已经回填的拍摄表单，不自动再次打开相机。
- 后台任务必须在普通退出、划掉最近任务、进程被回收和设备重启后可恢复。
- Android 系统设置中的“强行停止”会暂停调度，直到用户重新打开 App；界面和文档必须如实说明。
- 全分辨率照片串行处理，不允许同时渲染多张大图。
- 临时错误使用指数退避，最多自动尝试 3 次；最终失败显示原因并允许人工重试。
- MediaStore 继续使用 `Pictures/SiteMark/<photoNumber>.jpg`，重试必须覆盖同名照片，不能产生重复成片。
- 全局水印默认值只影响之后新建的项目，不追溯覆盖已有项目设置。
- 筛选日期采用手机本地时区的 `capturedAt`；缺失时回退 `createdAt`。
- `pendingCamera` 不进入普通记录列表。
- `captured`/`rendering` 状态不开放编辑或删除，避免与后台发布产生竞态。

## 不得突破的产品与安全边界

- 不加入广告、统计分析、账号、云同步、远程 API、Google Play Services 或 INTERNET 权限。
- 不申请后台定位、CAMERA 权限、广泛媒体权限；继续使用系统相机 Intent 和 scoped MediaStore。
- 不实现 iOS、图库导入、自由拖拽水印、批量编辑或跨设备协作。
- 不删除或重建用户数据库来规避迁移问题。
- 不手工编辑 Drift、Pigeon 或 flutter_rust_bridge 生成文件；运行生成器并提交结果。
- 不使用 `git reset --hard`、强制推送或覆盖用户的未提交改动。
- 不把测试用 debug APK描述为正式签名 Release。

## 技术实现主线

严格按详细实施计划的 Task 1–8 顺序执行：

1. Drift schema v3、全局设置、后台尝试次数、记录筛选与回填查询。
2. 将 Android Pigeon 系统桥接提取为仓库内 `FlutterPlugin + ActivityAware` 路径插件，使 headless FlutterEngine 可以调用 MediaStore。
3. 实现 WorkManager 串行持久队列、幂等 `CaptureProcessor`、启动补偿和 queued capture workflow。
4. 实现三项表单回填、备注清空和拍完后停留表单。
5. 实现共享图片预览、记录卡片、项目/全局记录页和级联筛选。
6. 实现持久化主题、语言、新项目水印默认值和 About。
7. Rust 水印排版整体放大 20%，增加长文本测量和截断回归测试。
8. 完整集成、自动化验证、真机验收、README/截图/验证文档和 Alpha APK。

不要跳过任务中的红—绿测试步骤。若计划中的某条示例代码与当前依赖的真实 API 有小幅差异，可以按已锁定依赖的实际 API 做最小语法修正，但产品行为、公开接口意图、测试目标和验收标准不得改变。

## 每个任务的执行协议

对 Task 1–8 重复以下流程：

1. 标记当前任务 `in_progress`，读取该任务涉及的现有文件和测试。
2. 写出计划指定的失败测试。
3. 运行聚焦测试，确认它因缺少目标行为而失败；记录真实失败原因。
4. 实现满足测试的最小完整代码。
5. 运行聚焦测试、相关回归测试和静态检查。
6. 检查 diff，确保没有无关改动、手工生成文件或敏感信息。
7. 如有子 Agent，先做规格符合性审查，再做代码质量审查；修复审查问题。
8. 使用实施计划给出的提交边界和语义化提交信息提交。
9. 标记任务 `completed`，向用户发一条简短进度更新，然后进入下一任务。

任务间允许必要的小型重构，但必须服务于本版本需求，并包含测试。不得进行与目标无关的大规模架构重写。

## Windows 与工具约定

- 默认使用 PowerShell 7：`pwsh.exe -NoLogo -NoProfile`。
- 搜索文件或代码优先使用 `rg` / `rg --files`。
- 修改文件使用补丁方式，保护工作区中的用户改动。
- `flutter` 当前可能不在 PATH；从 `android/local.properties` 解析 SDK：

```powershell
$flutterSdk = (Get-Content android/local.properties |
  Where-Object { $_ -like 'flutter.sdk=*' } |
  ForEach-Object { $_.Substring('flutter.sdk='.Length).Replace('\:', ':') })
$flutter = Join-Path $flutterSdk 'bin\flutter.bat'
$dart = Join-Path $flutterSdk 'bin\dart.bat'
& $flutter --version
& $dart --version
```

- 不要因为命令行中文显示异常就认定文件损坏；验证真实 UTF-8 文件和生成产物。

## 完成前强制验证

在声称完成前必须调用并遵守 `verification-before-completion`，运行新鲜、完整的验证命令并阅读输出。至少包括：

```powershell
& $flutter pub get
& $dart run build_runner build --delete-conflicting-outputs
& $dart run pigeon --input pigeons/system_api.dart
& $dart format --output=none --set-exit-if-changed lib test integration_test
& $flutter analyze
& $flutter test
cargo fmt --manifest-path rust/Cargo.toml -- --check
cargo test --manifest-path rust/Cargo.toml
Set-Location android
.\gradlew.bat test
Set-Location ..
& $flutter build apk --debug
```

还必须验证：

- schema v2 → v3 迁移保留已有项目和记录。
- 后台任务幂等、串行、三次重试、启动补偿且 MediaStore 不重复。
- 表单回填、备注清空和拍摄按钮及时恢复。
- 原图/处理状态/成片/失败/文件缺失的预览行为。
- 项目和全部记录的项目/年/月/日筛选边界。
- 主题、语言和新项目默认水印持久化，已有项目不受影响。
- 横拍、竖拍、4:3、16:9 和最长工作内容下的水印排版。
- APK 的包名、版本号、版本码、min/target SDK、签名和权限清单。

如果没有可用真机，不得伪造真机结论。完成全部可执行的自动化、模拟和 APK 验证，在 `docs/verification-v0.2.0-alpha.md` 中明确列出尚需用户真机确认的项目，并提供最短测试步骤。

## 真机验收要求

有 Android 12+ 真机时完成并记录：

1. 在已安装 v0.1.0 测试版的手机上覆盖安装，确认旧项目和记录保留。
2. 连续拍摄至少 10 张，上一张处理时下一张仍可立即拍摄。
3. 确认三项字段保留、备注每次清空。
4. 确认列表从等待处理 → 处理中 → 已完成，预览切换为水印图。
5. 处理过程中划掉 App，重新打开后任务继续。
6. 至少测试一次设备重启后的任务补偿。
7. 确认系统相册每个照片编号只有一张成片。
8. 测试定位拒绝、相机取消和处理失败后的人工重试。

## APK 与文档交付

- 版本必须为 `0.2.0+2`。
- 为兼容用户手机上现有 debug 签名测试版，生成 debug-signed Alpha APK。
- 最终文件必须复制到：

```text
C:\Users\Administrator\Documents\水印相机\SiteMark-v0.2.0-alpha-debug.apk
```

- 记录 APK 文件大小和 SHA-256。
- 更新 README、`docs/verification-v0.2.0-alpha.md`、release checklist 和四张统一尺寸手机截图：
  1. 全部记录与筛选。
  2. 项目记录缩略图。
  3. 设置/About。
  4. 已回填的连续拍摄表单。
- 最终回复中直接把截图显示在对话里，用户不应被要求自行打开本地文件才能查看。

## GitHub 权限边界

你已获得以下权限：

- 修改本任务范围内的代码、测试、依赖、生成文件和文档。
- 按实施计划逐任务提交。
- 推送 `feat/sitemark-v0.1.0`。
- 更新 Draft PR #2 的标题、正文、提交和验证信息。

你没有以下权限：

- 合并 PR。
- 将 Draft PR 标记为 Ready for review，除非用户再次明确授权。
- 创建或发布正式 GitHub Release。
- 创建、替换或暴露生产签名密钥。
- 删除远端分支或改写 Git 历史。

提交前检查 `git status` 和 diff，只暂存当前任务文件。推送前确认本地与远端没有意外分叉。不得使用 `git add -A` 吞入来源不明的用户改动。

## 必须停止并询问用户的情况

仅在以下情况暂停，不要猜测：

- 工作区存在与本任务重叠且来源不明的未提交修改。
- 设计规格与实施计划存在会改变用户体验的实质冲突。
- schema 迁移可能丢失、重建或破坏现有用户数据。
- 实现需要新增云服务、网络权限、后台定位、广泛媒体权限、生产密钥或付费外部服务。
- 同一技术阻塞经过系统化排查和至少三次有证据的尝试后仍无法继续。
- 必须扩大 Android 版本范围、改变系统相机方案或更改已批准的后台处理模型。
- 需要合并 PR、发布正式 Release 或执行其他未授权外部操作。

报告阻塞时给出：复现命令、完整关键错误、已验证事实、尝试过的方案、推荐的最小选择。不要只说“失败了”。

## 最终完成标准

只有同时满足以下条件，才能向用户报告代码工作完成：

- 实施计划 Task 1–8 全部完成并有对应提交。
- 所有可运行的自动化检查有本轮新鲜的成功输出。
- 五项用户反馈均有自动化测试和验收证据。
- 工作区干净，本地 HEAD 与远端实现分支一致。
- Draft PR #2 已更新但未合并。
- APK 已生成到指定目录，并给出文件大小和 SHA-256。
- README、验证文档和截图已经同步。
- 未完成的真机步骤被明确标注，不能用自动化结果冒充真机结果。

全部任务完成后，调用 `requesting-code-review` 做最终代码审查，再调用 `finishing-a-development-branch`。在 finishing 阶段只报告可选方案；默认保持 Draft PR，不合并、不发布。

## 立即开始

现在开始执行：先完整读取设计规格和实施计划，检查仓库与 Draft PR 状态，建立 Task 1–8 清单，然后从 Task 1 的失败测试开始。除本文列出的阻塞条件外，持续推进直到交付完成。
