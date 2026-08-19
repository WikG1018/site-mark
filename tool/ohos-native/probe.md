# SiteMark 鸿蒙原生技术探测记录

更新时间：2026-08-19

## 工具链与运行环境

| 项目 | 实测结果 |
| --- | --- |
| DevEco Studio | `DS-243.24978.46.36.611290` |
| HarmonyOS SDK | `6.1.1.125`，API 24 |
| hvigor | `6.24.3` |
| ohpm | `6.1.2.285` |
| 模拟器 | `127.0.0.1:5555`，HarmonyOS Emulator `6.0.0.130`，API 22 |
| 模拟器 ABI | `x86_64` |
| 应用模型 | Stage 模型，ArkTS / ArkUI |
| target / compatible | `6.1.1(24)` / `5.0.5(17)` |

Windows 上 DevEco 自带的 `ohpm.bat` 在本机发生批处理递归，构建脚本固定使用 DevEco 自带 Node 直接执行 `pm-cli.js`；hvigor 同样用 Node 直接执行 `hvigorw.js`，避免受系统 PATH 和批处理包装器影响。

## 冷启动与构建硬闸

- `assembleHap` 成功，生成 `entry-default-unsigned.hap`。
- HAP 通过 HDC 安装到 API 22 / x86_64 模拟器，并完成冷启动。
- Hypium 本地测试链路已安装并通过模板基线测试。
- 鸿蒙原生包名为 `io.github.wikg1018.sitemark.native`，不会覆盖或干扰社区 Flutter 鸿蒙分支的包。

## 平台能力探测

### 1. 系统相机 CameraPicker

API 22 / x86_64 模拟器中，`cameraPicker.pick()` 返回 `undefined`，未得到有效的 `PickerResult`；系统也没有请求 `CAMERA` 权限。产品路径仍使用系统 CameraPicker，不声明相机权限；模拟器回归采用仅调试构建可见的 JPEG 注入通道驱动完整拍摄状态机。真实设备的厂商相机返回 URI、取消语义与方向信息仍需真机复验。

### 2. 相册保存

`PhotoAccessHelper.showAssetsCreationDialog` 可用，会显示系统确认面板“允许‘工程印记’保存 1 张图片？”。允许后返回 `file://media/Photo/...` URI，确认可作为无需私有 ACL 的安全托底路径。产品实现优先尝试平台发布能力；不可用或被拒绝时使用系统确认面板，不把未完成的保存宣称为成功。

### 3. 相册删除

模拟器对刚保存 URI 调用 `MediaAssetChangeRequest.deleteAssets` 返回 `201 Permission denied`，且照片未删除。产品层必须将拒绝视为“保留相册照片”，不得影响应用私有记录删除；真实设备上的系统确认与 ACL 行为待复验。

### 4. 应用详情设置

普通 action/URI 组合在该模拟器上会退回设置首页或返回 `16000019`。可用的系统 Want 为：

```ts
{
  bundleName: 'com.huawei.hmos.settings',
  abilityName: 'com.huawei.hmos.settings.MainAbility',
  uri: 'application_info_entry',
  parameters: { pushParams: context.applicationInfo.name }
}
```

### 5. 外部链接与文件保存

- `UIAbilityContext.openLink('https://github.com/WikG1018/site-mark')` 成功拉起系统浏览器；应用本身不申请网络权限。
- `DocumentViewPicker.save()` 成功拉起系统文件选择器，并展示建议文件名 `SiteMark-Probe.zip`。该链路作为备份、导出与诊断包的用户选择目的地。

## 结论

Task 0 硬闸通过：Stage 空壳可构建、安装、冷启动，五项平台能力均有明确实测结论。相机和相册删除仅能在模拟器确认降级行为，不能据此宣称真机对等；两项会持续登记在 `ohos-native/docs/deltas.md`。
