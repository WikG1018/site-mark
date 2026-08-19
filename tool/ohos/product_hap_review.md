# 产品 HAP 树 + 模拟器审查（2026-08-19）

Worktree: `.worktrees/ohos`  
Branch: `ohos`（基线 GitHub `v1.0.8` / `847c74b`；远端 `origin/ohos` = `e408878`）  
AVD: `SiteMarkPhone602`（HarmonyOS-6.0.2 phone_all_x86 API 22，hdc **`127.0.0.1:5555`**）

Verdict: **PASS（全量 `lib/main.dart` 未签名 HAP：隐私门 → 新建项目 → 设置 / 关于 → 项目详情 → 拍摄表单；定位/相机权限框已出）**。  
**不是** Android SiteMark v1.0.8 能力对等，**不证明** 相机拍成 / 相册 ACL / `ohos-arm64` 布局。

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
| kernel 门禁 | `SITEMARK_DB_V3` + `SITEMARK_TASK11` |

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
8. 社区 `pub get` 后必须 `restore-official-lock.ps1`，不提交 lock 涎动。
9. 禁止 `ZipFile.CreateFromDirectory` 重打包 HAP（反斜杠条目会变成桌面）。so / 清单只能 in-place zip。
10. 禁止删除整个 `intermediates/flutter`。只删 `kernel_blob.bin` + `.dart_tool/flutter_build`。
11. `shareAcrossIsolates: true` 在 ohos 上会 isolate 重试挂起 → same-isolate `NativeDatabase`。
12. Flutter-OH native-assets hook 会编出 glibc `libsqlite3.so`（`NEEDED libc.so.6`）→ 事后换成 musl OH so（1533928，`NEEDED libc.so`）。
13. `OhosAssetBundle` 不拷 `NativeAssetsManifest.json`；引擎 `native_assets.cc` 读的是这份清单，不是 `native_assets.json`。由 `inject-native-assets-manifest.ps1` 注入 HAP。
14. `NativeDatabase(File)` 构造不 `sqlite3.open` → opener 里显式 `sqlite3.open` + `NativeDatabase.opened`。设备日志：`opened 3.50.2`。

---

## 模拟器步骤与证据

### Task 6–9（仍成立）

1. 非沙箱执行 `tool/ohos/build-product-hap.ps1`。
2. `hdc -t 127.0.0.1:5555 install` 未签名 HAP → `install bundle successfully`。
3. `aa start -a EntryAbility -b io.github.wikg1018.sitemark`。
4. 首次是产品隐私门：`使用前说明` / `同意并继续` 中心约 `628,2326`。
5. `path_provider` 由 `SiteMarkSystemPlugin` 桥到 `filesDir` / `cacheDir` / `tempDir`。
6. 同意后首页：`工程印记` / `项目` / `全部记录` / `设置` / `暂无进行中的项目`。不是审查壳。

### Task 10：新建项目（2026-08-19）

1. FAB `Key('new-project-fab')` 点 `1102,2242`。
2. 创建页填 `Task10Demo`，点保存。
3. 首页 dump 出现项目名 `Task10Demo`。
4. `filesDir` 出现 `sitemark.sqlite` 与 `sitemark_db_open.log`（`enter` / `docs_ok` / `before_open` / `opened 3.50.2` / `after_native`）。

### Task 11：设置 / 通知 / 关于（2026-08-19）

1. Dock「设置」`1045,2560` → 外观 / 数据与备份 / 通知 / 诊断 / 关于。
2. 「通知」页可开，拨开关不崩（no-op，不是系统通知）。
3. 「关于」显示 SiteMark / `1.0.8+23` / `https://github.com/wikg1018/sitemark`。
4. 设备 `sitemark_package_info.log`：`SITEMARK_PKG_INFO getAll 1.0.8 23`（桥成功，不是关于页 fallback）。
5. 点仓库链接：SnackBar「无法打开浏览器」，dump 仍在关于页（`NoopExternalLinkService`）。

卸载会清 userdata，下次会再出隐私门。

### Task 13–15：项目详情 / 拍摄表单 / 权限探测（2026-08-19）

1. 首页空库 → 新建 `Task13Demo` → 点进详情：`Task13Demo` / 进行中 / `0 张照片` / FAB「拍摄」。
2. FAB `1031,2508` → `CaptureFormScreen` 标题「水印内容」；定位卡「为照片记录 GPS（拒绝后仍可拍摄）」；三个 TextInput + 底部「拍摄」。
3. 填写 `Gongdi` / `Xunjian` / `Tance`。
4. 「开启定位」`919,444` → 系统框「允许 SiteMark 访问你的位置？」；「本次使用允许」后定位卡消失，仍在表单。
5. 底部「拍摄」`628,2578` → 系统框「允许 SiteMark 访问你的相机？」。
6. 「允许」后 hilog：`CameraPicker::Pick`，`saveUri file://.../originals/<uuid>.jpg`。未见相机 UI；`files/originals` 空；应用回表单仍 FOREGROUND。**未拍成，未改宿主。**

### Task 17：全部记录空列表（2026-08-19）

1. 底部 Tab「全部记录」约 `628,2501`。
2. dump 标题「全部记录」；空态「暂无记录」/「还没有拍摄记录」。
3. 应用仍 FOREGROUND。不是审查壳。**未拍成，所以列表为空是预期。**

### Task 18：备份选项目（2026-08-19）

1. 设置 → 备份与恢复 → 备份项目。
2. 选项目页列表含 `Task13Demo`，可勾选。
3. **未点恢复**，不宣称 `file_picker` 导入。

### Task 19：`saveArchive` 失败路径（2026-08-19）

1. 勾选 `Task13Demo` 后开始备份；确认框点「不包含原图」。
2. `files/exports` 被创建且目录内无 zip。
3. 宿主 `saveArchive` 仍 `throw new Error('ohos_not_ready')`。
4. 应用回选项目页，未红屏、未回桌面。**未导出备份，未改宿主。**

---

## 官方测试

官方 Flutter `C:\Users\Administrator\Development\flutter`（3.44.6 / Dart 3.12.2）：

- Task 12（2026-08-19 早）：notification / external_link / platform_services / ohos_platform_services / rust_initialization / app_database 全部通过。
- Task 16（2026-08-19 续）：`ohos_platform_services_test` + `rust_initialization_contract_test` + `app_database_test` 再次全部通过（`+44`）。
- Task 20（2026-08-19 记录/备份后）：`ohos_platform_services_test` + `app_database_test` 全部通过（`+43`）。产品代码未改。

不要用社区 Flutter 跑官方测试。不要提交社区 lock。`ohos_platform_services_test` 在无插件环境断言 `ohos_not_ready`，不等于宿主未实现相机，也不等于备份已导出。

---

## 明确不成立的说法

- 不是 Android v1.0.8 能力对等
- 不是 `flutter build hap --release` / 已签名 AGC 产物
- 未拍成照片；定位未出坐标；相册 ACL、系统 picker / 沙箱回退未走通
- 备份 zip 未导出；`saveArchive` / `inspectImage` 仍 `ohos_not_ready`
- 未测 `ohos-arm64` 水印布局对等
- AutoFill 只有 API 24 编译桩
- 通知 / 分享 / 外链是 no-op，不是系统能力
- GitHub Releases 里的 APK 属于 Android 主线

---

## 下一步

Tasks 17–20 文档随本次提交推到 `origin/ohos`。仍不宣称相机拍成 / 备份已导出 / ACL / `ohos-arm64`。用户再说「继续」再开恢复导入或真 `saveArchive`。
