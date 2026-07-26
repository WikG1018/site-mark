# 主题色扩展实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把应用主题色从硬编码扩展为用户可选的 9 种，同步扩展水印强调色到 9 种，并消除项目水印页的重复颜色选择器代码。

**Architecture:** 在 `AppSettings` 表新增 `appSeedColorArgb` 字段（schema v6→v7 迁移），把 `accentSwatches` 常量从 3 种扩展到 9 种并加 `labelKey`，新增共享 `AccentChoiceChip` widget。外观设置页新增主题色选择器（仅在 `useDynamicColor=false` 时显示），水印默认值页和项目水印页都改为复用共享 chip。`app.dart` 读取持久化种子色替代硬编码。

**Tech Stack:** Flutter, drift (schema v7), Riverpod 3.x `AsyncNotifier`, Material 3 `ColorScheme.fromSeed`, `dynamic_color` package。

## Global Constraints

- Schema 版本从 v6 升到 v7，必须用 `PRAGMA table_info` + `ALTER TABLE` 模式补列，参考现有 `_ensureDynamicColorColumns()`。
- `accentSwatches` 常量必须从 3 种扩展到 9 种，新增 `labelKey` 字段（String），由调用方映射到 `AppStrings` getter。
- Light/Dark 主题共用用户选的种子色，由 `ColorScheme.fromSeed(seedColor, brightness)` 自动生成调色板。
- 默认种子色从硬编码 `0xff176b55` 改为 `0xff37c58b`（与水印色统一）。
- 项目水印页必须删除重复的 `_AccentChoice` 私有 widget，改用共享 `AccentChoiceChip`。
- 所有测试通过 `flutter test`，代码通过 `flutter analyze`。
- 提交信息用 `feat:` / `refactor:` / `test:` / `docs:` 前缀，参照现有提交风格。
- 提交到 `feat/theme-color-expansion` 分支，最终推送并创建 PR。

---

## 文件结构

| 文件 | 职责 | 操作 |
|---|---|---|
| `lib/data/app_database.dart` | drift 表定义、迁移、`updateAppSettings` | 修改 |
| `lib/data/app_database.g.dart` | drift 生成代码 | 重新生成 |
| `lib/app.dart` | `ColorScheme.fromSeed` 种子色来源 | 修改 |
| `lib/features/settings/app_setting_controller.dart` | `update` 透传新字段 | 修改 |
| `lib/features/settings/settings_section_scaffold.dart` | `accentSwatches` 扩展到 9 种 | 修改 |
| `lib/features/settings/accent_choice_chip.dart` | 共享 `AccentChoiceChip` widget | 新建 |
| `lib/features/settings/sections/appearance_section_screen.dart` | 新增主题色选择器 | 修改 |
| `lib/features/settings/sections/watermark_defaults_section_screen.dart` | 复用共享 chip | 修改 |
| `lib/features/projects/project_watermark_settings_screen.dart` | 删除重复 `_AccentChoice`，复用共享 chip | 修改 |
| `lib/l10n/app_strings.dart` | 新增 7 个字符串 | 修改 |
| `test/data/app_database_migration_test.dart` | v6→v7 迁移测试 | 修改 |
| `test/features/settings/app_setting_controller_test.dart` | controller 透传测试 | 修改/新建 |
| `test/features/settings/sections/appearance_section_screen_test.dart` | 主题色选择器测试 | 修改 |
| `test/features/settings/sections/watermark_defaults_section_screen_test.dart` | 9 chip 测试 | 修改 |
| `test/features/settings/accent_choice_chip_test.dart` | 共享 widget 测试 | 新建 |
| `test/features/projects/project_watermark_settings_screen_test.dart` | 9 chip 测试 | 修改 |

---

### Task 1: 新增 `appSeedColorArgb` DB 字段 + schema v7 迁移

**Files:**
- Modify: `lib/data/app_database.dart:42-62`（`AppSettings` 表定义）
- Modify: `lib/data/app_database.dart:138`（`schemaVersion`）
- Modify: `lib/data/app_database.dart:190-214`（`onUpgrade` 加 v7 分支）
- Modify: `lib/data/app_database.dart:225-242`（`_ensureGlobalSettingsRow` 加默认值）
- Modify: `lib/data/app_database.dart:264-291`（新增 `_ensureAppSeedColorColumn`）
- Modify: `lib/data/app_database.dart:657-703`（`updateAppSettings` 加参数）
- Modify: `lib/data/app_database.g.dart`（drift 重新生成）
- Test: `test/data/app_database_migration_test.dart`（新增 v6→v7 迁移测试）

**Interfaces:**
- Produces: `AppSetting.appSeedColorArgb` (int, 默认 `0xff37c58b`)；`updateAppSettings(appSeedColorArgb: int?)` 参数；`_ensureAppSeedColorColumn()` 方法。

- [ ] **Step 1: 写失败的迁移测试**

在 `test/data/app_database_migration_test.dart` 末尾追加（在最后一个 `test(...)` 闭合括号前）：

```dart
  test('v6 to v7 migration adds app_seed_color_argb column', () async {
    // Open a genuine v6 schema (with use_dynamic_color and
    // completion_notifications_enabled already present), then bump
    // user_version to 6 and reopen via AppDatabase.forTesting so onUpgrade
    // runs the v7 branch and adds app_seed_color_argb.
    final db = sqlite3.openInMemory();

    // Create a complete v6 app_settings row so _ensureGlobalSettingsRow()
    // does not need to insert anything (we want to verify the ALTER TABLE
    // path, not the insert path).
    db.execute('''
      CREATE TABLE app_settings (
        id TEXT NOT NULL,
        theme_mode TEXT NOT NULL DEFAULT 'system',
        locale_code TEXT,
        default_watermark_position TEXT NOT NULL DEFAULT 'bottomLeft',
        default_watermark_opacity REAL NOT NULL DEFAULT 0.78,
        default_watermark_accent_color_argb INTEGER NOT NULL DEFAULT 0xff37c58b,
        default_watermark_font_scale REAL NOT NULL DEFAULT 1.0,
        location_permission_prompt_dismissed INTEGER NOT NULL DEFAULT 0,
        use_dynamic_color INTEGER NOT NULL DEFAULT 0,
        completion_notifications_enabled INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (id)
      );
    ''');
    db.execute(
      "INSERT INTO app_settings (id, theme_mode, updated_at) VALUES ('global', 'dark', 0);",
    );
    // Minimal projects + captures tables so onCreate doesn't fail.
    db.execute('''
      CREATE TABLE projects (
        id TEXT NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        watermark_position TEXT NOT NULL DEFAULT 'bottomLeft',
        watermark_opacity REAL NOT NULL DEFAULT 0.78,
        watermark_accent_color_argb INTEGER NOT NULL DEFAULT 0xff37c58b,
        watermark_font_scale REAL NOT NULL DEFAULT 1.0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (id)
      );
    ''');
    db.execute('''
      CREATE TABLE captures (
        id TEXT NOT NULL,
        project_id TEXT NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
        photo_number TEXT,
        work_location TEXT NOT NULL,
        work_content TEXT NOT NULL,
        photographer TEXT NOT NULL,
        notes TEXT,
        original_path TEXT NOT NULL,
        published_uri TEXT,
        original_sha256 TEXT,
        status TEXT NOT NULL,
        failure_reason TEXT,
        created_at INTEGER NOT NULL,
        captured_at INTEGER,
        latitude REAL,
        longitude REAL,
        accuracy_meters REAL,
        address TEXT,
        location_outcome TEXT,
        processing_attempts INTEGER NOT NULL DEFAULT 0,
        watermark_locale_code TEXT NOT NULL DEFAULT 'zh',
        location_resolution TEXT NOT NULL DEFAULT 'resolved',
        original_deleted_at INTEGER,
        PRIMARY KEY (id)
      );
    ''');
    db.execute('PRAGMA user_version = 6;');

    final database = AppDatabase.forTesting(NativeDatabase(db));
    addTearDown(database.close);

    final settings = await database.getAppSettings();
    expect(settings.id, 'global');
    expect(settings.appSeedColorArgb, 0xff37c58b);

    final updated = await database.updateAppSettings(
      appSeedColorArgb: 0xff1565c0,
    );
    expect(updated.appSeedColorArgb, 0xff1565c0);
  });
```

- [ ] **Step 2: 运行测试验证失败**

Run: `flutter test test/data/app_database_migration_test.dart --plain-name "v6 to v7 migration adds app_seed_color_argb column"`
Expected: FAIL — `appSeedColorArgb` getter 不存在（drift 未重新生成）。

- [ ] **Step 3: 修改 `AppSettings` 表定义**

在 `lib/data/app_database.dart` 的 `AppSettings` 表（第 57-58 行 `completionNotificationsEnabled` 后）新增字段：

```dart
  BoolColumn get completionNotificationsEnabled =>
      boolean().withDefault(const Constant(false))();
  IntColumn get appSeedColorArgb =>
      integer().withDefault(const Constant(0xff37c58b))();
  DateTimeColumn get updatedAt => dateTime()();
```

- [ ] **Step 4: 升级 schema 版本**

把 `lib/data/app_database.dart` 第 138 行：

```dart
  int get schemaVersion => 6;
```

改为：

```dart
  int get schemaVersion => 7;
```

- [ ] **Step 5: 在 `onUpgrade` 加 v7 分支**

在 `lib/data/app_database.dart` 的 `onUpgrade` 中，`if (from < 6) { ... }` 块之后（第 213 行 `await _ensureDynamicColorColumns();` 闭合的 `}` 之后、`await _ensureGlobalSettingsRow();` 之前）新增：

```dart
      if (from < 7) {
        // Adds the persisted app theme seed color. Users on any prior
        // schema version converge here; the default (0xff37c58b) keeps
        // the existing green brand identity.
        await _ensureAppSeedColorColumn();
      }
```

- [ ] **Step 6: 新增 `_ensureAppSeedColorColumn` 方法**

在 `lib/data/app_database.dart` 的 `_ensureDynamicColorColumns()` 方法之后（第 291 行 `}` 之后）新增：

```dart
  /// Adds the `app_seed_color_argb` column to `app_settings` if missing.
  ///
  /// Called from the v7 migration step. Uses `PRAGMA table_info` so the
  /// operation is idempotent and never raises "duplicate column name".
  Future<void> _ensureAppSeedColorColumn() async {
    final columns = await customSelect(
      'PRAGMA table_info(app_settings)',
    ).get();
    final columnNames = columns.map((row) => row.read<String>('name')).toSet();
    if (!columnNames.contains('app_seed_color_argb')) {
      await customStatement(
        'ALTER TABLE app_settings ADD COLUMN app_seed_color_argb '
        'INTEGER NOT NULL DEFAULT 4293215371',
      );
    }
  }
```

注意：`4293215371` 是 `0xff37c58b` 的十进制值（SQLite ALTER TABLE 的 DEFAULT 不支持十六进制字面量）。

- [ ] **Step 7: 在 `_ensureGlobalSettingsRow` 加默认值**

在 `lib/data/app_database.dart` 的 `_ensureGlobalSettingsRow()` 方法（第 227-241 行），`AppSettingsCompanion.insert` 中 `completionNotificationsEnabled` 之后、`updatedAt` 之前新增：

```dart
        completionNotificationsEnabled: const Value(false),
        appSeedColorArgb: const Value(0xff37c58b),
        updatedAt: now,
```

- [ ] **Step 8: 在 `updateAppSettings` 加参数**

在 `lib/data/app_database.dart` 第 657-667 行的 `updateAppSettings` 签名加参数：

```dart
  Future<AppSetting> updateAppSettings({
    String? themeMode,
    String? localeCode,
    String? defaultWatermarkPosition,
    double? defaultWatermarkOpacity,
    int? defaultWatermarkAccentColorArgb,
    double? defaultWatermarkFontScale,
    bool? locationPermissionPromptDismissed,
    bool? useDynamicColor,
    bool? completionNotificationsEnabled,
    int? appSeedColorArgb,
  }) async {
```

在 companion 构造（第 668-696 行）中，`completionNotificationsEnabled` 之后、`updatedAt` 之前新增：

```dart
      completionNotificationsEnabled: completionNotificationsEnabled == null
          ? const Value.absent()
          : Value(completionNotificationsEnabled),
      appSeedColorArgb: appSeedColorArgb == null
          ? const Value.absent()
          : Value(appSeedColorArgb),
      updatedAt: Value(DateTime.now()),
```

- [ ] **Step 9: 重新生成 drift 代码**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `Succeeded after ...s with ... outputs`

- [ ] **Step 10: 运行迁移测试验证通过**

Run: `flutter test test/data/app_database_migration_test.dart --plain-name "v6 to v7 migration adds app_seed_color_argb column"`
Expected: PASS

- [ ] **Step 11: 运行全量数据库测试确保无回归**

Run: `flutter test test/data/`
Expected: 全部 PASS

- [ ] **Step 12: 提交**

```bash
git add lib/data/app_database.dart lib/data/app_database.g.dart test/data/app_database_migration_test.dart
git commit -m "feat(db): add appSeedColorArgb column with v7 migration"
```

---

### Task 2: `AppSettingController` 透传 `appSeedColorArgb`

**Files:**
- Modify: `lib/features/settings/app_setting_controller.dart:40-49`（`update` 方法的 `db.updateAppSettings` 调用）
- Test: `test/features/settings/app_setting_controller_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `updateAppSettings(appSeedColorArgb: int?)` 参数
- Produces: `AppSettingController.update` 通过 `copyWith(appSeedColorArgb: ...)` 接受新字段

- [ ] **Step 1: 写失败的 controller 测试**

在 `test/features/settings/app_setting_controller_test.dart` 末尾追加（若文件不存在则创建，参照现有 `appearance_section_screen_test.dart` 的 setUp 模式）：

```dart
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/features/settings/app_setting_controller.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  testWidgets('update persists appSeedColorArgb', (tester) async {
    await database.getAppSettings();
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
    addTearDown(container.dispose);

    await container.read(appSettingControllerProvider.future);
    await container
        .read(appSettingControllerProvider.notifier)
        .update((s) => s.copyWith(appSeedColorArgb: 0xff1565c0));

    final persisted = await database.getAppSettings();
    expect(persisted.appSeedColorArgb, 0xff1565c0);
  });
}
```

- [ ] **Step 2: 运行测试验证失败**

Run: `flutter test test/features/settings/app_setting_controller_test.dart --plain-name "update persists appSeedColorArgb"`
Expected: FAIL — `db.updateAppSettings` 未传 `appSeedColorArgb`，持久化值仍是默认。

- [ ] **Step 3: 修改 controller 透传字段**

在 `lib/features/settings/app_setting_controller.dart` 第 40-49 行的 `db.updateAppSettings(...)` 调用中，`completionNotificationsEnabled` 之后新增：

```dart
      await db.updateAppSettings(
        themeMode: next.themeMode,
        useDynamicColor: next.useDynamicColor,
        localeCode: next.localeCode,
        defaultWatermarkPosition: next.defaultWatermarkPosition,
        defaultWatermarkOpacity: next.defaultWatermarkOpacity,
        defaultWatermarkFontScale: next.defaultWatermarkFontScale,
        defaultWatermarkAccentColorArgb: next.defaultWatermarkAccentColorArgb,
        completionNotificationsEnabled: next.completionNotificationsEnabled,
        appSeedColorArgb: next.appSeedColorArgb,
      );
```

- [ ] **Step 4: 运行测试验证通过**

Run: `flutter test test/features/settings/app_setting_controller_test.dart --plain-name "update persists appSeedColorArgb"`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/features/settings/app_setting_controller.dart test/features/settings/app_setting_controller_test.dart
git commit -m "feat(settings): persist appSeedColorArgb through controller"
```

---

### Task 3: l10n 新增 7 个颜色字符串

**Files:**
- Modify: `lib/l10n/app_strings.dart:103`（`orange` 之后新增 6 个颜色名）
- Modify: `lib/l10n/app_strings.dart:136`（`about` 之前新增 `appThemeColor`）

**Interfaces:**
- Produces: `AppStrings.appThemeColor`、`.red`、`.purple`、`.teal`、`.pink`、`.yellow`、`.indigo` getter

- [ ] **Step 1: 新增 6 个颜色名 getter**

在 `lib/l10n/app_strings.dart` 第 103 行 `String get orange => ...` 之后新增：

```dart
  String get orange => _english ? 'Orange' : '橙色';
  String get red => _english ? 'Red' : '红色';
  String get purple => _english ? 'Purple' : '紫色';
  String get teal => _english ? 'Teal' : '青色';
  String get pink => _english ? 'Pink' : '粉色';
  String get yellow => _english ? 'Yellow' : '黄色';
  String get indigo => _english ? 'Indigo' : '靛蓝';
```

- [ ] **Step 2: 新增 `appThemeColor` getter**

在 `lib/l10n/app_strings.dart` 第 136 行 `String get about => ...` 之前新增：

```dart
  String get appThemeColor => _english ? 'App theme color' : '应用主题色';
  String get about => _english ? 'About' : '关于';
```

- [ ] **Step 3: 运行 analyze 确保无语法错误**

Run: `flutter analyze lib/l10n/app_strings.dart`
Expected: No issues found

- [ ] **Step 4: 提交**

```bash
git add lib/l10n/app_strings.dart
git commit -m "feat(l10n): add theme color and 6 color name strings"
```

---

### Task 4: 扩展 `accentSwatches` 常量到 9 种 + 新增共享 `AccentChoiceChip`

**Files:**
- Modify: `lib/features/settings/settings_section_scaffold.dart:5-9`（`accentSwatches` 扩展）
- Create: `lib/features/settings/accent_choice_chip.dart`
- Test: `test/features/settings/accent_choice_chip_test.dart`

**Interfaces:**
- Produces: `accentSwatches`（9 元素列表，每项 `(int argb, Key key, String labelKey)`）；`AccentChoiceChip` widget；`accentLabel(AppStrings, int)` 顶层函数。

- [ ] **Step 1: 写失败的共享 widget 测试**

创建 `test/features/settings/accent_choice_chip_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/features/settings/accent_choice_chip.dart';
import 'package:sitemark/features/settings/settings_section_scaffold.dart';
import 'package:sitemark/l10n/app_strings.dart';

void main() {
  testWidgets('AccentChoiceChip renders label and color', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Material(
          child: AccentChoiceChip(
            argb: 0xff37c58b,
            label: '绿色',
            selected: true,
            onSelected: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('绿色'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsOneWidget);
    expect(find.byKey(const Key('accent-green')), findsNothing);
  });

  test('accentSwatches has 9 entries with unique keys', () {
    expect(accentSwatches.length, 9);
    final keys = accentSwatches.map((s) => s.key).toSet();
    expect(keys.length, 9);
  });

  test('accentLabel maps every swatch to a non-empty string', () {
    final strings = AppStrings(const Locale('zh'));
    for (final swatch in accentSwatches) {
      final label = accentLabel(strings, swatch.argb);
      expect(label, isNotEmpty);
    }
  });
}
```

- [ ] **Step 2: 运行测试验证失败**

Run: `flutter test test/features/settings/accent_choice_chip_test.dart`
Expected: FAIL — `AccentChoiceChip` 和 `accentLabel` 不存在，`accentSwatches.length` 是 3。

- [ ] **Step 3: 扩展 `accentSwatches` 常量**

在 `lib/features/settings/settings_section_scaffold.dart` 第 5-9 行替换为：

```dart
/// Accent swatches offered as new-project watermark defaults AND app theme
/// seed colors. Each entry carries a stable [Key] for test discovery and a
/// `labelKey` string that callers map to an [AppStrings] getter via
/// [accentLabel].
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

- [ ] **Step 4: 创建 `AccentChoiceChip` widget 和 `accentLabel` 函数**

创建 `lib/features/settings/accent_choice_chip.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:sitemark/features/settings/settings_section_scaffold.dart';
import 'package:sitemark/l10n/app_strings.dart';

/// Shared ChoiceChip for accent color selection.
///
/// Used by the appearance screen (app theme seed color), the watermark
/// defaults screen, and the project watermark settings screen. The [key]
/// is intentionally NOT set from the swatch's key — callers pass a stable
/// swatch key only when they need test discoverability via ancestor lookup
/// (the chip's `avatar` CircleAvatar is the visual anchor).
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
      avatar: CircleAvatar(backgroundColor: Color(argb)),
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }
}

/// Maps a swatch ARGB value to its localized label.
///
/// Returns the empty string for unknown ARGB values so callers can assert
/// non-empty in tests without crashing production.
String accentLabel(AppStrings strings, int argb) {
  for (final swatch in accentSwatches) {
    if (swatch.argb == argb) {
      return switch (swatch.labelKey) {
        'green' => strings.green,
        'blue' => strings.blue,
        'orange' => strings.orange,
        'red' => strings.red,
        'purple' => strings.purple,
        'teal' => strings.teal,
        'pink' => strings.pink,
        'yellow' => strings.yellow,
        'indigo' => strings.indigo,
        _ => '',
      };
    }
  }
  return '';
}
```

- [ ] **Step 5: 运行测试验证通过**

Run: `flutter test test/features/settings/accent_choice_chip_test.dart`
Expected: 3 tests PASS

- [ ] **Step 6: 提交**

```bash
git add lib/features/settings/settings_section_scaffold.dart lib/features/settings/accent_choice_chip.dart test/features/settings/accent_choice_chip_test.dart
git commit -m "feat(settings): expand accentSwatches to 9 and add shared AccentChoiceChip"
```

---

### Task 5: `app.dart` 读取持久化种子色

**Files:**
- Modify: `lib/app.dart:580-591`（`ColorScheme.fromSeed` 种子色来源）

**Interfaces:**
- Consumes: Task 1 的 `AppSetting.appSeedColorArgb`

- [ ] **Step 1: 修改种子色来源**

在 `lib/app.dart` 第 580-591 行，把 `lightScheme` / `darkScheme` 块替换为：

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

- [ ] **Step 2: 运行 analyze 确保无错误**

Run: `flutter analyze lib/app.dart`
Expected: No issues found

- [ ] **Step 3: 运行 widget 测试确保无回归**

Run: `flutter test test/widget_test.dart`
Expected: 全部 PASS

- [ ] **Step 4: 提交**

```bash
git add lib/app.dart
git commit -m "feat(app): use persisted appSeedColorArgb for ColorScheme seed"
```

---

### Task 6: 外观设置页新增主题色选择器

**Files:**
- Modify: `lib/features/settings/sections/appearance_section_screen.dart:24-62`（在 theme SegmentedButton 和 dynamic color toggle 之间插入）
- Test: `test/features/settings/sections/appearance_section_screen_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `appSettingControllerProvider`、Task 3 的 `strings.appThemeColor`、Task 4 的 `accentSwatches` / `AccentChoiceChip` / `accentLabel`

- [ ] **Step 1: 写失败的选择器测试**

在 `test/features/settings/sections/appearance_section_screen_test.dart` 末尾追加：

```dart
  testWidgets('shows 9 theme color chips when dynamic color is off', (tester) async {
    await pumpScreen(tester);
    expect(find.text('应用主题色'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(9));
  });

  testWidgets('hides theme color chips when dynamic color is on', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('dynamic-color-switch')));
    await tester.pumpAndSettle();
    expect(find.text('应用主题色'), findsNothing);
  });

  testWidgets('tapping a theme color chip persists appSeedColorArgb', (tester) async {
    await pumpScreen(tester);
    // Tap the blue chip (second in the Wrap).
    await tester.tap(find.byType(ChoiceChip).at(1));
    await tester.pumpAndSettle();
    expect((await database.getAppSettings()).appSeedColorArgb, 0xff1565c0);
  });
```

- [ ] **Step 2: 运行测试验证失败**

Run: `flutter test test/features/settings/sections/appearance_section_screen_test.dart`
Expected: FAIL — 找不到 '应用主题色' 文本。

- [ ] **Step 3: 在外观页插入主题色选择器**

在 `lib/features/settings/sections/appearance_section_screen.dart` 顶部 import 区新增：

```dart
import 'package:sitemark/features/settings/accent_choice_chip.dart';
```

在 `build` 方法的 `Column.children` 中，`SegmentedButton` 的 `const SizedBox(height: 8)` 之后、`SwitchListTile` 之前插入：

```dart
          const SizedBox(height: 8),
          if (!settings.useDynamicColor) ...[
            const SizedBox(height: 12),
            Text(strings.appThemeColor,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final swatch in accentSwatches)
                  AccentChoiceChip(
                    argb: swatch.argb,
                    label: accentLabel(strings, swatch.argb),
                    selected: settings.appSeedColorArgb == swatch.argb,
                    onSelected: () => ref
                        .read(appSettingControllerProvider.notifier)
                        .update((s) =>
                            s.copyWith(appSeedColorArgb: swatch.argb)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
```

注意：原 `const SizedBox(height: 8)` 保留，新增的 `if` 块在它之后。`SwitchListTile` 紧跟 `if` 块之后（原代码 `const SizedBox(height: 8)` 之后直接是 `SwitchListTile`，现在中间插入选择器）。

- [ ] **Step 4: 运行测试验证通过**

Run: `flutter test test/features/settings/sections/appearance_section_screen_test.dart`
Expected: 5 tests PASS（原 2 个 + 新增 3 个）

- [ ] **Step 5: 提交**

```bash
git add lib/features/settings/sections/appearance_section_screen.dart test/features/settings/sections/appearance_section_screen_test.dart
git commit -m "feat(settings): add theme color picker to appearance screen"
```

---

### Task 7: 水印默认值页复用共享 chip

**Files:**
- Modify: `lib/features/settings/sections/watermark_defaults_section_screen.dart:146-200`（替换 `_AccentChoice` 为 `AccentChoiceChip`，删除私有 widget）

**Interfaces:**
- Consumes: Task 4 的 `AccentChoiceChip` / `accentLabel`

- [ ] **Step 1: 写失败的 9-chip 测试**

在 `test/features/settings/sections/watermark_defaults_section_screen_test.dart` 末尾追加（若文件不存在则创建，setUp 参照 `appearance_section_screen_test.dart`）：

```dart
  testWidgets('shows 9 accent chips', (tester) async {
    await pumpScreen(tester);
    expect(find.byType(ChoiceChip), findsNWidgets(9));
  });
```

- [ ] **Step 2: 运行测试验证失败**

Run: `flutter test test/features/settings/sections/watermark_defaults_section_screen_test.dart --plain-name "shows 9 accent chips"`
Expected: FAIL — 当前只有 3 个 `_AccentChoice`（虽是 ChoiceChip 子类，但 `find.byType(ChoiceChip)` 会匹配；若实际通过则说明测试不够严格，改用 `findsNWidgets(9)` 仍会因数量是 3 而失败）。

- [ ] **Step 3: 替换为共享 chip + 删除私有 widget**

在 `lib/features/settings/sections/watermark_defaults_section_screen.dart` 顶部 import 区新增：

```dart
import 'package:sitemark/features/settings/accent_choice_chip.dart';
```

把第 146-162 行的 `Wrap` 块替换为：

```dart
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final swatch in accentSwatches)
                AccentChoiceChip(
                  argb: swatch.argb,
                  label: accentLabel(strings, swatch.argb),
                  selected:
                      settings.defaultWatermarkAccentColorArgb == swatch.argb,
                  onSelected: () => ref
                      .read(appSettingControllerProvider.notifier)
                      .update((s) => s.copyWith(
                          defaultWatermarkAccentColorArgb: swatch.argb)),
                ),
            ],
          ),
```

删除文件末尾第 169-200 行的 `class _AccentChoice extends StatelessWidget { ... }` 整个私有 widget 定义。

- [ ] **Step 4: 运行测试验证通过**

Run: `flutter test test/features/settings/sections/watermark_defaults_section_screen_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/features/settings/sections/watermark_defaults_section_screen.dart test/features/settings/sections/watermark_defaults_section_screen_test.dart
git commit -m "refactor(settings): reuse AccentChoiceChip in watermark defaults"
```

---

### Task 8: 项目水印设置页复用共享 chip

**Files:**
- Modify: `lib/features/projects/project_watermark_settings_screen.dart:187-216`（替换硬编码三段为循环）
- Modify: `lib/features/projects/project_watermark_settings_screen.dart:313-338`（删除私有 `_AccentChoice`）
- Test: `test/features/projects/project_watermark_settings_screen_test.dart`

**Interfaces:**
- Consumes: Task 4 的 `AccentChoiceChip` / `accentLabel`

- [ ] **Step 1: 写失败的 9-chip 测试**

在 `test/features/projects/project_watermark_settings_screen_test.dart` 末尾追加（若文件不存在则创建，setUp 参照 `project_list_screen_test.dart` 的 ProviderScope + database override 模式，需要先创建一个 project）：

```dart
  testWidgets('shows 9 accent chips', (tester) async {
    await pumpScreen(tester);
    expect(find.byType(ChoiceChip), findsNWidgets(9));
  });
```

- [ ] **Step 2: 运行测试验证失败**

Run: `flutter test test/features/projects/project_watermark_settings_screen_test.dart --plain-name "shows 9 accent chips"`
Expected: FAIL — 当前只有 3 个 chip。

- [ ] **Step 3: 替换为循环 + 删除私有 widget**

在 `lib/features/projects/project_watermark_settings_screen.dart` 顶部 import 区新增：

```dart
import 'package:sitemark/features/settings/accent_choice_chip.dart';
import 'package:sitemark/features/settings/settings_section_scaffold.dart' show accentSwatches, accentLabel;
```

把第 187-216 行的 `Wrap` 块替换为：

```dart
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final swatch in accentSwatches)
                    AccentChoiceChip(
                      argb: swatch.argb,
                      label: accentLabel(strings, swatch.argb),
                      selected: _accentColorArgb == swatch.argb,
                      onSelected: () =>
                          setState(() => _accentColorArgb = swatch.argb),
                    ),
                ],
              ),
```

删除文件末尾第 313-338 行的 `class _AccentChoice extends StatelessWidget { ... }` 整个私有 widget 定义。

- [ ] **Step 4: 运行测试验证通过**

Run: `flutter test test/features/projects/project_watermark_settings_screen_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/features/projects/project_watermark_settings_screen.dart test/features/projects/project_watermark_settings_screen_test.dart
git commit -m "refactor(projects): reuse AccentChoiceChip in project watermark settings"
```

---

### Task 9: 全量回归 + 推送 PR

**Files:**
- 无新文件，仅验证

- [ ] **Step 1: 运行全量 analyze**

Run: `flutter analyze`
Expected: No issues found

- [ ] **Step 2: 运行全量测试**

Run: `flutter test`
Expected: 全部 PASS（原 291 + 新增约 8 = ~299）

- [ ] **Step 3: 推送分支**

Run: `git -c http.proxy=http://127.0.0.1:6789 -c https.proxy=http://127.0.0.1:6789 push -u origin feat/theme-color-expansion`
Expected: 推送成功

- [ ] **Step 4: 创建 PR**

用 `gh pr create` 创建 PR，base 是 `main`，标题 `feat: expand theme colors to 9 with persisted seed color`，body 包含变更摘要、颜色清单、迁移说明、测试结果。
