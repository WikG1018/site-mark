# 工程印记发布检查清单

这份清单适用于每个正式版本，不绑定具体版本号。自动检查全部通过只代表代码和安装包具备发布条件；拍照、系统文件选择器、后台调度等仍需在真机完成关键验收。

Agent 执行仓库内开发任务时，请同时阅读仓库根目录的 [`NEXT_AGENT_PROMPT.md`](../NEXT_AGENT_PROMPT.md)。

v1.0 真机回归勾选表见 [`verification-v1.0.0-device.md`](verification-v1.0.0-device.md)（适用于已发布的 1.0 维护，而非“尚未发版”）。

## 一、版本与分支

- `pubspec.yaml` 的版本号和构建号已递增，关于页面的备用版本同步更新（含 `about_section_screen_test.dart` 中硬编码的 `版本+构建号` 断言）。
- 发布标签必须为 `v<版本号>`，例如 `version: 0.8.1+12` 对应 `v0.8.1`；鸿蒙原生版发布标签为 `native-v<版本号>`，与 `AppScope/app.json5` 的 `versionName` 一致。
- 标签指向的提交必须已经进入 `main`，不得从未合并的功能分支直接发布。
- 发布说明准确列出新增功能、修复内容、已知限制和升级注意事项。
- **v1.0.13 已发布（Latest）。** `v1.0.13`（全屏查看器单指拖动修复）与 `native-v1.0.6` 同步发布并转正；真机增量回归在升级后按本清单补做。后续 `1.0.x` 补丁同样用本清单做回归。

## 二、自动化检查

以下项目由 GitHub Actions 的 CI 和发布工作流执行：

- Python 工具测试、启动图标资源校验、发布标签与版本一致性校验。
- Dart 格式检查、`flutter analyze`、全部 Flutter 单元与组件测试。
- 重新生成 Pigeon 系统桥接代码并检查仓库是否存在生成漂移。
- Rust `fmt`、`clippy -D warnings` 和全部测试。
- Android 系统桥接模块单元测试。
- CI 同时构建 Debug APK 和无正式签名的 Release 变体，提前发现仅发布构建才出现的问题。
- 标签发布时构建正式签名的 arm64 与 universal APK。
- 使用 `apksigner` 验证两个 APK 的签名有效且证书一致。
- 使用 `aapt2` 验证包名、版本号、版本代码、最低/目标 Android 版本和 ABI。
- 验证发布 APK 不含网络、相机、后台定位或广泛读取相册权限。
- 为最终 APK 生成 `SHA256SUMS.txt`。

本地复核可运行：

```text
python -m unittest tool.test_generate_launcher_icon tool.test_verify_launcher_icon_resources tool.test_verify_release_tag
python tool/verify_launcher_icon_resources.py
dart format --output=none --set-exit-if-changed lib test pigeons packages/sitemark_system_api/lib
flutter analyze
flutter test
cargo fmt --manifest-path rust/Cargo.toml --check
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path rust/Cargo.toml
android/gradlew -p android :sitemark_system_api:testDebugUnitTest
flutter build apk --debug
flutter build apk --release
```

## 三、拍照与后台处理真机验收

- 连续拍摄至少 10 张：系统相机应快速打开，返回后表单立即可继续使用，现场、内容和拍摄人保留，备注按设计清空。
- 观察记录从等待、处理中到完成；列表状态应自动刷新，缩略图最终切换为水印成片。
- 在处理过程中切到后台、从最近任务划掉应用并重新打开，记录应继续处理或由启动恢复重新调度。
- 系统相机取消、不可用或照片处理失败时，界面不得显示底层异常；原图已保留时必须明确告知并允许重新处理。
- 原图缺失与原图校验不一致应显示不同的可操作提示，不得继续生成可能误导的工程记录。
- 系统相册中同一照片编号只保留一份最新水印成片。
- 建议在至少两类以上厂商相机上抽查（例如小米/Redmi、OPPO/一加、vivo、Samsung、Pixel）。

后台启动时间由 Android 和厂商系统控制；“强行停止”会暂停计划任务，直到用户再次打开应用。

## 四、备份与恢复真机验收

- 从项目详情和“设置 → 备份与恢复”发起备份时，应进入同一套项目选择和完整性检查流程。
- 空白项目可备份并恢复项目说明、水印设置等元数据。
- 存在处理中照片时必须阻止备份；存在失败照片时必须明确提示遗漏数量并由用户确认。
- 分别验证单项目、多项目、包含原图和不包含原图四种备份。
- 备份生成后应打开 Android 系统保存面板；取消保存不能提示成功，并应保留“再次保存”和“分享”。
- 保存大体积备份时不应出现明显内存峰值或界面卡死。
- 恢复前应显示预览；普通照片分享 ZIP 必须被拒绝，损坏或不兼容备份应给出明确提示。
- 多项目恢复任一项目失败时应整体回滚；中途结束应用后，重新打开应清理半成品和临时文件。
- 删除项目不应删除已经保存到 Android 系统相册的照片。
- 导入/恢复失败的界面提示不得包含私有路径或原始异常字符串。

## 五、界面与兼容性抽查

- 在 360 dp 宽度、系统大字体、浅色/深色主题和中文/英文下检查主要页面无溢出或遮挡。
- 检查项目列表、记录列表、筛选、搜索、编辑模式、详情、全屏查看和返回逻辑。
- 检查 Hero 图片转场、页面返回和全屏缩放无闪烁、黑帧或重复动画。
- 检查定位未授权、近似定位、精确定位、通知开关和应用设置跳转。
- 检查圆形、圆角矩形和主题图标遮罩下的启动图标，以及 Android 12 及以上启动画面。
- 至少执行一次覆盖安装，确认已有项目、记录、设置和私有原图不丢失。

## 六、发布产物

- arm64 APK、universal APK 与 `SHA256SUMS.txt` 均已上传到同一 GitHub Release。
- Release 标题统一为 `SiteMark <标签>`（Android）或 `SiteMark 鸿蒙原生版 <版本号>`（HarmonyOS NEXT）；Android 标题由发布工作流自动生成。
- 发布资产统一按 `sitemark-<标签>-<变体>.<扩展名>` 命名，例如 `sitemark-v1.0.13-arm64.apk`、`sitemark-native-v1.0.6-unsigned.hap`。
- `README.md` 与 `README_EN.md` 的版本号、徽章、下载链接和 Latest/Pre-release 状态必须保持一致；更新其中一个时同步另一个。
- Release 页面显示的标签、版本说明和文件名一致。
- 随机下载一个发布 APK，重新校验 SHA-256、签名、版本和安装升级。
- 发布后记录真机型号、Android 版本、测试时间、关键结果和仍需观察的系统调度限制。
