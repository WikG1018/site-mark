# HarmonyOS Dynamic Color Honesty Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** HarmonyOS 外观页不得假装 Material You「跟随系统取色」可用：不支持时隐藏开关、始终露出应用主题色，并标明差异。

**Architecture:** 用 `supportsDynamicColorProvider`（默认 `!isOhosBuild`）表达能力，外观页 watch 该 provider，不要 page-level `if (ohos)`。测试通过 override 模拟鸿蒙。`SiteMarkApp` 在不支持时忽略已持久化的 `useDynamicColor`，继续用种子色。

**Tech Stack:** Flutter 3.44 / Dart 3.12.2、Riverpod、官方 `flutter test --no-pub`

## Global Constraints

- 长期 `ohos` 分支，不合 `main`，不开 PR。
- 不改 `ci.yml` / `release.yml` / `android/` / `pigeons/`。
- 不降 `sdk: ^3.12.2`。
- 不要 page-level `if (ohos)`。
- 无拍成 dump 不得写相机已拍成；无相册 dump 不得写系统相册已通；不得把动态取色标成与 Android 对等。
- 官方测试必须 `--no-pub`；搅 lock 则 `git checkout -- pubspec.lock`。

---

### Task 50: 外观页动态取色诚实化

**Files:**
- Modify: `lib/app.dart`
- Modify: `lib/features/settings/sections/appearance_section_screen.dart`
- Modify: `lib/l10n/app_strings.dart`
- Test: `test/features/settings/sections/appearance_section_screen_test.dart`
- Docs: `README.md`, `tool/ohos/full_product_gap.md`, `tool/ohos/product_hap_review.md`

**Interfaces:**
- Consumes: `isOhosBuild`, `AppSetting.useDynamicColor`, `AppStrings.dynamicColorTitle`
- Produces: `supportsDynamicColorProvider` (`Provider<bool>`), `AppStrings.dynamicColorUnavailable`, `Key('dynamic-color-unavailable')`

- [x] **Step 1: Write the failing tests**

在 `appearance_section_screen_test.dart` 给 `pumpScreen` 增加 `supportsDynamicColor` 覆盖，并追加：

```dart
testWidgets('hides dynamic color switch and shows honesty hint when unsupported', (
  tester,
) async {
  await pumpScreen(tester, supportsDynamicColor: false);
  expect(find.byKey(const Key('dynamic-color-switch')), findsNothing);
  expect(find.byKey(const Key('dynamic-color-unavailable')), findsOneWidget);
  expect(find.text('鸿蒙暂不支持壁纸动态取色'), findsOneWidget);
  expect(find.text('应用主题色'), findsOneWidget);
  expect(find.byType(ChoiceChip), findsNWidgets(9));
});

testWidgets('still shows theme chips when unsupported even if useDynamicColor is on', (
  tester,
) async {
  await database.updateAppSettings(useDynamicColor: true);
  await pumpScreen(tester, supportsDynamicColor: false);
  expect(find.byKey(const Key('dynamic-color-switch')), findsNothing);
  expect(find.text('应用主题色'), findsOneWidget);
  expect(find.byType(ChoiceChip), findsNWidgets(9));
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run official `appearance_section_screen_test` with `--no-pub`.
Expected: 新测 FAIL（仍有 `dynamic-color-switch`，没有 `dynamic-color-unavailable`）。

- [ ] **Step 3: Write minimal implementation**

1. `lib/l10n/app_strings.dart` 增加 `dynamicColorUnavailable`。
2. `lib/app.dart` 增加 `supportsDynamicColorProvider => !isOhosBuild`；`SiteMarkApp` 在 `!supports` 时不启用动态色。
3. 外观页 watch provider：不支持时隐藏开关、显示 hint、始终露出主题色芯片。

- [x] **Step 4: Run tests to verify they pass**

Expected: 官方 `appearance_section_screen_test` 全绿（原 7 + 新 2）。

- [x] **Step 5: Honest docs + commit + push origin/ohos**

不得写动态取色已对等 Android Material You。
