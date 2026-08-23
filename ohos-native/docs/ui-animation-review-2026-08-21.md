# 鸿蒙原生版 UI 与动画审查报告（2026-08-21）

基线：`ohos-native` @ `50e5688`（PR #78 合入后）。审查方式：对 `entry/src/main/ets` 全部 97 个 ArkTS 文件做静态走查，结合最近 4 个 UI/动画相关 PR（#75 动画审查、#76 消息状态、#77 主题传播、#78 界面打磨）与 `docs/deltas.md`、验证记录交叉核对。

> 本机（macOS）没有 DevEco Studio / HarmonyOS SDK，无法编译或跑 Hypium 测试；本报告为静态代码审查。所有"疑似"结论都标注了需要真机验证的项。最近一次自动化基线（2026-08-20，Windows/DevEco）：182 ArkTS 测试 + 34 主机门禁通过，debug unsigned HAP 可构建。

---

## 一、总体评价

这个分支的工程底子明显好于一般"native 移植"项目，以下做得好、不需要动的部分先明确：

- **Token 化彻底**：`UiTokens.ets` 浅色/深色两套完整，`apply(dark, accent)` 统一切换；PR #75 已把散落硬编码色（卡片描边/阴影、模板卡、定位提示）收进 token，深色模式不再泄漏浅色表面。
- **减少动画（reduce motion）闭环完整**：`MotionPolicy` 统一 `duration()/blur()` 归零；`Index.ets` 用代次机制在系统设置变化时刷新并 `pathStack.disableAnimation()`，PR #77 已把已打开屏幕一起传播。API 23 以下安全回退为"不减少"。
- **列表与分页**：`LazyListDataSource` + 50 条分页 + 单飞 + 过期代次丢弃 + 滚动位置/筛选恢复，且有 `LazyListDataSource.test.ets` 等 28 个测试文件兜底。
- **全屏查看器内存策略**：最多 5 张窗口、当前图 2048 / 邻图 1024 解码上限、稳定占位 + 代次回调防旧图覆盖、内存压力 `shrinkToCurrent`。
- **表单与设置**：字段容器、字段级校验、保存单飞、单步撤销、操作防重（`ScreenActionCoordinator` 的 token/epoch 设计）。
- **无障碍**：44vp 热区、全部图标按钮有中英文 `accessibilityText`、选中/禁用/危险状态可读。

下面的问题按"动画"和"界面"两组、P0（影响核心体验）/P1（明显不一致）/P2（打磨项）排列。

---

## 修复状态（2026-08-21 第 2 轮，分支 `bionic/ohos-ui-animation-polish-2026-08-21`）

本轮完成 **A1–A5、B1、B2**；**A6、A7、B3–B8 保留在 Backlog**（A6/A7 后由主线 PR #80/#86 承接，见下文状态标注）。平台差异与验证边界按仓库规则先落入 [deltas.md](deltas.md)。

> 2026-08-23 合入主线 `ohos-native`（PR #79–#91）后的冲突处置：SettingRow 按压取主线 90ms；骨架脉冲取主线 600ms 并保留本轮挂载转场；`LifecycleSegment` 保留本轮参数化结构 + 主线固定 Medium 字重（主线弹性滑动高亮变体无调用方，未采纳）；筛选面板取主线系统半模态。

| 项目 | 状态 | 实现要点 |
| --- | --- | --- |
| A1 跨页面 Hero | 已修复（待真机确认） | 三处 `sharedTransition` → `geometryTransition('capture-photo-${id}')`（API 11+，系统计时，跟随系统减少动画）；`isSelf` 省略走系统默认，最坏回退为默认页面转场、无功能回归；删除已失去作用对象的 `SHARED_TRANSITION_DURATION` / `transitionDuration()` 及对应测试 |
| A2 查看器缩放动画 | 已修复 | `settleZoom` / `toggleZoom` / `resetScale` 走 `getUIContext().animateTo`（180ms EaseOut，reduce-motion 归零）；程序化切页 `resetScale(false)` 瞬时；pinch `onActionUpdate` 保持直接赋值保证跟手 |
| A3 条件面板转场 | 已修复（1 处合并变更） | 抽共享 `panelTransition(distanceVp)`（180ms 入 EaseOut / 120ms 出 EaseIn，非对称 opacity+translate；0 = 纯淡入淡出），铺到模板/建议/定位提示/删除确认/消息/批量栏/根 Dock，并给 EmptyPanel / InlineErrorPanel / ListSkeleton 加挂载转场。**合并变更**：主线 PR #86 将筛选面板改为系统半模态（`bindSheet`，自带出现/消失动画与返回键联动），筛选项的 `panelTransition(24)` 移除 |
| A4 Swiper 翻页时长 | 已修复 | 查看器专用 `ViewerNodePolicy.SWIPE_DURATION = 320ms`（新增“慢于通用 UI 动效”测试），全局 `MOTION_STANDARD` 不变；Swiper 的 `duration` 参数不接受曲线，保留系统默认曲线 |
| A5 勾选/按压动画 | 已修复（1 处偏差） | SettingRow 按压高亮 90ms 淡入（与主线 #80 取值对齐）；卡片勾选徽章 120ms 颜色/透明度交叉淡化 + 挂载淡入。**偏差**：审查建议 opacity+scale(0.8)，但选择模式下徽章恒在，缩放会改变静止未选徽章尺寸，故只用 opacity/颜色 |
| B1 搜索框统一 | 已修复 | 项目 Tab 与项目详情的手写胶囊 TextInput（GLASS_STRONG/22vp）换成 `AppSearchField`，与记录 Tab 同一视觉语言；两处均带 accessibilityLabel，详情入口保留 pageBusy 禁用态 |
| B2 分段控件收敛 | 已修复（1 处延后） | `LifecycleSegment` 参数化：`pill` 精确复现原 `statusChip`（CONTROL 底、24/22vp、14fp），默认 segment 复现原 ChoiceButton 行（SURFACE_MUTED 底、15/12vp、13fp、等宽）；新增 `controlEnabled`，统一 `choiceAccessibilityText` 播报；删除 `ChoiceButton`。**合并变更**：chip 文字改固定 `FontWeight.Medium`（主线 #80/#86 防抖动决定，与主线 statusChip 修复一致）。**延后**：记录筛选的项目 chips 为不定长横向滚动，等宽分段控件无法表达，暂不改造 |

## 二、动画问题

### A1（P0，需先真机验证）跨页面 Hero 转场疑似未生效：`sharedTransition` 用错了 API

**状态：已修复（待真机确认）。**三处统一改为 `geometryTransition('capture-photo-${id}')`；“先真机走查”仍是转正前提，见 deltas.md 新增行。

三处 Hero 节点全部使用 `sharedTransition`：

| 位置 | 节点 |
| --- | --- |
| `feature/records/RecordComponents.ets:89` | 记录卡片缩略图（列表页，Navigation 根内容） |
| `feature/records/RecordScreens.ets:1618` | 记录详情媒体区（`CAPTURE_DETAIL` 页） |
| `feature/records/PhotoViewerScreen.ets:350` | 全屏查看器当前照片（`PHOTO_VIEWER` 页） |

跳转链是 `列表 → push(CAPTURE_DETAIL) → push(PHOTO_VIEWER)`，三者分属**不同页面**。ArkUI 中：

- `sharedTransition(id, options)`：仅用于**同一页面内**的组件共享转场（条件渲染替换）；
- `geometryTransition(id, isSelf)`：用于 **Navigation 跨页面**的共享元素转场。

按 API 语义，当前写法在 push/pop 时不会触发 Hero 动画，用户看到的只会是系统默认的页面滑入滑出；220ms 的"统一共享转场时长"（`ViewerNodePolicy.SHARED_TRANSITION_DURATION`）实际没有作用对象。三处调用反而是惰性列表里的额外几何采集开销。

**建议**：
1. 先真机走查一次（列表卡→详情、详情→查看器、查看器→返回），确认是否无 Hero；
2. 若确认，把三处统一改为 `geometryTransition('capture-photo-${id}', isSelf)`（两端同 id，isSelf 按官方跨页面样例设置；API 11+，与 `compatibleSdkVersion 17` 无冲突），保留 220ms 时长与 reduce-motion 归零；
3. 若实测默认页面滑动已被接受，则直接删掉三处 `sharedTransition` 调用，省掉列表侧的几何采集成本。两条路线都必须落文档。

### A2（P0）全屏查看器缩放无任何动画

**状态：已修复。**三处改走 `getUIContext().animateTo`（180ms EaseOut，reduce-motion 归零）；pinch 实时跟手保持直接赋值。

`PhotoViewerScreen.ets` 的 `toggleZoom()`（双击 2.5x/还原）、`resetScale()`（单击/返回时归位）、`settleZoom()`（pinch 结束吸附）都是**直接赋值** `viewerScale` / `panOffsetX` / `panOffsetY`，`@State` 跳变不走 `animateTo`，于是双击缩放是"瞬移"。这是查看器最核心的交互，当前观感会明显生硬。

**建议**：三处改为 `this.getUIContext().animateTo({ duration: MotionPolicy.duration(180), curve: Curve.EaseOut }, () => { ...赋值... })`；pinch `onActionUpdate` 期间的实时跟手保持直接赋值不动。reduce-motion 下 `MotionPolicy.duration` 已归零，无需额外分支。

### A3（P1）条件面板全部硬切：筛选 / 模板 / 建议 / 删除确认 / 消息

**状态：已修复（1 处合并变更）。**共享 `panelTransition(distanceVp)` 统一上述面板，并铺到批量栏、根 Dock 与空态/错误/骨架节点；合入主线 PR #86 后筛选面板改为系统半模态（`bindSheet`），筛选项的 `panelTransition(24)` 移除（系统 sheet 自带出现/消失动画）。

以下"出现/消失"都没有 `.transition()`，直接 pop：

- `RecordScreens.ets:588` 附近：`if (this.filterOpen) { this.filterPanel() }`（筛选面板）
- `RecordScreens.ets` 拍摄表单：`templatePanel()`（模板面板）、建议面板（`suggestionField`）、`undoAvailable` 撤销按钮、定位权限提示块、`message` 文本
- `ProjectScreens.ets` 项目详情：`if (this.confirmDelete)` 删除确认面板、`message` 文本

对照：批量栏 `RecordScreens.ets:498` 的 `batchBar` 和根 Dock 都已经有了 opacity+translate 的非对称转场（180ms 入 / 120ms 出），说明模式是现成的，只是没铺开到这些面板。

**建议**：抽一个共享 `TransientPanel` 包装（或统一 `@Builder` 修饰器）内置 `TransitionEffect.asymmetric(opacity+translate(24) 入 EaseOut 180ms / 出 EaseIn 120ms)`，上述 5+ 处直接套用，避免每处重复写转场参数。

### A4（P1）全屏 Swiper 翻页 180ms 偏快

**状态：已修复。**查看器专用 320ms（`ViewerNodePolicy.SWIPE_DURATION`，含测试），全局 180ms 不动。

`PhotoViewerScreen.ets` 的 `Swiper().duration(MotionPolicy.duration(UiTokens.MOTION_STANDARD))` = 180ms。这是系统默认 600ms 的 1/3，50MP 大图连续左右切会显急促。

**建议**：查看器单独给一个时长（建议 300–360ms，`Curve.EaseInOut`），不动全局 `MOTION_STANDARD`（Dock/批量栏等 UI 元素 180ms 是合理的）。

### A5（P2）选中勾选与按压反馈无动画

**状态：已修复，1 处偏差。**勾选徽章不做 scale(0.8)（会改变静止徽章尺寸），改为 120ms 颜色/透明度交叉淡化 + 挂载淡入；SettingRow 按压淡入初为 100ms，合入主线 #80 后对齐其 90ms 取值。

- `RecordComponents.ets` 卡片选择圆标（✓/遮罩圈）在 `selected` 变化时瞬现瞬灭；
- `AppComponents.ets` 的 `SettingRow` 按压高亮在 `onTouch` 里硬切背景色。

**建议**：勾选圆标加 120ms `opacity+scale(0.8→1)`；SettingRow 高亮加 100ms 淡入。两者成本都很低。

### A6（P2）启动/隐私页硬切

**状态：主线已实现（PR #80）。**

`Index.ets` 的 `spinner → privacyGate → 主界面` 三段都是硬切。可加 200ms 淡入（`Navigation` 出现时）。低优先级，属于第一印象打磨。主线 PR #80 已给 spinner/隐私门/运行时错误/恢复四分支加 180ms 淡入，此项关闭，真机走查确认即可。

### A7（P2，仅走查）Tab 切换位移距离偏小

**状态：Backlog（走查）。**并入真机走查项，不预设改动。

根分支切换用 24/16vp 位移 + 整体 opacity，方向感很弱。是否"太弱"属于观感判断，建议并入真机走查项，不预设改动。主线 PR #86 已将 Tab 切换改为 `curves.springMotion` 弹性曲线（reduce-motion 瞬时切换），走查需确认弹性曲线下方向感是否仍然偏弱。

---

## 三、界面问题

### B1（P1）两个根 Tab 搜索框样式不一致

**状态：已修复。**项目 Tab 与项目详情搜索框统一为 `AppSearchField`。

- 项目 Tab：`ProjectScreens.ets:253` 手写 `TextInput`，22vp 全圆胶囊 + `GLASS_STRONG` 背景；
- 记录 Tab：`AppComponents.ets:262` 的 `AppSearchField`，12vp 圆角 + `SURFACE_MUTED` + 描边 + `⌕` 图标。

同一层级两个入口视觉语言不同，直接违反 README 自己定的"统一表面与间距"。**建议**：项目 Tab 换成 `AppSearchField`（或把两者收敛为一个组件 + 形状 token）。

### B2（P1）分段选择控件存在三套并存

**状态：已修复，1 处延后。**`LifecycleSegment` 参数化为唯一分段控件（pill/segment 两形态）并替换 `statusChip`、`ChoiceButton`；记录筛选项目 chips（不定长滚动）暂不改造。

- `AppComponents.ets:286` 的 `LifecycleSegment`（`SURFACE_MUTED` 底、12vp 圆角）——**全仓库无调用方，死代码**；
- `ProjectScreens.ets:232` 手写 `statusChip`（24vp 全圆胶囊、`CONTROL` 底）实际在用；
- 记录筛选的项目 chips、设置页 `ChoiceButton`（12vp 圆角）又是另外两种。

**建议**：以 `LifecycleSegment` 为基础改造成唯一的"分段/胶囊选择"组件（形状可参数化：segment=12vp / pill=22vp），替换 `statusChip`、`ChoiceButton`、筛选 chips 三处，然后删除死代码。这一步和 B1 同属"控件收敛"，建议同一个 PR 做。

### B3（P1）图标体系混杂：图片资源与 Unicode 符号混用

**状态：Backlog。**

根 Dock 用的是真正的图片资源（`$r('app.media.ic_projects')` 等，fillColor 染色），但其余图标全是 Unicode 字符：`⌕ ≡ ‹ ⇩ ▣ ⌫ × ◇ ◩ ⌖ ◉ ◐ ⓘ ⇅ ▤ ▦ ◆ ↻ ↔`。字符图标在不同系统字体/大字体档位下粗细和基线不一致，深色模式下视觉重量也和图片图标不统一（例如 `‹` 返回键在 32fp 下明显偏细）。

**建议**：分 2–3 个 PR 把高频图标（返回、搜索、筛选、批量四件套、设置行 8 个）替换为统一 24vp 线性/面性向量资源（`fillColor` 染色复用 Dock 的做法）；低频装饰符号（`◇ ▦` 空状态）可最后处理。

### B4（P1）水印设置预览是"假照片"

**状态：Backlog。**

`ProjectFormPolicy.ets:195` 的 `WatermarkPreviewStyle.BACKGROUND = '#081412'` + 占位文字，只能预览排版，看不到真实照片上的水印效果。

**建议**：用该项目最近一张成片（1024 解码上限）作为预览底图，叠真实水印文本层（现有 `previewLayout` 逻辑可复用）；无照片时回退现在的占位框。这是设置页感知提升最直观的一处。

### B5（P2）设置页"完成通知"行手写复制 SettingRow 布局

**状态：Backlog。**

`SettingsScreens.ets:141` 附近手写了 icon+标题+副标题+Toggle 并手工补了 `constraintSize/minHeight/padding`，与 `SettingRow` 完全同构。建议给 `SettingRow` 加 `@BuilderParam trailing` 收编，顺带获得按压高亮一致性。

### B6（P2）AppTopBar 标题字号规则粗糙

**状态：Backlog。**

`AppComponents.ets:52` 的 `this.title.length > 20 ? 22 : 24` 以字符数粗切，中文 20 字与英文 20 字视觉宽度差很多。建议改为"首行放不下时降一级"的自适应（`Text` 的 `maxLines(1)` + 测量回调，或简单按语言切换阈值）。

### B7（P2）平板/横竖屏未设计

**状态：Backlog，独立任务。**

`module.json5` 声明了 `phone / tablet / 2in1`，但全部布局是单列纵向，平板上两侧大面积留白。手机是主场景，建议至少：要么文档中明确"本期仅保证 phone 竖屏"，要么做 1 个最小适配（列表断点变 2 列 Grid）。归入独立任务，不阻塞其他项。

### B8（P2）列表无下拉刷新

**状态：Backlog（可选项）。**

记录/项目列表都没有 `Refresh` 组件，依赖 runtime 通知刷新。数据源都是应用自己产生，自动刷新逻辑成立，可不加；若加，注意与"分页单飞"的交互。列为可选项。

---

## 四、与 UI/动画相关但非界面本身的提醒

1. **所有设备级验证仍空缺**（`docs/deltas.md` 已如实记录：`hdc list targets` 为 `[Empty]`）。本报告 A1 是其中唯一"代码层面疑似不工作"的项，必须优先真机确认。
2. **`compatibleSdkVersion 17`**：`sharedTransition`（API 12+）与 `geometryTransition`（API 11+）均可用；reduce-motion 查询（API 23+）已有版本守卫。改成 `geometryTransition` 不会引入新的兼容性问题。
3. **backdropBlur 性能**：Dock（24/14）、批量栏（12）持续存在，reduce-motion 时已归零；中低端真机走查时把"开启动画"档位也测一遍 GPU 占用，若超标可把 Dock 模糊降到 8 或直接去掉（PR #75 已因性能移除过卡片级 blur）。
4. **Release 签名仍未配置**（`build-profile.json5` 的 `signingConfigs` 为空）——发行前置项，与 UI 无关但常一起被问。

---

## 五、建议修复顺序（Backlog）

> 更新：序 2、3、4、5、6、7 已在本轮完成（A2/A3/A1/B1+B2/A4/A5）。序 1（真机走查）与 8–11 仍待排期。

| 序 | 项目 | 工作量 | 依赖 |
| --- | --- | --- | --- |
| 1 | 真机走查基线：Hero 转场(A1)、Tab 切换(A7)、Swiper 翻页(A4)、大字体、深色、减少动画 | 半天（需设备） | 无 —— **后续全部动画项的前提** |
| 2 | A2 查看器缩放 `animateTo` | S | 无 |
| 3 | A3 条件面板统一转场（抽共享 builder，铺 5+ 处） | M | 无 |
| 4 | A1 Hero 转场改 `geometryTransition`（或确认接受默认滑动后删除调用） | M | 走查结论 |
| 5 | B1 搜索框统一 + B2 分段控件收敛（删 `LifecycleSegment` 死代码、统一 `statusChip`/`ChoiceButton`/chips） | M | 无 |
| 6 | A4 Swiper 时长 320ms | XS | 无 |
| 7 | A5 勾选/按压 120ms 动画 | XS | 无 |
| 8 | B3 图标向量化（返回/搜索/筛选/批量/设置行，分 2–3 PR） | L | 无 |
| 9 | B4 水印真实预览 | M | 无 |
| 10 | B5/B6 设置行收编、标题字号 | S | 无 |
| 11 | B7 平板适配 或 文档声明仅 phone | M | 独立任务 |

2–7、8、9 之间无依赖，可按此序拆成 4–6 个小 PR，每个 PR 都沿用现有门禁（ArkTS 测试 + HAP 构建 + 主机门禁）与"先写失败测试再实现"的仓库惯例；纯视觉项（A2/A3/A4/A5/B1/B2/B4/B5/B6）以策略/组件级测试 + 真机截图走查验收。
