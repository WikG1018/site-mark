# 鸿蒙原生版自动化验证记录（2026-08-20）

本记录对应实现基线 `37cd6d6`。它记录可重复的自动化证据，不代表模拟器或真机验收。

## 自动化结果

| 门禁 | 命令 | 结果 |
| --- | --- | --- |
| 鸿蒙数据库契约 | `python -m unittest tool.test_ohos_capture_database_contract` | 10 项通过 |
| ArkTS 全量测试 + debug HAP | `pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests` | 169 项通过；debug unsigned HAP 构建成功 |
| ArkTS 报告防假绿 | `pwsh -File .\tool\ohos-native\test\verify-test-result.Tests.ps1` | 成功报告可解析；失败、错误、缺失/畸形汇总均会使门禁失败 |
| Python 仓库门禁 | `python -m unittest tool.test_generate_launcher_icon tool.test_verify_launcher_icon_resources tool.test_verify_release_tag tool.test_release_workflow tool.test_verify_ohos_native_manifest tool.test_ohos_capture_database_contract` | 全量通过 |
| Rust 格式 | `cargo fmt --manifest-path rust/Cargo.toml --check` | 通过 |
| Rust 鸿蒙特性静态检查 | `cargo clippy --manifest-path rust/Cargo.toml --no-default-features --features ohos-native --all-targets -- -D warnings` | 通过 |
| Rust 鸿蒙特性测试 | `cargo test --manifest-path rust/Cargo.toml --no-default-features --features ohos-native` | 全量通过 |
| Flutter 静态检查 | `flutter analyze` | 通过 |
| Flutter 回归 | `flutter test` | 全量通过 |

本地新工作树先运行 `pwsh -File .\tool\ohos-native\build-rust.ps1` 生成 `arm64-v8a` 与 `x86_64` 原生库，再使用 `-SkipRust` 构建 HAP。2026-08-20 的 debug 产物为：

```text
ohos-native/entry/build/default/outputs/default/entry-default-unsigned.hap
SHA-256: 5CE33B5D5092B35614E188813B523CF273614D315F07AA794BC32BA80777AE9D
```

该哈希仅对应本次本地 debug unsigned 构建；重新编译后应重新计算，不能作为发布签名包哈希复用。

## 当前未完成

执行 `hdc list targets` 返回 `[Empty]`，因此以下项目没有在本轮完成：

- 模拟器或真机上的中文/英文、浅色/深色、大字体、减少动画视觉走查；
- CameraPicker 拍摄、取消、方向信息和连续拍摄；
- 系统相册保存/拒绝/重复保存/删除确认；
- 文件选择器上的真实 ZIP 备份恢复与真实 RDB 中断收敛；
- 2,000 条记录滚动、12MP/50MP 图片、全屏连续切换和内存压力；
- 正式签名、覆盖安装及应用市场发行检查。

这些项目必须在可用设备上补验后才能更新为“已验证”。
