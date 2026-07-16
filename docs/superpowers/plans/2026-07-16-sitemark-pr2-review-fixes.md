# SiteMark PR #2 Review Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repair every blocking PR #2 review finding, integrate the merged Android icon work, and leave PR #2 green, conflict-free, and ready for its maintainer to merge.

**Architecture:** Merge `origin/main` into the existing PR branch without rewriting history. Keep startup orchestration explicit and testable, preserve capture evidence across retries, translate stable Rust error prefixes into typed Dart failures, scope date options to the selected project, and make CI execute the tests it claims to cover.

**Tech Stack:** Flutter 3.44.6, Dart 3.12, Riverpod, Drift/SQLite, WorkManager 0.9.0+3, flutter_rust_bridge 2.12.0, Rust, Kotlin/Gradle, Python/Pillow, GitHub Actions.

## Global Constraints

- Keep package ID `io.github.wikg1018.sitemark`, version `0.2.0+2`, minSdk 31, targetSdk 36.
- Keep the app fully offline: no `INTERNET`, `CAMERA`, background-location, or broad-media permission in the merged APK.
- Keep the system-camera Intent and repository-local `sitemark_system_api` plugin architecture.
- Keep all full-resolution watermark rendering and SHA-256 work in Rust.
- Keep WorkManager tasks serialized on `sitemark-render-queue`, bounded to three automatic attempts, and idempotent by photo number.
- Preserve existing projects, captures, photo numbers, original paths, hashes, published URIs, and schema version 3.
- Preserve PR #3 launcher resources and the PR #2 v0.2.0 dependencies.
- Do not perform the final GitHub merge; only make PR #2 ready for the maintainer.

## File Map

- `android/app/src/main/AndroidManifest.xml` — merged offline permissions, plugin architecture, and round launcher icon.
- `docs/superpowers/specs/2026-07-16-sitemark-android-icon-design.md` — PR #3 shared-scene icon design.
- `lib/workflow/app_startup_recovery.dart` — ordered camera and queue recovery coordinator.
- `lib/app.dart` — startup provider wiring; no production-default WorkManager disable switch.
- `lib/data/app_database.dart` — retry reset that preserves evidence and MediaStore references.
- `lib/platform/platform_services.dart` — typed image-pipeline errors and Rust error translation.
- `lib/workflow/capture_processor.dart` — uniform hash/render retry handling.
- `rust/src/api/image_core.rs` — stable `not_found:`, `io:`, and `invalid_data:` error contract.
- `lib/features/capture/all_captures_screen.dart` — project-scoped date-option source.
- `.github/workflows/ci.yml`, `.github/workflows/release.yml` — real Kotlin and icon checks.
- `.gitignore`, `docs/images/branding/README.md` — Python cache ignore and reproducible setup instructions.

---

### Task 1: Merge PR #3 Mainline Into PR #2

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `docs/superpowers/specs/2026-07-16-sitemark-android-icon-design.md`
- Verify: `docs/release-checklist.md`
- Verify: `pubspec.yaml`
- Verify: `pubspec.lock`

**Interfaces:**
- Consumes: `origin/main` at or after merge commit `9a18a80931b5557edf2e3748da7391207b5c9065`.
- Produces: one merge commit containing PR #3 icon assets and PR #2 application architecture.

- [ ] **Step 1: Confirm clean branch and fetch current main**

Run:

```powershell
git status --short --branch
git fetch origin
git rev-parse origin/main
```

Expected: clean PR #2 worktree; `origin/main` contains PR #3.

- [ ] **Step 2: Merge main without committing unresolved files**

Run:

```powershell
git merge --no-commit --no-ff origin/main
```

Expected: conflicts only in `AndroidManifest.xml` and the icon design spec.

- [ ] **Step 3: Resolve the Android manifest**

The resulting `<manifest>` and `<application>` openings must be:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <uses-permission android:name="android.permission.INTERNET" tools:node="remove" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" tools:node="remove" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />

    <application
        android:label="@string/app_name"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:roundIcon="@mipmap/ic_launcher_round">
```

Do not add an application-level `.CaptureContentProvider` block; the local plugin manifest owns it.

- [ ] **Step 4: Resolve the icon design spec**

Keep the PR #3 version whose production section states that one declarative scene drives Pillow PNG rendering and the SVG companion. Remove all conflict markers.

- [ ] **Step 5: Verify the auto-merged dependency and checklist files**

Run:

```powershell
rg -n "version: 0.2.0\+2|sitemark_system_api|workmanager:|package_info_plus:|flutter_launcher_icons:" pubspec.yaml
rg -n "test_generate_launcher_icon|verification-v0.2.0-alpha|Shoot 10 photos" docs/release-checklist.md
git diff --check
```

Expected: all PR #2 dependencies and PR #3 icon dependency/checks are present; no conflict markers or whitespace errors.

- [ ] **Step 6: Commit the merge**

```powershell
git add android/app/src/main/AndroidManifest.xml `
  docs/superpowers/specs/2026-07-16-sitemark-android-icon-design.md `
  docs/release-checklist.md pubspec.yaml pubspec.lock
git commit -m "merge: integrate adaptive launcher icon into v0.2.0"
```

---

### Task 2: Make Startup Recovery Unconditionally Active in Production

**Files:**
- Create: `lib/workflow/app_startup_recovery.dart`
- Create: `test/workflow/app_startup_recovery_test.dart`
- Modify: `lib/app.dart`
- Test: `test/widget_test.dart`

**Interfaces:**
- Produces: `AppStartupRecovery({required Future<void> Function() recoverCamera, required Future<void> Function() reconcileQueue})` and `Future<void> run()`.
- Consumes: `CaptureWorkflow.recoverPendingCapture()` and `CaptureBackgroundScheduler.reconcilePending()`.

- [ ] **Step 1: Write the failing coordinator test**

Create `test/workflow/app_startup_recovery_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/workflow/app_startup_recovery.dart';

void main() {
  test('recovers camera state before reconciling the processing queue', () async {
    final events = <String>[];
    final recovery = AppStartupRecovery(
      recoverCamera: () async => events.add('camera'),
      reconcileQueue: () async => events.add('queue'),
    );

    await recovery.run();

    expect(events, ['camera', 'queue']);
  });
}
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```powershell
flutter test test/workflow/app_startup_recovery_test.dart
```

Expected: FAIL because `app_startup_recovery.dart` and `AppStartupRecovery` do not exist.

- [ ] **Step 3: Implement the coordinator**

Create `lib/workflow/app_startup_recovery.dart`:

```dart
class AppStartupRecovery {
  const AppStartupRecovery({
    required this.recoverCamera,
    required this.reconcileQueue,
  });

  final Future<void> Function() recoverCamera;
  final Future<void> Function() reconcileQueue;

  Future<void> run() async {
    await recoverCamera();
    await reconcileQueue();
  }
}
```

- [ ] **Step 4: Run the test and verify GREEN**

Run:

```powershell
flutter test test/workflow/app_startup_recovery_test.dart
```

Expected: PASS, 1 test.

- [ ] **Step 5: Write a failing production-wiring regression test**

Add to `test/widget_test.dart` a test that builds `MyApp` with a test database, a recording startup recovery, and an explicit opt-in test hook, then expects events `camera`, `queue`. The app constructor must expose only `startupRecovery` for injection, not `enableWorkManager`:

```dart
testWidgets('production startup runs camera and queue recovery', (tester) async {
  final events = <String>[];
  final recovery = AppStartupRecovery(
    recoverCamera: () async => events.add('camera'),
    reconcileQueue: () async => events.add('queue'),
  );

  await tester.pumpWidget(
    MyApp(
      database: database,
      initialLocale: const Locale('zh'),
      startupRecovery: recovery,
    ),
  );
  await tester.pump();

  expect(events, ['camera', 'queue']);
});
```

- [ ] **Step 6: Run the wiring test and verify RED**

Run the exact test by name. Expected: FAIL because `startupRecovery` is not accepted and database injection always disables startup.

- [ ] **Step 7: Wire startup recovery and remove the production kill switch**

In `lib/app.dart`:

```dart
final appStartupRecoveryProvider = Provider<AppStartupRecovery>((ref) {
  return AppStartupRecovery(
    recoverCamera: () => ref.read(captureWorkflowProvider).recoverPendingCapture(),
    reconcileQueue: () =>
        ref.read(captureBackgroundSchedulerProvider).reconcilePending(),
  );
});
```

Change `_SiteMarkAppState.initState` to:

```dart
Future<void>.microtask(() async {
  if (!ref.read(startupRecoveryEnabledProvider)) return;
  await ref.read(appStartupRecoveryProvider).run();
});
```

Remove `workManagerEnabledProvider`, `MyApp.enableWorkManager`, its unconditional override, and the UI-stage `scheduler.initialize()` call. Add nullable `AppStartupRecovery? startupRecovery`; when provided, override `appStartupRecoveryProvider` and do not auto-disable startup merely because a database was injected. Preserve the existing default auto-disable only when a database is injected without a startup-recovery override.

- [ ] **Step 8: Run focused and widget tests**

```powershell
flutter test test/workflow/app_startup_recovery_test.dart test/widget_test.dart
```

Expected: PASS; production wiring test observes ordered recovery and all existing widget tests remain isolated from WorkManager.

- [ ] **Step 9: Commit**

```powershell
git add lib/app.dart lib/workflow/app_startup_recovery.dart `
  test/workflow/app_startup_recovery_test.dart test/widget_test.dart
git commit -m "fix: restore pending captures on production startup"
```

---

### Task 3: Preserve Original Hash and Published URI During Retry

**Files:**
- Modify: `test/data/app_database_test.dart`
- Modify: `test/workflow/capture_workflow_test.dart`
- Modify: `test/workflow/capture_processor_test.dart`
- Modify: `lib/data/app_database.dart`

**Interfaces:**
- Produces: `resetCaptureForRetry` that changes only status, failure reason, and attempts.
- Preserves: `CaptureRecord.originalSha256` and `CaptureRecord.publishedUri` when already present.

- [ ] **Step 1: Change the database regression test to the desired behavior**

In the existing `resetCaptureForRetry` test, replace null assertions with:

```dart
expect(reset.originalSha256, originalHash);
expect(reset.publishedUri, 'content://media/site-mark/1');
expect(reset.failureReason, isNull);
expect(reset.processingAttempts, 0);
```

- [ ] **Step 2: Run the database test and verify RED**

```powershell
flutter test test/data/app_database_test.dart --plain-name "resetCaptureForRetry clears render metadata and resets attempts"
```

Expected: FAIL because the implementation returns null hash and URI.

- [ ] **Step 3: Implement the minimal database fix**

Change the retry companion to:

```dart
CaptureRecordsCompanion(
  status: const Value(CaptureStatus.captured),
  failureReason: const Value(null),
  processingAttempts: const Value(0),
)
```

Do not write `publishedUri` or `originalSha256` in this update.

- [ ] **Step 4: Verify the database test GREEN**

Run the same focused test. Expected: PASS.

- [ ] **Step 5: Update workflow regeneration expectations and add tamper retry coverage**

In `capture_workflow_test.dart`, expect the regenerated record to retain `digestA` and `content://media/site-mark/1`.

In `capture_processor_test.dart`, add:

```dart
test('manual retry preserves hash and still rejects a modified original', () async {
  await seedRenderingCapture(attempts: 0);
  await database.markFailed(captureId: 'capture-1', reason: 'hash mismatch');
  await database.resetCaptureForRetry('capture-1');
  images.sha256ByPath = {'/private/capture-1.jpg': _digestB};

  expect(await processor.process('capture-1'), CaptureProcessResult.failed);
  final record = await database.captureById('capture-1');
  expect(record?.originalSha256, _digestA);
  expect(platform.publishedNames, isEmpty);
});
```

- [ ] **Step 6: Run focused workflow tests**

```powershell
flutter test test/workflow/capture_workflow_test.dart test/workflow/capture_processor_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit**

```powershell
git add lib/data/app_database.dart test/data/app_database_test.dart `
  test/workflow/capture_workflow_test.dart test/workflow/capture_processor_test.dart
git commit -m "fix: preserve capture evidence across retries"
```

---

### Task 4: Add a Typed Rust-to-Dart Image Failure Contract

**Files:**
- Create: `test/platform/platform_services_test.dart`
- Modify: `test/workflow/capture_processor_test.dart`
- Modify: `lib/platform/platform_services.dart`
- Modify: `lib/workflow/capture_processor.dart`
- Modify: `rust/src/api/image_core.rs`
- Modify: `rust/tests/core_test.rs`

**Interfaces:**
- Produces: `enum ImagePipelineFailureKind { notFound, transientIo, invalidData }`.
- Produces: `ImagePipelineException.tryParseRustError(Object error)` returning a typed exception or null.
- Consumes Rust prefixes: `not_found:`, `io:`, `invalid_data:`.

- [ ] **Step 1: Write failing parser tests**

Create `test/platform/platform_services_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/platform/platform_services.dart';

void main() {
  test('parses stable Rust image error prefixes', () {
    expect(
      ImagePipelineException.tryParseRustError('not_found:open original'),
      isA<ImagePipelineException>().having(
        (error) => error.kind,
        'kind',
        ImagePipelineFailureKind.notFound,
      ),
    );
    expect(
      ImagePipelineException.tryParseRustError('io:write output'),
      isA<ImagePipelineException>().having(
        (error) => error.kind,
        'kind',
        ImagePipelineFailureKind.transientIo,
      ),
    );
    expect(
      ImagePipelineException.tryParseRustError('invalid_data:decode jpeg'),
      isA<ImagePipelineException>().having(
        (error) => error.kind,
        'kind',
        ImagePipelineFailureKind.invalidData,
      ),
    );
    expect(ImagePipelineException.tryParseRustError('unknown'), isNull);
  });
}
```

- [ ] **Step 2: Run parser tests and verify RED**

```powershell
flutter test test/platform/platform_services_test.dart
```

Expected: FAIL because the typed exception contract does not exist.

- [ ] **Step 3: Implement Dart parsing and RustImagePipeline translation**

Add to `lib/platform/platform_services.dart`:

```dart
enum ImagePipelineFailureKind { notFound, transientIo, invalidData }

class ImagePipelineException implements Exception {
  const ImagePipelineException(this.kind, this.message);

  final ImagePipelineFailureKind kind;
  final String message;

  static ImagePipelineException? tryParseRustError(Object error) {
    final message = error.toString();
    const prefixes = <String, ImagePipelineFailureKind>{
      'not_found:': ImagePipelineFailureKind.notFound,
      'io:': ImagePipelineFailureKind.transientIo,
      'invalid_data:': ImagePipelineFailureKind.invalidData,
    };
    for (final entry in prefixes.entries) {
      if (message.startsWith(entry.key)) {
        return ImagePipelineException(
          entry.value,
          message.substring(entry.key.length),
        );
      }
    }
    return null;
  }

  @override
  String toString() => message;
}
```

Wrap every RustImagePipeline call:

```dart
Future<T> _translateRustError<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } catch (error) {
    final translated = ImagePipelineException.tryParseRustError(error);
    if (translated != null) throw translated;
    rethrow;
  }
}
```

- [ ] **Step 4: Run parser tests and verify GREEN**

Run the focused test. Expected: PASS.

- [ ] **Step 5: Write failing processor tests for hash-stage errors**

Add tests proving:

```dart
images.sha256Error = const ImagePipelineException(
  ImagePipelineFailureKind.transientIo,
  'temporary read error',
);
expect(await processor.process('capture-1'), CaptureProcessResult.retry);
```

and that a third transient hash attempt returns `failed`, while `notFound` and `invalidData` fail immediately. Verify that attempts increment and the record never remains as an unhandled future error.

- [ ] **Step 6: Run processor tests and verify RED**

Expected: transient hash test throws instead of returning `retry`.

- [ ] **Step 7: Handle all hash and render errors uniformly**

In `CaptureProcessor.process`, change the hash stage to catch `Object` and use the same classification helper as render:

```dart
try {
  hashResult = await _resolveOriginalSha256(attempted);
} catch (error) {
  if (_isTransient(error) && attempts < maxAttempts) {
    return CaptureProcessResult.retry;
  }
  await _failPermanently(captureId, error.toString());
  return CaptureProcessResult.failed;
}
```

Extend `_isTransient`:

```dart
if (error is ImagePipelineException) {
  return error.kind == ImagePipelineFailureKind.transientIo;
}
```

Keep `PathNotFoundException` permanent and the existing platform exception branches.

- [ ] **Step 8: Run processor tests and verify GREEN**

```powershell
flutter test test/workflow/capture_processor_test.dart
```

Expected: all processor tests pass, including bounded hash-stage retry.

- [ ] **Step 9: Write failing Rust prefix tests**

Add to `rust/tests/core_test.rs`:

```rust
#[test]
fn missing_file_uses_not_found_error_prefix() {
    let error = sha256_file("definitely-missing-sitemark-file.jpg".into()).unwrap_err();
    assert!(error.starts_with("not_found:"), "{error}");
}
```

Add a render request with an invalid/empty source and assert `invalid_data:` or `not_found:` according to the failure point.

- [ ] **Step 10: Run Rust tests and verify RED**

```powershell
cargo test --manifest-path rust/Cargo.toml
```

Expected: new prefix test fails against the old free-form errors.

- [ ] **Step 11: Implement stable Rust error prefixes**

Add helpers:

```rust
fn io_failure(context: &str, error: std::io::Error) -> String {
    let prefix = if error.kind() == std::io::ErrorKind::NotFound {
        "not_found:"
    } else {
        "io:"
    };
    format!("{prefix}{context}: {error}")
}

fn invalid_data(context: &str, error: impl std::fmt::Display) -> String {
    format!("invalid_data:{context}: {error}")
}

fn image_failure(context: &str, error: image::ImageError) -> String {
    match error {
        image::ImageError::IoError(error) => io_failure(context, error),
        error => invalid_data(context, error),
    }
}
```

Use `io_failure` for `File::open`, `Read::read`, `create_dir_all`, and `File::create`. Use `image_failure` for decoder construction, pixel/orientation reads, and JPEG encoding so nested `ImageError::IoError` remains retryable. Use `invalid_data` for request validation and invalid watermark layout. Preserve the successful return types, so flutter_rust_bridge generated signatures do not change.

- [ ] **Step 12: Run Rust and Dart focused suites**

```powershell
cargo fmt --manifest-path rust/Cargo.toml --check
cargo test --manifest-path rust/Cargo.toml
flutter test test/platform/platform_services_test.dart test/workflow/capture_processor_test.dart
```

Expected: all pass.

- [ ] **Step 13: Commit**

```powershell
git add lib/platform/platform_services.dart lib/workflow/capture_processor.dart `
  rust/src/api/image_core.rs rust/tests/core_test.rs `
  test/platform/platform_services_test.dart test/workflow/capture_processor_test.dart
git commit -m "fix: classify background image failures for retry"
```

---

### Task 5: Scope Date Options to the Selected Project

**Files:**
- Modify: `test/features/capture/capture_filter_ui_test.dart`
- Modify: `lib/features/capture/all_captures_screen.dart`

**Interfaces:**
- Consumes: current `CaptureFilter.projectId` and unfiltered `List<CaptureSummary>`.
- Produces: a project-scoped list passed to `CaptureDateFilterBar`.

- [ ] **Step 1: Write the failing widget test**

Seed project A with a 2025 capture and project B with a 2026 capture. Open all records, select project B, open `filter-year`, and assert `2026` is present while `2025` is absent.

Use the existing database/fake setup in `capture_filter_ui_test.dart`; select the project through `project-filter` rather than calling private state.

- [ ] **Step 2: Run the focused test and verify RED**

```powershell
flutter test test/features/capture/capture_filter_ui_test.dart --plain-name "all-records date options follow the selected project"
```

Expected: FAIL because both years are currently shown.

- [ ] **Step 3: Implement project-scoped date summaries**

Before building `CaptureDateFilterBar`, calculate:

```dart
final dateOptionSummaries = _filter.projectId == null
    ? allSummaries
    : allSummaries
          .where((summary) => summary.capture.projectId == _filter.projectId)
          .toList(growable: false);
```

Pass `dateOptionSummaries` as `summaries` while retaining `allSummaries` for the empty-state distinction.

- [ ] **Step 4: Run filter tests and verify GREEN**

```powershell
flutter test test/features/capture/capture_filter_ui_test.dart
```

Expected: all date cascade tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/features/capture/all_captures_screen.dart `
  test/features/capture/capture_filter_ui_test.dart
git commit -m "fix: scope date filters to the selected project"
```

---

### Task 6: Make CI Run Icon and Kotlin Plugin Checks

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `.github/workflows/release.yml`
- Modify: `.gitignore`
- Modify: `docs/images/branding/README.md`

**Interfaces:**
- Consumes: `tool/icon-requirements.txt`, Python test modules, `:sitemark_system_api:testDebugUnitTest`.
- Produces: CI logs with 11 Python tests, resource verification, and 7 Kotlin plugin tests.

- [ ] **Step 1: Update CI commands**

After `flutter pub get` in `.github/workflows/ci.yml`, add:

```yaml
      - run: python -m pip install -r tool/icon-requirements.txt
      - run: python -m unittest tool.test_generate_launcher_icon tool.test_verify_launcher_icon_resources
      - run: python tool/verify_launcher_icon_resources.py
```

Replace:

```yaml
      - run: ./android/gradlew -p android :app:testDebugUnitTest
```

with:

```yaml
      - run: ./android/gradlew -p android :sitemark_system_api:testDebugUnitTest
```

Apply the same Python and Kotlin checks in `.github/workflows/release.yml` before signed builds.

- [ ] **Step 2: Ignore Python cache and document setup**

Add to `.gitignore`:

```gitignore
__pycache__/
*.py[cod]
```

Before the generation command in `docs/images/branding/README.md`, add:

```powershell
python -m pip install -r tool/icon-requirements.txt
```

- [ ] **Step 3: Run every newly referenced command locally**

```powershell
python -m pip install -r tool/icon-requirements.txt
python -m unittest tool.test_generate_launcher_icon tool.test_verify_launcher_icon_resources
python tool/verify_launcher_icon_resources.py
pwsh.exe -NoLogo -NoProfile -Command "Set-Location android; .\gradlew.bat :sitemark_system_api:testDebugUnitTest"
```

Expected: 11 Python tests pass, 25 PNG resources plus Play icon verify, and Gradle executes 7 Kotlin tests with zero failures.

- [ ] **Step 4: Verify workflow syntax and diff**

Run:

```powershell
git diff --check
rg -n "test_generate_launcher_icon|verify_launcher_icon_resources|sitemark_system_api:testDebugUnitTest" .github/workflows
git status --short
```

Expected: commands appear in CI and release workflows; only intended files are modified.

- [ ] **Step 5: Commit**

```powershell
git add .github/workflows/ci.yml .github/workflows/release.yml `
  .gitignore docs/images/branding/README.md
git commit -m "ci: run launcher and Android plugin verification"
```

---

### Task 7: Full Verification, Push, and PR Readiness

**Files:**
- Verify: all changed source, test, workflow, and documentation files.
- Modify: `docs/verification-v0.2.0-alpha.md`

**Interfaces:**
- Consumes: completed Tasks 1-6.
- Produces: pushed PR #2 head with green GitHub checks and clean merge state.

- [ ] **Step 1: Regenerate/check generated Dart and formatting**

```powershell
dart format --output=none --set-exit-if-changed lib test integration_test
dart run build_runner build --delete-conflicting-outputs
dart run pigeon --input pigeons/system_api.dart
git status --short
```

Expected: generated files match source; inspect and include only deterministic generated changes required by the source edits.

- [ ] **Step 2: Run full Flutter verification**

```powershell
flutter analyze
flutter test
```

Expected: no analyzer issues; all tests pass.

- [ ] **Step 3: Run full Rust verification**

```powershell
cargo fmt --manifest-path rust/Cargo.toml --check
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path rust/Cargo.toml
```

Expected: format clean, zero clippy warnings, all Rust tests pass.

- [ ] **Step 4: Run Android and icon verification**

```powershell
python -m unittest tool.test_generate_launcher_icon tool.test_verify_launcher_icon_resources
python tool/verify_launcher_icon_resources.py
pwsh.exe -NoLogo -NoProfile -Command "Set-Location android; .\gradlew.bat :sitemark_system_api:testDebugUnitTest"
flutter build apk --debug
```

Expected: Python, resource, Kotlin tests pass and `build/app/outputs/flutter-apk/app-debug.apk` is created.

- [ ] **Step 5: Inspect the merged APK**

Use Android build tools to verify package/version and merged permissions. Confirm the APK contains `ic_launcher_round`, carries no forbidden permissions, and is debug signed. Record the new size, SHA-256, final Flutter/Rust/Kotlin/Python test counts, and current device-test status in `docs/verification-v0.2.0-alpha.md`.

- [ ] **Step 6: Verify repository state**

```powershell
git diff --check origin/main...HEAD
git status --short --branch
git log --oneline --decorate origin/main..HEAD
```

Expected: clean worktree, intentional commits only, no conflict markers.

- [ ] **Step 7: Push PR #2 branch**

```powershell
git push origin feat/sitemark-v0.1.0
```

Expected: normal fast-forward push; no force push.

- [ ] **Step 8: Wait for GitHub CI and inspect PR state**

```powershell
gh pr checks 2 --repo WikG1018/site-mark --watch
gh pr view 2 --repo WikG1018/site-mark `
  --json isDraft,mergeable,mergeStateStatus,headRefOid,statusCheckRollup
```

Expected: all checks `SUCCESS`, `mergeable=MERGEABLE`, and no conflict state.

- [ ] **Step 9: Mark ready for review when automated gates are green**

```powershell
gh pr ready 2 --repo WikG1018/site-mark
```

Do not merge. Report any remaining real-device release acceptance item separately from code mergeability.
