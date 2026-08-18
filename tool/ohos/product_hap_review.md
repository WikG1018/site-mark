# 产品 HAP 树 + 模拟器审查（2026-08-18）

Worktree: `.worktrees/ohos`  
Branch: `ohos`（基线 GitHub `v1.0.8` / `847c74b`；文档提交前远端仍是 `821f3d4`）  
AVD: `SiteMarkPhone602`（HarmonyOS-6.0.2 phone_all_x86 API 22，hdc **`127.0.0.1:5555`**；`15555` 常 Offline）

Verdict: **PASS（全量 `lib/main.dart` 未签名 HAP：隐私门 → 真实首页）**。  
**不是** Android SiteMark v1.0.8 能力对等，**不证明** 相机 / 相册 ACL / `ohos-arm64` 布局。

---

## 这次接上了什么

| 项 | 值 |
|---|---|
| bundle | `io.github.wikg1018.sitemark` |
| vendor | `wikg1018` |
| versionName / versionCode | `1.0.8` / `23` |
| Ability | `EntryAbility` + `FlutterAbility` |
| HAP | `ohos/entry/build/default/outputs/default/entry-default-unsigned.hap`（未签名；模拟器可装。`BUILD_EXIT=1` 是调试签名警告，不是编译失败） |
| 入口 | `--target lib/main.dart` + `--dart-define=SITEMARK_OHOS=true` |
| 平台 | `--target-platform ohos-x64` |
| Flutter-OH | 仓库外 `C:\Users\Administrator\Development\flutter-ohos-3.44`，本地 tag `3.44.9-ohos`，Dart 3.12.2 |
| 官方 SDK | `pubspec.yaml` 仍是 `sdk: ^3.12.2`，未降 |

`rust_builder` CMake native 仍关掉。引擎状态见 `engine_status.md`：**degraded**。

社区 3.27.4 overlay **不再**用于产品 HAP。审查壳 `lib/ohos_review_main.dart` 只留对照。

---

## 编译闸门（已过）

1. Flutter-OH `0.0.0-unknown` → 本地 tag `3.44.9-ohos`。
2. 缺 `HOS_SDK_HOME` → `DEVECO_SDK_HOME` / `HOS_SDK_HOME` / `OHOS_SDK_HOME`。
3. `file_picker` 12.0.0 破坏 `result?.files` → 钉死 `12.0.0-beta.7`。
4. AutoFill API 26 vs 本机 API 24 → `tool/ohos/patches/OhosAutoFillHelper.api24.ets` + `ohos/hvigorw.bat`。**不宣称自动填充可用。**
5. ArkTS：禁止匿名对象类型、禁止 `arr[i]` / `str[i]`、禁止 index signature。
6. `Want.parameters` 必须是带**引号键**的 `Record<string, Object>`（`'ability.params.stream'` / `'pushParams'`）。
7. HAP 构建必须**不走沙箱**（否则写不了 Flutter-OH lockfile）。

---

## 模拟器步骤与证据（全量入口）

1. 非沙箱执行 `tool/ohos/build-product-hap.ps1`。
2. `hdc -t 127.0.0.1:5555 install` 未签名 HAP → `install bundle successfully`。
3. `aa start -a EntryAbility -b io.github.wikg1018.sitemark` → FOREGROUND。
4. 首次 dump（`sitemark_layout_full_before.json`）是**产品隐私门**，不是审查壳：
   - `使用前说明`
   - `工程印记离线工作…`
   - `同意并继续` `[84,2242][1172,2410]`（中心 628,2326）
   - `退出`
   - Flutter `XComponent` `oh_flutter_1`
5. 第一次点同意失败：`MissingPluginException` on `plugins.flutter.io/path_provider` / `getApplicationDocumentsDirectory`。
6. `SiteMarkSystemPlugin` 同时挂 `sitemark.system.ohos` 与 `plugins.flutter.io/path_provider`；`OhosSystemHost.resolveAppDirectory` 映射：
   - `getTemporaryDirectory` → `context.tempDir`
   - `getApplicationCacheDirectory` → `context.cacheDir`
   - `getApplicationDocumentsDirectory` / `getApplicationSupportDirectory` → `context.filesDir`
7. 重建安装后再点 628,2326。二次 dump（`sitemark_layout_full_home.json`，41951 字节）文案：
   - `工程印记`
   - `项目`
   - `全部记录`
   - `设置`
   - `暂无项目`
   - `新建项目后即可开始拍摄记录。`
   - **没有** `鸿蒙审查壳已启动`
   - **没有** `使用前说明` / `同意并继续`
8. 截图：`tool/ohos/review/sitemark_full_home.jpeg`。产品 mission `#38` / pid `#3657` FOREGROUND。

---

## 官方测试

官方 Flutter `C:\Users\Administrator\Development\flutter`（3.44.6 / Dart 3.12.2）：

- 全量 `flutter test` 曾 `+1013 -1`：`rust_initialization_contract_test` 要求源码字面量 `RustLib.init()`，不是 tear-off。
- 已改回 `startInitialization: () => RustLib.init()`。
- 复跑该文件：`+1 All tests passed`。

不要用社区 Flutter 跑官方测试。不要提交社区 `pub get` 冲过的 lock。

---

## 明确不成立的说法

- 不是 Android v1.0.8 能力对等
- 不是 `flutter build hap --release` / 已签名 AGC 产物
- 未测相机、定位、相册 ACL、系统 picker / 沙箱回退
- 未测 `ohos-arm64` 水印布局对等
- AutoFill 只有 API 24 编译桩
- 通知 / 分享 / `package_info_plus` 等第三方插件未在模拟器走通
- GitHub Releases 里的 APK 属于 Android 主线

---

## 下一步

见 [2026-08-18-harmonyos-product-runtime.md](../../docs/superpowers/plans/2026-08-18-harmonyos-product-runtime.md)。方向：在已能进首页的全量 HAP 上走通新建项目 / 设置，补缺插件，仍不宣称相机 / ACL / `ohos-arm64`。
