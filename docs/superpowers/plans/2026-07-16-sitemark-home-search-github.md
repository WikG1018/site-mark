# SiteMark Home Search and GitHub Link Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add fast local project-name search to the home page and make About display and open the full SiteMark GitHub repository URL in the system browser.

**Architecture:** Filter the existing watched project list in widget state without adding a database field or query. Wrap `url_launcher` behind an injectable `ExternalLinkService` so About remains testable and always launches HTTPS with external-application mode.

**Tech Stack:** Flutter Material 3, Riverpod, url_launcher 6.3.2, existing `AppStrings` localization.

## Global Constraints

- Complete the foundation plan before this plan; this plan may run after the other feature plans because it has no schema dependency beyond the shared app shell.
- Search matches project name only, trims the query, uses direct contains matching for Chinese, and ignores case for Latin text.
- Empty query displays all projects and retains the existing updated-at ordering.
- Search is local and adds no network call, field, permission, or analytics.
- Chinese label is “GitHub 代码仓库”; English label is “GitHub Repository”.
- Display and open exactly `https://github.com/WikG1018/site-mark`.
- Open the system browser, not an embedded web view.
- Use `url_launcher: ^6.3.2`; do not use `canLaunchUrl` as a prerequisite—call `launchUrl` and handle `false`/exception.

---

## File Map

- Modify: `lib/features/projects/project_list_screen.dart` — search state and filtered project list.
- Create: `test/features/projects/project_list_screen_test.dart` — search interactions.
- Create: `lib/domain/app_links.dart`, `lib/platform/external_link_service.dart`, `test/platform/external_link_service_test.dart`.
- Modify: `lib/features/settings/global_settings_screen.dart` — clickable full repository URL and failure feedback.
- Modify: `lib/l10n/app_strings.dart` — search and GitHub copy.
- Modify: `lib/app.dart` — external-link provider/test override.
- Modify: `pubspec.yaml`, `pubspec.lock` — url_launcher 6.3.2.
- Modify: `test/features/settings/global_settings_screen_test.dart`, `test/widget_test.dart`.

### Task 1: Add Local Project Search to Home

**Files:**
- Modify: `lib/features/projects/project_list_screen.dart`
- Create: `test/features/projects/project_list_screen_test.dart`
- Modify: `lib/l10n/app_strings.dart`

**Interfaces:**
- Produces: home AppBar search mode with query, clear, and exit controls.

- [ ] **Step 1: Write failing search tests**

Create an in-memory database with `东区厂房改造`, `西区管线整改`, and `Warehouse Alpha`, then pump `ProjectListScreen` in the localized/provider harness.

```dart
late AppDatabase database;

Future<void> pumpProjects(WidgetTester tester) async {
  database = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(database.close);
  await database.createProject(id: 'east', name: '东区厂房改造');
  await database.createProject(id: 'west', name: '西区管线整改');
  await database.createProject(id: 'warehouse', name: 'Warehouse Alpha');
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
        home: const ProjectListScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
```

```dart
testWidgets('home search filters by Chinese project name', (tester) async {
  await pumpProjects(tester);
  await tester.tap(find.byKey(const Key('search-projects')));
  await tester.enterText(find.byKey(const Key('project-search-field')), '东区');
  await tester.pump();
  expect(find.text('东区厂房改造'), findsOneWidget);
  expect(find.text('西区管线整改'), findsNothing);
});

testWidgets('home search ignores Latin case and clears', (tester) async {
  await pumpProjects(tester);
  await tester.tap(find.byKey(const Key('search-projects')));
  await tester.enterText(find.byKey(const Key('project-search-field')), 'warehouse alpha');
  await tester.pump();
  expect(find.text('Warehouse Alpha'), findsOneWidget);
  await tester.tap(find.byKey(const Key('clear-project-search')));
  await tester.pump();
  expect(find.byType(Card), findsNWidgets(3));
});

testWidgets('search no-result state keeps exit available', (tester) async {
  await pumpProjects(tester);
  await tester.tap(find.byKey(const Key('search-projects')));
  await tester.enterText(find.byKey(const Key('project-search-field')), '不存在');
  await tester.pump();
  expect(find.text('没有匹配的项目'), findsOneWidget);
  expect(find.byKey(const Key('close-project-search')), findsOneWidget);
});
```

The test helper must create/close its `AppDatabase`, seed all three rows, and pump a Chinese `MaterialApp` with `AppStrings.delegate` and `databaseProvider.overrideWithValue(database)`.

- [ ] **Step 2: Run tests and verify the search controls are absent**

```powershell
flutter test test/features/projects/project_list_screen_test.dart
```

Expected: FAIL because `search-projects` and the search field do not exist.

- [ ] **Step 3: Convert the home screen to stateful search**

Change `ProjectListScreen` to `ConsumerStatefulWidget` with:

```dart
final _searchController = TextEditingController();
final _searchFocus = FocusNode();
bool _searching = false;
String _query = '';
```

Dispose both objects. Implement filtering:

```dart
List<Project> _filteredProjects(List<Project> projects) {
  final query = _query.trim().toLowerCase();
  if (query.isEmpty) return projects;
  return projects
      .where((project) => project.name.toLowerCase().contains(query))
      .toList(growable: false);
}
```

- [ ] **Step 4: Implement AppBar search/clear/exit and no-result state**

Normal mode keeps all-records/settings and adds:

```dart
IconButton(
  key: const Key('search-projects'),
  onPressed: _startSearch,
  tooltip: strings.searchProjects,
  icon: const Icon(Icons.search),
),
```

Search mode title:

```dart
TextField(
  key: const Key('project-search-field'),
  controller: _searchController,
  focusNode: _searchFocus,
  decoration: InputDecoration(
    hintText: strings.searchProjectsHint,
    border: InputBorder.none,
  ),
  onChanged: (value) => setState(() => _query = value),
),
```

Add keyed clear and close actions. `_startSearch` schedules `requestFocus()` after the frame; `_closeSearch` clears query/controller and restores normal AppBar. If the database has projects but the filtered list is empty, display `strings.noMatchingProjects`, not the first-run empty state.

- [ ] **Step 5: Run tests and commit**

```powershell
dart format lib/features/projects lib/l10n test/features/projects
flutter test test/features/projects/project_list_screen_test.dart test/widget_test.dart
flutter analyze
git add lib/features/projects/project_list_screen.dart lib/l10n/app_strings.dart test/features/projects
git commit -m "feat: add project search to home"
```

### Task 2: Add Injectable External Browser Launching

**Files:**
- Create: `lib/platform/external_link_service.dart`
- Create: `lib/domain/app_links.dart`
- Create: `test/platform/external_link_service_test.dart`
- Modify: `pubspec.yaml`, `pubspec.lock`
- Modify: `lib/app.dart`

**Interfaces:**
- Produces: `ExternalLinkService.open(Uri) -> Future<bool>`.
- Produces: `externalLinkServiceProvider` and `MyApp.externalLinkService` override.

- [ ] **Step 1: Add url_launcher and write a failing adapter test**

```powershell
flutter pub add url_launcher:^6.3.2
```

Create an adapter that accepts an injectable function, then test exact mode:

```dart
test('external link service uses external application mode', () async {
  Uri? opened;
  LaunchMode? openedMode;
  final service = UrlLauncherExternalLinkService(
    launcher: (uri, {required LaunchMode mode}) async {
      opened = uri;
      openedMode = mode;
      return true;
    },
  );

  expect(await service.open(siteMarkRepositoryUri), isTrue);
  expect(opened, siteMarkRepositoryUri);
  expect(openedMode, LaunchMode.externalApplication);
});
```

- [ ] **Step 2: Implement the service and constant**

```dart
// lib/domain/app_links.dart
const siteMarkRepositoryUrl = 'https://github.com/WikG1018/site-mark';
final siteMarkRepositoryUri = Uri.parse(siteMarkRepositoryUrl);

// lib/platform/external_link_service.dart
abstract interface class ExternalLinkService {
  Future<bool> open(Uri uri);
}

typedef UrlLauncher = Future<bool> Function(
  Uri uri, {
  required LaunchMode mode,
});

class UrlLauncherExternalLinkService implements ExternalLinkService {
  const UrlLauncherExternalLinkService({UrlLauncher? launcher})
      : _launcher = launcher ?? launchUrl;
  final UrlLauncher _launcher;

  @override
  Future<bool> open(Uri uri) =>
      _launcher(uri, mode: LaunchMode.externalApplication);
}
```

- [ ] **Step 3: Wire provider and test override**

Add:

```dart
final externalLinkServiceProvider = Provider<ExternalLinkService>(
  (ref) => const UrlLauncherExternalLinkService(),
);
```

Add `ExternalLinkService? externalLinkService` to `MyApp` and override the provider when supplied. Use a recording fake in settings/widget tests.

- [ ] **Step 4: Run adapter tests and commit**

```powershell
dart format lib/platform lib/app.dart test/platform
flutter test test/platform/external_link_service_test.dart
flutter analyze
git add pubspec.yaml pubspec.lock lib/domain/app_links.dart lib/platform/external_link_service.dart lib/app.dart test/platform/external_link_service_test.dart
git commit -m "feat: add external browser link service"
```

### Task 3: Make the About Repository Row Explicit and Clickable

**Files:**
- Modify: `lib/features/settings/global_settings_screen.dart`
- Modify: `lib/l10n/app_strings.dart`
- Modify: `test/features/settings/global_settings_screen_test.dart`

**Interfaces:**
- Consumes: `siteMarkRepositoryUrl`, `siteMarkRepositoryUri`, `externalLinkServiceProvider`.
- Produces: clickable About row with full URL and localized title.

- [ ] **Step 1: Replace the old repository test with failing label/link tests**

```dart
testWidgets('about shows and opens the full GitHub repository URL', (tester) async {
  final links = _RecordingExternalLinkService();
  await pumpSettings(tester, externalLinks: links);
  await tester.scrollUntilVisible(
    find.text(siteMarkRepositoryUrl),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  expect(find.text('GitHub 代码仓库'), findsOneWidget);
  expect(find.text(siteMarkRepositoryUrl), findsOneWidget);

  await tester.tap(find.byKey(const Key('github-repository-link')));
  await tester.pump();
  expect(links.opened, [siteMarkRepositoryUri]);
});
```

Add a failure test where `open` returns false and assert the localized “无法打开浏览器” Snackbar.

Define the recording fake in the test file:

```dart
class _RecordingExternalLinkService implements ExternalLinkService {
  _RecordingExternalLinkService({this.result = true});
  final bool result;
  final List<Uri> opened = [];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return result;
  }
}
```

- [ ] **Step 2: Update localized repository strings**

```dart
String get repository => _english ? 'GitHub Repository' : 'GitHub 代码仓库';
String get repositoryValue => siteMarkRepositoryUrl;
String get openLinkFailed =>
    _english ? 'Could not open the browser' : '无法打开浏览器';
```

Import `siteMarkRepositoryUrl` from the dependency-neutral `lib/domain/app_links.dart`; `app_strings.dart` must not import the platform service.

- [ ] **Step 3: Open the link and report failure**

Pass an `onOpenRepository` callback into `_AboutSection`. Render:

```dart
ListTile(
  key: const Key('github-repository-link'),
  leading: const Icon(Icons.source_outlined),
  title: Text(strings.repository),
  subtitle: const Text(siteMarkRepositoryUrl),
  trailing: const Icon(Icons.open_in_new),
  onTap: onOpenRepository,
),
```

The callback:

```dart
Future<void> _openRepository(BuildContext context) async {
  try {
    final opened = await ref
        .read(externalLinkServiceProvider)
        .open(siteMarkRepositoryUri);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).openLinkFailed)),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).openLinkFailed)),
      );
    }
  }
}
```

- [ ] **Step 4: Run settings tests and commit**

```powershell
dart format lib test/features/settings
flutter test test/features/settings/global_settings_screen_test.dart test/widget_test.dart
flutter analyze
git add lib test/features/settings
git commit -m "feat: link GitHub repository from about"
```

### Task 4: Home/About Verification Gate

**Files:**
- Verify only.

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: verified search and browser behavior.

- [ ] **Step 1: Run automated checks**

```powershell
flutter test
flutter analyze
git diff --check
```

Expected: all tests PASS and analysis reports no issues.

- [ ] **Step 2: Run device acceptance cases**

Search Chinese and mixed-case English project names, clear and exit search, and verify the project order returns unchanged. Open About, confirm the full URL is visible, tap it, and verify the phone’s external browser opens `https://github.com/WikG1018/site-mark`.
