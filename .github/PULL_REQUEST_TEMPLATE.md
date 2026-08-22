<!-- 选择目标分支（base）：改动涉及 ohos-native/、lib/、rust/、packages/ 或两者共用的 CI/工具链 → base 选 ohos-native；仅 Android 稳定线的文档或发布类改动 → base 选 main。拿不准时选 ohos-native。 -->

## Summary

<!-- 一段话说明本 PR 做什么、为什么。 -->

## 本地验证（必填）

> 公共 CI runner 没有 DevEco/HarmonyOS SDK，**ArkTS 编译与全量测试只能在本地验证**。
> 涉及 `ohos-native/` 或共享 Rust 核心的改动，以下三项为合并前提；纯文档/CI 改动可跳过并说明。

- [ ] `pwsh -File ./tool/ohos-native/run-host-tests.ps1` 通过
- [ ] `pwsh -File ./tool/ohos-native/build-hap.ps1 -SkipRust -RunTests` 通过；ArkTS 测试计数：_____ 项通过 / 0 失败
- [ ] debug HAP 构建成功（`entry-default-unsigned.hap`）

<details>
<summary>测试输出摘要（粘贴最后几行，含通过/失败计数）</summary>

```
# 在此粘贴 build-hap.ps1 的测试结果摘要
```

</details>

## 平台差异自查

- [ ] 未在用户可见文案中拼接原始异常或私有路径
- [ ] 行为变化已对照 [`ohos-native/docs/deltas.md`](../ohos-native/docs/deltas.md)：如引入新的平台差异，已先更新该表再写代码
- [ ] 不含设备级结论（真机/模拟器验收只能来自真实设备，见 deltas.md 证据使用规则）

## CI 说明

GitHub Actions 仅覆盖主机门禁 + Dart/Rust 回归，不编译 HAP——这正是上面「本地验证」必须填写的原因。
