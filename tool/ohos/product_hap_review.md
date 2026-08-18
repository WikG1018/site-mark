# 产品 HAP 树 + 模拟器审查（2026-08-18）

Worktree: `.worktrees/ohos`  
Branch: `ohos`（基线仍是 GitHub `v1.0.8` / `847c74b`，上次已推 `a204981`）  
AVD: `SiteMarkPhone602`（HarmonyOS-6.0.2 phone_all_x86 API 22，hdc `127.0.0.1:15555`，x86_64）

Verdict: **PASS（产品宿主冷启动 + 隐私门审查壳）**。  
**不是** Android SiteMark v1.0.8 全量 Dart 对等，**不证明** 相机 / 相册 ACL / `ohos-arm64` 布局。

---

## 这次接上了什么

产品 `ohos/` 宿主已在仓库工作树里（源码树，不含 `build/` / `oh_modules/`）：

| 项 | 值 |
|---|---|
| bundle | `io.github.wikg1018.sitemark` |
| vendor | `wikg1018` |
| versionName / versionCode | `1.0.8` / `23` |
| Ability | `EntryAbility` + `FlutterAbility` |
| HAP | `ohos/entry/build/default/outputs/default/entry-default-unsigned.hap`（未签名；模拟器可装） |
| 入口 | `--target lib/ohos_review_main.dart` + `--dart-define=SITEMARK_OHOS=true` |
| 平台 | `--target-platform ohos-x64` |

`rust_builder/ohos/build-profile.json5` 去掉了 CMake native，避免 HAP 去编 cargokit（无可用 ohos 链接器）。引擎状态仍见 `engine_status.md`：**degraded**。

官方 `pubspec.yaml` **未降 SDK**，仍是 `sdk: ^3.12.2`。社区编译只用 `tool/ohos/community-overlay/`，`build-product-hap.ps1` 的 `finally` 会还原官方 pubspec / lock / 插件 pubspec。

---

## 为什么不是全量 `lib/main.dart`

社区 CPF-Flutter：`3.27.4` / Dart `3.6.2`。  
官方产品树：`sdk: ^3.12.2` + Dart 3.12 语法与新插件 API。

直接 `pub get` 失败（SDK 约束）。overlay 保留官方依赖后，`skeletonizer >=2.1.2` 仍要 SDK `>=3.7.0`。把运行时依赖降到 3.6 能过 kernel，但产品源码编不过（null-aware-elements、`_` named params、`toARGB32`、`SharePlus`/`ShareParams` 等）。

**没有**改官方 SDK、**没有**改 `ci.yml` / `release.yml` / `android/`、**没有**把产品页面改成 `if (ohos)`。  
最窄可审查路径：Flutter SDK only overlay + `lib/ohos_review_main.dart`（内存同意态，不走 `FilePrivacyConsentStore` / Riverpod / Drift / Rust / 插件）。

---

## 模拟器步骤与证据

1. 社区 `flutter build hap --debug --target-platform ohos-x64 --target lib/ohos_review_main.dart`
2. `hdc install` 未签名 HAP → 成功
3. `aa start -a EntryAbility -b io.github.wikg1018.sitemark` → 成功
4. 旧 empty 包 `com.sitemark.sitemark_ohos_empty` 会抢焦点；`aa force-stop` 后产品 mission `#35` 前台
5. `uitest dumpLayout`（点同意前）文案：
   - `隐私说明`
   - `SiteMark 在本机拍摄、生成水印并保存记录。…同意后才会启动相机、定位和相册相关能力。`
   - `同意并继续` / `退出`
   - Flutter `XComponent` `oh_flutter_1`
6. `uitest uiInput click 628 2326`（「同意并继续」中心）
7. 点后 dumpLayout：
   - bundle `io.github.wikg1018.sitemark` / `EntryAbility`
   - `SiteMark`
   - `鸿蒙审查壳已启动`
   - 边界说明正文（非全量 Dart、degraded、不证明相机/ACL/ohos-arm64）

本地截图 / dump（不作为过审材料）：

- `tool/ohos/review/sitemark_review_product.jpeg`（隐私门，empty 已停）
- `tool/ohos/review/sitemark_review_home.jpeg`（审查首页）
- `tool/ohos/review/sitemark_layout.json` / `sitemark_layout_before_click.json` / `sitemark_layout_home.json`

---

## 明确不成立的说法

- 不是 Android v1.0.8 全量 Dart HAP
- 不是 `flutter build hap --release` / 已签名 AGC 产物
- 未测相机、定位、相册 ACL、系统 picker / 沙箱回退
- 未测 `ohos-arm64` 水印布局对等
- 同意态是内存，杀进程后会再出隐私门
- empty HAP 仍可能装在同一模拟器上，审查前必须确认焦点 bundle

---

## 下一步

见 [2026-08-18-harmonyos-full-product-hap.md](../../docs/superpowers/plans/2026-08-18-harmonyos-full-product-hap.md)。方向已锁定：不降官方 `sdk: ^3.12.2`，用 CPF-Flutter `oh-3.44.9-dev`（Dart 3.12.2）编全量 `lib/main.dart`。真机再谈 ACL / 相机 / `ohos-arm64`。
