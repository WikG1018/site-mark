# iOS 适配交接

> 日期：2026-08-30
> 基线：`origin/main` @ `542a359`（Merge PR #122）
> 产品：SiteMark（https://github.com/WikG1018/site-mark）
> 读者：另一台电脑上的接替 Agent。本文件是唯一交接入口；不要依赖上一会话的聊天记录。

## 一句话现状

iOS 是第三条产品线，走 **Flutter 复用**（`lib/` + `rust/` 全量复用，新增 Swift 系统桥），**不做原生重写**。Phase 0–2b 已全部合入 `main` 且 CI 绿。**下一步是 Phase 3（Dart 侧接线与平台差异落地）**。Phase 4（TestFlight / 签名）在用户提供 Apple Developer 账号之前**不得启动**。

## 权威文档（按此顺序读）

1. 本文件（当前进度、陷阱、Phase 3 具体落点）
2. [`docs/superpowers/specs/2026-08-30-ios-adaptation-design.md`](../specs/2026-08-30-ios-adaptation-design.md) — 路线、14 条桥接方法、后台调度降级、权限清单、非目标
3. [`docs/superpowers/plans/2026-08-30-ios-adaptation.md`](../plans/2026-08-30-ios-adaptation.md) — 分期计划 + 每阶段「实施记录」（含已发生的偏差与 CI 陷阱）
4. [`NEXT_AGENT_PROMPT.md`](../../../NEXT_AGENT_PROMPT.md) — 仓库工作方式（单分支、PR 规范、Mimosa、鸿蒙门禁）
5. [`docs/decision-records.md`](../../decision-records.md)、[`docs/current-product-architecture.md`](../../current-product-architecture.md)

冲突时：用户当前会话的新指令 > 本交接 > 设计规格 > 实施计划 > NEXT_AGENT_PROMPT。

## 仓库与发版快照（交接当日）

| 项 | 值 |
| --- | --- |
| 仓库 | https://github.com/WikG1018/site-mark |
| 默认分支 | `main`（唯一开发分支） |
| HEAD | `542a359` Merge PR #122 |
| Android | `pubspec.yaml` `1.0.13+28`，GitHub Latest = [`v1.0.13`](https://github.com/WikG1018/site-mark/releases/tag/v1.0.13) |
| HarmonyOS | `ohos-native/AppScope/app.json5` `1.0.6` / `1000006`，[`native-v1.0.6`](https://github.com/WikG1018/site-mark/releases/tag/native-v1.0.6) 已转正（未签名 HAP；AGC 证书材料仍待用户提供） |
| iOS 包名 | `io.github.wikg1018.sitemark`（与 Android 同 bundle，Display name `SiteMark`） |
| iOS 最低版本 | 14.0（`file-picker-darwin` 要求；Phase 1 从模板 13.0 升上来） |
| Flutter | 3.44.6 stable |
| 本机能力 | 上一会话在 Windows 上工作，**所有 iOS 编译只发生在 CI macos-15**。接替机若是 Mac，仍必须以 CI 绿为合并条件，不要用「本地看起来能过」替代。 |

相关已合并 PR：

- [#119](https://github.com/WikG1018/site-mark/pull/119) Phase 0 设计 + 计划
- [#120](https://github.com/WikG1018/site-mark/pull/120) Phase 1 `ios/` 脚手架 + CI `ios` job
- [#121](https://github.com/WikG1018/site-mark/pull/121) Phase 2a Swift 纯逻辑核心 + XCTest
- [#122](https://github.com/WikG1018/site-mark/pull/122) Phase 2b 系统交互层（相机/定位/相册/存档/内存压力）

## 已完成（不要重做）

### Phase 0 — 设计

- 路线 A 已选：Flutter 复用。否决 Swift 原生重写、KMP。
- 后台调度最大平台差异已设计：前台 `conditional_polling_stream` 两端一致；后台只注册 BGProcessingTask（机会性，不模拟 Android 节奏）；不做静默推送。

### Phase 1 — 脚手架 + CI

- `ios/` Runner 工程已生成并清理。Flutter 3.44 模板走 **SPM 混合模式，仓库里没有 Podfile**；CocoaPods 只给未迁移 SPM 的插件（`sitemark_core` cargokit 桥、`sitemark_system_api`、`workmanager_apple`）。构建时 Flutter 会警告这些插件尚未 SPM，目前不是错误。
- CI `.github/workflows/ci.yml` 的 `ios` job（macos-15, 60 分钟）：`swift test --package-path packages/sitemark_system_api/ios` → `flutter build ios --no-codesign --release`（3 次重试）→ PlistBuddy 校验 Display name / 版本 / 权限键存在、麦克风与蓝牙键不存在 → 上传 `sitemark-ios-unsigned` artifact。**不重复跑** ubuntu `test` job 已覆盖的 Dart/Rust/鸿蒙矩阵。
- ubuntu `test` job 的 pigeon drift 检查已纳入 `packages/sitemark_system_api/ios/Classes/SystemApi.g.swift`。

### Phase 2a — 纯逻辑核心（SPM 可测，不 import Flutter）

路径：`packages/sitemark_system_api/ios/`

| 文件 | 职责 |
| --- | --- |
| `Classes/CaptureTargetPolicy.swift` | captureId 正则、`.jpg` 命名、空文件 = 取消 |
| `Classes/CaptureSessionPolicy.swift` | 待拍会话键名 + `CaptureStateStore` 协议（同步清除） |
| `Classes/ArchiveSavePolicy.swift` | 私有 ZIP 校验、安全文件名、分块拷贝 |
| `Classes/PublishedImageDeletePolicy.swift` | 只放行 PHAsset `localIdentifier` 形状 `<UUID>/L0/NNN` |
| `Classes/PublishJournalStore.swift` | `journal.<base64url-id>.<field>`；captureId 键控；条件清除；同 capture 重发布折叠；跨实例 `NSLock` |
| `Classes/JournalFilePersistence.swift` | Application Support JSON 原子写 |
| `Classes/SafeMediaPublisher.swift` | 崩溃安全发布顺序；`PublishedImageStore` 协议隔离相册 |
| `Package.swift` | `SiteMarkSystemApiCore` + XCTest；平台下限 **macOS 13 / iOS 14** |
| `sitemark_system_api.podspec` | CocoaPods 插件目标（source_files `Classes/**`） |

SPM target **exclude** 所有 import Flutter 的文件：`SystemApi.g.swift`、`SiteMarkSystemPlugin.swift`、`MemoryPressurePlugin.swift`、`IOSSystemApi.swift`。

### Phase 2b — 系统交互层（已接线，尚未被 Dart 侧差异文案消费）

| 文件 | 职责 |
| --- | --- |
| `Classes/IOSSystemApi.swift` | Pigeon `SiteMarkSystemApi` 全 14 方法的 iOS 实现 |
| `Classes/SiteMarkSystemPlugin.swift` | `FlutterPlugin`：注册 Pigeon host + 内存压力通道 |
| `Classes/MemoryPressurePlugin.swift` | `sitemark/memory_pressure` MethodChannel；DispatchSource WARNING→trim / CRITICAL→kill；`acknowledge` 无操作成功 |
| `Classes/PHPhotoPublishedImageStore.swift` | `PublishedImageStore` 的 PHPhotoLibrary 适配（无 pending 行：创建即完成） |
| `Classes/ImageMetadataReader.swift` | ImageIO：EXIF 旋转换算显示尺寸、GPS 半球、范围校验 |
| `Classes/PrivateStoragePolicy.swift` | 沙盒根包含性校验 |
| `Classes/PublishedImageNamePolicy.swift` | 发布名规范化（**逐字保留** Android `removeSuffix` 大小写怪癖：`capture.JPG` → `capture.JPG.jpg`） |
| `Classes/MemoryPressureLevelMapper.swift` | DispatchSource 事件 → Dart 已有的 `trim` / `kill` 字符串 |

插件已在 `packages/sitemark_system_api/pubspec.yaml` 声明 `ios: pluginClass: SiteMarkSystemPlugin`，`flutter build ios` 会编进 Runner。

Info.plist 已有：`NSCameraUsageDescription`、`NSLocationWhenInUseUsageDescription`、`NSPhotoLibraryAddUsageDescription`、`NSPhotoLibraryUsageDescription`。**尚未**声明 `BGTaskSchedulerPermittedIdentifiers` / `UIBackgroundModes` processing——这是 Phase 3 的活。

## 已声明的设计偏差（不要回退）

写在计划文档实施记录和 PR #121 / #122 正文，接替时视为已接受：

1. **定位 `address` 恒为 nil。** Android `toPigeonResult` 本来就不填逆地理；`CLGeocoder` 依赖网络，违背离线产品原则。设计文档第 9 行的 CLGeocoder **不实施**。
2. **相机目标目录是 Application Support/originals，不是 tmp。** tmp 会被系统清理，破坏 `recoverCameraCapture` 的崩溃恢复契约；与 Dart `OriginalPhotoPaths` 一致。
3. **iOS 定位授权映射：** `notDetermined` → `denied`（Dart 走请求路径）；`denied` / `restricted` → `permanentlyDenied`（只能去设置页）。iOS 没有 Android 的 rationale 信号。
4. **相册删除允许列表**校验 PHAsset `localIdentifier` 形状，不是 Android 的 MediaStore authority + `Pictures/SiteMark/` 相对路径。精神相同：只放行系统媒体提供方签发的标识。
5. **核心层恢复类型**叫 `RecoveredJournalEntry`，Pigeon 生成物叫 `RecoveredPublishJournal`；`IOSSystemApi.recoverPublishJournals` 做映射。不要让核心层 import Flutter。
6. **journal 持久化**抽象为 `JournalPersistence`（snapshot / commit），生产后端是 JSON 文件，测试注入内存替身。
7. **Android URI 授权旗标**（`FLAG_GRANT_READ/WRITE_URI_PERMISSION`）无 iOS 对应物，未移植。`CaptureContentProvider` 整类无 iOS 对应物（相机交接机制不同）。
8. **PHAsset 无法强制写入 display name**（库自命名）。SafeMediaPublisher 仍接收规范化后的名字，但相册里的文件名由系统决定。
9. **内存压力 `acknowledge` 是无操作成功。** Android 的 Binder / `goAsync()` PendingResult / 6s 超时 / 同 level 顶替，全部是 OEM 契约，iOS 无等价物，按设计不模拟。Flutter 自己的 `didHaveMemoryPressure` 走现有 Dart `system` 档，原生不必转发。

## CI 与 Swift 陷阱（踩过，写进计划文档了）

1. **SPM 包必须显式声明平台下限。** tools-5.9 默认 macOS 10.13，早于抛错版 `FileHandle.read(upToCount:)` / `close()`（10.15.4+）。当前：`platforms: [.macOS(.v13), .iOS(.v14)]`。
2. **Swift raw string 里 `\p{Cc}` 只写一层反斜杠。** `#"[\\p{Cc}...]"` 会把字面 `p` 拉进字符类，误杀 `sitemark-backup-123.zip`。正确：`#"[\p{Cc}/\\:*?"<>|]"#`。
3. **C 级 typealias 只在 iOS SDK 存在。** `DispatchSourceMemoryPressureEvent` 在 macOS `swift test` 里找不到。跨平台文件必须用 Swift 嵌套名 `DispatchSource.MemoryPressureEvent`。
4. **内存压力源的具体类名各 SDK 不同。** 不要给它写存储属性类型。用「类型推断的局部变量 + 取消闭包」：`let source = DispatchSource.makeMemoryPressureSource(...); cancelSource = { source.cancel() }`。
5. **存储属性默认值不能引用 `Self`。** 写成 `IOSSystemApi.defaultLocationTimeoutMillis`，不要 `Self.defaultLocationTimeoutMillis`。
6. **pigeon 重新生成后必须 `dart format` 生成的 `.g.dart`**，否则 CI drift 检查会把格式差异当成漂移。dart / kotlin 产物必须逐字节不变；只允许新增 `SystemApi.g.swift`。
7. **关于页测试钉死版本字符串。** `test/features/settings/sections/about_section_screen_test.dart` 里有硬编码的 `1.0.13+28`。发版 bump 时必须同步（`docs/release-checklist.md` 第一节已写）。本阶段不发版，不要动它。
8. **Mimosa：** 源码用 Edit 工具写（Bash 写源码会被拦）。push 门禁扫描的是**会话 primary 工作树**，与命令 cwd 无关——开工前把 primary 停在同步后的 `main`。扫描器会误报 `oh_modules/` 里的 `@ohos/hypium`（gitignored 第三方测试框架），忽略即可。
9. **`gh pr merge --delete-branch` 会把当前 worktree 切回默认分支。** 在 worktree 里继续干活前先 `git branch --show-current`。Windows 上 `git worktree remove` 经常因为长路径 / 文件占用失败，回退 `rm -rf` + `git worktree prune`。
10. **合并用 merge commit，禁止 squash，禁止直接 push `main`。**

## 下一步：Phase 3（接替 Agent 从这里开工）

计划原文四条，落地时按这个拆：

### 3.1 workmanager iOS 后台注册

- 入口：[`lib/background/capture_background_scheduler.dart`](../../../lib/background/capture_background_scheduler.dart)。`WorkmanagerBackgroundWorkClient.initialize` 目前是无条件 `_workmanager.initialize(dispatcher)`；iOS 需要额外注册 BGProcessingTask。
- 查 `workmanager` 0.9.0+3 / `workmanager_apple` 0.9.1+2 的 iOS API（`registerBGProcessingTask` 或 Info.plist identifier 约定），**不要升级插件版本**（计划明确 Phase 0–3 不引入新第三方依赖；现有 workmanager 已声明支持 iOS）。
- Info.plist 增加：
  - `BGTaskSchedulerPermittedIdentifiers`：与 workmanager 要求的 identifier 一致（先读插件文档/源码再写，不要猜）
  - `UIBackgroundModes` → `processing`（只要这一个；不要 audio / location / fetch）
- 前台路径 [`lib/data/conditional_polling_stream.dart`](../../../lib/data/conditional_polling_stream.dart) **不动**。
- 后台只是机会性补拍 + 启动 `reconcilePending()`。不要尝试复现 Android 的「拍完立刻串行处理」。

### 3.2 诊断页 + l10n 平台差异文案

- 诊断页：[`lib/features/settings/sections/diagnostics_section_screen.dart`](../../../lib/features/settings/sections/diagnostics_section_screen.dart)
- 文案：[`lib/l10n/app_strings.dart`](../../../lib/l10n/app_strings.dart)（中英必须同步）
- 必须落地的差异（设计文档 + 计划自检第 3 条）：
  - iOS 后台调度是机会性的，不保证拍完立刻处理；诊断页如实展示，不要装成 Android
  - 相册删除会弹出系统确认框（`PHAssetChangeRequest.deleteAssets`）；UI 文案统一按「可能弹出系统确认」表述，**不要做 `Platform.isIOS` 分支改交互**
  - 模糊定位：`LocationOutcome.approximate` 已由 `accuracyAuthorization` 映射，文案如需区分精确/模糊就在这里加，不要改桥

### 3.3 平台初始化审查

- [`lib/main.dart`](../../../lib/main.dart)、bootstrap / `lib/app.dart`
- 通知：`flutter_local_notifications` 的 Darwin 初始化（`DarwinInitializationSettings`）；iOS 不需要 Android 的 notification channel id
- 路径：确认 `path_provider` 的 Application Support 在 iOS 上就是 `IOSSystemApi` 写 originals / journal 的那个目录
- `PlatformMemoryPressureService` 已按通道名工作，iOS 插件会发 `trim`/`kill`；`system` 档继续走 Flutter `didHaveMemoryPressure`。审查 `MyApp` 是否在 iOS 上也注入了生产实现（默认 provider 是 `NoopMemoryPressureService`）

### 3.4 文档

- [`docs/capture-processing-storage.md`](../../capture-processing-storage.md)
- [`docs/current-product-architecture.md`](../../current-product-architecture.md)
- 如有新的平台差异，先更新文档再写代码（对齐鸿蒙 `ohos-native/docs/deltas.md` 的纪律）。iOS 目前没有独立 deltas 文件；Phase 3 可以把差异写进上述两份文档的新小节，不必新开一份 unless 差异表变长。
- README 仍写「两条产品线」。Phase 3 完成后把 iOS 写成第三条（中英 README 必须同步），但**不要**把 iOS 放进 GitHub Release 下载表——还没有签名包。
- 计划文档 Phase 3 节补「实施记录」，格式照抄 Phase 1/2a/2b。

### Phase 3 验收

- ubuntu `test` job + macos `ios` job 双绿
- `flutter test` / `flutter analyze` / `dart format` 无回归
- XCTest 45 个既有用例保持绿（只加、不改 2a/2b 语义）
- Info.plist 权限键与设计文档清单逐条一致，无麦克风 / 蓝牙 / Always 定位 / 完整媒体库读权限
- Apple 材料未入库

### Phase 3 明确不做

- 不改 `lib/` 业务状态机、数据库 schema、Rust
- 不动 Android / 鸿蒙现行为与发版节奏
- 不申请非 processing 的后台模式
- 不引入新的 Flutter 依赖（`sqlite3_flutter_libs` 是唯一预留例外，Phase 1 已确认系统 SQLite 够用，不要加）
- 不开始 Phase 4

## Phase 4（不要做，直到用户给账号）

前置：Apple Developer Program（$99/年）+ 证书 / 描述文件。材料走 GitHub Secrets，与 Android keystore 同规，**绝不入库**。iOS 发版不并入 `release.yml`（该工作流只匹配 `v*` 标签、只出 Android APK）。真机回归清单建立后再谈 App Store。

## 开工清单（复制即用）

```
# 1. primary 工作树必须在同步后的 main（Mimosa push 门禁扫这里）
git fetch origin main && git checkout main && git pull --ff-only

# 2. 独立 worktree，不要在 primary 上开发
git worktree add .worktrees/ios-phase3 -b feat/ios-adaptation-phase3-dart-wiring origin/main

# 3. 先读
#    docs/superpowers/handoffs/2026-08-30-ios-adaptation-handoff.md
#    docs/superpowers/plans/2026-08-30-ios-adaptation.md（Phase 3 节 + 2b 实施记录）
#    lib/background/capture_background_scheduler.dart
#    ios/Runner/Info.plist

# 4. TDD：先写失败测试（诊断页文案、Info.plist 键、workmanager 初始化在 iOS 上的调用）再实现

# 5. 本地（任何 OS）
dart format --output=none --set-exit-if-changed lib test pigeons packages/sitemark_system_api/lib
flutter analyze
flutter test

# 6. iOS 编译只信 CI macos-15。Mac 上可以预跑，但不能替代 CI。

# 7. PR → CI 双 job 绿 → gh pr merge --merge（不要 --squash）
#    合并后在计划文档追加 Phase 3 实施记录（可同 PR 或紧随的 docs commit）
```

分支名：`feat/ios-adaptation-phase3-dart-wiring`。PR 标题建议：`feat(ios): wire Dart-side iOS differences (BGTaskScheduler, diagnostics, l10n)`。

## 用户侧未决事项（Agent 不要催、不要绕过）

- Apple Developer 账号与证书 — Phase 4 硬门槛
- HarmonyOS AGC 签名材料（`.cer` / `.p7b` / `.p12` + 别名 + 密码）— 与 iOS 无关，但发版仍缺签名 HAP
- v1.0.13 / native-v1.0.6 的真机回归 — 用户已要求「发版并标记为最新」，已经转正；增量真机回归仍建议补做，不阻塞 Phase 3
- 仓库 `.worktrees/` 下仍有一批遗留目录（`ohos-polish-*` 等），远端分支已删；用户未要求清理，不要主动删

## 联系点

产品决策（要不要申请某个后台模式、要不要上架、文案语气）问用户。技术实现按设计文档 + 本交接推进，偏差写入计划文档实施记录，不要静默改语义。
