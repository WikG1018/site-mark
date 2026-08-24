# 鸿蒙外观一致性批次设计

> 日期：2026-08-24
> 基线：`origin/ohos-native` @ `1cb0b8e`（PR #93 已合入）
> 需求源：`docs/ohos-native-ui-animation-review-2026-08-21.md` 第三批，对照主干去重后落地
> 路径：B — 对齐 Flutter 9 色，不把 `UiTokens` 改成 `@Observed`

## 目标

在鸿蒙 HAP 上补齐审查报告第三批里**对照 `1cb0b8e` 仍未完成**的项：

1. **M1**：外观页提供独立「应用主题色」选择器，与水印强调色共用 9 色表、互不写入。
2. **M2 / A6**：`appearanceRevision` / `motionRevision` 真正进入 `Index.build()`，栈内页跟根壳重绘，读到新的静态 token。
3. **A2**：去掉详情媒体 overlay 与批量栏的 `backdropBlur`；Dock / 选中态保留并继续走 `MotionPolicy.blur()`。
4. **M5**：记录页、项目页的年月日筛选抽成共享 `DateFilterRow`，高度统一 `filterControlHeight()`。
5. **连带**：项目编辑器水印色选项改读同一张 9 色表，避免外观能存、项目页选不到。

## 对照主干后不再做的项

审查报告 2026-08-21 的下列条目在 `1cb0b8e` 已落地，本批次**禁止返工**：

| 项 | 现状 |
|---|---|
| M3 消息成败 | `setMessage(text, isError)` 已在记录 / 项目 / 设置页使用 |
| M4 英文截断 | 详情操作钮、批量栏已有 `maxLines(2)` |
| M5 视觉 | 两处日期输入已是 `SURFACE_MUTED` + `OUTLINE_SUBTLE` + `CONTROL_RADIUS` |
| M6 / A1 / A3–A5 / H1–H7 | PR #93 及更早批次 |
| M1 半截 | 保存水印默认值已不再写 `appSeedColorArgb` |

## 非目标

- 改 Flutter、改数据库 schema、新增持久化字段。
- 把 `UiTokens` 做成 `@Observed` / `AppStorage`。
- 点选未保存时全应用即时换肤。
- 历史行自动把 `0xFF176B55` / `0xFF2E7D61` 改写成新绿。
- 真机四组走查、发布签名、正式图标、远程 DevEco CI。
- 把「减少动画」搬进外观页。
- 给每个 `NavDestination` 手写 `@Consume`。

## 方案比较（已选 B）

| | A 最小补丁 | **B 对齐 Flutter（采用）** | C token 响应式 |
|---|---|---|---|
| 主题色 | 第二排圆点，仍 5 色 | 9 色，与 Flutter `accentSwatches` 同序同值 | 同 B |
| token | 静态字符串 + 现有 notify | 静态字符串 + 根壳 revision 绑进 `build()` | `@Observed` / AppStorage |
| 筛选 / blur | 只改调用点 | 抽 `DateFilterRow`；blur 按表收口 | 同 B |
| 风险 | 与 Flutter 继续分叉 | 工作量匹配「第三批全做」 | ArkTS 编译面过大 |

## 架构

四个互不耦合的单元。入口仍是现有 `AppRuntime.applyAppearance()`：读 `settings.appSeedColorArgb` → `UiTokens.apply(dark, seed)` → `notifyDataChanged()`。缺口是外观页没有种子色 UI，且 `Index.build()` 不读 revision。

### 1. AccentSwatches（纯数据）

新文件（建议）：`ohos-native/entry/src/main/ets/shared/AccentSwatches.ets`

与 Flutter `lib/shared/theme/accent_swatches.dart` 对齐：

| 名称 | ARGB | id |
|---|---|---|
| 绿色 | `0xFF37C58B` | green |
| 蓝色 | `0xFF1565C0` | blue |
| 橙色 | `0xFFEF6C00` | orange |
| 红色 | `0xFFC62828` | red |
| 紫色 | `0xFF6A1B9A` | purple |
| 青色 | `0xFF00838F` | teal |
| 粉色 | `0xFFAD1457` | pink |
| 黄色 | `0xFFF9A825` | yellow |
| 靛蓝 | `0xFF283593` | indigo |

API：

- `values(): AccentSwatch[]` — 固定 9 项，顺序同上。
- `defaultArgb(): number` — `0xFF37C58B`（与 `AppSettings.createDefault` / Flutter `kDefaultSeedColorArgb` 一致）。
- `contains(argb: number): boolean`
- `nearest(argb: number): number` — RGB 欧氏距离，忽略 alpha（按 `0xFF` 比较）。NaN / 非有限值回退第一项。
- `label(argb, english): string` — 中英名称；未知值返回空串或「自定义 / Custom」，不抛。

主题色和水印色**共用**这份表，禁止各自维护调色盘。

`SettingsAccessibility.watermarkAccentOptions()` 与 `ProjectFormPolicy.watermarkAccentChoices()` 改为基于 `AccentSwatches.values()` 生成。旧 5 色（含 `0xFF2E7D61`、`0xFFC05A24`、`0xFF7B4DA8`、`0xFF37474F`）退出选择器。

### 2. AppearanceChrome（根壳）

`Index` 已有：

- `@State appearanceRevision` — `runtimeListener` 在根壳 active 时 `+= 1`
- `@State motionRevision` — `MotionPolicy` 刷新时用正负号编码 reduce-motion

本轮：**`build()` 必须读取这两个 `@State`**。根 `Column`（或现有最外层容器）加上：

```ts
.id(`chrome-${this.appearanceRevision}-${this.motionRevision}`)
```

不给每个 `NavDestination` 手写 `@Consume`。不另开 listener。

接受副作用：捕获完成等其它 `notifyDataChanged` 也会 bump `appearanceRevision` 并触发一次根壳重绘——与今天 listener 已 bump 的行为相同，只是终于生效。不为外观单独开第二条 listener。

根壳 inactive 时 listener 直接 return、不 bump（现状保留）。

### 3. AppearanceSettings（设置页）

`AppearanceScreen`：

- 新增 `@State appSeed: number`，`load()` 从 `settings.appSeedColorArgb` 填入。
- 现有 `@State accent` 仍只来自 `defaultWatermarkAccentColorArgb`。
- 两套 state 互不拷贝。

「界面外观」段顺序（语言段之前）：

1. 标题「界面外观」
2. 深色模式 `LifecycleSegment`（现有）
3. **新**：小标题「应用主题色」+ `AccentSwatchRow`（绑 `appSeed`）
4. 现有「应用语言」段不动

「新建项目水印默认值」段：位置 / 透明度 / 字号不变。底下那排 5 色换成同一 `AccentSwatchRow`，绑 `accent`。

`save()` 写 `AppSettingsRecord`：

- `appSeedColorArgb: this.appSeed`
- `defaultWatermarkAccentColorArgb: this.accent`
- 其余字段保持现写法

然后 `database.updateSettings` → `applyAppearance()`。成功 / 失败文案不改。

加载中 / 保存中：两排圆点 `enabled=false`。继续用 `loadCoordinator` / `saveCoordinator`：过期 load 不覆盖正在编辑的 `appSeed`/`accent`；保存失败不改本地 state。

点选未保存时**不**调用 `UiTokens.apply`。外观页圆点用 swatch 自身色，不依赖 `PRIMARY`。

抽出小纯函数（建议 `AppearanceSettingsDraft` 或放进现有 settings policy）便于测「改 seed 不碰 accent」。

### 4. ListChrome（列表 / 详情装饰）

**DateFilterRow**（放 `shared/AppComponents.ets`，与 `BatchActionBar` 同文件）

入参：`year` / `month` / `day` 字符串、`enabled`、`onChange(year, month, day)`。三个 `TextInput` 样式统一：

- `backgroundColor(UiTokens.SURFACE_MUTED)`
- `border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })`
- `borderRadius(UiTokens.CONTROL_RADIUS)`
- `height(RecordBatchLayoutPolicy.filterControlHeight())`（已等于 `TOUCH_TARGET`）

记录页、项目页 `filterPanel` 只保留各自的「筛选 / 重置」按钮和业务回调。

**Blur**

| 位置 | 动作 |
|---|---|
| 记录详情媒体 overlay（约 L1731、L1750） | 去掉 `backdropBlur`，保留 `OVERLAY` / 半透明底 |
| `BatchActionBar` | 去掉 `backdropBlur(12)`，保留 `GLASS_STRONG` |
| Index Dock / 选中态 | **保留**，半径继续 `MotionPolicy.blur()`（减少动画时为 0） |
| 列表卡片 | 确认无 blur，不再加回去 |

若抽出 `ListChromePolicy.mediaOverlayBlur()` / `batchBarBlur()` 返回 0，便于单测；不抽就不测修饰符。

## 组件与交互

### AccentSwatchRow

共享一行 9 色圆点，给「应用主题色」和「水印强调色」各用一次。

入参：`selectedArgb`、`enabled`、`onSelect(argb)`、无障碍前缀（「应用主题色」/「水印强调色」）。

选中态：白边 4vp / 未选 1vp（沿用现有水印钮）。未知历史色用 `nearest()` 高亮最接近项，**不改写**该值，直到用户点某一圆点。

9 色一行可能换行：`Flex` wrap，间距 11vp，触控目标 44vp。

无障碍：

- 主题色：`{前缀} {色名}`，选中时中文加「已选择」、英文加 `, selected`（对齐现有 `watermarkAccentAccessibilityText` 模式）。
- 水印色：沿用 `watermarkAccentAccessibilityText`，色名表扩到 9 色。
- 项目编辑器 `watermarkAccentChoices` 的中英标签与同一张表对齐。

## 数据流

```
load() → appSeed ← settings.appSeedColorArgb
         accent  ← settings.defaultWatermarkAccentColorArgb

tap theme swatch  → appSeed = argb          （不 apply token）
tap watermark     → accent  = argb          （不 apply token）

save() → AppSettingsRecord { appSeedColorArgb: appSeed,
                             defaultWatermarkAccentColorArgb: accent, ... }
       → updateSettings → applyAppearance()
       → UiTokens.apply(dark, settings.appSeedColorArgb)
       → notifyDataChanged()
       → Index.runtimeListener → appearanceRevision++
       → Index.build() 读 revision → 栈内页重绘
```

### 未知 / 历史色

选择器高亮 `nearest(value)`，**不在 load/save 时改写**库里的旧值。用户点某一圆点后才变成表内精确色。

| 库内值 | 选择器高亮 |
|---|---|
| `0xFF37C58B` | 绿（自身） |
| `0xFF176B55`（旧库 / 旧 Flutter 深绿） | nearest → 绿 |
| `0xFF2E7D61`（旧鸿蒙外观墨绿） | nearest → 绿 |
| NaN / 非有限 | 第一项绿 |

新安装默认：`0xFF37C58B`。

### 减少动画

现有 `MotionPolicy.read` → `commit` → `motionRevision` 正负号 + `pathStack.disableAnimation`。本轮只保证 `build()` 读 `motionRevision`。`MotionPolicy.read` 失败仍当 `reduceMotion=false`。

## 错误处理

- 加载失败、保存失败文案不改。
- `AccentSwatches.nearest` 对非法 number：表非空则第一项；本轮表写死 9 项。
- 根壳 inactive 不 bump revision。

## 测试

跟现有 Hypium 习惯：政策 / 纯函数单测 + 全量 `entry/src/test` + debug HAP + 模拟器冒烟。不写 ArkUI 组件树测。

### 单测

新增 `AccentSwatches.test.ets`（或并入 `UiPolicy.test.ets`）：

1. 9 项顺序与 ARGB 与上表完全一致；第一项等于 `defaultArgb()`。
2. `contains` 表内为真；`nearest(0xFF37C58B)` 自身；`nearest(0xFF176B55)` 与 `nearest(0xFF2E7D61)` 均为 `0xFF37C58B`；NaN 回退第一项。
3. 每个 swatch 中英 label 非空且互不相同。

改现有测例：

- `SettingsProjectSelection`：「5 个不重复无障碍标签」改为 **9**；覆盖主题色前缀文案中英不同、选中态不同。
- `ProjectFormPolicy.watermarkAccentChoices`：改为表内色；未知历史值（如 `0xFF2E7D61`）nearest 高亮，不再断言旧 5 色列表。
- `AppearanceSettingsDraft`：改 seed 不碰 watermarkAccent，改 accent 不碰 seed；`toRecord()` 两字段分别来自对应 state。
- `filterControlHeight() === TOUCH_TARGET` 保持。

### 门禁

- `ohos-native/entry/src/test` 全绿（基线 223，本轮增加条数）。
- `tool/ohos-native/build-hap.ps1` debug 警告 ≤ 300。
- 不把 token 改成 `@Observed`，不新增 schema。

### 模拟器冒烟（debug HAP）

1. 设置 → 外观：能看到「应用主题色」和「水印强调色」两排 9 点。
2. 只改主题色为蓝、保存：PRIMARY 变蓝；水印默认色不变。返回记录 / 项目页，按钮 / 强调色跟蓝走（revision 重建生效）。
3. 只改水印色为橙、保存：主题仍蓝；新建项目水印默认是橙。
4. 记录 / 项目筛选：年月日输入高度、圆角、底色一致。
5. 记录详情媒体 overlay、批量栏：无毛玻璃；Dock 仍有（未开减少动画时）。

`ohos-native/docs/deltas.md` 诚实写「设备验证待补」。不把模拟器冒烟写成真机转正。

## 实现落点（文件级，供计划拆分）

| 文件 | 变更 |
|---|---|
| `shared/AccentSwatches.ets` | 新建：9 色表、nearest、label |
| `shared/AppComponents.ets` | `AccentSwatchRow`、`DateFilterRow`；`BatchActionBar` 去 blur |
| `feature/settings/AppearanceSettingsDraft.ets` | 新建：seed / accent 互不写入 |
| `feature/settings/SettingsAccessibility.ets` | `watermarkAccentOptions` 改读 9 色；主题色无障碍前缀 |
| `feature/settings/SettingsScreens.ets` | draft 驱动两排 swatch、save 分字段 |
| `feature/projects/ProjectFormPolicy.ets` | `watermarkAccentChoices` 改读 9 色 |
| `feature/projects/ProjectScreens.ets` | 筛选改用 `DateFilterRow`；新建项目表单默认 accent = `AccentSwatches.defaultArgb()` |
| `feature/records/RecordScreens.ets` | 筛选改用 `DateFilterRow`；详情 overlay 去 blur |
| `pages/Index.ets` | `build()` 读 `appearanceRevision` 与 `motionRevision` |
| `entry/src/test/*` | 见上文 |
| `ohos-native/docs/deltas.md` | 主题色 UI、revision 重建、blur 收口、筛选归一；设备验证待补 |

不抽 `ListChromePolicy`。`AccentSwatchRow` 放 `AppComponents.ets`。

## 成功标准

- 外观页两套 9 色选择器独立保存。
- 保存主题色后，已打开的记录 / 项目页强调色跟着变（不必杀进程）。
- 详情 overlay 与批量栏无 `backdropBlur`；Dock 在未减少动画时仍有 blur。
- 两处日期筛选同一组件、同一高度。
- Hypium 全绿；debug HAP 警告预算不破；模拟器五项冒烟通过。
