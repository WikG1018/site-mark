# 鸿蒙根壳系统栏沉浸式（edge-to-edge）设计

> 日期：2026-08-24
> 基线：`origin/ohos-native` @ `d1ebaa8`（PR #94 已合入）
> 需求源：用户在模拟器观察到「上下状态栏和小白条没有沉浸式」
> 结论：已选 **方案 A — 真 edge-to-edge**：内容铺到系统栏下方，系统栏保持可见、背景透明

## 根因（模拟器实测）

模拟器 `127.0.0.1:5555`，屏幕 `[0,0][1320,2856]`，`uitest dumpLayout` 证据：

| 节点 | bounds | 说明 |
|---|---|---|
| sceneboard StatusBar | `[0,0][1320,136]` | 状态栏高 136px |
| `EntryAbility` root | `[0,137][1320,2856]` | 应用窗口被挤到 y=137 起 |
| `chrome-5-3` Column | orig `[0,136][1320,2758]` | 内容底停在 2758 |
| `NavBarContent` | `[0,137][1320,2758]` bg `#FFF5FAF6` | 底部留约 98px 小白条区 |

代码根因：[EntryAbility.ets](../../../ohos-native/entry/src/main/ets/entryability/EntryAbility.ets) 的 `onWindowStageCreate` 只 `loadContent`，未开全屏布局；根页无 `expandSafeArea`。全仓只有图片查看器 `applyViewerSystemBar` 做过系统栏控制。

## 目标

1. 根壳内容延伸绘制到状态栏和底部小白条**下方**；系统栏保持可见、背景透明。
2. 可点控件全部避开安全区：页签头部、悬浮 Dock、批量操作栏、弹层。
3. 状态栏/小白条区域图标颜色跟随明暗主题（延续 H7 对比度关注点）。
4. 从图片查看器返回根壳后布局不破版。

## 非目标

- 不隐藏系统栏（查看器的沉浸-sticky 行为保持不变）。
- 不改 Flutter、schema、SQL 默认值；不返工外观批次内容。
- 不做真机四组走查、发布签名（模拟器验证为主，见「验证范围」）。
- 不引入 `UiTokens` 响应式改造；inset 走 `AppStorage` 键，不动现有 token 机制。

## 方案比较

| | **A 窗口级 edge-to-edge（采用）** | B 仅背景层 `expandSafeArea` |
|---|---|---|
| 效果 | 列表滚动到栏下，真沉浸 | 栏区只是纯色背景，列表仍在栏下停住 |
| 改动面 | Ability + 共享组件 + 查看器联动 | 几行属性 |
| 风险 | 查看器退出路径、弹层避让需连带改 | 近零，但不解决观感问题 |

## 架构

四个单元。新增一个共享模块承载 inset 的读写与组合规则：

### 1. `shared/SystemBars.ets`（新文件，纯逻辑 + AppStorage 键）

- 常量：`SAFE_AREA_TOP_VP = 'safeAreaTopVp'`、`SAFE_AREA_BOTTOM_VP = 'safeAreaBottomVp'`（`AppStorage` 键名集中于此）。
- 纯函数 `bottomInsetVp(navigationVp: number, indicatorVp: number): number`
  = 两者的最大值，非有限值按 0 处理 —— 手势机型取小白条高度，三键导航机型取导航栏高度。
- 纯函数 `topPaddingVp(insetVp: number, baseVp: number): number` = 相加，供 privacyGate 等「固定间距 + 安全区」场景复用。

### 2. 窗口层（EntryAbility）

`onWindowStageCreate` 的 `loadContent` 成功回调内：

1. `windowStage.getMainWindowSync()` 取主窗。
2. `win.setWindowLayoutFullScreen(true)`（幂等）；
   `win.setWindowSystemBarProperties({ statusBarColor: 透明, navigationBarColor: 透明,
   statusBarContentColor: '#17201C', navigationBarContentColor: '#17201C' })` 作为启动初值。
3. 读 `getWindowAvoidArea`：顶部取 `TYPE_SYSTEM.topRect.height`；底部按 §1 组合规则取
   `TYPE_NAVIGATION` 与 `TYPE_NAVIGATION_INDICATOR`；px→vp 用 `windowStage.getUIContext().px2vp()`；
   写入两个 `AppStorage` 键。
4. 注册 `win.on('avoidAreaChange', ...)`：任何类型变化都重算并覆盖写入（旋转、折叠、查看器藏栏/复显都会触发）。
5. **失败降级**：任一步抛错只 `hilog.error` 并整体跳过 —— 应用回到现状的非全屏布局，不阻断启动，不半途残留状态。

颜色属主约定：EntryAbility 只设一次启动初值；此后唯一属主是 §4 的 `applyAppearance()`。

### 3. UI 避让层

消费方式统一为 `@StorageLink` 读取两个键，默认值 0（降级时自动等于现状布局）：

| 元素 | 位置 | 改法 |
|---|---|---|
| `AppTopBar`（14 个页面共用） | [AppComponents.ets](../../../ohos-native/entry/src/main/ets/shared/AppComponents.ets) | 高度 = `TOP_BAR_HEIGHT + safeAreaTopVp`，内容加顶部 padding |
| 悬浮 Dock | [Index.ets](../../../ohos-native/entry/src/main/ets/pages/Index.ets) `floatingDock()` | `margin.bottom = dockBottomMargin() + safeAreaBottomVp` |
| 批量操作栏 ×2 | ProjectScreens / RecordScreens 底部 Stack | 叠加 `safeAreaBottomVp` |
| 记录筛选 `bindSheet` | RecordScreens.ets:679 | 面板底部 padding 叠加 `safeAreaBottomVp` |
| 隐私门页 | Index.ets `privacyGate()` | 顶部 padding 由 52 改为 `safeAreaTopVp + 20` |

加载中/错误页为垂直居中布局，不需要处理。列表滚动区自然铺进栏下，无需逐页改动。

### 4. 查看器与主题联动

- [PhotoViewerScreen.applyViewerSystemBar](../../../ohos-native/entry/src/main/ets/feature/records/PhotoViewerScreen.ets)：
  `lightContent === false` 分支**删除** `setWindowLayoutFullScreen(false)` —— 窗口从此恒为全屏，
  退出只恢复系统栏显隐（`setWindowSystemBarEnable(['status','navigation'])`）；同步更新该处注释
  （原注释声称"restore both on exit"，不再成立）。它已有的 avoid-area 动态重读逻辑不变。
- [AppRuntime.applyAppearance](../../../ohos-native/entry/src/main/ets/app/AppRuntime.ets)：
  `UiTokens.apply(dark, …)` 之后追加 `setWindowSystemBarProperties`：
  背景仍透明，`statusBarContentColor` / `navigationBarContentColor` = dark ? `'#E7EEE9'` : `'#17201C'`；
  失败记日志不影响外观流程。

## 测试与验证

1. **Hypium 单测**：`bottomInsetVp` 组合规则（indicator > navigation、navigation > indicator、0、NaN）、`topPaddingVp` 相加规则。
2. **布局对比**（模拟器 hdc `uitest dumpLayout`）：
   - 改后 root bounds 应为 `[0,0][1320,2856]`（不再是 y=137 起）；
   - `chrome-*` orig 高度应达屏高；
   - `AppTopBar` bounds 顶部含状态栏高度；Dock 底边距屏底 = `safeAreaBottomVp + 12vp` 折算像素。
3. **查看器往返**：进入图片全屏 → 返回根壳，root bounds 仍为全屏、Dock/AppTopBar 位置正确。
4. **明暗切换**：设置里切深色后状态栏图标变浅色（目检记录，延续 H7 关注点）。

### 验证范围声明

本轮只在模拟器 `127.0.0.1:5555`（手势导航）验证；三键导航真机、折叠态、自由多窗为后续独立项，不在本批次承诺。

## 工程安排

- 工作区：`.worktrees/ohos-immersive-bars`，分支 `feat/ohos-immersive-bars`，基线 `d1ebaa8`。
- 完成后推送并开 PR 到 `ohos-native`，CI 绿 + 审查通过后以 merge-commit 合入（沿用 #94 流程）。
- 外观 worktree `.worktrees/ohos-appearance-consistency` 保持保留不动。

## 范围外（明确不做）

- 系统栏「隐藏式」沉浸（那是查看器模式）。
- 状态栏背景做渐变/毛玻璃。
- Flutter 端对齐改动。
- 竖横屏旋转的专门适配测试。
