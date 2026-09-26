# SiteMark 动效 / 材质规范（Phase E）

> 版本：2026-09-23（2026-09-26 修订适用范围）。适用范围：Android / iOS / 鸿蒙——鸿蒙原生已按本文对齐（springMotion 的 response 为 ArkUI 换算值，手感验证状态见 `ohos-native/docs/deltas.md`）；Flutter 线以本文为准。
> 对标：小米澎湃OS「生命感美学」。**重要前提**：小米未公开第三方 App 的动效数值规范；本文所有数值均为**工程选择**（★），不是小米官方要求。可直接引用的一手依据只有 MiSans 授权与 MiHaptic 触感体系（★★★）。
> 跨项目调研原文（可信度分级、许可细节、MiHaptic 映射表）：交接机桌面 `小米澎湃OS设计规范调研-2026-09.md`（不在仓库内）。

## 1. 可信度标记

| 等级 | 含义 |
| --- | --- |
| ★★★ | 官方一手（MiSans 授权 / MiHaptic / 大屏与深浅色合规） |
| ★★ | 官方场合表述的媒体转述（「生命感美学」定性） |
| ★ | 工程自选数值，上线前须真机验证手感 |

## 2. 设计语言（★★）

「生命感美学」六要点在本应用的落点：

1. **全局圆角** → `AppRadius` 六档（见 §4）。
2. **模糊混色** → `GlassChrome` 单配方玻璃（见 §5）。
3. **柔和阴影** → `AppShadow.chrome` 单一悬浮阴影（见 §4）。
4. **环境色感知** → `DynamicColorBuilder` + `ColorScheme.fromSeed`（既有）。
5. **灵动光效** → 玻璃顶部高光 + overlay 微光泽（`GlassSurface.enableOverlay`）。
6. **动效「舞台艺术」** → 三档弹簧曲线 + 统一弹窗/面板转场（见 §3）。

## 3. 动效 token（★，`lib/motion.dart`）

### 3.1 时长

| Token | 值 | 用途 |
| --- | --- | --- |
| `short4` | 180ms | 图标/透明度微交互、弹窗退出 |
| `pageTransition` / `medium2` | 260ms | 路由转场、面板进出 |
| `medium4` | 320ms | 缩放动画、列表 entrance |
| `long2` | 500ms | 惯性收尾、大位移 |

### 3.2 曲线与弹簧

Flutter iOS 默认弹簧族（mass 0.5 / stiffness 100–140），三档阻尼比：

| Token | 参数 | 用途 |
| --- | --- | --- |
| `springSnap` → `springSnapBack` | mass .5 / stiff 100 / ratio 1 | 消失回弹、chrome 滑入滑出、弹窗转场 |
| `springSettle` → `springScaleSettle` | mass .5 / stiff 100 / ratio .92 | 缩放落点（按压释放、双击缩放） |
| `springRise` → `springSlideRise` | mass .5 / stiff 140 / ratio .85 | pill/面板上升（toast、dock、列表 entrance） |

派生 cubic（与 M3 对齐，用于非弹簧场景）：`emphasized` / `emphasizedDecelerate` / `emphasizedAccelerate` / `standard` 三件套。

**端点精确**：`SpringCurve` 对采样值做端点归一，0/1 精确落在目标上——凡「必须停在终值」的驱动（可见性、scale 目标、dismiss 归位）一律走弹簧曲线，不用裸 cubic。

### 3.3 统一弹窗 / 面板（`AppMotion.dialogStyleOf` / `sheetStyleOf`）

- 进：`springSnapBack`，dialog 220ms / sheet 260ms。
- 出：`standardAccelerate`，`short4`。
- reduce-motion：`AnimationStyle.noAnimation`。

### 3.4 禁止事项

- 业务代码不得写死 `Duration` / `Curves.xxx`；一律取 `AppMotion.*`。
- 手势松手（回弹 / 惯性）走 `SpringSimulation` / 物理采样，禁止 tween 硬凑。
- reduce-motion 下：按压缩放完全静止（跳变闪烁比动画更刺激），转场塌缩为无动画，触感承载反馈。

### 3.5 场景落点（Phase A–D 已迁移）

| 场景 | 行为 |
| --- | --- |
| 全屏看图双击 | 内容矩形缩放（`contentRectFillScale`），测不到 frame 回退 2x |
| 全屏看图拖拽 | 橡皮筋 0.25；松手惯性 ×0.18 + 边界弹簧收尾 |
| 列表行进出场 | `capturePagedItemEntrance`：fade + 4% 上移，`springSlideRise`；冷启动顶部 `entranceSettledCount` 行不动 |
| 照片 Hero | cover→contain 交叉淡化 shutte；入口帧封印防重影 |
| 按压缩放 | `PressScale` / `PressScaleView`，`kInteractivePressScale = 0.96` |
| 弹窗 / 面板 | `dialogStyleOf` / `sheetStyleOf` |

## 4. 形状与深度 token（★，`lib/design_tokens.dart`）

### 4.1 圆角 `AppRadius`（六档）

| Token | 值 | 用途 |
| --- | --- | --- |
| `xs` | 8 | 缩略图、chip、进度条 |
| `sm` | 12 | 预览图、banner、菜单行 |
| `md` | 16 | 输入框、按钮、分段控件 |
| `lg` | 20 | 卡片、设置组、面板头 |
| `xl` | 24 | dock、批量条、toast、FAB |
| `pill` | 999 | 全圆 pill / 圆形 |

规则：表面尺寸与角色选档，禁止散落魔数。相邻档差 2px 光晕，保持一个形状家族。

### 4.2 阴影 `AppShadow.chrome`（单配方）

| 模式 | color | blur | offset |
| --- | --- | --- | --- |
| light | shadow @ 8% | 12 | (0, 3) |
| dark | shadow @ 14% | 14 | (0, 3) |

只有悬浮 chrome 带阴影；卡片内容保持扁平。

## 5. 玻璃材质（★，`lib/shared/ui/glass_surface.dart`）

**唯一配方 `GlassChrome`**：opacity **0.58** / blurSigma **20**。调材质改配方，禁止 fork。

| 层 | 说明 |
| --- | --- |
| 填充 | surface @ 0.58 |
| 模糊 | BackdropFilter sigma 20 |
| 高光 | 顶部细高光线（增加厚度感） |
| 描边 | 内描边 |
| overlay | 极低透明 `BlendMode.overlay`（可关） |

**Android 性能红线**：`BackdropFilter` 是每帧 saveLayer。列表卡片禁用实时 blur（`blurOnAndroid: false` 默认）；仅常驻 chrome（dock 等）可 `blurOnAndroid: true`。v1.0.20 掉帧教训。

**reduce-motion**：关 live blur，保留同色填充与描边；调用方不得依赖 blur 做内容对比度。

## 6. 按压与触感（★★★ MiHaptic 映射，★ 落地）

### 6.1 按压形态

- 指针驱动（`Listener` 原始指针，非 `GestureDetector`——后者有 ~100ms 死区）。
- 缩放 0.96；reduce-motion 下完全静止。
- 变暗 ≤8%（如用）。

### 6.2 触感契约（勿回退）

> **一次语义动作 = 恰好一次触感。** 校验失败静音（见 `capture_form_screen_test.dart`）。

| 交互 | API | 时机 |
| --- | --- | --- |
| 开关 / 勾选 | `lightImpact` | 切换成功时 |
| 分段 / 刻度 / dock 切换 | `selectionClick` | 切换成功时 |
| 破坏性确认 / 批量 | `heavyImpact` | 确认时 |
| 提交 / 保存 | `selectionClick` 或 `lightImpact` | 成功时 |

**禁止**：FAB、卡片导航等「只是去某处」的动作响触感；按压缩放本身不响，触感由动作语义持有。

## 7. 字体 MiSans（★★★ 授权 / ★ 嵌入）

- 授权：免费商用、可嵌入分发、**关于页署名**（"MiSans © Xiaomi"）、禁止改轮廓 / 单独出售。
- 嵌入：`pyftsubset` 子集化 Regular + Medium（GB2312 常用字 + 标点 + ASCII/数字），`assets/fonts/`，单字重目标 **&lt; 2MB**。
- `pubspec.yaml`：`fontFamily: MiSans` + 系统 fallback 链（生僻字 / emoji）。
- 关于页：双语署名 + LICENSE 副本入库。

详见同目录 `misans-attribution.md`（若已建）与 `assets/fonts/LICENSE-MiSans.txt`。

## 8. 合规（★★★）

- 断点：≥600dp 平板、≥840dp 大屏。
- 间距：4 / 8 / 12 倍数。
- 对比度：WCAG 2.1 AA（正文 4.5:1，大字 3:1）。
- 深色：跟随系统；非纯黑白，主色降饱和。

## 9. 验证纪律

1. 动效 / 触感 / 帧率结论**只认真机**（Android 真机 + 鸿蒙真机），模拟器与单测不得替代。
2. 上线前逐场景录屏 A/B（对照系统相机 / 一流 App）。
3. Android 中低端机必测列表滚动与弹窗 blur。

## 10. 预测返回

Android 已 `targetSdk 37` + `enableOnBackInvokedCallback="true"`（系统返回派发就绪）。**预测返回转场暂不接入**，理由与备忘见 `superpowers/handoffs/2026-09-23-predictive-back-evaluation.md`。
