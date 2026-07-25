# Settings Secondary Menu Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the monolithic 805-line `GlobalSettingsScreen` into a secondary menu with 7 dedicated sub-pages and a shared `AppSettingController`.

**Architecture:** A Riverpod `Notifier` (`AppSettingController`) centralizes `AppSetting` read/persist logic with optimistic updates. The main settings page becomes a 7-entry `ListTile` menu. Each section migrates verbatim into its own file under `lib/features/settings/sections/`. Nested `GoRoute`s handle navigation.

**Tech Stack:** Flutter, Riverpod, go_router, drift, Material 3

## Global Constraints

- All existing widget test assertions must pass after refactor (234+ tests).
- l10n keys are unchanged — reuse existing `AppStrings` keys.
- Page transitions use existing `_fadeThroughPage` / `_sharedAxisPage` helpers from `lib/app.dart`.
- `AppSetting` type comes from `package:sitemark/data/app_database.dart`.
- `databaseProvider` from `package:sitemark/data/app_database.dart`.
- No new dependencies; no schema changes.
- Commit messages in English; code comments follow user language (Chinese for domain logic, English for technical).

---

## File Structure

```
lib/features/settings/
├── global_settings_screen.dart              # MODIFY: 7 ListTile entries only
├── app_setting_controller.dart              # CREATE: shared Riverpod controller
├── settings_section_scaffold.dart           # CREATE: shared scaffold + helpers
└── sections/
    ├── appearance_section_screen.dart        # CREATE: theme + dynamic color
    ├── language_section_screen.dart          # CREATE: language selection
    ├── watermark_defaults_section_screen.dart# CREATE: position/opacity/font/accent
    ├── storage_section_screen.dart           # CREATE: storage detail + manage + clear
    ├── location_section_screen.dart          # CREATE: location permission
    ├── notification_section_screen.dart      # CREATE: completion notification toggle
    └── about_section_screen.dart             # CREATE: version/privacy/repo/license
```

Test files mirror the structure under `test/features/settings/`.

---

### Task 1: Create AppSettingController

**Files:**
- Create: `lib/features/settings/app_setting_controller.dart`
- Test: `test/features/settings/app_setting_controller_test.dart`

**Interfaces:**
- Consumes: `databaseProvider` (`AppDatabase`), `AppSetting` type
- Produces: `appSettingControllerProvider` ( Riverpod `NotifierProvider`), `AppSettingController` class with `update()` method

- [ ] **Step 1: Write the failing test**

```dart
// test/features/settings/app_setting_controller_test.dart
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

  test('build loads the singleton AppSetting', () async {
    await database.getAppSettings();
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
    addTearDown(container.dispose);
    final result = await container.read(appSettingControllerProvider.future);
    expect(result.themeMode, 'system');
  });

  test('update persists and reflects the new value', () async {
    await database.getAppSettings();
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
    addTearDown(container.dispose);
    await container.read(appSettingControllerProvider.future);
    await container
        .read(appSettingControllerProvider.notifier)
        .update((s) => s.copyWith(themeMode: 'dark'));
    final fromDb = await database.getAppSettings();
    expect(fromDb.themeMode, 'dark');
    expect(container.read(appSettingControllerProvider).value?.themeMode, 'dark');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/settings/app_setting_controller_test.dart`
Expected: FAIL — `app_setting_controller.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/features/settings/app_setting_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitemark/data/app_database.dart';

/// Centralizes [AppSetting] read/persist logic for all settings sub-pages.
///
/// Sub-pages `ref.watch(appSettingControllerProvider)` for auto-rebuild on
/// change. Call `update` with a functional updater to modify the setting:
/// the controller optimistic-updates the state, then persists to the database.
class AppSettingController extends Notifier<AsyncValue<AppSetting>> {
  @override
  AsyncValue<AppSetting> build() {
    final db = ref.read(databaseProvider);
    return AsyncValue.guard(() => db.getAppSettings());
  }

  /// Updates the [AppSetting] optimistically, then persists to the database.
  /// If persistence fails, the state rolls back to the previous value.
  Future<void> update(AppSetting Function(AppSetting current) updater) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = updater(current);
    state = AsyncData(next);
    try {
      final db = ref.read(databaseProvider);
      await db.updateAppSettings(
        themeMode: next.themeMode,
        useDynamicColor: next.useDynamicColor,
        localeCode: next.localeCode,
        defaultWatermarkPosition: next.defaultWatermarkPosition,
        defaultWatermarkOpacity: next.defaultWatermarkOpacity,
        defaultWatermarkFontScale: next.defaultWatermarkFontScale,
        defaultWatermarkAccentColorArgb: next.defaultWatermarkAccentColorArgb,
        completionNotificationsEnabled: next.completionNotificationsEnabled,
      );
    } catch (_) {
      // Roll back to the previous value on persist failure.
      state = AsyncData(current);
    }
  }
}

final appSettingControllerProvider =
    NotifierProvider<AppSettingController, AsyncValue<AppSetting>>(
  AppSettingController.new,
);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/settings/app_setting_controller_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/settings/app_setting_controller.dart test/features/settings/app_setting_controller_test.dart
git commit -m "feat: add AppSettingController for shared settings state"
```

---

### Task 2: Create shared scaffold and helpers

**Files:**
- Create: `lib/features/settings/settings_section_scaffold.dart`
- Consumes: `AppStrings`, `AppMotion`
- Produces: `SettingsSectionScaffold` widget, `SectionHeader` widget, `accentSwatches` const, `segmentTapTargetStyle` const

- [ ] **Step 1: Write the implementation (no test needed — pure presentational)**

```dart
// lib/features/settings/settings_section_scaffold.dart
import 'package:flutter/material.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';

/// Accent swatches offered as new-project watermark defaults.
const accentSwatches = <({int argb, Key key})>[
  (argb: 0xff37c58b, key: Key('accent-green')),
  (argb: 0xff1565c0, key: Key('accent-blue')),
  (argb: 0xffef6c00, key: Key('accent-orange')),
];

/// Segmented buttons default to 40dp; lifting to 48dp meets Android tap-target.
const segmentTapTargetStyle = ButtonStyle(
  minimumSize: WidgetStatePropertyAll<Size>(Size.fromHeight(48)),
);

/// Standard scaffold for a settings sub-page: AppBar with the section title,
/// scrollable body with consistent padding.
class SettingsSectionScaffold extends StatelessWidget {
  const SettingsSectionScaffold({
    super.key,
    required this.title,
    required this.body,
  });

  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [body],
      ),
    );
  }
}

/// Section header label used inside sub-pages.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/features/settings/settings_section_scaffold.dart
git commit -m "feat: add shared settings section scaffold and helpers"
```

---

### Task 3: Create AppearanceSectionScreen

**Files:**
- Create: `lib/features/settings/sections/appearance_section_screen.dart`
- Test: `test/features/settings/sections/appearance_section_screen_test.dart`

**Interfaces:**
- Consumes: `appSettingControllerProvider`, `AppStrings`, `segmentTapTargetStyle`
- Produces: `AppearanceSectionScreen` widget

- [ ] **Step 1: Write the failing test**

```dart
// test/features/settings/sections/appearance_section_screen_test.dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/features/settings/sections/appearance_section_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await database.getAppSettings();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const AppearanceSectionScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('theme selection persists', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('theme-dark')));
    await tester.pumpAndSettle();
    expect((await database.getAppSettings()).themeMode, 'dark');
  });

  testWidgets('dynamic color switch persists', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('dynamic-color-switch')));
    await tester.pumpAndSettle();
    expect((await database.getAppSettings()).useDynamicColor, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/settings/sections/appearance_section_screen_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/features/settings/sections/appearance_section_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitemark/features/settings/app_setting_controller.dart';
import 'package:sitemark/features/settings/settings_section_scaffold.dart';
import 'package:sitemark/l10n/app_strings.dart';

class AppearanceSectionScreen extends ConsumerWidget {
  const AppearanceSectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppStrings.of(context);
    final asyncSettings = ref.watch(appSettingControllerProvider);
    final settings = asyncSettings.valueOrNull;
    if (settings == null) {
      return SettingsSectionScaffold(
        title: strings.appearance,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return SettingsSectionScaffold(
      title: strings.appearance,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(strings.theme, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            key: const Key('theme-segmented'),
            style: segmentTapTargetStyle,
            segments: [
              ButtonSegment(
                value: 'system',
                label: Text(strings.systemTheme, key: const Key('theme-system')),
              ),
              ButtonSegment(
                value: 'light',
                label: Text(strings.lightTheme, key: const Key('theme-light')),
              ),
              ButtonSegment(
                value: 'dark',
                label: Text(strings.darkTheme, key: const Key('theme-dark')),
              ),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (selection) => ref
                .read(appSettingControllerProvider.notifier)
                .update((s) => s.copyWith(themeMode: selection.single)),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            key: const Key('dynamic-color-switch'),
            title: Text(strings.dynamicColorTitle),
            subtitle: Text(strings.dynamicColorSubtitle),
            value: settings.useDynamicColor,
            onChanged: (value) => ref
                .read(appSettingControllerProvider.notifier)
                .update((s) => s.copyWith(useDynamicColor: value)),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/settings/sections/appearance_section_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/settings/sections/appearance_section_screen.dart test/features/settings/sections/appearance_section_screen_test.dart
git commit -m "feat: add appearance settings sub-page"
```

---

### Task 4: Create LanguageSectionScreen

**Files:**
- Create: `lib/features/settings/sections/language_section_screen.dart`
- Test: `test/features/settings/sections/language_section_screen_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/settings/sections/language_section_screen_test.dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/features/settings/sections/language_section_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  testWidgets('language selection persists', (tester) async {
    await database.getAppSettings();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const LanguageSectionScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-en')));
    await tester.pumpAndSettle();
    expect((await database.getAppSettings()).localeCode, 'en');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/settings/sections/language_section_screen_test.dart`
Expected: FAIL

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/features/settings/sections/language_section_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitemark/features/settings/app_setting_controller.dart';
import 'package:sitemark/features/settings/settings_section_scaffold.dart';
import 'package:sitemark/l10n/app_strings.dart';

class LanguageSectionScreen extends ConsumerWidget {
  const LanguageSectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppStrings.of(context);
    final asyncSettings = ref.watch(appSettingControllerProvider);
    final settings = asyncSettings.valueOrNull;
    if (settings == null) {
      return SettingsSectionScaffold(
        title: strings.language,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return SettingsSectionScaffold(
      title: strings.language,
      body: SegmentedButton<String?>(
        key: const Key('language-segmented'),
        style: segmentTapTargetStyle,
        segments: [
          ButtonSegment(
            value: null,
            label: Text(strings.systemLanguage, key: const Key('language-system')),
          ),
          ButtonSegment(
            value: 'zh',
            label: Text(strings.chinese, key: const Key('language-zh')),
          ),
          ButtonSegment(
            value: 'en',
            label: Text(strings.english, key: const Key('language-en')),
          ),
        ],
        selected: {settings.localeCode.isEmpty ? null : settings.localeCode},
        onSelectionChanged: (selection) => ref
            .read(appSettingControllerProvider.notifier)
            .update((s) => s.copyWith(localeCode: selection.single ?? '')),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/settings/sections/language_section_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/settings/sections/language_section_screen.dart test/features/settings/sections/language_section_screen_test.dart
git commit -m "feat: add language settings sub-page"
```

---

### Task 5: Create WatermarkDefaultsSectionScreen

**Files:**
- Create: `lib/features/settings/sections/watermark_defaults_section_screen.dart`
- Test: `test/features/settings/sections/watermark_defaults_section_screen_test.dart`

**Note:** This is a `ConsumerStatefulWidget` because it needs `_dragValue` and `_fontScaleDragValue` local state for slider drag-follow.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/settings/sections/watermark_defaults_section_screen_test.dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/features/settings/sections/watermark_defaults_section_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await database.getAppSettings();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const WatermarkDefaultsSectionScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('watermark position persists', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('default-position-bottomRight')));
    await tester.pumpAndSettle();
    expect(
      (await database.getAppSettings()).defaultWatermarkPosition,
      'bottomRight',
    );
  });

  testWidgets('opacity slider persists on change end', (tester) async {
    await pumpScreen(tester);
    await tester.timedDrag(
      find.byKey(const Key('opacity-slider')),
      const Offset(500, 0),
      const Duration(milliseconds: 200),
    );
    await tester.pumpAndSettle();
    expect((await database.getAppSettings()).defaultWatermarkOpacity, 0.95);
  });

  testWidgets('font scale slider persists on release', (tester) async {
    await pumpScreen(tester);
    final slider = find.byKey(const Key('default-font-scale-slider'));
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    await tester.timedDrag(
      slider,
      const Offset(500, 0),
      const Duration(milliseconds: 200),
    );
    await tester.pumpAndSettle();
    expect(
      (await database.getAppSettings()).defaultWatermarkFontScale,
      1.60,
    );
  });

  testWidgets('accent swatch selection persists', (tester) async {
    await pumpScreen(tester);
    await tester.ensureVisible(find.byKey(const Key('accent-orange')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('accent-orange')));
    await tester.pumpAndSettle();
    expect(
      (await database.getAppSettings()).defaultWatermarkAccentColorArgb,
      0xffef6c00,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/settings/sections/watermark_defaults_section_screen_test.dart`
Expected: FAIL

- [ ] **Step 3: Write minimal implementation**

Migrate the slider + `_dragValue` logic, position SegmentedButton, and accent ChoiceChip Wrap verbatim from the current `global_settings_screen.dart` lines 332-498. Use `ref.read(appSettingControllerProvider.notifier).update(...)` instead of `_apply`. Create a local `_AccentChoice` widget in this file (or import from a shared location).

```dart
// lib/features/settings/sections/watermark_defaults_section_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitemark/features/settings/app_setting_controller.dart';
import 'package:sitemark/features/settings/settings_section_scaffold.dart';
import 'package:sitemark/l10n/app_strings.dart';

class WatermarkDefaultsSectionScreen extends ConsumerStatefulWidget {
  const WatermarkDefaultsSectionScreen({super.key});

  @override
  ConsumerState<WatermarkDefaultsSectionScreen> createState() =>
      _WatermarkDefaultsSectionScreenState();
}

class _WatermarkDefaultsSectionScreenState
    extends ConsumerState<WatermarkDefaultsSectionScreen> {
  double? _dragValue;
  double? _fontScaleDragValue;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final asyncSettings = ref.watch(appSettingControllerProvider);
    final settings = asyncSettings.valueOrNull;
    if (settings == null) {
      return SettingsSectionScaffold(
        title: strings.newProjectDefaults,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return SettingsSectionScaffold(
      title: strings.newProjectDefaults,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Position
          Text(strings.watermarkPosition,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            key: const Key('default-position-segmented'),
            style: segmentTapTargetStyle,
            segments: [
              ButtonSegment(
                value: 'bottomLeft',
                label: Text(strings.bottomLeft,
                    key: const Key('default-position-bottomLeft')),
              ),
              ButtonSegment(
                value: 'bottomRight',
                label: Text(strings.bottomRight,
                    key: const Key('default-position-bottomRight')),
              ),
            ],
            selected: {settings.defaultWatermarkPosition},
            onSelectionChanged: (selection) => ref
                .read(appSettingControllerProvider.notifier)
                .update((s) =>
                    s.copyWith(defaultWatermarkPosition: selection.single)),
          ),
          const SizedBox(height: 24),
          // Opacity slider (migrate _dragValue logic)
          Builder(builder: (context) {
            final opacity =
                (_dragValue ?? settings.defaultWatermarkOpacity).clamp(0.20, 0.95);
            final percent = (opacity * 100).round();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(strings.watermarkOpacity,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  Text('$percent%'),
                ]),
                Slider(
                  key: const Key('opacity-slider'),
                  value: opacity,
                  min: 0.20,
                  max: 0.95,
                  divisions: 75,
                  label: '$percent%',
                  onChanged: (value) =>
                      setState(() => _dragValue = value),
                  onChangeEnd: (value) {
                    ref
                        .read(appSettingControllerProvider.notifier)
                        .update((s) =>
                            s.copyWith(defaultWatermarkOpacity: value));
                    setState(() => _dragValue = null);
                  },
                ),
              ],
            );
          }),
          const SizedBox(height: 8),
          Text(strings.opacityHint,
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 20),
          // Font scale slider (migrate _fontScaleDragValue logic)
          Builder(builder: (context) {
            final fontScale =
                (_fontScaleDragValue ?? settings.defaultWatermarkFontScale)
                    .clamp(0.80, 1.60);
            final percent = (fontScale * 100).round();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(strings.watermarkFontSize,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  Text('$percent%'),
                ]),
                Slider(
                  key: const Key('default-font-scale-slider'),
                  value: fontScale,
                  min: 0.80,
                  max: 1.60,
                  divisions: 16,
                  label: '$percent%',
                  onChanged: (value) =>
                      setState(() => _fontScaleDragValue = value),
                  onChangeEnd: (value) {
                    ref
                        .read(appSettingControllerProvider.notifier)
                        .update((s) =>
                            s.copyWith(defaultWatermarkFontScale: value));
                    setState(() => _fontScaleDragValue = null);
                  },
                ),
              ],
            );
          }),
          const SizedBox(height: 8),
          Text(strings.fontScaleHint,
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 20),
          // Accent color
          Text(strings.accentColor,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final swatch in accentSwatches)
                _AccentChoice(
                  choiceKey: swatch.key,
                  colorArgb: swatch.argb,
                  selected:
                      settings.defaultWatermarkAccentColorArgb == swatch.argb,
                  onSelected: () => ref
                      .read(appSettingControllerProvider.notifier)
                      .update((s) => s.copyWith(
                          defaultWatermarkAccentColorArgb: swatch.argb)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccentChoice extends StatelessWidget {
  const _AccentChoice({
    required this.choiceKey,
    required this.colorArgb,
    required this.selected,
    required this.onSelected,
  });

  final Key choiceKey;
  final int colorArgb;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      key: choiceKey,
      selected: selected,
      avatar: CircleAvatar(backgroundColor: Color(colorArgb)),
      label: Text(_label(context, colorArgb)),
      onSelected: (_) => onSelected(),
    );
  }

  String _label(BuildContext context, int argb) {
    final strings = AppStrings.of(context);
    if (argb == 0xff37c58b) return strings.green;
    if (argb == 0xff1565c0) return strings.blue;
    if (argb == 0xffef6c00) return strings.orange;
    return '';
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/settings/sections/watermark_defaults_section_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/settings/sections/watermark_defaults_section_screen.dart test/features/settings/sections/watermark_defaults_section_screen_test.dart
git commit -m "feat: add watermark defaults settings sub-page"
```

---

### Task 6: Create StorageSectionScreen

**Files:**
- Create: `lib/features/settings/sections/storage_section_screen.dart`
- Test: `test/features/settings/sections/storage_section_screen_test.dart`

Migrate `_StorageSection`, `_StorageRow`, the clear-exports dialog, and refresh logic. This screen does NOT use `AppSettingController` — it uses `storageUsageProvider`.

- [ ] **Step 1: Write the failing test** (migrate storage-related assertions from `global_settings_screen_test.dart`)

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Write minimal implementation**

Migrate `_StorageSection` + `_StorageRow` + `_clearLocalExports` verbatim into a `ConsumerStatefulWidget`. The screen watches `storageUsageProvider` and calls `ref.invalidate(storageUsageProvider)` on refresh.

- [ ] **Step 4: Run test to verify it passes**

- [ ] **Step 5: Commit**

```bash
git add lib/features/settings/sections/storage_section_screen.dart test/features/settings/sections/storage_section_screen_test.dart
git commit -m "feat: add storage settings sub-page"
```

---

### Task 7: Create LocationSectionScreen

**Files:**
- Create: `lib/features/settings/sections/location_section_screen.dart`
- Test: `test/features/settings/sections/location_section_screen_test.dart`

Migrate `_LocationPermissionTile` + `WidgetsBindingObserver` resumed refresh + `_loadPermission` + `_onLocationTapped`.

- [ ] **Step 1-5:** TDD cycle as above.

---

### Task 8: Create NotificationSectionScreen

**Files:**
- Create: `lib/features/settings/sections/notification_section_screen.dart`
- Test: `test/features/settings/sections/notification_section_screen_test.dart`

Migrate the completion notification `SwitchListTile` + `_onCompletionNotificationChanged` permission request logic. Uses `appSettingControllerProvider` for the `completionNotificationsEnabled` field.

- [ ] **Step 1-5:** TDD cycle as above.

---

### Task 9: Create AboutSectionScreen

**Files:**
- Create: `lib/features/settings/sections/about_section_screen.dart`
- Test: `test/features/settings/sections/about_section_screen_test.dart`

Migrate `_AboutSection` + `_loadPackageInfo` + `_openRepository`. Uses `PackageInfo.fromPlatform()` and `externalLinkServiceProvider`.

- [ ] **Step 1-5:** TDD cycle as above.

---

### Task 10: Rewrite GlobalSettingsScreen as menu

**Files:**
- Modify: `lib/features/settings/global_settings_screen.dart` (rewrite from 805 lines to ~80 lines)
- Test: `test/features/settings/global_settings_screen_test.dart` (rewrite)

- [ ] **Step 1: Write the failing test**

```dart
// Verify 7 ListTile entries exist and navigate correctly
testWidgets('shows 7 settings entries', (tester) async {
  await pumpSettings(tester);
  expect(find.text('新建项目水印默认值'), findsOneWidget);
  expect(find.text('外观'), findsOneWidget);
  expect(find.text('语言'), findsOneWidget);
  expect(find.text('储存'), findsOneWidget);
  expect(find.text('定位'), findsOneWidget);
  expect(find.text('完成通知'), findsOneWidget);
  expect(find.text('关于'), findsOneWidget);
});

testWidgets('tapping appearance navigates to AppearanceSectionScreen', (tester) async {
  await pumpSettings(tester);
  await tester.tap(find.text('外观'));
  await tester.pumpAndSettle();
  expect(find.byType(AppearanceSectionScreen), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Rewrite GlobalSettingsScreen**

```dart
// lib/features/settings/global_settings_screen.dart (rewrite)
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/l10n/app_strings.dart';

class GlobalSettingsScreen extends StatelessWidget {
  const GlobalSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final entries = <(Icon, String, String)>[
      (const Icon(Icons.water_drop_outlined), strings.newProjectDefaults, '/settings/watermark'),
      (const Icon(Icons.palette_outlined), strings.appearance, '/settings/appearance'),
      (const Icon(Icons.language), strings.language, '/settings/language'),
      (const Icon(Icons.storage_outlined), strings.storageScope, '/settings/storage'),
      (const Icon(Icons.location_on_outlined), strings.locationLabel, '/settings/location'),
      (const Icon(Icons.notifications_outlined), strings.completionNotificationTitle, '/settings/notification'),
      (const Icon(Icons.info_outline), strings.about, '/settings/about'),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(strings.settings)),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final (icon, title, route) = entries[index];
          return Card(
            child: ListTile(
              leading: icon,
              title: Text(title),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(route),
            ),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

- [ ] **Step 5: Commit**

```bash
git add lib/features/settings/global_settings_screen.dart test/features/settings/global_settings_screen_test.dart
git commit -m "feat: rewrite settings screen as secondary menu"
```

---

### Task 11: Update routes in app.dart

**Files:**
- Modify: `lib/app.dart` (lines 273-277 — add nested GoRoutes)

- [ ] **Step 1: Update routes**

Replace the single `settings` GoRoute with a nested structure:

```dart
GoRoute(
  path: 'settings',
  pageBuilder: (context, state) =>
      _fadeThroughPage(state, const GlobalSettingsScreen()),
  routes: [
    GoRoute(
      path: 'watermark',
      pageBuilder: (context, state) =>
          _sharedAxisPage(state, const WatermarkDefaultsSectionScreen()),
    ),
    GoRoute(
      path: 'appearance',
      pageBuilder: (context, state) =>
          _sharedAxisPage(state, const AppearanceSectionScreen()),
    ),
    GoRoute(
      path: 'language',
      pageBuilder: (context, state) =>
          _sharedAxisPage(state, const LanguageSectionScreen()),
    ),
    GoRoute(
      path: 'storage',
      pageBuilder: (context, state) =>
          _sharedAxisPage(state, const StorageSectionScreen()),
    ),
    GoRoute(
      path: 'location',
      pageBuilder: (context, state) =>
          _sharedAxisPage(state, const LocationSectionScreen()),
    ),
    GoRoute(
      path: 'notification',
      pageBuilder: (context, state) =>
          _sharedAxisPage(state, const NotificationSectionScreen()),
    ),
    GoRoute(
      path: 'about',
      pageBuilder: (context, state) =>
          _sharedAxisPage(state, const AboutSectionScreen()),
    ),
  ],
),
```

Add imports for all 7 section screens at the top of `app.dart`.

- [ ] **Step 2: Run flutter analyze**

Run: `flutter analyze`
Expected: No issues

- [ ] **Step 3: Run all tests**

Run: `flutter test`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add lib/app.dart
git commit -m "feat: add nested settings routes"
```

---

### Task 12: Full regression and cleanup

- [ ] **Step 1: Run flutter analyze**

Run: `flutter analyze`
Expected: 0 issues

- [ ] **Step 2: Run full test suite**

Run: `flutter test`
Expected: All tests pass

- [ ] **Step 3: Run APK build**

Run: `flutter build apk --debug`
Expected: Success

- [ ] **Step 4: Delete old test file if fully migrated**

If `test/features/settings/global_settings_screen_test.dart` old assertions are all migrated to section tests, ensure no duplicate coverage remains.

- [ ] **Step 5: Commit any cleanup**

```bash
git add -A
git commit -m "chore: settings refactor regression cleanup"
```

---

### Task 13: Push to PR #14 branch

- [ ] **Step 1: Ensure on correct branch**

```bash
git checkout fix/capture-fab-animation-overflow
```

- [ ] **Step 2: Push**

```bash
git -c http.proxy=http://127.0.0.1:6789 -c https.proxy=http://127.0.0.1:6789 push
```

- [ ] **Step 3: Verify PR #14 is updated**
