# HarmonyOS native openLink Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. User has already chosen **inline execution** (no subagents). Steps use checkbox (`- [ ]`) syntax.

**Goal:** 关于页点 GitHub 仓库链接时，用鸿蒙系统浏览器（或可处理 `https` 的 Ability）打开，体验对齐安卓 `url_launcher` 外链。

**Architecture:** 不改 Pigeon，不改 `pigeons/system_api.dart`。在已有 `sitemark.system.ohos` 通道上增加 `openLink`：宿主用 `Want` `ohos.want.action.viewData` + `entity.system.browsable` + `startAbility`。Dart 侧新增 `OhosExternalLinkService`，`app.dart` / `main.dart` 不再注入 `NoopExternalLinkService`。不要 page-level `if (ohos)`。无模拟器浏览器 dump 不得写系统外链已通。

**Tech Stack:** 官方 Flutter 3.44.6 / Dart 3.12.2 跑测试；社区 Flutter-OH 编 HAP；AbilityKit `Want` / `startAbility`；`module.json5` `querySchemes`。

**Predecessor:** [2026-08-19-harmonyos-notifications.md](2026-08-19-harmonyos-notifications.md) 已推 `610f57f`：拍成通知走 NotificationKit。鸿蒙入口外链仍是 `NoopExternalLinkService`。

## Global Constraints

- 不降 `sdk: ^3.12.2`，不改 `version: 1.0.8+23`。
- 不改 `ci.yml` / `release.yml` / `android/` / `pigeons/`，不合 `main`。
- 不要 page-level `if (ohos)`。
- 不实现真相机拍成、ACL、`ohos-arm64`、定位出坐标。
- 无浏览器 dump 不得写系统外链已通。
- 不提交一次性脚本、HAP、`ohos/entry/libs/`、社区 lock、`flutter_*.log`、`tool/ohos/review/`。
- 官方测试搅 lock 后必须 `git checkout -- pubspec.lock`。
- 用户已说提交并继续：本块绿灯后只 add 产品/文档并 `git push origin ohos`。

## File map

- Modify: `test/platform/ohos_platform_services_test.dart` — `openLink` 通道契约。
- Modify: `packages/sitemark_system_api/lib/src/ohos/ohos_system_api.dart` — `openLink()`。
- Modify: `lib/platform/ohos_platform_services.dart` — `OhosExternalLinkService`。
- Modify: `lib/app.dart` — `externalLinkServiceProvider`。
- Modify: `lib/main.dart` — 鸿蒙入口不再覆盖成 no-op。
- Modify: `packages/sitemark_system_api/ohos/src/main/ets/components/plugin/OhosSystemHost.ets` — `openLink`。
- Modify: `ohos/entry/src/main/module.json5` — `querySchemes: ["https", "http"]`。
- Docs: `README.md`、`tool/ohos/full_product_gap.md`、`tool/ohos/product_hap_review.md`。

---

### Task 37: Dart openLink channel and service

**Files:**
- Modify: `test/platform/ohos_platform_services_test.dart`
- Modify: `packages/sitemark_system_api/lib/src/ohos/ohos_system_api.dart`
- Modify: `lib/platform/ohos_platform_services.dart`
- Modify: `lib/app.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: Write the failing tests**

在 `ohos_platform_services_test.dart` 末尾增加：

- `OhosExternalLinkService` 调 `openLink`，参数 `url` 为 `https://github.com/WikG1018/site-mark`，返回 `true`。
- 非 `http`/`https` scheme 不调通道，返回 `false`。
- `OhosSystemApi.openLink` 缺插件映射 `ohos_not_ready`。

- [ ] **Step 2: Run official test to verify RED**

- [x] **Step 3: Implement Dart channel + OhosExternalLinkService + provider**

`OhosSystemApi.openLink(String url)` → `_invoke<bool>('openLink', {'url': url})`。

`OhosExternalLinkService.open`：仅 `http`/`https` 走通道；其它 scheme 返回 `false`。

`externalLinkServiceProvider` 鸿蒙走 `OhosExternalLinkService()`。`main.dart` 去掉 `NoopExternalLinkService` 覆盖（或同样注入 `OhosExternalLinkService`）。

- [x] **Step 4: Run official test to verify GREEN**

---

### Task 38: Native startAbility host

**Files:**
- Modify: `packages/sitemark_system_api/ohos/src/main/ets/components/plugin/OhosSystemHost.ets`
- Modify: `ohos/entry/src/main/module.json5`
- Docs: `README.md`、`tool/ohos/full_product_gap.md`、`tool/ohos/product_hap_review.md`

- [ ] **Step 1: Wire openLink**

`handle` 增加 `case 'openLink'`。宿主：

```ets
const want: Want = {
  action: 'ohos.want.action.viewData',
  entities: ['entity.system.browsable'],
  uri: url,
};
await abilityContext.startAbility(want);
```

非 `http://`/`https://` 返回 `false`。无 Ability 或 `startAbility` 失败返回 `false`。成功 `true`。

`module.json5` 模块级增加 `querySchemes: ["https", "http"]`（NEXT 隐式 Want 必需）。`INTERNET` 已在 `requestPermissions`。

- [ ] **Step 2: Honest docs. No browser dump.**
