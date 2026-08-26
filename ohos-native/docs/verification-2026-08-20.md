# 鸿蒙原生版自动化验证记录（2026-08-20）

本记录对应实现基线 `cd4a8bd`。它记录可重复的自动化证据，不代表模拟器或真机验收。

## 自动化结果

| 门禁 | 命令 | 结果 |
| --- | --- | --- |
| 鸿蒙主机门禁 | `pwsh -File .\tool\ohos-native\run-host-tests.ps1` | 34 项通过；包含数据库契约、返回接线、清单与门禁自测 |
| ArkTS 全量测试 + debug HAP | `pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests` | 182 项通过；debug unsigned HAP 构建成功 |
| ArkTS 报告防假绿 | 由主机门禁调用 `verify-test-result.Tests.ps1` | 成功报告可解析；失败、错误、缺失/畸形汇总均会使门禁失败 |
| Rust 格式 | `cargo fmt --manifest-path rust/Cargo.toml --check` | 通过 |
| Rust 鸿蒙特性静态检查 | `cargo clippy --manifest-path rust/Cargo.toml --features ohos-native --all-targets -- -D warnings` | 通过 |
| Rust 鸿蒙特性测试 | `cargo test --manifest-path rust/Cargo.toml --features ohos-native` | 64 项通过 |
| Flutter 静态检查 | `flutter analyze` | 通过 |
| Flutter 回归 | `flutter test` | 1,000 项通过 |

本地新工作树先运行 `pwsh -File .\tool\ohos-native\build-rust.ps1` 生成 `arm64-v8a` 与 `x86_64` 原生库，再使用 `-SkipRust` 构建 HAP。2026-08-20 的 debug 产物为：

```text
ohos-native/entry/build/default/outputs/default/entry-default-unsigned.hap
大小: 35,334,917 bytes
SHA-256: 5C14F0AC8D299F92368F0D3FA876A1F5256B67A43DA6F7A72644BBCE91180674
```

该哈希仅对应本次本地 debug unsigned 构建；重新编译后应重新计算，不能作为发布签名包哈希复用。

## 当前未完成

执行 `hdc list targets` 返回 `[Empty]`，因此以下项目没有在本轮完成：

- 模拟器或真机上的中文/英文、浅色/深色、大字体、减少动画视觉走查；
- CameraPicker 拍摄、取消、方向信息和连续拍摄；
- 系统相册保存/取消/重复保存/图片完整性，以及应用记录删除后相册副本仍保留；
- 文件选择器上的真实 ZIP 备份恢复与真实 RDB 中断收敛；
- 2,000 条记录滚动、12MP/50MP 图片、全屏连续切换和内存压力；
- 正式签名、覆盖安装及应用市场发行检查。

这些项目必须在可用设备上补验后才能更新为“已验证”。
