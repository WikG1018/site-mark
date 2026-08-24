# 鸿蒙根壳系统栏沉浸式 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 根壳窗口真 edge-to-edge：内容铺到状态栏和小白条下方，系统栏保持可见、背景透明，可点控件全部避开安全区，查看器往返不破版，图标色跟随明暗。

**Architecture:** `SystemBars.ets` 集中 AppStorage 键名与 inset 组合纯函数。`EntryAbility` 开全屏、写 inset、监听 `avoidAreaChange`。共享 `AppTopBar` / Dock / 批量栏 / 弹层 / 列表底 padding 用 `@StorageLink` 消费。查看器退出不再关全屏。`AppRuntime.applyAppearance()` 是系统栏图标色的运行时唯一属主。

**Tech Stack:** HarmonyOS NEXT / ArkTS / Hypium；主机门禁 `tool/ohos-native/run-host-tests.ps1`；debug HAP `tool/ohos-native/build-hap.ps1`（`$MaxArkTsWarnings = 300`）；hdc `C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe`，设备 `127.0.0.1:5555`。

**Spec:** [2026-08-24-ohos-immersive-system-bars-design.md](../specs/2026-08-24-ohos-immersive-system-bars-design.md)

## Global Constraints

- 基线：`origin/ohos-native` @ `d1ebaa8`。只在隔离 worktree `.worktrees/ohos-immersive-bars`、分支 `feat/ohos-immersive-bars` 改 HAP。主仓脏分支 `agent/journal-key-and-cleanup-observability` 禁止改 HAP。外观 worktree `.worktrees/ohos-appearance-consistency` 保留不动。
- 方案 A：窗口级 edge-to-edge。系统栏保持显示。禁止改成隐藏系统栏（查看器 immersive-sticky 除外）。禁止方案 B（只 `expandSafeArea` 铺背景）。
- 禁止改 Flutter、schema、SQL 默认值。禁止返工外观批次。禁止把 `UiTokens` 做成 `@Observed` / `AppStorage`。inset 只走 `safeAreaTopVp` / `safeAreaBottomVp`。
- 颜色属主：EntryAbility 只设一次启动初值（亮色图标 `#17201C`，背景透明）。此后唯一属主是 `AppRuntime.applyAppearance()`（dark `#E7EEE9`，light `#17201C`）。
- 查看器退出路径必须删除 `setWindowLayoutFullScreen(false)`，窗口恒全屏。退出只恢复 `setWindowSystemBarEnable(['status','navigation'])` 和图标色。
- Ability 任一步抛错只 `hilog.error` 并整体跳过，不阻断启动，不半途残留状态。
- Hypium 入口是 `ohos-native/entry/src/test/List.test.ets` 的 `testsuite()`。新测必须 import 并调用。`ohosTest/.../Ability.test.ets` 是空壳。
- 验证范围只覆盖模拟器 `127.0.0.1:5555` 手势导航。三键导航、折叠、自由多窗不承诺。`deltas.md` 必须诚实写模拟器 vs 真机，「设备验证待补」。
- 提交信息英文祈使句。PR 说明用简体中文。合并用 merge-commit。不改版本号、不签名、不上远程 CI、不做真机四组。
- 禁止用 MCP Computer Use 点模拟器窗口。hdc 必须用绝对路径；PowerShell 里不要写 `@{u}` 这种会被解析成 hashtable 的 git 简写。
- 本 worktree 的 HAP 在子目录 `ohos-native/`。所有源码路径相对仓库根，带 `ohos-native/` 前缀。命令在仓库根执行。

---

## 文件结构

| 路径 | 职责 | 操作 |
|---|---|---|
| `ohos-native/entry/src/main/ets/shared/SystemBars.ets` | 键名、`bottomInsetVp`、`topPaddingVp` | 新建 |
| `ohos-native/entry/src/test/SystemBars.test.ets` | inset 组合与 padding 相加 | 新建 |
| `ohos-native/entry/src/test/List.test.ets` | 注册 SystemBars 测 | 修改 |
| `ohos-native/entry/src/main/ets/entryability/EntryAbility.ets` | 全屏、透明栏、写 inset、监听变化 | 修改 |
| `ohos-native/entry/src/main/ets/shared/AppComponents.ets` | `AppTopBar` 高度 + 顶 padding | 修改 |
| `ohos-native/entry/src/main/ets/pages/Index.ets` | Dock 底边距、privacyGate 顶 padding | 修改 |
| `ohos-native/entry/src/main/ets/feature/records/RecordUiCoordinator.ets` | `listBottomPadding` 叠加底 inset | 修改 |
| `ohos-native/entry/src/test/RecordUiCoordinator.test.ets` | 默认 0 保持旧断言；新增 inset 测 | 修改 |
| `ohos-native/entry/src/main/ets/feature/records/RecordScreens.ets` | 列表底、批量栏、filterPanel | 修改 |
| `ohos-native/entry/src/main/ets/feature/projects/ProjectScreens.ets` | 列表底、批量栏、拍摄钮 | 修改 |
| `ohos-native/entry/src/main/ets/feature/settings/SettingsScreens.ets` | 设置页底 padding | 修改 |
| `ohos-native/entry/src/main/ets/feature/records/PhotoViewerScreen.ets` | 退出不再关全屏 | 修改 |
| `ohos-native/entry/src/main/ets/app/AppRuntime.ets` | `applyAppearance` 写系统栏图标色 | 修改 |
| `ohos-native/docs/deltas.md` | 本轮条目 + 模拟器证据边界 | 修改 |

不改：`UiTokens` 静态模型、`RootShellPolicy.contentBottomInset()` 签名（仍是 `DOCK_HEIGHT + 28`）、Flutter、schema、`PhotoViewerWindow.test.ets`（那是数据库窗口查询，不是系统栏）。

列表滚动区会铺进栏下，但 Dock / 批量栏仍占底，所以 `contentBottomInset()` 的调用点必须再加 `safeAreaBottomVp`，否则最后一项和小白条重叠。这是目标 2（可点控件避开安全区）的必要落地，不是逐页装饰。

---

## 执行前 worktree

worktree 与分支已存在，HEAD 含 spec 提交 `b94bb8f`。不要另开 worktree，不要在主仓改 HAP。

```powershell
cd c:\Users\Administrator\Documents\Codex\2026-07-15\new-chat\.worktrees\ohos-immersive-bars
git status
git log -1 --oneline
```

Expected：分支 `feat/ohos-immersive-bars`，干净（或仅本计划文件），最近提交含 immersive system bars design。

Hypium / HAP 命令一律在该仓库根执行：

```powershell
pwsh -File .\tool\ohos-native\run-host-tests.ps1
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
```

Expected host：`HarmonyOS host tests passed`。Expected HAP：Hypium 全绿、`ArkTS warnings within budget: N/300` 且 N ≤ 300。

hdc（验证 Task 用）：

```powershell
$hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
& $hdc -t 127.0.0.1:5555 shell uitest dumpLayout
```

---

### Task 1: SystemBars 纯函数

**Files:**
- Create: `ohos-native/entry/src/main/ets/shared/SystemBars.ets`
- Create: `ohos-native/entry/src/test/SystemBars.test.ets`
- Modify: `ohos-native/entry/src/test/List.test.ets`

**Interfaces:**
- Consumes: 无
- Produces:
  - `SAFE_AREA_TOP_VP: string` = `'safeAreaTopVp'`
  - `SAFE_AREA_BOTTOM_VP: string` = `'safeAreaBottomVp'`
  - `bottomInsetVp(navigationVp: number, indicatorVp: number): number` — 两者最大值；任一非有限按 0
  - `topPaddingVp(insetVp: number, baseVp: number): number` — 相加；任一非有限按 0

- [ ] **Step 1: 写失败测例并注册入口**

创建 `ohos-native/entry/src/test/SystemBars.test.ets`：

```ts
import { describe, expect, it } from '@ohos/hypium';
import { SAFE_AREA_BOTTOM_VP, SAFE_AREA_TOP_VP, bottomInsetVp, topPaddingVp }
  from '../main/ets/shared/SystemBars';

export default function systemBarsTest(): void {
  describe('SystemBars', () => {
    it('exposes AppStorage keys for top and bottom safe area', 0, () => {
      expect(SAFE_AREA_TOP_VP).assertEqual('safeAreaTopVp');
      expect(SAFE_AREA_BOTTOM_VP).assertEqual('safeAreaBottomVp');
    });

    it('takes the larger of navigation and indicator bottom insets', 0, () => {
      expect(bottomInsetVp(48, 34)).assertEqual(48);
      expect(bottomInsetVp(24, 36)).assertEqual(36);
      expect(bottomInsetVp(0, 0)).assertEqual(0);
      expect(bottomInsetVp(12, 12)).assertEqual(12);
    });

    it('treats non-finite navigation or indicator values as zero', 0, () => {
      expect(bottomInsetVp(Number.NaN, 36)).assertEqual(36);
      expect(bottomInsetVp(48, Number.NaN)).assertEqual(48);
      expect(bottomInsetVp(Number.POSITIVE_INFINITY, 10)).assertEqual(10);
      expect(bottomInsetVp(-8, 20)).assertEqual(20);
      expect(bottomInsetVp(20, -4)).assertEqual(20);
      expect(bottomInsetVp(Number.NaN, Number.NaN)).assertEqual(0);
    });

    it('adds a finite inset to a finite base padding', 0, () => {
      expect(topPaddingVp(34, 20)).assertEqual(54);
      expect(topPaddingVp(0, 52)).assertEqual(52);
      expect(topPaddingVp(34, 0)).assertEqual(34);
    });

    it('treats non-finite inset or base as zero when adding padding', 0, () => {
      expect(topPaddingVp(Number.NaN, 20)).assertEqual(20);
      expect(topPaddingVp(34, Number.NaN)).assertEqual(34);
      expect(topPaddingVp(-8, 20)).assertEqual(20);
      expect(topPaddingVp(34, -4)).assertEqual(34);
    });
  });
}
```

在 `ohos-native/entry/src/test/List.test.ets` 增加 import 并在 `testsuite()` 末尾调用：

```ts
import systemBarsTest from './SystemBars.test';
```

```ts
  appearanceSettingsDraftTest();
  systemBarsTest();
```

- [ ] **Step 2: 跑测确认失败**

Run:

```powershell
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
```

Expected: FAIL，原因是 `SystemBars` 模块不存在，或 `bottomInsetVp` / `topPaddingVp` 未导出。

- [ ] **Step 3: 写最小实现**

创建 `ohos-native/entry/src/main/ets/shared/SystemBars.ets`：

```ts
export const SAFE_AREA_TOP_VP: string = 'safeAreaTopVp';
export const SAFE_AREA_BOTTOM_VP: string = 'safeAreaBottomVp';

function finiteOrZero(value: number): number {
  return Number.isFinite(value) && value > 0 ? value : 0;
}

export function bottomInsetVp(navigationVp: number, indicatorVp: number): number {
  return Math.max(finiteOrZero(navigationVp), finiteOrZero(indicatorVp));
}

export function topPaddingVp(insetVp: number, baseVp: number): number {
  return finiteOrZero(insetVp) + finiteOrZero(baseVp);
}
```

负值按 0：手势/三键高度不应为负；脏数据不得把控件推进危险区。

- [ ] **Step 4: 跑测确认通过**

Run:

```powershell
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
```

Expected: Hypium 全绿，含 `SystemBars` 五条。`ArkTS warnings within budget: N/300`。

若本机 HAP 构建过慢，可先确认文件可编译；本 Task 结束前必须有一次 Hypium 绿。

- [ ] **Step 5: Commit**

```powershell
git add ohos-native/entry/src/main/ets/shared/SystemBars.ets `
  ohos-native/entry/src/test/SystemBars.test.ets `
  ohos-native/entry/src/test/List.test.ets
git commit -m "test: add SystemBars inset helpers"
```

---

### Task 2: EntryAbility 窗口层

**Files:**
- Modify: `ohos-native/entry/src/main/ets/entryability/EntryAbility.ets`

**Interfaces:**
- Consumes: `SAFE_AREA_TOP_VP`、`SAFE_AREA_BOTTOM_VP`、`bottomInsetVp(navigationVp, indicatorVp)`
- Produces: 主窗 `setWindowLayoutFullScreen(true)`；透明系统栏 + 启动图标色 `#17201C`；两个 AppStorage 键；`avoidAreaChange` 重算。失败整体 skip。

窗口 API 没有 Hypium 替身。本 Task 的测试是：ArkTS 能编过，且失败路径不抛出到 `loadContent` 之外。布局对比放到 Task 6。

- [ ] **Step 1: 在 loadContent 成功回调里接入沉浸式，失败整体 skip**

`ohos-native/entry/src/main/ets/entryability/EntryAbility.ets` 增加 import：

```ts
import { SAFE_AREA_BOTTOM_VP, SAFE_AREA_TOP_VP, bottomInsetVp } from '../shared/SystemBars';
```

`onWindowStageCreate` 改成：

```ts
  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading the content.');
      this.applyImmersiveLayout(windowStage);
    });
  }
```

在 `EntryAbility` 类里新增私有方法（放在 `onWindowStageCreate` 之后）：

```ts
  private applyImmersiveLayout(windowStage: window.WindowStage): void {
    try {
      const win = windowStage.getMainWindowSync();
      win.setWindowLayoutFullScreen(true);
      win.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        statusBarContentColor: '#17201C',
        navigationBarContentColor: '#17201C'
      });
      const uiContext = windowStage.getUIContext();
      const publish = (): void => {
        const systemArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        const navigationArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION);
        const indicatorArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
        const topVp = finitePxToVp(uiContext, systemArea.topRect.height);
        const navigationVp = finitePxToVp(uiContext, navigationArea.bottomRect.height);
        const indicatorVp = finitePxToVp(uiContext, indicatorArea.bottomRect.height);
        AppStorage.setOrCreate(SAFE_AREA_TOP_VP, topVp);
        AppStorage.setOrCreate(SAFE_AREA_BOTTOM_VP, bottomInsetVp(navigationVp, indicatorVp));
      };
      publish();
      win.on('avoidAreaChange', (_info: window.AvoidAreaOptions): void => {
        try {
          publish();
        } catch (error) {
          hilog.error(DOMAIN, TAG, 'Failed to refresh avoid area. Cause: %{public}s', JSON.stringify(error));
        }
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to apply immersive layout. Cause: %{public}s', JSON.stringify(error));
    }
  }
```

文件底部（`EntryAbility` 类外）加：

```ts
function finitePxToVp(uiContext: UIContext, px: number): number {
  if (!Number.isFinite(px) || px <= 0) {
    return 0;
  }
  const vp = uiContext.px2vp(px);
  return Number.isFinite(vp) && vp > 0 ? vp : 0;
}
```

规则：

- `setWindowLayoutFullScreen(true)` 幂等，允许重复调用。
- 启动初值图标色固定 `#17201C`。不要在 Ability 里读主题；运行时属主是 Task 5 的 `applyAppearance`。
- `AppStorage.setOrCreate` 必须用 Task 1 的键常量，不要手写第二个字符串。
- 任一步抛错被外层 `catch` 吃掉：不阻断 `loadContent` 成功日志，不半途关全屏。键未写入时 UI 侧默认 0 = 现状布局。
- 监听回调里的错误只记日志，不卸载监听（Ability 生命周期内窗口仍在）。
- 不要 `setWindowSystemBarEnable([])`。根壳栏必须可见。
- 若 ArkTS 报 `AppStorage` 未定义，从 `@kit.ArkUI` 补 import（与 `window` 同模块）。`UIContext` 同理。
- 若 `AvoidAreaType.TYPE_NAVIGATION` 在本 SDK 不存在：用 `TYPE_SYSTEM` 的 `bottomRect.height` 代替 navigation 参数，indicator 仍读 `TYPE_NAVIGATION_INDICATOR`；在 commit message body 里写清实际枚举。不要静默丢掉底部 inset。

- [ ] **Step 2: 编译确认 Ability 能过 ArkTS**

Run:

```powershell
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
```

Expected: 编译成功，既有 Hypium + Task 1 全绿。Ability 无新增单测。

- [ ] **Step 3: Commit**

```powershell
git add ohos-native/entry/src/main/ets/entryability/EntryAbility.ets
git commit -m "feat: enable edge-to-edge window layout"
```

---

### Task 3: AppTopBar、Dock、privacyGate

**Files:**
- Modify: `ohos-native/entry/src/main/ets/shared/AppComponents.ets`
- Modify: `ohos-native/entry/src/main/ets/pages/Index.ets`

**Interfaces:**
- Consumes: `SAFE_AREA_TOP_VP`、`SAFE_AREA_BOTTOM_VP`、`topPaddingVp(insetVp, baseVp)`
- Produces: 14 个共用 `AppTopBar` 避开状态栏；悬浮 Dock 底边距 = `dockBottomMargin() + safeAreaBottomVp`；隐私门顶 padding = `topPaddingVp(safeAreaTopVp, 20)`。加载中/错误页不改。

`@StorageLink` 默认值必须是 `0`。键未写入时布局等于改前。

若装饰器不接受导入常量，写成 `@StorageLink('safeAreaTopVp')`，字符串必须与 Task 1 常量逐字相同。

- [ ] **Step 1: AppTopBar 加顶 inset**

`ohos-native/entry/src/main/ets/shared/AppComponents.ets` 顶部增加：

```ts
import { SAFE_AREA_TOP_VP, topPaddingVp } from './SystemBars';
```

在 `AppTopBar` 的 `@Prop actionEnabled` 之后、`onBack` 之前加：

```ts
  @StorageLink(SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
```

把 build 末尾的高度和 padding：

```ts
    .width('100%')
    .height(UiTokens.TOP_BAR_HEIGHT)
    .padding({ left: this.showBack ? 4 : UiTokens.PAGE_PADDING,
      right: UiTokens.PAGE_PADDING, top: 6, bottom: 6 })
    .alignItems(VerticalAlign.Center)
```

改成：

```ts
    .width('100%')
    .height(UiTokens.TOP_BAR_HEIGHT + this.safeAreaTopVp)
    .padding({ left: this.showBack ? 4 : UiTokens.PAGE_PADDING,
      right: UiTokens.PAGE_PADDING, top: topPaddingVp(this.safeAreaTopVp, 6), bottom: 6 })
    .alignItems(VerticalAlign.Center)
```

不要改 `BatchActionBar` 内部 padding。底 inset 由外层 Column 的 margin 加。

- [ ] **Step 2: Index Dock 与 privacyGate**

`ohos-native/entry/src/main/ets/pages/Index.ets` 增加 import：

```ts
import { SAFE_AREA_BOTTOM_VP, SAFE_AREA_TOP_VP, topPaddingVp } from '../shared/SystemBars';
```

在 `Index` 的 `@State` 区（`motionRevision` 附近）加：

```ts
  @StorageLink(SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageLink(SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
```

`floatingDock()` 里把：

```ts
    .margin({ bottom: RootShellPolicy.dockBottomMargin() })
```

改成：

```ts
    .margin({ bottom: RootShellPolicy.dockBottomMargin() + this.safeAreaBottomVp })
```

`privacyGate()` 里把：

```ts
        .padding({ left: 24, right: 24, top: 52, bottom: 34 })
```

改成：

```ts
        .padding({ left: 24, right: 24, top: topPaddingVp(this.safeAreaTopVp, 20), bottom: 34 })
```

不要给 `privacyGate` 外层 Column 再加一份顶 padding。不要改 `build()` 里加载中 / 错误页的垂直居中。不要改 `chrome-${appearanceRevision}-${motionRevision}` 的 id 格式。

- [ ] **Step 3: 编译**

Run:

```powershell
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
```

Expected: Hypium 全绿，ArkTS 警告仍 ≤ 300。

- [ ] **Step 4: Commit**

```powershell
git add ohos-native/entry/src/main/ets/shared/AppComponents.ets `
  ohos-native/entry/src/main/ets/pages/Index.ets
git commit -m "feat: inset AppTopBar dock and privacy gate"
```

---

### Task 4: 列表底、批量栏、筛选 sheet、拍摄钮

**Files:**
- Modify: `ohos-native/entry/src/main/ets/feature/records/RecordUiCoordinator.ets`
- Modify: `ohos-native/entry/src/test/RecordUiCoordinator.test.ets`
- Modify: `ohos-native/entry/src/main/ets/feature/records/RecordScreens.ets`
- Modify: `ohos-native/entry/src/main/ets/feature/projects/ProjectScreens.ets`
- Modify: `ohos-native/entry/src/main/ets/feature/settings/SettingsScreens.ets`

**Interfaces:**
- Consumes: `SAFE_AREA_BOTTOM_VP`；`RootShellPolicy.contentBottomInset()` 保持无参、仍等于 `DOCK_HEIGHT + 28`
- Produces: `RecordBatchLayoutPolicy.listBottomPadding(selectionMode: boolean, fontScale: number = 1, safeAreaBottomVp: number = 0): number` — 选择模式与非选择模式都加底 inset。调用点把 `@StorageLink` 读到的值传进去。

- [ ] **Step 1: 扩展 listBottomPadding 测例（先失败）**

`ohos-native/entry/src/test/RecordUiCoordinator.test.ets` 里现有三条相关断言必须继续成立（第三参默认 0）：

```ts
      expect(RecordBatchLayoutPolicy.listBottomPadding(true))
        .assertEqual(RecordBatchLayoutPolicy.barHeight() + RecordBatchLayoutPolicy.bottomMargin() +
          RecordBatchLayoutPolicy.contentGap());
      expect(RecordBatchLayoutPolicy.listBottomPadding(true)).assertEqual(132);
      expect(RecordBatchLayoutPolicy.listBottomPadding(false)).assertEqual(RootShellPolicy.contentBottomInset());
      expect(RecordBatchLayoutPolicy.listBottomPadding(true, 1.6)).assertEqual(152);
```

在 `'shares root dock clearance and accessible filter heights with project detail'` 这条 `it` 末尾追加：

```ts
      expect(RecordBatchLayoutPolicy.listBottomPadding(false, 1, 36))
        .assertEqual(RootShellPolicy.contentBottomInset() + 36);
      expect(RecordBatchLayoutPolicy.listBottomPadding(true, 1, 36)).assertEqual(168);
      expect(RecordBatchLayoutPolicy.listBottomPadding(true, 1.6, 36)).assertEqual(188);
      expect(RecordBatchLayoutPolicy.listBottomPadding(false, 1, Number.NaN))
        .assertEqual(RootShellPolicy.contentBottomInset());
      expect(RecordBatchLayoutPolicy.listBottomPadding(false, 1, -8))
        .assertEqual(RootShellPolicy.contentBottomInset());
```

不要改 `RootShellPolicy.test.ets` 里 `contentBottomInset() === DOCK_HEIGHT + 28`。

- [ ] **Step 2: 跑测确认新断言失败**

Run:

```powershell
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
```

Expected: FAIL，`listBottomPadding` 仍是两参数，或第三参被忽略。

- [ ] **Step 3: 改 listBottomPadding**

`ohos-native/entry/src/main/ets/feature/records/RecordUiCoordinator.ets` 把：

```ts
  static listBottomPadding(selectionMode: boolean, fontScale: number = 1): number {
    return selectionMode ? RecordBatchLayoutPolicy.barHeight(fontScale) + RecordBatchLayoutPolicy.bottomMargin() +
      RecordBatchLayoutPolicy.contentGap() : RootShellPolicy.contentBottomInset();
  }
```

改成：

```ts
  static listBottomPadding(selectionMode: boolean, fontScale: number = 1,
    safeAreaBottomVp: number = 0): number {
    const inset = Number.isFinite(safeAreaBottomVp) && safeAreaBottomVp > 0 ? safeAreaBottomVp : 0;
    const base = selectionMode ? RecordBatchLayoutPolicy.barHeight(fontScale) +
      RecordBatchLayoutPolicy.bottomMargin() + RecordBatchLayoutPolicy.contentGap() :
      RootShellPolicy.contentBottomInset();
    return base + inset;
  }
```

`bottomMargin()` 仍返回 `12`，不要把系统 inset 塞进这个函数。

- [ ] **Step 4: 跑测确认通过**

Run:

```powershell
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
```

Expected: `RecordUiCoordinator` 新旧断言全绿。

- [ ] **Step 5: RecordScreens 消费底 inset**

`ohos-native/entry/src/main/ets/feature/records/RecordScreens.ets` 增加：

```ts
import { SAFE_AREA_BOTTOM_VP } from '../../shared/SystemBars';
```

`AllRecordsView`（含 `batchBar` / `filterPanel` 的那个 `@Component`）加：

```ts
  @StorageLink(SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
```

三处改动：

1. `batchBar()` 外层 Column：

```ts
    .margin({ left: 16, right: 16, bottom: RecordBatchLayoutPolicy.bottomMargin() })
```

改成：

```ts
    .margin({ left: 16, right: 16,
      bottom: RecordBatchLayoutPolicy.bottomMargin() + this.safeAreaBottomVp })
```

2. `filterPanel()` 末尾：

```ts
    .padding({ left: 16, right: 16, top: 8, bottom: 16 })
```

改成：

```ts
    .padding({ left: 16, right: 16, top: 8, bottom: 16 + this.safeAreaBottomVp })
```

`bindSheet` 高度保持 `460`。不要改 sheet 的 `dragBar`。避让只靠面板底 padding。

3. 列表 padding：

```ts
          .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING,
            top: 4, bottom: RecordBatchLayoutPolicy.listBottomPadding(this.isSelectionMode(),
              this.batchFontScale()) })
```

改成：

```ts
          .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING,
            top: 4, bottom: RecordBatchLayoutPolicy.listBottomPadding(this.isSelectionMode(),
              this.batchFontScale(), this.safeAreaBottomVp) })
```

- [ ] **Step 6: ProjectScreens 与 SettingsScreens**

`ProjectScreens.ets` 增加：

```ts
import { SAFE_AREA_BOTTOM_VP } from '../../shared/SystemBars';
```

`ProjectListView` 加 `@StorageLink(SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;`，把：

```ts
        .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING, top: 6,
          bottom: RootShellPolicy.contentBottomInset() })
```

改成：

```ts
        .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING, top: 6,
          bottom: RootShellPolicy.contentBottomInset() + this.safeAreaBottomVp })
```

含 `batchBar()` 的项目详情 `@Component`（`ProjectDetailScreen`）同样加 `@StorageLink`。然后：

1. `batchBar()`：

```ts
    .margin({ left: 16, right: 16, bottom: RecordBatchLayoutPolicy.bottomMargin() })
```

改成：

```ts
    .margin({ left: 16, right: 16,
      bottom: RecordBatchLayoutPolicy.bottomMargin() + this.safeAreaBottomVp })
```

2. 详情列表：

```ts
            .padding({ bottom: RecordBatchLayoutPolicy.listBottomPadding(this.selectionMode,
              this.batchFontScale()) })
```

改成：

```ts
            .padding({ bottom: RecordBatchLayoutPolicy.listBottomPadding(this.selectionMode,
              this.batchFontScale(), this.safeAreaBottomVp) })
```

3. 拍摄钮是可点控件，必须避开小白条。把：

```ts
            .margin({ right: 18, bottom: 18 }).align(Alignment.BottomEnd)
```

改成：

```ts
            .margin({ right: 18, bottom: 18 + this.safeAreaBottomVp }).align(Alignment.BottomEnd)
```

`SettingsScreens.ets` 的 `SettingsView` 已 import `RootShellPolicy`。增加：

```ts
import { SAFE_AREA_BOTTOM_VP } from '../../shared/SystemBars';
```

```ts
  @StorageLink(SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
```

把：

```ts
        .padding({ bottom: RootShellPolicy.contentBottomInset() })
```

改成：

```ts
        .padding({ bottom: RootShellPolicy.contentBottomInset() + this.safeAreaBottomVp })
```

不要改 `AppearanceScreen` 或其他已用 `AppTopBar` 的子页底 padding（它们不垫 Dock）。

- [ ] **Step 7: 编译**

Run:

```powershell
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
```

Expected: 全绿。

- [ ] **Step 8: Commit**

```powershell
git add ohos-native/entry/src/main/ets/feature/records/RecordUiCoordinator.ets `
  ohos-native/entry/src/test/RecordUiCoordinator.test.ets `
  ohos-native/entry/src/main/ets/feature/records/RecordScreens.ets `
  ohos-native/entry/src/main/ets/feature/projects/ProjectScreens.ets `
  ohos-native/entry/src/main/ets/feature/settings/SettingsScreens.ets
git commit -m "feat: keep tappable chrome above the gesture bar"
```

---

### Task 5: 查看器退出路径与主题图标色

**Files:**
- Modify: `ohos-native/entry/src/main/ets/feature/records/PhotoViewerScreen.ets`
- Modify: `ohos-native/entry/src/main/ets/app/AppRuntime.ets`

**Interfaces:**
- Consumes: `UiTokens.TEXT`（apply 之后等于 dark `#E7EEE9` / light `#17201C`）；`window.getLastWindow`
- Produces: 窗口恒全屏；退出只恢复系统栏显隐；`applyAppearance` 写透明底 + 对比色图标。失败记日志，不改变外观流程。

- [ ] **Step 1: 删除查看器退出时的 `setWindowLayoutFullScreen(false)`**

`applyViewerSystemBar` 现注释（约 L303–307）和 `else` 分支（约 L313–317）改成：

```ts
      // True immersion while the viewer is on top: hide system bars
      // (immersive-sticky, matching Android). The window stays layout-fullscreen
      // for the rest of the process so the root shell can draw edge-to-edge.
      // Exit only re-enables status and navigation bars. Avoid-area insets are
      // re-read after the visibility change so chrome margins track whatever
      // the platform now reports (zero-height once the bars are hidden).
      if (lightContent) {
        await win.setWindowLayoutFullScreen(true);
        if (stale()) return;
        await win.setWindowSystemBarEnable([]);
        if (stale()) return;
      } else {
        await win.setWindowSystemBarEnable(['status', 'navigation']);
        if (stale()) return;
      }
```

禁止在 `else` 里再调用 `setWindowLayoutFullScreen(false)`。进页仍全屏 + 藏栏。`catch (_) {}` 保持吞错。不要改 `topInsetVp` / `bottomInsetVp` 的动态重读。

退出后图标色由随后的 `setWindowSystemBarProperties({ statusBarContentColor: UiTokens.TEXT, ... })` 恢复；Task 5 Step 2 会保证 `UiTokens.TEXT` 与主题一致。不要在查看器里写死 `#17201C`。

- [ ] **Step 2: applyAppearance 写系统栏颜色**

`ohos-native/entry/src/main/ets/app/AppRuntime.ets` 增加：

```ts
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
```

文件顶部（import 区后）加：

```ts
const RUNTIME_DOMAIN = 0x0000;
const RUNTIME_TAG = 'SiteMarkRuntime';
```

`applyAppearance` 在 `UiTokens.apply(dark, settings.appSeedColorArgb);` **之后**、`setColorMode` **之前**插入：

```ts
    try {
      const win = await window.getLastWindow(this.context);
      const contentColor = dark ? '#E7EEE9' : '#17201C';
      await win.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        statusBarContentColor: contentColor,
        navigationBarContentColor: contentColor
      });
    } catch (error) {
      hilog.error(RUNTIME_DOMAIN, RUNTIME_TAG, 'Failed to update system bar colors. Cause: %{public}s',
        JSON.stringify(error));
    }
```

规则：

- 失败不影响 `setLanguage` / `UiTokens.apply` / `setColorMode` / `notifyDataChanged`。
- 背景必须保持透明 `#00000000`，不要写成实色。
- 不要在这里调用 `setWindowLayoutFullScreen` 或 `setWindowSystemBarEnable`。
- `initializeFresh` 已调用 `applyAppearance`，会覆盖 Ability 启动初值。不要再从 Ability 读设置。

- [ ] **Step 3: 编译**

Run:

```powershell
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
```

Expected: 全绿。`PhotoViewerWindow.test.ets` 无需改。

- [ ] **Step 4: Commit**

```powershell
git add ohos-native/entry/src/main/ets/feature/records/PhotoViewerScreen.ets `
  ohos-native/entry/src/main/ets/app/AppRuntime.ets
git commit -m "fix: keep fullscreen after photo viewer exit"
```

（若更想强调主题色，也可用 `feat: sync system bar icon colors with appearance`，但本 Task 必须同时包含查看器那次删除。一次 commit 覆盖两个文件即可。）

推荐信息：

```powershell
git commit -m "feat: keep fullscreen and theme system bar icons"
```

---

### Task 6: 模拟器 dump、往返、明暗、deltas

**Files:**
- Modify: `ohos-native/docs/deltas.md`

**Interfaces:**
- Consumes: Task 1–5 全部落地后的 HAP
- Produces: dump 证据；deltas 诚实条目

本 Task 才装模拟器。前面 Task 不要提前点模拟器。禁止 MCP 点 Emulator.exe。

- [ ] **Step 1: 安装 debug HAP 到 `127.0.0.1:5555`**

用仓库现有安装脚本（与外观批次相同）。若需手动：

```powershell
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust
```

然后按 `tool/ohos-native/` 里现有 hdc install 路径安装。确认：

```powershell
$hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
& $hdc list targets
```

Expected: 含 `127.0.0.1:5555`。

- [ ] **Step 2: dump 根壳全屏**

冷启动到项目 Tab（已同意隐私）。dump：

```powershell
$hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
& $hdc -t 127.0.0.1:5555 shell uitest dumpLayout
```

把 JSON 存到 worktree 外或 gitignore 目录，不要提交整棵 dump。核对：

| 检查 | 通过标准 |
|---|---|
| 屏 | `[0,0][1320,2856]`（若模拟器分辨率变了，用当前屏，不要硬套旧数字） |
| `EntryAbility` root | 起点 y=0，底边 = 屏高。禁止再出现改前的 y=137 |
| `chrome-*` orig | 高度达到屏高，禁止再停在 2758 |
| `AppTopBar` | 顶边 y=0 或紧贴屏顶；高度明显大于 68vp 折算像素 |
| Dock | 底边距屏底约为 `safeAreaBottomVp + 12vp` 折算像素，不被小白条切开 |

若 root 仍从 y=137 起：先查 hilog `Failed to apply immersive layout`，再查是否装了旧 HAP。不要改成 `expandSafeArea` 凑数。

- [ ] **Step 3: 查看器往返**

打开一张记录进入图片查看器（系统栏应隐藏），返回根壳，再 dump 一次。

Expected：root 仍全屏；Dock 与 AppTopBar 位置与 Step 2 同量级；系统栏重新可见。若返回后窗口缩回 y=137，说明 `setWindowLayoutFullScreen(false)` 仍在，回 Task 5。

- [ ] **Step 4: 明暗切换目检**

设置 → 外观，切深色。状态栏/小白条图标应变浅（`#E7EEE9`）。再切浅色，图标变深（`#17201C`）。把结果写进 deltas，不要假装做了真机四组。

- [ ] **Step 5: 写 deltas**

`ohos-native/docs/deltas.md`：

1. 文首「更新：2026-08-24」可保留日期，在「本轮已确认」追加一条，不要删除外观批次条目。
2. 新条目必须写清：模拟器 `127.0.0.1:5555` 手势导航；root 是否 `[0,0][屏宽,屏高]`；查看器往返是否仍全屏；明暗图标是否目检。
3. 必须出现「设备验证待补」或等价句。禁止把模拟器写成真机转正。
4. 「平台差异表」可加一行「窗口沉浸 / 系统栏」：当前为 edge-to-edge + 透明栏 + inset 避让；转正条件为真机手势/三键/折叠/多窗。

示例句式（按实测改数字，禁止抄未发生的 bounds）：

```
- 根壳窗口 edge-to-edge：EntryAbility setWindowLayoutFullScreen + 透明系统栏；AppTopBar / Dock / 批量栏 / 筛选 sheet / 拍摄钮按 AppStorage inset 避让。本轮 hdc list targets 为 127.0.0.1:5555（模拟器，手势导航，非真机）。dump 见 root bounds …（按实测填写）。查看器往返后窗口保持全屏。深浅色图标目检。三键导航真机、折叠态、自由多窗未测，设备验证待补。
```

- [ ] **Step 6: Commit**

```powershell
git add ohos-native/docs/deltas.md
git commit -m "docs: record emulator immersive bar verification"
```

不要把 dump JSON 提交进 git。

---

## Self-review

**Spec coverage**

| Spec 要求 | Task |
|---|---|
| `SystemBars` 键名 + `bottomInsetVp` + `topPaddingVp` | 1 |
| Ability 全屏、透明栏、启动色、读 avoid area、px2vp、AppStorage、`avoidAreaChange`、失败 skip | 2 |
| AppTopBar 高度 + 顶 padding | 3 |
| Dock `dockBottomMargin + safeAreaBottomVp` | 3 |
| privacyGate `safeAreaTopVp + 20` | 3 |
| 批量栏 ×2 叠加底 inset | 4 |
| 记录筛选 bindSheet 底 padding | 4 |
| 列表/设置最后一项不被小白条挡住（目标 2） | 4 |
| 拍摄钮可点避开小白条（目标 2） | 4 |
| 查看器退出删除 `setWindowLayoutFullScreen(false)` + 改注释 | 5 |
| `applyAppearance` 透明底 + TEXT 对比色，失败不影响外观 | 5 |
| Hypium 组合规则 | 1、4 |
| dump root 全屏、chrome 达屏高、TopBar/Dock | 6 |
| 查看器往返 | 6 |
| 明暗目检 | 6 |
| 验证范围仅模拟器手势导航；deltas 诚实 | 6 |
| 不隐藏根壳系统栏、不改 Flutter/schema、不改 UiTokens 响应式 | Global Constraints |

**Placeholder scan:** 无 TBD / TODO / “similar to Task N” / “add error handling”。Ability 的 SDK 枚举缺失有明确回退（`TYPE_SYSTEM.bottomRect`），不是占位。

**Type consistency:** `bottomInsetVp(navigationVp: number, indicatorVp: number): number`、`topPaddingVp(insetVp: number, baseVp: number): number`、`listBottomPadding(selectionMode, fontScale = 1, safeAreaBottomVp = 0)`、键名 `safeAreaTopVp` / `safeAreaBottomVp` 在 Task 1 定义，后续全文相同。`contentBottomInset()` 保持无参。

---

## 完成后

推送 `feat/ohos-immersive-bars`，PR 目标 `ohos-native`，说明用简体中文。CI 绿 + 审查通过后 merge-commit（沿用 #94）。本计划不自动开 PR，等用户选执行方式并做完 Task。
