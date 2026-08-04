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
