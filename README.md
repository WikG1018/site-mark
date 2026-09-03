# SiteMark 工程印记

[English](README_EN.md) | 简体中文

> 面向工程现场记录的本地水印相机：Android 版稳定发布（Latest `v1.0.16`，targetSdk 37 / Android 17），HarmonyOS NEXT 原生 ArkTS 版同步发布当前版本（未签名 HAP），iOS 版复用同一套 Flutter 代码完成全量适配（iOS 26/27 界面形态、后台补拍、深色模式），等待 Apple Developer 账号进入签名发布，当前无可安装包。仓库单分支维护三条产品线。

An offline-first engineering watermark camera with a stable Android release
(Latest `v1.0.16`, targeting Android 17), a native HarmonyOS NEXT implementation published
alongside it, and an iOS build on the shared Flutter codebase that is fully adapted
(iOS 26/27-style UI, background catch-up, dark mode) and awaits an Apple Developer
account for signed distribution — no installable package yet. All product lines live on a
single branch.

[![CI](https://github.com/WikG1018/site-mark/actions/workflows/ci.yml/badge.svg)](https://github.com/WikG1018/site-mark/actions/workflows/ci.yml)
![Android 12+](https://img.shields.io/badge/Android-12%2B-3DDC84?logo=android&logoColor=white)
![HarmonyOS native](https://img.shields.io/badge/HarmonyOS-native%20ArkTS-E60012)
[![License](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)
![No ads](https://img.shields.io/badge/Ads-none-176B55)
![NAS sync](https://img.shields.io/badge/NAS_sync-WebDAV%20%2F%20SFTP%20%2F%20SMB-176B55)
[![Latest](https://img.shields.io/badge/latest-v1.0.16-176B55)](https://github.com/WikG1018/site-mark/releases/tag/v1.0.16)
[![HarmonyOS](https://img.shields.io/badge/HarmonyOS-native--v1.0.8-E60012)](https://github.com/WikG1018/site-mark/releases/tag/native-v1.0.8)

**当前稳定版本（Latest）：[`v1.0.16`](https://github.com/WikG1018/site-mark/releases/tag/v1.0.16)**

**鸿蒙原生版当前版本：[`native-v1.0.8`](https://github.com/WikG1018/site-mark/releases/tag/native-v1.0.8)（HarmonyOS NEXT，未签名 HAP）**

支持 Android 12（API 31）及以上系统。`v1.0.16` 已设为 Latest：优化 NAS 同步设置页的表单排版（字段间距、分组节奏、协议标签与分段按钮对齐全局设置规范）。功能基线与 v1.0.15 一致：三端可选 NAS 同步（WebDAV/SFTP/SMB，默认关闭，密码只存系统安全存储）、队列计数与失败重试入口、审查修复全部包含。重要项目请定期创建包含私有原图的备份，并把备份文件复制到应用目录之外。


## 下载

### 稳定版（Latest，推荐）

| 安装包 | 适用设备 | 下载 |
| --- | --- | --- |
| arm64 | 推荐；绝大多数近年 Android 手机 | [sitemark-v1.0.16-arm64.apk](https://github.com/WikG1018/site-mark/releases/download/v1.0.16/sitemark-v1.0.16-arm64.apk) |
| universal | 不确定处理器架构或 arm64 无法安装时使用；文件更大 | [sitemark-v1.0.16-universal.apk](https://github.com/WikG1018/site-mark/releases/download/v1.0.16/sitemark-v1.0.16-universal.apk) |
| SHA-256 | 校验下载文件是否完整 | [SHA256SUMS.txt](https://github.com/WikG1018/site-mark/releases/download/v1.0.16/SHA256SUMS.txt) |

### 鸿蒙原生版（native-v1.0.8）

| 安装包 | 适用设备/说明 | 下载 |
| --- | --- | --- |
| HarmonyOS HAP | **未签名**，需在 DevEco/hdc 环境自行签名后安装；正式签名需 AGC 发布证书（见 `tool/ohos-native/sign-hap.ps1`）。当前发布的 HAP 为 debug 构建变体（未签名的 release 包无法直接安装） | [sitemark-native-v1.0.8-unsigned.hap](https://github.com/WikG1018/site-mark/releases/download/native-v1.0.8/sitemark-native-v1.0.8-unsigned.hap) |
| HarmonyOS SHA-256 | 校验下载文件是否完整 | [SHA256SUMS.txt](https://github.com/WikG1018/site-mark/releases/download/native-v1.0.8/SHA256SUMS.txt) |

> [!WARNING]
> 卸载 SiteMark 会删除应用数据库、应用私有原图和私有水印文件。已经发布到系统相册 `Pictures/SiteMark` 的水印照片通常仍会保留。卸载、换机或处理签名冲突前，请先进入“设置 → 备份与恢复”，备份重要项目并把 ZIP 保存到可靠位置。

## HarmonyOS NEXT 原生版

`ohos-native/` 是独立的 Stage + ArkTS + ArkUI 实现，不使用社区 Flutter 鸿蒙适配层，与 Android 版同仓库单分支演进。它已在 DevEco NEXT 模拟器跑通项目、拍摄处理、记录管理、水印、备份恢复、存储与诊断主流程，图像与 ZIP 规则复用 Android 版的同一 Rust 核心。

当前提供 `native-v1.0.8` 的 unsigned HAP（见上方下载表），**尚未提供签名的鸿蒙安装包，也未上架华为应用市场**；真机相机、相册权限和性能仍需在 HarmonyOS NEXT 真机复验。请不要把模拟器结果解读为已完成应用市场发布。

- [鸿蒙原生版说明与构建](ohos-native/README.md)
- [平台差异与验证边界](ohos-native/docs/deltas.md)
- [DevEco 与模拟器技术探测](tool/ohos-native/probe.md)
- [鸿蒙原生版发布记录](https://github.com/WikG1018/site-mark/releases?q=native-&expanded=false)

## iOS 版

iOS 与 Android 共用同一套 Flutter 界面、业务逻辑、数据库 schema 和 Rust 图像核心；平台能力（系统相机桥、可选前台定位、相册发布与删除、BGTaskScheduler 机会性后台补拍）由仓库内的 Swift 插件承接。界面已按 iOS 26/27 形态全量适配：大标题导航、Cupertino 动作表与对话框、玻璃胶囊提示、边缘滑动返回，深色模式全表面正确。

剩余工作只有两类，且都需要外部条件：一是 Apple Developer 账号到位后，由 GitHub Actions 完成 TestFlight 与签名发布（证书材料不入库）；二是在真机上验证启动屏深色、滑动手感与相机实拍。在此之前不提供任何 iOS 安装包，也不承诺时间。

## 安装与升级

1. 优先下载 arm64 安装包；只有设备不兼容时再使用 universal。
2. 打开 APK，按 Android 提示允许浏览器或文件管理器“安装未知应用”。
3. 正式 Release 使用同一签名，可以直接覆盖升级并保留应用数据。
4. Debug APK 与正式版签名不同，通常不能直接覆盖安装。
5. 如果 Android 提示签名冲突，不要直接卸载保存着重要数据的旧版本；先完成项目备份并确认备份文件已复制到应用目录之外。

## 近期更新

完整说明见各版本 [GitHub Release](https://github.com/WikG1018/site-mark/releases)。

- **v1.0.16**（Latest）：NAS 同步设置页表单排版优化——字段间距、分组节奏，协议标签与分段按钮对齐全局设置规范（48dp 触达高度）；Android-only，功能与 v1.0.15 一致。
- **v1.0.15 / native-v1.0.8**：NAS 全面审查修复——设置页新增上传队列计数与“重试失败的上传”入口；测试连接在密码留空时使用已保存密码；端口越界在保存/测试前拦截；处理中的记录延后排队而不消耗重试预算（防空转）；上传与凭据读取异常兜底为分类错误。
- **v1.0.14 / native-v1.0.7**：三端新增可选 NAS 同步（WebDAV/SFTP/SMB，默认关闭，仅访问用户自配服务器，密码存系统安全存储）；Android/iOS 数据库迁移至 v14（NAS 配置与上传簿记表），鸿蒙 RDB 迁移至 v15；上传走串行队列 + 5 次尝试预算，SFTP 首连核对主机指纹。
- **v1.0.13 / native-v1.0.6**：修复全屏照片查看器双指缩放后无法单指拖动查看角落的问题（Android 与鸿蒙原生同修）；README 新增英文版并支持中英切换。
- **v1.0.12 / native-v1.0.5**（Pre-release）：双版本全量审查修复（只读批量绕过、跨端水印域统一、深色对比度、冷启动通知路由、草稿耐久性）。
- **v1.0.11**：targetSdk 提升到 Android 17（API 37），compileSdk 同为 37；已审查 Android 17 定向行为变化（大屏方向/可调整性规则、后台 Activity 启动收紧、本地网络权限、后台音频、MessageQueue、原生库加载），对本离线应用均无影响，运行时行为与 36 一致，真机回归通过。
- **v1.0.10**（Pre-release）：修复全部记录/项目记录页在选择模式下按系统返回直接退到桌面的问题，返回现在先取消选择（搜索、筛选同层处理）。
- **v1.0.9 / native-v1.0.3**（Pre-release，2026-08-28，双线并轨后首个联合版本）：Android——完成通知跟随应用内语言、定位失败诊断留痕、导出证据守卫、未知状态容错、compileSdk 37；鸿蒙原生——失败原因存码并随语言切换刷新、错误文案分类化、导出原子写 + ZIP64 大文件、数据库迁移脚手架。
- **v1.0.8**：相册安全替换、跨层 journal 对账、共享 URI 保护、清理重试上限。
- **v1.0.7**：恢复不再误删项目；拍摄处理幂等；解码与相册防线收紧。
- **v1.0.6**：媒体清理可恢复；相册发布失败可回滚。
- **v1.0.0–v1.0.5**：项目生命周期与备份、悬浮导航、搜索与全屏浏览、发布链路稳定化。

## 功能总览

| 范围 | 当前状态 |
| --- | --- |
| 一级导航 | “项目 / 全部记录 / 设置”通过紧凑悬浮 Dock 切换，选中背景覆盖图标和文字；分别保留列表、搜索和筛选状态，但只绘制当前页面；进入详情等二级页面后 Dock 隐藏 |
| 拍摄 | 调用系统/厂商相机，连续拍摄时后台生成水印；下一张保留工程部位、工作内容和拍摄人，仅清空备注；支持最近字段建议和项目内命名模板；非进行中项目禁止新拍摄 |
| 记录 | 缩略图列表在筛选按钮右侧显示当前可见日期，并随滚动更新；详情支持“成片 / 原图”和“现场记录 / 文件信息”切换，点击照片可进入相邻照片全屏浏览；支持编辑、删除和再次保存 |
| 检索 | 首页状态筛选与跨状态项目搜索；全部记录和项目记录支持关键词搜索，以及从紧凑底部面板选择项目、年、月、日，已生效条件可单独移除 |
| 批量操作 | 复选框覆盖缩略图，不挤压照片和文字；多选时以带图标与文字的紧凑悬浮 Dock 替换一级导航；支持按当前筛选结果全选/取消全选、导出、再次保存、清理原图和删除整条记录 |
| 水印 | 项目名称、现场字段、时间和可选位置；支持位置、透明度、字体大小和强调色 |
| 项目 | 生命周期、置顶、同名/安全文件名冲突保护；支持重命名、删除和项目级水印设置 |
| 设置 | 一级页按“拍摄与记录 / 数据与安全 / 应用”分组，集中进入水印默认值、定位、通知、备份恢复、存储、NAS 同步、诊断、语言、外观与关于 |
| 数据安全 | 项目备份恢复、原图 SHA-256 校验、恢复事务与文件回滚、异常中断清理 |
| NAS 同步 | 可选功能（默认关闭）：把水印成片上传到你自建的 WebDAV / SFTP / SMB 服务器；仅 Wi-Fi 可选、失败自动重试（5 次预算）、SFTP 主机指纹核对（TOFU）；密码只存系统安全存储，不进备份、诊断或数据库 |
| 体验 | 玻璃材质导航与卡片、稳定且符合层级关系的页面转场、图片 Hero 动画、无隐藏列表闪现的返回逻辑、减少动画适配，以及可继续加载的记录和全屏图片列表 |

## 产品定位

我做 SiteMark，是因为工程现场的记录需求远不止“给照片加文字”：拍摄要顺手、后台处理要稳、项目归档要清晰、原图信息要可回查。

我刻意不在应用里重新实现相机，也不嵌第三方相机 SDK——厂商对着自家镜头调校了多年，应用层重做一遍只会更差。SiteMark 通过系统标准能力调用手机系统/厂商相机，把对焦、HDR、防抖和画质留给系统；自己只做三件事：拍摄前的工程信息、拍摄后的本地水印处理、以及记录与项目备份。

发布 APK 没有广告、账号、第三方云同步或统计上传；点击 GitHub 仓库链接时交给外部浏览器处理。唯一的网络出口是你主动配置并启用的 NAS 同步（WebDAV/SFTP/SMB，见 `docs/decision-records.md` D-023）：上传只发往你自己填写的服务器，默认关闭。离线仍是默认状态，网络是用户手中显式打开的例外。

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
- 最多保留 7 天，事件文件上限 2 MB（该保留策略为 Android 版实现；鸿蒙原生版当前保留最近 200 条事件）；
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
| `INTERNET`、`ACCESS_NETWORK_STATE` | 可选 NAS 同步（WebDAV/SFTP/SMB）；仅在你配置并启用后访问你自己的 NAS 服务器，Wi-Fi 限制判定也用到网络状态 |

发布 APK 不申请：

- `CAMERA`；
- `ACCESS_BACKGROUND_LOCATION`；
- `READ_MEDIA_IMAGES` 或传统广泛存储权限。

相机权限由外部系统相机应用持有，SiteMark 通过临时 URI 授权提供拍摄目标。更多信息见 [隐私政策](PRIVACY.md) 和 [安全政策](SECURITY.md)。

## 当前限制

- 当前可下载稳定版仅支持 Android 12 及以上系统；HarmonyOS NEXT 原生版仅有 Pre-release 的未签名 HAP，尚未上架应用市场；iOS 版已完成适配但尚无签名发布（等 Apple Developer 账号），当前无可安装包；
- 不提供第三方云同步、多人协作或图库图片导入；NAS 同步只面向你自己搭建的服务器；
- 水印不是自由拖拽模板；
- 后台任务执行时机仍受 Android 和厂商系统调度策略影响；iOS 上由系统机会性调度后台补拍，不保证拍完立刻处理；
- SHA-256 用于本地一致性核对，不代表司法鉴定、可信时间戳或第三方存证；
- 不同厂商相机兼容性仍需要更多真实设备反馈。

## 技术架构

| 层 | 技术 | 职责 |
| --- | --- | --- |
| 应用与界面 | Flutter、Material 3、Riverpod、GoRouter | 中英文界面、主题、导航、表单、项目与记录交互 |
| 数据 | Drift、SQLite | 项目、设置、拍摄记录、项目内模板、状态流转、筛选与数据库迁移 |
| 后台任务 | Kotlin、WorkManager、Dart 后台 isolate | 持久化处理队列、失败重试、启动和重启恢复 |
| Android 集成 | Kotlin、Pigeon、Intent、ContentProvider、LocationManager、MediaStore | 系统相机、可选前台定位、图片检查和相册发布 |
| iOS 集成 | Swift、Pigeon、BGTaskScheduler、PHPhotoLibrary | 系统相机桥、可选前台定位、图片检查、相册发布与删除、机会性后台补拍 |
| 图像与归档 | Rust、flutter_rust_bridge | EXIF 方向、全分辨率水印、SHA-256、CSV/JSON/ZIP 和备份校验 |

HarmonyOS NEXT 原生线使用 Stage + ArkTS + ArkUI、RelationalStore、Preferences、CameraPicker 和 PhotoAccessHelper，通过 C ABI + C++ N-API 调用同一 `sitemark_core` Rust crate。两条产品线共享业务语义、图像和归档算法，不共享 UI SDK 或数据库文件。iOS 线复用同一套 Flutter 界面、业务逻辑与 Rust 核心，平台能力由仓库内 Swift 插件（Pigeon + BGTaskScheduler）承接，与 Android 共享业务语义、数据库 schema 和备份格式，详见[当前产品边界与总体架构](docs/current-product-architecture.md)第 10 节。

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

涉及鸿蒙原生代码时，同时检查鸿蒙 manifest 的最小权限集、双 ABI 配置，并以 `ohos-native` feature 单独执行 Rust Clippy/测试。ArkTS 测试与 HAP 打包需要 DevEco Studio SDK，当前在本地 DevEco 环境验证。

正式安装包由版本标签触发 GitHub Actions 完成签名构建。`v1.0.16` 已设为 Latest；鸿蒙原生版仍为未签名 debug 构建 HAP，AGC 证书材料到位后提供正式签名包。下载和校验以对应 GitHub Release 中的实际资源为准。

## 本地构建

已验证环境：Flutter 3.44.6、JDK 17、Android SDK 37（compileSdk / targetSdk 37）、NDK 28.2.13676358 和稳定版 Rust。鸿蒙原生线另需 DevEco Studio（含 HarmonyOS SDK）。

```bash
flutter pub get
flutter analyze
flutter test
cargo fmt --manifest-path rust/Cargo.toml --check
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path rust/Cargo.toml
flutter build apk --debug
```

鸿蒙原生线（需要 DevEco Studio）：

```powershell
pwsh -File ./tool/ohos-native/build-rust.ps1              # 新工作树首次必须
pwsh -File ./tool/ohos-native/build-hap.ps1 -SkipRust -RunTests   # ArkTS 测试 + unsigned HAP
pwsh -File ./tool/ohos-native/run-host-tests.ps1          # 主机契约门禁
```

生产发布需要 `android/key.properties` 和对应 keystore。签名文件与密码不会提交到仓库。

## 参与贡献

欢迎提交缺陷复现、Android 厂商相机兼容性结果、隐私审查和工程记录流程建议。开始前请阅读 [贡献指南](CONTRIBUTING.md)、[安全政策](SECURITY.md) 和 [第三方声明](THIRD_PARTY_NOTICES.md)。

## License

[Apache License 2.0](LICENSE)
