# SiteMark 动效/材质升级交接文档（2026-09-23）

> 交接对象：接手"小米澎湃OS 风格动效/材质升级"（Phase A–E + MiSans）的下一个 agent。
> 用户已批准全部范围："a到e都要，misans也需要"。

## 一、任务背景

用户认为 app 质感/动画未达一线大厂水准，要求按小米 HyperOS 审美升级。调研结论：小米未公开数字动效规格，动效参数为工程自选（Flutter iOS 家族默认 spring：mass 0.5 / stiffness 100–140，三档阻尼比）。

- **跨项目调研文档**（含可信度分级、MiSans 许可、MiHaptic 映射表）：`C:\Users\Administrator\Desktop\小米澎湃OS设计规范调研-2026-09.md`（在交接电脑的桌面上，不在仓库内）。
- 五阶段计划：A 弹簧引擎 → B 按压缩放+触感 → C 材质 token+玻璃统一+弹窗转场 → D 列表进出场+Hero 扩展+看图物理+预测返回评估 → E 动效材质规范文档+MiSans 嵌入。

## 二、已完成并合并 main（main = `31b6bd9`，测试基线 1149 green）

| 阶段 | PR | 内容 |
|---|---|---|
| A | #169 | `lib/motion.dart`：`SpringCurve`（SpringSimulation 采样、端点精确 0/1）+ `springSnap/Settle/Rise` + 派生曲线；首批场景迁移（fullscreen 双击/回弹、路由、dock、toast、选中标记） |
| B | #170 | `lib/shared/ui/press_scale.dart`：**指针驱动**的 `PressScale`/`PressScaleView`（onTapDown 有 ~100ms 死区，必须用 Listener 原始指针）；触感归语义动作原则（FAB/卡片导航不响，提交/勾选/开关响一次） |
| C | #171 | `lib/design_tokens.dart`：`AppRadius`（8/12/16/20/24/999 六档）+ `AppShadow.chrome`；`GlassSurface` 默认值直取 `GlassChrome`（.58/20 单配方）；`AppMotion.dialogStyleOf/sheetStyleOf` 统一全部弹窗/面板转场（spring 进、加速出、reduce-motion 塌缩） |

关键设计决策（勿回退）：
- 触感契约：一次语义动作 = 恰好一次触感；校验失败静音（`capture_form_screen_test.dart` 钉死此行为）。
- Android 玻璃策略：blur 按 chrome 表面 opt-in（`blurOnAndroid: true`），列表卡片禁用（v1.0.20 掉帧教训）。
- reduce-motion 下按压缩放完全静止（跳变闪烁比动画更刺激），触感承载反馈。

## 三、进行中：Phase D（WIP，**未推送**）

- 位置：worktree `.worktrees/motion-d`，本地分支 `feat/motion-phase-d-physics-hero-list`，WIP 提交 `53adc12`（基于 31b6bd9）。
- **该分支不能编译**，提交信息里也写明了。已完成 ~70%：
  1. **列表进出场**：`CapturePagedList` 新增 `itemEntrance`（`CapturePagedItemEntranceBuilder`，one-shot per row via `_enteredRowIds`）。**尚未在两个调用点接线**：`all_captures_screen.dart:~370` 和 `project_detail_screen.dart:~510` 的 `CapturePagedList(itemEntrance: …)` 需传入 rise 包装器（建议：FadeTransition+SlideTransition 0.04 偏移，`AppMotion.springSlideRise`，注意 reduce-motion 直接 rise=1）。
  2. **Hero 统一**：`capture_photo_hero.dart` 新增 `CapturePhotoHeroFrame`（tag+path+fit）与共享 shuttle `capturePhotoHeroFlightShuttle`（cover→contain 交叉淡化）；detail 屏（`capture_detail_screen.dart:257`）、preview 自包裹（`capture_image_preview.dart:~274`）、fullscreen 端点（`_FullscreenPhotoFrame` 的 `_heroSealed` 首帧封印防重影）三处已接线。
  3. **看图物理**：`capture_fullscreen_screen.dart` 的 `_panUpdate`（橡皮筋 0.25 系数 + VelocityTracker 采样）、`_settlePan`（释放惯性 velocity×0.18 + 边界弹簧收尾）已写好。
  4. **双击内容矩形**（未完成，3 个已知缺陷）：
     - `_frameRenderBox()` 引用的 `final Map<String, GlobalKey> _frameKeys = {};` **字段未声明**（应加在 `_transformationControllers` 旁，并在 itemBuilder 的 `fullscreen-photo-id-…` KeyedSubtree 处注册）；
     - `_handleDoubleTap` 里算了 `final zoom = _contentRectScale();` 但矩阵仍是 `..scaleByDouble(2.0, …)`，**需改用 zoom**；
     - `_contentRectScale` 用了 `math.min` 但**缺 `import 'dart:math' as math;`**。
- 修完后的收尾清单：
  1. `flutter analyze` 清零（用 3.44.6 SDK，见铁律）；
  2. 接线两个列表调用点的 `itemEntrance`；
  3. 补测试：viewer 橡皮筋/惯性/内容矩形双击（注意既有用例 `'double tap zooms to 2x and back to 1x'` 会因 content-rect 缩放改变断言——`_contentRectScale` 在测不到 frame 时回退 2.0，测试用不存在路径的照片，先实测再改断言）；paged list entrance 的 one-shot；
  4. `dart format`（3.44.6）→ commit → push → PR → CI 双绿 → merge commit；
  5. **预测返回评估**（原 Phase D 子项，未动）：Android `targetSdk 37` + `android:enableOnBackInvokedCallback="true"` 已就绪；Flutter 3.44 有 `PredictiveBackPageTransitionsBuilder`；评估是否接入并写结论即可，不必强行实现。

## 四、未开始：Phase E

1. `docs/motion-and-material-spec.md`：token 清单+理由+截图基线（引用调研文档的工程替代表）。
2. **MiSans 嵌入**：官网 https://hyperos.mi.com/font 下载；许可：免费商用、可嵌入、需在"关于"页署名，不得衍生字体轮廓；用 `pyftsubset` 子集化（Regular+Medium 两字重，含 GB2312 常用字+拉丁），放 `assets/fonts/`，pubspec `fontFamily: MiSans` + fallback 链（系统字体），About 页加双语署名 + LICENSE 副本。注意 APK 体积（子集后应 <2MB/字重）。

## 五、工作流铁律（违反会翻车）

1. **一切改动经 PR → CI 双绿（ubuntu `test` + macos `ios`）→ merge commit 合入 main**；禁 squash、禁直推 main、`gh pr merge` 不加 `--delete-branch`（会切走 worktree 的分支）。
2. **源码写改只用 Edit/Write 工具**（Mimosa 钩子拦 Bash 写源文件）；commit 钩子若报 `library_source_unavailable` 属已知噪音，按兼容策略继续，但**不得宣称项目安全**。
3. **推送门禁扫描 primary 工作树**（`C:\Users\Administrator\Documents\Codex\2026-07-15\new-chat`，必须停在同步的 main）。本次交接前 primary 曾落后在 `6ebe448`，已同步到 `31b6bd9`——**每次开工前先核对**。
4. `dart format`/`flutter` 一律用 `C:\Users\Administrator\Development\flutter-3.44.6\bin\…`（PATH 上的 3.47.2 dart_style 版本不同，格式化结果不一致会挂 CI）。
5. `test/features/settings/sections/about_section_screen_test.dart` 钉死版本号字符串，任何版本 bump 必须同步改。
6. 签名材料（Apple/Android）永不入库/日志/CI 输出，只走 GitHub Secrets。
7. Android/鸿蒙行为不得改变；用户可见字符串中英双语；真机结论不得用模拟器/单测冒充。
8. Windows 陷阱：`git worktree remove` 长路径失败 → `rm -rf` + `git worktree prune`；widget 测试双击识别器后要 `pump(350ms)` 清定时器；`Transform.scale` 的 `getMaxScaleOnAxis()` 恒 1（z 轴），读 `transform.storage[0]`；Ticker 首拍 elapsed=0，断言前补一拍。

## 六、环境速查

- 仓库：https://github.com/WikG1018/site-mark（单分支 main 三产品线：Android=Flutter+Rust、鸿蒙=`ohos-native/`、iOS=Flutter 复用+Swift 桥已完成 Phase 0–8 仅剩签名）
- 发版状态：Android Latest = v1.0.27+42；鸿蒙 native-v1.0.13 Pre-release；iOS 无包（等 Apple 账号）
- worktree 清单：`.worktrees/` 下 motion-a/b/c（已合并，可删）、**motion-d（Phase D WIP，勿删）**、handoff（本文档）、其余（android-api37/ios-review/ohos*/release-prep）属其他会话，**不要动**。
- 完整历史交接：`docs/superpowers/handoffs/2026-08-30-ios-adaptation-handoff.md`（iOS 线）；实施计划模板：`docs/superpowers/plans/`。

## 七、建议接手顺序

1. 修 Phase D 三个编译缺陷 → 接线 entrance → 补测试 → PR/CI/合并；
2. 预测返回评估（写结论进本文档同目录）；
3. Phase E：规范文档 + MiSans；
4. 真机验证动效手感（Android 真机 + 鸿蒙真机），按 release-checklist 走发版。
