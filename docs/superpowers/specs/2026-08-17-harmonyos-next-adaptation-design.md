# SiteMark HarmonyOS NEXT 适配设计

## 目标

在 GitHub `origin/main` 最新发布 **SiteMark v1.0.8**（`847c74b`）之上，做一版 **HarmonyOS NEXT 原生 HAP**。第一期目标是与 Android v1.0.8 **产品语义全量对等**：同一套拍摄状态机、同一套编号与水印字段、同一套按 `captureId` 记账的相册替换 / 删除 / 杀进程恢复 / 备份恢复。

这不是把现有 APK 装到“兼容安卓”的老鸿蒙上。官方 Flutter 3.41.2 不支持鸿蒙；HAP 必须用 OpenHarmony 社区 Flutter fork 另编。

**全量对等只在两件事同时成立时才能对外宣称：**

1. 华为 AGC 批准受限相册权限，成片能进系统图库并按稳定 ID 精确替换。
2. 现有 Rust 水印 crate 能编出 `ohos-arm64` 并接到 FFI。

相册 ACL 批不下来时，用系统保存 picker / 应用沙箱托底，可发测试包，但必须在界面和发布说明里标明降级，不得标成与 v1.0.8 对等完成。Rust 编不过时允许临时降级出片，同样不得标对等。

## 已确认约束

| 项 | 决定 |
|---|---|
| 交付物 | HarmonyOS NEXT 原生 HAP，目标华为应用市场 |
| 对等范围 | 与 Android v1.0.8 全量对等（见上方硬条件） |
| 仓库 | 从 `v1.0.8` 拉长期 `ohos` 分支；`main` 继续官方 Flutter 3.41.2 |
| 相册 | 先申请 `READ/WRITE_IMAGEVIDEO` ACL；未批准前 picker / 沙箱托底 |
| Android 主线 | 不改产品语义，不把社区 Flutter / ohos 依赖打进 `main` |
| 不做 | 账号、联网、推送、自研相机、图库导入、iOS、折叠屏 / 多设备流转 |

## 范围

### 包含

- 长期 `ohos` 分支与 OHOS Flutter SDK 工程骨架（`ohos/`、签名、`module.json5`）。
- `sitemark_system_api` 的鸿蒙实现：系统相机 / 拍照 Ability、按需定位、相册发布、发布日记、按稳定 ID 删除、崩溃恢复。
- `BackgroundWorkClient` 的鸿蒙实现：串行队列、同 `captureId` 重试替换、启动对账。
- 现有 Rust 水印引擎的 `ohos-arm64` 适配；编不过时的显式降级通道。
- ohos 版插件补丁：`path_provider`、`shared_preferences`、`url_launcher`、`share_plus`、`package_info_plus`、`file_picker`、`sqlite3` / `drift_flutter`、通知（没有就关）。
- 首次启动隐私弹窗、按需权限文案、无网声明与实际上架材料。
- 与现网一致的 Dart 单测继续作为业务门禁；另增相册适配器、队列客户端单测和真机手工清单。

### 不包含

- 修改 `main` 以兼容社区 Flutter。
- 在页面或 `CaptureProcessor` 里写 `if (ohos)` 发图分支。
- 按文件名扫相册替换。
- 把 picker / 降级水印标成全量对等。
- 动态取色、本地通知若 ohos 插件缺失，第一期可关，但必须写入差异表。
- 应用市场审核通过本身（第 5 期完成条件是“材料齐、能提交”）。
- 用鸿蒙改 Android 的 MediaStore / WorkManager / Pigeon 生成器。

## 方案比较与选择

### 实现路线

1. **Flutter OHOS fork + 联邦插件（采用）**  
   Android 继续 3.41.2。鸿蒙用社区 Flutter（约 3.27–3.32）编 HAP。Dart UI、Riverpod、GoRouter、Drift、`CaptureWorkflow` / `CaptureProcessor` 复用。系统能力收在现有 `PlatformServices`，鸿蒙只换实现。  
   理由：产品内核已经把系统契约收口，重写 UI 浪费最大；双 SDK 可隔离在 `ohos` 分支。

2. 纯 ArkTS 重写，只借 Rust 水印  
   上架和权限最干净，但等于再做一款 App，会与 Android 迅速分叉。仅当第 0 期空壳 HAP 无法在 NEXT 真机启动时改评。

3. 现有 APK 跑在兼容安卓的老鸿蒙  
   快，但不是 NEXT，也上不了纯血应用市场。明确不做。

### 仓库

1. **长期 `ohos` 分支（采用）**  
   从 `origin/main` 的 v1.0.8 拉出。OHOS SDK、`ohos/`、插件补丁只存在该分支。`main` 的产品修复定期 cherry-pick 进来；禁止把 fork 补丁合回 `main`。

2. 同一 `main` 双平台  
   CI 和依赖冲突最高，否决。

3. 独立鸿蒙仓  
   隔离最好，双份业务最容易漂，否决。

### 相册

1. **ACL 优先 + picker / 沙箱托底（采用）**  
   有受限权限时走 `PhotoAccessHelper`，按稳定 ID 替换 / 删除。没有权限时走系统保存 picker 或应用沙箱，UI 必须显示“未进入系统相册”。

2. 第一期强制拿到 ACL 否则不算能发  
   审核不在开发可控范围，会把整期卡死。否决。

3. 不申请 ACL  
   做不到 MediaStore 级精确替换，与“全量对等”冲突。否决。

## 架构

Android 主线不动：`main` 继续官方 Flutter 3.41.2，发布 APK，契约仍是现有 Pigeon + Kotlin。

鸿蒙从 v1.0.8 的 `ohos` 分支用社区 Flutter 编 HAP。两边共享产品语义，不共享 SDK。

分层保持现网五层，只换最下面两层的实现：

| 层 | 鸿蒙做法 |
|---|---|
| Flutter 应用层 | 复用页面、Riverpod、GoRouter、中英文 |
| 数据层 | 继续 Drift；`drift_flutter` / `sqlite3` 换成 ohos 能编的实现 |
| 后台任务层 | 去掉 WorkManager，换成应用内串行队列 + 前台任务 / `WorkScheduler` |
| 系统集成层 | `sitemark_system_api` 增加 ArkTS / NAPI 实现 |
| 图像核心层 | 现有 Rust crate 编 `ohos-arm64`；编不过走显式降级 |

Dart 业务只认现有 `PlatformServices`，不改方法签名：

- `createCameraTarget` / `launchCamera` / `recoverCameraCapture` / `finishCameraCapture`
- 定位读写与申请、打开设置
- `publishJpeg(path, displayName, captureId, publishedUri)`：只替换这一条旧资源
- `recoverPublishJournals` / `clearPublishJournal(captureId, expectedContentUri)`
- `deletePublishedImage`、`inspectImage`

Android 仍走 Pigeon 生成的 Kotlin。鸿蒙用同名 method channel / NAPI，不把 Pigeon 的 Kotlin 生成器硬接到 ohos。

第 0 期是硬闸：空壳 HAP 在 NEXT 真机启动之前，不写业务。工具链走不通就停，改评纯 ArkTS。

## 组件

每个单元一件事，通过 `PlatformServices` 或 `BackgroundWorkClient` 对外，内部可换。

### `PlatformServices`

已有接口保持稳定。页面、工作流、处理器不写平台分支。

### `sitemark_system_api` 鸿蒙实现

拆成可单测的小策略，对齐现有 Kotlin 文件，避免单文件堆所有系统调用：

| 单元 | 职责 | 依赖 |
|---|---|---|
| 相机会话 | 建私有原图路径、调系统相机 / 拍照 Ability、写半截会话、恢复、结束 | 前台 Ability；无 Ability 时只允许恢复 / 清理 |
| 定位 | 读 / 申请权限、超时定位、打开设置 | 按需权限，启动时不扫权限 |
| 相册发布 | 把 JPEG 写入系统相册或 picker / 沙箱，返回稳定 ID + 被替换旧 ID | ACL 优先，否则托底 |
| 发布日记 | 进程死后对上「新图已进相册、库还没提交」 | 本地 Preferences / 文件，key 用 `captureId` |
| 删除 | 按稳定 ID 幂等删，不按照片名扫 | 无 ACL 时只能删自己沙箱 / 自己创建的资源 |
| 元数据 | 宽高、体积、MIME、可选 GPS | 读文件，不读整库 |

系统相机不能往应用私有路径写时：拍到临时 URI，再拷进 `originals/<id>.jpg`。对外仍是现有四个相机方法。

### 相册适配器

- `AclGalleryStore`：有 `READ/WRITE_IMAGEVIDEO` 时写系统相册，尽量做出 `Pictures/SiteMark`、按 URI 替换、卸载后日记可对账。
- `PickerFallbackStore`：无 ACL 时走系统保存 picker 或沙箱。返回值仍是发布结果，但带降级标记；UI 必须显示“未进入系统相册”。
- 选用哪个：启动时探测权限，不在业务层写 if。

**全量对等只在 ACL 批准后成立。** picker 是可发布的降级，不是对等完成。

### `BackgroundWorkClient` 鸿蒙实现

保留 `CaptureBackgroundScheduler` 的 `enqueue` / `retry` / `reconcilePending`。只替换 `WorkmanagerBackgroundWorkClient`：

- 一条串行链，同一时间只处理一张。
- 按 `captureId` 追加；同 ID 重试替换未跑完的那条。
- 启动时按库里 `captured` / `rendering` 对账。
- 进程被杀后靠前台任务或 `WorkScheduler` 拉起队列；拉不起来就下次进 App 对账，不能丢编号。

不把 `workmanager` 插件打进 ohos 依赖。

### 水印引擎

现有 Rust crate 是唯一完整引擎。鸿蒙必须编出 `ohos-arm64` 并接到 FRB 或等价 FFI。编不过时允许临时原生 / Dart 出片，记录必须标“降级水印”。完整引擎是全量对等的硬条件。

### 插件与 CI

ohos 插件补丁只存在 `ohos` 分支。该分支 CI 编 HAP；Android APK 仍以 `main` 的 3.41.2 为准。定期把 `main` 的产品修复 cherry-pick 进 `ohos`，反向合入禁止。

## 数据流

Dart 编排不改：`CaptureWorkflow` → 入队 → `CaptureProcessor` → `publishJpeg` → `markReady`。鸿蒙只替换相机、队列、相册、日记。

### 正常路径

1. 填表后 `createCameraTarget(captureId)` 在沙箱建 `originals/<id>.jpg` 占位，并写相机会话。
2. `launchCamera` 拉起系统相机 / 拍照 Ability。不能直写私有路径时先拍到临时 URI 再拷入。
3. 回前台：文件在且非空 → `markCaptured` → `finishCameraCapture(keep=true)` → `enqueue`。取消或空文件 → 清会话、删占位，不占编号。
4. 鸿蒙队列按 `captureId` 串行追加；同 ID 重试替换未跑完的那条。
5. `CaptureProcessor` 顺序与 Android 相同，不可重排：缺记录 → `ready` 短路 → 拒绝 `pendingCamera` → 尝试次数 +1 → 校验原图 / 时间 / 编号 → SHA-256 → `rendering` → 渲到 `rendered/<id>.jpg` → `publishJpeg` → `markReady` → 条件清除日记。
6. `publishJpeg`：有 ACL 时先落新图、写日记（新 ID + 待删旧 ID）、再删旧图；无 ACL 时走 picker / 沙箱，`supersededUris` 可为空。
7. `markReady` 成功后再 `clearPublishJournal(id, 本次URI)`。日记已被更新的发布覆盖则不许清。

定位失败不阻断出片，坐标为空。定位继续按需、可关。

### 杀进程窗口

| 死在哪 | 谁收 | 行为 |
|---|---|---|
| 相机已拍、Dart 未 `markCaptured` | `recoverCameraCapture` | 原图在就补记并入队；不在或空就丢会话 |
| 已 `captured` / `rendering`，未发布 | 启动 `reconcilePending` | 按库重入队，不另开并行链 |
| 相册已写入，Drift 未提交 | 原生发布日记 + `_recoverPublishJournals` | 按 **captureId** 对账，绝不按照片编号 |
| 已 `ready` 且 URI 已是日记里的新图 | 只清日记 | 提交已成功 |
| `ready` 仍指向被替换的旧 URI | CAS 采纳新 URI，旧 URI 进待删 | 提交没做成 |
| `ready` 已指向更新的另一张图 | 日记里的图当孤儿删，日记按条件清 | 禁止回滚 |
| 记录已删或 `failed` | 新图 + 旧图都进待删 | 幂等，已删当成功 |
| 仍是 `captured` / `rendering` | 日记先留着 | 处理器会再发并覆盖 |

删除、重新生成、再发布沿用现网规则：删要同时清库、原图、成片、系统侧那一条；重新生成必须原图还在；再发布只对 `ready` 且成片文件在。备份 ZIP 的 `captureId` / 编号语义不变，所以鸿蒙发布也必须按 `captureId` 记账。

## 错误处理

- **永久失败**：原图丢失、哈希对不上、缺拍摄时间 / 编号、记录或项目没了。标 `failed`，不再自动入队。
- **可重试**：写盘失败、相册 / picker 临时失败。尝试少于 3 次回队列。
- **队列登记失败**：返回 `delayed`，下次启动对账再入队，不当用户取消。
- **ACL 被拒**：自动切 picker / 沙箱，不把整次拍摄打成 `failed`。对等状态记在差异表，不记在 capture 失败码。
- 界面只显示稳定错误类别和下一步，不展示底层异常或平台字符串。
- 原始异常不进记录卡片、SnackBar 或诊断包对外文案。

明确禁止：按文件名扫相册；在页面里写 `if (ohos)` 发图；用“先发一张新的、旧的留着”冒充替换；把 picker 模式标成与 Android 全量对等。

## 分期与闸门

| 期 | 内容 | 过关 | 不过就停 |
|---|---|---|---|
| 0 工具链 | 独立 OHOS Flutter SDK，空壳 HAP | NEXT 真机启动 | 改评纯 ArkTS，不堆业务 |
| 1 骨架 | `ohos/`、联邦插件空实现、中英文资源 | 同仓 Dart 打出 HAP，进主界面；`main` APK 不回归 | 不接相机 |
| 2 系统契约 | 相机、定位、相机会话恢复、相册探测 | 真机「填表 → 拍 → 有记录」 | 不接完整队列 |
| 3 引擎 | Rust `ohos-arm64` + FFI | 版式与 Android 对得上 | 降级水印可测，但对等未完成 |
| 4 队列与数据 | 串行队列、日记对账、备份恢复、删除 / 再生成 / 再发布 | 杀进程后续跑；备份 ZIP 可恢复 | 不宣称对等 |
| 5 上架 | 隐私弹窗、权限话术、release HAP、AGC 材料 | 能提交应用市场 | 过审不是开发完成定义 |

## 差异表

| 项 | Android v1.0.8 | 鸿蒙第一期 | 能否称对等 |
|---|---|---|---|
| 相册写入 | MediaStore `Pictures/SiteMark` | ACL：`PhotoAccessHelper`；否则 picker / 沙箱 | 仅 ACL |
| 精确替换 | 只换本条 `publishedUri` | ACL 下按稳定 ID 做同样语义；picker 无旧系统图可换 | 仅 ACL |
| 卸载后对账 | MediaStore + 日记 | 视厂商是否保留应用创建的图 | 尽力，做不到就写进发布说明 |
| 后台 | WorkManager 链 | 前台任务 / WorkScheduler + 启动对账 | 用户可感知结果一致即可 |
| 通知 | 本地通知 | 插件没有就关 | 允许关，须标明 |
| 动态取色 | 有则用 | 插件没有就关 | 允许关，须标明 |
| 折叠屏 / 流转 | 无 | 无 | 不做 |
| 引擎 | Rust FRB | 必须同一套 crate | 编不过 ≠ 对等 |

## 测试与验收

### 完成定义

1. `ohos` 分支从 GitHub v1.0.8（`847c74b`）拉出；`main` 的 Android 3.41.2 发布线不被社区 Flutter 污染。
2. NEXT 真机 HAP：建项目 → 填表 → 系统相机 → 串行出片 → 进相册（ACL）或明确降级提示（picker）。
3. 水印字段与 Android 一致：工程部位、工作内容、拍摄人、时间、可选坐标；编号规则不变。
4. 杀进程恢复四窗都在：相机半截、队列未跑完、相册已写库未提交、日记与 Drift 对账（按 `captureId`）。
5. 删除 / 再生成 / 再发布 / 备份恢复语义与现网测试一致；不按文件名扫相册。
6. 首次启动隐私弹窗、按需权限、无网声明与实际一致；能打 release HAP 并提交应用市场。

### 自动化

沿用现有 Dart 单测（假平台即可）：`capture_processor`、`capture_workflow`、`capture_media_service`（日记恢复）、`capture_background_scheduler`、`app_startup_recovery`、备份导入。鸿蒙实现必须能被这些测试的 fake 语义套住，不另写一套业务状态机。

鸿蒙新增：

- 相册适配器：ACL 替换 / picker 降级 / 条件清日记 / 按 ID 不按文件名。
- 队列客户端：串行、同 ID 重试替换、启动对账。

`ohos` 分支不负责证明 Android APK。Android 仍以 `main` CI 为准。cherry-pick 进 `ohos` 后只跑鸿蒙相关测试。

### 真机手工清单

- 取消拍照不占号。
- 连拍编号不乱，同一时间只处理一张。
- 杀进程四窗都能收敛。
- 拒绝定位仍出片。
- 拒绝相册走 picker，且文案写明未进系统相册。
- 备份 ZIP 可在鸿蒙侧恢复；恢复后同编号跨项目不得串 URI。
- 删记录后，ACL 下系统图消失，picker 下沙箱文件消失。

## 风险

1. OHOS Flutter 与 3.41.2 双工具链，插件版本对不齐。第 0 期不过就改评 ArkTS。
2. 相册受限权限批不下来。产品可发，但对等未完成。
3. `flutter_rust_bridge` + `sqlite3` 在 ohos 上编不过。完整引擎是对等硬条件。
4. 没有 WorkManager，杀进程恢复和编号串行要自己做。
5. 上架还要软著、隐私政策、权限话术，和技术完成不是同一件事。
