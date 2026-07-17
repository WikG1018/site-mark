# SiteMark Project Photo Naming and Watermark Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every newly captured photo a filesystem-safe project-prefixed number and filename while removing the number row from Chinese and English watermarks.

**Architecture:** A new pure Dart formatter owns project-name sanitization and photo-number construction. `AppDatabase.markCaptured` remains the single allocation point and passes the stored number unchanged through rendering, MediaStore publishing, details, and export. Rust keeps `photo_number` as traceability input but removes it from the visible watermark-line builder.

**Tech Stack:** Flutter/Dart 3.12, Drift 2.34, Rust, flutter_rust_bridge 2.12, `imageproc`, Flutter test, Cargo test.

## Global Constraints

- New numbers use `{safeProjectName}~{projectId}-SM-{yyyyMMdd}-{sequence padded to at least 3 digits}`, where `~` is a **dedicated field separator** (blacklisted in `safePhotoProjectName`, excluded from the `projectId` ASCII whitelist) and `projectId` is embedded **verbatim** (hyphens preserved). This prevents cross-field collisions such as `(A, B-C)` vs `(A-B, C)`, and preserving hyphens keeps the project-ID-to-file-name mapping strictly one-to-one.
- Validate `projectId` against `^[A-Za-z0-9_-]+$` (matches the Rust `safe_archive_component` ASCII contract) before generating the number. Also reject `projectId` when the suffix bytes plus the `Project` fallback bytes would exceed 255, so the final JPEG name can never exceed the POSIX `NAME_MAX` of 255 bytes.
- Replace control characters (incl. C1), `~`, Unicode whitespace, and `/ \ : * ? " < > |` with one underscore; collapse repeated underscores; trim leading/trailing dots, spaces, and underscores.
- Truncate the sanitized project-name component to a UTF-8 byte budget of `255 - suffixBytes`, where `suffixBytes` is the UTF-8 byte length of `~{projectId}-SM-{yyyyMMdd}-{seq}.jpg`. Truncation iterates Unicode runes so multi-byte characters (CJK, Emoji) are never split. Fall back to `Project` when empty.
- Apply the new number only when a future capture reaches `markCaptured`; do not migrate or rename existing records or gallery files.
- Regenerating an existing photo preserves its stored number.
- Remove the visible number row from both Chinese and English watermarks without removing the persisted `photoNumber` field.
- Keep homepage watermark defaults scoped to newly created projects; do not change font-size or opacity semantics.
- Do not edit Drift or flutter_rust_bridge generated Dart files by hand.

## File Map

- Create: `lib/domain/photo_number.dart` — pure project-name sanitization and number formatting.
- Create: `test/domain/photo_number_test.dart` — formatter boundary and invalid-input tests.
- Modify: `lib/data/app_database.dart` — read the project and allocate the new number inside `markCaptured`.
- Modify: `test/data/app_database_test.dart` — database allocation and regeneration expectations.
- Modify: `test/workflow/capture_workflow_test.dart` — foreground workflow expectation.
- Modify: `test/workflow/capture_processor_test.dart` — render and MediaStore name expectations.
- Modify: `rust/src/api/image_core.rs` — omit the number logical line and add private-unit coverage.

---

### Task 1: Pure Photo Number Formatter

**Files:**
- Create: `test/domain/photo_number_test.dart`
- Create: `lib/domain/photo_number.dart`

**Interfaces:**
- Consumes: raw project name, project ID (ASCII `^[A-Za-z0-9_-]+$`), capture-local `DateTime`, and positive daily sequence.
- Produces: `safePhotoProjectName(String, {int maxJpegNameBytes, int suffixReserve}) -> String`, `const fallbackProjectName = 'Project'`, and `formatPhotoNumber({required String projectName, required String projectId, required DateTime capturedAt, required int sequence}) -> String`. Output format: `{safeProjectName}~{projectId}-SM-{yyyyMMdd}-{seq}`.

- [ ] **Step 1: Write the failing formatter tests**

Create `test/domain/photo_number_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/domain/photo_number.dart';

void main() {
  test('formats a project-prefixed daily photo number with full project id', () {
    expect(
      formatPhotoNumber(
        projectName: '东区厂房改造',
        projectId: 'project-1',
        capturedAt: DateTime(2026, 7, 17, 9, 5),
        sequence: 1,
      ),
      '东区厂房改造~project-1-SM-20260717-001',
    );
  });

  test('sanitizes unsafe characters and repeated separators', () {
    expect(safePhotoProjectName('  A 区 / 风管::检查  '), 'A_区_风管_检查');
  });

  test('sanitizes tilde from project names', () {
    expect(safePhotoProjectName('A~B'), 'A_B');
    expect(safePhotoProjectName('A~~B'), 'A_B');
  });

  test('truncates to fit the UTF-8 byte budget and trims result', () {
    final repeated = List.filled(60, '工').join();
    final safe = safePhotoProjectName(repeated);
    expect(utf8.encode(safe).length, lessThanOrEqualTo(231));
    expect(safe.runes.length, 60);
  });

  test('uses Project when no safe project characters remain', () {
    expect(safePhotoProjectName(' . / : ? _ '), 'Project');
  });

  test('rejects non-positive sequences', () {
    expect(
      () => formatPhotoNumber(
        projectName: '项目',
        projectId: 'p1',
        capturedAt: DateTime(2026, 7, 17),
        sequence: 0,
      ),
      throwsArgumentError,
    );
  });

  test('rejects project ids that are not safe ASCII', () {
    expect(
      () => formatPhotoNumber(
        projectName: '项目',
        projectId: '',
        capturedAt: DateTime(2026, 7, 17),
        sequence: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => formatPhotoNumber(
        projectName: '项目',
        projectId: 'a/b',
        capturedAt: DateTime(2026, 7, 17),
        sequence: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => formatPhotoNumber(
        projectName: '项目',
        projectId: '项目一',
        capturedAt: DateTime(2026, 7, 17),
        sequence: 1,
      ),
      throwsArgumentError,
    );
  });

  test('rejects a project id whose suffix exceeds the byte budget', () {
    final longId = List.filled(235, 'a').join();
    expect(
      () => formatPhotoNumber(
        projectName: '项目',
        projectId: longId,
        capturedAt: DateTime(2026, 7, 17),
        sequence: 1,
      ),
      throwsArgumentError,
    );
  });

  test('keeps final jpeg name within 255 UTF-8 bytes', () {
    final projectName = List.filled(60, '😀').join();
    final number = formatPhotoNumber(
      projectName: projectName,
      projectId: 'project-1',
      capturedAt: DateTime(2026, 7, 17),
      sequence: 1,
    );
    expect(utf8.encode('$number.jpg').length, lessThanOrEqualTo(255));
  });

  test('different project ids with same sanitized name produce different numbers', () {
    final a = formatPhotoNumber(
      projectName: 'A/B',
      projectId: 'aaaa1111-2222-3333-4444-555566667777',
      capturedAt: DateTime(2026, 7, 17),
      sequence: 1,
    );
    final b = formatPhotoNumber(
      projectName: 'A:B',
      projectId: 'bbbb2222-3333-4444-5555-666677778888',
      capturedAt: DateTime(2026, 7, 17),
      sequence: 1,
    );
    expect(a, isNot(equals(b)));
  });

  test('different ids sharing first 8 chars stay distinct', () {
    final a = formatPhotoNumber(
      projectName: '同名项目',
      projectId: 'aaaaaaaa-1111-2222-3333-444444444444',
      capturedAt: DateTime(2026, 7, 17),
      sequence: 1,
    );
    final b = formatPhotoNumber(
      projectName: '同名项目',
      projectId: 'aaaaaaaa-9999-8888-7777-666666666666',
      capturedAt: DateTime(2026, 7, 17),
      sequence: 1,
    );
    expect(a, isNot(b));
  });

  test('hyphen removal cannot collapse distinct project ids', () {
    final a = formatPhotoNumber(
      projectName: '同名项目',
      projectId: 'project-1',
      capturedAt: DateTime(2026, 7, 17),
      sequence: 1,
    );
    final b = formatPhotoNumber(
      projectName: '同名项目',
      projectId: 'project1',
      capturedAt: DateTime(2026, 7, 17),
      sequence: 1,
    );
    expect(a, isNot(b));
  });

  test('project name and id boundaries cannot collide', () {
    final a = formatPhotoNumber(
      projectName: 'A',
      projectId: 'B-C',
      capturedAt: DateTime(2026, 7, 17),
      sequence: 1,
    );
    final b = formatPhotoNumber(
      projectName: 'A-B',
      projectId: 'C',
      capturedAt: DateTime(2026, 7, 17),
      sequence: 1,
    );
    expect(a, isNot(b));
  });
}
```

- [ ] **Step 2: Run the formatter tests and verify RED**

Run:

```powershell
flutter test test/domain/photo_number_test.dart
```

Expected: FAIL because `package:sitemark/domain/photo_number.dart` does not exist.

- [ ] **Step 3: Implement the pure formatter**

Create `lib/domain/photo_number.dart`:

```dart
import 'dart:convert';

String safePhotoProjectName(
  String projectName, {
  int maxJpegNameBytes = 255,
  int suffixReserve = 24,
}) {
  var safe = projectName.trim().replaceAll(
    RegExp(r'[\s~ /\\:*?"<>|\x00-\x1F\x7F\x80-\x9F]+'),
    '_',
  );
  safe = safe.replaceAll(RegExp(r'_+'), '_');
  final byteBudget = maxJpegNameBytes - suffixReserve;
  if (byteBudget < 1) {
    return _trimToUtf8Bytes(safe, 1);
  }
  safe = _trimToUtf8Bytes(safe, byteBudget);
  safe = safe.replaceAll(RegExp(r'^[._ ]+|[._ ]+$'), '');
  return safe.isEmpty ? 'Project' : safe;
}

String _trimToUtf8Bytes(String value, int maxBytes) {
  final runes = value.runes.toList();
  var result = StringBuffer();
  var used = 0;
  for (final rune in runes) {
    final char = String.fromCharCodes([rune]);
    final charBytes = utf8.encode(char).length;
    if (used + charBytes > maxBytes) break;
    result.write(char);
    used += charBytes;
  }
  return result.toString();
}

const fallbackProjectName = 'Project';

String formatPhotoNumber({
  required String projectName,
  required String projectId,
  required DateTime capturedAt,
  required int sequence,
}) {
  if (sequence < 1) {
    throw ArgumentError.value(sequence, 'sequence', 'Must be positive');
  }
  if (projectId.isEmpty ||
      !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(projectId)) {
    throw ArgumentError.value(
      projectId,
      'projectId',
      'Expected a non-empty ASCII identifier (A-Z, a-z, 0-9, _, -)',
    );
  }
  String two(int value) => value.toString().padLeft(2, '0');
  final date =
      '${capturedAt.year.toString().padLeft(4, '0')}'
      '${two(capturedAt.month)}${two(capturedAt.day)}';
  final seq = sequence.toString().padLeft(3, '0');
  final projectKey = projectId;
  final suffix = '~$projectKey-SM-$date-$seq.jpg';
  final suffixBytes = utf8.encode(suffix).length;
  final fallbackBytes = utf8.encode(fallbackProjectName).length;
  if (suffixBytes + fallbackBytes > 255) {
    throw ArgumentError.value(
      projectId,
      'projectId',
      'Project ID is too long for a valid JPEG file name',
    );
  }
  final safe = safePhotoProjectName(projectName, suffixReserve: suffixBytes);
  final number = '$safe~$projectKey-SM-$date-$seq';
  if (utf8.encode('$number.jpg').length > 255) {
    throw StateError('Generated JPEG name exceeds 255 UTF-8 bytes');
  }
  return number;
}
```

- [ ] **Step 4: Run the formatter tests and verify GREEN**

Run:

```powershell
dart format lib/domain/photo_number.dart test/domain/photo_number_test.dart
flutter test test/domain/photo_number_test.dart
```

Expected: all 17 formatter tests PASS.

- [ ] **Step 5: Commit the formatter**

```powershell
git add lib/domain/photo_number.dart test/domain/photo_number_test.dart
git commit -m "feat: format project photo numbers"
```

---

### Task 2: Allocate and Publish the Project-Prefixed Number

**Files:**
- Modify: `lib/data/app_database.dart:1-5,349-366`
- Modify: `test/data/app_database_test.dart:104-174,263-300,396-424`
- Modify: `test/workflow/capture_workflow_test.dart:65-87,236-252`
- Modify: `test/workflow/capture_processor_test.dart:44-102,142-152,440-455`

**Interfaces:**
- Consumes: `formatPhotoNumber` from Task 1 and the parent `Project.name` read inside the existing `markCaptured` transaction.
- Produces: persisted `CaptureRecord.photoNumber` values such as `东区厂房改造~project-1-SM-20260717-001` (~ separator, projectId verbatim, hyphens preserved); `CaptureProcessor` continues passing that value to `RenderPhotoRequest.photoNumber` and `PlatformServices.publishJpeg`.

- [ ] **Step 1: Change allocation and publishing expectations first**

Update the generated-number assertions for projects named `车间改造` or `东区厂房改造`:

```dart
expect(captured.photoNumber, '车间改造~project-SM-20260716-001');
expect(captured.photoNumber, '车间改造~project-SM-20260716-003');
expect(edited.photoNumber, '车间改造~project-SM-20260716-001');
expect(updated?.photoNumber, '东区厂房改造~project-1-SM-20260716-001');
```

In `test/workflow/capture_workflow_test.dart`, use:

```dart
expect(record?.photoNumber, '东区厂房改造~project-1-SM-20260716-001');
expect(edited.photoNumber, '东区厂房改造~project-1-SM-20260716-001');
```

In `test/workflow/capture_processor_test.dart`, use:

```dart
expect(captured.photoNumber, '东区厂房改造~project-1-SM-20260716-001');
expect(platform.publishedNames, ['东区厂房改造~project-1-SM-20260716-001']);
expect(
  images.lastRenderRequest?.photoNumber,
  '东区厂房改造~project-1-SM-20260716-001',
);
```

Replace the remaining exact `publishedNames` expectations in that test file with the same project-prefixed value. Leave migration fixtures, manually constructed historical records, and export fixtures using `SM-...` unchanged; they prove backward compatibility.

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```powershell
flutter test test/data/app_database_test.dart test/workflow/capture_workflow_test.dart test/workflow/capture_processor_test.dart
```

Expected: FAIL because `markCaptured` still produces `SM-20260716-001` (no project name or project key prefix).

- [ ] **Step 3: Integrate the formatter at the allocation source**

Add the import in `lib/data/app_database.dart`:

```dart
import 'package:sitemark/domain/photo_number.dart';
```

Inside the existing `markCaptured` transaction, immediately after loading `current`, load its parent project:

```dart
final project = await (select(
  projects,
)..where((row) => row.id.equals(current.projectId))).getSingleOrNull();
if (project == null) {
  throw StateError('Capture project does not exist');
}
```

Replace the inline `SM-...` construction with a call to `formatPhotoNumber(projectName: project.name, projectId: current.projectId, capturedAt: capturedAt, sequence: sequence)`:

```dart
final number = formatPhotoNumber(
  projectName: project.name,
  capturedAt: capturedAt,
  sequence: highestSequence + 1,
);
```

Do not change `CaptureProcessor`: it already sends the stored number to both the Rust request and `publishJpeg`.

- [ ] **Step 4: Run database and workflow tests and verify GREEN**

Run:

```powershell
dart format lib/data/app_database.dart test/data/app_database_test.dart test/workflow/capture_workflow_test.dart test/workflow/capture_processor_test.dart
flutter test test/domain/photo_number_test.dart test/data/app_database_test.dart test/workflow/capture_workflow_test.dart test/workflow/capture_processor_test.dart
```

Expected: all selected tests PASS, including regeneration preserving the stored project-prefixed number.

- [ ] **Step 5: Commit allocation integration**

```powershell
git add lib/data/app_database.dart test/data/app_database_test.dart test/workflow/capture_workflow_test.dart test/workflow/capture_processor_test.dart
git commit -m "feat: include project names in new photo numbers"
```

---

### Task 3: Remove the Number from the Visible Watermark

**Files:**
- Modify: `rust/src/api/image_core.rs:486-545,850-950`

**Interfaces:**
- Consumes: unchanged `RenderPhotoRequest.photo_number` for traceability and export compatibility.
- Produces: `logical_watermark_lines(&RenderPhotoRequest) -> Vec<String>` without a number label or number value; adaptive layout automatically shrinks to the remaining rows.

- [ ] **Step 1: Add a failing private-unit test for both locales**

In the existing `#[cfg(test)] mod tests` in `rust/src/api/image_core.rs`, add:

```rust
#[test]
fn chinese_and_english_watermarks_omit_photo_number() {
    for locale in ["zh", "en"] {
        let request = sample_request(locale, 1.0, "东区厂房改造");
        let lines = logical_watermark_lines(&request);
        let text = lines.join("\n");

        assert!(!text.contains(&request.photo_number), "{locale}: {text}");
        assert!(!text.contains("编号"), "{locale}: {text}");
        assert!(!text.contains("Number"), "{locale}: {text}");
        assert_eq!(lines.len(), 5);
    }
}
```

- [ ] **Step 2: Run the Rust test and verify RED**

Run:

```powershell
cargo test chinese_and_english_watermarks_omit_photo_number --manifest-path rust/Cargo.toml
```

Expected: FAIL because the current logical lines contain `SM-20260716-001` (or the new project-prefixed form) and have 6 required rows.

- [ ] **Step 3: Remove only the visible number label and row**

Remove `number` from `WatermarkLabels`:

```rust
struct WatermarkLabels {
    title: &'static str,
    location: &'static str,
    content: &'static str,
    photographer: &'static str,
    time: &'static str,
    address: &'static str,
    coordinates: &'static str,
    notes: &'static str,
}
```

Remove the Chinese and English `number` label initializers. In `logical_watermark_lines`, keep these required lines and omit the number line:

```rust
let mut lines = vec![
    format!("{} · {}", labels.title, request.project_name),
    format!("{}  {}", labels.location, request.work_location),
    format!("{}  {}", labels.content, request.work_content),
    format!("{}  {}", labels.photographer, request.photographer),
    format!("{}  {}", labels.time, request.captured_at),
];
```

Do not delete `RenderPhotoRequest.photo_number`; export and record traceability still require it.

- [ ] **Step 4: Run Rust formatting, focused tests, and the full Rust suite**

Run:

```powershell
cargo fmt --manifest-path rust/Cargo.toml -- --check
cargo test chinese_and_english_watermarks_omit_photo_number --manifest-path rust/Cargo.toml
cargo test --manifest-path rust/Cargo.toml
cargo clippy --manifest-path rust/Cargo.toml -- -D warnings
```

Expected: the focused test and the full Rust suite PASS; fmt and clippy exit 0.

- [ ] **Step 5: Commit the watermark change**

```powershell
git add rust/src/api/image_core.rs
git commit -m "feat: remove photo number from watermarks"
```

---

### Task 4: Photo Naming Regression Gate

**Files:**
- Verify only; no expected production file changes.

**Interfaces:**
- Consumes: Tasks 1-3.
- Produces: a clean checkpoint before processing-status work begins.

- [ ] **Step 1: Run all naming and watermark tests together**

```powershell
flutter test test/domain/photo_number_test.dart test/data/app_database_test.dart test/workflow/capture_workflow_test.dart test/workflow/capture_processor_test.dart
cargo test --manifest-path rust/Cargo.toml
```

Expected: every selected Dart test and every Rust test PASS.

- [ ] **Step 2: Check formatting and the worktree**

```powershell
dart format --output=none --set-exit-if-changed lib test
cargo fmt --manifest-path rust/Cargo.toml -- --check
git diff --check
git status --short
```

Expected: all commands exit 0; `git status --short` has no uncommitted implementation changes.
