# SiteMark 工程印记

> 调用手机厂商系统相机的开源工程水印相机：无广告、无云端、原图留在本机。

An open-source, offline-first engineering watermark camera that keeps the
manufacturer camera experience.

[![CI](https://github.com/WikG1018/site-mark/actions/workflows/ci.yml/badge.svg)](https://github.com/WikG1018/site-mark/actions/workflows/ci.yml)
![Android 12+](https://img.shields.io/badge/Android-12%2B-3DDC84?logo=android&logoColor=white)
[![License](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)
![Offline](https://img.shields.io/badge/Network-offline--first-176B55)
![Status](https://img.shields.io/badge/status-v0.2.0--alpha-orange)

**当前状态：`v0.2.0-alpha`。尚未发布生产签名 APK，欢迎开发者参与测试。**

## 实际效果 / Screenshots

<table>
  <tr>
    <td align="center"><img src="docs/images/readme/01-projects.png" alt="项目列表" width="260"><br><sub>项目列表</sub></td>
    <td align="center"><img src="docs/images/readme/02-capture-form.png" alt="现场记录表单" width="260"><br><sub>现场记录表单</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/images/readme/03-system-camera.png" alt="Android 系统相机" width="260"><br><sub>独立的 Android 系统相机</sub></td>
    <td align="center"><img src="docs/images/readme/04-watermarked-output.jpg" alt="工程水印成片" width="260"><br><sub>工程水印成片</sub></td>
  </tr>
</table>

截图来自 Android 16 / API 36 模拟器，使用 AOSP 合成相机和虚构工程数据。
不同品牌手机的系统相机界面、镜头能力和成像效果会有所不同。

## 为什么做工程印记 / Why SiteMark

工程现场需要的不只是“在照片上加几行字”，还需要顺手的拍摄体验、清晰的项目归档，
以及可以解释照片从哪里来、何时生成的记录链路。

SiteMark 不在应用里重做一套相机界面，而是通过 Android 标准 Intent 调用手机厂商相机。
用户继续使用手机原有的对焦、HDR、防抖、镜头切换和画质调校；SiteMark 负责拍摄前的
工程信息、拍摄后的本地水印处理与项目导出。

- **没有广告和统计 SDK**：应用内没有广告位、账号系统或行为分析。
- **离线优先**：照片、水印和项目数据都在手机本地处理，不依赖云服务。
- **原图与成片分离**：原图保存在应用私有目录，只把完成的水印 JPEG 发布到相册。
- **面向工程归档**：按项目组织记录，自动编号，并可导出照片、CSV 和 JSON 清单。
- **连续拍摄不打断**：拍完一张立刻回到表单，工程部位、工作内容、拍摄人自动保留，
  仅清空备注；照片进入后台处理队列，不阻塞下一张。
- **后台串行处理**：水印渲染通过 WorkManager 在后台串行执行、持久化、最多重试三次，
  覆盖同一 MediaStore 条目；应用被划掉或重启后可继续完成未处理项。后台启动时间由
  系统调度决定；Android “强制停止”会暂停计划任务，重新打开应用后恢复。

## 核心能力

| 能力 | 实现方式 | 对工程记录的价值 |
| --- | --- | --- |
| 调用系统相机 | 使用 `ACTION_IMAGE_CAPTURE` 和一次性授权的私有输出 URI | 保留手机厂商相机的拍摄体验与成像能力 |
| 全程本地处理 | Flutter/Kotlin 协调流程，Rust 处理方向、水印和哈希 | 无需账号、云端或网络即可完成拍摄归档 |
| 私有保存原图 | 原始照片留在应用私有目录 | 避免原图直接暴露给其他应用或相册扫描 |
| 发布水印成片 | 仅将完成的 JPEG 写入 `Pictures/SiteMark` | 相册、文件管理器和工程交付流程可直接使用 |
| 连续拍摄保留字段 | 拍摄后表单保留工程部位/工作内容/拍摄人，仅清空备注 | 连续多张拍摄时无需重复录入，专注每张备注 |
| 后台串行处理队列 | WorkManager 串行链、持久化、三次重试、MediaStore 覆盖 | 拍摄不等待渲染；崩溃或重启后能继续完成 |
| 图片预览 | 列表缩略图 + 详情页全屏放大查看 | 快速核对成片，不必离开应用 |
| 日期与项目筛选 | 项目详情与全局「全部记录」共享同一筛选卡，支持年/月/日级联 | 按日期或工程快速定位记录 |
| 全局设置 | 主题、语言、新建项目水印默认值与关于信息 | 统一外观与默认值，现有项目设置不受影响 |
| 固化采集证据 | 保存照片编号、拍摄时间、坐标和原图 SHA-256 | 为后续核对提供可追溯元数据，不提供司法鉴定结论 |
| 受约束的水印设置 | 每个项目可调整左右位置、卡片透明度和强调色；水印字号较 v0.1.0 放大 20% | 保持项目内版式一致，同时适配不同画面 |
| 开放源代码 | Apache License 2.0 | 代码、权限和数据流均可审查，也便于二次开发 |

支持简体中文和英文界面。

## 使用流程

1. **新建项目**：按工程组织照片和水印设置；新建项目会复制当前全局水印默认值。
2. **填写现场信息**：录入工程部位、工作内容、拍摄人和可选备注。
3. **选择位置授权**：拍摄前仅请求一次前台位置；拒绝授权也可以继续拍摄。
4. **调用系统相机**：由手机厂商相机完成取景、拍照和确认。
5. **后台生成工程成片**：照片加入后台串行队列，校正 EXIF 方向、渲染全分辨率水印、
   计算 SHA-256，随后发布到系统相册。拍摄表单立刻恢复可用，三项描述字段保留、备注清空。
6. **浏览与筛选**：在项目详情或全局「全部记录」中按年/月/日和项目筛选，缩略图点击可
   全屏放大查看；列表会从等待/处理中过渡到已完成，缩略图随后切换为水印成片。
7. **归档与导出**：按项目查看记录，必要时修正描述字段并重新生成，或导出完整项目包。
8. **全局设置**：在设置中切换主题（浅色/深色/跟随系统）与语言（简体中文/English），
   调整新建项目水印默认值，或在关于页查看版本与隐私声明。后台处理由系统调度，
   Android「强制停止」会暂停计划任务，重新打开应用后恢复。

## 安装与当前状态

SiteMark 目前处于 **alpha 开发阶段**，还没有面向普通用户的生产签名安装包。

- GitHub Actions 会在每次 CI 中构建 `sitemark-debug-apk`，仅供开发和测试使用。
- 生产签名、首个预发布版本和多品牌实体机兼容性验证完成后，才会在
  [Releases](https://github.com/WikG1018/site-mark/releases) 提供正式下载。
- 当前最低系统版本为 **Android 12（API 31）**。

如果你只是想体验，建议等待第一个预发布 APK；如果你愿意参与测试，可以按下方步骤
本地构建，或从已通过的 [Actions](https://github.com/WikG1018/site-mark/actions)
运行中下载调试产物。

## 隐私与权限

应用声明的用户可见权限：

| 权限 | 用途 | 是否阻塞拍照 |
| --- | --- | --- |
| `ACCESS_COARSE_LOCATION` | 可选的前台近似位置 | 否 |
| `ACCESS_FINE_LOCATION` | 可选的前台精确位置 | 否 |
| `WAKE_LOCK`、`RECEIVE_BOOT_COMPLETED` | WorkManager 本地后台处理与重启补偿 | 否 |
| `FOREGROUND_SERVICE` | WorkManager 后台任务执行 | 否 |

以上权限均为本地后台处理所需，不涉及网络访问。

所有构建变体（Release、Debug、Profile）**均不申请** `CAMERA`、`INTERNET`、
`ACCESS_NETWORK_STATE`、`ACCESS_BACKGROUND_LOCATION`、`READ_MEDIA_IMAGES` 或传统存储权限。
`INTERNET` 与 `ACCESS_NETWORK_STATE` 通过 `tools:node="remove"` 在 main、debug、profile
清单中统一剥离，确保离线边界在所有变体生效。相机由外部系统应用持有；SiteMark 只通过 Android
URI 授权机制临时提供一个拍摄目标。

完整说明见 [隐私政策 / Privacy Policy](PRIVACY.md) 和
[安全政策 / Security Policy](SECURITY.md)。

## 水印与项目导出

默认水印可包含：项目名称、工程部位、工作内容、拍摄人、照片编号、拍摄时间和坐标。
照片编号、时间、坐标与原图 SHA-256 作为采集证据保存；工程部位、工作内容、拍摄人和
备注属于描述字段，可以修正并重新生成水印成片。

项目导出为 ZIP，可包含：

- 已完成的水印 JPEG；
- 带 UTF-8 BOM 的 CSV，方便在常见表格软件中直接打开；
- 带版本号的 JSON manifest；
- 用户明确选择时附带的私有原图。

SHA-256 仅用于原图一致性核对和追溯；SiteMark 不提供司法鉴定结论或第三方存证服务。

## 技术架构 / Architecture

| 层 | 技术 | 职责 |
| --- | --- | --- |
| 应用与界面 | Flutter、Material 3、Riverpod、GoRouter、Drift/SQLite | 中英文界面、项目/记录状态、本地数据库、连续拍摄字段保留与全局设置 |
| 后台处理 | Kotlin、WorkManager | 串行渲染队列、持久化、三次重试、开机与崩溃后恢复 |
| Android 集成 | Kotlin、Intent、ContentProvider、LocationManager、MediaStore | 系统相机调用、进程恢复标记、可选位置和相册发布 |
| 图像与导出 | Rust、flutter_rust_bridge | EXIF 方向、全分辨率水印（字号较 v0.1.0 放大 20%）、SHA-256、CSV/JSON/ZIP 导出 |

详细设计与决策记录：

- [SiteMark v0.1.0 产品与技术设计](docs/superpowers/specs/2026-07-16-sitemark-design.md)
- [SiteMark v0.1.0 实施计划](docs/superpowers/plans/2026-07-16-sitemark-v0.1.0.md)
- [README 产品首页改版设计](docs/superpowers/specs/2026-07-16-readme-redesign-design.md)
- [README 产品首页实施计划](docs/superpowers/plans/2026-07-16-readme-redesign.md)

## 本地构建 / Build locally

已验证的开发环境：Flutter 3.44.6、JDK 17、Android SDK 36、
NDK 28.2.13676358，以及稳定版 Rust（本次验证为 1.95.0）。

```bash
flutter pub get
flutter analyze
flutter test
cargo test --manifest-path rust/Cargo.toml
flutter build apk --debug
```

生产发布还需要本地 `android/key.properties` 与对应 keystore；签名文件和密码不会提交到
仓库。完整发布步骤和设备验收项见 [Release checklist](docs/release-checklist.md)。

## 验证状态与路线图

`v0.2.0-alpha` 已完成（自动化验证，Windows 主机）：

- Flutter 静态检查无问题，87 项 Dart 测试通过；
- Rust 格式检查与 6 项测试通过，包含水印字号放大 20% 与横竖版适配；
- Android 单元测试与 Debug APK 构建通过；
- 数据库 v2 -> v3 迁移、后台串行处理与重试幂等性、日期/项目筛选、全局设置持久化、
  水印几何尺寸均有对应自动化测试通过；
- Debug Alpha APK（`0.2.0+2`）已生成并校验包名、版本、权限与签名。

实体机设备验收（连续拍摄、后台处理、重启恢复、多厂商相机兼容性等 8 项）尚未在本
环境执行，详见 [v0.2.0-alpha 验证记录](docs/verification-v0.2.0-alpha.md)。

`v0.1.0-alpha` 已完成的模拟器端到端验收见
[v0.1.0-alpha 验证记录](docs/verification-v0.1.0-alpha.md)。

稳定发布前仍需完成：Android 12 实体机，以及 Samsung、Xiaomi/Redmi、OPPO/OnePlus、
vivo、Honor、Pixel 等代表性厂商相机的兼容性矩阵；位置授权分支、相机中断恢复、原位
重生成和签名发布也需要在实体机上复核。

## 参与贡献

欢迎提交 Android 厂商相机兼容性结果、缺陷复现、隐私审查和工程工作流建议。
开始前请阅读 [Contributing guide](CONTRIBUTING.md)、[Security policy](SECURITY.md)
与 [Third-party notices](THIRD_PARTY_NOTICES.md)。

## License

[Apache License 2.0](LICENSE)
