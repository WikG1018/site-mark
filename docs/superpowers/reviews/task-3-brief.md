# Task 3: Create AppearanceSectionScreen

**Source:** `docs/superpowers/plans/2026-07-25-settings-secondary-menu.md` (Task 3)

## Goal
Migrate the theme + dynamic-color section from `global_settings_screen.dart` into its own sub-page that reads/writes via `appSettingControllerProvider`.

## Files
- Create: `lib/features/settings/sections/appearance_section_screen.dart`
- Test: `test/features/settings/sections/appearance_section_screen_test.dart`

## Interfaces
- Consumes: `appSettingControllerProvider` (from Task 1), `segmentTapTargetStyle` + `SettingsSectionScaffold` (from Task 2), `AppStrings`
- Produces: `AppearanceSectionScreen` widget (used by Task 11 routes)

## TDD steps

### Step 1: Write the failing test

```dart
// test/features/settings/sections/appearance_section_screen_test.dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
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

**NOTE:** the plan's test imports `package:sitemark/data/app_database.dart` for `databaseProvider`, but `databaseProvider` is actually defined in `package:sitemark/app.dart` (verified in Task 1). The test above imports `package:sitemark/app.dart` instead. Use this corrected import.

### Step 2: Run test to verify it fails
Run: `flutter test test/features/settings/sections/appearance_section_screen_test.dart`
Expected: FAIL — file does not exist.

### Step 3: Write minimal implementation

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

### Step 4: Run test to verify it passes
Run: `flutter test test/features/settings/sections/appearance_section_screen_test.dart`
Expected: PASS (2/2)

### Step 5: Commit
```
git add lib/features/settings/sections/appearance_section_screen.dart test/features/settings/sections/appearance_section_screen_test.dart
git commit -m "feat: add appearance settings sub-page"
```

## Context for the implementer
- `databaseProvider` is in `package:sitemark/app.dart` (NOT `app_database.dart` as the plan states). Both the test and impl must import from `app.dart` for `databaseProvider`. The impl also needs `app_database.dart` for the `AppSetting` type — but `AppSetting` is re-exported from `app.dart` too? **Verify:** if `app.dart` exports `app_database.dart`, then a single `import 'package:sitemark/app.dart'` suffices in the test. If not, the test needs both imports. Check `lib/app.dart` for `export 'data/app_database.dart';`. (Task 1's test imported only `package:sitemark/app.dart` and compiled, so `app.dart` does export `AppDatabase`/`AppSetting`/`databaseProvider`.)
- The l10n keys `appearance`, `theme`, `systemTheme`, `lightTheme`, `darkTheme`, `dynamicColorTitle`, `dynamicColorSubtitle` all exist (verified in existing `global_settings_screen.dart` lines 251–293).
- `AppSetting.copyWith(themeMode: ...)` and `AppSetting.copyWith(useDynamicColor: ...)` are valid (Task 1 test used `copyWith(themeMode:)`; existing screen uses `useDynamicColor`).
- The `update` method on `AppSettingController` returns `Future<AppSetting>` (Riverpod 3.x override). Calling it without `await` inside `onSelectionChanged`/`onChanged` is fine — fire-and-forget optimistic update is the intended pattern.
- Do NOT modify `global_settings_screen.dart` (Task 10 handles that).

## Global Constraints (binding)
- All existing widget test assertions must pass after refactor (234+ tests).
- l10n keys are unchanged — reuse existing `AppStrings` keys.
- No new dependencies; no schema changes.
- Commit messages in English; code comments follow user language (Chinese for domain logic, English for technical).
