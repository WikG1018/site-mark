# Task 6: Create StorageSectionScreen

**Source:** `docs/superpowers/plans/2026-07-25-settings-secondary-menu.md` (Task 6)

## Goal
Migrate the storage section (`_StorageSection` + `_StorageRow` + `_clearLocalExports` dialog/logic) from `global_settings_screen.dart` into its own sub-page. This screen does NOT use `appSettingControllerProvider` — it watches `storageUsageProvider` and manages refresh/clear via `storageUsageServiceProvider`.

## Files
- Create: `lib/features/settings/sections/storage_section_screen.dart`
- Test: `test/features/settings/sections/storage_section_screen_test.dart`

## Interfaces
- Consumes: `storageUsageProvider` + `storageUsageServiceProvider` (from `lib/app.dart`), `AppStrings`, `AppStorageUsage` + `formatStorageBytes` (from `package:sitemark/domain/app_storage_usage.dart`), `ClearExportsResult` (from `package:sitemark/workflow/app_storage_service.dart`), `go_router` for `context.go('/records')`
- Produces: `StorageSectionScreen` widget (used by Task 11 routes)

## Context for the implementer
- The existing `global_settings_screen.dart:535-656` defines `_StorageSection` (StatelessWidget) and `_StorageRow` (StatelessWidget). The existing `global_settings_screen.dart:196-233` defines `_clearLocalExports`. Migrate these verbatim, replacing `ref` access patterns as noted below.
- The storage screen has a refresh `IconButton` that doesn't fit `SettingsSectionScaffold`'s `{title, body}` API, so this screen builds its own `Scaffold` (do NOT use `SettingsSectionScaffold`). This is an intentional, plan-permitted deviation (Task 6 plan does not list `SettingsSectionScaffold` as a consumed interface).
- `onManageRecords` navigates to `/records` via `context.go('/records')` (existing behavior at `global_settings_screen.dart:503`).
- l10n keys (all verified in existing screen): `storageScope`, `refreshStorage`, `storageTotal`, `privateOriginals`, `privateWatermarked`, `localExportFiles`, `databaseAndOther`, `manageRecords`, `clearLocalExports`, `clearLocalExportsHint`, `storageLoadFailed`, `retry`, `clearLocalExportsPrompt`, `cancel`, `clear`, `localExportsCleared`, `clearLocalExportsFailed`.

## TDD steps

### Step 1: Write the failing test

```dart
// test/features/settings/sections/storage_section_screen_test.dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/app_storage_usage.dart';
import 'package:sitemark/features/settings/sections/storage_section_screen.dart';
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

  Future<void> pumpScreen(
    WidgetTester tester, {
    required StorageUsageService storage,
  }) async {
    await database.getAppSettings();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          storageUsageServiceProvider.overrideWithValue(storage),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const StorageSectionScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('storage section shows totals, refreshes, and clears exports', (
    tester,
  ) async {
    final storage = _RecordingStorageUsageService([
      const AppStorageUsage(
        originalBytes: 1024 * 1024,
        renderedBytes: 2 * 1024 * 1024,
        exportBytes: 3 * 1024 * 1024,
        databaseAndOtherBytes: 4 * 1024 * 1024,
      ),
      const AppStorageUsage(
        originalBytes: 1024 * 1024,
        renderedBytes: 2 * 1024 * 1024,
        exportBytes: 0,
        databaseAndOtherBytes: 4 * 1024 * 1024,
      ),
    ]);
    await pumpScreen(tester, storage: storage);

    expect(find.text('SiteMark 应用内数据占用（不含系统相册）'), findsOneWidget);
    expect(find.text('10 MB'), findsOneWidget);
    expect(find.text('1 MB'), findsOneWidget);
    expect(find.text('2 MB'), findsOneWidget);
    expect(find.text('3 MB'), findsOneWidget);
    expect(find.text('4 MB'), findsOneWidget);

    await tester.tap(find.byKey(const Key('storage-refresh')));
    await tester.pumpAndSettle();
    expect(storage.loadCount, 2);

    // Restore a non-zero export value to exercise the destructive action.
    storage.values.add(
      const AppStorageUsage(
        originalBytes: 1024 * 1024,
        renderedBytes: 2 * 1024 * 1024,
        exportBytes: 3 * 1024 * 1024,
        databaseAndOtherBytes: 4 * 1024 * 1024,
      ),
    );
    await tester.tap(find.byKey(const Key('storage-refresh')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clear-local-exports')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-clear-exports')));
    await tester.pumpAndSettle();
    expect(storage.clearCount, 1);
    expect(storage.loadCount, 4);
  });

  testWidgets('storage error state retries successfully', (tester) async {
    final storage = _RetryingStorageUsageService();
    await pumpScreen(tester, storage: storage);
    expect(find.text('无法读取存储占用'), findsOneWidget);

    await tester.tap(find.byKey(const Key('retry-storage-load')));
    await tester.pumpAndSettle();

    expect(storage.loadCount, 2);
    expect(find.text('无法读取存储占用'), findsNothing);
  });

  testWidgets('storage manage-records entry opens the records route', (
    tester,
  ) async {
    await database.getAppSettings();
    final router = GoRouter(
      initialLocation: '/settings/storage',
      routes: [
        GoRoute(
          path: '/settings',
          builder: (context, state) => const Scaffold(body: Text('settings')),
          routes: [
            GoRoute(
              path: 'storage',
              builder: (context, state) => const StorageSectionScreen(),
            ),
            GoRoute(
              path: 'records',
              builder: (context, state) =>
                  const Scaffold(body: Text('records destination')),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          storageUsageServiceProvider.overrideWithValue(
            _RecordingStorageUsageService(const [
              AppStorageUsage(
                originalBytes: 0,
                renderedBytes: 0,
                exportBytes: 0,
                databaseAndOtherBytes: 0,
              ),
            ]),
          ),
        ],
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
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manage-storage-records')));
    await tester.pumpAndSettle();

    expect(find.text('records destination'), findsOneWidget);
  });
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

class _RetryingStorageUsageService implements StorageUsageService {
  int loadCount = 0;

  @override
  Future<AppStorageUsage> load() async {
    loadCount++;
    if (loadCount == 1) throw StateError('read failed');
    return const AppStorageUsage(
      originalBytes: 0,
      renderedBytes: 0,
      exportBytes: 0,
      databaseAndOtherBytes: 0,
    );
  }

  @override
  Future<ClearExportsResult> clearExports() async {
    return const ClearExportsResult(deletedFiles: 0, freedBytes: 0);
  }
}
```

### Step 2: Run test to verify it fails
Run: `flutter test test/features/settings/sections/storage_section_screen_test.dart`
Expected: FAIL — file does not exist.

### Step 3: Write minimal implementation

```dart
// lib/features/settings/sections/storage_section_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/domain/app_storage_usage.dart';
import 'package:sitemark/l10n/app_strings.dart';

class StorageSectionScreen extends ConsumerStatefulWidget {
  const StorageSectionScreen({super.key});

  @override
  ConsumerState<StorageSectionScreen> createState() =>
      _StorageSectionScreenState();
}

class _StorageSectionScreenState extends ConsumerState<StorageSectionScreen> {
  Future<void> _clearLocalExports(BuildContext context) async {
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.clearLocalExports),
        content: Text(strings.clearLocalExportsPrompt),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            key: const Key('confirm-clear-exports'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.clear),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final result = await ref.read(storageUsageServiceProvider).clearExports();
      ref.invalidate(storageUsageProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.localExportsCleared(result.deletedFiles)),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.clearLocalExportsFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final usage = ref.watch(storageUsageProvider);
    return Scaffold(
      appBar: AppBar(title: Text(strings.storageScope)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Column(
            key: const Key('storage-section'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Spacer(),
                  IconButton(
                    key: const Key('storage-refresh'),
                    onPressed: () => ref.invalidate(storageUsageProvider),
                    tooltip: strings.refreshStorage,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              usage.when(
                data: (value) => Column(
                  children: [
                    Card(
                      child: Column(
                        children: [
                          _StorageRow(
                            label: strings.storageTotal,
                            bytes: value.totalBytes,
                            emphasized: true,
                          ),
                          const Divider(height: 1),
                          _StorageRow(
                            label: strings.privateOriginals,
                            bytes: value.originalBytes,
                          ),
                          _StorageRow(
                            label: strings.privateWatermarked,
                            bytes: value.renderedBytes,
                          ),
                          _StorageRow(
                            label: strings.localExportFiles,
                            bytes: value.exportBytes,
                          ),
                          _StorageRow(
                            label: strings.databaseAndOther,
                            bytes: value.databaseAndOtherBytes,
                          ),
                        ],
                      ),
                    ),
                    ListTile(
                      key: const Key('manage-storage-records'),
                      leading: const Icon(Icons.photo_library_outlined),
                      title: Text(strings.manageRecords),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.go('/records'),
                    ),
                    ListTile(
                      key: const Key('clear-local-exports'),
                      leading: const Icon(Icons.delete_sweep_outlined),
                      title: Text(strings.clearLocalExports),
                      subtitle: Text(strings.clearLocalExportsHint),
                      onTap: value.exportBytes == 0
                          ? null
                          : () => _clearLocalExports(context),
                    ),
                  ],
                ),
                error: (_, _) => Column(
                  children: [
                    Text(strings.storageLoadFailed),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const Key('retry-storage-load'),
                      onPressed: () => ref.invalidate(storageUsageProvider),
                      icon: const Icon(Icons.refresh),
                      label: Text(strings.retry),
                    ),
                  ],
                ),
                loading: () => const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StorageRow extends StatelessWidget {
  const _StorageRow({
    required this.label,
    required this.bytes,
    this.emphasized = false,
  });

  final String label;
  final int bytes;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = emphasized ? Theme.of(context).textTheme.titleMedium : null;
    return ListTile(
      dense: true,
      title: Text(label, style: style),
      trailing: Text(formatStorageBytes(bytes), style: style),
    );
  }
}
```

### Step 4: Run test to verify it passes
Run: `flutter test test/features/settings/sections/storage_section_screen_test.dart`
Expected: PASS (3/3)

### Step 5: Commit
```
git add lib/features/settings/sections/storage_section_screen.dart test/features/settings/sections/storage_section_screen_test.dart
git commit -m "feat: add storage settings sub-page"
```

## Notes
- The screen does NOT use `SettingsSectionScaffold` because it has a refresh `IconButton` that doesn't fit the shared scaffold's `{title, body}` API. It builds its own `Scaffold` + `AppBar` + `ListView`. This is plan-permitted (Task 6 does not list `SettingsSectionScaffold` as consumed).
- The `_SectionHeader` from the existing `_StorageSection` is dropped — the AppBar now carries the `storageScope` title, so the body doesn't repeat it. The refresh button moves into a right-aligned `Row` at the top of the body.
- The existing `global_settings_screen_test.dart` "storage usage stays cached after settings disposal until invalidated" test (line 315) is a pure provider test that does NOT depend on the screen — leave it in the old test file; Task 12 will triage.
- The `manage-records` test uses a nested GoRouter (`/settings/storage` → `StorageSectionScreen`, `/settings/records` → destination). This matches how Task 11 will wire the real routes.
- Do NOT modify `global_settings_screen.dart`.

## Global Constraints (binding)
- All existing widget test assertions must pass after refactor (234+ tests).
- l10n keys are unchanged — reuse existing `AppStrings` keys.
- No new dependencies; no schema changes.
- Commit messages in English; code comments follow user language (Chinese for domain logic, English for technical).
