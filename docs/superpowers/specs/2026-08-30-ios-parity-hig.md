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
