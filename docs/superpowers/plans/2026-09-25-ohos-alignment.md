# 鸿蒙对齐实施计划（2026-09-25）

> 设计：`../specs/2026-09-25-ohos-alignment-design.md`
> 基线：main @ `3cc0635`。每个阶段独立 PR（merge commit），本地门禁全绿再推。

## H0 设计+计划入库（本 PR）

- [x] 设计文档 + 本计划。

## H1 动效/材质 token 层

- [ ] `MotionTokens`：时长四档 + 三弹簧（springMotion 映射）+ 五 cubic（cubicBezier 精确值）；
      reduce-motion 经 `MotionPolicy.duration()` 折叠；Hypium 单测（token 值、折叠语义）。
- [ ] `UiTokens`：`RADIUS_XS..XL`、`chromeShadow()`、玻璃公式（SURFACE@0.58 + σ20）；
      迁移 `CARD_RADIUS`/`CONTROL_RADIUS`/`GLASS`/`GLASS_STRONG` 调用点；
      迁移散落 `Curve.EaseOut`（16 处）到 token；契约测试正则同步（如有钉住）。
- [ ] 门禁：build-hap -RunTests、run-host-tests、警告预算。

## H2 按压缩放 + 触感补齐

- [ ] `Haptics.lightImpact()/heavyImpact()`（16/48ms）；单测档位值。
- [ ] `PressSurface` 共享组件（onTouch 驱动、slop 取消、reduce-motion 静止）；单测状态机（注入事件）。
- [ ] 场景接线：主按钮/卡片/FAB/批量按钮按压；批量破坏性确认 heavy、表单提交成功 light、
      开关 selectionClick；FAB/导航卡静音。
- [ ] deltas.md 触感行更新（含"强度映射 ★ 待真机"）。

## H3 转场/列表入场/看图物理

- [ ] CustomDialog open/close 转场 token 化（springSnap 进 / standardAccelerate 出）。
- [ ] Toast 玻璃胶囊 + springRise 入场。
- [ ] 列表行入场 one-shot（fade + 4% 上移，springRise 320ms）；重排不重放单测。
- [ ] 看图：橡皮筋 0.25、松手惯性 ×0.18、弹簧回位、双击内容矩形缩放（回退 2x）；
      物理纯函数单测；reduce-motion 直接跳目标。
- [ ] FAB 滚动稳定性复核；`geometryTransition` 走查复核（无重影）。

## H4 MiSans

- [ ] 字体子集入 `resources/rawfile/font/` + fontFamily 注册 + fallback。
- [ ] 关于页双语署名 + LICENSE 副本。
- [ ] HAP 体积核对（≤ +4MB）。

## H5 NAS 双向同步（先出细化设计再实施）

- [ ] Rust：`nas_list_project_files` 进 JSON C ABI dispatch + Rust 测试。
- [ ] ArkTS：双向导入/删除同步编排、RDB 迁移（如需）、host 契约测试。
- [ ] #162 Dart 编排侧修复逐项评估移植；通知/重试语义对齐。
- [ ] 模拟器冒烟（本地 NAS 服务）+ deltas.md 真机项登记。

## H6 小型 parity

- [ ] 批量栏死动作复核（对齐 #156 删 View）；仅导出照片选项（#157）。
- [ ] 设置页一级开关评估落点（#158：图库=picker 说明、定位/通知=授权跳转）。

## H7 收尾发版

- [ ] `ohos-native` 版本 bump native-v1.0.14（versionCode 1000014）。
- [ ] deltas.md 全面更新（动效/触感/字体/NAS 行 + 真机清单）。
- [ ] build-hap 产物上传 `native-v1.0.14` Pre-release；README 版本表更新。

## 记录

- H0 #179、H1 #180、H2 #181、H3a #182、H3b #183、H4 #184、H5（设计/策略/迁移/桥接/预览/远端删除）#185 已合并。
- 本 PR（收尾批次）：H5 导入执行器 + 设置页模式切换与恢复流；H3 列表行入场（`rowEntranceEffect`，首屏后武装、每行一次，记录与项目详情两列表）；触感契约修复（dock 切换触感从 runTabAction 移至 switchTab——finish 动作也是 started，原实现会双响）；H6 评估落 deltas（批量栏无死动作、导出已随共享 Rust 获得照片结构、#158 一级开关不移植）；H7 版本 bump native-v1.0.14 + README/NEXT_AGENT_PROMPT/deltas。
- 本地门禁：build-hap -RunTests 全绿（285 测试）、host 契约测试 15/15、警告预算内；真机项全部如实登记 deltas.md 待补。
