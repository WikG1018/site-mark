# SiteMark 鸿蒙原生（ArkTS）从零到对齐实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **配套设计规划：** [`docs/superpowers/specs/2026-08-18-harmonyos-native-parity-design.md`](../specs/2026-08-18-harmonyos-native-parity-design.md)。目标、边界、架构、数据流与对等门槛以规划为准；本文件只拆 Task 与验收步骤。

**Goal:** 在 GitHub `origin/main` 的 SiteMark v1.0.8（`abc0164`）功能基线上，**从零**用原生 ArkTS 按 2026-08 最新 HarmonyOS 开发规范开发独立鸿蒙应用，交付在 DevEco Studio NEXT **模拟器**上完整验证的签名 HAP（产物同时保持 arm64 + x86_64 双架构，真机就绪），产品语义与 Android v1.0.8 **对齐到模拟器验证级**；产品代码全部落在从 `abc0164` 拉出的长期分支 `ohos-native`。

**规范基线（最新鸿蒙系统开发规范，本计划的技术锚点）：**

| 项 | 取值 |
| --- | --- |
| 操作系统 | HarmonyOS 6.1.1（API 24 Release，2026-05-26）；兼容 HarmonyOS 7 / API 26 Beta1 仅做预检，不用于生产 |
| IDE / 工具链 | DevEco Studio 6.1.1 Release（6.1.1.300）+ 内置 HarmonyOS SDK 6.1.1（基于 OpenHarmony SDK 6.1.1.125） |
| 应用模型 | Stage 模型（FA 模型已废弃，禁止使用） |
| 语言 / UI | ArkTS（严格静态超集）+ ArkUI 声明式；ArkCompiler AOT |
| 构建 / 包管理 | hvigor（`hvigorw`）+ ohpm（`oh-package.json5`） |
| targetSdkVersion | `6.1.1(24)` |
| compatibleSdkVersion | 初值 `5.0.5(17)`（下限不低于 `5.0.0(12)`，Kit 逐项标注最低 API）；无真机流量矩阵，暂不校准，登记入 `deltas.md` |
| 代码规范 | ArkTS 严格模式（`arkOptions.strictMode`）、codelinter 零 error；对象字面量必须对应明确 class/interface；状态装饰器显式类型 |
| 测试 | hypium（`ohosTest` 单元 / UI）+ 模拟器手工回归总表（真机复跑为挂起前置） |

**Architecture:** `main` 继续官方 Flutter 3.41.x / Pigeon+Kotlin / WorkManager / MediaStore 的 Android 发布线，一行不改。`ohos-native` 分支新增 `ohos-native/` 原生工程：单 entry + 多 HSP/HAR 分层（commons / data / core / feature_*），ArkUI `Navigation` + `NavPathStack` + 根部悬浮 Dock 三分支保活；数据层用 `@ohos.data.relationalStore` 镜像 Drift schema v11；图像核心**复用仓库根 `rust/` 的 `sitemark_core` crate**（交叉编译双目标：`x86_64-unknown-linux-ohos` 供 DevEco 模拟器、`aarch64-unknown-linux-ohos` 供真机就绪，经 NAPI 绑定），保证 EXIF、SHA-256、全分辨率水印、CSV/JSON/ZIP 导出与 Android **同源同算法**；相机走系统相机（不自研相机），相册走 PhotoAccessHelper（ACL 直写主路径 + 安全面板托底）；后台处理为应用内存活期串行队列 + 启动 reconcile（与 Android WorkManager 的差异显式声明，见差异表）。

**Tech Stack:** ArkTS / ArkUI / Stage 模型（UIAbility + EntryAbility）、hvigor + ohpm、`@ohos.data.relationalStore`、`@ohos.data.preferences`、`@kit.CameraKit`（系统相机）、`@kit.LocationKit`、`@kit.MediaLibraryKit`（PhotoAccessHelper）、`@kit.NotificationKit`、`@ohos.file.fs` / `@kit.CoreFileKit`（picker）、Rust `sitemark_core` + NAPI（napi-rs ohos 目标或 C ABI + C++ 薄封装，以 Task 3 实测为准）、hypium。

**与既有 `ohos` 分支（社区 Flutter 适配路线）的关系：** 本计划**取代**该路线。`ohos` 分支截至 `821f3d4` 的实测结论是关键输入：① 空壳 Flutter HAP 已在 DevEco NEXT 模拟器（`SiteMarkPhone602`，OpenHarmony 6.0.2.130 / API 22）冷启动通过——本机模拟器环境可用是直接资产；② Rust `ohos-arm64` 可交叉编译但引擎初始化失败，长期处于 `degraded` 降级水印，且社区 Flutter 锁在 3.27–3.32、插件生态断档，无法追平 `main` 的 Flutter 3.41.x 主线；③ 相册 ACL、相机、定位契约未闭环。`ohos` 分支冻结归档仅作参考（发布日记按 `captureId`、条件清日记、串行队列、隐私弹窗文案等**设计结论直接继承**），不再推进；`ohos-native` 为唯一活跃鸿蒙线。

---

## Global Constraints

- 基线是 GitHub `origin/main` **v1.0.8 / `abc0164`**。产品语义以该提交的代码与 `docs/current-product-architecture.md`、`docs/record-watermark-settings.md`、`docs/capture-processing-storage.md` 为准。
- `ohos-native` 从 `abc0164` 拉出；`ohos-native/` 工程、CI、签名配置只存在该分支。`main` 的 `lib/`、`android/`、`pigeons/`、`.github/workflows/ci.yml`、`release.yml` 禁止改动。
- `main` 的产品修复只允许 `main` → `ohos-native` cherry-pick，反向合入禁止。
- 产品边界不变：无账号、无云同步、无广告、无统计上传、**不申请 `ohos.permission.INTERNET`**；仓库链接交给外部浏览器（`openLink`）。
- 相机边界不变：不自研、不嵌第三方相机 UI，调用系统相机拍摄；相机取消不创建可见记录、不占照片编号。
- 发布日记只按 **`captureId`** 记账（备份恢复后同编号可跨项目重复，编号/文件名不可作为相册操作键）；**原生侧不删除相册行**，`publishJpeg` 返回 `PublishJpegOutcome(contentUri, supersededUris)`，删除由业务层做全库引用检查后执行；`clearPublishJournal(captureId, expectedContentUri)` 必须条件清除。
- 黄金向量强制对齐：编号/命名（`{安全化项目名称}-SM-{yyyyMMdd}-{全应用当日序号}.jpg`）、模板与字段规范化（`trim` + `\s+` 折叠、`name_key` 仅小写 ASCII `A-Z`、长度按 Unicode 标量、拒绝 U+0000）、状态机（`pendingCamera → captured → rendering → ready / failed`）必须移植 Android/Dart 现有单元测试用例为 hypium 测试，逐条对齐。
- 备份兼容性强制：项目 ZIP 兼容 schema v1/v2/v3/v4/v5，多项目外层 bundle schema v1；恢复的所有权令牌、暂存回滚、提交标记收尾语义照搬 `docs/capture-processing-storage.md`。
- 「全量对等」宣称门槛拆两级（详见文末）：**模拟器对等验证**（本计划出口）与**真机对等确认**（挂起前置，获得真机后补验）。任何降级（托底相册、降级水印、通知缺失）必须写入 `ohos-native/docs/deltas.md` 差异表并在发布说明标注，不得 silently 假装对等。
- 不在 UI、记录卡片、SnackBar/Toast、诊断包对外文案里暴露原始异常或平台字符串。
- 所有行为变更先写失败测试（hypium 先红），再写最小实现验证转绿；纯逻辑必须落在 `commons/*` HAR 以便单测。Task 0 工具链用模拟器冷启动作为验收，不编造单测替代表。
- 模拟器是唯一验收环境（当前无鸿蒙真机）：Task 0 与所有里程碑验收均在 DevEco NEXT 模拟器执行；**真机验证作为独立前置条件挂起**（见「对等宣称门槛」），模拟器通过不得对外宣称真机全量对等。模拟器无法覆盖的能力（性能/流畅性、传感器实况、厂商相机差异、ACL 真机授权行为、通知通道实况）逐项登记 `ohos-native/docs/deltas.md`。
- 模拟器相机不可用或不可控时：允许 **debug-only 拍摄注入通道**（从图库/文件选择 JPEG 注入 `originals/` 驱动完整状态机），仅存在于 debug 构建并在 release 编译剥离；该通道是测试注入，不构成自研相机，不违反产品边界。

---

## 功能对齐矩阵（Android v1.0.8 → HarmonyOS 原生）

| # | Android 能力（main 现状） | 鸿蒙方案（Kit / API） | 最低 API | 对等备注 |
| --- | --- | --- | --- | --- |
| 1 | 系统相机拍摄（MediaStore ActionStillImage / 厂商相机） | `@kit.CameraKit` `cameraPicker.pick()` 拉起系统相机拍摄；不能直写沙箱时先落临时 URI 再拷贝到 `originals/<captureId>.jpg` | 12 | Task 0 实测落档；取消/失败语义照 Android（0 captured / 1 cancelled / 2 failed） |
| 2 | 拍摄半截恢复（杀进程后补记） | `@ohos.data.preferences` 持久 `CaptureSessionStore`（键 `capture_id` / `capture_path`，commit 语义） | 12 | 与 Android `CaptureTargetPolicy` 同判定：`exists && length > 0` |
| 3 | 前台定位（按需、拒权不阻断） | `@kit.LocationKit` `geoLocationManager.getCurrentLocation` + `requestPermissionFromUser`（`LOCATION` + `APPROXIMATELY_LOCATION`） | 12 | 超时/拒权/服务关闭映射 `LocationOutcome` 同枚举语义 |
| 4 | 跳系统应用设置 | `startAbility` 跳应用详情（action 以 API 24 文档实测为准） | 12 | Task 0 探测项 |
| 5 | MediaStore 发布到 `Pictures/SiteMark` | `@kit.MediaLibraryKit` `PhotoAccessHelper.MediaAssetChangeRequest` 创建 JPEG 资源（用户目录 SiteMark） | 12 | **主路径**需 AGC ACL（`READ_IMAGEVIDEO`/`WRITE_IMAGEVIDEO`）；**托底**为 SaveButton 安全面板 / `DocumentViewPicker.save`，托底必须标“未进入系统相册” |
| 6 | 按引用删除已发布相册照片 | `MediaAssetChangeRequest` / `phHelper.deleteAssets`（删除需用户授权确认） | 12 | 授权语义与 Android 略异：删除前弹系统确认；拒绝时保留相册照片并在差异表声明 |
| 7 | WorkManager 串行后台处理 | 应用内串行队列（ArkTS `taskpool` 派发 Rust 渲染）+ 启动 `reconcilePending`；`workScheduler` 仅用于延迟拉起补跑，不承诺被杀后继续 | 12 | **预声明差异**：应用被杀后处理暂停，下次启动收敛；不使用长时任务伪装后台 |
| 8 | Drift / SQLite schema v11 | `@ohos.data.relationalStore` 镜像同表同列同索引（`projects` / `captures` / `capture_templates` / `app_settings`，游标索引 `(sortTime, id)`） | 12 | 新装直接建 v11；不迁移 Flutter 数据库文件（数据经备份 ZIP 迁移） |
| 9 | SharedPreferences（设置/日记/会话） | `@ohos.data.preferences` | 12 | 日记键布局照搬 Android（`journal.<base64url(id)>.exists/newUri/staleCount/stale.<i>`，XML 安全） |
| 10 | Rust 水印/EXIF/SHA-256/ZIP（FRB） | 同一 `rust/` crate 交叉编译 `aarch64-unknown-linux-ohos` → .so，NAPI 绑定进 `entry`（`libs/arm64-v8a`） | 12 | 同源同算法；FRB 不适用，新增 `extern "C"` JSON-in/JSON-out 薄 FFI（不动 FRB 导出） |
| 11 | 全分辨率水印渲染（后台 isolate） | `taskpool` 任务封装 `ImagePipeline`（`render/export/exportSelection/readProjectArchive/extractArchivePhoto/sha256`） | 12 | 大图字节不过 ArkTS 主线程，只传路径与结构化参数 |
| 12 | 通知（Android 13+ best-effort） | `@kit.NotificationKit` `requestEnableNotification` + `publish`；失败吞掉不阻断处理 | 12 | best-effort 语义一致 |
| 13 | Material 3 主题/深色/强调色 | ArkUI 主题 tokens + `resources/dark` 深色资源 + 强调色板（固定色板） | 12 | **预声明差异**：无 Monet 动态取色等价，仅手动强调色 |
| 14 | 中英文 + 应用内语言切换 | `resources/base`（en）+ `resources/zh_CN` + `i18n.System.setAppLanguage` | 12 | 文案从 `lib/l10n/app_strings.dart` 全量搬运 |
| 15 | 悬浮 Dock 三分支导航 + 状态保活 | `Navigation` + `NavPathStack` + 自定义 Tabs 容器；分支用 `onPageShow` 状态缓存（保活/仅当前分支绘制） | 12 | Dock 选中背景覆盖图标+文字；二级页隐藏 Dock |
| 16 | Hero 转场 / 玻璃材质 | ArkUI `sharedTransition` + 模糊/透明度材质容器 | 12 | 视觉近似即可，列入模拟器走查项 |
| 17 | 分享导出 ZIP（share_plus） | Share Kit 或 `DocumentViewPicker.save`（以 API 24 实测为准） | 12 | Task 7 探测项；导出文件仍可恢复语义不变 |
| 18 | 外部浏览器打开仓库链接 | `UIAbilityContext.openLink`（https） | 12 | 应用自身仍无网络权限 |
| 19 | 通知/内存压力清理 imageCache | PixelMap 列表缩略缓存上限（≈40 张/32MB 等价）+ `onMemoryLevel` 清理 | 12 | 模拟器仅功能验证，滚动性能结论留给真机阶段（`deltas.md` 登记） |
| 20 | 诊断包（本机、不上传、无工程内容） | hilog 旁路 + 自有诊断事件存储（RDB 表/JSON 文件），`DocumentViewPicker` 导出 | 12 | 固定结果分类/数量/耗时，不落原始异常 |
| 21 | 隐私同意门（ohos 分支已定稿文案） | 首启 `PrivacyConsentGate`（未同意不进主界面、不申请权限） | 12 | 文案原样继承 `ohos` 分支 `app_strings` 定义 |
| 22 | 存储：应用私有目录统计 / 清理导出 | `@ohos.file.fs` 递归统计沙箱目录（originals/renders/exports/db/docs） | 12 | 口径与 Android 一致：不含系统相册 |

---

## File map

| 路径（`ohos-native` 分支） | 职责 |
| --- | --- |
| `ohos-native/AppScope/` + `build-profile.json5` + `oh-package.json5` | 应用级配置：bundleName、versionCode/API 版本（target `6.1.1(24)`）、签名占位 |
| `ohos-native/entry/` | UIAbility 壳：`EntryAbility`、`pages/Index`（Navigation 宿主 + 悬浮 Dock）、隐私门挂载、NAPI .so 加载 |
| `ohos-native/commons/utils/`（HAR） | 纯逻辑：字段/模板规范化、照片编号与文件名、重试退避、base64url 日记键 |
| `ohos-native/commons/model/`（HAR） | 实体与状态机：CaptureStatus、Lifecycle、CameraOutcome/LocationOutcome 枚举、PublishJpegOutcome/RecoveredPublishJournalEntry |
| `ohos-native/data/database/`（HSP） | RelationalStore schema v11 镜像、DAO、游标分页/关键词/日期 facets、编号分配事务、迁移骨架 |
| `ohos-native/data/prefs/`（HSP） | preferences 封装：设置键、发布日记、相机会话、隐私同意、恢复所有权令牌 |
| `ohos-native/core/media/`（HSP） | Rust NAPI 绑定 + taskpool `ImagePipeline` + 降级管线标记 |
| `ohos-native/feature/projects|records|capture|settings|backup|diagnostics/`（HSP） | 各功能域页面与控制器（ArkUI） |
| `ohos-native/entry/libs/{arm64-v8a,x86_64}/libsitemark_core.so` | `rust/` 双架构交叉编译产物（模拟器 x86_64 + 真机就绪 arm64；构建脚本拷贝，不入 LFS） |
| `rust/src/ffi/` | 新增 `extern "C"` JSON FFI 层（只增不改，FRB 导出不动） |
| `tool/ohos-native/` | `probe.md`（工具链/模拟器实测）、`build-rust.ps1`、`build-hap.ps1`、`deltas.md`（差异表） |
| `.github/workflows/ohos-native.yml` | **只挂 `ohos-native` 分支**：command-line-tools（hvigorw + ohpm）`assembleHap` + codelinter |
| `ohos-native/docs/deltas.md` | 预声明差异与实测差异的唯一登记处 |
| `ohos-native/entry/src/main/module.json5` | 权限声明：`LOCATION`、`APPROXIMATELY_LOCATION`、通知；**不声明** INTERNET / CAMERA（系统相机替拍） |

不改：`lib/`、`android/`、`pigeons/`、`packages/`、`.github/workflows/ci.yml`、`release.yml`。

---

### Task 0: 规范基线、模拟器硬闸与 `ohos-native` 分支

**Files:**
- Create branch: `ohos-native` from `origin/main` @ `abc0164`（含本计划与配套规格的合并结果）
- Create: `tool/ohos-native/probe.md`（实测记录：DevEco 版本、SDK、模拟器型号 / ABI / API 版本、相机/相册/设置页/分享探测结论）
- Do not modify: `main` 的任何文件

**Interfaces:**
- Consumes: GitHub `origin/main` `abc0164`；本计划与配套设计规划（经 PR 合入 `main` 后拉分支，或先 cherry-pick 本提交到 `ohos-native`）
- Produces: 可在 DevEco NEXT 模拟器冷启动的签名空壳 HAP；五项技术探测结论（相机 picker、相册直写/删除授权流、应用详情页跳转、文件保存托底、openLink）

- [ ] **Step 1: 安装并锁定工具链**

安装 DevEco Studio 6.1.1 Release（6.1.1.300）+ 内置 SDK（API 24）。`hvigorw -v`、`ohpm -v`、`hdc version` 输出写入 `probe.md`。开启 hvigor 守护进程与并行编译加速。

- [ ] **Step 2: 生成 Stage 模型空壳并在模拟器跑通冷启动**

DevEco 新建 Empty Ability 工程（Stage 模型，ArkTS，phone），`targetSdkVersion 6.1.1(24)`、`compatibleSdkVersion 5.0.5(17)`；签名后安装到本机 DevEco NEXT 模拟器冷启动。同时确认两项并写入 `probe.md`：① 模拟器实际 API 版本（现有 `SiteMarkPhone602` 为 OpenHarmony 6.0.2.130 / API 22；若 DevEco 6.1.1 提供更高 API 镜像则升级）——决定哪些 API 24 特性需降级验证；② 模拟器 CPU ABI（x86_64 / arm64）——决定 Rust 编译与 .so 加载目标。

- [ ] **Step 3: 五项技术探测（在模拟器执行，结论写入 probe.md，后续任务按结论走；ACL/相机/删除授权结论标注「模拟器行为，真机待复验」）**

1. `cameraPicker.pick()` 拍照返回 URI 行为与权限要求（预期无需 CAMERA 权限）；模拟器虚拟相机不可用时记录替代验证方式（debug 注入通道）；
2. `MediaAssetChangeRequest` 创建 JPEG：无 ACL 时表现 → 确认 SaveButton 托底链路；
3. 删除用户相册资产的授权弹窗语义；
4. 跳转本应用详情页的 Want action 实测值；
5. `openLink` 打开 https 与 `DocumentViewPicker.save` 保存 ZIP。

- [ ] **Step 4: 过关或停**

过关条件：模拟器冷启动成功 + 五项探测有明确结论（含模拟器 ABI 与 API 版本落档）。不过：停在 Task 0，把失败写入 `probe.md`，向用户汇报后调整（不得带着未探测项进入后续任务）。

- [ ] **Step 5: Commit**

```bash
git add tool/ohos-native/probe.md ohos-native
git commit -m "chore(ohos-native): add toolchain probe and empty Stage-model shell"
```

---

### Task 1: 工程骨架、分层、隐私门与主题/语言

**Files:**
- Create: `ohos-native/` 分层结构（见 File map；`commons/utils`、`commons/model`、`data/*`、`core/media`、`feature/*` 骨架 + `oh-package.json5` 依赖图）
- Create: `entry/src/main/ets/pages/Index.ets`（Navigation 宿主 + 悬浮 Dock 三分支占位页）
- Create: `feature/onboarding/PrivacyConsentGate.ets` + `data/prefs/PrivacyConsentStore.ets`
- Create: `resources/base/element/*` + `resources/zh_CN/element/*` + `resources/dark/element/color.json`
- Modify: `entry/src/main/module.json5`（权限 reason 资源引用）
- Create: `ohosTest` 用例（隐私门两例）

**Interfaces:**
- Produces:
  - `class PrivacyConsentStore { isAccepted(): Promise<boolean>; accept(): Promise<void> }`，键 `privacy_consent_accepted_v1`
  - `PrivacyConsentGate` 组件：未同意只显示说明 +「同意并继续」+「退出」；退出调用 `terminateSelf()`
  - 主题 tokens：深/浅色、强调色板（accent 列表与 Android `accent_swatches.dart` 一致）
  - 语言：资源双语 + `i18n.System.setAppLanguage` 切换即时生效

- [ ] **Step 1: 失败测试**（hypium）：未同意时主界面不可见、同意后进入且 `accept()` 持久化。
- [ ] **Step 2: 实现隐私门**（文案原样继承 `ohos` 分支定稿：使用前说明 / 离线声明 / 同意并继续 / 退出）。
- [ ] **Step 3: 搭分层与 Dock 骨架**：三分支占位页状态保活（仅当前分支绘制）；`strictMode` 开启，codelinter 零 error。
- [ ] **Step 4: 模拟器验证**：首启弹隐私门 → 同意 → 进入三分支骨架；杀进程重启不再弹；语言切换即时生效。
- [ ] **Step 5: Commit** — `feat(ohos-native): add stage skeleton, privacy gate, theme and i18n`

---

### Task 2: 数据层镜像（schema v11 + 查询 + 黄金向量）

**Files:**
- Create: `data/database/schema/`（建表 SQL：`projects`、`captures`、`capture_templates`、`app_settings` + `(sortTime, id)` 游标索引 + 级联删除）
- Create: `data/database/dao/`（ProjectDao、CaptureDao、TemplateDao、SettingsDao）
- Create: `data/database/query/`（游标分页 50/页、多词 AND 搜索、日期 facets、全选复用同一查询）
- Create: `commons/utils/normalize.ets`（trim/空白折叠/name_key/长度按 Unicode 标量/拒绝 U+0000）
- Create: `commons/utils/photo_naming.ets`（`{safeName}-SM-{yyyyMMdd}-{seq}` 与全应用当日序号分配 SQL）
- Create: `data/diagnostics/DiagnosticEventStore.ets`
- Create: `ohosTest` 用例集

**Interfaces:**
- Consumes: Android/Dart 测试黄金向量 —— 移植 `capture_display_name_test`、`photo_number_test`、`capture_template_rules_test`、`project_name_test`、`capture_status_test`、`capture_list_query_test` 的全部用例为 hypium 测试
- Produces:
  - `interface CaptureListQuery { page(cursor, size=50): Page<Item>; facets(): {years, months, days}; total(): number }`
  - 编号分配：单事务内取当日最大序号 +1（跨项目递增）
  - 搜索：空白分词、每词匹配 项目名/工程部位/工作内容/拍摄人/备注/照片编号/地址，多词同时命中

- [ ] **Step 1: 失败测试**：先移植全部黄金向量用例（规范化/命名/状态机/查询分页与 facets）。
- [ ] **Step 2: 实现纯逻辑与 DAO**，逐条转绿。
- [ ] **Step 3: 验证**：hypium 全绿；模拟器确认建库、插入、分页翻页稳定（相同拍摄时间也能稳定翻页）。
- [ ] **Step 4: Commit** — `feat(ohos-native): mirror drift schema v11 with golden-vector parity`

---

### Task 3: Rust 核心集成与图像管线

**Files:**
- Create: `rust/src/ffi/mod.rs`（`extern "C"` JSON-in/JSON-out：`render_photo` / `export_project` / `export_selection` / `read_project_archive` / `extract_archive_photo` / `sha256`；参数/返回结构与 `lib/src/rust/api/image_core.dart` 对齐）
- Create: `tool/ohos-native/build-rust.ps1`（双目标编译：`x86_64-unknown-linux-ohos`（模拟器，按 Task 0 实测 ABI）+ `aarch64-unknown-linux-ohos`（真机就绪）→ 按模拟器 ABI 加载对应 .so，两架构产物都入库）
- Create: `core/media/SitemarkCore.ets`（NAPI 绑定）+ `core/media/ImagePipeline.ets`（`taskpool` 封装六方法）
- Create: `core/media/DegradedPipeline.ets`（`isDegraded=true`；复制原图 + 纯文本水印；`invalid_data:` 前缀错误）
- Create: `ohosTest` + 模拟器版式对照流程
- Modify: `rust/Cargo.toml`（如需 ohos 目标条件依赖，不改既有 API）

**Interfaces:**
- Consumes: `sitemark_core` 既有纯 Rust 入口（FRB 只是 Dart 绑定，算法本体直接可用）
- Produces: `interface ImagePipeline { isDegraded: boolean; render(...); export(...); exportSelection(...); readProjectArchive(...); extractArchivePhoto(...); sha256(...) }`

- [ ] **Step 1: 失败测试**：`DegradedPipeline` 契约（isDegraded、六方法齐备、错误前缀可解析）。
- [ ] **Step 2: 编 .so 并接 NAPI**（napi-rs ohos 或 C ABI + C++ 薄封装，二选一以实测为准，写入 `probe.md`；Rust 初始化失败 → 自动切 `DegradedPipeline` 且 UI/诊断可见降级标记）。
- [ ] **Step 3: 模拟器版式对照**：同字段同参数在模拟器渲染一张（相机不可用时经 debug 注入通道取原图），与 Android v1.0.8 同源成片逐块对照（项目名/字段/时间/位置/透明度/字号/强调色/EXIF 方向）——Rust 渲染输出为文件级对比，不依赖设备形态。结论写 `tool/ohos-native/engine_status.md`（`ok` / `degraded`，标注「模拟器验证级」）。
- [ ] **Step 4: 验证**：sha256 与 Android 同文件一致；ZIP 导出可被 Android 端恢复读取。
- [ ] **Step 5: Commit** — `feat(ohos-native): integrate rust core via napi with degraded fallback`

---

### Task 4: 拍摄链路（相机、定位、状态机、串行队列、启动恢复）

**Files:**
- Create: `core/system/SystemServices.ets`（ArkTS 版 `PlatformServices` 同名方法集：`createCameraTarget` / `launchCamera` / `recoverCameraCapture` / `finishCameraCapture` / `requestCurrentLocation` / `publishJpeg` / `recoverPublishJournals` / `clearPublishJournal` / `deletePublishedImage` / `getLocationPermissionState` / `requestLocationPermission` / `openApplicationSettings` / `inspectImage`）
- Create: `core/system/CameraBridge.ets`、`LocationBridge.ets`（按 Task 0 探测结论实现）
- Create: `data/prefs/CaptureSessionStore.ets`（commit 语义持久化）
- Create: `feature/capture/CaptureWorkflow.ets` + `CaptureProcessor.ets`（状态机：`pendingCamera → captured → rendering → ready/failed`；处理次数幂等；定位解析失败不阻断）
- Create: `background/SerialCaptureQueue.ets`（应用内串行：同 `captureId` 未执行可替换，进程内一次一张）
- Create: `app/StartupRecovery.ets`（相机半截补记 + 队列 reconcile + 日记对账，杀进程四窗收敛）
- Create: `ohosTest` 用例集

**Interfaces:**
- Consumes: `commons/model` 枚举（CameraOutcome 0/1/2、LocationOutcome 0–5、CaptureStatus）
- Produces: 相机原图落沙箱 `originals/<captureId>.jpg`（校验 `^[A-Za-z0-9][A-Za-z0-9_-]{0,95}$` + `.jpg`）；连拍保留三必填字段清空备注；取消不占编号；通知 best-effort

- [ ] **Step 1: 失败测试**：会话恢复、编号不乱（取消/失败/杀进程）、串行一次一张、同 ID 替换未执行项、状态机全转移。
- [ ] **Step 2: 实现桥接与队列**，转绿。
- [ ] **Step 3: 模拟器手工**：建项目→填表→系统相机（模拟器虚拟相机不可用则 debug 注入）→确认入库；取消拍照；拍后立即杀进程再进（半截恢复）；拒定位仍出片；连拍编号递增。
- [ ] **Step 4: Commit** — `feat(ohos-native): implement capture pipeline with serial queue and recovery`

---

### Task 5: 相册发布与媒体管理语义

**Files:**
- Create: `data/prefs/PublishJournalStore.ets`（`record/peek/recover/clear`；键布局与 Android 一致且 XML 安全；record 失败 → 整次 publish 失败）
- Create: `core/system/GalleryPublisher.ets`（ACL 直写主路径）+ `SaveButtonFallbackPublisher.ets`（安全面板托底，`enteredSystemAlbum=false`）+ `ProbingPublisher.ets`（探测一次缓存选路）
- Create: `core/system/MediaCleanup.ets`（`supersededUris` 引用检查删除：全库无引用才删；已不存在当成功；重试上限）
- Create: `ohosTest` 用例集（日记四例照搬 `ohos` 分支定稿：round-trip / 条件 clear / 同 ID 折叠 / 敌意 ID 键安全；相册适配器三例：不扫文件名、原生不删、托底不宣称对等）

**Interfaces:**
- Consumes: Task 4 `SystemServices.publishJpeg` 语义
- Produces: 发布 = 落新图 → 同步写日记 → 返回 `(contentUri, supersededUris)`；Dart/ArkTS 业务提交 DB 后 `clearPublishJournal(id, contentUri)`；删除走引用检查

- [ ] **Step 1: 失败测试**（上述七例，先红）。
- [ ] **Step 2: 实现并转绿**；`module.json5` 补 ACL 权限申请与 reason。
- [ ] **Step 3: 模拟器手工**：ACL 授权路径直写相册（模拟器授权行为与真机的差异登记 `deltas.md`）；拒绝授权 → SaveButton 托底 + 「未进入系统相册」文案；删除整条记录时相册照片按授权语义处理（差异表登记）；再保存仅对 `ready` 且成片在；清理原图保留成片与记录；删除项目不删相册照片。
- [ ] **Step 4: Commit** — `feat(ohos-native): gallery publish journal and media parity semantics`

---

### Task 6: 记录与项目管理 UI 对等

**Files:**
- Create: `feature/projects/`（列表：状态筛选默认进行中 + 跨状态搜索 + 置顶 + 卡片信息；表单：两层唯一性校验 + 项目说明 + 水印参数；详情；生命周期操作防呆：处理中阻止、失败需确认；项目水印设置页）
- Create: `feature/records/`（记录卡片列表：缩略图 + 可见日期随滚动更新；筛选面板（项目/年/月/日）+ 已生效条件独立移除；批量模式：复选框盖缩略图 + 批量 Dock（全选/导出/再保存/清理原图/删除）；详情：成片/原图 + 现场记录/文件信息双 Tab + 点击进全屏相邻浏览；编辑页）
- Create: `feature/capture/`（拍摄表单：三必填 + 备注、最近建议 3 条/更多 20 条、命名模板应用与撤销、连拍字段保留）
- Create: `shared/`（悬浮 Dock、玻璃卡片、`sharedTransition` Hero、骨架屏）

**Interfaces:**
- Consumes: Task 2 DAO + Task 4/5 链路
- Produces: 与 Android v1.0.8 逐屏对等的 UI（文案从 `app_strings.dart` 全量搬运双语）

- [ ] **Step 1: 按 Android 截图清单逐屏实现**（`docs/images/readme/` 为视觉基准）。
- [ ] **Step 2: 模拟器走查**：三分支状态保活（返回不闪现）、Dock 交互、Hero 转场、批量操作全链路、深浅色与强调色切换、中英切换。滚动流畅性/性能仅做功能走查，性能结论留给真机阶段（`deltas.md` 登记）。
- [ ] **Step 3: Commit** — `feat(ohos-native): reach UI parity for projects, records and capture forms`

---

### Task 7: 设置、备份恢复与诊断

**Files:**
- Create: `feature/settings/`（一级三分组 + 九个二级分区：水印默认值/定位/通知/备份恢复/存储/诊断/语言/外观/关于；关于页声明无网无账号 + 鸿蒙实际权限一致）
- Create: `feature/backup/`（创建备份：多选项目、是否含原图、处理中阻止、失败需明确选择“仅备份已完成记录”；项目 ZIP schema v5 + bundle v1 —— 由 Rust `export` 生成；恢复：picker 选 ZIP → 所有权令牌 → 暂存区 → 提交前失败回滚 DB+暂存+已规划目标 → 收尾中断下次启动清理）
- Create: `feature/diagnostics/`（诊断事件查看 + 导出诊断包；不落工程内容/照片/位置/文件标识）
- Create: `core/storage/StorageUsage.ets`（私有目录统计 + 清理本地导出）

- [ ] **Step 1: 失败测试**：备份阻止条件、恢复回滚两窗（`ownershipLost` / `templateSetMismatch` → 统一 `general` 文案）、旧版 ZIP v1–v4 恢复为空模板/进行中/未置顶。
- [ ] **Step 2: 实现并转绿**；跨端验证：鸿蒙备份 ZIP 在 Android v1.0.8 恢复成功，反之亦然（同编号跨项目 URI 不串）。
- [ ] **Step 3: Commit** — `feat(ohos-native): settings, backup restore and diagnostics parity`

---

### Task 8: 发布、CI 与上架

**Files:**
- Create: `.github/workflows/ohos-native.yml`（仅 `on: push/pull_request branches: [ohos-native]`；ubuntu 安装 command-line-tools → `ohpm install` → `hvigorw assembleHap` + codelinter；不碰 `main` 工作流）
- Create: `tool/ohos-native/build-hap.ps1`（release 签名构建 + 产物校验）
- Modify: `ohos-native/AppScope/app.json5`（versionName/VersionCode 与发布对齐）
- Create: `ohos-native/docs/deltas.md` 终版（后台处理/动态取色/相册删除授权/分享通道/真机验证挂起项等全部差异）
- Create: `tool/ohos-native/appgallery_checklist.md`（软著/名称、隐私政策 URL、ACL 受限权限申请、权限逐条用途、截图 2–5 张、降级声明、签名与包名校验）
- Modify: `README.md`、`docs/current-product-architecture.md`（增补鸿蒙原生章节：边界、差异表链接、下载入口）

- [ ] **Step 1: CI 绿**：`ohos-native` 分支 push 后 assembleHap + codelinter 通过。
- [ ] **Step 2: release 构建**：签名 HAP 产出（含 arm64 + x86_64 双架构），模拟器覆盖安装升级保留数据（真机覆盖升级留待真机阶段复验）。
- [ ] **Step 3: 模拟器手工回归总表全绿**（见下）后，AGC 材料齐备提交审核；材料中注明「功能对等已在模拟器验证，真机验证与云真机抽查待补」。
- [ ] **Step 4: Commit** — `feat(ohos-native): release build, ci and appgallery materials`

---

## 手工回归总表（Task 8 收口时一次跑完，DevEco NEXT 模拟器；真机阶段复跑同表）

| 项 | 期望 |
| --- | --- |
| 首启隐私门 | 未同意不进主界面、不申请任何权限；同意后持久生效 |
| 取消拍照 | 不占编号，无空记录，表单内容保留 |
| 连拍 | 编号递增且跨项目递增，同一时间只处理一张；三必填保留、备注清空 |
| 拒定位 | 仍出片，坐标空 |
| 拒相册（ACL） | SaveButton/选择器托底 + 「未进入系统相册」；差异表已登记 |
| 杀进程四窗 | 相机半截 / 队列未跑完 / 相册已写库未提交 / 日记与 DB 对账 —— 全部收敛到 `ready` 或可解释 `failed`，不丢编号 |
| 删除整条记录 | 按授权语义删相册照片；无授权时保留并提示（差异已声明） |
| 删除项目 | 不删相册照片、不删已导出备份 |
| 清理原图 | 成片、相册照片、记录保留；再生成要求原图在 |
| 再保存 | 非 `ready` 或成片缺失拒绝；成功重进相册 |
| 备份/恢复 | schema v5 与 v1–v4 都可恢复；同编号跨项目 URI 不串；恢复中断可收敛 |
| 跨端互备 | 鸿蒙 ZIP ↔ Android v1.0.8 互恢复成功 |
| 水印版式 | 与 Android v1.0.8 同字段成片逐块一致（或差异表登记降级） |
| 搜索/筛选/分页 | 多词 AND、日期 facets、50/页游标稳定、全选与全屏相邻复用同一查询 |
| 语言/主题 | 中英即时切换；深浅色与强调色正确 |
| 无网边界 | 全功能离线；仓库链接经外部浏览器打开 |

---

## 里程碑与“对等宣称”门槛

| 里程碑 | 内容 | 出口条件 |
| --- | --- | --- |
| M0 | Task 0 | 模拟器冷启动 + 五项探测落档（含 ABI / API 版本） |
| M1 | Task 1–2 | 骨架 + 数据层黄金向量全绿 |
| M2 | Task 3–4 | 拍摄链路模拟器闭环 + 引擎 `ok/degraded` 定级（模拟器验证级） |
| M3 | Task 5 | 相册/媒体语义模拟器闭环（ACL 或已声明托底，真机差异登记） |
| M4 | Task 6 | UI 逐屏对等模拟器走查通过 |
| M5 | Task 7 | 备份跨端互恢复通过 |
| M6 | Task 8 | 回归总表全绿 + AGC 材料齐 |

**模拟器对等验证（本计划出口）** = 模拟器回归总表全绿 ∧ 引擎版式对照 `ok`（模拟器渲染文件级对比）∧ `deltas.md` 覆盖全部模拟器边界差异。达成后可宣称「功能对等（模拟器验证级）」。

**真机对等确认（挂起前置，获得真机后执行）** = 同一回归总表在 NEXT 真机复跑全绿 ∧ ACL 真机授权行为确认（AGC 批复 + 直写生效）∧ 性能走查通过。在此之前**不得对外宣称真机全量对等**；发布说明必须标注「已在模拟器完成功能对等验证，真机验证待补」。任一降级（托底相册/降级水印/通知缺失/性能未知）→ 按差异表降级表述。

---

## Self-review

**覆盖检查：** v1.0.8 全部功能域（导航/拍摄/记录/检索/批量/水印/项目/设置/数据安全/体验）均已进矩阵或任务；产品边界（无网、无账号、系统相机、本机数据、卸载语义）以 Global Constraints 锁死；发布日记与相册替换语义继承 `8a6fe79`（XML 安全日记键 + 清理重试上限）与 v1.0.8 真实行为（原生不删、引用检查后删）；备份兼容 v1–v5 + bundle v1。

**路线决策依据：** `ohos` 分支实测（引擎长期 degraded、社区 Flutter 锁 3.27–3.32 无法追平主线、产品级契约未闭环）证明社区 Flutter 路线无法达到对等；原生 ArkTS + Rust 同源核心是对等性最强路径。本计划与用户环境对齐：无鸿蒙真机，全部验收在 DevEco NEXT 模拟器完成（该模拟器环境已在 `ohos` 分支 Task 0 验证可用），真机验证作为发布前置挂起。`ohos` 分支的设计资产（日记/会话/队列/隐私文案/AGC 清单）已全部吸收。

**占位符扫描：** 相机 picker 行为、NAPI 绑定方式、应用详情页 Want、分享通道、compatibleSdkVersion 下限、模拟器 ABI 与 API 版本六处标注「以 Task 0/3 实测为准」并规定落档 `probe.md`，未留双实现。

**类型一致性：** `SystemServices` 方法集与 main `PlatformServices` 一一对应；`PublishJpegOutcome` / `RecoveredPublishJournalEntry` / 枚举 index 语义与 Pigeon 约定一致；`ImagePipeline` 六方法与 `lib/platform/platform_services.dart` 现网接口同名同义。
