# SiteMark Backup Completeness and Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow empty projects to round-trip through backup/restore without silently omitting unfinished records, and add a privacy-preserving local diagnostics package under Settings.

**Architecture:** Backup gains a typed preflight snapshot and schema-v3 project archives. Diagnostics use a bounded, versioned JSONL event store whose writes are best-effort and whose export is user-triggered; application workflows emit only allow-listed categories and numeric metadata.

**Tech Stack:** Flutter 3.44.6, Dart, Riverpod, GoRouter, Drift, flutter_rust_bridge, Rust `zip`/`serde`, Kotlin/Pigeon Android system API, Flutter and Rust tests.

## Global Constraints

- Version is `0.8.0+11`.
- Empty schema-v3 project archives are restorable; v1 and v2 remain compatible.
- No record may be silently omitted from backup.
- Diagnostics stay local until the user explicitly shares them.
- Diagnostics retain at most 7 days and 2 MB.
- Diagnostics never contain photos, project names, engineering fields, people, coordinates, paths, photo numbers, hashes, or raw exception text.
- Diagnostics add no Android permission and no network access.
- The diagnostics privacy notice is visible on the page and repeated before sharing.
- Deliver through a GitHub Pull Request from `feat/backup-diagnostics`.

---

## File Map

**Create**

- `lib/workflow/project_backup_preflight.dart` — typed project/capture state snapshot.
- `lib/diagnostics/diagnostic_event.dart` — allow-listed diagnostic event schema.
- `lib/diagnostics/diagnostic_event_store.dart` — bounded JSONL persistence and rotation.
- `lib/diagnostics/diagnostic_recorder.dart` — non-blocking event facade and error classification.
- `lib/diagnostics/diagnostic_bundle_service.dart` — summary/environment collection and ZIP creation.
- `lib/features/settings/sections/diagnostics_section_screen.dart` — settings UI.
- Matching tests under `test/workflow/`, `test/diagnostics/`, and `test/features/settings/sections/`.

**Modify**

- `lib/workflow/project_bundle_service.dart` and `project_export_service.dart` — preflight enforcement, empty archives, structured results.
- `lib/workflow/project_import_service.dart` — schema-v3 project metadata restore.
- `rust/src/api/image_core.rs` and generated FRB files — schema-v3 archive and diagnostic ZIP support.
- `lib/app.dart`, `lib/features/settings/global_settings_screen.dart`, `lib/l10n/app_strings.dart` — providers, route, menu and copy.
- Capture/background/backup/restore/delete workflows — allow-listed diagnostic events.
- `packages/sitemark_system_api` Pigeon/Kotlin/Dart files — manufacturer/model/API snapshot without permissions.
- `pubspec.yaml`, About fallback/test, `README.md` — `0.8.0+11` and feature documentation.

---

### Task 1: Typed Backup Preflight

**Files:**
- Create: `lib/workflow/project_backup_preflight.dart`
- Modify: `lib/data/app_database.dart`
- Test: `test/workflow/project_backup_preflight_test.dart`

**Interfaces:**
- Produces:
  - `ProjectBackupPreflightService.inspect(List<String> projectIds)`
  - `ProjectBackupSnapshot`
  - `ProjectBackupProjectSnapshot`
  - `ProjectBackupDisposition`

- [ ] **Step 1: Write failing tests**

Cover empty, all-ready, processing, failed, mixed, duplicate selection and missing project:

```dart
expect(result.projects.single.disposition, ProjectBackupDisposition.empty);
expect(result.projects.single.readyCount, 0);
expect(result.projects.single.processingCount, 0);
expect(result.projects.single.failedCount, 0);
```

- [ ] **Step 2: Verify tests fail**

Run:

```powershell
flutter test test/workflow/project_backup_preflight_test.dart
```

Expected: compile failure because preflight types do not exist.

- [ ] **Step 3: Implement immutable snapshot types**

Use these exact dispositions:

```dart
enum ProjectBackupDisposition { empty, ready, processing, failed, missing }
```

`ProjectBackupSnapshot` includes `capturedAt`, ordered project snapshots and aggregate omitted/processing counts. Treat `pendingCamera`, `captured`, and `rendering` as processing; `failed` as failed; `ready` as ready.

- [ ] **Step 4: Run tests**

Expected: all preflight tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/workflow/project_backup_preflight.dart lib/data/app_database.dart test/workflow/project_backup_preflight_test.dart
git commit -m "feat: add typed backup preflight"
```

### Task 2: Schema-v3 Empty Project Archives

**Files:**
- Modify: `rust/src/api/image_core.rs`
- Modify: generated files under `lib/src/rust/` and `rust/src/frb_generated.rs`
- Test: `rust/tests/core_test.rs`

**Interfaces:**
- Extend `ExportProjectRequest` with:

```rust
pub project_description: Option<String>,
pub project_created_at: String,
pub snapshot_at: String,
pub omitted_processing_count: u32,
pub omitted_failed_count: u32,
```

- Extend archive preview with the same project metadata and omission counts.
- Add `export_diagnostic_bundle(DiagnosticBundleRequest)`.

- [ ] **Step 1: Write failing Rust round-trip tests**

Test a schema-v3 archive with zero photos, project description, created time, watermark settings and zero omission counts. Test a partial archive with non-zero omitted count. Keep existing v1/v2 fixtures passing.

- [ ] **Step 2: Verify tests fail**

```powershell
cargo test --manifest-path rust/Cargo.toml empty_project
```

- [ ] **Step 3: Implement schema v3**

Export new archives with `schema_version: 3`. Permit `photos.is_empty()` only when schema version is 3. Include empty BOM CSV and manifest. Preview must expose `is_partial` derived from omission counts.

- [ ] **Step 4: Add diagnostic ZIP writer**

`DiagnosticBundleRequest` accepts output path plus four already-sanitized byte/string payloads. Rust writes `summary.txt`, `environment.json`, `events.jsonl`, then creates `manifest.json` with schema version, generated time and SHA-256 for the first three entries.

- [ ] **Step 5: Regenerate FRB bindings**

```powershell
flutter_rust_bridge_codegen generate
dart format lib/src/rust
```

- [ ] **Step 6: Verify Rust and generated bindings**

```powershell
cargo fmt --manifest-path rust/Cargo.toml -- --check
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path rust/Cargo.toml
flutter analyze
```

- [ ] **Step 7: Commit**

```powershell
git add rust lib/src/rust
git commit -m "feat: support empty schema v3 project archives"
```

### Task 3: Dart Backup and Restore Round Trip

**Files:**
- Modify: `lib/workflow/project_export_service.dart`
- Modify: `lib/workflow/project_import_service.dart`
- Modify: `lib/workflow/project_bundle_service.dart`
- Modify: `lib/data/app_database.dart`
- Test: `test/workflow/project_export_test.dart`
- Test: `test/workflow/project_import_test.dart`
- Test: `test/workflow/project_bundle_service_test.dart`

**Interfaces:**
- `ProjectBackupService.exportProjects` consumes a confirmed `ProjectBackupSnapshot`.
- `ProjectBackupResult` includes `omittedProcessingCount` and `omittedFailedCount`.

- [ ] **Step 1: Write failing empty-project and partial-backup tests**

Assert:

```dart
expect(result.photoCount, 0);
expect(restored.project.description, '项目说明');
expect(restored.project.createdAt, originalCreatedAt);
expect(result.omittedFailedCount, 2);
```

- [ ] **Step 2: Verify failure**

Run the three workflow test files.

- [ ] **Step 3: Remove the empty-ready-record rejection**

Build an empty photo request for an empty project. Pass description, original creation time, preflight snapshot time and omission counts into Rust.

- [ ] **Step 4: Enforce the confirmed snapshot**

Before file export, inspect again. If project disappearance or processing counts differ, return a typed failure and create no final ZIP. A partial backup is allowed only when the caller passes an explicit `allowFailedOmissions: true`.

- [ ] **Step 5: Restore v3 metadata**

Restore description and creation time for v3. Keep current defaults for v1/v2 fields that did not exist. Empty restore still goes through durable ownership/finalization.

- [ ] **Step 6: Run workflow tests**

Expected: empty, complete, partial, mixed bundle and compatibility cases pass.

- [ ] **Step 7: Commit**

```powershell
git add lib/workflow lib/data test/workflow
git commit -m "feat: preserve empty projects in backups"
```

### Task 4: Backup UI Reasons and Actions

**Files:**
- Modify: `lib/features/settings/sections/project_backup_selection_screen.dart`
- Modify: `lib/l10n/app_strings.dart`
- Test: `test/features/settings/sections/project_backup_selection_screen_test.dart`

**Interfaces:**
- UI calls preflight before the originals dialog.
- Processing blocks with a project/count list.
- Failed rows require “返回处理” or “仅备份已完成记录”.

- [ ] **Step 1: Add failing widget tests**

Verify:

- empty card subtitle says it will preserve project data/settings;
- processing dialog names the affected project and suggests waiting;
- failed dialog does not default to partial export;
- confirming partial export passes `allowFailedOmissions: true`;
- completion message repeats the omitted count;
- 360 dp width has no overflow.

- [ ] **Step 2: Run widget tests and confirm failure**

- [ ] **Step 3: Implement dialogs and localized copy**

Do not expose `StateError.toString()`. Map typed result/failure values to Chinese and English copy with a concrete next step.

- [ ] **Step 4: Verify widget tests**

- [ ] **Step 5: Commit**

```powershell
git add lib/features/settings/sections/project_backup_selection_screen.dart lib/l10n/app_strings.dart test/features/settings/sections/project_backup_selection_screen_test.dart
git commit -m "feat: explain backup completeness before export"
```

### Task 5: Bounded Diagnostic Event Store

**Files:**
- Create: `lib/diagnostics/diagnostic_event.dart`
- Create: `lib/diagnostics/diagnostic_event_store.dart`
- Create: `lib/diagnostics/diagnostic_recorder.dart`
- Test: `test/diagnostics/diagnostic_event_store_test.dart`
- Test: `test/diagnostics/diagnostic_recorder_test.dart`

**Interfaces:**
- `DiagnosticRecorder.record(DiagnosticEvent event)` is non-blocking/best-effort.
- Event fields are enums, timestamps, durations, counts and booleans only.
- `DiagnosticEventStore.readRecent`, `clear`, `sizeBytes`.

- [ ] **Step 1: Write failing allow-list and rotation tests**

Test 7-day expiry, 2 MB oldest-first rotation, malformed trailing line, concurrent writes and clear. Assert serialized output cannot contain injected project/path/error strings.

- [ ] **Step 2: Verify failure**

- [ ] **Step 3: Implement fixed event schema**

Use categories:

```dart
enum DiagnosticCategory {
  app,
  camera,
  processing,
  backup,
  restore,
  deletion,
  permission,
}
```

Payload uses a fixed `Map<String, int|bool|String>` whose string values are validated enums/codes, never caller-provided prose.

- [ ] **Step 4: Implement locked JSONL append and rotation**

Serialize writes within the isolate and use an exclusive file lock across isolates. If lock acquisition exceeds the short diagnostic budget, abandon that event without surfacing an error to the workflow. Ignore malformed trailing lines on read.

- [ ] **Step 5: Verify diagnostic core tests**

- [ ] **Step 6: Commit**

```powershell
git add lib/diagnostics test/diagnostics
git commit -m "feat: add bounded local diagnostic recorder"
```

### Task 6: Device Snapshot and Diagnostic Bundle

**Files:**
- Modify: `pigeons/system_api.dart`
- Modify: `packages/sitemark_system_api/lib/src/system_api.g.dart`
- Modify: `packages/sitemark_system_api/android/src/main/kotlin/io/github/wikg1018/sitemark/system/SystemApi.g.kt`
- Modify: `packages/sitemark_system_api/android/src/main/kotlin/io/github/wikg1018/sitemark/system/AndroidSystemApi.kt`
- Test: `packages/sitemark_system_api/android/src/test/kotlin/io/github/wikg1018/sitemark/system/AndroidSystemApiTest.kt`
- Create: `lib/diagnostics/diagnostic_bundle_service.dart`
- Test: `test/diagnostics/diagnostic_bundle_service_test.dart`

**Interfaces:**
- `DeviceDiagnosticInfo { manufacturer, model, androidRelease, apiLevel }`
- `DiagnosticBundleService.generate()` returns final ZIP path.

- [ ] **Step 1: Add failing platform contract tests**

Verify device snapshot contains only the four approved fields and needs no permission.

- [ ] **Step 2: Regenerate Pigeon code and implement Kotlin**

Use `Build.MANUFACTURER`, `Build.MODEL`, `Build.VERSION.RELEASE`, and `Build.VERSION.SDK_INT`.

- [ ] **Step 3: Add failing diagnostic bundle tests**

Assert exact ZIP entries and that generated text/JSON has no forbidden key names or fixture secrets.

- [ ] **Step 4: Implement bundle generation**

Collect package version, device info, locale, storage totals, state counts and recent sanitized events. Call Rust diagnostic ZIP export. Delete older generated diagnostic ZIP after the new one is committed.

- [ ] **Step 5: Verify Dart, Rust and native tests**

- [ ] **Step 6: Commit**

```powershell
git add pigeons packages lib/diagnostics test/diagnostics android rust lib/src/rust
git commit -m "feat: generate private local diagnostic bundles"
```

### Task 7: Settings Diagnostics UI

**Files:**
- Create: `lib/features/settings/sections/diagnostics_section_screen.dart`
- Modify: `lib/features/settings/global_settings_screen.dart`
- Modify: `lib/app.dart`
- Modify: `lib/l10n/app_strings.dart`
- Test: `test/features/settings/sections/diagnostics_section_screen_test.dart`
- Test: `test/features/settings/global_settings_screen_test.dart`

**Interfaces:**
- Route: `/settings/diagnostics`
- Actions: view summary, generate/share, clear.

- [ ] **Step 1: Write failing widget tests**

Require the visible privacy card text:

```text
诊断记录只保存在本机，不会自动上传。
```

Require the second confirmation before share and both included/excluded lists. Verify Back returns exactly one level.

- [ ] **Step 2: Verify failure**

- [ ] **Step 3: Implement route, card and actions**

Show current retention, byte size and last failure category. Clearing requires confirmation. Sharing uses the existing Android share sheet service.

- [ ] **Step 4: Run widget tests at normal and 360 dp widths**

- [ ] **Step 5: Commit**

```powershell
git add lib/app.dart lib/features/settings lib/l10n/app_strings.dart test/features/settings
git commit -m "feat: add diagnostics and feedback settings"
```

### Task 8: Workflow Diagnostic Integration

**Files:**
- Modify: `lib/workflow/capture_workflow.dart`
- Modify: `lib/workflow/capture_processor.dart`
- Modify: `lib/background/capture_background_scheduler.dart`
- Modify: `lib/workflow/project_bundle_service.dart`
- Modify: `lib/workflow/project_import_service.dart`
- Modify: `lib/workflow/project_deletion_service.dart`
- Modify providers in `lib/app.dart`.
- Test: `test/workflow/capture_workflow_test.dart`
- Test: `test/workflow/capture_processor_test.dart`
- Test: `test/background/capture_background_scheduler_test.dart`
- Test: `test/workflow/project_bundle_service_test.dart`
- Test: `test/workflow/project_import_test.dart`
- Test: `test/workflow/project_deletion_service_test.dart`

**Interfaces:**
- Every workflow receives an optional `DiagnosticRecorder`.
- Diagnostics calls are unawaited/best-effort and never change workflow results.

- [ ] **Step 1: Write failing integration tests**

For each workflow, verify success/failure category and numeric duration/count fields. Inject a recorder that throws and verify the core operation still returns the same result.

- [ ] **Step 2: Verify failure**

- [ ] **Step 3: Wire approved events**

Reuse existing `CaptureLaunchTiming`. Add camera result, processing retry/result, backup preflight/result, restore result and deletion result. Map raw exceptions to allow-listed codes before recording.

- [ ] **Step 4: Verify workflow tests**

- [ ] **Step 5: Commit**

```powershell
git add lib/app.dart lib/workflow lib/background test/workflow test/background
git commit -m "feat: record privacy-safe workflow diagnostics"
```

### Task 9: Version, README and Release Gate

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/features/settings/sections/about_section_screen.dart`
- Modify: `test/features/settings/sections/about_section_screen_test.dart`
- Modify: `README.md`

- [ ] **Step 1: Update version contract**

Set `version: 0.8.0+11`, About fallback `0.8.0`/`11`, and expected widget text `0.8.0+11`.

- [ ] **Step 2: Update README**

Document empty-project backup, preflight/partial warnings, diagnostics location/privacy/retention, and use `v0.8.0` release links without claiming the release already exists.

- [ ] **Step 3: Run full verification**

```powershell
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
cargo fmt --manifest-path rust/Cargo.toml -- --check
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path rust/Cargo.toml
.\android\gradlew.bat -p android :sitemark_system_api:testDebugUnitTest
flutter build apk --debug
```

Expected: every command exits 0.

- [ ] **Step 4: Verify APK contract**

Use `aapt dump badging` to confirm package `io.github.wikg1018.sitemark`, version name `0.8.0`, universal debug version code `11`, min SDK 31 and target SDK 36. Verify merged release permissions still exclude INTERNET, CAMERA, background location and broad media access.

- [ ] **Step 5: Commit**

```powershell
git add pubspec.yaml lib/features/settings/sections/about_section_screen.dart test/features/settings/sections/about_section_screen_test.dart README.md
git commit -m "release: prepare v0.8.0"
```

- [ ] **Step 6: Push and create PR**

```powershell
git push -u origin feat/backup-diagnostics
gh pr create --base main --head feat/backup-diagnostics --title "feat: complete backups and add local diagnostics"
```

PR body must include scope, privacy guarantees, compatibility, exact test counts and manual testing still required.
