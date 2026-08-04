# Task 10: Rewrite GlobalSettingsScreen as menu

**Source:** `docs/superpowers/plans/2026-07-25-settings-secondary-menu.md` (Task 10)

## Goal
Rewrite the monolithic 805-line `GlobalSettingsScreen` into a ~80-line 7-entry menu. Each `ListTile` navigates to its dedicated sub-page via `context.go('/settings/<section>')`. The old per-section tests are removed because they are now covered by the section-specific test files (Tasks 3-9).

## Files
- Modify: `lib/features/settings/global_settings_screen.dart` (rewrite from 805 lines to ~80 lines)
- Modify: `test/features/settings/global_settings_screen_test.dart` (rewrite — remove old per-section tests, keep 2 generic tests, add 1 new menu test)

## Interfaces
- Consumes: `AppStrings`, `go_router` (`context.go`)
- Produces: rewritten `GlobalSettingsScreen` widget (a 7-entry menu)

## Context for the implementer
- The existing `global_settings_screen.dart` (805 lines) defines a monolithic settings screen with 7 sections: appearance, language, watermark defaults, storage, location, notification, about. Each section has been migrated to its own sub-page in Tasks 3-9.
- The existing `global_settings_screen_test.dart` has 14 tests that test the OLD integrated screen. Most of these tests are now redundant because they are covered by the section-specific test files. Specifically:
  - Theme/language/dynamic-color/watermark tests (lines 87-175) → covered by Tasks 3, 4, 5
  - Notification tests (lines 177-225) → covered by Task 8
  - About tests (lines 227-237, 421-457) → covered by Task 9
  - Storage tests (lines 239-419) → covered by Task 6
  - Location tests (lines 459-518) → covered by Task 7
- KEEP these 2 tests (they are NOT covered by section tests):
  - "settings route is reachable from the app shell" (lines 520-571) — pure routing test
  - "storage usage stays cached after settings disposal until invalidated" (lines 315-355) — pure provider caching test, not screen-bound
- ADD 1 new test: "shows 7 settings entries" — verifies all 7 menu ListTiles render.
- The 7 menu entries map to l10n keys:
  - `newProjectDefaults` → '/settings/watermark'
  - `appearance` → '/settings/appearance'
  - `language` → '/settings/language'
  - `storageScope` → '/settings/storage'
  - `locationLabel` → '/settings/location'
  - `completionNotificationTitle` → '/settings/notification'
  - `about` → '/settings/about'
- The new screen is a `StatelessWidget` (no Riverpod, no Consumer) because it only renders static menu entries. The `context.go()` calls happen in `onTap`.
- The `Card` + `ListTile` pattern matches the plan's Step 3 code block.
- DO NOT add unused imports — only `flutter/material.dart`, `go_router`, and `app_strings.dart` are needed.

## TDD steps

### Step 1: Write the failing test (rewrite the test file)

Replace the entire contents of `test/features/settings/global_settings_screen_test.dart` with:

```dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/app_storage_usage.dart';
import 'package:sitemark/features/settings/global_settings_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/workflow/app_storage_service.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  /// Pumps the [GlobalSettingsScreen] in a localized Material harness wired to
  /// the in-memory [database] via Riverpod overrides.
  Future<void> pumpSettings(WidgetTester tester) async {
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
          home: const GlobalSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows 7 settings entries', (tester) async {
    await pumpSettings(tester);
    final strings = AppStrings.of(Locale('zh') as BuildContext);
    // Use a localized harness so the strings resolve deterministically.
    expect(find.text('新建项目水印默认值'), findsOneWidget);
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('语言'), findsOneWidget);
    expect(find.text('储存'), findsOneWidget);
    expect(find.text('定位'), findsOneWidget);
    expect(find.text('完成通知'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
  });

  testWidgets('settings route is reachable from the app shell', (tester) async {
    await database.getAppSettings();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
          routes: [
            GoRoute(
              path: 'settings',
              builder: (context, state) => const GlobalSettingsScreen(),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp.router(
          locale: const Locale('zh'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: router,
        ),
      ),
    );
    router.go('/settings');
    await tester.pumpAndSettle();

    expect(find.byType(GlobalSettingsScreen), findsOneWidget);
  });

  test(
    'storage usage stays cached after settings disposal until invalidated',
    () async {
      final storage = _RecordingStorageUsageService(const [
        AppStorageUsage(
          originalBytes: 1,
          renderedBytes: 2,
          exportBytes: 3,
          databaseAndOtherBytes: 4,
        ),
      ]);
      final container = ProviderContainer(
        overrides: [storageUsageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);

      final firstListener = container.listen(
        storageUsageProvider,
        (_, _) {},
        fireImmediately: true,
      );
      await container.read(storageUsageProvider.future);
      expect(storage.loadCount, 1);

      firstListener.close();
      await container.pump();

      final reenteredListener = container.listen(
        storageUsageProvider,
        (_, _) {},
        fireImmediately: true,
      );
      await container.read(storageUsageProvider.future);
      expect(storage.loadCount, 1);

      container.invalidate(storageUsageProvider);
      await container.read(storageUsageProvider.future);
      expect(storage.loadCount, 2);
      reenteredListener.close();
    },
  );
}

class _RecordingStorageUsageService implements StorageUsageService {
  _RecordingStorageUsageService(this.values);

  final List<AppStorageUsage> values;
  int loadCount = 0;
  int clearCount = 0;

  @override
  Future<AppStorageUsage> load() async {
    final index = loadCount < values.length ? loadCount : values.length - 1;
    loadCount++;
    return values[index];
  }

  @override
  Future<ClearExportsResult> clearExports() async {
    clearCount++;
    final current = values.last;
    values.add(
      AppStorageUsage(
        originalBytes: current.originalBytes,
        renderedBytes: current.renderedBytes,
        exportBytes: 0,
        databaseAndOtherBytes: current.databaseAndOtherBytes,
      ),
    );
    return const ClearExportsResult(deletedFiles: 1, freedBytes: 1024);
  }
}
```

**IMPORTANT**: The first test `shows 7 settings entries` calls `AppStrings.of(Locale('zh') as BuildContext)` — this is INVALID. Remove that line; it was a mistake. The test should only use `find.text(...)` calls with hardcoded Chinese strings (which match because `MaterialApp.locale = Locale('zh')`). The corrected first test is:

```dart
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
```

So the final test file does NOT have that erroneous line. Use the corrected version above.

### Step 2: Run test to verify it fails
Run: `flutter test test/features/settings/global_settings_screen_test.dart`
Expected: FAIL — the old `GlobalSettingsScreen` still has the old structure, so `shows 7 settings entries` will fail (the 7 ListTiles are not present yet). The other 2 tests should still pass.

### Step 3: Rewrite GlobalSettingsScreen

Replace the entire contents of `lib/features/settings/global_settings_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/l10n/app_strings.dart';

/// 二级菜单入口的设置页。原 805 行的单体屏幕已拆分为 7 个独立子页面，
/// 通过 [context.go] 跳转到对应的二级路由（路由在 `lib/app.dart` 中由
/// Task 11 注册）。
class GlobalSettingsScreen extends StatelessWidget {
  const GlobalSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final entries = <(IconData, String, String)>[
      (Icons.water_drop_outlined, strings.newProjectDefaults, '/settings/watermark'),
      (Icons.palette_outlined, strings.appearance, '/settings/appearance'),
      (Icons.language, strings.language, '/settings/language'),
      (Icons.storage_outlined, strings.storageScope, '/settings/storage'),
      (Icons.location_on_outlined, strings.locationLabel, '/settings/location'),
      (Icons.notifications_outlined, strings.completionNotificationTitle, '/settings/notification'),
      (Icons.info_outline, strings.about, '/settings/about'),
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
              leading: Icon(icon),
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

### Step 4: Run test to verify it passes
Run: `flutter test test/features/settings/global_settings_screen_test.dart`
Expected: PASS (3/3)

### Step 5: Run flutter analyze
Run: `flutter analyze lib/features/settings/global_settings_screen.dart test/features/settings/global_settings_screen_test.dart`
Expected: No issues.

### Step 6: Commit
```
git add lib/features/settings/global_settings_screen.dart test/features/settings/global_settings_screen_test.dart
git commit -m "feat: rewrite settings screen as secondary menu"
```

## Notes
- The new screen is a `StatelessWidget` — no Riverpod needed because it only renders static entries.
- The old `_SettingsTestPlatformServices`, `_RecordingExternalLinkService`, `_RetryingStorageUsageService`, `_FakeCompletionNotificationService` test doubles are REMOVED from this test file. They are now duplicated in the section-specific test files (Tasks 6-9). Only `_RecordingStorageUsageService` remains because it's needed for the pure-provider caching test.
- DO NOT delete the section-specific test files. They are the new home for the migrated tests.
- The 7 routes (`/settings/watermark`, `/settings/appearance`, etc.) do NOT exist yet — Task 11 will add them to `lib/app.dart`. The `shows 7 settings entries` test only verifies the menu renders, NOT navigation (navigation is verified in the routing test for `/settings` only).
- The `tapping appearance navigates to AppearanceSectionScreen` test mentioned in the plan is OMITTED because navigation requires Task 11's routes to be wired. The plan's Step 1 test code included it, but it cannot pass until Task 11 completes. Task 11's regression suite will cover navigation.

## Global Constraints (binding)
- All existing widget test assertions must pass after refactor (234+ tests).
- l10n keys are unchanged — reuse existing `AppStrings` keys.
- No new dependencies; no schema changes.
- Commit messages in English; code comments in Chinese for domain logic, English for technical.
