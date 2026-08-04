# Task 6 报告：设置首页三组玻璃列表

## 实现范围

- 新增纯展示/导航的 `SettingsGroup(title, children)` 与 `SettingsEntry(icon, title, subtitle, route, key)`。
- 将设置首页的 9 个入口按“拍摄与记录”“数据与安全”“应用”分为三组圆角玻璃列表，组内使用分隔线，整行由 `ListTile` 导航且点击高度不低于 48dp。
- 保留原 9 条设置路由和 Task 2 root dock；设置一级页明确禁用自动返回按钮。
- 通过 `appSettingsProvider` 实时显示语言和完成通知状态，通过缓存的 `storageUsageProvider` 与 `formatStorageBytes` 显示应用内总占用。
- provider 加载或错误时副标题为空，不显示 spinner 或跳动占位；设置值更新后摘要实时刷新。
- 新增中英文、360dp、3 倍字号滚动、Android 点击目标、可访问标签、provider 错误与玻璃分组测试。
- 将既有“设置子页返回”回归测试迁移为先滚动“外观”入口到 root dock 上方，再点击；没有为塞入首屏压缩设置行。

## TDD 证据

### RED：分组与实时摘要

命令：

```text
flutter test test/features/settings/global_settings_screen_test.dart test/features/settings/a11y_test.dart
```

结果：退出码 1，5 个既有测试通过、6 个新增测试按预期失败。失败明确为找不到 `settings-group-capture/data/app`、0 个 `GlassSurface`（期望 3 个）和没有“简体中文”摘要；没有编译或 fixture 错误。

### 回归 RED：旧测试未滚动到第三组

全量首跑 793 个测试通过、1 个失败。唯一失败是 `test/widget_test.dart` 的 `settings subsection pop returns to settings menu`：旧测试直接点击“外观”，目标中心为 y=510，被 root dock 覆盖。修复为 `ensureVisible` 后断言目标中心位于 dock 顶部之上，再执行点击和返回验证；产品行高与可读间距保持不变。

## GREEN 与门禁

- 指定双文件：11/11 通过。
- 设置目录全部测试：66/66 通过。
- 导航测试：14/14 通过。
- 旧设置子页返回回归测试：1/1 通过。
- `flutter analyze`：无问题。
- 完整 `flutter test`：794/794 通过。
- `git diff --check`：通过。

覆盖边界包括：三组键和中英文标题、9 个入口、一级页无 `BackButton`、3 个圆角 `GlassSurface` 与 6 条组内分隔线、语言/通知实时摘要、1.0 KB 总占用、加载/错误空副标题、无 spinner、provider 错误安全、Android 点击目标与标签语义、每行高度至少 48dp，以及 360dp + 3 倍英文滚动到底无溢出。

## 交付约束

- 提交标题：`feat: group settings into glass sections`
- 未推送。
- 未开始 Task 7。

## 审查修复：稳定摘要与真实导航覆盖

### 实现

- 设置摘要只读取已经落定、且不处于加载状态的 `AsyncData`；刷新中、纯加载及携带旧值的错误状态均不复用旧摘要。
- 通知、存储和语言三行始终保留一个排除语义的空副标题槽位，因此摘要清空时本行及其后续行不会上下跳动。
- 精确验证 9 个 `SettingsEntry`、三组各 3 项及全部路由（含诊断页），并分别点击每组一个代表入口。
- 使用真实数据库、provider 和 router 验证从语言页返回后摘要切换为 English，以及存储 provider 失效后从存储页返回时摘要更新为 2 KB。
- 使用真实 `RootNavigationScaffold` 在 360dp、3 倍字号、中英文两种环境中把最后一项滚动到 root dock 上方，验证无溢出且可点击。

### TDD RED

- 构造带旧值的刷新、加载和错误状态后，三种状态最初都错误显示 `[简体中文, 已开启, 1.0 KB]`，证明直接读取 `.value` 会泄漏旧摘要。
- 严格读取落定数据后摘要成功清空，但布局测试继续按预期失败：通知、存储、语言行均从 60dp 缩至 48dp；备份、诊断、关于分别上移 12dp、24dp、36dp。

### GREEN 与最终门禁

- 稳定摘要/几何测试：1/1 通过；刷新、加载、错误状态均无旧摘要、无 spinner，所有相关行尺寸及纵向位置保持不变。
- 指定双文件：16/16 通过。
- 设置目录全部测试：71/71 通过。
- 导航与 widget 测试：45/45 通过。
- `flutter analyze`：无问题。
- 完整 `flutter test`：799/799 通过。
- `git diff --check`：通过。

审查修复使用独立提交标题 `fix: stabilize settings summaries`；不 amend、不推送，仍未开始 Task 7。
