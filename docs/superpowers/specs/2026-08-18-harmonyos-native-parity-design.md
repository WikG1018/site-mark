# SiteMark 鸿蒙原生（ArkTS）从零到对齐设计规划

> **配套实施计划：** [`docs/superpowers/plans/2026-08-18-harmonyos-native-parity.md`](../plans/2026-08-18-harmonyos-native-parity.md)
>
> **产品语义源（不得另写一套）：** `docs/current-product-architecture.md`、`docs/record-watermark-settings.md`、`docs/capture-processing-storage.md`，均以 GitHub `origin/main` **v1.0.8 / `abc0164`** 为准。
>
> **状态：** 已落地鸿蒙原生模拟器验证版（2026-08-20）。Stage + ArkTS/ArkUI、RelationalStore、系统适配、共享 Rust N-API、备份恢复与主要页面已实现；33 项 ArkTS 测试与 debug HAP 构建通过。未配置发布签名，HarmonyOS NEXT 真机相机、相册授权与性能仍是挂起项，不宣称真机全量对等。
>
> **分支结论：** 实现在 `agent/ohos-native` 隔离分支完成，PR #73 已合入长期 `ohos-native` 分支；`main` 与独立的 `ohos` 分支均未改动。后续原生鸿蒙 PR 继续以 `ohos-native` 为目标分支。

## 目标

在 SiteMark Android v1.0.8（`abc0164`）功能基线上，**从零**用原生 ArkTS / Stage 模型做一款独立鸿蒙应用，交付在 DevEco Studio NEXT **模拟器**上完整验证的可复现 HAP 构建（产物同时包含 arm64 + x86_64 双架构）。发布签名及真机转正不伪装为已完成。

产品语义与 Android v1.0.8 **对齐到模拟器验证级**：同一套拍摄状态机、同一套编号与水印字段、同一套按 `captureId` 记账的相册发布 / 引用检查删除 / 杀进程恢复 / 备份恢复。图像核心复用仓库根 `rust/` 的 `sitemark_core`，保证 EXIF、SHA-256、全分辨率水印、CSV/JSON/ZIP 与 Android **同源同算法**。

这不是把现有 APK 装到兼容安卓的老鸿蒙上，也不是继续推进社区 Flutter `ohos` 分支。官方 Flutter 3.41.x 不支持鸿蒙；社区 fork 已实测无法追平主线。

**对等宣称拆两级，不得混用：**

1. **模拟器对等验证（本规划出口）** = 模拟器回归总表全绿 ∧ 引擎版式对照 `ok`（文件级对比）∧ `ohos-native/docs/deltas.md` 覆盖全部模拟器边界差异。达成后可宣称「功能对等（模拟器验证级）」。
2. **真机对等确认（挂起前置）** = 同一回归总表在 NEXT 真机复跑全绿 ∧ 系统相册确认面板行为确认 ∧ 性能走查通过。获得真机之前**不得对外宣称真机全量对等**。

任一降级（托底相册、降级水印、通知缺失、性能未知）必须写入差异表并在发布说明标注，不得 silently 假装对等。

## 已确认约束

| 项 | 决定 |
| --- | --- |
| 交付物 | HarmonyOS 原生 HAP（Stage + ArkTS），目标华为应用市场；第一期验收环境是 DevEco NEXT 模拟器 |
| 对等范围 | 与 Android v1.0.8 对齐到模拟器验证级；真机全量对等挂起 |
| 基线提交 | `origin/main` v1.0.8 / `abc0164` |
| 仓库 | `ohos-native/` 原生工程与 Android 同仓维护；原生鸿蒙 PR 合入长期 `ohos-native` 分支，`main` 与历史 `ohos` 分支不动 |
| 规范锚点 | HarmonyOS 6.1.1（API 24）+ DevEco 6.1.1.300；`targetSdkVersion 6.1.1(24)`；`compatibleSdkVersion` 初值 `5.0.5(17)` |
| 相册 | 后台只生成应用私有水印成片；用户在详情页主动保存时调用 `PhotoAccessHelper.showAssetsCreationDialog`，不声明广泛媒体读写权限 |
| Android 主线 | 不改 `lib/`、`android/`、`pigeons/`、`release.yml`；只扩展共享 Rust feature 与 CI 静态/回归门禁 |
| 验收环境 | 无鸿蒙真机。Task 0 与全部里程碑在模拟器执行。模拟器相机不可用时允许 **debug-only JPEG 注入**（release 剥离） |
| 不做 | 账号、联网、推送、自研相机、图库导入、iOS、折叠屏 / 多设备流转、FA 模型、把 picker / 降级水印标成全量对等 |

## 范围

### 包含

- 从 `abc0164` 拉出的隔离实现分支与 Stage 工程（`ohos-native/`、签名占位、`module.json5`），验收后通过 PR 合入长期 `ohos-native` 分支。
- 单 entry 模块化分层：`domain`（纯逻辑 / 实体）、`data`（RDB + preferences）、`core`（系统桥 + 图像管线）、`feature`（页面与工作流）。
- ArkTS 版 `SystemServices`：方法集与 `lib/platform/platform_services.dart` 的 `PlatformServices` **同名同义**（相机 / 定位 / publishJpeg / 日记 / 删除 / 设置页 / inspectImage）。
- 应用内存活期串行队列 + 启动 `reconcilePending`；`workScheduler` 仅延迟拉起，不承诺被杀后继续。
- 同一 `sitemark_core` crate 交叉编译双目标（`x86_64-unknown-linux-ohos` + `aarch64-unknown-linux-ohos`），经 NAPI / C ABI 接入；初始化失败走显式 `DegradedPipeline`。
- RelationalStore 业务字段对齐 Drift schema v11，鸿蒙内部 schema 14 另含私有文件/媒体清理和恢复所有权状态；preferences 保存设置 / 发布日记 / 相机会话 / 隐私同意 / 恢复日记。
- 首启隐私同意门（文案继承 `ohos` 分支定稿）、按需权限 reason、无网声明与 AGC 材料。
- hypium 先红后绿：Dart 黄金向量全量移植；模拟器手工回归总表（真机复跑为挂起前置）。
- `ohos-native/docs/deltas.md` 作为预声明差异与实测差异的唯一登记处。

### 不包含

- 修改 `main` 以兼容社区 Flutter 或鸿蒙工具链。
- 修改、合并或替另一位 Agent 决定 `ohos` 分支（社区 Flutter 适配线）的去留；本 PR 只维护 `ohos-native/`。
- 在业务层按平台写第二套状态机、第二套编号规则或按文件名扫相册。
- 把 SaveButton / picker / 降级水印 / 模拟器通过标成真机全量对等。
- 申请 `ohos.permission.INTERNET` 或 `CAMERA`（系统相机替拍；debug 注入不是相机）。
- 用长时任务伪装后台，假装具备 WorkManager 被杀后续跑能力。
- 动态取色（Monet）等价实现。
- 应用市场审核通过本身（Task 8 完成条件是「材料齐、能提交」；材料须注明真机待补）。
- 用鸿蒙改 Android 的 MediaStore / WorkManager / Pigeon 生成器。

## 方案比较与选择

### 实现路线

1. **原生 ArkTS + 同源 Rust 核心（采用）**
   UI / 导航 / 数据 / 系统集成全部用 Stage + ArkTS 重写；图像与归档算法不重写，交叉编译现有 `sitemark_core`。
   理由：原生路线能直接遵循 Stage、ArkUI 与系统权限模型；对等性由「契约镜像 + 同源算法 + 黄金向量」约束，而不是依赖另一条 Flutter 适配线的页面实现。

2. 在本任务继续修改社区 Flutter `ohos` 分支
   分支由另一项工作独立负责，本任务不触碰也不评价其最终去留。

3. 现有 APK 跑在兼容安卓的老鸿蒙
   快，但不是 NEXT，也上不了纯血应用市场。明确不做。

### 仓库

1. **同仓隔离实现分支，完成后 PR 合入长期 `ohos-native`（实际采用）**
   从 `abc0164` 拉出 `agent/ohos-native`，所有原生代码位于 `ohos-native/`；PR #73 验收后合入长期 `ohos-native` 分支。`main` 与独立 `ohos` 分支不参与本 PR。

2. 直接在 `main` 开发
   难以隔离大规模新增代码，否决；最终合入不等于直接开发。

3. 独立鸿蒙仓
   隔离最好，双份业务与 Rust FFI 最容易漂，否决。同仓共享 `rust/` 与产品文档。

### 验收环境

1. **DevEco NEXT 模拟器为唯一验收环境（采用）**
   当前无鸿蒙真机。`ohos` 分支 Task 0 已证明本机模拟器（`SiteMarkPhone602`，OpenHarmony 6.0.2.130 / API 22）可用。本规划全部里程碑在模拟器闭环；真机验证挂起。

2. 真机硬闸才算完成
   与用户环境冲突，否决。

3. 云真机替代本地模拟器
   可作为日后抽查，不作为本规划出口。

### 相册

1. **私有成片 + 用户主动系统保存面板（实际采用）**
   后台队列只完成应用私有成片，确保相机返回后可以继续连拍。用户在详情页点击“保存到相册”时调用 `PhotoAccessHelper.showAssetsCreationDialog`，允许后记录系统返回 URI；取消或拒绝不改变成片 `ready` 状态。manifest 不申请广泛媒体读写权限。

2. 第一期强制拿到 ACL 否则不算能发
   审核与真机授权不在本规划可控范围，会把整期卡死。否决。

3. 申请广泛媒体 ACL 并在后台直写
   受限权限审核与需要交互的系统语义会阻塞连拍，也扩大隐私权限面；第一版不采用。

### 图像核心绑定

1. **同一 crate + 新增 C ABI JSON FFI，不动 FRB（采用）**
   FRB 是 Dart 绑定，不能用于 ArkTS。在 `rust/src/ffi/` 增加 `extern "C"` JSON-in/JSON-out 薄层，参数 / 返回与 `lib/src/rust/api/image_core.dart` 对齐。NAPI 用 napi-rs ohos 目标或 C++ 薄封装，以 Task 3 实测为准，写入 `probe.md`。

2. 把 FRB 接到鸿蒙
   无官方路径，否决。

3. ArkTS / ImageKit 重写水印
   版式与哈希必然分叉，否决。

### 模拟器相机

1. **系统相机优先 + debug-only JPEG 注入（采用）**
   `cameraPicker.pick()` 为产品路径。模拟器虚拟相机不可用或不可控时，debug 构建允许把内置测试 JPEG 写入 `originals/`，驱动完整状态机。运行时由 `applicationInfo.debug` 保护，release 不进入该通道，也不构成自研相机。

2. 自研相机预览填补模拟器缺口
   违反产品边界，否决。

## 架构

`main` 继续用官方 Flutter 3.41.x 发布 APK，Android 产品代码仍采用 Pigeon + Kotlin + WorkManager + MediaStore；本工作只扩展共享 Rust 核心和 CI 门禁，不改 Android 业务/UI。

`ohos-native` 从 v1.0.8 拉出，用原生 ArkTS 编 HAP。两边共享产品语义与 Rust 算法，不共享 UI SDK，不共享数据库文件（数据经备份 ZIP 迁移）。

分层对照：

| Android 层（v1.0.8） | 鸿蒙原生对应 | 对等锁 |
| --- | --- | --- |
| Flutter 应用层（Material 3 / Riverpod / GoRouter） | ArkUI `Navigation` + `NavPathStack` + 根部悬浮 Dock；feature HSP | 文案全量搬运；逐屏走查；无 Monet |
| Drift schema v11 | `@ohos.data.relationalStore` 同表同列同索引 | 黄金向量 + 游标分页测试 |
| SharedPreferences | `@ohos.data.preferences` | 日记键布局照搬 |
| WorkManager 串行链 | 应用内串行队列 + 启动 reconcile | 用户可感知结果一致；被杀后暂停须预声明 |
| Pigeon + Kotlin `PlatformServices` | ArkTS `SystemServices` 同名方法集 | 枚举 index 与 outcome 结构一致 |
| Rust + FRB | 同一 crate + C ABI / NAPI | sha256 同文件一致；ZIP 可被 Android 恢复 |

规范基线：

| 项 | 取值 |
| --- | --- |
| 操作系统 | HarmonyOS 6.1.1（API 24 Release）；HarmonyOS 7 / API 26 Beta1 仅预检 |
| IDE | DevEco Studio 6.1.1.300 + 内置 SDK |
| 模型 / 语言 | Stage；ArkTS 严格模式 + ArkUI；禁止 FA |
| 构建 | hvigor + ohpm |
| 测试 | hypium + 模拟器手工回归总表 |

`compatibleSdkVersion` 初值 `5.0.5(17)`（下限不低于 `5.0.0(12)`）。无真机流量矩阵，暂不校准，登记 `deltas.md`。模拟器实际 API 可能仍是 22（现有 `SiteMarkPhone602`）；API 24 特性若镜像不支持，按 Task 0 探测结论降级验证并落档。

## 组件

每个单元一件事。页面与工作流只认 `SystemServices` / `ImagePipeline` / DAO，不写 Kit 分支。

### `SystemServices`

ArkTS 对 `PlatformServices` 的镜像。方法集保持稳定，禁止增删改名：

- `createCameraTarget` / `launchCamera` / `recoverCameraCapture` / `finishCameraCapture`
- `requestCurrentLocation` / `getLocationPermissionState` / `requestLocationPermission` / `openApplicationSettings`
- `publishJpeg(sourcePath, displayName, captureId, publishedUri)` → `PublishJpegOutcome(contentUri, supersededUris)`
- `recoverPublishJournals` / `clearPublishJournal(captureId, expectedContentUri)`
- `deletePublishedImage` / `inspectImage`

内部拆成可单测的小策略：

| 单元 | 职责 | 约束 |
| --- | --- | --- |
| `CameraBridge` | `cameraPicker.pick()`；不能直写沙箱时先落临时 URI 再拷到 `originals/<captureId>.jpg` | 取消 / 失败语义 0 captured / 1 cancelled / 2 failed；无 CAMERA 权限 |
| `CaptureSessionStore` | preferences 持久 `capture_id` / `capture_path`，commit 语义 | 判定 `exists && length > 0`，对齐 Android `CaptureTargetPolicy` |
| `LocationBridge` | `geoLocationManager.getCurrentLocation` + `LOCATION` / `APPROXIMATELY_LOCATION` | 超时 / 拒权 / 服务关闭映射 `LocationOutcome` 同枚举；拒权不阻断出片 |
| `HarmonySystemServices.saveJpegToAlbum` | 用户主动调用系统保存面板 | 允许后返回系统 URI；取消/拒绝不破坏私有成片 |
| `PublishJournalStore` | `record` / `peek` / `recover` / `clear` | 键 `journal.<base64url(id)>.exists/newUri/staleCount/stale.<i>`；record 失败 → 整次 publish 失败 |
| `MediaCleanup` | 对 `supersededUris` 做全库引用检查后再删 | 已不存在当成功；删除需用户授权确认；拒绝则保留并登记差异 |
| 设置跳转 | `startAbility` 打开应用详情 | Want action 以 Task 0 实测为准 |

### `ImagePipeline`

```text
interface ImagePipeline {
  isDegraded: boolean
  render(...)
  export(...)
  exportSelection(...)
  readProjectArchive(...)
  extractArchivePhoto(...)
  sha256(...)
}
```

- 正常实现：`taskpool` 调 Rust FFI，只传路径与结构化参数，全分辨率字节不过 ArkTS 主线程。
- `DegradedPipeline`：`isDegraded=true`；复制原图 + 纯文本水印；错误带 `invalid_data:` 前缀。UI / 诊断必须可见降级标记。
- 双 ABI：`.so` 同时产出 `x86_64`（模拟器，以 Task 0 实测 ABI 为准）与 `arm64-v8a`（真机就绪）。构建脚本拷贝到 `entry/libs/`，不入 LFS。

### 数据层

- RelationalStore 新装直接建 schema v11：`projects` / `captures` / `capture_templates` / `app_settings`，游标索引 `(sortTime, id)`，级联删除。不迁移 Flutter 数据库文件。
- 编号分配在单事务内取当日最大序号 +1（跨项目递增）。文件名 `{安全化项目名称}-SM-{yyyyMMdd}-{全应用当日序号}.jpg`。
- 规范化：`trim` + `\s+` 折叠、`name_key` 仅小写 ASCII `A-Z`、长度按 Unicode 标量、拒绝 U+0000。纯逻辑落在 `commons/utils` HAR，供 hypium 单测。
- 查询：50/页游标、多词 AND、日期 facets、全选与全屏相邻复用同一查询。
- 模板每项目最多 100；不含备注。

### 导航与体验

- 根部三分支（项目 / 全部记录 / 设置）用 `Navigation` + 自定义 Tabs；仅当前分支绘制，返回不闪现。
- Dock 选中背景覆盖图标 + 文字；二级页隐藏 Dock。
- 主题：ArkUI tokens + `resources/dark` + 固定强调色板（与 Android `accent_swatches.dart` 一致）。无 Monet，预声明。
- 语言：`resources/base`（en）+ `resources/zh_CN`；`i18n.System.setAppLanguage` 即时生效。文案从 `lib/l10n/app_strings.dart` 全量搬运。
- Hero：`sharedTransition` + 玻璃材质，视觉近似即可。
- PixelMap 列表缩略缓存上限约 40 张 / 32MB，`onMemoryLevel` 清理。滚动性能结论留给真机阶段。

### 隐私门

`PrivacyConsentGate`：未同意只显示说明 +「同意并继续」+「退出」；退出 `terminateSelf()`；未同意不进主界面、不申请任何权限。键 `privacy_consent_accepted_v1`。文案原样继承 `ohos` 分支。

### 从 `ohos` 分支继承、不再重评的设计结论

- 发布日记按 `captureId`，不用编号 / 文件名当相册键。
- `clearPublishJournal` 必须条件清除（期望 URI 匹配才清）。
- 原生侧不删相册行；删除由业务层引用检查后执行。
- 串行队列：同 `captureId` 未执行可替换，进程内一次一张。
- 隐私弹窗文案与 AGC 清单结构。

## 数据流

编排顺序与 Android 相同，不可重排。鸿蒙只替换相机、队列、相册、日记的实现。

### 正常路径

1. 用户填表。项目必须存在且生命周期为 `active`，否则不启动相机（只读异常转用户可读提示）。
2. 若定位已授权，同时发起一次前台定位，不等待结果。
3. `createCameraTarget(captureId)` 在沙箱建 `originals/<id>.jpg` 占位（`captureId` 校验 `^[A-Za-z0-9][A-Za-z0-9_-]{0,95}$`），并 commit 相机会话。
4. `launchCamera` 拉起系统相机。模拟器相机不可用时，debug 构建走注入通道写入同一路径，对外仍是四个相机方法。
5. 回前台：文件在且非空 → 分配编号 → `captured` → `finishCameraCapture(keep=true)` → `enqueue`。取消或空文件 → 清会话、删占位，**不占编号、不创建可见记录**。
6. 队列按 `captureId` 串行；同 ID 重试替换未跑完的那条。
7. 处理器顺序固定：缺记录 → `ready` 短路 → 拒绝 `pendingCamera` → 尝试次数 +1 → 校验原图 / 时间 / 编号 → SHA-256 → `rendering` → 渲到 `renders/<id>.jpg` → `markReady`。后台不弹系统相册面板。
8. 用户主动保存：系统面板落新图 → **同步**写日记 → 返回 `(contentUri, supersededUris)` → DB 以 CAS 提交新 URI并同事务入队旧 URI 清理。
9. 业务提交 DB 后 `clearPublishJournal(id, contentUri)`。日记已被更新的保存覆盖则不许清。
10. 删除走 `MediaCleanup`：全库无引用才请求系统删除；用户拒绝授权则保留相册照片并提示。

定位失败不阻断出片，坐标为空。连拍保留三必填、清空备注。通知 best-effort，失败吞掉。

### 杀进程四窗

| 死在哪 | 谁收 | 行为 |
| --- | --- | --- |
| 相机已拍、业务未 `markCaptured` | `recoverCameraCapture` | 原图在就补记并入队；不在或空就丢会话 |
| 已 `captured` / `rendering`，未发布 | 启动 `reconcilePending` | 按库重入队，不另开并行链 |
| 相册已写入，RDB 未提交 | 发布日记 + 启动对账 | 按 **captureId** 对账，绝不按编号 |
| 已 `ready` 且 URI 已是日记里的新图 | 只清日记 | 提交已成功 |
| `ready` 仍指向被替换的旧 URI | CAS 采纳新 URI，旧 URI 进待删 | 提交没做成 |
| `ready` 已指向更新的另一张图 | 日记里的图当孤儿进待删，日记按条件清 | 禁止回滚 |
| 记录已删或 `failed` | 新图 + 旧图都进待删 | 幂等，已删当成功 |
| 仍是 `captured` / `rendering` | 日记先留着 | 处理器会再发并覆盖 |

与 Android WorkManager 的差异必须预声明：应用被杀后处理**暂停**，下次启动收敛；不使用长时任务伪装后台。用户可感知结果（最终 `ready` / 可解释 `failed`、编号不丢）必须一致。

### 三类照片与操作

| 数据 | 鸿蒙位置 | 卸载 |
| --- | --- | --- |
| 私有原图 | 沙箱 `originals/` | 删除 |
| 私有水印图 | 沙箱 `renders/` | 删除 |
| 已发布水印图 | 用户经系统确认面板保存到系统相册 | 通常保留，删除仍受系统确认与授权约束 |

| 操作 | 原图 | 成片 | 相册 | 记录 |
| --- | --- | --- | --- | --- |
| 清理原图 | 删 | 留 | 留 | 留（编号 / SHA-256 留） |
| 再保存 | 不变 | 读 | 新建 | 更新 URI；非 `ready` 或成片缺失拒绝 |
| 删除整条记录 | 删 | 删 | 引用检查后按授权删 | 删 |
| 删除项目 | 随级联删 | 随级联删 | **不删** | 级联删；已导出备份不删 |
| 重新生成 | 必须在 | 覆盖 | 覆盖（经 publish 日记） | 不可变证据字段保留 |

### 备份与恢复

- 创建：多选项目、是否含原图；`pendingCamera` / `captured` / `rendering` 阻止；`failed` 需明确选择「仅备份已完成记录」。
- 产物由 Rust `export` 生成：项目 ZIP schema v5 + 多项目 bundle v1；兼容恢复 v1/v2/v3/v4（空模板 / 进行中 / 未置顶）。
- 恢复：picker 选 ZIP → 所有权令牌 → 暂存区 → 提交前失败回滚 DB + 暂存 + 已规划目标 → 收尾中断下次启动清理。
- `ownershipLost` / `templateSetMismatch` 对内区分，对外统一 `general`。
- 恢复成片不自动进系统相册，需要时「再次保存」。
- 所选记录分享 ZIP 不能恢复。
- 跨端硬条件：鸿蒙 ZIP ↔ Android v1.0.8 互恢复成功；同编号跨项目 URI 不串。

### 存储与诊断

- 存储统计只算沙箱（originals / renders / exports / db / docs），不含系统相册。
- 清理本地导出只删沙箱 `exports`。
- 诊断：固定结果分类 / 数量 / 耗时；不落工程内容、照片、位置、文件标识、原始异常。经 `DocumentViewPicker` 导出，不上传。

## 错误处理

- **永久失败**：原图丢失、哈希对不上、缺拍摄时间 / 编号、记录或项目没了。标 `failed`，不再自动入队。
- **可重试**：写盘失败、相册 / picker 临时失败。尝试少于 3 次回队列。
- **队列登记失败**：返回 `delayed`，下次启动对账，不当用户取消。
- **相册面板取消/拒绝**：保留 `ready` 私有成片和原有相册 URI，不把拍摄打成 `failed`。
- **Rust 初始化失败**：切 `DegradedPipeline`，UI / 诊断可见；不得标引擎对等。
- 界面只显示稳定错误类别和下一步。禁止在记录卡片、Toast、诊断包对外文案暴露原始异常或平台字符串。

明确禁止：按文件名扫相册；用「先发一张新的、旧的留着」冒充替换；把托底模式或模拟器通过标成真机全量对等；debug 注入残留到 release。

## 分期与闸门

实施步骤、checkbox 与提交信息以配套计划为准。本规划只锁分期含义与停手条件。

| 里程碑 | 计划任务 | 过关 | 不过就停 |
| --- | --- | --- | --- |
| M0 | Task 0 | 模拟器冷启动 + 五项探测落档（相机 picker、相册直写、删除授权、应用详情 Want、openLink / DocumentViewPicker）+ ABI / API 版本 | 不堆业务；失败写入 `probe.md` 后向用户汇报 |
| M1 | Task 1–2 | 骨架 + 隐私门 + 主题 / 语言；schema v11 黄金向量全绿 | 不接相机 |
| M2 | Task 3–4 | 拍摄链路模拟器闭环；引擎 `ok` / `degraded` 定级（模拟器验证级） | 引擎 `degraded` 可继续开发，但对等未完成 |
| M3 | Task 5 | 私有成片 + 用户主动系统保存面板闭环 | 不宣称真机相册对等 |
| M4 | Task 6 | UI 逐屏对等模拟器走查通过 | 性能结论不在本闸 |
| M5 | Task 7 | 备份跨端互恢复通过 | 不宣称数据对等 |
| M6 | Task 8 | 回归总表全绿 + CI assembleHap + AGC 材料齐（注明真机待补） | 过审不是开发完成定义 |

占位符只允许这六处，且必须在 Task 0 / 3 实测后落入 `probe.md`，不得长期双实现：相机 picker 行为、NAPI 绑定方式、应用详情 Want、分享通道、`compatibleSdkVersion` 下限、模拟器 ABI 与 API 版本。

## 差异表（规划预声明）

实测差异追加到 `ohos-native/docs/deltas.md`，不得只改本表。

| 项 | Android v1.0.8 | 鸿蒙原生（本规划） | 能否称对等 |
| --- | --- | --- | --- |
| 相册写入 | MediaStore `Pictures/SiteMark` | 详情页主动调用 `PhotoAccessHelper` 系统确认面板 | 模拟器已验证允许路径；真机需复验允许/拒绝/重复保存 |
| 精确替换 / 删除 | 原生不删，业务引用检查后删 | 同语义；删除另需系统确认弹窗 | 授权拒绝须声明 |
| 卸载后对账 | MediaStore + 日记 | 视系统是否保留应用创建的图 | 尽力，做不到写进发布说明 |
| 后台 | WorkManager 链，被杀后可被拉起 | 应用内队列，被杀后暂停，下次启动收敛 | 用户可感知结果一致即可；机制差异必须声明 |
| 通知 | Android 13+ best-effort | NotificationKit best-effort | 允许缺失，须标明 |
| 动态取色 | Monet 可用则用 | 仅手动强调色 | 允许关，须标明 |
| 相机 | 系统 / 厂商相机 | `cameraPicker`；模拟器可 debug 注入 | 注入不是产品能力 |
| 引擎 | Rust FRB | 同一 crate + NAPI | 文件级对照 `ok` 才称引擎对等 |
| 主题 / 动效 | Material 3 + Hero | ArkUI tokens + `sharedTransition` | 视觉近似 |
| 验收环境 | 真机 + 模拟器 | 本规划仅模拟器 | 不得宣称真机全量对等 |
| 折叠屏 / 流转 | 无 | 无 | 不做 |

## 测试与验收

### 完成定义（模拟器验证级）

1. `ohos-native` 从 GitHub v1.0.8（`abc0164`）拉出；`main` 的 Android 发布线不被鸿蒙工程污染。
2. DevEco NEXT 模拟器 HAP：首启隐私门 → 建项目 → 填表 → 系统相机或 debug 注入 → 串行生成私有成片 → 详情页主动保存到系统相册。
3. 水印字段与 Android 一致：工程部位、工作内容、拍摄人、时间、可选坐标；编号规则不变；版式文件级对照 `ok` 或差异表登记降级。
4. 杀进程四窗都在：相机半截、队列未跑完、相册已写库未提交、日记与 RDB 对账（按 `captureId`）。
5. 删除 / 再生成 / 再发布 / 清理原图 / 备份恢复语义与现网一致；不按文件名扫相册。
6. 鸿蒙 ZIP ↔ Android v1.0.8 互恢复成功；同编号跨项目 URI 不串。
7. 首次启动隐私门、按需权限、无网声明与实际一致；能打双架构 release HAP；AGC 材料齐且注明真机待补。
8. `deltas.md` 覆盖后台、取色、相册删除授权、分享通道、模拟器 ABI / API、真机挂起项。

### 自动化

- 移植 Android/Dart 黄金向量为 hypium：`capture_display_name`、`photo_number`、`capture_template_rules`、`project_name`、`capture_status`、`capture_list_query`。
- 日记四例：round-trip / 条件 clear / 同 ID 折叠 / 敌意 ID 键安全。
- 相册适配器三例：不扫文件名、原生不删、托底不宣称对等。
- 队列：串行、同 ID 替换未执行项、启动对账、状态机全转移。
- 备份：阻止条件、回滚两窗、旧版 ZIP v1–v4。
- 纯逻辑必须落在 `commons/*` HAR。所有行为变更先写失败测试再实现。
- Task 0 用模拟器冷启动验收，不编造单测替代表。
- `ohos-native` 分支 CI 只编 HAP + codelinter，不证明 Android APK。

### 模拟器手工回归总表

与实施计划「手工回归总表」同一张表，Task 8 收口时一次跑完；真机阶段复跑同表。相机步允许 debug 注入，须在记录中标注。

### 真机阶段（挂起，不阻塞本规划出口）

获得真机后另开前置，不改写本规划的模拟器完成定义：

- 复跑回归总表。
- 确认系统相册保存面板在允许、拒绝、重复保存和删除时的真机行为。
- 性能 / 流畅性、传感器实况、厂商相机差异、通知通道实况。
- 覆盖安装升级保留数据。

## 风险

1. 模拟器镜像停在 API 22，部分 API 24 Kit 行为与生产不一致。Task 0 必须落档实际 API，并决定哪些特性降级验证。
2. 模拟器 ABI 不是 arm64。Rust 必须双目标；只编 arm64 会在模拟器上重蹈 `ohos` 分支 `degraded`。
3. `cameraPicker` 在模拟器上不可用。debug 注入可走通状态机，但不能替代真机厂商相机差异。
4. AGC 不受理或不受理模拟器证据。产品可按差异表降级提交，真机对等未完成。
5. napi-rs ohos 目标或 C ABI 绑定失败。允许 `DegradedPipeline` 继续开发，引擎对等未完成。
6. 没有 WorkManager，编号串行与四窗收敛必须自测；机制差异必须写进发布说明。
7. 上架还要软著、隐私政策、权限话术，和技术完成不是同一件事。
8. `main` 持续演进。`ohos-native` 只收 cherry-pick，避免双主线互相污染。

## 文档维护

- 改变权限、数据生命周期、拍摄状态机、导出可恢复性或技术分层时，同步更新本文件、配套实施计划，并在实现落地后更新 `docs/current-product-architecture.md` 与 `docs/decision-records.md`（仅在 `ohos-native` 或经批准合入 `main` 的文档提交中进行）。
- `ohos` 分支的 `2026-08-17` Flutter 适配规格与计划保留作历史，路线已被本规划取代。
- 实现过程中的探测结论写入 `tool/ohos-native/probe.md`；差异只登记 `ohos-native/docs/deltas.md`。
