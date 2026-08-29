# iOS 适配设计（Flutter 复用路线）

> 日期：2026-08-30
> 基线：origin/main @ `57ad67e`（v1.0.13，Latest）
> 需求源：用户 2026-08-30 提出增加 iOS 版本，并确认走「先设计、再分阶段实施」的路径
> 路径：A — Flutter 复用（`lib/` + `rust/` 全量复用，新增 Swift 系统桥），不做原生重写

## 目标

1. iOS 版作为第三条产品线并入现有 Flutter 工程：同一套 `lib/` UI 与业务逻辑、同一 Rust 核心、同一数据库 schema 与备份格式，行为对齐 Android v1.0.x。
2. 系统桥接面完整对齐 Android：`pigeons/system_api.dart` 的全部 HostApi 方法 + `sitemark/memory_pressure` 通道，每一条都有 Swift 实现与测试。
3. CI 在 GitHub Actions macOS runner 上可构建无签名 iOS 产物并跑 Flutter 全量测试；为 TestFlight 分发预留签名挂点。
4. 平台差异（后台调度、相册删除确认、模糊定位）显式记录在文档与 UI 文案层面，不做静默降级。

## 路线比较（已选 A）

| 路线 | 说明 | 结论 |
|---|---|---|
| A. Flutter 复用 | `lib/` 零重写；新增 `ios/` 平台目录与 Swift 桥（对齐 Android Kotlin 面） | **采用**：iOS 是 Flutter 一级平台，无适配层风险 |
| B. Swift 原生重写 | 复刻鸿蒙 ArkTS 线的做法 | 否：鸿蒙走原生是因为 Flutter 鸿蒙当时只有社区适配层；iOS 上重写意味着数千行重复实现和第三份需要同步维护的 UI |
| C. 引入 KMP 等新技术栈 | 共享原生层 | 否：只增加构建复杂度，不减少任何原生工作量 |

## 现状盘点（@ 57ad67e）

**直接可用（不改）**：

- `lib/` 全部 UI、domain、data、workflow：drift/sqlite3（iOS 系统自带 SQLite）、riverpod、go_router、l10n。
- 三方依赖全部声明支持 iOS：flutter_rust_bridge 2.12、drift 2.34 + drift_flutter、sqlite3 3.4、path_provider、share_plus、package_info_plus、url_launcher、workmanager 0.9（iOS 后端 = BGTaskScheduler）、flutter_local_notifications 22.x、file_picker 12、archive、dynamic_color、animations、skeletonizer、uuid、intl。
- Rust 核心：`rust_builder/ios/` 的 cargokit Pod 集成已就位，Xcode 构建时自动交叉编译 Apple 目标；`rust/` 源码无需改动。

**需要新增的 Swift 实现**：

- `packages/sitemark_system_api` 的 Pigeon HostApi——Android 侧对应面：964 行 Pigeon 生成代码 + 约 770 行手写 Kotlin（`SiteMarkSystemPlugin` / `SafeMediaPublisher` / `PublishJournalStore` / `CaptureContentProvider` / `ArchiveSavePolicy` / `CaptureSessionPolicy` / `CaptureTargetPolicy` / `ImageMetadataReader` / `PublishedImageDeletePolicy`）+ 约 1,100 行 JVM 测试。
- `sitemark/memory_pressure` 通道——Android 侧对应 `MemoryPressurePlugin`（254 行）+ `MemoryPressureReceiver`（179 行）。

## 桥接方法逐条设计

| # | 方法 | Android 现状 | iOS 方案 | 差异记录 |
|---|---|---|---|---|
| 1 | `createCameraTarget` | 应用目录下目标路径 | 沙盒 tmp 目录文件路径 | 无 |
| 2 | `launchCamera` | 系统相机 intent + ActivityResult | `UIImagePickerController(.camera)` 起步；自定义取景需求出现后再评估 `AVCaptureSession` | 需 `NSCameraUsageDescription` |
| 3 | `recoverCameraCapture` | `CaptureContentProvider` 跨进程恢复 | 沙盒 marker 文件 + 启动扫描，语义对齐 | 机制不同、行为一致 |
| 4 | `finishCameraCapture` | 按 `keepOriginal` 清理 | 同语义，沙盒内删除/保留 | 无 |
| 5 | `getLocationPermissionState` | 权限查询 | `CLLocationManager.authorizationStatus` | iOS 精度授权（精确/模糊）一律映射 granted，精确度由定位结果体现 |
| 6 | `requestLocationPermission` | 运行时请求 | `requestWhenInUseAuthorization` + 回调 | 无 |
| 7 | `openApplicationSettings` | 系统设置 intent | `UIApplication.openSettingsURLString` | 无 |
| 8 | `inspectImage` | `ImageMetadataReader`（尺寸/类型/EXIF GPS） | `CGImageSource`：尺寸、UTType、文件大小 + EXIF/GPS 属性 | 无 |
| 9 | `requestCurrentLocation` | FusedProvider 一次性定位（`timeoutMillis`） | `CLLocationManager` 一次性定位 + `CLGeocoder` 逆地理；`timeoutMillis` 驱动超时 | `approximate` 对应 iOS 模糊定位；`servicesDisabled` 对应定位服务总开关 |
| 10 | `publishJpeg` | MediaStore 插入 + journal | `PHPhotoLibrary.performChanges` 创建资产；`localIdentifier` 即 `contentUri` | 需 `NSPhotoLibraryAddUsageDescription`（仅添加权限即可写入） |
| 11 | `recoverPublishJournals` / `clearPublishJournal` | `PublishJournalStore` 文件持久化 | Application Support 下 JSON 原子写；`captureId` 键、`expectedContentUri` 条件清除语义逐条对齐 | 无 |
| 12 | `saveArchive` | SAF 创建文档 | `UIDocumentPickerViewController(forExporting:)` | 无 |
| 13 | `deletePublishedImage` | `ContentResolver` 直接删除 | `PHAsset` fetch + `performChanges(.delete)` | **平台差异：iOS 系统会弹确认框**；不做平台分支，UI 文案统一按「可能弹出系统确认」表述 |
| 14 | `MediaPublishResult.supersededUris` | MediaStore URI 列表 | 上一轮 publish 的 `localIdentifier` 列表（journal 折叠） | 不透明字符串语义一致，Dart 层零改动 |

Pigeon 配置：`pigeons/system_api.dart` 增加 `swiftOut`，生成 Swift 胶水与手写实现同仓库；`tool/verify_*.py` 等门禁同步。

内存压力通道：iOS 无 Android 分级 `onTrimMemory` 广播，用 `DispatchSource.makeMemoryPressureSource`（normal/warning/critical）映射现有三档；`MemoryPressureReceiver` 的系统级广播在 iOS 无等价物，不模拟。

## 后台调度降级设计（最大平台差异）

- Android 现状：workmanager 自定义条件轮询——前台 `conditional_polling_stream` 轮询 + WorkManager 后台补拍处理与清理重试。
- iOS 现实：workmanager 的 iOS 后端是 BGTaskScheduler——系统机会性调度，最小间隔约 15 分钟，不保证执行时机，低电量与用户行为会进一步推迟。
- 方案：
  1. 前台路径两端完全一致（同一段 Dart 轮询代码，行为不变）。
  2. 后台注册 BGProcessingTask（复用 workmanager iOS API），任务体复用同一个 Dart 回调；补拍处理与清理重试的幂等语义原样带到 iOS。
  3. Info.plist 声明 `BGTaskSchedulerPermittedIdentifiers` + background processing mode；不申请 audio/location 等其他后台模式。
  4. 诊断页如实展示 iOS 后台限制；README 与发布说明记录。
- 不做：模拟 Android 的调度节奏；静默推送唤醒（需要服务端，违背离线产品原则）。

## 权限清单（Info.plist）

| Key | 用途 | 说明 |
|---|---|---|
| `NSCameraUsageDescription` | 拍摄水印照片 | 必需 |
| `NSLocationWhenInUseUsageDescription` | 水印定位 | 必需；**禁用** Always/后台定位 |
| `NSPhotoLibraryAddUsageDescription` | `publishJpeg` 写入相册 | 仅添加权限 |
| `NSPhotoLibraryUsageDescription` | `deletePublishedImage` / 相册读取 | 仅在实现删除时声明 |
| `BGTaskSchedulerPermittedIdentifiers` | 后台补拍处理 | 显式 id 列表 |
| 不申请 | 麦克风、蓝牙、本地网络、追踪、通讯录、媒体库完整读权限（非必需部分） | 对齐 Android 禁权限清单的门禁精神 |

## 构建与 CI

- `ci.yml` 新增 `ios` job（macos-15）：rustup 增加 Apple 目标 → `flutter pub get` → `flutter test` → `flutter build ios --no-codesign --release`；产物作为 artifact 留档，不进 GitHub Release。
- iOS 不并入现有 release.yml——发版走独立 checklist 章节，待 TestFlight 打通后再定。
- 签名与 TestFlight：Apple Developer 账号到位后启用（`xcodebuild archive` 或 fastlane；证书与描述文件走 GitHub Secrets，与 Android keystore 同规：**绝不入库**）。

## 风险与缓解

| 风险 | 缓解 |
|---|---|
| 本机 Windows 无法本地构建/调试 iOS | CI macOS runner 是唯一编译门禁；小步 PR，控制单轮迭代成本 |
| BGTaskScheduler 不可靠 | 前台轮询承担主路径；后台仅机会性补拍；诊断页明示 |
| 相册删除系统确认框与 Android 不一致 | 文档与 UI 文案统一，不做平台分支 |
| sqlite3/drift 的 iOS 系统库链接 | Phase 1 的 CI ios job 第一时间验证；不行则引入 `sqlite3_flutter_libs` |
| Rust iOS 交叉编译拖慢 CI | cargokit 增量缓存；必要时仅编真机 target |
| `UIImagePickerController` 取景能力弱于 Android 相机 intent | 先满足"拍到带元数据的原图"；自定义相机作为后续独立设计 |

## 非目标

- 不改 `lib/` 业务逻辑（新增平台判断分支除外）。
- 不动 Android / 鸿蒙两条线的任何现行为与发版节奏。
- 本批次不完成 App Store 上架、审核与签名自动化。
- 不做 macOS / Windows 桌面端。
