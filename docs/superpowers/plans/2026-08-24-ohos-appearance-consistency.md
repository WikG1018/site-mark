# 鸿蒙外观一致性实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `origin/ohos-native` @ `1cb0b8e` 上补齐审查第三批未完成项：外观页独立 9 色主题色、根壳 revision 绑进 `build()`、去掉 overlay/批量栏 blur、年月日筛选抽成 `DateFilterRow`、项目编辑器读同一张 9 色表。

**Architecture:** 路径 B。`AccentSwatches` 是唯一调色盘；`AppearanceSettingsDraft` 保证 seed / accent 互不写入；`Index.build()` 用 `.id(\`chrome-${appearanceRevision}-${motionRevision}\`)` 强制读两个 `@State`；共享 `AccentSwatchRow` / `DateFilterRow`；不把 `UiTokens` 做成 `@Observed`，不改 schema。

**Tech Stack:** HarmonyOS NEXT / ArkTS / Hypium；主机门禁 `tool/ohos-native/run-host-tests.ps1`；debug HAP `tool/ohos-native/build-hap.ps1`（`$MaxArkTsWarnings = 300`）。

**Spec:** [2026-08-24-ohos-appearance-consistency-design.md](../specs/2026-08-24-ohos-appearance-consistency-design.md)

## Global Constraints

- 基线：`origin/ohos-native` @ `1cb0b8e`。业务代码只改鸿蒙 HAP，在 **ohos-native worktree** 里做，不要在当前 Flutter 脏树改 HAP。
- 禁止改 Flutter、禁止改数据库 schema、禁止 ALTER / 迁移历史行、禁止改 SQL 默认 `4281849227`（`0xFF176B55`）。
- 禁止把 `UiTokens` 做成 `@Observed` / `AppStorage`。禁止给每个 `NavDestination` 手写 `@Consume`。禁止点选未保存时调用 `UiTokens.apply`。
- 禁止返工已落地项：M3 `setMessage(isError)`、M4 `maxLines(2)`、M5 视觉 token、M6/A1/A3–A5/H1–H7、保存水印不再写 seed（半截）。
- 9 色顺序与 ARGB 必须与 Flutter `lib/shared/theme/accent_swatches.dart` 完全一致。`defaultArgb()` = `0xFF37C58B`。
- `AccentSwatches.nearest` **必须先匹配历史别名** `{0xFF176B55, 0xFF2E7D61} → 0xFF37C58B`，再对未知色做忽略 alpha 的 RGB 欧氏距离。纯欧氏距离会把旧绿判成青色 `0xFF00838F`，违反 spec。NaN / 非有限回退第一项。
- `label(argb, english)` 未知值返回空串 `''`，不抛。
- 选择器高亮 `nearest(value)`，**load/save 不改写**库内旧值。
- 新建选择器 state 默认 `AccentSwatches.defaultArgb()`，不是改库默认。
- 不抽 `ListChromePolicy`。`AccentSwatchRow` / `DateFilterRow` 放 `shared/AppComponents.ets`。`AppComponents` 不得 import `feature/`。
- Hypium 入口是 `ohos-native/entry/src/test/List.test.ets` 的 `testsuite()`。`ohosTest/.../Ability.test.ets` 是空壳，不要当政策测入口。
- 新测例必须 `import` 并在 `testsuite()` 调用。主机门禁不跑 Hypium；ArkTS 全量走 `build-hap.ps1 -SkipRust -RunTests` 或 DevEco。
- 文案不改：加载失败「设置加载失败，请返回后重试」；保存成功「设置已保存」；保存失败「设置保存失败，请稍后重试」。
- `deltas.md` 必须诚实写「设备验证待补」。不把模拟器冒烟写成真机转正。
- 提交信息英文祈使句（`feat:` / `test:` / `refactor:` / `docs:`）。PR 说明用简体中文。合并用 merge-commit。
- 本计划不改版本号、不签名、不换正式图标、不上远程 CI、不做真机四组。

---

## 文件结构

| 路径 | 职责 | 操作 |
|---|---|---|
| `ohos-native/entry/src/main/ets/shared/AccentSwatches.ets` | 9 色表、历史别名 nearest、label | 新建 |
| `ohos-native/entry/src/test/AccentSwatches.test.ets` | 顺序 / 别名 / NaN / 中英名 | 新建 |
| `ohos-native/entry/src/main/ets/feature/settings/AppearanceSettingsDraft.ets` | seed / accent 互不写入，`toRecord()` 填齐字段 | 新建 |
| `ohos-native/entry/src/test/AppearanceSettingsDraft.test.ets` | 改 seed 不碰 accent | 新建 |
| `ohos-native/entry/src/main/ets/feature/settings/SettingsAccessibility.ets` | Task 3 先实现 9 色与主题色前缀；Task 4 改为 re-export `AccentAccessibility` | 修改 |
| `ohos-native/entry/src/test/SettingsProjectSelection.test.ets` | 5→9；主题色前缀中英/选中态 | 修改 |
| `ohos-native/entry/src/main/ets/feature/projects/ProjectFormPolicy.ets` | `watermarkAccentChoices` 改读 9 色 + nearest 高亮 | 修改 |
| `ohos-native/entry/src/test/ProjectFormPolicy.test.ets` | 9 色标签；历史墨绿高亮绿 | 修改 |
| `ohos-native/entry/src/main/ets/shared/AppComponents.ets` | `AccentSwatchRow`、`DateFilterRow`；`BatchActionBar` 去 blur | 修改 |
| `ohos-native/entry/src/main/ets/feature/settings/SettingsScreens.ets` | 两排 9 点、`@State appSeed`、save 写 `this.appSeed` | 修改 |
| `ohos-native/entry/src/main/ets/pages/Index.ets` | `build()` 读双 revision | 修改 |
| `ohos-native/entry/src/main/ets/feature/records/RecordScreens.ets` | `DateFilterRow`；overlay 两处去 blur | 修改 |
| `ohos-native/entry/src/main/ets/feature/projects/ProjectScreens.ets` | `DateFilterRow`；新建默认 `defaultArgb()`；色点改 `AccentSwatchRow` | 修改 |
| `ohos-native/entry/src/test/List.test.ets` | 注册两个新 test 模块 | 修改 |
| `ohos-native/docs/deltas.md` | 本轮条目 + 设备验证待补 | 修改 |
| `ohos-native/entry/src/test/RecordUiCoordinator.test.ets` | `filterControlHeight() === TOUCH_TARGET` **保持，不改** | 不改 |

不改：`AppDatabase.ets` SQL 默认、`Models.ets` 字段、`UiTokens` 静态模型、`ProjectComponents.ets` 占位 `0xFF176B55`、Flutter、`Ability.test.ets`。

---

## 执行前 worktree

实现必须在 `origin/ohos-native` 的隔离 worktree，不要在当前分支 `agent/journal-key-and-cleanup-observability` 上改 HAP（该树没有 `ohos-native/`）。

```powershell
git fetch origin
git worktree add .worktrees/ohos-appearance-consistency origin/ohos-native
cd .worktrees/ohos-appearance-consistency
git checkout -b feat/ohos-appearance-consistency
```

把本计划与 spec 带进该 worktree（cherry-pick `8c2b6a9` 以及本计划提交，或直接拷贝 `docs/superpowers/` 两份 md）。后续每个 Task 的路径都相对该 worktree 仓库根。

Hypium / HAP 命令一律在仓库根执行：

```powershell
pwsh -File .\tool\ohos-native\run-host-tests.ps1
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
```

Expected host：`HarmonyOS host tests passed`（基线约 34 项）。Expected HAP：Hypium 全绿、`ArkTS warnings within budget: N/300` 且 N ≤ 300。

---

### Task 1: AccentSwatches（含历史别名 nearest）

**Files:**
- Create: `ohos-native/entry/src/main/ets/shared/AccentSwatches.ets`
- Create: `ohos-native/entry/src/test/AccentSwatches.test.ets`
- Modify: `ohos-native/entry/src/test/List.test.ets`

**Interfaces:**
- Consumes: 无
- Produces:
  - `class AccentSwatch { argb: number; id: string }`
  - `AccentSwatches.values(): AccentSwatch[]` — 固定 9 项
  - `AccentSwatches.defaultArgb(): number` — `0xFF37C58B`
  - `AccentSwatches.contains(argb: number): boolean` — 表内精确相等
  - `AccentSwatches.nearest(argb: number): number`
  - `AccentSwatches.label(argb: number, english: boolean): string`
  - `AccentSwatches.toRgbHex(argb: number): string` — `'#RRGGBB'`，供 `WatermarkAccentChoice.color` 使用

- [ ] **Step 1: 写失败测例并注册入口**

创建 `ohos-native/entry/src/test/AccentSwatches.test.ets`：

```ts
import { describe, expect, it } from '@ohos/hypium';
import { AccentSwatch, AccentSwatches } from '../main/ets/shared/AccentSwatches';

export default function accentSwatchesTest(): void {
  describe('AccentSwatches', () => {
    it('exposes nine Flutter-aligned swatches in order with the new green default', 0, () => {
      const values: AccentSwatch[] = AccentSwatches.values();
      expect(values.length).assertEqual(9);
      expect(values.map((row: AccentSwatch): string => row.id).join('|'))
        .assertEqual('green|blue|orange|red|purple|teal|pink|yellow|indigo');
      expect(values.map((row: AccentSwatch): string => row.argb.toString(16).toUpperCase()).join('|'))
        .assertEqual('FF37C58B|FF1565C0|FFEF6C00|FFC62828|FF6A1B9A|FF00838F|FFAD1457|FFF9A825|FF283593');
      expect(values[0].argb).assertEqual(AccentSwatches.defaultArgb());
      expect(AccentSwatches.defaultArgb()).assertEqual(0xFF37C58B);
    });

    it('treats table members as contained and unknown colors as absent', 0, () => {
      expect(AccentSwatches.contains(0xFF37C58B)).assertTrue();
      expect(AccentSwatches.contains(0xFF00838F)).assertTrue();
      expect(AccentSwatches.contains(0xFF176B55)).assertFalse();
      expect(AccentSwatches.contains(0xFF2E7D61)).assertFalse();
    });

    it('maps legacy greens by alias before Euclidean distance so they are not teal', 0, () => {
      expect(AccentSwatches.nearest(0xFF37C58B)).assertEqual(0xFF37C58B);
      expect(AccentSwatches.nearest(0xFF176B55)).assertEqual(0xFF37C58B);
      expect(AccentSwatches.nearest(0xFF2E7D61)).assertEqual(0xFF37C58B);
      expect(AccentSwatches.nearest(0xFF176B55) === 0xFF00838F).assertFalse();
      expect(AccentSwatches.nearest(0xFF2E7D61) === 0xFF00838F).assertFalse();
      expect(AccentSwatches.nearest(Number.NaN)).assertEqual(0xFF37C58B);
      expect(AccentSwatches.nearest(Number.POSITIVE_INFINITY)).assertEqual(0xFF37C58B);
    });

    it('returns distinct bilingual labels and blank for unknown values', 0, () => {
      const chinese: string[] = AccentSwatches.values()
        .map((row: AccentSwatch): string => AccentSwatches.label(row.argb, false));
      const english: string[] = AccentSwatches.values()
        .map((row: AccentSwatch): string => AccentSwatches.label(row.argb, true));
      expect(chinese.join('|')).assertEqual('绿色|蓝色|橙色|红色|紫色|青色|粉色|黄色|靛蓝');
      expect(english.join('|')).assertEqual('Green|Blue|Orange|Red|Purple|Teal|Pink|Yellow|Indigo');
      expect(new Set<string>(chinese).size).assertEqual(9);
      expect(new Set<string>(english).size).assertEqual(9);
      expect(AccentSwatches.label(0xFF176B55, false)).assertEqual('');
      expect(AccentSwatches.label(0xFF2E7D61, true)).assertEqual('');
    });

    it('formats RGB hex without alpha for project choice backgrounds', 0, () => {
      expect(AccentSwatches.toRgbHex(0xFF37C58B)).assertEqual('#37C58B');
      expect(AccentSwatches.toRgbHex(0xFF1565C0)).assertEqual('#1565C0');
    });
  });
}
```

在 `List.test.ets` 现有 import 块末尾（`appSettingsLaunchPolicyTest` 之后）追加：

```ts
import accentSwatchesTest from './AccentSwatches.test';
```

在 `testsuite()` 末尾、`appSettingsLaunchPolicyTest();` 之后追加：

```ts
  accentSwatchesTest();
```

- [ ] **Step 2: 跑测例，确认按预期失败**

Run:

```powershell
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
```

Expected: FAIL，`AccentSwatches` 模块不存在，或 `List.test.ets` 无法解析新 import。

若本机 DevEco 尚未配好、HAP 脚本不能跑：先确认文件已注册，再进入 Step 3；该 Task 结束前必须有一次真正的 Hypium 失败或通过记录。不要把「文件存在」当成测例通过。

- [ ] **Step 3: 最小实现**

创建 `ohos-native/entry/src/main/ets/shared/AccentSwatches.ets`：

```ts
export class AccentSwatch {
  argb: number;
  id: string;

  constructor(argb: number, id: string) {
    this.argb = argb;
    this.id = id;
  }
}

export class AccentSwatches {
  private static readonly SWATCHES: AccentSwatch[] = [
    new AccentSwatch(0xFF37C58B, 'green'),
    new AccentSwatch(0xFF1565C0, 'blue'),
    new AccentSwatch(0xFFEF6C00, 'orange'),
    new AccentSwatch(0xFFC62828, 'red'),
    new AccentSwatch(0xFF6A1B9A, 'purple'),
    new AccentSwatch(0xFF00838F, 'teal'),
    new AccentSwatch(0xFFAD1457, 'pink'),
    new AccentSwatch(0xFFF9A825, 'yellow'),
    new AccentSwatch(0xFF283593, 'indigo')
  ];

  private static readonly LABELS_ZH: string[] = [
    '绿色', '蓝色', '橙色', '红色', '紫色', '青色', '粉色', '黄色', '靛蓝'
  ];

  private static readonly LABELS_EN: string[] = [
    'Green', 'Blue', 'Orange', 'Red', 'Purple', 'Teal', 'Pink', 'Yellow', 'Indigo'
  ];

  private static readonly LEGACY_GREEN: number[] = [0xFF176B55, 0xFF2E7D61];

  static values(): AccentSwatch[] {
    return AccentSwatches.SWATCHES;
  }

  static defaultArgb(): number {
    return AccentSwatches.SWATCHES[0].argb;
  }

  static contains(argb: number): boolean {
    const needle: number = argb >>> 0;
    return AccentSwatches.SWATCHES.some((row: AccentSwatch): boolean => (row.argb >>> 0) === needle);
  }

  static nearest(argb: number): number {
    if (!Number.isFinite(argb)) {
      return AccentSwatches.defaultArgb();
    }
    const needle: number = argb >>> 0;
    for (let i = 0; i < AccentSwatches.LEGACY_GREEN.length; i++) {
      if ((AccentSwatches.LEGACY_GREEN[i] >>> 0) === needle) {
        return AccentSwatches.defaultArgb();
      }
    }
    if (AccentSwatches.contains(needle)) {
      return needle;
    }
    const nr: number = (needle >> 16) & 0xFF;
    const ng: number = (needle >> 8) & 0xFF;
    const nb: number = needle & 0xFF;
    let best: number = AccentSwatches.defaultArgb();
    let bestDist: number = Number.POSITIVE_INFINITY;
    const rows: AccentSwatch[] = AccentSwatches.SWATCHES;
    for (let i = 0; i < rows.length; i++) {
      const value: number = rows[i].argb >>> 0;
      const dr: number = nr - ((value >> 16) & 0xFF);
      const dg: number = ng - ((value >> 8) & 0xFF);
      const db: number = nb - (value & 0xFF);
      const dist: number = dr * dr + dg * dg + db * db;
      if (dist < bestDist) {
        bestDist = dist;
        best = rows[i].argb;
      }
    }
    return best;
  }

  static label(argb: number, english: boolean): string {
    const needle: number = argb >>> 0;
    const rows: AccentSwatch[] = AccentSwatches.SWATCHES;
    for (let i = 0; i < rows.length; i++) {
      if ((rows[i].argb >>> 0) === needle) {
        return english ? AccentSwatches.LABELS_EN[i] : AccentSwatches.LABELS_ZH[i];
      }
    }
    return '';
  }

  static toRgbHex(argb: number): string {
    const rgb: number = (argb >>> 0) & 0xFFFFFF;
    return `#${rgb.toString(16).toUpperCase().padStart(6, '0')}`;
  }
}
```

- [ ] **Step 4: 再跑测例，确认通过**

Run:

```powershell
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
```

Expected: PASS（含新 `AccentSwatches` 描述）。警告 ≤ 300。

- [ ] **Step 5: Commit**

```powershell
git add ohos-native/entry/src/main/ets/shared/AccentSwatches.ets `
  ohos-native/entry/src/test/AccentSwatches.test.ets `
  ohos-native/entry/src/test/List.test.ets
git commit -m "feat: add HarmonyOS accent swatches with legacy green aliases"
```

---

### Task 2: AppearanceSettingsDraft

**Files:**
- Create: `ohos-native/entry/src/main/ets/feature/settings/AppearanceSettingsDraft.ets`
- Create: `ohos-native/entry/src/test/AppearanceSettingsDraft.test.ets`
- Modify: `ohos-native/entry/src/test/List.test.ets`

**Interfaces:**
- Consumes: `AppSettingsRecord` / `AppSettingsInit`（`domain/Models.ets` 现有 9 字段，无 schema 变更）
- Produces:
  - `AppearanceSettingsDraft.fromSettings(value: AppSettingsRecord): AppearanceSettingsDraft`
  - `selectSeed(argb: number): void` — 只改 `appSeed`
  - `selectAccent(argb: number): void` — 只改 `accent`
  - `toRecord(): AppSettingsRecord` — `appSeedColorArgb` 来自 `appSeed`，`defaultWatermarkAccentColorArgb` 来自 `accent`，其余字段原样

`AppSettingsInit` 字段（必须填齐，缺一不可）：

```
themeMode, localeCode, defaultWatermarkPosition, defaultWatermarkOpacity,
defaultWatermarkAccentColorArgb, defaultWatermarkFontScale,
locationPermissionPromptDismissed, completionNotificationsEnabled, appSeedColorArgb
```

- [ ] **Step 1: 写失败测例并注册**

创建 `ohos-native/entry/src/test/AppearanceSettingsDraft.test.ets`：

```ts
import { describe, expect, it } from '@ohos/hypium';
import { AppSettingsRecord } from '../main/ets/domain/Models';
import { AppearanceSettingsDraft } from '../main/ets/feature/settings/AppearanceSettingsDraft';

function sampleSettings(seed: number, accent: number): AppSettingsRecord {
  return new AppSettingsRecord({
    themeMode: 'dark',
    localeCode: 'zh',
    defaultWatermarkPosition: 'bottomLeft',
    defaultWatermarkOpacity: 0.78,
    defaultWatermarkAccentColorArgb: accent,
    defaultWatermarkFontScale: 1.0,
    locationPermissionPromptDismissed: true,
    completionNotificationsEnabled: false,
    appSeedColorArgb: seed
  });
}

export default function appearanceSettingsDraftTest(): void {
  describe('AppearanceSettingsDraft', () => {
    it('loads seed and accent independently from settings', 0, () => {
      const draft = AppearanceSettingsDraft.fromSettings(sampleSettings(0xFF1565C0, 0xFFEF6C00));
      expect(draft.appSeed).assertEqual(0xFF1565C0);
      expect(draft.accent).assertEqual(0xFFEF6C00);
      expect(draft.themeMode).assertEqual('dark');
      expect(draft.localeCode).assertEqual('zh');
    });

    it('changing the seed does not copy or rewrite the watermark accent', 0, () => {
      const draft = AppearanceSettingsDraft.fromSettings(sampleSettings(0xFF37C58B, 0xFFC62828));
      draft.selectSeed(0xFF1565C0);
      expect(draft.appSeed).assertEqual(0xFF1565C0);
      expect(draft.accent).assertEqual(0xFFC62828);
      const record = draft.toRecord();
      expect(record.appSeedColorArgb).assertEqual(0xFF1565C0);
      expect(record.defaultWatermarkAccentColorArgb).assertEqual(0xFFC62828);
    });

    it('changing the accent does not copy or rewrite the app seed', 0, () => {
      const draft = AppearanceSettingsDraft.fromSettings(sampleSettings(0xFF1565C0, 0xFF37C58B));
      draft.selectAccent(0xFFEF6C00);
      expect(draft.appSeed).assertEqual(0xFF1565C0);
      expect(draft.accent).assertEqual(0xFFEF6C00);
      const record = draft.toRecord();
      expect(record.appSeedColorArgb).assertEqual(0xFF1565C0);
      expect(record.defaultWatermarkAccentColorArgb).assertEqual(0xFFEF6C00);
    });

    it('keeps non-color fields intact when emitting a record', 0, () => {
      const draft = AppearanceSettingsDraft.fromSettings(sampleSettings(0xFF37C58B, 0xFF2E7D61));
      const record = draft.toRecord();
      expect(record.themeMode).assertEqual('dark');
      expect(record.localeCode).assertEqual('zh');
      expect(record.defaultWatermarkPosition).assertEqual('bottomLeft');
      expect(record.defaultWatermarkOpacity).assertEqual(0.78);
      expect(record.defaultWatermarkFontScale).assertEqual(1.0);
      expect(record.locationPermissionPromptDismissed).assertTrue();
      expect(record.completionNotificationsEnabled).assertFalse();
      expect(record.defaultWatermarkAccentColorArgb).assertEqual(0xFF2E7D61);
      expect(record.appSeedColorArgb).assertEqual(0xFF37C58B);
    });
  });
}
```

`List.test.ets` 追加：

```ts
import appearanceSettingsDraftTest from './AppearanceSettingsDraft.test';
```

```ts
  appearanceSettingsDraftTest();
```

- [ ] **Step 2: 跑测例，确认失败**

Run:

```powershell
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
```

Expected: FAIL，`AppearanceSettingsDraft` 不存在。

- [ ] **Step 3: 最小实现**

创建 `ohos-native/entry/src/main/ets/feature/settings/AppearanceSettingsDraft.ets`：

```ts
import { AppSettingsRecord } from '../../domain/Models';

export class AppearanceSettingsDraft {
  themeMode: string = 'system';
  localeCode: string = '';
  defaultWatermarkPosition: string = 'bottomLeft';
  defaultWatermarkOpacity: number = 0.78;
  defaultWatermarkFontScale: number = 1.0;
  locationPermissionPromptDismissed: boolean = false;
  completionNotificationsEnabled: boolean = false;
  appSeed: number = 0xFF37C58B;
  accent: number = 0xFF37C58B;

  static fromSettings(value: AppSettingsRecord): AppearanceSettingsDraft {
    const draft = new AppearanceSettingsDraft();
    draft.themeMode = value.themeMode;
    draft.localeCode = value.localeCode;
    draft.defaultWatermarkPosition = value.defaultWatermarkPosition;
    draft.defaultWatermarkOpacity = value.defaultWatermarkOpacity;
    draft.defaultWatermarkFontScale = value.defaultWatermarkFontScale;
    draft.locationPermissionPromptDismissed = value.locationPermissionPromptDismissed;
    draft.completionNotificationsEnabled = value.completionNotificationsEnabled;
    draft.appSeed = value.appSeedColorArgb;
    draft.accent = value.defaultWatermarkAccentColorArgb;
    return draft;
  }

  selectSeed(argb: number): void {
    this.appSeed = argb;
  }

  selectAccent(argb: number): void {
    this.accent = argb;
  }

  toRecord(): AppSettingsRecord {
    return new AppSettingsRecord({
      themeMode: this.themeMode,
      localeCode: this.localeCode,
      defaultWatermarkPosition: this.defaultWatermarkPosition,
      defaultWatermarkOpacity: this.defaultWatermarkOpacity,
      defaultWatermarkAccentColorArgb: this.accent,
      defaultWatermarkFontScale: this.defaultWatermarkFontScale,
      locationPermissionPromptDismissed: this.locationPermissionPromptDismissed,
      completionNotificationsEnabled: this.completionNotificationsEnabled,
      appSeedColorArgb: this.appSeed
    });
  }
}
```

- [ ] **Step 4: 再跑测例，确认通过**

Run:

```powershell
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
```

Expected: PASS。

- [ ] **Step 5: Commit**

```powershell
git add ohos-native/entry/src/main/ets/feature/settings/AppearanceSettingsDraft.ets `
  ohos-native/entry/src/test/AppearanceSettingsDraft.test.ets `
  ohos-native/entry/src/test/List.test.ets
git commit -m "feat: keep appearance seed and watermark accent independent"
```

---

### Task 3: 无障碍与项目 9 色政策

**Files:**
- Modify: `ohos-native/entry/src/main/ets/feature/settings/SettingsAccessibility.ets`
- Modify: `ohos-native/entry/src/test/SettingsProjectSelection.test.ets`
- Modify: `ohos-native/entry/src/main/ets/feature/projects/ProjectFormPolicy.ets`
- Modify: `ohos-native/entry/src/test/ProjectFormPolicy.test.ets`

**Interfaces:**
- Consumes: `AccentSwatches.values()` / `label` / `nearest` / `toRgbHex`
- Produces:
  - `watermarkAccentOptions()` 9 项，色名走 `AccentSwatches.label`（绿色/Green … 靛蓝/Indigo）
  - `themeSeedAccessibilityText(option, selected)`：中文 `{前缀} {色名}，已选择/未选择`，英文 `{prefix} {name}, selected/not selected`，前缀 `应用主题色` / `App theme color`
  - `watermarkAccentChoices(english, selectedValue)` 9 项；`selected` 为 `AccentSwatches.nearest(selectedValue) === swatch.argb`；`color` 仍是 `'#RRGGBB'` 字符串
  - 旧 5 色（`0xFF2E7D61` / `0xFFC05A24` / `0xFF7B4DA8` / `0xFF37474F` 及「墨绿/Forest green」等）退出选择器

`watermarkAccentAccessibilityText` 签名不变，只换数据源。项目页位置钮的 `selectionVisual` 本轮保留。

- [ ] **Step 1: 改失败测例**

`SettingsProjectSelection.test.ets`：

1. import 增加 `themeSeedAccessibilityText`。
2. 把四处 `assertEqual(5)` 改成 `assertEqual(9)`。
3. 在 `provides localized and distinct settings accessibility labels` 里追加：第一项颜色 `0xFF37C58B`；中文标签含「绿色」不含「深绿色」；英文含 `Green` 不含 `Deep green`。
4. 新增测例：

```ts
    it('prefixes theme-seed accessibility text in the active language', 0, () => {
      const option = watermarkAccentOptions()[0];
      AppText.apply('zh', 'en-US');
      const zhOff = themeSeedAccessibilityText(option, false);
      const zhOn = themeSeedAccessibilityText(option, true);
      AppText.apply('en', 'zh-CN');
      const enOff = themeSeedAccessibilityText(option, false);
      const enOn = themeSeedAccessibilityText(option, true);

      expect(zhOff.indexOf('应用主题色') >= 0).assertTrue();
      expect(zhOff.indexOf('绿色') >= 0).assertTrue();
      expect(zhOff.indexOf('未选择') >= 0).assertTrue();
      expect(zhOn.indexOf('已选择') >= 0).assertTrue();
      expect(zhOn === zhOff).assertFalse();
      expect(enOff.indexOf('App theme color') >= 0).assertTrue();
      expect(enOff.indexOf('Green') >= 0).assertTrue();
      expect(enOff.indexOf('not selected') >= 0).assertTrue();
      expect(enOn.indexOf(', selected') >= 0).assertTrue();
      expect(enOn === enOff).assertFalse();
      expect(zhOff === enOff).assertFalse();
      AppText.apply('', 'zh-CN');
    });
```

`ProjectFormPolicy.test.ets` 把 `gives accent presets unique bilingual names and selected state` **整段替换**为：

```ts
    it('gives accent presets unique bilingual names and selected state', 0, () => {
      const chinese = watermarkAccentChoices(false, 0xFF2E7D61);
      const english = watermarkAccentChoices(true, 0xFF1565C0);

      expect(chinese.length).assertEqual(9);
      expect(english.length).assertEqual(9);
      expect(chinese.map((choice): string => choice.label).join('|'))
        .assertEqual('绿色|蓝色|橙色|红色|紫色|青色|粉色|黄色|靛蓝');
      expect(english.map((choice): string => choice.label).join('|'))
        .assertEqual('Green|Blue|Orange|Red|Purple|Teal|Pink|Yellow|Indigo');
      expect(chinese[0].value).assertEqual(0xFF37C58B);
      expect(chinese[0].color).assertEqual('#37C58B');
      expect(chinese[0].selected).assertTrue();
      expect(chinese[5].selected).assertFalse();
      expect(english[1].selected).assertTrue();
      expect(english[1].value).assertEqual(0xFF1565C0);
      expect(chinese[0].accessibilityText.includes('已选择')).assertTrue();
      expect(english[1].accessibilityText.includes('selected')).assertTrue();
    });
```

不要再断言 `墨绿|蓝色|棕橙|紫色|深灰` 或 `Forest green|Blue|Burnt orange|Purple|Charcoal`。

- [ ] **Step 2: 跑测例，确认失败**

Run:

```powershell
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
```

Expected: FAIL，长度仍为 5，标签仍是旧名，`themeSeedAccessibilityText` 未导出。

- [ ] **Step 3: 最小实现**

`SettingsAccessibility.ets`：在文件顶增加 `import { AccentSwatch, AccentSwatches } from '../../shared/AccentSwatches';`。替换 `watermarkAccentOptions`，并新增主题色前缀函数：

```ts
export function watermarkAccentOptions(): WatermarkAccentOption[] {
  return AccentSwatches.values().map((swatch: AccentSwatch): WatermarkAccentOption =>
    new WatermarkAccentOption(
      swatch.argb,
      AccentSwatches.label(swatch.argb, false),
      AccentSwatches.label(swatch.argb, true)));
}

export function themeSeedAccessibilityText(option: WatermarkAccentOption, selected: boolean): string {
  return selected ?
    tr(`应用主题色 ${option.chineseName}，已选择`, `App theme color ${option.englishName}, selected`) :
    tr(`应用主题色 ${option.chineseName}，未选择`, `App theme color ${option.englishName}, not selected`);
}
```

`watermarkAccentAccessibilityText` 保持原实现。

`ProjectFormPolicy.ets`：增加 `import { AccentSwatch, AccentSwatches } from '../../shared/AccentSwatches';`。替换 `watermarkAccentChoices`：

```ts
export function watermarkAccentChoices(english: boolean, selectedValue: number): WatermarkAccentChoice[] {
  const highlighted: number = AccentSwatches.nearest(selectedValue);
  return AccentSwatches.values().map((swatch: AccentSwatch): WatermarkAccentChoice =>
    new WatermarkAccentChoice(
      swatch.argb,
      AccentSwatches.toRgbHex(swatch.argb),
      AccentSwatches.label(swatch.argb, english),
      (swatch.argb >>> 0) === (highlighted >>> 0),
      english));
}
```

- [ ] **Step 4: 再跑测例，确认通过**

Run:

```powershell
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
```

Expected: PASS。`RecordUiCoordinator.test.ets` 里 `filterControlHeight() === UiTokens.TOUCH_TARGET` 仍绿。

- [ ] **Step 5: Commit**

```powershell
git add ohos-native/entry/src/main/ets/feature/settings/SettingsAccessibility.ets `
  ohos-native/entry/src/test/SettingsProjectSelection.test.ets `
  ohos-native/entry/src/main/ets/feature/projects/ProjectFormPolicy.ets `
  ohos-native/entry/src/test/ProjectFormPolicy.test.ets
git commit -m "feat: drive HarmonyOS accent pickers from the nine-color table"
```

---

### Task 4: AccentSwatchRow + 外观页两排独立保存

**Files:**
- Modify: `ohos-native/entry/src/main/ets/shared/AppComponents.ets`
- Modify: `ohos-native/entry/src/main/ets/feature/settings/SettingsScreens.ets`
- Modify: `ohos-native/entry/src/main/ets/feature/projects/ProjectScreens.ets`

**Interfaces:**
- Consumes: `AccentSwatches`、`themeSeedAccessibilityText` / `watermarkAccentAccessibilityText`、`AppearanceSettingsDraft`、`watermarkAccentOptions`
- Produces: 共享 `AccentSwatchRow`；`AppearanceScreen` `@State appSeed`；`save()` 写 `appSeedColorArgb: this.appSeed`（经 Draft）；项目编辑器默认 `AccentSwatches.defaultArgb()`，色点改用 `AccentSwatchRow`（白边 4vp / 未选 1vp）

现状（必须改掉）：

- `AppearanceScreen` 无 `appSeed`；`save()` 仍是 `appSeedColorArgb: this.settings.appSeedColorArgb`
- `@State accent = 0xFF2E7D61`；深色段之后直接「应用语言」
- 水印 5 色 `ForEach(this.accentOptions)`，选中比较是精确相等
- `ProjectSettingsScreen` `@State accent = 0xFF2E7D61`；`colorChoice` 为 48vp + ✓ + TEXT 边框

- [ ] **Step 1: 先把无障碍函数上移到 shared，再写 `AccentSwatchRow`。**

`AppComponents` **不得** import `feature/`。禁止写：

```ts
from '../feature/settings/SettingsAccessibility';
```

把 `WatermarkAccentOption` + `watermarkAccentOptions` + `watermarkAccentAccessibilityText` + `themeSeedAccessibilityText` 放到 `shared/AccentAccessibility.ets`。`SettingsAccessibility.ets` 只 re-export，Settings 测例 import 路径不变。

`AppComponents.ets` 只允许这些 import：

```ts
import { AccentSwatch, AccentSwatches } from './AccentSwatches';
import { themeSeedAccessibilityText, watermarkAccentAccessibilityText, WatermarkAccentOption }
  from './AccentAccessibility';
```

入参：

```ts
@Component
export struct AccentSwatchRow {
  @Prop selectedArgb: number = 0xFF37C58B;
  @Prop enabled: boolean = true;
  @Prop accessibilityKind: string = 'watermark';
  onSelect: (argb: number) => void = (_argb: number): void => {};

  build() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(AccentSwatches.values(), (swatch: AccentSwatch) => {
        Button()
          .width(UiTokens.TOUCH_TARGET)
          .height(UiTokens.TOUCH_TARGET)
          .borderRadius(UiTokens.TOUCH_TARGET / 2)
          .backgroundColor(swatch.argb)
          .border({
            width: AccentSwatches.nearest(this.selectedArgb) === swatch.argb ? 4 : 1,
            color: Color.White
          })
          .margin({ right: 11, bottom: 11 })
          .enabled(this.enabled)
          .accessibilityText(this.swatchText(swatch))
          .onClick((): void => { this.onSelect(swatch.argb); })
      }, (swatch: AccentSwatch): string => swatch.argb.toString())
    }.width('100%')
  }

  private swatchText(swatch: AccentSwatch): string {
    const option = new WatermarkAccentOption(
      swatch.argb,
      AccentSwatches.label(swatch.argb, false),
      AccentSwatches.label(swatch.argb, true));
    const selected: boolean = AccentSwatches.nearest(this.selectedArgb) === swatch.argb;
    if (this.accessibilityKind === 'theme') {
      return themeSeedAccessibilityText(option, selected);
    }
    return watermarkAccentAccessibilityText(option, selected);
  }
}
```

为遵守「AppComponents 不得 import feature」，把 `WatermarkAccentOption` + 两个 accessibility 函数 **上移到** `shared/AccentSwatches.ets` 或新建 `shared/AccentAccessibility.ets`。**采用新建 `shared/AccentAccessibility.ets`**，由 `SettingsAccessibility.ets` re-export，避免 Settings 测例大改 import。

`shared/AccentAccessibility.ets`：

```ts
import { tr } from './AppText';
import { AccentSwatch, AccentSwatches } from './AccentSwatches';

export class WatermarkAccentOption {
  color: number;
  chineseName: string;
  englishName: string;

  constructor(color: number, chineseName: string, englishName: string) {
    this.color = color;
    this.chineseName = chineseName;
    this.englishName = englishName;
  }
}

export function watermarkAccentOptions(): WatermarkAccentOption[] {
  return AccentSwatches.values().map((swatch: AccentSwatch): WatermarkAccentOption =>
    new WatermarkAccentOption(
      swatch.argb,
      AccentSwatches.label(swatch.argb, false),
      AccentSwatches.label(swatch.argb, true)));
}

export function watermarkAccentAccessibilityText(option: WatermarkAccentOption, selected: boolean): string {
  return selected ? tr(`${option.chineseName}，已选择`, `${option.englishName}, selected`) :
    tr(`${option.chineseName}，未选择`, `${option.englishName}, not selected`);
}

export function themeSeedAccessibilityText(option: WatermarkAccentOption, selected: boolean): string {
  return selected ?
    tr(`应用主题色 ${option.chineseName}，已选择`, `App theme color ${option.englishName}, selected`) :
    tr(`应用主题色 ${option.chineseName}，未选择`, `App theme color ${option.englishName}, not selected`);
}
```

然后：

- `SettingsAccessibility.ets` 改为 `export { WatermarkAccentOption, watermarkAccentOptions, watermarkAccentAccessibilityText, themeSeedAccessibilityText } from '../../shared/AccentAccessibility';`，保留 `settingsBackAccessibilityText` 等其余函数。
- `AppComponents.ets` import `AccentAccessibility`（shared→shared）。
- Task 3 若已把函数写在 SettingsAccessibility，本步 **搬文件并保持 re-export**，测例 import 路径不变。

若 Task 3 尚未提交搬迁：本 Task 允许把 Task 3 的函数直接写在 `AccentAccessibility.ets`，SettingsAccessibility 只 re-export。不要两份 9 色表。

- [ ] **Step 2: 编译前用现有测例确认 re-export 仍绿**

Run:

```powershell
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
```

Expected: 若只搬文件、行为不变，Settings/Project 测例仍 PASS。`AccentSwatchRow` 尚未接入页面也可以先提交前再跑一次。

- [ ] **Step 3: 改 AppearanceScreen**

`SettingsScreens.ets` import 增加：

```ts
import { AccentSwatchRow } from '../../shared/AppComponents';
import { AppearanceSettingsDraft } from './AppearanceSettingsDraft';
import { AccentSwatches } from '../../shared/AccentSwatches';
```

删除 `private readonly accentOptions: WatermarkAccentOption[] = watermarkAccentOptions();`（若 ForEach 已换成 `AccentSwatchRow`）。可保留 `watermarkAccentOptions` import 仅当别处仍用；外观页不再 ForEach option。

状态：

```ts
  @State private appSeed: number = AccentSwatches.defaultArgb();
  @State private accent: number = AccentSwatches.defaultArgb();
```

`load()` 在成功写入现有字段处增加：

```ts
      this.appSeed = value.appSeedColorArgb;
      this.accent = value.defaultWatermarkAccentColorArgb;
```

**不要** `nearest` 回写到 state。历史 `0xFF176B55` 保持原值，只靠 `AccentSwatchRow` 高亮绿。

`save()` 把构造 `AppSettingsRecord` 换成 Draft：

```ts
    const draft = AppearanceSettingsDraft.fromSettings(this.settings);
    draft.themeMode = this.theme;
    draft.localeCode = this.locale;
    draft.defaultWatermarkPosition = this.watermarkPosition;
    draft.defaultWatermarkOpacity = this.watermarkOpacity;
    draft.defaultWatermarkFontScale = this.fontScale;
    draft.appSeed = this.appSeed;
    draft.accent = this.accent;
    const value = draft.toRecord();
```

禁止再写 `appSeedColorArgb: this.settings.appSeedColorArgb`。点选：

```ts
onSelect: (argb: number): void => { this.appSeed = argb; }
```

和

```ts
onSelect: (argb: number): void => { this.accent = argb; }
```

**不要**调用 `UiTokens.apply`。

`build()` 在深色 `LifecycleSegment` 之后、「应用语言」之前插入：

```ts
            Text(tr('应用主题色', 'App theme color')).fontSize(16).fontWeight(FontWeight.Bold).width('100%')
            AccentSwatchRow({
              selectedArgb: this.appSeed,
              enabled: !this.loading && !this.saving,
              accessibilityKind: 'theme',
              onSelect: (argb: number): void => { this.appSeed = argb; }
            })
```

水印段底部把 `Row + ForEach(this.accentOptions)` 换成：

```ts
            Text(tr('水印强调色', 'Watermark accent')).fontSize(16).fontWeight(FontWeight.Bold).width('100%')
            AccentSwatchRow({
              selectedArgb: this.accent,
              enabled: !this.loading && !this.saving,
              accessibilityKind: 'watermark',
              onSelect: (argb: number): void => { this.accent = argb; }
            })
```

加载失败 / 保存成功 / 保存失败文案一行都不要改。`loadCoordinator` / `saveCoordinator` / `appearanceActionCoordinator` / `ScreenMessageClock` 继续用。

- [ ] **Step 4: 改项目编辑器默认色与圆点**

`ProjectScreens.ets`：

- import `AccentSwatchRow`、`AccentSwatches`
- `@State private accent: number = AccentSwatches.defaultArgb();`
- 编辑已有项目仍 `this.accent = project.watermarkAccentColorArgb`（不 nearest 改写）
- 把 `ForEach(watermarkAccentChoices(...), colorChoice)` 换成：

```ts
            AccentSwatchRow({
              selectedArgb: this.accent,
              enabled: !this.saving,
              accessibilityKind: 'watermark',
              onSelect: (argb: number): void => { this.accent = argb; }
            })
```

删除仅被色点使用的 `colorChoice` builder。位置钮 `positionChoice` + `selectionVisual` 保留。`watermarkAccentChoices` 政策函数保留给测例，页面可以不再调用。

- [ ] **Step 5: 跑测例 + 静态确认 save 路径**

Run:

```powershell
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
```

Expected: PASS，警告 ≤ 300。

再 grep 确认：

```powershell
git grep -n "this.settings.appSeedColorArgb" -- ohos-native/entry/src/main/ets/feature/settings/SettingsScreens.ets
git grep -n "0xFF2E7D61" -- ohos-native/entry/src/main/ets/feature/settings/SettingsScreens.ets ohos-native/entry/src/main/ets/feature/projects/ProjectScreens.ets
git grep -n "backdropBlur" -- ohos-native/entry/src/main/ets/shared/AppComponents.ets
```

Expected：AppearanceScreen 不再把 seed 写成 `this.settings.appSeedColorArgb`；两页默认 state 不再是 `0xFF2E7D61`。本 Task **还不要**删 BatchActionBar blur（Task 7）。

- [ ] **Step 6: Commit**

```powershell
git add ohos-native/entry/src/main/ets/shared/AccentAccessibility.ets `
  ohos-native/entry/src/main/ets/shared/AppComponents.ets `
  ohos-native/entry/src/main/ets/feature/settings/SettingsAccessibility.ets `
  ohos-native/entry/src/main/ets/feature/settings/SettingsScreens.ets `
  ohos-native/entry/src/main/ets/feature/projects/ProjectScreens.ets
git commit -m "feat: add independent nine-color theme and watermark pickers"
```

---

### Task 5: Index.build() 绑定 appearanceRevision / motionRevision

**Files:**
- Modify: `ohos-native/entry/src/main/ets/pages/Index.ets`

**Interfaces:**
- Consumes: 现有 `@State appearanceRevision`、`@State motionRevision`；`runtimeListener` 在根壳 active 时 `appearanceRevision += 1`；inactive 直接 return（保留）
- Produces: `build()` 读取这两个 `@State`。不新开 listener，不 `@Consume`

现状：`build()`（consent / privacyGate / runtimeError / runtimeReady / Navigation）不读 `appearanceRevision`，无 chrome `.id(...)`。Dock 选中 blur（约 L360–361）与 Dock blur（约 L377–378）已读 `motionRevision`，**不要动**。

本轮不写 ArkUI 树测。验收=源码出现 id 绑定 + 模拟器冒烟（Task 8）。

- [ ] **Step 1: 确认现状不含 chrome id**

```powershell
git grep -n "chrome-\${this.appearanceRevision}" -- ohos-native/entry/src/main/ets/pages/Index.ets
```

Expected: 无匹配。

- [ ] **Step 2: 给 build() 最外层加容器 id**

把 `build()` 五条分支包进一个根 `Column`（不要拆掉现有分支逻辑）：

```ts
  build() {
    Column() {
      if (!this.consentChecked) {
        Column({ space: 14 }) {
          LoadingProgress().width(42).height(42).color(UiTokens.PRIMARY)
          Text(tr('正在准备工程印记…', 'Preparing SiteMark…')).fontSize(14).fontColor(UiTokens.TEXT_SECONDARY)
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor(UiTokens.BACKGROUND)
        .transition(TransitionEffect.opacity(0)
          .animation({ duration: MotionPolicy.duration(UiTokens.MOTION_STANDARD), curve: Curve.EaseOut }))
      } else if (!this.consentAccepted) {
        this.privacyGate()
      } else if (this.runtimeError.length > 0) {
        // 保持现有 runtimeError 分支原文
      } else if (!this.runtimeReady) {
        // 保持现有 runtimeReady 分支原文
      } else {
        Navigation(this.pathStack) {
          this.rootContent()
        }
        .hideTitleBar(true)
        .navDestination(this.pathMap)
        .mode(NavigationMode.Stack)
      }
    }
    .width('100%')
    .height('100%')
    .id(`chrome-${this.appearanceRevision}-${this.motionRevision}`)
  }
```

`runtimeError` / `runtimeReady` 分支请 **复制现有原文**，不要改文案或 retry 逻辑。禁止给每个 `NavDestination` 加 `@Consume`。

- [ ] **Step 3: grep 确认 build 读取双 revision，Dock blur 仍在**

```powershell
git grep -n "chrome-\${this.appearanceRevision}-\${this.motionRevision}" -- ohos-native/entry/src/main/ets/pages/Index.ets
git grep -n "backdropBlur" -- ohos-native/entry/src/main/ets/pages/Index.ets
```

Expected: chrome id 一行；Index 仍有两处 Dock/选中 `backdropBlur`（约 L360–361、L377–378）。

Run:

```powershell
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
```

Expected: PASS，警告 ≤ 300。

- [ ] **Step 4: Commit**

```powershell
git add ohos-native/entry/src/main/ets/pages/Index.ets
git commit -m "fix: rebuild root chrome when appearance or motion revision changes"
```

---

### Task 6: DateFilterRow 归一记录页 / 项目页筛选

**Files:**
- Modify: `ohos-native/entry/src/main/ets/shared/AppComponents.ets`
- Modify: `ohos-native/entry/src/main/ets/feature/records/RecordScreens.ets`
- Modify: `ohos-native/entry/src/main/ets/feature/projects/ProjectScreens.ets`
- Do not modify: `ohos-native/entry/src/test/RecordUiCoordinator.test.ets`（已有 `filterControlHeight() === UiTokens.TOUCH_TARGET`）

**Interfaces:**
- Consumes: `UiTokens.TOUCH_TARGET` / `SURFACE_MUTED` / `OUTLINE_SUBTLE` / `CONTROL_RADIUS`；`tr`
- Produces: `DateFilterRow`（year / month / day / enabled / onChange）。高度写 `UiTokens.TOUCH_TARGET`，**不**从 `AppComponents` import `RecordBatchLayoutPolicy`（避免 shared→feature）。两页统一高度由已有等式测例保证。

现状：记录页 `filterPanel` L553–576 三个 `TextInput` 已 token 化但内联；项目页 `recordFilterPanel` L1016–1060 已用 `filterControlHeight()`。记录页尚未用 `filterControlHeight()`。

- [ ] **Step 1: 确认高度契约测例仍在**

```powershell
git grep -n "filterControlHeight" -- ohos-native/entry/src/test/RecordUiCoordinator.test.ets
```

Expected: L328–329 仍断言等于 `UiTokens.TOUCH_TARGET` 且 `>= 44`。不要改这个文件。

- [ ] **Step 2: 在 AppComponents.ets 追加 DateFilterRow**

`AppComponents.ets` 若尚未 import `tr`，加上 `import { tr } from './AppText';`。

```ts
@Component
export struct DateFilterRow {
  @Prop year: string = '';
  @Prop month: string = '';
  @Prop day: string = '';
  @Prop enabled: boolean = true;
  onChange: (year: string, month: string, day: string) => void =
    (_year: string, _month: string, _day: string): void => {};

  build() {
    Row({ space: 8 }) {
      TextInput({ text: this.year, placeholder: tr('年', 'Year') }).layoutWeight(1)
        .height(UiTokens.TOUCH_TARGET)
        .enabled(this.enabled)
        .type(InputType.Number)
        .backgroundColor(UiTokens.SURFACE_MUTED)
        .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
        .borderRadius(UiTokens.CONTROL_RADIUS)
        .onChange((value: string): void => { this.onChange(value, this.month, this.day); })
      TextInput({ text: this.month, placeholder: tr('月', 'Month') }).layoutWeight(1)
        .height(UiTokens.TOUCH_TARGET)
        .enabled(this.enabled)
        .type(InputType.Number)
        .backgroundColor(UiTokens.SURFACE_MUTED)
        .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
        .borderRadius(UiTokens.CONTROL_RADIUS)
        .onChange((value: string): void => { this.onChange(this.year, value, this.day); })
      TextInput({ text: this.day, placeholder: tr('日', 'Day') }).layoutWeight(1)
        .height(UiTokens.TOUCH_TARGET)
        .enabled(this.enabled)
        .type(InputType.Number)
        .backgroundColor(UiTokens.SURFACE_MUTED)
        .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
        .borderRadius(UiTokens.CONTROL_RADIUS)
        .onChange((value: string): void => { this.onChange(this.year, this.month, value); })
    }.width('100%')
  }
}
```

- [ ] **Step 3: 记录页 / 项目页只留筛选按钮**

`RecordScreens.ets` import 增加 `DateFilterRow`。`filterPanel()` 里三个 `TextInput` 的 `Row` 换成：

```ts
      DateFilterRow({
        year: this.yearText,
        month: this.monthText,
        day: this.dayText,
        enabled: !this.batchBusy,
        onChange: (year: string, month: string, day: string): void => {
          this.yearText = year;
          this.monthText = month;
          this.dayText = day;
          this.markFilterChanged();
        }
      })
```

项目选择 Scroll、「清除日期 / 应用筛选」按钮保留。

`ProjectScreens.ets` import 增加 `DateFilterRow`。`recordFilterPanel()` 里年月日三个输入换成同样的 `DateFilterRow`，`onChange` 写回该页对应的 year/month/day state 并走现有 mark/filter 回调。筛选 / 重置按钮保留。

- [ ] **Step 4: 跑测例并 grep 内联输入是否还在**

Run:

```powershell
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
```

Expected: PASS。`filterControlHeight` 测例仍绿。

```powershell
git grep -n "placeholder: tr('年'" -- ohos-native/entry/src/main/ets/feature/records/RecordScreens.ets ohos-native/entry/src/main/ets/feature/projects/ProjectScreens.ets
```

Expected: 无匹配（占位符只活在 `DateFilterRow`）。

- [ ] **Step 5: Commit**

```powershell
git add ohos-native/entry/src/main/ets/shared/AppComponents.ets `
  ohos-native/entry/src/main/ets/feature/records/RecordScreens.ets `
  ohos-native/entry/src/main/ets/feature/projects/ProjectScreens.ets
git commit -m "refactor: share DateFilterRow across record and project filters"
```

---

### Task 7: 去掉 overlay / 批量栏 blur，保留 Dock

**Files:**
- Modify: `ohos-native/entry/src/main/ets/feature/records/RecordScreens.ets`
- Modify: `ohos-native/entry/src/main/ets/shared/AppComponents.ets`
- Do not modify: `ohos-native/entry/src/main/ets/pages/Index.ets` Dock blur

**Interfaces:**
- Consumes: 无新 API。不抽 `ListChromePolicy`
- Produces: 详情 overlay 重载钮与成片/原图 Row 无 `backdropBlur`；`BatchActionBar` 无 `backdropBlur`；保留 `OVERLAY` / `GLASS_STRONG` 底；Index Dock / 选中态仍 `MotionPolicy.blur()` / `RootShellPolicy.motion(...).dockBlur|selectionBlur`

现状：

- `RecordScreens.ets` 约 L1731：重载钮 `.backdropBlur(MotionPolicy.blur(12))`（底 `GLASS_STRONG`）
- 约 L1750：成片/原图 `Row` `.padding(10).backdropBlur(MotionPolicy.blur(12))`
- `BatchActionBar` 约 L431 `GLASS_STRONG`，L432 `.backdropBlur(MotionPolicy.blur(12))`

- [ ] **Step 1: 删三处 blur，保留底色**

重载钮：删除 `.backdropBlur(MotionPolicy.blur(12))`，保留 height / borderRadius / margin / accessibility / onClick / 现有 background。

成片/原图 Row：`.padding(10).backdropBlur(MotionPolicy.blur(12))` 改成 `.padding(10)`。

`BatchActionBar` 根容器：删除 `.backdropBlur(MotionPolicy.blur(12))`，保留 `.backgroundColor(UiTokens.GLASS_STRONG)`。

若 `RecordScreens.ets` 因此不再使用 `MotionPolicy`，删除未用 import。`AppComponents.ets` 的 `MotionPolicy` 仍给 `panelTransition` 用，不要删。

- [ ] **Step 2: grep 验收 blur 表**

```powershell
git grep -n "backdropBlur" -- ohos-native/entry/src/main/ets/feature/records/RecordScreens.ets
git grep -n "backdropBlur" -- ohos-native/entry/src/main/ets/shared/AppComponents.ets
git grep -n "backdropBlur" -- ohos-native/entry/src/main/ets/pages/Index.ets
```

Expected：

- `RecordScreens.ets`：**零**处 `backdropBlur`
- `AppComponents.ets`：**零**处 `backdropBlur`（`panelTransition` 不是 blur）
- `Index.ets`：仍有 Dock 选中与 Dock 两处

Run:

```powershell
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
```

Expected: PASS，警告 ≤ 300。

- [ ] **Step 3: Commit**

```powershell
git add ohos-native/entry/src/main/ets/feature/records/RecordScreens.ets `
  ohos-native/entry/src/main/ets/shared/AppComponents.ets
git commit -m "fix: drop overlay and batch-bar backdrop blur"
```

---

### Task 8: 门禁、模拟器五项、deltas

**Files:**
- Modify: `ohos-native/docs/deltas.md`
- Verify: `tool/ohos-native/run-host-tests.ps1`、`tool/ohos-native/build-hap.ps1`

**Interfaces:**
- Consumes: 本计划全部前序 Task
- Produces: 主机门禁绿、Hypium 全绿、debug HAP 警告 ≤ 300、模拟器五项冒烟记录、deltas 写「设备验证待补」

- [ ] **Step 1: 主机门禁**

```powershell
pwsh -File .\tool\ohos-native\run-host-tests.ps1
```

Expected: `HarmonyOS host tests passed`。本轮不应需要改 Python/PowerShell 门禁。

- [ ] **Step 2: debug HAP + Hypium**

```powershell
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
```

Expected: Hypium 全绿（条数 > 基线，因新增 AccentSwatches / Draft / 主题色前缀测例）；`ArkTS warnings within budget: N/300` 且 N ≤ 300。禁止为过关把 `$MaxArkTsWarnings` 上调。禁止把 `UiTokens` 改成 `@Observed`。禁止改 `AppDatabase.ets` 默认 `4281849227`。

- [ ] **Step 3: 模拟器五项冒烟（debug HAP）**

若 `hdc list targets` 为 `[Empty]`：**不要假装做过**。跳到 Step 4，deltas 写设备验证待补，并写明本轮未跑模拟器。

若有模拟器：

1. 设置 → 外观：能看到「应用主题色」和「水印强调色」两排 9 点。
2. 只改主题色为蓝、保存：PRIMARY 变蓝；水印默认色不变。返回已打开的记录 / 项目页，按钮 / 强调色跟蓝走（revision 重建生效，不必杀进程）。
3. 只改水印色为橙、保存：主题仍蓝；新建项目水印默认是橙。
4. 记录 / 项目筛选：年月日输入高度、圆角、底色一致。
5. 记录详情媒体 overlay、批量栏：无毛玻璃；Dock 在未开减少动画时仍有。

点选未保存时主题不得立刻全应用换肤。

- [ ] **Step 4: 更新 deltas.md**

在 `ohos-native/docs/deltas.md` 顶部「更新」日期改为当天。在「本轮已确认」追加四条，**不要**删「当前 hdc list targets 为 Empty」这类诚实句；若本轮模拟器五项都过，写「模拟器五项冒烟已过，真机验证待补」。若没跑设备，写：

```
- 外观页独立「应用主题色」与「水印强调色」两排 9 色选择器；seed / accent 分字段保存；历史 0xFF176B55 / 0xFF2E7D61 选择器高亮新绿但不改写库值。
- Index.build() 读取 appearanceRevision / motionRevision，保存主题色后栈内页跟根壳重绘。
- 详情媒体 overlay 与 BatchActionBar 去掉 backdropBlur；Dock / 选中态仍走 MotionPolicy.blur()。
- 记录页与项目页年月日筛选共用 DateFilterRow，高度与 TOUCH_TARGET / filterControlHeight() 对齐。
```

保留：`当前 hdc list targets 为 [Empty]`（若仍为空）或改为模拟器已过、**真机**验证待补。禁止把模拟器写成真机转正。动态取色行保持「不宣称与 Android Monet 完全等价」。

- [ ] **Step 5: Commit**

```powershell
git add ohos-native/docs/deltas.md
git commit -m "docs: record HarmonyOS appearance consistency delta"
```

不要在 deltas 提交里夹带业务代码。

---

## 自检

### Spec coverage

| Spec 项 | Task |
|---|---|
| M1 应用主题色 9 点、与水印互不写入 | Task 2、4 |
| 9 色表与 Flutter 同序同值、`defaultArgb` | Task 1 |
| `nearest` 历史绿→新绿，禁止判成 teal | Task 1 |
| load/save 不改写历史色 | Task 2、4 |
| `watermarkAccentOptions` / `watermarkAccentChoices` 改读 9 色 | Task 3 |
| 主题色前缀无障碍 | Task 3、4（函数最终在 `AccentAccessibility`，Settings 测例仍走 re-export） |
| 项目编辑器同一张表、新建默认新绿、白边 4vp | Task 3、4 |
| M2/A6 `build()` 读双 revision | Task 5 |
| 不 Consume 每页、不新开 listener | Task 5 |
| M5 `DateFilterRow`、高度统一 | Task 6 |
| A2 overlay + BatchActionBar 去 blur，Dock 保留 | Task 7 |
| Hypium + List.test 注册 + HAP 警告 ≤ 300 | Task 1/2/8 |
| 模拟器五项、deltas 设备验证待补 | Task 8 |
| 不改 schema / @Observed / Flutter / SQL 默认 | Global + Task 8 grep |
| 已落地 M3/M4/M5 视觉等禁止返工 | Global |
| 保存文案不改 | Task 4 |

### Placeholder scan

计划内无 TBD / TODO / 「类似 Task N」；命令、路径、代码块均为完整内容。

### Type consistency

- `AccentSwatch.argb` / `id`
- `AppearanceSettingsDraft.appSeed` / `accent` / `fromSettings` / `selectSeed` / `selectAccent` / `toRecord`
- `AccentSwatchRow.selectedArgb` / `enabled` / `accessibilityKind` (`theme` \| `watermark`) / `onSelect`
- `DateFilterRow.year` / `month` / `day` / `enabled` / `onChange`
- `WatermarkAccentOption` 仍是 `color: number`；`WatermarkAccentChoice.color` 仍是 `'#RRGGBB'`
- `themeSeedAccessibilityText(option, selected)`
- chrome id：`` chrome-${this.appearanceRevision}-${this.motionRevision} ``

---

## 明确不做

- 历史行把 `0xFF176B55` / `0xFF2E7D61` UPDATE 成新绿
- 改 `AppDatabase.ets` 三处 `DEFAULT 4281849227`
- 改 `ProjectComponents.ets` 占位项目色
- 把「减少动画」搬进外观页
- 真机四组、签名、正式图标、远程 DevEco CI
- 改 Flutter `accent_swatches.dart`
