# iOS 适配实施计划

> 日期：2026-08-30
> 设计：[`specs/2026-08-30-ios-adaptation-design.md`](../specs/2026-08-30-ios-adaptation-design.md)
> 需求源：用户 2026-08-30 确认按设计推进（Flutter 复用路线）

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

### Phase 4 — 分发准备（前置条件：Apple Developer 账号）

1. 用户提供 Apple Developer Program 账号与证书材料后：fastlane 或 `xcodebuild archive` 接入 GitHub Secrets；TestFlight 上传 job。
2. `docs/release-checklist.md` 增补 iOS 发版章节（TestFlight → 真机回归 → App Store 审核）。
3. iOS 发版不并入 Android/鸿蒙的 release.yml；按双先例独立管理。

验收：TestFlight 可安装、真机回归清单建立。未提供账号前本阶段不启动。

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
