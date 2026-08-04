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

### RED 2：项目切换后的日期候选

命令：

```text
flutter test test/features/capture/capture_filter_ui_test.dart --plain-name "filter draft drops stale date options after project changes"
```

结果：退出码 1；切换项目并重选年份后找不到 `filter-month-8`，证明面板错误复用了旧项目的月份候选。修复为只有草稿父级仍与初始筛选一致时才使用传入候选，否则提供完整有效日历范围；随后同一测试通过。

## GREEN 与回归验证

- 指定三文件：60/60 通过。
  - `capture_filter_ui_test.dart`
  - `capture_search_paging_ui_test.dart`
  - `capture_batch_paged_selection_test.dart`
- 相关分页、查询过滤、详情和全屏导航测试：62/62 通过。
- 导航/选择动效回归：`motion_selection_test.dart` 11/11 通过。
- `flutter analyze`：无问题。
- 完整 `flutter test`：781/781 通过。
- `git diff --check`：通过。

特殊边界测试已覆盖：取消不污染页面、完整筛选应用、条件标签级联删除、未知项目标签、360dp 无溢出、搜索时无筛选入口、筛选清空选择、减少动态效果、最后 8 条分页触发、`watchByIds` 保持、`capturedAt` 为空时回退 `createdAt`、跨分页同日标题不重复且记录不遗漏、header pinned。

## 交付约束

- 提交标题：`feat: add record filter sheet and date groups`
- 未推送。
- 未开始 Task 6。
