# Task 4: Create LanguageSectionScreen

**Source:** `docs/superpowers/plans/2026-07-25-settings-secondary-menu.md` (Task 4)

## Goal
Migrate the language selection section into its own sub-page using `appSettingControllerProvider`.

## Files
- Create: `lib/features/settings/sections/language_section_screen.dart`
- Test: `test/features/settings/sections/language_section_screen_test.dart`

## Interfaces
- Consumes: `appSettingControllerProvider` (Task 1), `SettingsSectionScaffold` + `segmentTapTargetStyle` (Task 2), `AppStrings`
- Produces: `LanguageSectionScreen` widget (used by Task 11 routes)

## Pre-applied corrections (from Task 3 findings)
1. **`valueOrNull` → `.value`**: Riverpod 3.3.2's `AsyncValue<T>` does not expose `valueOrNull`. Use `asyncSettings.value` (returns `T?`, null on loading/error — behaviorally equivalent). This matches existing code at `lib/app.dart:459` and `app_setting_controller.dart:30`.
2. **Dual import in test**: `lib/app.dart` does NOT `export 'data/app_database.dart'`. The test references `AppDatabase` directly, so it needs BOTH `package:sitemark/app.dart` (for `databaseProvider`) AND `package:sitemark/data/app_database.dart` (for `AppDatabase` type).

## TDD steps

### Step 1: Write the failing test

```dart
// test/features/settings/sections/language_section_screen_test.dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
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

### Step 2: Run test to verify it fails
Run: `flutter test test/features/settings/sections/language_section_screen_test.dart`
Expected: FAIL — file does not exist.

### Step 3: Write minimal implementation

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
    final settings = asyncSettings.value;
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

### Step 4: Run test to verify it passes
Run: `flutter test test/features/settings/sections/language_section_screen_test.dart`
Expected: PASS (1/1)

### Step 5: Commit
```
git add lib/features/settings/sections/language_section_screen.dart test/features/settings/sections/language_section_screen_test.dart
git commit -m "feat: add language settings sub-page"
```

## Context for the implementer
- l10n keys `language`, `systemLanguage`, `chinese`, `english` all exist (verified in `global_settings_screen.dart` lines 301–322).
- **Behavioral note (not a bug):** The existing `global_settings_screen.dart:325` uses `selected: {settings.localeCode}`, which leaves NO segment highlighted when `localeCode` is empty (system default). The plan's code uses `selected: {settings.localeCode.isEmpty ? null : settings.localeCode}`, which correctly highlights the "system" segment when localeCode is empty. This is an intentional improvement from the plan — keep the plan's version.
- `AppSetting.copyWith(localeCode: ...)` is valid (existing screen uses it at line 328).
- `update()` returns `Future<AppSetting>`; fire-and-forget in `onSelectionChanged` is the intended pattern.
- Do NOT modify `global_settings_screen.dart` (Task 10 handles that).

## Global Constraints (binding)
- All existing widget test assertions must pass after refactor (234+ tests).
- l10n keys are unchanged — reuse existing `AppStrings` keys.
- No new dependencies; no schema changes.
- Commit messages in English; code comments follow user language (Chinese for domain logic, English for technical).
