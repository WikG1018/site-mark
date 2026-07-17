# SiteMark Background Processing Status Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make project lists, the all-records list, and capture details automatically observe WorkManager status changes without running a permanent polling loop.

**Architecture:** Production Drift connections opt into same-engine cross-isolate sharing for the fast path. A reusable stream decorator starts a one-second disk reread only while the latest value contains a `captured` or `rendering` record, emits changed values, tolerates one failed reread, and stops on terminal state, pause, or cancellation. AppDatabase applies that decorator to the three UI-facing capture watchers.

**Tech Stack:** Flutter/Dart 3.12, Drift 2.34, drift_flutter 0.3.1, SQLite, WorkManager 0.9.0+3, Flutter test.

## Global Constraints

- Enable `DriftNativeOptions(shareAcrossIsolates: true)` only for the production `sitemark` database connection.
- Poll once per second in production only while the latest watched value contains `CaptureStatus.captured` or `CaptureStatus.rendering`.
- Stop polling immediately when all watched records are terminal, the stream is paused, or its subscription is cancelled.
- A failed poll must keep the existing Drift source stream alive and retry on the next interval.
- Never enqueue, render, publish, increment attempts, or mutate database state from the polling layer.
- Do not reset capture filters, edit mode, or selected IDs when a refreshed value arrives.
- Use a configurable interval in the database constructor so integration tests run in milliseconds without test-only production methods.
- Do not add network, background-location, or broad media-read permissions.
- Do not edit Drift generated Dart by hand.

## File Map

- Create: `lib/data/conditional_polling_stream.dart` — lifecycle-safe generic source-stream decorator.
- Create: `test/data/conditional_polling_stream_test.dart` — start, terminal-stop, and cancellation coverage.
- Modify: `lib/data/app_database.dart` — production Drift options, refresh interval, and decorated capture watchers.
- Create: `test/data/app_database_external_refresh_test.dart` — two independent SQLite connections proving disk refresh.
- Verify: `test/features/capture/capture_filter_ui_test.dart` and `test/features/capture/capture_detail_screen_test.dart` — existing UI stream consumers and local selection behavior.

---

### Task 1: Lifecycle-Safe Conditional Polling Stream

**Files:**
- Create: `test/data/conditional_polling_stream_test.dart`
- Create: `lib/data/conditional_polling_stream.dart`

**Interfaces:**
- Consumes: `Stream<T> source`, `Future<T> Function() load`, `bool Function(T) shouldPoll`, optional equality callback, and poll interval.
- Produces: `watchWithConditionalPolling<T>(...) -> Stream<T>` that keeps the source subscription as the primary path and rereads only while required.

- [ ] **Step 1: Write failing lifecycle tests**

Create `test/data/conditional_polling_stream_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/conditional_polling_stream.dart';
import 'package:sitemark/domain/capture_status.dart';

void main() {
  test('polls while processing and stops after a terminal value', () async {
    final source = StreamController<CaptureStatus>();
    var stored = CaptureStatus.captured;
    var reads = 0;
    final readySeen = Completer<void>();
    final subscription = watchWithConditionalPolling<CaptureStatus>(
      source: source.stream,
      load: () async {
        reads += 1;
        return stored;
      },
      shouldPoll: (status) =>
          status == CaptureStatus.captured ||
          status == CaptureStatus.rendering,
      pollInterval: const Duration(milliseconds: 5),
    ).listen((status) {
      if (status == CaptureStatus.ready && !readySeen.isCompleted) {
        readySeen.complete();
      }
    });

    source.add(CaptureStatus.captured);
    await Future<void>.delayed(Duration.zero);
    stored = CaptureStatus.ready;
    await readySeen.future.timeout(const Duration(milliseconds: 200));
    final readsAtReady = reads;
    await Future<void>.delayed(const Duration(milliseconds: 25));

    expect(reads, readsAtReady);
    await subscription.cancel();
    await source.close();
  });

  test('does not poll when the source starts terminal', () async {
    final source = StreamController<CaptureStatus>();
    var reads = 0;
    final subscription = watchWithConditionalPolling<CaptureStatus>(
      source: source.stream,
      load: () async {
        reads += 1;
        return CaptureStatus.ready;
      },
      shouldPoll: (status) =>
          status == CaptureStatus.captured ||
          status == CaptureStatus.rendering,
      pollInterval: const Duration(milliseconds: 5),
    ).listen((_) {});

    source.add(CaptureStatus.ready);
    await Future<void>.delayed(const Duration(milliseconds: 25));

    expect(reads, 0);
    await subscription.cancel();
    await source.close();
  });

  test('cancelling the subscription stops an active poller', () async {
    final source = StreamController<CaptureStatus>();
    final loadStarted = Completer<void>();
    final releaseLoad = Completer<void>();
    var reads = 0;
    final subscription = watchWithConditionalPolling<CaptureStatus>(
      source: source.stream,
      load: () async {
        reads += 1;
        if (!loadStarted.isCompleted) loadStarted.complete();
        await releaseLoad.future;
        return CaptureStatus.captured;
      },
      shouldPoll: (status) => status == CaptureStatus.captured,
      pollInterval: const Duration(milliseconds: 5),
    ).listen((_) {});

    source.add(CaptureStatus.captured);
    await loadStarted.future.timeout(const Duration(milliseconds: 200));
    await subscription.cancel();
    final readsAtCancel = reads;
    releaseLoad.complete();
    await Future<void>.delayed(const Duration(milliseconds: 25));

    expect(reads, readsAtCancel);
    await source.close();
  });
}
```

- [ ] **Step 2: Run the helper tests and verify RED**

Run:

```powershell
flutter test test/data/conditional_polling_stream_test.dart
```

Expected: FAIL because `conditional_polling_stream.dart` does not exist.

- [ ] **Step 3: Implement the generic stream decorator**

Create `lib/data/conditional_polling_stream.dart`:

```dart
import 'dart:async';

Stream<T> watchWithConditionalPolling<T>({
  required Stream<T> source,
  required Future<T> Function() load,
  required bool Function(T value) shouldPoll,
  bool Function(T previous, T next)? equals,
  Duration pollInterval = const Duration(seconds: 1),
}) {
  if (pollInterval <= Duration.zero) {
    throw ArgumentError.value(pollInterval, 'pollInterval', 'Must be positive');
  }

  late final StreamController<T> controller;
  StreamSubscription<T>? sourceSubscription;
  Timer? timer;
  T? latest;
  var hasLatest = false;
  var pollRunning = false;
  var active = false;
  late Future<void> Function() poll;

  bool same(T previous, T next) =>
      equals?.call(previous, next) ?? previous == next;

  void stopPolling() {
    timer?.cancel();
    timer = null;
  }

  void updatePolling(T value) {
    if (!active || !shouldPoll(value)) {
      stopPolling();
      return;
    }
    timer ??= Timer.periodic(
      pollInterval,
      (_) => unawaited(poll()),
    );
  }

  void accept(T value) {
    if (!active) return;
    final changed = !hasLatest || !same(latest as T, value);
    latest = value;
    hasLatest = true;
    updatePolling(value);
    if (changed && !controller.isClosed) {
      controller.add(value);
    }
  }

  poll = () async {
    if (!active || pollRunning || controller.isClosed) return;
    pollRunning = true;
    try {
      accept(await load());
    } catch (_) {
      // Keep the primary Drift stream alive and retry on the next interval.
    } finally {
      pollRunning = false;
    }
  };

  controller = StreamController<T>(
    onListen: () {
      active = true;
      sourceSubscription = source.listen(
        accept,
        onError: (Object error, StackTrace stackTrace) {
          controller.addError(error, stackTrace);
        },
        onDone: () {
          active = false;
          stopPolling();
          unawaited(controller.close());
        },
      );
    },
    onPause: () {
      active = false;
      sourceSubscription?.pause();
      stopPolling();
    },
    onResume: () {
      active = true;
      sourceSubscription?.resume();
      if (hasLatest) updatePolling(latest as T);
    },
    onCancel: () async {
      active = false;
      stopPolling();
      await sourceSubscription?.cancel();
    },
  );

  return controller.stream;
}
```

- [ ] **Step 4: Run helper tests and verify GREEN**

Run:

```powershell
dart format lib/data/conditional_polling_stream.dart test/data/conditional_polling_stream_test.dart
flutter test test/data/conditional_polling_stream_test.dart
```

Expected: all 3 helper tests PASS with no leaked-timer warning.

- [ ] **Step 5: Commit the helper**

```powershell
git add lib/data/conditional_polling_stream.dart test/data/conditional_polling_stream_test.dart
git commit -m "feat: add conditional processing refresh stream"
```

---

### Task 2: Apply Refresh to Drift Capture Watchers

**Files:**
- Create: `test/data/app_database_external_refresh_test.dart`
- Modify: `lib/data/app_database.dart:1-5,95-102,577-591,743-798`

**Interfaces:**
- Consumes: `watchWithConditionalPolling` from Task 1 and existing Drift `watch`/`get` queries.
- Produces: production `AppDatabase({Duration externalRefreshInterval})`, test constructor interval override, and externally refreshed `watchCaptureById`, `watchCaptureSummaries`, and `watchAllCaptureSummaries`.

- [ ] **Step 1: Write a failing two-connection integration test**

Create `test/data/app_database_external_refresh_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_filter.dart';
import 'package:sitemark/domain/capture_status.dart';

void main() {
  const digest =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  late Directory directory;
  late AppDatabase foreground;
  late AppDatabase background;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sitemark-refresh-');
    final file = File(
      '${directory.path}${Platform.pathSeparator}sitemark.sqlite',
    );
    foreground = AppDatabase.forTesting(
      NativeDatabase(file),
      externalRefreshInterval: const Duration(milliseconds: 10),
    );
    await foreground.createProject(id: 'project-1', name: '东区厂房改造');
    final pending = await foreground.createPendingCapture(
      id: 'capture-1',
      projectId: 'project-1',
      originalPath: '/private/capture-1.jpg',
      workLocation: 'A 区',
      workContent: '风管检查',
      photographer: '张工',
      watermarkLocaleCode: 'zh',
    );
    await foreground.markCaptured(
      captureId: pending.id,
      capturedAt: DateTime(2026, 7, 17, 9, 30),
    );
    background = AppDatabase.forTesting(NativeDatabase(file));
    await background.customSelect('SELECT 1').get();
  });

  tearDown(() async {
    await background.close();
    await foreground.close();
    await directory.delete(recursive: true);
  });

  test('detail and summary watchers observe an external ready update', () async {
    final detail = StreamIterator(foreground.watchCaptureById('capture-1'));
    final filtered = StreamIterator(
      foreground.watchCaptureSummaries(const CaptureFilter()),
    );
    final all = StreamIterator(foreground.watchAllCaptureSummaries());

    expect(await detail.moveNext(), isTrue);
    expect(detail.current?.status, CaptureStatus.captured);
    expect(await filtered.moveNext(), isTrue);
    expect(filtered.current.single.capture.status, CaptureStatus.captured);
    expect(await all.moveNext(), isTrue);
    expect(all.current.single.capture.status, CaptureStatus.captured);

    await background.markRendering(
      captureId: 'capture-1',
      originalSha256: digest,
    );
    await background.markReady(
      captureId: 'capture-1',
      publishedUri: 'content://media/site-mark/1',
    );

    final readyDetail = await _nextMatching(
      detail,
      (record) => record?.status == CaptureStatus.ready,
    );
    final readyFiltered = await _nextMatching(
      filtered,
      (rows) => rows.single.capture.status == CaptureStatus.ready,
    );
    final readyAll = await _nextMatching(
      all,
      (rows) => rows.single.capture.status == CaptureStatus.ready,
    );

    expect(readyDetail?.publishedUri, 'content://media/site-mark/1');
    expect(readyFiltered.single.projectName, '东区厂房改造');
    expect(readyAll.single.capture.publishedUri, 'content://media/site-mark/1');
    await detail.cancel();
    await filtered.cancel();
    await all.cancel();
  });
}

Future<T> _nextMatching<T>(
  StreamIterator<T> iterator,
  bool Function(T value) predicate,
) async {
  while (await iterator.moveNext().timeout(const Duration(seconds: 1))) {
    if (predicate(iterator.current)) return iterator.current;
  }
  throw StateError('Stream closed before the expected value');
}
```

- [ ] **Step 2: Run the integration test and verify RED**

Run:

```powershell
flutter test test/data/app_database_external_refresh_test.dart
```

Expected: FAIL because `AppDatabase.forTesting` has no `externalRefreshInterval` parameter and existing watchers have no external polling fallback.

- [ ] **Step 3: Configure production database sharing and the interval**

Add the helper import:

```dart
import 'package:sitemark/data/conditional_polling_stream.dart';
```

Replace the constructors with:

```dart
static const _defaultExternalRefreshInterval = Duration(seconds: 1);

final Duration externalRefreshInterval;

AppDatabase({
  this.externalRefreshInterval = _defaultExternalRefreshInterval,
}) : super(
       driftDatabase(
         name: 'sitemark',
         native: const DriftNativeOptions(shareAcrossIsolates: true),
       ),
     );

AppDatabase.forTesting(
  super.executor, {
  this.externalRefreshInterval = _defaultExternalRefreshInterval,
});
```

Do not enable `shareAcrossIsolates` for `forTesting`; file-backed integration tests intentionally use independent connections so the polling fallback is exercised.

- [ ] **Step 4: Decorate all UI-facing capture watchers**

Replace the three watcher methods with:

```dart
Stream<CaptureRecord?> watchCaptureById(String captureId) {
  final query = select(captureRecords)
    ..where((row) => row.id.equals(captureId));
  return watchWithConditionalPolling(
    source: query.watchSingleOrNull(),
    load: () => query.getSingleOrNull(),
    shouldPoll: (record) => record != null && _isProcessing(record.status),
    pollInterval: externalRefreshInterval,
  );
}

Stream<List<CaptureSummary>> watchCaptureSummaries(CaptureFilter filter) {
  final query = _captureSummarySelectable(filter);
  return watchWithConditionalPolling(
    source: query.watch(),
    load: query.get,
    shouldPoll: (rows) =>
        rows.any((summary) => _isProcessing(summary.capture.status)),
    equals: _sameCaptureSummaries,
    pollInterval: externalRefreshInterval,
  );
}

Stream<List<CaptureSummary>> watchAllCaptureSummaries() {
  final query = _captureSummarySelectable(null);
  return watchWithConditionalPolling(
    source: query.watch(),
    load: query.get,
    shouldPoll: (rows) =>
        rows.any((summary) => _isProcessing(summary.capture.status)),
    equals: _sameCaptureSummaries,
    pollInterval: externalRefreshInterval,
  );
}
```

Add these private helpers inside `AppDatabase`:

```dart
bool _isProcessing(CaptureStatus status) =>
    status == CaptureStatus.captured || status == CaptureStatus.rendering;

bool _sameCaptureSummaries(
  List<CaptureSummary> previous,
  List<CaptureSummary> next,
) {
  if (previous.length != next.length) return false;
  for (var index = 0; index < previous.length; index++) {
    if (previous[index].capture != next[index].capture ||
        previous[index].projectName != next[index].projectName) {
      return false;
    }
  }
  return true;
}
```

- [ ] **Step 5: Run the helper, external-refresh, and database suites**

Run:

```powershell
dart format lib/data/app_database.dart test/data/app_database_external_refresh_test.dart
flutter test test/data/conditional_polling_stream_test.dart test/data/app_database_external_refresh_test.dart test/data/app_database_test.dart
```

Expected: all selected tests PASS; the two-connection test reaches `ready` without recreating the foreground database.

- [ ] **Step 6: Run existing UI watcher regression tests**

Run:

```powershell
flutter test test/features/capture/capture_filter_ui_test.dart test/features/capture/capture_detail_screen_test.dart
```

Expected: all tests PASS; filter/edit state and detail actions remain unchanged when capture streams emit new values.

- [ ] **Step 7: Commit database refresh integration**

```powershell
git add lib/data/app_database.dart test/data/app_database_external_refresh_test.dart
git commit -m "fix: refresh externally processed capture statuses"
```

---

### Task 3: Full Verification, APK, and PR Update

**Files:**
- Verify the complete repository.
- Replace: `C:\Users\Administrator\Desktop\mac\SiteMark-PR4-debug.apk`

**Interfaces:**
- Consumes: the photo-naming plan and Tasks 1-2 of this plan.
- Produces: verified commits on `feat/sitemark-field-test-follow-up`, updated Draft PR #4, and a fresh desktop APK.

- [ ] **Step 1: Regenerate deterministic bindings and check formatting**

```powershell
dart format lib test
dart run pigeon --input pigeons/system_api.dart
dart run build_runner build --delete-conflicting-outputs
git diff --check
```

Expected: all commands exit 0; generated output has no unexpected drift.

- [ ] **Step 2: Run all Flutter checks**

```powershell
flutter test
flutter analyze
```

Expected: every Flutter test PASS and analyze reports `No issues found!`.

- [ ] **Step 3: Run Android plugin tests**

```powershell
Push-Location packages/sitemark_system_api/android
.\gradlew.bat :sitemark_system_api:testDebugUnitTest
Pop-Location
```

Expected: Gradle reports `BUILD SUCCESSFUL`.

- [ ] **Step 4: Run Rust checks**

```powershell
cargo fmt --manifest-path rust/Cargo.toml -- --check
cargo clippy --manifest-path rust/Cargo.toml -- -D warnings
cargo test --manifest-path rust/Cargo.toml
```

Expected: fmt and clippy exit 0; all Rust unit and integration tests PASS.

- [ ] **Step 5: Build and copy the new debug APK**

```powershell
flutter build apk --debug
$source = Resolve-Path 'build/app/outputs/flutter-apk/app-debug.apk'
$destination = 'C:\Users\Administrator\Desktop\mac\SiteMark-PR4-debug.apk'
Copy-Item -LiteralPath $source -Destination $destination -Force
Get-Item -LiteralPath $destination | Select-Object FullName, Length, LastWriteTime
Get-FileHash -Algorithm SHA256 -LiteralPath $destination
```

Expected: build succeeds and the destination file exists with a non-zero length and SHA-256 hash.

- [ ] **Step 6: Confirm the final commit set and push PR #4**

```powershell
git status --short --branch
git log --oneline origin/main..HEAD
git push origin feat/sitemark-field-test-follow-up
gh pr view 4 --repo WikG1018/site-mark --json number,title,url,isDraft,state,headRefOid
```

Expected: the worktree is clean, push succeeds, and PR #4 remains OPEN and Draft with its head at the final local commit.

- [ ] **Step 7: Record the remaining real-device acceptance checks**

Verify on the user's phone:

```text
1. Keep a project record list open while taking a photo.
2. Confirm waiting/processing changes to completed or failed without leaving the page.
3. Confirm the preview appears when processing reaches completed.
4. Confirm the detail number and gallery filename use 项目名称-SM-yyyyMMdd-001.
5. Confirm the visible Chinese and English watermarks contain no number row.
6. Confirm an existing pre-fix photo retains its old SM-yyyyMMdd-001 number.
```
