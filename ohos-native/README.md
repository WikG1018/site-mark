# SiteMark 鸿蒙原生版

本目录是 SiteMark 的 HarmonyOS NEXT 原生实现，使用 Stage 模型、ArkTS 和 ArkUI，不依赖 Flutter 鸿蒙分支。项目、拍摄记录、筛选与批量处理、水印设置、备份恢复、存储统计和诊断均在鸿蒙原生层实现；图像渲染与归档复用仓库根目录的同一 Rust 核心。

## 当前状态

- 原生包名：`io.github.wikg1018.sitemark.native`，不会覆盖历史 Flutter `ohos` 试验包。
- 目标 SDK：HarmonyOS 6.1.1 / API 24；当前功能回归在 API 22 x86_64 模拟器完成。
- Rust 原生库同时生成 `arm64-v8a` 和 `x86_64` 两种 ABI。
- 调试 HAP 可构建并安装；正式签名和 HarmonyOS 真机回归尚未完成，因此不宣称真机全量对等。
- 当前自动化基线：33 项 ArkTS 单元测试，以及共享 Rust 核心的 fmt、Clippy 和全量测试。

已知平台差异和不可越界的验证边界见 [docs/deltas.md](docs/deltas.md)，工具链与模拟器实测见 [tool/ohos-native/probe.md](../tool/ohos-native/probe.md)。

## 产品能力

| 范围 | 鸿蒙原生实现 |
| --- | --- |
| 项目 | 不重名创建、搜索、置顶、重命名、进行中/已完成/已归档生命周期、删除 |
| 拍摄 | 调用系统 CameraPicker，三个必填字段连拍保留，备注清空，定位可选且拒绝不阻止拍摄 |
| 处理 | 应用存活期串行渲染，失败重试，启动时对账，发布日记按 `captureId` 持久化 |
| 记录 | 项目/日期/关键词筛选，缩略图，详情，成片/原图，全屏相邻浏览，编辑，全选/取消全选 |
| 批量操作 | 导出所选、再次保存、清理原图、删除记录；删除前完成全库引用检查 |
| 水印 | 项目名、部位、内容、拍摄人、时间和可选位置；支持位置、透明度、字体比例和强调色 |
| 数据 | 单/多项目 ZIP 备份与恢复、恢复事务和中断收敛、应用私有存储统计 |
| 应用 | 首启隐私门、中英文、浅色/深色/跟随系统、诊断包、外部 GitHub 链接 |

## 权限与数据边界

应用只声明前台精确/模糊定位权限，不声明 `INTERNET`、`CAMERA`、广泛媒体读写权限。实际拍摄交给系统相机；保存到系统相册时使用 HarmonyOS 系统确认面板。GitHub 仓库链接交给外部浏览器，应用自身不联网。

卸载会删除 RDB、私有原图、私有水印成片和未另存的导出文件。经用户确认保存到系统相册或文件选择器外部位置的副本不在应用私有目录内。

## 本地构建

需要 DevEco Studio 6.1.1.300 及其内置 HarmonyOS SDK、稳定版 Rust 和已安装的 `x86_64-unknown-linux-ohos` / `aarch64-unknown-linux-ohos` Rust 目标。

```powershell
# 编译两种 ABI 的共享 Rust 核心
pwsh -File .\tool\ohos-native\build-rust.ps1

# 执行 ArkTS 测试并构建 debug HAP
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests

# 构建 release 变体（未配置签名时仍为 unsigned）
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -BuildMode release
```

调试 HAP 位于 `ohos-native/entry/build/default/outputs/default/entry-default-unsigned.hap`。生产签名需在 DevEco 中配置自有证书；签名文件和密码不得提交。

## 开发调试通道

API 22 模拟器的 CameraPicker 无法返回可用拍摄结果。只有 `applicationInfo.debug == true` 时，应用才会注入 `rawfile/probe.jpg` 驱动完整拍摄状态机；发布变体不会进入该通道。这不是产品相机实现，也不代表真机相机已验收。
