# Task 4 execution report

Date: 2026-08-04
Branch: `design/ui-refresh-v2`
Task 3 baseline: `4252963`

## Scope

Implemented only Task 4: a pure project-action bottom sheet, a compact glass
project summary, and the required project-detail navigation/back behavior. No
database schema, data model, backup contract, deletion semantics, or project
lifecycle rule was changed. No push was performed and Task 5 was not started.

## RED evidence

### Unified project action sheet and back chain

Command:

`flutter test test/features/capture/capture_filter_ui_test.dart test/navigation/back_navigation_test.dart`

Result before production changes:

- exit code `1`;
- 30 tests discovered: 27 passed and 3 failed;
- the project detail still exposed the standalone watermark tooltip;
- `project-action-sheet` was absent after tapping `project-actions`;
- the new lifecycle-aware `pin-project` action was absent.

These were feature failures from the old standalone buttons and `PopupMenu`,
not compilation, syntax, or fixture errors.

### Remove the old lifecycle shortcut

Command:

`flutter test test/features/capture/capture_filter_ui_test.dart --plain-name "project action sheet follows lifecycle and pin state"`

Result before removing the status-banner action:

- exit code `1`;
- the selected test failed because completed/archived details still exposed a
  `reopen-project` button before the unified sheet opened.

## GREEN implementation

- Added the public `ProjectAction` enum and
  `showProjectActionSheet(BuildContext, Project)` in
  `project_action_sheet.dart`.
- Kept the sheet UI-only. It computes localized rows from `Project` state,
  returns the selected enum, and holds no database, workflow service, or
  navigation dependency.
- The sheet uses `useSafeArea: true`, `showDragHandle: true`, and a scrollable
  height so every action remains reachable. Delete icon and label use
  `colorScheme.error`.
- Moved watermark, backup, rename, pin/unpin, complete/archive/reopen, and
  delete into the sheet. Active, completed, and archived projects expose only
  their valid lifecycle actions.
- The project detail owns all effects after the sheet returns: existing
  navigation, database pin updates, lifecycle workflow, rename dialog, and
  delete preview/confirmation are unchanged.
- Backup navigation passes exactly `{project.id}` through
  `ProjectBackupSelectionArguments.initialProjectIds`.
- Reduced the normal project-detail app bar to search and more (plus the
  automatic back button). The selection entry moved to a compact glass summary
  showing project name, lifecycle status, and photo count.
- Removed the old status-banner reopen shortcut so lifecycle operations have a
  single entry point. The completed/archived informational banner remains.
- Preserved the selection controller and select-all implementation. System
  back now has verified behavior across sheet, search, selection, and page
  layers without changing the established selection/search order.
- Updated legacy widget flows to enter watermark, backup, and lifecycle actions
  through the new sheet.

## Verification

- Required focused tests: `30/30` passed.
- Fresh project-detail, lifecycle, and paged-selection regression set:
  `45/45` passed.
- Earlier broader project-detail/search/selection/lifecycle/backup regression
  set after entry-point migration: `69/69` passed.
- `flutter analyze`: `No issues found`.
- Full `flutter test`: `770/770` passed, exit code `0`.
- `git diff --check`: exit code `0`.

The full suite printed the repository's existing Drift multiple-database debug
warning and dependency-update notices. Neither failed verification, and no
dependency was changed.

## Handoff

- The implementation commit uses the requested title:
  `feat: simplify project detail actions`.
- This report is included as the Task 4 execution handoff.
- No push was performed.
- Task 5 was not started.

## Review follow-up

### Review decisions

- Accepted the project-switch race. The action sheet previously captured the
  `Project` shown when it opened, so an action could still mutate that project
  or navigate for it after the same detail `State` switched to another ID.
- Kept the established `selection -> search -> page` back order. Selection is
  entered after search and is therefore the topmost UI mode; reversing the
  order would violate the requested edit-mode cancellation behavior.
- Added missing end-to-end action, constrained-layout, and accessibility
  coverage.

### Follow-up RED evidence

Before the guard, four focused regressions failed:

- an action sheet opened for project A could pin A after the detail switched to
  project B;
- its backup action could navigate using stale project A state;
- rename used the name captured when the sheet opened rather than the latest
  same-ID database row;
- a lifecycle action that became illegal while the sheet was open still ran
  and surfaced a conflict.

The new real-database pin/unpin/complete/archive test passed immediately as a
characterization test. The 360dp bilingual 3x-text assertions also passed; its
first run failed only because the test's semantics handle was disposed by a
late teardown, which was corrected without a production change.

The combined search-plus-selection test initially appeared to fail on its
second back. Instrumentation confirmed both back events reached the page
`PopScope`; the second event ran `_exitSearch`. The stale finder result was the
outgoing search widget at the exact 180ms `AnimatedSwitcher` boundary. Waiting
for animations to settle made the regression deterministic; no production back
order change was needed.

### Follow-up implementation

- Record the project ID when the action sheet opens and reject its result if
  the detail widget has switched IDs, including a second guard after the
  database await.
- Re-read the project before every effect, reject deleted rows, and verify that
  the selected action remains legal for the latest pin/lifecycle state.
- Execute navigation, rename, pinning, lifecycle, and deletion with the fresh
  row instead of the captured sheet input.
- Verify both stale database actions and stale backup navigation, plus latest
  same-ID rename and lifecycle legality.
- Verify real database/service side effects for pin, unpin, complete, and
  archive.
- Verify Chinese and English action sheets at 360dp and 3x text remain
  scrollable through delete, tappable, correctly labeled in semantics, free of
  overflow, and visually preserve the delete danger color.
- Verify combined search and selection uses two-step LIFO back behavior.

### Follow-up verification

- Focused project-action and back-navigation tests: `36/36` passed.
- Related project, lifecycle, deletion, backup, paged-selection, and Task 2
  navigation suites: `128/128` passed.
- `flutter analyze`: `No issues found`.
- Full `flutter test`: `776/776` passed, exit code `0`.
- `git diff --check`: exit code `0`.
- The full suite emitted only the repository's existing Drift
  multiple-database debug warning and dependency-update notices.
- No push was performed and Task 5 was not started.
