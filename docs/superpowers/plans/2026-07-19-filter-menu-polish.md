# 筛选菜单与项目水印设置文案优化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复窄屏筛选按钮文字与箭头重叠，优化筛选菜单样式及动画，并将项目级水印设置命名为“此项目水印设置”。

**Architecture:** 继续复用现有 `CompactFilterMenu<T>` 作为所有记录页和项目详情页的统一筛选控件。控件新增当前值输入，在菜单内部负责选中项视觉状态；日期级联与项目筛选的数据逻辑保持在现有调用方中，不作重构。

**Tech Stack:** Flutter、Material 3 `MenuAnchor` / `MenuItemButton`、Dart widget tests、GitHub Actions。

## Global Constraints

- 360dp 宽度下四个筛选按钮必须保持同一行。
- 筛选按钮高度保持 44dp、圆角保持 10dp，文字水平与垂直居中。
- 筛选按钮不再显示下拉箭头。
- 菜单使用圆角浮层、轻阴影、Flutter 内置淡入展开动画和选中项勾选提示。
- 原有项目 → 年 → 月 → 日级联筛选行为不变。
- 中文项目专用文案为“此项目水印设置”，英文为“Project watermark settings”。
- 不新增第三方依赖。

---

### Task 1: 修复筛选按钮并优化菜单

**Files:**
- Modify: `test/features/capture/capture_filter_ui_test.dart`
- Modify: `lib/features/capture/compact_filter_menu.dart`
- Modify: `lib/features/capture/capture_date_filter_bar.dart`
- Modify: `lib/features/capture/all_captures_screen.dart`

**Interfaces:**
- Consumes: `CompactFilterMenu<T>` 的 `label`、`entries`、`onSelected` 与 `enabled`。
- Produces: 新增必填参数 `selectedValue: T`，供控件识别当前菜单项。

- [ ] **Step 1: 写入失败的窄屏与菜单视觉测试**

在现有 360dp 控件测试中加入按钮内无箭头断言，并新增菜单样式测试：

```dart
expect(
  find.descendant(
    of: menuFinder,
    matching: find.byIcon(Icons.arrow_drop_down),
  ),
  findsNothing,
);

await tester.tap(menuFinder);
await tester.pumpAndSettle();
final selectedItem = tester.widget<MenuItemButton>(
  find.widgetWithText(MenuItemButton, '2026'),
);
expect((selectedItem.leadingIcon! as Icon).icon, Icons.check_rounded);
final anchor = tester.widget<MenuAnchor>(
  find.descendant(of: menuFinder, matching: find.byType(MenuAnchor)),
);
expect(anchor.animated, isTrue);
```

- [ ] **Step 2: 运行定向测试并确认失败**

Run: `flutter test test/features/capture/capture_filter_ui_test.dart`

Expected: FAIL，现有按钮仍含 `Icons.arrow_drop_down`，`CompactFilterMenu` 也尚未提供选中项样式与动画。

- [ ] **Step 3: 实现按钮与菜单视觉规则**

将按钮的 `Stack` 改为单一居中文本，并为 `MenuAnchor` 启用动画及浮层样式；使用 `selectedValue` 标识菜单项：

```dart
class CompactFilterMenu<T> extends StatelessWidget {
  const CompactFilterMenu({
    super.key,
    required this.label,
    required this.selectedValue,
    required this.entries,
    required this.onSelected,
    this.enabled = true,
  });

  final String label;
  final T selectedValue;
  final List<(T, String)> entries;
  final ValueChanged<T> onSelected;
  final bool enabled;
}
```

菜单采用 `animated: true`、`alignmentOffset: Offset(0, 6)`、14dp 圆角、6dp 阴影及上下 6dp 内边距。选中项使用 `colorScheme.primaryContainer`、`onPrimaryContainer` 和 `Icons.check_rounded`；未选项保留同宽空白前导位，保证文字对齐。

在 `CaptureDateFilterBar` 传入 `selectedValue: value`，在 `AllCapturesScreen` 传入 `selectedValue: _filter.projectId`。

- [ ] **Step 4: 格式化并运行定向测试**

Run: `dart format lib/features/capture/compact_filter_menu.dart lib/features/capture/capture_date_filter_bar.dart lib/features/capture/all_captures_screen.dart test/features/capture/capture_filter_ui_test.dart`

Run: `flutter test test/features/capture/capture_filter_ui_test.dart`

Expected: PASS，且 360dp 布局无 overflow 异常。

- [ ] **Step 5: 提交筛选菜单改动**

```bash
git add lib/features/capture/compact_filter_menu.dart lib/features/capture/capture_date_filter_bar.dart lib/features/capture/all_captures_screen.dart test/features/capture/capture_filter_ui_test.dart
git commit -m "fix: polish compact filter menus"
```

### Task 2: 增加项目专用水印设置文案

**Files:**
- Modify: `test/widget_test.dart`
- Modify: `lib/l10n/app_strings.dart`
- Modify: `lib/features/projects/project_detail_screen.dart`
- Modify: `lib/features/projects/project_watermark_settings_screen.dart`

**Interfaces:**
- Consumes: `AppStrings.of(context)`。
- Produces: 新 getter `String get projectWatermarkSettings`。

- [ ] **Step 1: 先更新 widget 测试为新文案**

在项目详情中验证入口提示，在进入设置页后验证标题：

```dart
expect(find.byTooltip('此项目水印设置'), findsOneWidget);
await tester.tap(find.byIcon(Icons.tune_outlined));
await tester.pumpAndSettle();
expect(find.text('此项目水印设置'), findsOneWidget);
```

- [ ] **Step 2: 运行定向测试并确认失败**

Run: `flutter test test/widget_test.dart --plain-name "edits constrained project watermark settings"`

Expected: FAIL，当前入口提示与页面标题仍为“水印设置”。

- [ ] **Step 3: 新增项目专用本地化文案并替换项目级用法**

```dart
String get projectWatermarkSettings =>
    _english ? 'Project watermark settings' : '此项目水印设置';
```

`ProjectDetailScreen` 的工具提示和 `ProjectWatermarkSettingsScreen` 的 AppBar 标题改用 `strings.projectWatermarkSettings`；保留通用 `watermarkSettings` getter，避免影响其他界面。

- [ ] **Step 4: 格式化并运行定向测试**

Run: `dart format lib/l10n/app_strings.dart lib/features/projects/project_detail_screen.dart lib/features/projects/project_watermark_settings_screen.dart test/widget_test.dart`

Run: `flutter test test/widget_test.dart --plain-name "edits constrained project watermark settings"`

Expected: PASS。

- [ ] **Step 5: 提交文案改动**

```bash
git add lib/l10n/app_strings.dart lib/features/projects/project_detail_screen.dart lib/features/projects/project_watermark_settings_screen.dart test/widget_test.dart
git commit -m "fix: clarify project watermark settings"
```

### Task 3: 全量验证、构建 APK 并更新 PR #8

**Files:**
- Modify: `README.md`
- Modify: `docs/verification-v0.2.0-alpha.md`

**Interfaces:**
- Consumes: Tasks 1–2 的完整代码与测试。
- Produces: 通过验证的 PR #8 分支和最新调试 APK。

- [ ] **Step 1: 运行静态分析和全量测试**

Run: `flutter analyze`

Expected: `No issues found!`

Run: `flutter test`

Expected: 全部 Dart 测试通过。

Run: `cargo test --manifest-path rust/Cargo.toml`

Expected: 全部 Rust 单元与集成测试通过。

- [ ] **Step 2: 同步测试总数文档并复验差异**

新增一项菜单视觉回归测试后，将 README 与验证记录中的 Flutter 测试数从 195 更新为 196。随后运行：

Run: `git diff --check`

Expected: 无输出。

- [ ] **Step 3: 构建调试 APK**

Run: `flutter build apk --debug`

Expected: 生成 `build/app/outputs/flutter-apk/app-debug.apk`。

- [ ] **Step 4: 复制 APK 并计算校验值**

将 APK 覆盖复制到 `C:\Users\Administrator\Desktop\mac\SiteMark-record-list-storage-debug.apk`，记录文件大小与 SHA-256。

- [ ] **Step 5: 提交文档、推送并检查 CI**

```bash
git add README.md docs/verification-v0.2.0-alpha.md
git commit -m "docs: update verification totals"
git push origin agent/sitemark-record-list-storage
gh pr checks 8 --watch
```

Expected: PR #8 所有必需检查通过，工作区干净。
