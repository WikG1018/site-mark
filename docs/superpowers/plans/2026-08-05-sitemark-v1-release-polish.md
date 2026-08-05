# SiteMark 1.0.0 Release Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 PR #31 的返回闪现和底部交互问题，并交付可发布的 SiteMark 1.0.0。

**Architecture:** 根分支改用只绘制当前项的 `IndexedStack`，从合成层消除隐藏“全部记录”闪现。根 Dock 与批量操作 Dock 使用项目内可控的紧凑组件，照片选择框改为缩略图叠层。

**Tech Stack:** Flutter、Riverpod、go_router、flutter_test、GitHub Actions

## Global Constraints

- 版本固定为 `1.0.0+15`，标签固定为 `v1.0.0`。
- 不增加第三方依赖。
- 保留三个根分支的导航和滚动状态。
- 所有行为修改遵循测试先行。

---

### Task 1: 隔离根分支绘制

**Files:**
- Modify: `lib/navigation/root_navigation_scaffold.dart`
- Test: `test/navigation/root_navigation_scaffold_test.dart`
- Test: `test/widget_test.dart`

**Interfaces:**
- Consumes: `RootBranchContainer(currentIndex, children)`
- Produces: 同一公开接口，内部只绘制 `currentIndex` 对应分支

- [ ] **Step 1: 写失败测试**

将测试改为断言 `RootBranchContainer` 使用 `IndexedStack`，`index` 跟随当前分支，并加入“全部记录 → 项目 → 项目详情 → 返回”后只有项目分支可绘制的回归测试：

```dart
final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
expect(stack.index, 0);
expect(find.byType(AnimatedOpacity), findsNothing);
```

- [ ] **Step 2: 验证测试按预期失败**

Run: `flutter test test/navigation/root_navigation_scaffold_test.dart test/widget_test.dart --plain-name "visited records branch stays hidden after project detail pop"`

Expected: FAIL，因为当前实现仍使用 `AnimatedOpacity`。

- [ ] **Step 3: 最小实现**

```dart
Widget build(BuildContext context) => IndexedStack(
  index: currentIndex,
  children: [
    for (final (index, child) in children.indexed)
      TickerMode(
        enabled: index == currentIndex,
        child: ExcludeSemantics(excluding: index != currentIndex, child: child),
      ),
  ],
);
```

- [ ] **Step 4: 运行相关测试**

Run: `flutter test test/navigation/root_navigation_scaffold_test.dart test/widget_test.dart`

Expected: PASS。

### Task 2: 紧凑根 Dock

**Files:**
- Create: `lib/navigation/root_navigation_dock.dart`
- Modify: `lib/navigation/root_navigation_scaffold.dart`
- Modify: `lib/shared/ui/floating_dock_layout.dart`
- Test: `test/navigation/root_navigation_scaffold_test.dart`
- Test: `test/shared/ui/floating_dock_layout_test.dart`

**Interfaces:**
- Produces: `RootNavigationDock(selectedIndex, onDestinationSelected)`
- Produces: `floatingDockHeight == 68`

- [ ] **Step 1: 写失败测试**

```dart
expect(floatingDockHeight, 68);
expect(find.byType(NavigationBar), findsNothing);
expect(find.byKey(const Key('root-destination-projects-selected-surface')), findsOneWidget);
```

- [ ] **Step 2: 验证测试失败**

Run: `flutter test test/navigation/root_navigation_scaffold_test.dart test/shared/ui/floating_dock_layout_test.dart`

Expected: FAIL，当前高度为 80 且使用 `NavigationBar`。

- [ ] **Step 3: 实现自定义 Dock**

每项使用等宽 `InkWell`，内部 `AnimatedContainer` 包裹完整 `Column(icon, label)`：

```dart
Expanded(
  child: InkWell(
    onTap: () => onDestinationSelected(index),
    child: Center(
      child: AnimatedContainer(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? colors.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [icon, label]),
      ),
    ),
  ),
)
```

- [ ] **Step 4: 运行相关测试**

Run: `flutter test test/navigation/root_navigation_scaffold_test.dart test/shared/ui/floating_dock_layout_test.dart`

Expected: PASS。

### Task 3: 叠层框选与带文字批量操作

**Files:**
- Modify: `lib/features/capture/capture_record_card.dart`
- Modify: `lib/features/capture/capture_batch_action_bar.dart`
- Test: `test/features/capture/capture_record_card_test.dart`
- Test: `test/features/capture/motion_selection_test.dart`
- Test: `test/widget_test.dart`

**Interfaces:**
- `CaptureRecordCard` 公开参数不变
- `_ActionButton` 仍接收 `icon`、`label`、`enabled`、`onPressed`

- [ ] **Step 1: 写失败测试**

```dart
expect(find.byKey(const Key('capture-selection-overlay')), findsOneWidget);
expect(find.text('导出所选'), findsOneWidget);
expect(find.text('保存到相册'), findsOneWidget);
expect(find.text('清理原图'), findsOneWidget);
expect(find.text('全部删除'), findsOneWidget);
```

同时比较普通模式与选择模式的缩略图左坐标，必须相同。

- [ ] **Step 2: 验证测试失败**

Run: `flutter test test/features/capture/capture_record_card_test.dart test/features/capture/motion_selection_test.dart test/widget_test.dart --plain-name "project detail edit mode shows overlay selection and labeled batch actions"`

Expected: FAIL，当前复选框占独立列且批量操作只有图标。

- [ ] **Step 3: 最小实现**

缩略图改为叠层：

```dart
Stack(
  children: [
    thumbnail,
    if (selectionMode)
      Positioned(
        key: const Key('capture-selection-overlay'),
        left: 4,
        top: 4,
        child: Checkbox(value: selected, onChanged: onChanged),
      ),
  ],
)
```

批量按钮改为紧凑 `InkWell + Column`，显示图标和单行短标签，并保留禁用态、语义和错误色。

- [ ] **Step 4: 运行相关测试**

Run: `flutter test test/features/capture/capture_record_card_test.dart test/features/capture/motion_selection_test.dart test/widget_test.dart`

Expected: PASS，360dp 无溢出。

### Task 4: 版本与发布说明

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/features/settings/about_section_screen.dart`
- Modify: `README.md`
- Test: `test/features/settings/sections/about_section_screen_test.dart`

**Interfaces:**
- Android `versionName = 1.0.0`
- Android `versionCode = 15`

- [ ] **Step 1: 写失败测试**

```dart
expect(find.text('1.0.0+15'), findsOneWidget);
```

- [ ] **Step 2: 验证测试失败**

Run: `flutter test test/features/settings/sections/about_section_screen_test.dart`

Expected: FAIL，兜底版本仍为旧版本。

- [ ] **Step 3: 更新版本与文档**

将 `pubspec.yaml` 改为 `version: 1.0.0+15`，关于页兜底版本改为 `1.0.0`，README 更新当前版本、功能截图说明与下载链接。

- [ ] **Step 4: 运行版本测试**

Run: `flutter test test/features/settings/sections/about_section_screen_test.dart`

Expected: PASS。

### Task 5: 全量验证与发布

**Files:**
- Verify: all changed files

- [ ] **Step 1: 格式化与静态检查**

Run: `dart format --output=none --set-exit-if-changed lib test && flutter analyze`

Expected: exit 0，无问题。

- [ ] **Step 2: 全量测试**

Run: `flutter test`

Expected: 全部通过。

Run: `cargo fmt --check --manifest-path native/sitemark_core/Cargo.toml && cargo clippy --manifest-path native/sitemark_core/Cargo.toml --all-targets -- -D warnings && cargo test --manifest-path native/sitemark_core/Cargo.toml`

Expected: exit 0。

- [ ] **Step 3: Android 验证与 APK**

Run: `flutter build apk --debug`

Expected: exit 0，并生成 `build/app/outputs/flutter-apk/app-debug.apk`。

- [ ] **Step 4: 推送、合并和发版**

推送 PR #31，等待 CI 成功；将 Draft 改为 Ready 并合并。确认合并提交的 `pubspec.yaml` 为 `1.0.0+15` 后创建并推送 `v1.0.0` 标签，等待发布工作流成功并核对 APK、版本号和 SHA-256。
