# SiteMark 工程印记 · `ohos` 分支

> **你正在看 HarmonyOS NEXT 适配分支，不是 Android 产品主线。**
>
> 仓库首页默认是 [`main`](https://github.com/WikG1018/site-mark/tree/main)。`main` 继续发 Android APK。本分支从 Android **v1.0.8**（`847c74b`）拉出，只承载鸿蒙 HAP、社区 Flutter 与 ohos 插件，**禁止合回 `main`**。

面向工程现场记录的离线水印相机。Android 产品语义见下方原文；鸿蒙目标是同一套项目 / 拍摄 / 记录 / 备份语义，交付 HarmonyOS NEXT 原生 HAP。

[![ohos Dart tests](https://github.com/WikG1018/site-mark/actions/workflows/ohos.yml/badge.svg?branch=ohos)](https://github.com/WikG1018/site-mark/actions/workflows/ohos.yml)
![HarmonyOS NEXT](https://img.shields.io/badge/HarmonyOS-NEXT-EE2B2B)
![Android baseline v1.0.8](https://img.shields.io/badge/Android_baseline-v1.0.8-3DDC84?logo=android&logoColor=white)
[![License](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)
![Engine degraded](https://img.shields.io/badge/watermark_engine-degraded-E67E22)

**当前状态（请按字面理解，不要当成已上架鸿蒙版）：**

| 项 | 事实 |
| --- | --- |
| 产品主线 | 仍在 `main`，安装包是 Android APK |
| 本分支基线 | SiteMark Android **v1.0.8** / `1.0.8+23` |
| HAP 宿主 | `ohos/`，包名 `io.github.wikg1018.sitemark` |
| 已验证 | DevEco 模拟器 `SiteMarkPhone602` 上 **全量 `lib/main.dart` 未签名 HAP**：隐私门 → 新建项目 → 项目详情 → 拍摄表单；定位/相机权限框可弹出；备份「不包含原图」写出沙箱 `files/exports/*.zip` 并弹出系统 Document picker。hdc 当前为 `127.0.0.1:5555` |
| 未完成 | 签名 release、相机拍成 dump / ACL / `ohos-arm64` 对等、系统通知未证、系统分享未证、系统文件选择恢复未证、系统外链未证、真机回归 |
| 引擎 | `tool/ohos/engine_status.md`：**degraded** |

后续实施计划：[2026-08-19-harmonyos-capture-sandbox-copy.md](docs/superpowers/plans/2026-08-19-harmonyos-capture-sandbox-copy.md)（Tasks 39–40：`CameraPicker` 省略沙箱 `saveUri`，`file://media/` 用 `fs.openSync(uri)` 拷进 `files/originals`；通道测试已绿，无拍成 dump 不得写相机已拍成）。前序：[2026-08-19-harmonyos-open-link.md](docs/superpowers/plans/2026-08-19-harmonyos-open-link.md)（Tasks 37–38：关于页 GitHub 走 `startAbility` 隐式 Want；`main.dart` 鸿蒙外链不再覆盖成 no-op；通道测试已绿，无浏览器 dump 不得写系统外链已通）。再前：[2026-08-19-harmonyos-notifications.md](docs/superpowers/plans/2026-08-19-harmonyos-notifications.md)（Tasks 35–36：NotificationKit）。再前：[2026-08-19-harmonyos-share-file.md](docs/superpowers/plans/2026-08-19-harmonyos-share-file.md)（Tasks 33–34：ShareKit）。再前：[2026-08-19-harmonyos-inspect-image.md](docs/superpowers/plans/2026-08-19-harmonyos-inspect-image.md)（Tasks 31–32：拍成后读图走 ImageKit `inspectImage`）。再前：[2026-08-19-harmonyos-pick-archive.md](docs/superpowers/plans/2026-08-19-harmonyos-pick-archive.md)（Tasks 29–30：鸿蒙恢复选文件走原生 `DocumentViewPicker`）。再前：[2026-08-19-harmonyos-restore-import.md](docs/superpowers/plans/2026-08-19-harmonyos-restore-import.md)（Tasks 25–28：降级读档）。再前：[2026-08-19-harmonyos-save-archive.md](docs/superpowers/plans/2026-08-19-harmonyos-save-archive.md)（Tasks 21–24：沙箱 schema 5 zip + picker 弹出）。再前：[2026-08-19-harmonyos-records-backup.md](docs/superpowers/plans/2026-08-19-harmonyos-records-backup.md)。再前：[2026-08-19-harmonyos-capture-path.md](docs/superpowers/plans/2026-08-19-harmonyos-capture-path.md)。再前：[2026-08-18-harmonyos-product-runtime.md](docs/superpowers/plans/2026-08-18-harmonyos-product-runtime.md)。全量 HAP 编译记录见 [2026-08-18-harmonyos-full-product-hap.md](docs/superpowers/plans/2026-08-18-harmonyos-full-product-hap.md)。前期 Tasks 0–5 见 [2026-08-17-harmonyos-next-adaptation.md](docs/superpowers/plans/2026-08-17-harmonyos-next-adaptation.md)。规格见 [harmonyos-next-adaptation-design.md](docs/superpowers/specs/2026-08-17-harmonyos-next-adaptation-design.md)。

---

## 鸿蒙适配说明

本分支保留 `android/`，是为了对照 Android v1.0.8 语义，**不是**本分支的发布物。不要改 `ci.yml` / `release.yml` / `android/`。`main` 的产品修复只允许 cherry-pick 进 `ohos`。

已落地（Tasks 0–5）：

- `packages/sitemark_system_api` 的 ohos 宿主与 JSON channel `sitemark.system.ohos`
- `OhosPlatformServices`、应用内串行队列、按 `captureId` 的发布日记
- ACL 相册 + picker / 沙箱托底（代码在，模拟器未证明 ACL）
- 首次启动隐私同意（产品路径走 `FilePrivacyConsentStore`）
- 产品 `ohos/` HAP 树；模拟器已跑全量 `lib/main.dart`（隐私门 → 新建项目 → 设置 / 关于 → 项目详情 → 拍摄表单 → 全部记录 → 备份选项目 → 沙箱 zip）
- 鸿蒙备份：`OhosArchiveSaveService` + 宿主 `saveArchive`（picker 优先，失败/取消回退沙箱）；降级 `DegradedImagePipeline` 可写出并读回 schema 5 zip / schema 1 bundle
- 鸿蒙恢复选文件：`OhosArchivePickService` + 宿主 `pickArchive`（`DocumentViewPicker.select` → `copyUriToPath` 到 `files/imports`）；产品页默认走该服务，非鸿蒙走 `FilePicker.pickFile` 单选 zip
- 鸿蒙读图：宿主 `inspectImage` 用 ImageKit 读宽高 / 大小 / MIME / 可选 EXIF GPS
- 鸿蒙拍成落盘：`CameraPicker` 不再把沙箱路径当 `saveUri`；`file://media/` 等媒体 URI 用 `fs.openSync(uri)` 拷进 `files/originals/{captureId}.jpg`；无拍成 dump
- 鸿蒙分享：`OhosShareFileService` + 宿主 `shareFile`（ShareKit `ShareController`，zip/jpeg/png 走对应 UTD）；产品入口不再覆盖成 no-op；无分享面板 dump
- 鸿蒙拍成通知：`OhosCompletionNotificationService` + NotificationKit 基础文本；点击经 WantAgent / `EntryAbility` 回 deep link；无通知 dump
- 鸿蒙外链：`OhosExternalLinkService` + 宿主 `openLink`（`ohos.want.action.viewData` + `entity.system.browsable`）；产品入口不再覆盖成 no-op；无浏览器 dump
- `path_provider` 由 `SiteMarkSystemPlugin` 桥到应用目录
- Drift / sqlite3：same-isolate + musl so + `NativeAssetsManifest.json`
- `package_info_plus` 桥返回 `1.0.8` / `23`

明确还不是完整鸿蒙版：

- 模拟器已跑全量 `lib/main.dart` 首页，**不等于** Android v1.0.8 能力对等
- 水印引擎未编出 `ohos-arm64`，运行时走降级管线
- 无真机，不能声称相机已拍成、定位出坐标、备份已进系统文件管理、系统文件选择恢复已通、系统分享已通、系统通知已通、系统外链已通、系统相册替换与 Android 对等；模拟器仅探测到权限框 + `CameraPicker.Pick` 回表单，以及备份沙箱 `files/exports/*.zip` + Document picker 弹出（未完成 picker 保存）。恢复导入引擎层已通；产品页已改走原生 Document picker，但无模拟器成功 dump，不得写系统文件选择恢复已通。读图通道与 ImageKit 宿主已接；相机媒体 URI 拷沙箱已接，无拍成 dump 不得写相机已拍成。分享通道与 ShareKit 宿主已接，无分享面板 dump 不得写系统分享已通。通知通道与 NotificationKit 宿主已接，无通知 dump 不得写系统通知已通。外链通道与 `startAbility` 宿主已接，无浏览器 dump 不得写系统外链已通
- 无签名 `flutter build hap --release`，不能当应用市场上架包
- GitHub Releases 里的 APK 属于 Android 主线，不是本分支产物

模拟器审查记录：`tool/ohos/product_hap_review.md`。应用市场材料清单：`tool/ohos/appgallery_checklist.md`。

---

# Android 产品说明（本分支语义基线，不是鸿蒙发布说明）

> 面向工程现场记录的 Android 水印相机：调用手机系统/厂商相机，无广告、无账号、无云端，照片与项目数据均在本机处理。

An offline-first engineering watermark camera for Android that keeps the
manufacturer camera experience.

[![CI](https://github.com/WikG1018/site-mark/actions/workflows/ci.yml/badge.svg)](https://github.com/WikG1018/site-mark/actions/workflows/ci.yml)
![Android 12+](https://img.shields.io/badge/Android-12%2B-3DDC84?logo=android&logoColor=white)
[![License](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)
![No ads](https://img.shields.io/badge/Ads-none-176B55)
![No network permission](https://img.shields.io/badge/Network_permission-none-176B55)
[![Pre-release](https://img.shields.io/badge/pre--release-v1.0.8-E67E22)](https://github.com/WikG1018/site-mark/releases/tag/v1.0.8)

**最新预发布版本：[`v1.0.8`](https://github.com/WikG1018/site-mark/releases/tag/v1.0.8)**  
**已完成真机回归的稳定版本：[`v1.0.5`](https://github.com/WikG1018/site-mark/releases/tag/v1.0.5)**

支持 Android 12（API 31）及以上系统。`v1.0.8` 加固相册发布与媒体生命周期：新图转正后再清理旧图、跨层 journal 对账、共享 URI 安全删除，以及 journal 键 XML 安全与清理重试上限；完成真机回归前保持 Pre-release。重要项目请定期创建包含私有原图的备份，并把备份文件复制到应用目录之外。

## 下载

| 安装包 | 适用设备 | 下载 |
| --- | --- | --- |
| arm64 | 推荐；绝大多数近年 Android 手机 | [sitemark-v1.0.7-arm64.apk](https://github.com/WikG1018/site-mark/releases/download/v1.0.7/sitemark-v1.0.7-arm64.apk) |
| universal | 不确定处理器架构或 arm64 无法安装时使用；文件更大 | [sitemark-v1.0.7-universal.apk](https://github.com/WikG1018/site-mark/releases/download/v1.0.7/sitemark-v1.0.7-universal.apk) |
| SHA-256 | 校验下载文件是否完整 | [SHA256SUMS.txt](https://github.com/WikG1018/site-mark/releases/download/v1.0.7/SHA256SUMS.txt) |

> [!WARNING]
> 卸载 SiteMark 会删除应用数据库、应用私有原图和私有水印文件。已经发布到系统相册 `Pictures/SiteMark` 的水印照片通常仍会保留。卸载、换机或处理签名冲突前，请先进入“设置 → 备份与恢复”，备份重要项目并把 ZIP 保存到可靠位置。

## 安装与升级

1. 优先下载 arm64 安装包；只有设备不兼容时再使用 universal。
2. 打开 APK，按 Android 提示允许浏览器或文件管理器“安装未知应用”。
3. 正式 Release 使用同一签名，可以直接覆盖升级并保留应用数据。
4. Debug APK 与正式版签名不同，通常不能直接覆盖安装。
5. 如果 Android 提示签名冲突，不要直接卸载保存着重要数据的旧版本；先完成项目备份并确认备份文件已复制到应用目录之外。

## v1.0.8 重点更新

- **相册替换不再截断旧图：** 重新保存到相册时先创建并转正新行，成功后再清理旧行；写入中途被杀时旧图仍完整可见，半写新行保持 pending。
- **发布对账与身份隔离：** Native 转正后同步写入 publish journal；启动时按 captureId 对账恢复，不再用照片编号当全局身份，避免备份恢复后同编号项目互相误删。
- **共享 URI 与并发安全：** 删除前全库检查引用；journal 仅在 URI 匹配时清除；连续崩溃会合并待清理 URI，避免旧清理任务丢失。
- **journal 键与清理预算：** journal 键改为 base64url，避免 XML 非法字符导致持久化失败；清理任务最多重试 5 次后 Stall，失败与恢复写入诊断事件。

## v1.0.7 重点更新

- **恢复不再误删项目：** 恢复流程在文件落位后立即持久化提交阶段标记；启动清理不再把已恢复完成的项目当作中断导入而删除。
- **拍摄处理幂等：** 相机恢复不再重铸每日照片编号、不再把已完成记录拉回待处理；处理重试只扣减一次次数预算；大批量选择的记录监听按 900 条分片，避开 SQLite 变量上限。
- **解码与相册防线收紧：** 非 JPEG/PNG 或超大尺寸的照片在分配解码内存前被拒绝，防止构造图片导致 OOM；拍摄完成后撤销相机 URI 授权；相册删除仅允许作用于 `Pictures/SiteMark` 条目。
- **英文文案补齐：** 残留中文的诊断、备份预检与诊断 ZIP 摘要文案全部双语化；项目或记录缺失、加载失败时显示明确状态，不再无限转圈。
- **诊断可观测：** 诊断事件存储失败不再静默，丢弃计数写入诊断包清单，便于排查存储异常。

## v1.0.6 重点更新

- **媒体清理可恢复：** 清除原图和删除记录采用持久化意图、数据库提交、幂等物理清理的顺序；应用在任意阶段退出后均可安全续作。
- **启动恢复相互隔离：** 单个恢复阶段失败不会跳过后续阶段，也不会向根级启动回调泄漏未处理异常。
- **Android 相册发布可回滚：** 替换已有水印照片失败时恢复旧内容；无法完整恢复时保持 pending 隐藏，避免暴露半写入文件。
- **验证链路更稳定：** Android 模拟器覆盖创建工程、拍摄处理和日期筛选主路径；Gradle、SQLite 原生库与 APK 构建的瞬时下载失败使用有界重试。

## v1.0.5 重点更新

- **首页搜索不再闪烁：** 输入项目名称的 250ms 防抖等待期间继续显示当前项目列表，不再逐字闪回骨架占位；查询切换后再更新结果。
- **版本信息统一：** README 下载入口、应用内“关于”版本和安装包版本统一为 `1.0.5+20`。

## v1.0.4 重点更新

- **详情 Hero 链路修复：** 详情页图片预览把 Hero 标识继续传递到全屏查看器，恢复列表、详情与全屏之间连续一致的图片飞行动画。
- **发布工程修复：** 统一 Dart 格式并修复发布分支中的异常文件内容，恢复完整 CI 验证。

## v1.0.3 重点更新

- **返回键逐级退出：** 「全部记录」筛选/编辑/搜索状态下按系统返回，先取消选择、再关闭搜索、再清除筛选，不再一次返回直接退出应用（按钮返回路径已由回归测试全链路锁定）。
- **品牌化启动画面：** 启动时不再显示放大版应用图标，改为品牌深绿圆盘 + 白色相机符号的专用启动图形，亮暗模式背景与首页衔接无闪色。
- **全屏查看体验：** 双指可从 1x 直接放大（此前需先双击）；点开照片改为 Hero 一镜到底飞入（替代覆盖式转场）；左右滑动相邻照片即时显示降采样预览，不再黑屏等全尺寸解码。
- **首页搜索性能：** 搜索输入增加 250ms 去抖并复用查询流，减少逐字输入触发的数据库查询；关于页与 `pubspec` 版本对齐为 `1.0.3+18`。

## v1.0.2 重点更新

- **整页横滑与 Dock 修复：** 首页切换改为整页边对边平移（一镜到底）；项目详情与图片详情不再出现首页 Dock；快速连点切换、反向跳切不再闪出背景或跳到中心回弹。
- **失败信息收口：** 拍摄记录批量操作失败原因改为枚举与本地化文案，界面不再显示内部异常与私有路径；删除/恢复诊断口径修正。
- **工程与测试：** 切换动画规划器抽为纯函数，新增随机链视口覆盖 property 测试（含反向跳切、快速连击场景）；关于页与 `pubspec` 版本对齐为 `1.0.2+17`。

## v1.0.1 重点更新

- **失败文案与诊断：** 备份/恢复/删除路径的用户可见错误不再拼接原始异常；删除与恢复诊断事件入库（无路径/项目内容）。
- **玻璃与根导航：** 根分支滑动增强空间感与 scale；GlassSurface 高光/内描边，overlay 画在内容下方，blur 路径 opacity 有 clamp。
- **工程与文档：** Agent 常驻入口刷新；真机回归清单；integration 夜间/手动工作流；关于页与 `pubspec` 版本对齐为 `1.0.1+16`。

## v1.0.0 重点更新

- **项目生命周期**：项目分为进行中、已完成、已归档；已完成/已归档禁止新建拍摄，仍可查看、编辑、导出和管理已有记录。
- **置顶与排序**：置顶与生命周期独立；首页按置顶、最近拍摄时间、创建时间、项目 ID 稳定排序。
- **状态筛选与跨状态搜索**：首页默认显示进行中；底部弹层切换状态；搜索覆盖全部状态并显示状态标识。
- **备份保留状态**：单项目 ZIP 升级至 schema v5，精确保留生命周期与置顶；v1–v4 恢复为进行中且未置顶；多项目外层 bundle 仍为 schema v1。
- **全新悬浮导航**：项目、全部记录、设置使用更低、更紧凑的悬浮 Dock，选中背景完整覆盖图标和文字；根页面只绘制当前分支，避免返回时照片列表闪现。
- **清晰的多选管理**：复选框覆盖缩略图而不挤压内容，悬浮操作栏同时显示图标和文字，支持导出、保存到相册、清理原图及全部删除。

## 从早期版本累计完成的改进

| 范围 | 当前状态 |
| --- | --- |
| 一级导航 | “项目 / 全部记录 / 设置”通过紧凑悬浮 Dock 切换，选中背景覆盖图标和文字；分别保留列表、搜索和筛选状态，但只绘制当前页面；进入详情等二级页面后 Dock 隐藏 |
| 拍摄 | 调用系统/厂商相机，连续拍摄时后台生成水印；下一张保留工程部位、工作内容和拍摄人，仅清空备注；支持最近字段建议和项目内命名模板；非进行中项目禁止新拍摄 |
| 记录 | 缩略图列表在筛选按钮右侧显示当前可见日期，并随滚动更新；详情支持“成片 / 原图”和“现场记录 / 文件信息”切换，点击照片可进入相邻照片全屏浏览；支持编辑、删除和再次保存 |
| 检索 | 首页状态筛选与跨状态项目搜索；全部记录和项目记录支持关键词搜索，以及从紧凑底部面板选择项目、年、月、日，已生效条件可单独移除 |
| 批量操作 | 复选框覆盖缩略图，不挤压照片和文字；多选时以带图标与文字的紧凑悬浮 Dock 替换一级导航；支持按当前筛选结果全选/取消全选、导出、再次保存、清理原图和删除整条记录 |
| 水印 | 项目名称、现场字段、时间和可选位置；支持位置、透明度、字体大小和强调色 |
| 项目 | 生命周期、置顶、同名/安全文件名冲突保护；支持重命名、删除和项目级水印设置 |
| 设置 | 一级页按“拍摄与记录 / 数据与安全 / 应用”分组，集中进入水印默认值、定位、通知、备份恢复、存储、诊断、语言、外观与关于 |
| 数据安全 | 项目备份恢复、原图 SHA-256 校验、恢复事务与文件回滚、异常中断清理 |
| 体验 | 玻璃材质导航与卡片、稳定且符合层级关系的页面转场、图片 Hero 动画、无隐藏列表闪现的返回逻辑、减少动画适配，以及可继续加载的记录和全屏图片列表 |

## 产品定位

工程现场需要的不只是“给照片加文字”，还包括顺手的拍摄体验、稳定的后台处理、清晰的项目归档和可回查的原图信息。

SiteMark 不在应用里重新实现相机，也不嵌入第三方相机 SDK。应用通过 Android 标准能力调用手机系统/厂商相机，保留设备原有的对焦、HDR、防抖、镜头切换和画质调校；SiteMark 负责拍摄前的工程信息、拍摄后的本地水印处理、记录管理和项目备份。

发布 APK 没有广告、账号、云同步或统计上传，也不申请网络权限。点击 GitHub 仓库链接时会交给外部浏览器处理。

## 快速使用

1. 新建项目，按需要填写项目说明并调整“此项目水印设置”。
2. 填写工程部位、工作内容、拍摄人和可选备注；可点选当前项目的最近建议，或应用项目内命名模板。
3. 需要位置时主动请求前台定位；拒绝定位不影响拍照。
4. 点击拍摄，进入手机系统/厂商相机完成拍照。
5. 返回 SiteMark 后照片进入本地后台处理，可继续拍摄下一张。
6. 在项目记录或全部记录中按关键词、项目或日期筛选，预览、编辑和管理照片。
7. 卸载或换机前进入“设置 → 备份与恢复”，选择一个或多个项目创建备份。

连续拍摄会保留工程部位、工作内容和拍摄人，仅清空备注。最近建议来自当前项目的既有记录；命名模板只保存三个必填字段，最多 100 个，备注不会被保存或覆盖。

## 水印与照片命名

水印可显示：

- 项目名称；
- 工程部位；
- 工作内容；
- 拍摄人；
- 拍摄时间；
- 授权并成功获取时的位置。

照片编号不会绘制到水印画面。新照片使用以下短文件名：

```text
{安全化项目名称}-SM-{yyyyMMdd}-{全应用当日序号}.jpg
```

例如：`云湖之城-SM-20260717-003.jpg`。

项目重命名只影响项目显示名称和重命名后的新照片。历史照片编号、文件名、文件路径和已生成水印不会被修改。

## 记录与原图管理

- **清理原图**：删除应用私有原图，保留水印成片、相册照片和数据库记录。
- **删除整条记录**：删除应用内原图、水印文件、数据库记录，并尝试删除该记录发布到系统相册的照片。
- **删除项目**：删除应用内项目、记录和私有文件，但不删除系统相册照片，也不删除已经导出的备份。
- **再次保存**：将水印成片重新发布到 Android 系统相册。

记录详情可查看缩略图、全屏图片、文件大小、原图保留状态、时间、位置和工程字段。项目记录与全部记录均支持编辑模式和批量操作。

## 备份与恢复

入口：**设置 → 备份与恢复**

### 创建备份

- 可选择单个或多个项目；
- 可选择是否包含应用私有原图；
- 空白项目同样可以备份；
- 有照片仍在处理时，应用会阻止备份并提示稍后重试；
- 有处理失败的照片时，默认不会继续，必须明确选择“仅备份已完成记录”；
- 单项目生成可独立恢复的项目 ZIP；多项目生成一个外层 bundle，其中每个项目仍是独立项目 ZIP。

每个项目 ZIP 包含项目元数据、项目水印设置、项目生命周期与置顶、项目内命名模板、已完成的水印 JPEG、UTF-8 BOM CSV 和 JSON manifest；用户选择时还会包含私有原图。项目 ZIP schema v5 继续记录备份快照时间和被明确跳过的失败记录数量，并精确保留生命周期与置顶。多项目外层 bundle 只负责组织这些项目 ZIP，其 schema v1 未改变。

### 恢复

- 项目 ZIP 支持当前 schema v5，以及旧版 v1/v2/v3/v4；这里的兼容版本不指多项目外层 bundle；旧项目 ZIP 恢复后模板列表为空，生命周期为进行中且未置顶；
- 恢复照片编号、拍摄时间、工程字段、位置、水印设置、原图 SHA-256，以及 schema v5 的生命周期与置顶；
- v3 额外恢复项目说明和原始创建时间；
- 恢复前校验归档结构与 SHA-256；schema v5 还严格校验生命周期与置顶字段；
- 恢复过程中项目保持隐藏，项目、记录和模板受同一恢复所有权约束，成功提交后才显示；
- 恢复结果汇总各状态数量；若包含归档项目，可直接跳转到归档列表；
- 恢复失败会回滚数据库内容、暂存文件和已经规划的目标文件；
- 恢复所有权或模板集合内部不一致时，界面统一显示通用恢复失败，不暴露内部状态；
- 应用异常退出后，下次启动会完成已提交的收尾，或回滚未完成的恢复；
- 恢复的照片不会自动写入系统相册，可通过“再次保存”发布。

拍摄记录编辑页生成的普通分享 ZIP 不是项目备份，不能用于恢复。

## 诊断与反馈

入口：**设置 → 诊断与反馈**

诊断功能用于生成便于排查问题的本地 ZIP。当前诊断包包含应用版本、构建号、系统版本、系统语言，以及允许列表内的备份、恢复与删除结果、数量和耗时。

隐私边界：

- 诊断记录只保存在本机，不会自动上传；
- 最多保留 7 天，事件文件上限 2 MB；
- 不包含照片、项目名称、项目说明、工程内容、拍摄人、备注；
- 不包含位置坐标、地址、EXIF、照片编号、文件名、文件路径或 SHA-256；
- 不包含原始异常文本和堆栈；
- 诊断事件覆盖备份、恢复与删除结果（不含路径与项目内容）；
- 只有用户主动确认后，诊断 ZIP 才会交给 Android 系统分享面板。

## 存储位置与卸载影响

| 数据 | 默认位置/行为 | 卸载后 |
| --- | --- | --- |
| 项目与记录数据库 | 应用私有目录 | 删除 |
| 私有原图 | 应用私有目录 | 删除 |
| 私有水印文件与处理中间文件 | 应用私有目录 | 删除 |
| 水印相册照片 | `Pictures/SiteMark` | 通常保留 |
| 未复制出去的本地导出/备份 ZIP | 应用私有文档目录 | 删除 |
| 已分享或复制到其他位置的备份 | 用户选择的位置 | 不受 SiteMark 卸载影响 |

“设置 → 存储”显示的是 SiteMark 应用内数据库、原图、水印成片、导出文件和其他文档占用，不包含系统相册占用。

## 隐私与权限

| 权限 | 用途 |
| --- | --- |
| `ACCESS_COARSE_LOCATION`、`ACCESS_FINE_LOCATION` | 可选前台定位；仅在用户主动请求时使用，拒绝后仍可拍照 |
| `POST_NOTIFICATIONS` | Android 13+ 后台处理完成通知 |
| `WAKE_LOCK`、`RECEIVE_BOOT_COMPLETED`、`FOREGROUND_SERVICE` | WorkManager 本地后台处理、重试和恢复 |

发布 APK 不申请：

- `CAMERA`；
- `INTERNET`、`ACCESS_NETWORK_STATE`；
- `ACCESS_BACKGROUND_LOCATION`；
- `READ_MEDIA_IMAGES` 或传统广泛存储权限。

相机权限由外部系统相机应用持有，SiteMark 通过临时 URI 授权提供拍摄目标。更多信息见 [隐私政策](PRIVACY.md) 和 [安全政策](SECURITY.md)。

## 当前限制

- 仅支持 Android 12 及以上系统；
- 不提供 iOS 版本、云同步、多人协作或图库图片导入；
- 水印不是自由拖拽模板；
- 后台任务执行时机仍受 Android 和厂商系统调度策略影响；
- SHA-256 用于本地一致性核对，不代表司法鉴定、可信时间戳或第三方存证；
- 不同厂商相机兼容性仍需要更多真实设备反馈。

## 技术架构

| 层 | 技术 | 职责 |
| --- | --- | --- |
| 应用与界面 | Flutter、Material 3、Riverpod、GoRouter | 中英文界面、主题、导航、表单、项目与记录交互 |
| 数据 | Drift、SQLite | 项目、设置、拍摄记录、项目内模板、状态流转、筛选与数据库迁移 |
| 后台任务 | Kotlin、WorkManager、Dart 后台 isolate | 持久化处理队列、失败重试、启动和重启恢复 |
| Android 集成 | Kotlin、Pigeon、Intent、ContentProvider、LocationManager、MediaStore | 系统相机、可选前台定位、图片检查和相册发布 |
| 图像与归档 | Rust、flutter_rust_bridge | EXIF 方向、全分辨率水印、SHA-256、CSV/JSON/ZIP 和备份校验 |

当前维护的产品与技术说明：

- [当前产品边界与总体架构](docs/current-product-architecture.md)
- [拍摄、后台处理与照片存储生命周期](docs/capture-processing-storage.md)
- [项目、记录、水印与设置](docs/record-watermark-settings.md)
- [关键技术决策记录](docs/decision-records.md)
- [发布检查清单](docs/release-checklist.md)

`docs/superpowers/` 保留早期设计、实施计划和审查记录，用于追溯历史，不代表当前版本行为。

## 质量基线

当前版本的发布门禁包括：

- Flutter 单元与 Widget 全量测试；
- Rust 单元与集成测试；
- `flutter analyze`；
- Rust fmt 与 Clippy；
- Android 插件单元测试，以及 Debug/Release APK 构建；
- APK 包名、版本号、minSdk、targetSdk 和禁止权限检查。

正式安装包由版本标签触发 GitHub Actions 完成签名构建。`v1.0.8` 发布后，下载和校验以对应 GitHub Release 中的实际资源为准；完成真机回归前该版本保持 Pre-release。

## 本地构建

已验证环境：Flutter 3.44.6、JDK 17、Android SDK 36、NDK 28.2.13676358 和稳定版 Rust。

```bash
flutter pub get
flutter analyze
flutter test
cargo fmt --manifest-path rust/Cargo.toml --check
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path rust/Cargo.toml
flutter build apk --debug
```

生产发布需要 `android/key.properties` 和对应 keystore。签名文件与密码不会提交到仓库。

## 参与贡献

欢迎提交缺陷复现、Android 厂商相机兼容性结果、隐私审查和工程记录流程建议。开始前请阅读 [贡献指南](CONTRIBUTING.md)、[安全政策](SECURITY.md) 和 [第三方声明](THIRD_PARTY_NOTICES.md)。自动化编码 Agent 请先阅读 [Agent 执行入口](NEXT_AGENT_PROMPT.md)。

## License

[Apache License 2.0](LICENSE)
