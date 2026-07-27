# 主题色扩展设计

> 日期：2026-07-27
> 目标：把应用主题色从硬编码扩展为用户可选的 9 种，同步扩展水印强调色到 9 种，并消除项目水印页的重复颜色选择器代码。

## 背景与现状

项目当前存在两套独立的"颜色"概念：

1. **应用主题种子色**：硬编码在 `lib/app.dart` 第 583、589 行（Light `0xFF176B55` / Dark `0xFF37C58B`），由 `ColorScheme.fromSeed` 生成全局 Material 3 调色板。**不持久化、不可选**。
2. **水印强调色**：3 种（绿/蓝/橙），用于水印卡片左侧 3px 边框。持久化在 `app_settings.defaultWatermarkAccentColorArgb`（全局默认）和 `projects.watermarkAccentColorArgb`（项目级覆盖）。

水印色选择器在两处重复实现：
- `lib/features/settings/sections/watermark_defaults_section_screen.dart`（全局默认，复用 `accentSwatches` 常量）
- `lib/features/projects/project_watermark_settings_screen.dart` 第 191-214 行（项目级，**硬编码三段 `_AccentChoice`，未复用 `accentSwatches`**）

## 目标

1. 新增"应用主题色"选项，9 种颜色，用户在「外观」设置里选择，影响整个 App 的 ColorScheme。
2. 把水印强调色从 3 种扩展到 9 种。
3. 消除项目水印页的重复代码，合并为共享 `accentSwatches` 常量 + 共享 `_AccentChoice` widget。
4. Light/Dark 主题共用用户选的种子色，由 `ColorScheme.fromSeed(seedColor, brightness)` 自动生成调色板。
5. 老用户升级无破坏，默认种子色保持绿色视觉。

## 颜色定义

9 种共享 swatch（应用种子色和水印色共用同一列表）：

| 名称 | ARGB | Key | 状态 |
|---|---|---|---|
| 绿色 | `0xff37c58b` | `accent-green` | 现有，默认 |
| 蓝色 | `0xff1565c0` | `accent-blue` | 现有 |
| 橙色 | `0xffef6c00` | `accent-orange` | 现有 |
| 红色 | `0xffc62828` | `accent-red` | 新增 |
| 紫色 | `0xff6a1b9a` | `accent-purple` | 新增 |
| 青色 | `0xff00838f` | `accent-teal` | 新增 |
| 粉色 | `0xffad1457` | `accent-pink` | 新增 |
| 黄色 | `0xfff9a825` | `accent-yellow` | 新增 |
| 靛蓝 | `0xff283593` | `accent-indigo` | 新增 |

**默认值变更**：当前应用种子色硬编码为 `0xff176b55`（深绿）。扩展后改为 `0xff37c58b`（亮绿，与水印色统一），保持绿色视觉但与水印色一致。

## 架构

### 数据层

#### 新增字段

`AppSettings` 表新增：
```dart
IntColumn get appSeedColorArgb =>
    integer().withDefault(const Constant(0xff37c58b))();
```

水印色字段不变（`defaultWatermarkAccentColorArgb` / `projects.watermarkAccentColorArgb`），仅扩展可选值。

#### Schema 迁移 v6 → v7

参考现有 `_ensureDynamicColorColumns()` 模式，新增 `_ensureAppSeedColorColumn()`：

```dart
int get schemaVersion => 7;

// 在 onUpgrade 中：
if (from < 7) {
  await _ensureAppSeedColorColumn();
}

Future<void> _ensureAppSeedColorColumn() async {
  final columns = await customSelect(
    'PRAGMA table_info(app_settings)',
  ).get();
  final columnNames = columns.map((row) => row.read<String>('name')).toSet();
  if (!columnNames.contains('app_seed_color_argb')) {
    await customStatement(
      'ALTER TABLE app_settings ADD COLUMN app_seed_color_argb '
      'INTEGER NOT NULL DEFAULT 0xff37c58b',
    );
  }
}
```

同时在 `_ensureGlobalSettingsRow()` 的 `AppSettingsCompanion.insert` 中加 `appSeedColorArgb: const Value(0xff37c58b)`。

`updateAppSettings()` 加 `int? appSeedColorArgb` 参数。

### 共享 swatch 重构

#### `lib/features/settings/settings_section_scaffold.dart`

把 `accentSwatches` 从 3 种扩展到 9 种，每个 swatch 增加 `label` 字段（l10n 字符串 getter 名）：

```dart
const accentSwatches = <({int argb, Key key, String labelKey})>[
  (argb: 0xff37c58b, key: Key('accent-green'),  labelKey: 'green'),
  (argb: 0xff1565c0, key: Key('accent-blue'),   labelKey: 'blue'),
  (argb: 0xffef6c00, key: Key('accent-orange'), labelKey: 'orange'),
  (argb: 0xffc62828, key: Key('accent-red'),    labelKey: 'red'),
  (argb: 0xff6a1b9a, key: Key('accent-purple'), labelKey: 'purple'),
  (argb: 0xff00838f, key: Key('accent-teal'),   labelKey: 'teal'),
  (argb: 0xffad1457, key: Key('accent-pink'),   labelKey: 'pink'),
  (argb: 0xfff9a825, key: Key('accent-yellow'), labelKey: 'yellow'),
  (argb: 0xff283593, key: Key('accent-indigo'), labelKey: 'indigo'),
];
```

由于 Dart records 不能直接存函数引用，`labelKey` 用字符串，由调用方映射到 `AppStrings` getter。

#### 共享 `_AccentChoice` widget

新增 `AccentChoiceChip` widget（放在 `settings_section_scaffold.dart` 或独立文件 `lib/features/settings/accent_choice_chip.dart`）：

```dart
class AccentChoiceChip extends StatelessWidget {
  const AccentChoiceChip({
    super.key,
    required this.argb,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final int argb;
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      avatar: CircleAvatar(backgroundColor: Color(argb)),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }
}
```

### UI 改造

#### 外观设置页 `appearance_section_screen.dart`

在 dynamic color toggle **上方** 新增"应用主题色"选择器：

```dart
// 仅在 useDynamicColor=false 时显示（动态色开启时种子色被覆盖）
if (!settings.useDynamicColor) ...[
  Text(strings.appThemeColor, style: Theme.of(context).textTheme.titleMedium),
  const SizedBox(height: 12),
  Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      for (final swatch in accentSwatches)
        AccentChoiceChip(
          argb: swatch.argb,
          label: _labelFor(swatch.labelKey, strings),
          selected: settings.appSeedColorArgb == swatch.argb,
          onSelected: () => ref.read(appSettingControllerProvider.notifier)
              .update((s) => s.copyWith(appSeedColorArgb: swatch.argb)),
        ),
    ],
  ),
  const SizedBox(height: 16),
],
```

`_labelFor` 把 `labelKey` 字符串映射到 `AppStrings` getter。

#### 水印默认值页 `watermark_defaults_section_screen.dart`

把现有 3 个 `_AccentChoice` 替换为 `for (final swatch in accentSwatches) AccentChoiceChip(...)`，循环体调 `appSettingControllerProvider`。

#### 项目水印设置页 `project_watermark_settings_screen.dart`

删除第 191-214 行的重复三段 `_AccentChoice`，替换为同样的 `for (final swatch in accentSwatches)` 循环，保存逻辑改为调 `database.updateProjectWatermarkSettings`。删除该文件内的 `_AccentChoice` 私有 widget 定义。

### app.dart 改造

第 583、589 行的硬编码种子色改为读取持久化值：

```dart
final seedColor = Color(settings?.appSeedColorArgb ?? 0xff37c58b);
final lightScheme = useDynamicColor
    ? lightDynamic
    : ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: Brightness.light,
      );
final darkScheme = useDynamicColor
    ? darkDynamic
    : ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: Brightness.dark,
      );
```

### AppSettingController 改造

`lib/features/settings/app_setting_controller.dart` 的 `update()` 方法参数列表加 `appSeedColorArgb`，调 `db.updateAppSettings` 时透传。

### l10n 新增字符串

`lib/l10n/app_strings.dart` 新增：

| getter | 英文 | 中文 |
|---|---|---|
| `appThemeColor` | 'App theme color' | '应用主题色' |
| `red` | 'Red' | '红色' |
| `purple` | 'Purple' | '紫色' |
| `teal` | 'Teal' | '青色' |
| `pink` | 'Pink' | '粉色' |
| `yellow` | 'Yellow' | '黄色' |
| `indigo` | 'Indigo' | '靛蓝' |

## 测试

### 数据库迁移测试

- v6 → v7 升级后 `app_seed_color_argb` 列存在，默认值 `0xff37c58b`
- 老用户升级后种子色保持绿色视觉
- `_ensureGlobalSettingsRow` 插入的行包含 `appSeedColorArgb`

### AppSettingController 测试

- `update` 接受 `appSeedColorArgb` 并持久化到 DB
- 乐观更新回流到 UI

### 外观页测试

- 9 个 `AccentChoiceChip` 渲染
- `useDynamicColor=true` 时选择器不显示
- `useDynamicColor=false` 时选择器显示
- 点击 chip 后 `appSeedColorArgb` 更新

### 水印默认值页测试

- 9 个 chip 渲染
- 选中状态正确
- 点击后 `defaultWatermarkAccentColorArgb` 更新

### 项目水印设置页测试

- 9 个 chip 渲染
- 选中状态正确
- 点击后 `watermarkAccentColorArgb` 更新
- 不再存在重复的 `_AccentChoice` 私有 widget

### 共享 swatch 常量测试

- `accentSwatches` 长度为 9
- 每个 `key` 唯一
- 每个 `labelKey` 能映射到 `AppStrings` getter

## 风险与权衡

- **视觉变化**：默认种子色从深绿 `0xff176b55` 改为亮绿 `0xff37c58b`，Light/Dark 调色板会略变。用户已选扩展主题色，可接受。
- **DB 迁移**：新增字段带默认值，老用户升级后自动获得绿色种子色，无破坏性。
- **重复代码消除**：项目水印页的重复 `_AccentChoice` 改为共享 widget，减少 ~50 行代码。
- **Light/Dark 共用种子色**：符合 M3 规范，`ColorScheme.fromSeed` 会根据 brightness 自动调整明度。可能让 Dark 主题的绿色比之前略暗，但视觉测试会验证。

## 文件清单

- `lib/data/app_database.dart` — 新增 `appSeedColorArgb` 字段、schema v7 迁移、`updateAppSettings` 参数
- `lib/data/app_database.g.dart` — drift 重新生成
- `lib/app.dart` — 读取 `appSeedColorArgb` 作为种子色
- `lib/features/settings/app_setting_controller.dart` — `update` 加参数
- `lib/features/settings/settings_section_scaffold.dart` — `accentSwatches` 扩展到 9 种
- `lib/features/settings/accent_choice_chip.dart` — 新增共享 widget
- `lib/features/settings/sections/appearance_section_screen.dart` — 新增主题色选择器
- `lib/features/settings/sections/watermark_defaults_section_screen.dart` — 复用共享 chip
- `lib/features/projects/project_watermark_settings_screen.dart` — 删除重复 `_AccentChoice`，复用共享 chip
- `lib/l10n/app_strings.dart` — 新增 7 个字符串
- 测试文件：迁移测试、controller 测试、3 个 UI 测试、swatch 常量测试
