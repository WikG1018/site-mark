# SiteMark 当前产品边界与总体架构

> 状态：Android v1.0.17 当前设计 + HarmonyOS NEXT 原生（native-v1.0.9）+ iOS Flutter 复用（签名待补）
> 适用版本：Android v1.0.17；HarmonyOS native 1.0.9；iOS Phase 0–3、5–8 已落地，Phase 4 待 Apple Developer 账号
> 本文描述已落地的产品边界；阶段性计划保留在 `docs/superpowers/` 供追溯。

## 1. 产品定位

SiteMark（工程印记）是面向工程现场记录的水印相机。应用负责项目、
现场信息、记录管理和水印处理，实际拍照交给手机系统或厂商相机完成。
产品线见第 9 节（HarmonyOS NEXT 原生）与第 10 节（iOS，Flutter 复用）。

当前产品边界：

- Android 12（API 31）及以上；界面支持简体中文和英文；
- 发布 APK 无广告、无账号、无第三方云同步、无统计分析；唯一的网络出口是默认关闭的可选 NAS 同步（WebDAV/SFTP/SMB，用户自行配置服务器，见 `docs/decision-records.md` D-023），发布包仅为此声明 `INTERNET` / `ACCESS_NETWORK_STATE` / `ACCESS_LOCAL_NETWORK`；
- 使用系统相机，不在应用内实现或集成第三方相机界面；
- 项目数据库、私有原图和处理中间文件保存在本机；
- 水印成片发布到系统相册 `Pictures/SiteMark`；
- 支持单项目、多项目备份与恢复；所选记录分享 ZIP 仅用于对外发送，不能恢复；
- 提供本机诊断包，诊断记录不自动上传，且不包含工程内容、照片、位置或文件标识；
- iOS 版适配进行中（Flutter 复用线，尚无签名发布，见第 10 节）；
- 不支持多人协作、云同步、图库导入和自由拖拽式水印模板。

## 2. 用户主流程

1. 新建不重名的项目，必要时调整该项目的水印位置、透明度、字体比例和强调色；
2. 填写工程部位、工作内容、拍摄人和可选备注；
3. 三个必填字段可从当前项目最近记录中点选建议，或应用只属于当前项目的命名模板；
4. 选择是否允许前台定位，然后调用系统相机；
5. 系统相机返回后立即生成记录，定位解析、水印渲染和相册发布在后台继续；
6. 用户可以保留上一张的工程部位、工作内容和拍摄人继续拍摄，备注会清空；
7. 在项目记录或全部记录中搜索、筛选、预览、导出、再次保存、清理原图或删除；
8. 在总设置查看应用内数据占用、管理备份恢复、诊断、定位、通知、外观和语言，并可选配置 NAS 同步；
9. 卸载或换机前，备份一个或多个项目并把 ZIP 复制到应用目录之外。

## 3. 总体架构

| 层 | 技术 | 主要职责 |
| --- | --- | --- |
| Flutter 应用层 | Flutter、Material 3、Riverpod、GoRouter | 页面、导航、中英文、主题、表单状态、记录交互 |
| 数据层 | Drift、SQLite | 项目、设置、拍摄记录、项目内模板、状态流转、筛选与迁移 |
| 后台任务层 | WorkManager、Dart 后台 isolate | 串行任务、失败重试、启动与重启恢复；iOS 由 BGTaskScheduler 机会性补拍承接（见第 10 节） |
| Android 集成层 | Kotlin、Pigeon、FlutterPlugin、ActivityAware | 系统相机、ContentProvider、EXIF 检查、前台定位、MediaStore |
| iOS 集成层 | Swift、Pigeon、BGTaskScheduler、PHPhotoLibrary | 系统相机桥、EXIF/GPS 检查、前台定位、相册发布与删除、存档、内存压力（见第 10 节） |
| 图像核心层 | Rust、flutter_rust_bridge | EXIF 方向、SHA-256、全分辨率水印、CSV/JSON/ZIP 导出 |

Flutter 与 Rust 之间只传文件路径和结构化参数，不把整张全分辨率图片作为 Dart
字节数组跨 FFI 传递。Android 平台能力集中在仓库内插件
`packages/sitemark_system_api`，前台 Activity 和后台 FlutterEngine 共用同一接口。

## 4. 数据模型

当前 Drift schema 为版本 14，核心实体如下：

- `projects`：项目名称、说明、生命周期状态（`active`/`completed`/`archived`）、置顶标记以及项目级水印设置；
- `captures`：现场字段、照片编号、时间、定位、路径、哈希、处理状态和原图清理状态；
- `capture_templates`：项目内命名模板，只保存模板名称、工程部位、工作内容和拍摄人；
- `app_settings`：主题、动态颜色、语言、定位提示、通知以及新建项目默认水印参数；
- `nas_sync_configs`：NAS 同步单例配置（协议、地址、根路径、Wi-Fi 限制等；密码不在此表，见下）；
- `nas_upload_states`：每条记录的上传簿记（状态、尝试次数、最后尝试时间）。

`captures.project_id` 通过外键关联项目，并定义数据库级级联删除。新建项目会同时检查
规范化显示名称和安全文件名键，避免同名项目及文件名碰撞。照片编号在系统相机成功
返回后分配，新格式为`安全化项目名称-SM-日期-全应用当日序号`。当日序号跨项目递增，
因此不再把项目 UUID 写入照片名。旧记录和旧文件不会迁移或改名。照片编号用于数据库、
文件名、CSV 和 JSON，不绘制在水印画面中。

NAS 同步（D-023 修订）在三条产品线共用同一 Rust 核心 `sitemark_core::nas`：
Android/iOS 经 flutter_rust_bridge，鸿蒙经 JSON C ABI。配置行不保存密码——密码只存
系统安全存储（Android Keystore 支撑的存储 / iOS Keychain / 鸿蒙 asset 资产存储），
上传时按次读出。上传队列为串行，失败按 5 次尝试预算进入 `failed`，可手动重试；
远端路径固定为 `{根路径}/{项目安全名}/{照片编号}.jpg`，重试覆盖同名文件以收敛。

记录列表由 SQLite 直接查询，而不是先把全部记录加载到界面内存。查询按
`capturedAt ?? createdAt` 与记录 ID 倒序排序；schema v9 为全局和按项目的这个排序
创建稳定游标索引。界面每页读取 50 条，游标以排序时间和 ID 共同定位，因此相同拍摄
时间的记录也能稳定翻页。接近已加载列表末尾 8 条时会预取下一页。

同一查询还由数据库返回匹配记录总数和实际存在的年、月、日选项。关键词会拆成多个
空白分隔的词；每个词可匹配项目名称、工程部位、工作内容、拍摄人、备注、照片编号或
地址，多个词必须同时匹配。查询条件同时适用于列表、日期选项、全选与全屏相邻图片。

最近字段建议不维护独立词库，而是从当前项目现存的 `captures` 分字段查询。
`pendingCamera` 不作为建议来源；`captured`、`rendering`、`ready` 和 `failed` 均可提供
现场输入。每个字段按 `capturedAt ?? createdAt` 与 ID 倒序读取，去除首尾空白并按
ASCII 英文大小写去重，保留最近一次显示文本。查询失败只隐藏建议，不阻止手动输入或拍照。

模板由 `project_id` 隔离并级联删除，每个项目最多 100 个；不同项目可以使用相同名称，
同一项目内名称按规范化键唯一。名称先执行 Dart `trim()`，再将 `RegExp(r'\s+')`
识别的连续 ECMAScript/Unicode 空白折叠为一个 ASCII 空格；名称键只把 ASCII `A-Z`
转成小写。工程部位、工作内容和拍摄人只执行 `trim()`，内部空白原样保留。模板列表按
`updatedAt DESC, name ASC` 排序。模板从数据类型到界面、归档均不包含备注。

长度按 Unicode 标量计数：Dart 使用 `runes.length`，Rust 使用 `chars().count()`。
Rust 分别显式复刻 Dart `trim` 与正则 `\s` 的字符集合：U+0085 只参与边缘 trim，
U+FEFF 同时参与 trim 和内部折叠，U+200B 不被两组识别并原样保留。SQLite 只以 `length()`、
U+0000 CHECK 和 `(project_id, name_key)` 唯一约束兜底，不负责文本规范化。

## 5. 权限与安全边界

发布 APK 可申请前台粗略/精确定位；拒绝定位不阻止拍照。WorkManager 使用唤醒、
开机恢复、前台服务和 Android 13+ 通知能力。应用不申请：

- `CAMERA`；
- 后台定位；
- 广泛媒体访问或传统外部存储权限。

唯一的网络出口是默认关闭的可选 NAS 同步（D-023）：发布包为此声明
`INTERNET` / `ACCESS_NETWORK_STATE`（鸿蒙另加 `GET_NETWORK_INFO`），
Android 17 局域网 NAS 另声明并在设置页运行时申请 `ACCESS_LOCAL_NETWORK`。GitHub 仓库链接由外部
浏览器打开。SHA-256 用于本地完整性检查和记录追溯，不代表司法鉴定、可信时间戳
或第三方存证。

## 6. 数据保留边界

应用私有数据库和原图会在卸载时被 Android 删除；已经发布到
`Pictures/SiteMark` 的水印照片通常仍会保留。单项目备份和多项目 bundle 内的每个项目
ZIP 使用项目归档 schema v5，保存空白项目、项目说明、创建时间、生命周期、置顶、水印设置、
项目内模板、快照和遗漏计数，并兼容 v1/v2/v3/v4 旧项目 ZIP；多项目外层 bundle schema
仍为 v1。旧项目 ZIP 恢复为空模板列表，生命周期为进行中且未置顶。

恢复项目、记录和模板由同一恢复所有权令牌约束，照片先进入私有暂存区。提交前失败会
回滚数据库、暂存文件和已规划目标文件；提交标记已写入但收尾中断时，由下次启动完成
所有权清理。内部以 `ProjectRestoreStateException.failure` 的 `ownershipLost` 和
`templateSetMismatch` 区分两种状态不一致；进入多项目 bundle 或界面层后统一归类为
`general` 并显示通用恢复失败。拍摄记录编辑页生成的普通分享 ZIP 仍然不是备份。

总设置中的存储统计只计算 SiteMark 应用私有原图、私有水印成片、私有导出文件、
数据库和其他应用文档，不包含系统相册。清理本地导出只删除应用私有 `exports` 目录的
ZIP，不删除已分享副本、系统相册照片、原图或数据库记录。

## 7. 当前质量基线

v1.0.0 必须通过 Flutter 全量测试与静态分析、Rust fmt/Clippy/全量测试、Android
插件单元测试和 Debug/Release APK 构建。持久化诊断记录备份、恢复与删除操作的
固定结果分类、数量和耗时；不持久化项目名称、模板内容、路径、SQL、原始异常或堆栈。

## 8. 文档维护规则

本文件只记录当前已经实现的产品边界和架构。阶段性任务、PR 修复过程和被替代的
假设留在 `docs/superpowers/` 作为历史，不再从 README 的当前设计入口展示。
任何改变权限、数据生命周期、拍摄状态机、导出可恢复性或技术分层的修改，必须同步
更新本文件及[关键技术决策记录](decision-records.md)。


## 根导航状态保活与内存

一级「项目 / 全部记录 / 设置」由 `RootBranchContainer` 保活各自分支的导航与滚动状态；切换时短时绘制来源页与目标页以完成方向滑动。`main` 将 `imageCache` 限制在约 40 张 / 32MB，并在内存压力回调中清空缓存。真机观察项见 `docs/verification-v1.0.0-device.md` 第 7 节。

## 9. HarmonyOS NEXT 原生实现

`ohos-native/` 是与 Android 稳定版并行的原生 Stage 应用，不是 Flutter 页面的鸿蒙适配。它使用独立包名 `io.github.wikg1018.sitemark.native`，不覆盖历史 `ohos` 试验线，也不共享 Android 的 SQLite 数据库文件。

| 层 | HarmonyOS 原生技术 | 边界 |
| --- | --- | --- |
| 界面与导航 | ArkTS、ArkUI、Navigation、自定义悬浮 Dock | 项目/记录/设置三分支、中英文、深浅色、表单与批量交互 |
| 数据 | RelationalStore schema 14、Preferences | 业务字段对齐 Android schema 11；额外表用于鸿蒙私有文件/媒体清理和中断恢复 |
| 拍摄与系统 | CameraPicker、LocationKit、PhotoAccessHelper、DocumentViewPicker | 系统相机与系统保存面板；声明前台定位权限，以及可选 NAS 同步所需的 INTERNET / GET_NETWORK_INFO |
| 处理与恢复 | 应用存活期串行队列、启动对账、Preferences 发布日记 | 进程被系统结束后暂停，下次启动幂等收敛，不伪装 WorkManager |
| 图像与归档 | 同一 `sitemark_core`，C ABI + C++ N-API，`arm64-v8a`/`x86_64` | 与 Android 复用水印、SHA-256、CSV/JSON/ZIP 算法；全分辨率数据不经 ArkTS 字节数组传递 |

鸿蒙数据安全语义继续使用稳定 `captureId` 而不是照片编号或文件名识别发布记录。新发布 URI 先写耐久日记，RDB 提交时同事务加入旧 URI 清理任务；清理前查询全库引用，日记只能按期望 URI 条件清除。

当前完成的是 DevEco API 22 x86_64 模拟器级功能回归和双 ABI 构建；正式签名、HarmonyOS NEXT 真机 CameraPicker/相册授权和高像素性能尚待复验。实测限制以 [`ohos-native/docs/deltas.md`](../ohos-native/docs/deltas.md) 为准。

## 10. iOS 适配（Flutter 复用线）

iOS 是第三条产品线，走 Flutter 复用：`lib/` UI 与业务逻辑、`rust/` 图像核心、
数据库 schema 与备份格式全量复用，平台能力由仓库内 Swift 插件
`packages/sitemark_system_api`（Pigeon `SiteMarkSystemApi` 全 14 方法 + `sitemark/memory_pressure`
通道）承接，包名 `io.github.wikg1018.sitemark`，最低 iOS 14.0。设计、分期与已接受
偏差见 `docs/superpowers/specs/2026-08-30-ios-adaptation-design.md` 及对应计划文档。

- **拍摄与存储**：相机走系统相机桥，原图写入 Application Support/originals（与
  Dart 侧 `getApplicationSupportDirectory()` 同一目录），发布 journal 为同目录 JSON；
  成片经 `PHPhotoLibrary` 发布，`localIdentifier` 承担 URI 角色，相册内文件名由系统决定。
- **成片删除**：`PHAsset` 删除会弹系统确认框；界面文案统一按“可能弹出系统确认”表述，
  不做平台分支。
- **界面惯例**：开关/滑块用 Flutter 自适应构造（iOS 呈现 Cupertino 外观），标准确认/
  信息对话框经 `lib/shared/ui/adaptive_dialog.dart` 在 iOS 呈现 CupertinoAlertDialog，
  Android 分支保持原 Material 组合；复杂表单对话框仍为 Material（已知偏差）。应用图标
  与 Android 同源（`assets/branding/sitemark-icon.png` 单尺寸 1024）。通知授权与
  Android 同时机：用户打开通知开关时请求（决策 D-022）；启动屏深色自适应留待
  真机阶段（当前固定白色背景，与 Android 浅色一致）。
- **后台处理**：前台轮询与 Android 完全一致；后台只注册一个 BGProcessingTask
  （identifier 与 Info.plist `BGTaskSchedulerPermittedIdentifiers`、AppDelegate 注册
  三方精确一致，后台模式仅 `processing`），触发时重新入队未完成记录并再次提交下一轮
  请求。系统机会性调度，不保证拍完立刻处理；诊断页“平台差异”卡片如实展示。
- **权限面**：仅相机、前台定位、相册添加与读取（用于自有成片替换/删除）四项用途描述；
  不申请麦克风、蓝牙、本地网络、追踪或 Always 定位。
- **构建与门禁**：CI macos-15 job 跑 Swift XCTest + `flutter build ios --no-codesign` +
  PlistBuddy 元数据门禁；尚无签名与 TestFlight，发布未接入 release.yml。
