# 鸿蒙原生版自动化验证记录（2026-08-26）

本记录对应 `fix/ohos-native-review-20260826` 合并候选。它记录本机可重复的自动化证据，不替代模拟器或真机验收。

## 自动化结果

| 门禁 | 命令 | 结果 |
| --- | --- | --- |
| 鸿蒙主机门禁 | `pwsh -File .\tool\ohos-native\run-host-tests.ps1` | 56 项通过；包含本轮相册、布局、通知、系统配置、备份和版本契约 |
| ArkTS 全量测试 + debug HAP | `pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests -BuildMode debug` | 238 项通过；debug unsigned HAP 构建成功；296 条已登记警告，未超过 296 基线 |
| release HAP | `pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -BuildMode release` | release unsigned HAP 构建成功；296/296 警告门禁通过 |
| Rust 格式 | `cargo fmt --manifest-path rust/Cargo.toml --check` | 通过 |
| Rust 鸿蒙特性静态检查 | `cargo clippy --manifest-path rust/Cargo.toml --no-default-features --features ohos-native --all-targets -- -D warnings` | 通过 |
| Rust 鸿蒙特性测试 | `cargo test --manifest-path rust/Cargo.toml --no-default-features --features ohos-native` | 64 项通过 |
| Flutter 静态检查 | `flutter analyze` | 通过，无问题 |
| Flutter 回归 | `flutter test` | 1,000 项通过 |

debug unsigned HAP 构建结果：

```text
ohos-native/entry/build/default/outputs/default/entry-default-unsigned.hap
大小: 35,510,153 bytes
SHA-256: B8F248EF69737426B37A21BF7C0AE1BADDBFA16A99C7A35AD685F43961A5270E
```

release unsigned HAP 随后覆盖同一路径，结果为：

```text
大小: 34,127,002 bytes
SHA-256: E3FF47EEE80EDECF029DE892EF4B8B81427DCC7691CCCAAD32CC427B84513D05
```

以上哈希只对应本次本地未签名构建；重新编译后应重新计算，不能作为发布签名包哈希复用。

## 本轮重点验证边界

- 系统相册保存必须在系统确认返回目标 URI 后完整复制 JPEG，再提交发布日记；应用不再包含删除系统相册资产的运行时入口。
- 删除单条记录、批量记录或项目只清理应用私有文件；升级后会丢弃旧版本遗留的相册删除任务。
- 根项目列表为悬浮 Dock 留出内容偏移；完成通知使用按记录区分的 requestCode。
- 沉浸式窗口设置等待系统调用完成，窗口销毁时解绑监听，系统语言和深浅色变化会重新应用外观。
- 系统自动备份关闭，继续使用应用内可选择项目的 ZIP 备份恢复；启动时清理中断遗留的导出工作目录。
- 关于页和诊断包从 bundle 元数据读取版本；项目创建或重命名只把实际重名映射为重名错误。

## 当前未完成

执行 `hdc list targets` 返回 `[Empty]`，因此以下项目仍需在可用模拟器或真机上补验：

- 系统相册确认、取消、重复保存、图片完整性和应用记录删除后相册副本保留；
- 通知冷启动、热启动和多条通知分别进入正确记录；
- 中文/英文、浅色/深色、大字体、减少动画及系统设置实时变化；
- 悬浮 Dock 遮挡、长列表滚动、50MP 图片、系统相机返回和内存压力；
- 正式签名、覆盖安装和应用市场发行检查。
