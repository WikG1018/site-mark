# SiteMark 鸿蒙原生版上架检查清单

本清单不代表已上架。在真机回归、正式签名和市场材料齐备前，不应创建公开发布。

## 产品与账号

- [ ] 确认开发者主体、软著/应用名称可用性和“工程印记”展示名。
- [ ] 确认包名 `io.github.wikg1018.sitemark.native` 与 AppGallery Connect 应用记录一致。
- [ ] 确认 `versionCode` 严格递增，`versionName` 与发布说明一致。
- [ ] 准备可公开访问的隐私政策 URL、开源许可说明和支持联系方式。

## 签名与产物

- [ ] 使用发布证书构建 HAP；仓库与 CI 不保存证书私钥、密码或本地签名配置。
- [ ] 检查 HAP 同时包含 `arm64-v8a` 和 `x86_64` 原生库，且不包含调试符号和本地路径。
- [ ] 在真机完成新安装、覆盖升级和卸载数据边界回归。
- [ ] 保存最终 HAP SHA-256，并与实际上传文件一致。

## 权限与隐私

- [ ] 上传前重新导出 manifest，确认声明前台定位、`INTERNET` 与 `GET_NETWORK_INFO`，且未声明 `CAMERA`、后台定位或广泛媒体读写权限。
- [ ] 确认声明了可选 NAS 同步所需的 `INTERNET` 与 `GET_NETWORK_INFO`，且未声明 `CAMERA`、后台定位或广泛媒体读写权限。
- [ ] 首启隐私门未同意时不进入主界面、不请求权限；中英文文案与隐私政策一致。
- [ ] 真机复验前台定位的首次提示、拒绝、永久拒绝和设置页返回。
- [ ] 确认诊断 ZIP 不包含照片、项目/工程字段、人员、位置、路径、文件标识、哈希、原始异常或堆栈。

## 真机功能回归

- [ ] 系统相机：拍摄、取消、前后摄、旋转/EXIF、厂商相机切换、拍后立即杀进程。
- [ ] 处理：连拍时可继续操作，编号连续，状态刷新，失败可解释，启动对账可收敛。
- [ ] 相册：允许/拒绝保存、再次保存、用户已手动删除、共享 URI、删除授权拒绝。
- [ ] 数据：清理原图、删除记录、删除项目不删外部备份/相册照片，多项目备份与恢复。
- [ ] 性能：至少用 12MP 与 50MP JPEG、500+/2000+ 条记录、快速连拍和内存压力复验。
- [ ] 无障碍：字体放大、深色模式、屏幕阅读、减少动画和触摸目标。

## 市场材料

- [ ] 准备 2–5 张真机截图，覆盖项目、拍摄表单、记录详情、全部记录与设置；不使用模拟器调试样图伪装真机截图。
- [ ] 中英文应用介绍、更新说明、搜索关键词、图标和分类一致。
- [ ] 介绍中明确：无广告、无账号、不自带相机、定位可选、卸载前应备份。
- [ ] 审核备注中说明系统相机、系统保存面板、文件选择器和可选定位的触发步骤。

## 本地签名流水线（2026-08-29）

发布签名材料只能来自 AGC（AppGallery Connect），仓库不保存证书私钥：

1. AGC → 证书/APP/Profile：创建发布证书（下载 `.cer`）、发布 Profile（下载 `.p7b`），
   并使用证书请求对应的 `.p12` 密钥库（连同密码与别名）。
2. 一键签名（材料放在仓库外或 git-ignored 路径）：

   ```powershell
   pwsh -File ./tool/ohos-native/sign-hap.ps1 `
     -Hap ohos-native/entry/build/default/outputs/default/entry-default-unsigned.hap `
     -Profile <release>.p7b -AppCert <release>.cer -Keystore <keystore>.p12 `
     -KeyAlias <alias> -KeystorePass <storePassword> -KeyPass <keyPassword>
   ```

   脚本内部调用 DevEco SDK 自带的 `hap-sign-tool.jar` 完成签名并执行
   `verify-app` 校验，输出产物路径与 SHA-256。
3. 产物通过 `hdc install` 在真机验证后，再作为发布资源上传 GitHub Release。
