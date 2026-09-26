# 验证记录 2026-09-26（对齐批次收尾 + native-v1.0.14 发版基线）

> 环境：Windows 11 + DevEco Studio（HarmonyOS 6.1.1 / API 24 SDK）。`hdc list targets` 返回 `[Empty]`——本轮没有可用模拟器或真机，以下全部是**本地构建与测试门禁证据**，不包含任何设备级结论。视觉走查、系统相机、相册交互、NAS 真实网络路径、动效手感与触感强度仍待真机（见 deltas.md）。

## 门禁命令与结果

| 门禁 | 命令 | 结果 |
| --- | --- | --- |
| Rust 双 ABI 构建 | `tool/ohos-native/build-rust.ps1` | exit 0（arm64-v8a / x86_64 产出） |
| ArkTS 全量测试 + HAP | `tool/ohos-native/build-hap.ps1 -SkipRust -RunTests` | **284 run, 284 passed, 0 ignored**；ArkTS 警告 362/362（棘轮内，增量均有预算注释）；debug HAP 构建成功 |
| 主机门禁 | `tool/ohos-native/run-host-tests.ps1` | HarmonyOS host tests passed（数据库契约 15/15、评审合约 74 项等） |
| GitHub CI | PR #179–#186 | ubuntu `test` + macos `ios` 双绿（Dart/Rust 回归 + Swift 桥测试） |

## 覆盖范围

- 对齐批次全部 7 个 PR（#179 设计、#180 token 层、#181 按压/触感、#182 转场、#183 看图物理、#184 MiSans、#185/#186 NAS 双向与收尾），含两轮细颗粒度自审修复（详见对应 PR 描述）。
- schema v15→v16 迁移由 `tool/test_ohos_capture_database_contract.py` 按"真实升级路径"（v15 CREATE + v16 ALTER + 新库 CREATE）回放验证。

## 发版产物

- `native-v1.0.14`（versionCode 1000014，Pre-release，target = main `9df9135`）。
- 资产：`sitemark-native-v1.0.14-unsigned.hap`（50,802,229 字节）+ `SHA256SUMS.txt`
  （HAP SHA-256 `2ac0bc28651c317b800e0d8b0e0541708201aa3b31cc08db92d4fac787201e15`）。
- 构建自合并后 main，非功能分支。

## 待补（真机）

动效手感 A/B（弹簧 response、惯性系数、双击缩放）、四档触感强度、NAS 本地服务冒烟与真实网络路径、关于页 MiSans 字形与包体影响、沉浸系统栏与返回手势——全部登记在 `deltas.md` 对应行。
