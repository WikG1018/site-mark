# iOS 适配实施计划

> 日期：2026-08-30
> 设计：[`specs/2026-08-30-ios-adaptation-design.md`](../specs/2026-08-30-ios-adaptation-design.md)
> 需求源：用户 2026-08-30 确认按设计推进（Flutter 复用路线）
> 交接：Phase 0–2b 完成后的接替入口见 [`handoffs/2026-08-30-ios-adaptation-handoff.md`](../handoffs/2026-08-30-ios-adaptation-handoff.md)

## Global Constraints

- 全部改动经 PR → CI 绿 → merge commit 合入 `main`；禁止 squash，禁止直接 push `main`。
- Apple 签名材料（.p12、.mobileprovision、密码）绝不入库；走 GitHub Secrets，与 Android keystore 同规。
- Mimosa 门禁：源码改动一律用 Edit 工具（Bash 写源码会被拦）；push 门禁固定扫描 primary 工作树——primary 必须停在同步后的 `main`。
- 每个阶段独立 PR，可独立回滚；测试先于实现（对齐仓库 TDD 惯例）。
- 不改 Android / 鸿蒙现行为；`flutter test` 全量 + `flutter analyze` + `dart format` 全程保持绿。
- 本机是 Windows：所有 iOS 编译验证只发生在 CI macOS runner；任何阶段不允许「本地看起来能过」的判断。

## 阶段划分

### Phase 0 — 设计与计划（本 PR）

新增本文档与设计文档，无代码。验收：PR CI 绿、合并。

### Phase 1 — 平台脚手架 + iOS CI job

让 `flutter build ios --no-codesign` 在 CI 变绿，作为后续一切工作的编译门禁。

1. `flutter create --platforms=ios .` 生成 `ios/`（Runner 工程、AppDelegate、Podfile）；清理到仓库规范（组织标识 `io.github.wikg1018.sitemark`，Display name 与 Android 一致）。
2. Info.plist 写入权限键（见设计文档权限清单；`NSPhotoLibraryUsageDescription` 可延后到 Phase 2b）。
3. Podfile 集成 `rust_builder` Pod（cargokit 自动交叉编译 Rust）；确认 `sqlite3` 系统库链接可用，不行则加 `sqlite3_flutter_libs` 依赖（记入设计文档偏差）。
4. `ci.yml` 增加 `ios` job（macos-15）：rustup `aarch64-apple-ios` + `aarch64-apple-ios-sim` → `flutter pub get` → `flutter build ios --no-codesign --release` + 产物 artifact。全量 Dart/Rust/鸿蒙测试由同一次 PR run 的 ubuntu `test` job 覆盖，iOS job 不重复跑，只做 iOS 编译验证与 Info.plist 元数据校验。（实施修正：原计划在 iOS job 重复 `flutter test`，无增量价值。）
5. `docs/release-checklist.md` 增加「iOS 构建检查」小节（此时只有构建门禁，无发版）。

实施记录（2026-08-30）：Flutter 3.44 的 iOS 模板默认走 Swift Package Manager 混合模式（无 Podfile，CocoaPods 仅用于未迁移 SPM 的插件如 cargokit FFI 桥）；`file-picker-darwin` 要求最低 iOS 14.0，`IPHONEOS_DEPLOYMENT_TARGET` 由 13.0 升至 14.0；`pubspec.lock` 无需任何变更（iOS 集成零依赖增量，flutter create 触发的 Pigeon 27.1.2→27.3.0 漂移已还原）。

验收：ios job 绿（含 Rust 交叉编译 + Flutter 全量测试）；Android / 鸿蒙 job 无回归。

### Phase 2a — Pigeon Swift 桥：纯逻辑层

1. `pigeons/system_api.dart` 增加 `swiftOut`（路径定于 `packages/sitemark_system_api/ios/Classes/SystemApi.g.swift`）；`packages/sitemark_system_api/ios/sitemark_system_api.podspec` 建立。
2. Swift 实现对齐 Android 手写 Kotlin 类清单（每类一个文件，测试对齐 Android JVM 测试面）：
   - `CaptureTargetPolicy` / `CaptureSessionPolicy` / `ArchiveSavePolicy` / `PublishedImageDeletePolicy`（纯函数策略，最先移植）
   - `PublishJournalStore`（Application Support JSON 原子写 + `captureId` 键 + `expectedContentUri` 条件清除）
   - `SafeMediaPublisher` 的 journal 折叠逻辑（PHPhotoLibrary 交互隔离成协议以便测试）
3. XCTest 通过 Swift Package（或 pod test target）在 CI 跑。

验收：CI 绿；策略与 journal 行为有测试覆盖；Pigeon 生成物与手写代码分离清晰。

实施记录（2026-08-30，PR #121）：6 个 Kotlin 类完成对齐移植（4 策略类 + PublishJournalStore + SafeMediaPublisher），新增 `JournalFilePersistence`（Application Support JSON 原子写后端）；XCTest 32/32 在 CI macos-15 通过（SPM `swift test`，含跨实例并发清除回归测试）。Pigeon `swiftOut` 生成物入 drift 检查，dart/kotlin 产物零漂移。两处 CI 修正：SPM 包必须显式声明平台下限（tools-5.9 默认 macOS 10.13 早于抛错版 FileHandle API，声明 macOS 13 / iOS 14）；Swift raw string 里 `\p{Cc}` 只写一层反斜杠（多写会把字面 `p` 拉进字符类，误杀合法文件名）。设计偏差 4 条已在 PR 声明：核心层恢复类型命名 `RecoveredJournalEntry` 避让 Pigeon 生成类型（2b 插件层映射）、iOS 删除允许列表改为 PHAsset localIdentifier 形状校验、Android URI 授权旗标无 iOS 对应物未移植、journal 持久化协议化为 `JournalPersistence`。podspec 已就位但插件平台声明留待 2b，iOS Runner 构建不受影响。

### Phase 2b — Pigeon Swift 桥：系统交互层

1. `SiteMarkSystemPlugin` 全量接线：相机（`UIImagePickerController` + 沙盒 marker 恢复）、定位（`CLLocationManager` 一次性 + `CLGeocoder`，`timeoutMillis` 驱动）、`inspectImage`（`CGImageSource`）、`publishJpeg`（`PHPhotoLibrary` 创建资产）、`saveArchive`（`UIDocumentPickerViewController`）、`deletePublishedImage`（`PHAsset` 删除 + 系统确认差异按设计处理）、`openApplicationSettings`。
2. 内存压力通道：`DispatchSource.makeMemoryPressureSource` 映射三档。
3. `MemoryPressurePlugin`/`MemoryPressureReceiver` 的 Android 语义逐条对照（对齐 `MemoryPressurePluginTest` 的行为面）。
4. Info.plist 补齐 `NSPhotoLibraryUsageDescription` 等剩余权限键。

验收：CI 绿（iOS job 编译 + Flutter 全量测试 + XCTest）；`flutter test` 里 platform-channel 的 mock 层无需改动（Dart 接口不变）。

实施记录（2026-08-30，PR #122）：`IOSSystemApi` 全量接线落地（相机/定位/元数据/发布/存档/删除/设置 + 内存压力通道），插件 pubspec 正式声明 iOS platform + pluginClass，Runner 首次编译完整 pod；XCTest 45/45（新增映射/命名/EXIF fixture/私有目录校验），flutter test 1007 通过、mock 层零改动。设计偏差 3 条已在 PR 声明：定位 `address` 恒为 nil（对齐 Android 现状 + 离线原则，CLGeocoder 不实施）、相机目标目录用 Application Support/originals 而非 tmp（tmp 会被系统清理，破坏崩溃恢复契约）、iOS 授权映射 notDetermined→denied / denied→permanentlyDenied。CI 修复三轮沉淀的平台陷阱：C 级 typealias（`DispatchSourceMemoryPressureEvent` 等）只在 iOS SDK 存在，跨平台文件必须用 Swift 嵌套名 `DispatchSource.MemoryPressureEvent`；内存压力源具体类名各 SDK 不同，用「类型推断局部变量 + 取消闭包」绕开类型标注；存储属性默认值不能引用 `Self`；iOS 上 `PHAsset` 删除经 `deleteAssets` 走系统确认框（全量相册权限下）。

### Phase 3 — Dart 侧接线与平台差异落地

1. workmanager iOS 后台注册：BGProcessingTask 复用同一 Dart 回调；`conditional_polling_stream` 前台路径不动。
2. 诊断页展示 iOS 后台调度限制与权限状态；平台差异文案（相册删除确认）入 l10n。
3. `main.dart` / `bootstrap.dart` 的平台初始化分支审查（通知渠道 id、路径策略在 iOS 上的正确性）。
4. `docs/capture-processing-storage.md` / `docs/current-product-architecture.md` 增补 iOS 平台差异章节。

验收：`flutter test` 全量绿；文档与设计文档一致。

实施记录（2026-08-30，PR #124）：钉死版本插件源码调研发现两处关键事实并据此接线——workmanager_apple 0.9.1+2 **不会**自动注册 BGTaskScheduler handler（`registerLaunchHandlers` 为 0.10+ API，未使用），handler 由 AppDelegate 在 launch 完成前显式 `registerBGProcessingTask(withIdentifier:)`；且 iOS dispatcher 按 **uniqueName** 回传任务名，一次性任务到达时是串行队列名而非 `captureProcessingTask`，原检查会静默忽略全部 iOS 任务。落地为三方精确一致的 identifier `io.github.wikg1018.sitemark.capture-processing`（Dart 常量 ↔ Info.plist ↔ AppDelegate，CI PlistBuddy 门禁 + Dart 漂移测试双保险）；`BackgroundWorkClient.scheduleBackgroundReconcile`（Android no-op / iOS 提交 BGProcessingTaskRequest，前台 initialize 提交、后台任务体消费后再武装）；dispatcher 增加 BG 任务分支（重入队 captured/rendering 走幂等管线）与 uniqueName 识别；`setPluginRegistrantCallback` 补上后台引擎插件注册（否则后台 isolate 的 drift/path_provider/Rust 全部 channel-error）。诊断页新增「平台差异」卡片：后台处理说明 + iOS 专属机会性调度披露（内容分支，用 `defaultTargetPlatform`，不改交互）；相册删除统一「可能弹出系统确认」表述；补模糊定位说明。平台初始化审查结论为无需改码：Darwin 通知初始化已就位且 Android channel 经空安全护栏、Dart 与 Swift 原图/journal 同在 Application Support、`main.dart` 始终注入生产内存压力服务。文档四处更新（两份产品文档 iOS 小节、中英 README 三条产品线表述，iOS 未进任何 Release 下载表）。TDD 先红后绿，新增 13 用例；本地 Flutter 3.44.6 全量 `flutter test` 1020 通过（既有 1007 零回归）、`dart analyze` 0 issue、`dart format` 0 diff；XCTest 45 例未触碰。

### Phase 4 — 分发准备（前置条件：Apple Developer 账号）

1. 用户提供 Apple Developer Program 账号与证书材料后：fastlane 或 `xcodebuild archive` 接入 GitHub Secrets；TestFlight 上传 job。
2. `docs/release-checklist.md` 增补 iOS 发版章节（TestFlight → 真机回归 → App Store 审核）。
3. iOS 发版不并入 Android/鸿蒙的 release.yml；按双先例独立管理。

验收：TestFlight 可安装、真机回归清单建立。未提供账号前本阶段不启动。

### Phase 5 — 功能对齐与 HIG 界面适配（2026-08-30 用户追加）

设计:[`specs/2026-08-30-ios-parity-hig.md`](../specs/2026-08-30-ios-parity-hig.md)。

1. iOS 应用图标换品牌图标(`assets/branding/sitemark-icon.png` 单尺寸 1024)。启动屏深色自适应经 CI 验证手写 storyboard XML 会被 ibtool 拒绝且无本机验证手段,回退并留待真机阶段(见实施记录)。
2. 通知授权流对齐:开关时在 iOS 经 `requestPermissions(alert/badge/sound)` 显式请求(与 Android 时机一致)。
3. HIG 组件自适应:`Switch.adaptive` / `SwitchListTile.adaptive` / `Slider.adaptive`(6 处);`lib/shared/ui/adaptive_dialog.dart` 共享 helper,iOS 呈现 CupertinoAlertDialog,标准确认/信息对话框迁移(约 12 处),复杂表单对话框保留 Material(记录偏差)。
4. 文档:decision-records、NEXT_AGENT_PROMPT 平台边界修正、架构文档 iOS 小节补 UI 惯例。

验收:CI 双绿(含 actool 图标编译);Android 平台 widget 树零变化(既有用例不改即过);深色启动屏真机复核待 Apple 账号/设备阶段补做。

实施记录（2026-08-30，PR #125）：功能对齐面——iOS 应用图标从 Flutter 模板默认图换为品牌图标（`assets/branding/sitemark-icon.png` 1024 全出血单尺寸声明，Xcode 14+ 单尺寸 catalog 经 CI actool 编译验证），删除模板散置 PNG；通知授权时机对齐 Android（开关时经 `IOSFlutterLocalNotificationsPlugin.requestPermissions(alert/badge/sound)` 显式请求，原先首次发通知才隐式弹；`resolvePlatformSpecificImplementation` 依赖平台接口静态 instance + `defaultTargetPlatform`，测试以真实子类 fake 注入并逐用例设平台）。HIG 适配面——`Switch.adaptive`/`SwitchListTile.adaptive`/`Slider.adaptive` 落地 6 处（要点：`Switch.adaptive` 在 iOS 是 Cupertino 风格的 Material 自绘，无 `CupertinoSwitch` 类型；`Slider.adaptive` 则真实构建 `CupertinoSlider`）；新增 `lib/shared/ui/adaptive_dialog.dart`（`showAppDialog` + 供自定义 showDialog 场景的 `buildAdaptiveAlertDialog`），iOS 呈现 `CupertinoAlertDialog`、Android 逐字节复刻原组合，迁移 11 处标准对话框，7 处复杂对话框（重命名表单、删除项目状态化内容、进度 PopScope、搜索列表、恢复预览）保留 Material 记录为偏差；SF 字体/弹性滚动/返回滑动由平台默认提供，核实后无需改码。**CI 修正一轮**：手写启动屏 storyboard（systemBackgroundColor + 移除占位图）被 CI ibtool `CompileStoryboard` 拒绝，本机无 Xcode 无法定位具体行，且深色启动效果本就无法离线验证——整体回退该改动（storyboard 与 LaunchImage 恢复模板原样），深色启动闪白留待真机/模拟器阶段。文档同步：决策 D-022、NEXT_AGENT_PROMPT 移除「不做 iOS」、架构文档界面惯例小节、release-checklist 图标同源纪律。TDD 先红后绿新增 10 用例；本地 Flutter 3.44.6 全量 `flutter test` 1030 通过（既有 1020 零改动）、`dart analyze` 0 issue、`dart format` 0 diff。

## 文件结构（预期新增/修改）

```
ios/                                            # Phase 1（flutter create 生成后清理）
  Runner.xcodeproj / Runner/{Info.plist,AppDelegate.swift,...} / Podfile
packages/sitemark_system_api/ios/               # Phase 2
  sitemark_system_api.podspec
  Classes/SystemApi.g.swift                     # Pigeon 生成
  Classes/{CaptureTargetPolicy,CaptureSessionPolicy,ArchiveSavePolicy,
    PublishedImageDeletePolicy,PublishJournalStore,SafeMediaPublisher,
    ImageMetadataReader,SiteMarkSystemPlugin,MemoryPressurePlugin}.swift
  ...Tests/                                     # XCTest
pigeons/system_api.dart                         # Phase 2：+swiftOut
.github/workflows/ci.yml                        # Phase 1：+ios job
lib/（诊断页、平台分支、l10n 文案）               # Phase 3
docs/{release-checklist,capture-processing-storage,current-product-architecture}.md
docs/superpowers/{specs,plans}/2026-08-30-ios-*.md  # Phase 0（本 PR）
```

## 执行前 worktree

- 分支命名：`feat/ios-adaptation-phase<N>-<slug>`（如 `feat/ios-adaptation-phase1-scaffold`）。
- 每阶段独立 worktree（`.worktrees/ios-phase<N>`），从最新 `origin/main` 切出；primary 工作树保持在 `main`。

## 自检

- [ ] 每个 Phase 的 CI（Android + 鸿蒙 + iOS 三线 job）全绿后才合并。
- [ ] `flutter test` / `flutter analyze` / `dart format` 无回归。
- [ ] Rust 侧零改动（cargokit 自动覆盖）；若被迫改 `rust/`，停下重开设计评审。
- [ ] Info.plist 权限键与设计文档权限清单逐条一致，无多余权限。
- [ ] 平台差异（后台调度、相册删除确认、模糊定位）在诊断页/l10n/文档三处落地。
- [ ] Apple 材料未入库、未进日志、未进 CI 输出。
- [ ] `docs/release-checklist.md` 与实际门禁状态一致。

## 明确不做

- 不在 iOS 上模拟 Android 调度节奏或申请非必需后台模式。
- 不做静默推送/服务端唤醒（违背离线产品原则）。
- 不做 macOS / Windows 桌面端。
- 不在 Phase 0–3 引入新的第三方 Flutter 依赖（`sqlite3_flutter_libs` 是唯一预留例外）。
- 不动 Android / 鸿蒙的现有平台实现与发版流程。
- App Store 上架材料与审核应对不在本计划内（Phase 4 之后另立文档）。
