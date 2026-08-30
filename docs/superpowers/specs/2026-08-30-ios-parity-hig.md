# iOS 功能对齐与 HIG 界面适配设计

> 日期:2026-08-30(用户追加需求)
> 前置:Phase 0–3 已合入(PR #119–#122、#124)
> 需求源:用户 2026-08-30「把 iOS 版本完善到对齐安卓版的功能,界面规范遵循苹果的设计规范」
> 路线:继续 Flutter 复用;在共享 `lib/` 上做**平台自适应**,不重写 iOS 专属 UI

## 现状审计(@ e4a368c)

共享 `lib/` + 完整平台桥(Phase 2b)使 iOS 功能面已对齐 Android 主流程(拍摄/定位/
水印/发布/备份/诊断/设置)。残余差距:

| 项 | Android 现状 | iOS 现状 | 结论 |
| --- | --- | --- | --- |
| 应用图标 | 品牌图标(`tool/generate_launcher_icon.py` 产出) | Flutter 模板默认图标 | **对齐**:品牌 1024 全出血图标入 AppIcon.appiconset(单尺寸声明) |
| 通知授权时机 | 用户打开开关时请求 | 首次发通知时由系统隐式请求 | **对齐**:开关时经 `requestPermissions(alert/badge/sound)` 显式请求 |
| 开关/滑块外观 | Material | Material(与 iOS 惯例不符) | **HIG**:`Switch.adaptive` / `SwitchListTile.adaptive` / `Slider.adaptive` |
| 确认对话框 | Material AlertDialog | Material AlertDialog | **HIG**:iOS 呈现 `CupertinoAlertDialog`(共享 helper,Android 分支逐字节不变) |
| 启动屏 | `?android:colorBackground`(随深色模式) | 固定白色(深色模式闪白) | **对齐**:启动屏背景色随深浅色(`LaunchBackground` colorset) |
| 字体/滚动物理/返回手势 | Material | SF 字体、弹性滚动、边缘返回滑动(Flutter 平台默认已提供) | 已达标,无需改码 |
| 相机体验 | 系统相机 intent | `UIImagePickerController` 桥 | 维持 Phase 2b 既定偏差;自定义取景按设计文档「出现需求后再评估」 |

## 方案

### 1. HIG 组件适配(平台自适应,Android 零变化)

- 判定源:`defaultTargetPlatform`(widget 测试可用 `debugDefaultTargetPlatformOverride` 驱动)。
- 开关/滑块:Flutter `.adaptive` 构造,iOS 呈现 Cupertino 控件,Android 分支与现实现完全一致。
- 对话框:新增 `lib/shared/ui/adaptive_dialog.dart` 的 `showAppDialog`(结构化
  title/content/actions);Android 路径产出与现有调用点相同的 Material 组合
  (取消=TextButton、主操作=FilledButton、破坏性=FilledButton+error 底色);
  iOS 路径产出 `CupertinoAlertDialog` + `CupertinoDialogAction`
  (`isDefaultAction`/`isDestructiveAction` 映射)。屏障点击是否可关闭**沿用各调用点现值**,
  不在本批改变确认语义。
- 迁移范围:标准确认/信息对话框(约 12 处)。内嵌复杂表单、依赖对话框内自定义布局的
  调用点(如重命名项目表单)**保留 Material**,记录为已知偏差,避免无真机验证下的大范围
  交互重排。

### 2. 品牌资产对齐

- `AppIcon.appiconset` 换为 `assets/branding/sitemark-icon.png`(1024×1024 RGB
  全出血、无透明,即 `render_full_icon(1024)` 的产物;Apple 自行套圆角蒙版)。
  Xcode 14+ 单尺寸(1024 universal)声明,CI `flutter build ios` 的 actool 即为编译门禁。
- 图标再生成纪律:`assets/branding/` 由生成器产出;更换品牌视觉时需同步刷新
  `AppIcon.appiconset`(写入 release-checklist)。
- 启动屏:深色模式闪白(固定白色背景)是已知小差异;深浅色自适应背景需手写
  storyboard XML 或 colorset 方案,CI 已验证手写 XML 会被 ibtool 拒绝,且视觉效果
  无本机验证手段——留待真机/模拟器阶段处理(见实施记录)。

### 3. 通知授权流对齐

- `LocalNotificationService.requestPermission` 在 iOS 上调用
  `IOSFlutterLocalNotificationsPlugin.requestPermissions(alert: true, badge: true, sound: true)`,
  返回授权与否;设置页既有「拒绝→SnackBar」路径两端共用。
- Android 路径不变;`DarwinInitializationSettings` 默认值不动(开关时已授权,
  首次展示不会二次弹窗)。

## 非目标(本批不做)

- 不改导航信息架构(大标题导航、页面结构重排)——需真机视觉走查,留待真机阶段。
- 不实现自定义相机(AVCaptureSession)——维持设计文档既定偏差。
- 不申请任何新权限/后台模式;不动 Android/鸿蒙;不引入新依赖。
- 不做 App Store 元数据与上架材料(Phase 4 前置未满足)。

## 验收

- `flutter test` 全量绿(新增用例:通知授权 iOS 调用、对话框 helper 双平台、
  自适应控件 iOS 分支);`flutter analyze` 0 issue;`dart format`(3.44.6)0 diff。
- CI ubuntu `test` + macos `ios` 双绿(含 actool 图标编译)。
- Android 行为零变化:共享界面在 android 平台的 widget 树与改前一致(既有 1020 用例
  无一改动即为证据)。

## 追加(2026-08-30 第二批,Phase 6):iOS 27 视界适配

用户拍板:相机**不需要**完整相机——`UIImagePickerController` 系统桥维持,原「自定义取景待评估」偏差就此转为已接受决策(D-022 同步更新)。导航形态按 iOS 调整,复杂对话框与标准对话框统一,整体遵循 iOS 26/27(Liquid Glass 世代)的设计方向。

| 项 | 方案 |
| --- | --- |
| 导航 | 设置分区页与次级列表/表单页在 iOS 用 `CupertinoSliverNavigationBar`:滚动收拢的大标题 + 毛玻璃导航栏(iOS 26/27 招牌形态);Android 保持现有 `AppBar`。根 Dock 已是 `GlassSurface` 玻璃浮动条,与 Liquid Glass 方向一致,不动 |
| 分段控件 | 6 处 `SegmentedButton` 改自适应:iOS 呈现 `CupertinoSlidingSegmentedControl`(滑动分段,原生形态),Android 不变 |
| 对话框统一 | 剩余 7 处复杂对话框全部走 `buildAdaptiveAlertDialog`:重命名表单/删除项目(内容 widget 直通),搜索建议/恢复预览(宽度按平台收敛,iOS alert 约 270pt),3 处进度(iOS 用 `CupertinoActivityIndicator`) |
| 相机 | 维持系统桥,落档为决策 |

## 追加(2026-08-31 第三批,Phase 7):全界面 iOS 27 走查与修复

用户要求每个界面都符合 iOS 27 风格;对整个 iOS 版本做全面深度审查后修复并完善。审查盘点出的残留非 iOS 形态及处置:

| 项 | 方案 |
| --- | --- |
| 反馈形态 | iOS 全部提示(约 30 处,含撤销/重试动作与排队/延时确认)从 `SnackBar` 迁移 `showAppToast`:iOS 呈现底部浮动玻璃胶囊(`GlassSurface` + Overlay,计时自动消失,带动作文字钮);Material 平台仍走 `ScaffoldMessenger`(行为/测试语义不变) |
| 动作菜单 | 照片操作、项目操作、项目状态筛选 3 处底部弹层迁移 `showAppActionSheet`:iOS 呈现 `CupertinoActionSheet`(居中标题、文字行为主、破坏性红字、可带副标题与选中勾、独立系统取消行);Material 分支保留拖把柄 + ListTile 队列 |
| 导航补全 | 剩余 8 处直连 `AppBar`(项目列表/全部记录/设置 3 个主标签页、项目详情、照片详情双态、拍照表单、项目水印设置)全部接入 `AdaptivePageScaffold` 大标题导航;主标签页搜索框经 `titleWidget` 就地换入导航栏 |
| 转场 | 层级推入(list→detail→form)路由在 iOS 改用 `CupertinoPage`:水平推入 + **边缘滑动返回手势**,Android 保持 Shared Axis |
| 选择控件 | 记录卡多选与备份选择改为 `AdaptiveSelectionMark`:iOS 呈现 Photos 式圆形勾(选中实心/未选空心),Material 保持 Checkbox/CheckboxListTile |
| 转轮清扫 | 20+ 处 `CircularProgressIndicator` 全部迁移 `AdaptiveProgressIndicator`(iOS `CupertinoActivityIndicator`);窄屏日期筛选 `DropdownMenu` 改 `CompactFilterMenu` 与宽栏一致;批量进度条圆角化 |
| 浮钮 | 根 Dock 新建按钮与项目详情拍照钮 iOS 呈玻璃浮钮(`AdaptiveFloatingButton`:圆形/带字胶囊两种,`GlassSurface` + 毛玻璃),Material 保持 FAB |
| 依赖 | 补 `cupertino_icons`(此前 `CupertinoIcons` 字形在任何平台都不渲染) |

验收同第二批:CI 双绿、Android 分支行为零变化(既有用例不改即过)、iOS 关键界面无头真渲染走查确认。

## 追加(2026-08-31 第四批,Phase 8):苹果官方 App 质感

用户要求把 iOS 版本做到视觉与流畅体验如苹果官方 App,不需要用户协助的部分全部先做掉。

| 项 | 方案 |
| --- | --- |
| 深色模式 | 全表面深色走查;修复大标题导航栏不随主题(应用内手选深色时浅色栏压深色内容)——`MaterialApp.builder` 桥接 `CupertinoTheme` 亮度与主色,`bridgeCupertinoTheme` 可测函数 + 双亮度回归用例 |
| 按压语言 | iOS `NoSplash`(去墨水涟漪,按压高亮代替),Android 保持 `InkSparkle` |
| 触感反馈 | 滑动分段控件选中 `selectionClick`(原生分段标准反馈) |
| 动效 | Toast 胶囊退场淡出;连发场景下仅"当前"胶囊可拆除槽位(竞态防护) |
| 键盘 | 全部记录/项目列表拖拽收起搜索键盘(`keyboardDismissBehavior.onDrag`,iOS 惯例) |
| 评估不做 | 下拉刷新(Android 无此交互,单侧加入引入分叉;分页控制器改造风险大于收益) |

验收同前批:CI 双绿、Android 分支行为零变化、无头真渲染深浅双色走查确认。
