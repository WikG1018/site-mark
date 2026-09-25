# 鸿蒙版对齐批次设计（native 1.0.13 → 对齐 Android v1.0.29）

> 日期：2026-09-25
> 基线：`origin/main` @ `3cc0635`（Android v1.0.29+44 已发布；鸿蒙 native-v1.0.13，2026-09-06 停更）
> 对齐源：`docs/motion-and-material-spec.md`（Phase E 规范）、`lib/motion.dart`、`lib/design_tokens.dart`、决策 D-024
> 需求源：用户 2026-09-25 指示「把鸿蒙版对齐完善」

## 目标

把鸿蒙原生版从 Android v1.0.21 时代的状态追平到 v1.0.29，分两个工作流：

1. **动效/材质对齐（H1–H4）**：把澎湃OS 风格 token 体系（决策 D-024）移植到 ArkTS——
   弹簧曲线、时长表、六档圆角、单一悬浮阴影、玻璃单配方、按压缩放、触感场景补齐、
   弹窗/面板转场、列表入场、看图物理、MiSans 字体。数值一律取自对齐源，不引入平台自选参数
   （响应参数等 ArkUI 特有换算除外，标注 ★ 待真机手感验证）。
2. **功能对齐（H5–H6）**：NAS 双向导入/删除同步（#164）与真实故障可靠性（#162）的
   ArkTS 移植；小型 UI parity（批量死按钮、FAB 滚动稳定性、设置一级开关、仅导出照片）。

## 差距清单（Android v1.0.22–v1.0.29 逐项判定）

| Android 变更 | 判定 | 归属 |
|---|---|---|
| #164 NAS 双向导入/删除同步 | **适用**：Rust trait 已有 `list_project_files`，但 JSON C ABI 未暴露；Dart 编排（`nas_sync_service` + `nas_sync_database` + scheduler + 通知）需 ArkTS 移植 | H5 |
| #162 NAS 真实故障可靠性 | **部分自动**：7 个 rust 文件的核心修复随共享 staticlib 重建即生效；Dart 编排侧修复随 H5 一并评估 | H5 |
| #169–#174 动效/材质 Phase A–E | **适用**：整体移植（本文主体） | H1–H4 |
| #176/#153 Hero 飞行重影 | **不适用**：Flutter Hero 专有；鸿蒙 `geometryTransition` 已有自有实现，H3 仅复核 | — |
| #158 设置页一级开关（图库/定位/通知） | **评估后移植**：鸿蒙相册走 picker（无常驻权限）、定位按需、通知授权时机同 D-022；落点为设置页顶层开关 | H6 |
| #157 仅导出照片选项 | **适用**：Rust `export_selection` 已支持（共享层）；补 ArkTS 导出 UI 选项 | H6 |
| #156 玻璃胶囊 toast / 删批量 View 死按钮 | **适用**：鸿蒙 toast 现为普通行内消息；批量栏复核死动作 | H2/H6 |
| #159 FAB 滚动时稳定 / #161 玻璃透明度统一 | **适用**（#161 已被 Phase C 单配方吸收） | H3 |
| #165/#167/#168 APK 瘦身、armv7 | **不适用**：Android 构建专有 | — |
| #149/`8d617e3`/`7d189f5` 动效流畅度 | **被吸收**：H1–H3 的 token 化转场覆盖其意图 | H1–H3 |

## 非目标

- 不改 `lib/`（Flutter 线零改动）；不改 Android/iOS 行为。
- 不做预测返回（鸿蒙返回手势为系统级，无对应 API 面）。
- 不在本批次内做发布签名（AGC 材料未到位，维持 unsigned HAP）。
- 真机结论不伪造：`hdc list targets` 为空期间，动效手感/触感强度/帧率、NAS 真实网络路径
  一律只登记为 deltas.md「真机验证待补」，模拟器冒烟不写成设备验收。

## 架构：动效/材质 token 层（H1–H4）

### 1. MotionTokens（`shared/MotionPolicy.ets` 扩展或新文件 `MotionTokens.ets`）

时长（对齐 AppMotion，经 `MotionPolicy.duration()` 折叠 reduce-motion）：

| Token | 值 |
|---|---|
| `DURATION_SHORT4` | 180ms |
| `DURATION_MEDIUM2` | 260ms（页面/面板转场） |
| `DURATION_MEDIUM4` | 320ms（缩放/列表入场） |
| `DURATION_LONG2` | 500ms（惯性收尾） |

弹簧（ArkUI `curves.springMotion(response, dampingFraction)`；dampingFraction 直接对齐
Flutter 阻尼比，response 为 ArkUI 换算 ★）：

| Token | 参数 | 对齐源 | 用途 |
|---|---|---|---|
| `springSnap` | springMotion(0.30, 1.0) | mass .5/stiff 100/ratio 1 | 消失回弹、chrome 滑入滑出、弹窗进入 |
| `springSettle` | springMotion(0.38, 0.92) | mass .5/stiff 100/ratio .92 | 按压释放、缩放落点 |
| `springRise` | springMotion(0.28, 0.85) | mass .5/stiff 140/ratio .85 | toast/dock 上升、列表入场 |

cubic（`curves.cubicBezier` 精确移植）：`emphasized`(0.2,0,0,1)、`emphasizedDecelerate`(0.05,0.7,0.1,1)、
`emphasizedAccelerate`(0.3,0,0.8,0.15)、`standard`(0.2,0,0,1)、`standardAccelerate`(0.3,0,1,1)。

业务文件禁止散写 `Curve.EaseOut` / 裸时长；迁移现有 16 处 EaseOut 到对应 token。

### 2. 材质 token（`shared/UiTokens.ets` 扩展）

- `RADIUS_XS 8 / SM 12 / MD 16 / LG 20 / XL 24`（迁移：`CARD_RADIUS` 18→LG 20、
  `CONTROL_RADIUS` 12→SM；pill 用大值）。
- `chromeShadow(dark)` 单配方：light `#14000000` blur 12 / dark `#24000000` blur 14，
  offsetY 3（`shadow({radius, color, offsetY})`）；只有悬浮 chrome 用，卡片保持现状。
- 玻璃单配方对齐 GlassChrome：填充 = SURFACE 色 @ 0.58 alpha、blur σ20
  （继续经 `MotionPolicy.blur()` 折叠）；`GLASS`/`GLASS_STRONG` 旧常量由公式替代并迁移调用点。

### 3. 按压缩放 + 触感（H2）

- `PressSurface` 共享组件：`onTouch` Down → `animateTo(springSettle)` scale 0.96；
  Up/Cancel → 回 1；Move 超触控 slop（约 8vp）即本次手势永久取消；
  reduce-motion 完全静止（`MotionPolicy.reduceMotion` 时不禁用事件，只不缩放）。
- 触感档位（vibrator time 型三档，对齐 MiHaptic 映射意图 ★）：light 16ms / medium 32ms
  （现有）/ heavy 48ms。
- 场景补齐（契约同规范 §6.2：一次语义动作恰好一次触感；FAB/卡片导航静音；校验失败静音）：
  批量破坏性确认 → heavy；表单提交成功 → light；开关/勾选 → selectionClick（16ms 与 light 同档，
  允许）；进入选择模式 → medium（现有）。

### 4. 转场与场景（H3）

- 弹窗（现仅 `RecordScreens.ets` CustomDialog）：open 用 springSnap + 220ms、
  close 用 standardAccelerate + 180ms；reduce-motion → duration 0。
- Toast：消息条升级玻璃胶囊（单配方）+ springRise 入场；`ScreenMessageClock` 行为不变。
- 列表入场：LazyForEach 行首帧 fade + 4% 上移（springRise 320ms），one-shot（会话内每行一次，
  复用 `LazyListDataSource` id 集合语义；重排/前插不重放）。
- 看图物理（`PhotoViewerScreen`/`PhotoViewerWindow`）：单指拖拽出界橡皮筋 0.25；
  松手惯性 ×0.18 + 出界弹簧回位（springSnap）；双击内容矩形缩放（测不到 frame 回退 2x）。
  与现有捏合/`PhotoViewerPanTracker` 协同，reduce-motion 直接跳目标值。

### 5. MiSans（H4）

- 子集文件复用 `assets/fonts/MiSans-{Regular,Medium}.ttf`（pyftsubset 产物，各 <2MB），
  拷入 `entry/src/main/resources/rawfile/font/`，注册 fontFamily `MiSans`，fallback 系统字。
- 关于页双语署名 "MiSans © Xiaomi" + LICENSE 副本同目录；与 Android 关于页文案对齐。

## 架构：NAS 双向同步（H5，实施前另出细化设计）

- Rust：`ffi/mod.rs` dispatch 增加 `nas_list_project_files`（payload 同 nas 配置；
  返回 `{project, file}[]`），Rust 单测覆盖 dispatch。
- ArkTS：`NasSyncService` 扩展双向语义——远端独有照片导入（下载 → 落 RDB → 本地原件登记）、
  删除同步（对账远端缺失 → 本地删除/标记，语义严格对齐 `lib/workflow/nas_sync_service.dart`）。
- RDB v15 增量（如需队列状态字段）必须走可迁移变更；host 契约测试同步。
- 通知与失败重试对齐 #162 语义（串行队列 + 重试预算耗尽停 failed + 手动重试）。

## 测试与门禁

- TDD：每个 token/策略/物理纯函数先测后实现（Hypium，`entry/src/test`）；
  现有 `tool/test_ohos_capture_database_contract*` host 门禁如钉了被改样式需同步。
- 每 PR：`build-hap.ps1 -SkipRust -RunTests` 全绿 + 警告 ≤ 预算 + `run-host-tests.ps1`；
  触碰 rust 的 PR（H5）另跑 `build-rust.ps1` + `cargo test/clippy`。
- CI（主机门禁 + Dart/Rust 回归）双绿；HAP 证据贴 PR。
- 模拟器冒烟可用（debug HAP），但按红线不得写成设备结论。

## 成功标准

- token 层落地后，业务代码无散落曲线/时长/圆角/阴影魔数。
- 触感契约与 reduce-motion 语义和 Android 一致。
- MiSans 生效且关于页有署名；HAP 体积增幅 ≤ 4MB。
- NAS 双向同步行为对齐 #164 语义（host 测试 + 模拟器冒烟），真机项如实登记。
- `native-v1.0.14` 发版（Pre-release），deltas.md 更新后真机清单明确。
