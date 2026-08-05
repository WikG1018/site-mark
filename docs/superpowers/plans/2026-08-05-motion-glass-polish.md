# SiteMark 动效与玻璃质感增强 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 PR #32 基础上提升根分支切换的空间感（更大位移 + 轻微 scale），并为 GlassSurface 与 Dock 指示器增加顶部高光、内描边与可关闭极淡噪声。

**Architecture:** 根分支继续使用现有 AnimationController + Offstage + FractionalTranslation 结构，仅在 transitioning 的 from/to 上叠加 Transform.scale。GlassSurface 在现有 ClipRRect + 条件 BackdropFilter 内部增加高光渐变、内描边和可选噪声层（enableNoise 默认 true）。Dock 指示器同步增加高光与内描边，不叠加噪声与第二层模糊。

**Tech Stack:** Flutter 3.x、Dart 3.x、现有 AppMotion、flutter_test

## Global Constraints

- 不修改版本号、不打 tag、不发布
- 不增加手指横向拖动切页
- 不改变业务逻辑、路由结构、数据库
- 保持 reduce-motion 立即切换
- 保持现有 Offstage / HeroMode / TickerMode / IgnorePointer / ExcludeSemantics 语义隔离
- 不引入新第三方依赖
- 噪声必须可关闭（enableNoise），默认开启但效果极克制
- 本计划基于 fix/v1-navigation-polish（PR #32）head 继续

---

## 文件结构

- `lib/navigation/root_navigation_scaffold.dart`：位移数值提升 + Transform.scale
- `lib/shared/ui/glass_surface.dart`：顶部高光、内描边、enableNoise 噪声
- `lib/navigation/root_navigation_dock.dart`：指示器高光 + 内描边 + 阴影微调
- `test/navigation/root_navigation_scaffold_test.dart`：更新方向与中间帧断言，增加 scale 断言
- `test/navigation/root_navigation_dock_test.dart`：确认无额外 BackdropFilter
- 可能扩展 GlassSurface 测试

---

### Task 1: 根分支滑动幅度与 scale

**Files:**
- Modify: `lib/navigation/root_navigation_scaffold.dart`
- Modify: `test/navigation/root_navigation_scaffold_test.dart`

**Interfaces:**
- Consumes: 现有 `_controller`、`_fromIndex`、`_currentIndex`、`AppMotion.emphasized`
- Produces: transitioning 时目标页 translation ≈ direction * 0.16、scale 0.94→1.0；来源页 translation ≈ -direction * 0.09、scale 1.0→0.985

- [ ] **Step 1: 写出失败的方向与 scale 测试**

在 `test/navigation/root_navigation_scaffold_test.dart` 的 `expectDirectionalBranchSwitch` 中增加中间帧 scale 断言，并更新 translation 期望幅度：

```dart
final fromScale = tester.widget<Transform>(
  find.ancestor(
    of: find.byKey(Key('root-branch-translation-$fromIndex'), skipOffstage: false),
    matching: find.byType(Transform, skipOffstage: false),
  ),
).transform.getMaxScaleOnAxis();
final toScale = tester.widget<Transform>(
  find.ancestor(
    of: find.byKey(Key('root-branch-translation-$toIndex'), skipOffstage: false),
    matching: find.byType(Transform, skipOffstage: false),
  ),
).transform.getMaxScaleOnAxis();

expect(fromScale, lessThan(1.0));
expect(toScale, lessThan(1.0));
expect(toScale, lessThan(fromScale)); // 目标页更小（从远处过来）
```

同时把 translation 断言从「符号正确」加强为「目标页 |dx| 接近 0.08 量级以上」。

- [ ] **Step 2: 运行测试并确认失败**

```bash
flutter test test/navigation/root_navigation_scaffold_test.dart
```

Expected: FAIL（当前无 Transform.scale，且位移仍为 0.08/0.04）

- [ ] **Step 3: 实现位移提升 + Transform.scale**

在 `RootBranchContainer` 的 build 中，把 `FractionalTranslation` 改为：

```dart
Transform.scale(
  scale: switch (index) {
    _ when index == _currentIndex && transitioning =>
      0.94 + progress * 0.06,
    _ when index == _fromIndex && transitioning =>
      1.0 - progress * 0.015,
    _ => 1.0,
  },
  child: FractionalTranslation(
    key: Key('root-branch-translation-$index'),
    translation: Offset(switch (index) {
      _ when index == _currentIndex && transitioning =>
        direction * (1 - progress) * 0.16,
      _ when index == _fromIndex && transitioning =>
        -direction * progress * 0.09,
      _ => 0,
    }, 0),
    child: HeroMode(
      // ... existing
    ),
  ),
)
```

保持 ClipRect、Offstage、HeroMode、TickerMode 等逻辑不变。

- [ ] **Step 4: 运行测试并确认通过**

```bash
flutter test test/navigation/root_navigation_scaffold_test.dart
```

Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/navigation/root_navigation_scaffold.dart test/navigation/root_navigation_scaffold_test.dart
git commit -m "feat: stronger root branch slide with scale"
```

---

### Task 2: GlassSurface 高光、内描边与可关闭噪声

**Files:**
- Modify: `lib/shared/ui/glass_surface.dart`
- Create or modify: 对应 widget 测试（可放在现有测试文件或新增 `test/shared/ui/glass_surface_test.dart`）

**Interfaces:**
- Consumes: 现有 opacity、blurSigma、borderRadius、MediaQuery.disableAnimationsOf
- Produces: 默认带顶部高光 + 1px 内描边 + 极淡噪声；`enableNoise: false` 时无噪声

- [ ] **Step 1: 写出失败的结构测试**

```dart
testWidgets('GlassSurface includes highlight and noise by default', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GlassSurface(child: const SizedBox(width: 100, height: 60)),
      ),
    ),
  );
  // 断言存在用于高光的 DecoratedBox 或 ShaderMask / 噪声相关层
  expect(find.byType(GlassSurface), findsOneWidget);
  // 具体 key 或类型断言在实现后精确化
});

testWidgets('GlassSurface skips noise when enableNoise is false', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GlassSurface(enableNoise: false, child: const SizedBox()),
      ),
    ),
  );
  // 断言噪声层不存在
});
```

- [ ] **Step 2: 运行测试并确认失败**

```bash
flutter test test/shared/ui/glass_surface_test.dart
```

Expected: FAIL（当前无 enableNoise 与高光层）

- [ ] **Step 3: 实现高光、内描边与噪声**

在 `GlassSurface` 中：

1. 增加参数 `final bool enableNoise;`（默认 true）
2. 在现有 `DecoratedBox` 的 decoration 上叠加：
   - 顶部 LinearGradient 高光（浅色/深色 alpha 区分）
   - 内描边（可用 border 的 inner 或额外 BoxDecoration）
3. 噪声层（仅当 `enableNoise && !disableAnimations`）：
   - 使用轻量方式（例如小尺寸噪声图 + Opacity，或 ImageFiltered 的简单替代）
   - opacity 控制在 0.03~0.06
   - 必须位于 ClipRRect 内部
4. 保持现有 opacity clamp、条件 BackdropFilter、DefaultTextStyle/IconTheme、RepaintBoundary

- [ ] **Step 4: 运行测试并确认通过**

```bash
flutter test test/shared/ui/glass_surface_test.dart
```

Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/shared/ui/glass_surface.dart test/shared/ui/glass_surface_test.dart
git commit -m "feat: glass surface highlight, inset border and optional noise"
```

---

### Task 3: Dock 指示器高光与内描边

**Files:**
- Modify: `lib/navigation/root_navigation_dock.dart`
- Modify: `test/navigation/root_navigation_dock_test.dart`

**Interfaces:**
- Consumes: 现有 AnimatedAlign + FractionallySizedBox + DecoratedBox
- Produces: 指示器带顶部高光与 1px 内描边，仍无 BackdropFilter，仍只有一个指示器

- [ ] **Step 1: 写出/更新失败测试**

保持现有「只有一个 root-dock-glass-indicator」和「无 BackdropFilter」断言，必要时增加高光相关结构断言。

- [ ] **Step 2: 运行测试确认当前基线仍通过，再实施后验证**

```bash
flutter test test/navigation/root_navigation_dock_test.dart
```

- [ ] **Step 3: 实现指示器高光与内描边**

在 `DecoratedBox` 的 decoration 中：

- 增加顶部 LinearGradient 高光（与 GlassSurface 风格一致，但更窄）
- 增加 1px 内描边
- 阴影在深色模式下可略微加强（根据 Theme.brightness）
- 不添加噪声，不添加 BackdropFilter

- [ ] **Step 4: 运行测试并确认通过**

```bash
flutter test test/navigation/root_navigation_dock_test.dart test/navigation/root_navigation_scaffold_test.dart
```

Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/navigation/root_navigation_dock.dart test/navigation/root_navigation_dock_test.dart
git commit -m "feat: dock indicator highlight and inset border"
```

---

### Task 4: 完整验证与 PR 准备

**Files:**
- Verify: Tasks 1-3 全部变更
- Docs: 已存在的设计与本计划

- [ ] **Step 1: 格式化与静态检查**

```bash
dart format lib/navigation/root_navigation_scaffold.dart lib/shared/ui/glass_surface.dart lib/navigation/root_navigation_dock.dart test/navigation/ test/shared/
flutter analyze --no-pub
```

Expected: No issues found

- [ ] **Step 2: 全量测试**

```bash
flutter test --no-pub
```

Expected: 全部通过，数量不低于 PR #32 基线

- [ ] **Step 3: 审查最终差异**

```bash
git status --short
git diff main...HEAD --stat
git log --oneline main..HEAD
```

Expected: 仅包含设计、计划、scaffold、glass_surface、dock 及对应测试；无版本号变更

- [ ] **Step 4: 推送并创建 PR #33**

以 `main`（或已合并的 #32）为 base，创建 draft PR，标题与正文明确：

- 根分支滑动幅度 + scale
- GlassSurface 高光 / 内描边 / 可关闭噪声
- Dock 指示器高光与内描边
- 无业务变更、无版本发布

---

**Plan complete and saved to `docs/superpowers/plans/2026-08-05-motion-glass-polish.md`.**

**Two execution options:**

**1. Subagent-Driven (recommended)** - 我为每个 Task 派发独立子代理，任务间 review，迭代快

**2. Inline Execution** - 在本会话用 executing-plans 按检查点批量执行

**Which approach?**