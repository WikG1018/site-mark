# SiteMark 当前验证记录

> 验证日期：2026-07-19
>
> 基线：已发布 v0.2.0 之后的记录列表、文件命名和存储管理改进分支
>
> 环境：Windows、Flutter 3.44.6、Dart 3.12.2、JDK 17、Android SDK 36、Rust 1.95.0

## 本次覆盖

- 新照片编号和实际 JPEG 文件名不再包含项目 UUID；
- 同一天的照片序号在所有项目之间统一递增；
- 新建项目拦截规范化重名和安全文件名碰撞；
- 记录列表显示短标题，详情保留完整编号；
- 项目/年/月/日筛选按钮保持单行、矩形圆角和文字居中；
- 全选按钮可再次点击取消全选，处理中记录不参与选择；
- 总设置显示应用私有存储合计和分类，支持刷新、管理记录及清理私有导出 ZIP；
- 旧记录、旧文件、系统相册照片和已分享导出副本不迁移、不改名、不清理。

## 自动化结果

| 验证项 | 结果 |
| --- | --- |
| `flutter analyze` | 通过，无问题 |
| `flutter test` | 195 项通过，0 失败 |
| `cargo fmt --manifest-path rust/Cargo.toml --check` | 通过 |
| `cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings` | 通过 |
| `cargo test --manifest-path rust/Cargo.toml` | 20 项通过，0 失败 |
| `./android/gradlew.bat -p android :sitemark_system_api:testDebugUnitTest` | 13 项通过，0 失败 |
| `flutter build apk --debug` | 通过 |

测试日志仍会显示 Drift 双连接测试提示和 Android/Kotlin Gradle 迁移弃用提示；两者均未
造成测试或构建失败。本次未修改数据库 schema、Android 权限或网络边界。

## 调试 APK

- 文件：`C:\Users\Administrator\Desktop\mac\SiteMark-record-list-storage-debug.apk`
- 大小：224,203,648 字节；
- SHA-256：`BD543B58A51EC74EB055EC0F8B81329FE443F3C1E53F3DE89D68EF7D33192B1A`；
- 类型：Debug 测试包，不是正式签名发布包。

## 真机待确认

1. 从项目页调用系统相机拍摄两张，确认新文件名不含 UUID 且序号连续；
2. 确认记录卡标题为“日期 · 序号”，详情仍能看到完整编号；
3. 在项目详情和全部记录中确认筛选按钮居中且全选可取消；
4. 在总设置核对存储分类，清理本地导出后确认相册照片、原图和记录仍保留；
5. 尝试创建大小写/空白重名项目以及 `A/B`、`A:B` 项目，确认第二个会被拒绝。
