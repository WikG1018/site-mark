# Task 5 报告：全部记录筛选面板、条件标签与日期分组

## 实现范围

- 将“全部记录”的项目/年月日常驻控件替换为单一筛选入口。
- 新增草稿式筛选面板：取消不改变页面查询；重置清空草稿；应用一次返回完整 `CaptureFilter`。
- 项目变化清空年月日；年份、月份、日期沿用 `CaptureFilter` 的逐级清理规则。
- 新增横向活动条件标签；支持逐项删除，并为未知或已删除项目显示明确标签。
- 为 `CapturePagedList` 新增成对可选的 `groupKey` / `groupHeaderBuilder`，无分组调用保持原路径。
- “全部记录”按 `capturedAt ?? createdAt` 的本地日期分组，使用 pinned header；同日记录跨分页边界合并为一个分组。
- 保持最后 8 条触发分页、游标、`watchByIds`、搜索/选择互斥和筛选变化清空选择。
- 搜索时隐藏筛选入口；360dp 使用横向可滚动标签；减少动态效果时禁用筛选面板自有动画。
- 项目详情页继续使用原 `CaptureDateFilterBar`，没有改动该日期筛选路径。

## TDD 证据

### RED 1：主功能

命令：

```text
flutter test test/features/capture/capture_filter_ui_test.dart test/features/capture/capture_search_paging_ui_test.dart
```

结果：退出码 1；49 个既有测试通过，新增 2 个测试按预期失败。首个失败明确为找不到 `filter-sheet-trigger`，第二个因同一缺失入口无法打开草稿面板。失败原因是功能尚不存在，不是语法或环境错误。

### RED 2：审查修复——真实日期候选与异步刷新

命令：

```text
flutter test test/features/capture/capture_filter_ui_test.dart --plain-name "filter draft reloads real date options for each parent choice"
```

结果：退出码 1；选择只有 2026 年记录的项目 A 后仍显示项目 B 的 2025 年候选，证明面板使用了静态/合成日期范围。修复为草稿父级每次变化都通过当前项目、日期和搜索条件异步读取数据库真实候选；请求期间立即隐藏旧候选，使用 generation 和 mounted 守卫丢弃慢旧响应及销毁后的响应，失败时安全回退为空。项目 A→B、慢 A/快 B 竞态、错误、销毁安全、已选但记录已消失的日期以及取消不修改查询均有测试覆盖。

### RED 3：审查修复——3× 大字号日期吸顶栏

命令：

```text
flutter test test/features/capture/capture_search_paging_ui_test.dart --plain-name "pinned date header fits 3x text at 360dp in zh"
```

结果：退出码 1；固定 40dp header 低于测试要求的实际文字高度，存在裁切风险。修复为按主题 `titleSmall`、当前 `TextScaler` 的实际单行高度加 16dp 垂直内边距计算 sliver extent，并移除 `SizedBox.expand`。中文和英文在 360dp、3× 字号下均保持 pinned，文字完整且不与首行重叠。

### RED 4：审查修复——英文标签与字段语义

命令：

```text
flutter test test/features/capture/capture_filter_ui_test.dart --plain-name "English active chips name month and day with distinct delete semantics"
```

结果：退出码 1；旧实现找不到 `Month 8`，只显示无上下文的数字 `8`，四类删除按钮也共用 `Remove filter`。修复后英文显示 `Month 8` / `Day 4`，中文保持 `8月` / `4日`；项目、年份、月份、日期使用各自的本地化删除提示，语义树中月份和日期标签各出现一次。

### RED 5：增量审查修复——应用后立即重开

命令：

```text
flutter test test/features/capture/capture_filter_ui_test.dart --plain-name "reopening after apply never shows date options from the previous query"
```

结果：退出码 1；从全部项目选择项目 A 并应用后，父页面的新日期请求保持延迟，立即重开面板仍找到旧查询的 `filter-year-2025`。修复为父页面在 query/filter/search 改变时同步清空 `_dateOptions`，面板从空候选开始并在 `initState` 主动加载当前 `initial` 草稿；initial 请求沿用 generation、mounted 和错误守卫。新增覆盖证明旧候选立即消失，面板自己的真实 2026 候选返回后才显示；同时覆盖 initial 慢响应后快速切项目、initial 失败和 initial 完成时已销毁。

## GREEN 与回归验证

- 指定三文件：68/68 通过。
  - `capture_filter_ui_test.dart`
  - `capture_search_paging_ui_test.dart`
  - `capture_batch_paged_selection_test.dart`
- 相关分页、查询过滤、详情、全屏、选择和 Task 2 导航测试：104/104 通过。
- `flutter analyze`：无问题。
- 完整 `flutter test`：789/789 通过。
- `git diff --check`：通过。

特殊边界测试已覆盖：取消不污染页面、完整筛选应用、应用后立即重开、真实数据库年月日候选、首次打开主动刷新、父级切换异步刷新、initial 与用户选择竞态、慢旧请求竞态、错误及销毁安全、当前已选日期保留、条件标签级联删除、中英文标签及字段级删除语义、未知项目标签、360dp 无溢出、3× 字号日期 header、搜索时无筛选入口、筛选清空选择、减少动态效果、最后 8 条分页触发、`watchByIds` 保持、`capturedAt` 为空时回退 `createdAt`、跨分页同日标题不重复且记录不遗漏、header pinned。

## 交付约束

- 初始提交：`72fd86d6df82651bbbaa38ba8e799d652e3752b3` (`feat: add record filter sheet and date groups`)
- 首轮审查修复：`fbaf7096acdcbe31a55a54aece81356dd27292a6` (`fix: refresh record filter options`)
- 增量审查修复提交标题：`fix: refresh filter options on open`
- 未推送。
- 未开始 Task 6。
