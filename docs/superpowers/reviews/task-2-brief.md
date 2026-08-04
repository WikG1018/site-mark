# Task 2: Create shared scaffold and helpers

**Source:** `docs/superpowers/plans/2026-07-25-settings-secondary-menu.md` (Task 2)

## Goal
Create a shared scaffold + presentational helpers used by all 7 settings sub-pages (Tasks 3–9).

## Files
- Create: `lib/features/settings/settings_section_scaffold.dart`
- No test (pure presentational, per plan).

## Interfaces (produces — later tasks depend on these exact names)
- `SettingsSectionScaffold` widget (constructor: `{required String title, required Widget body}`)
- `SectionHeader` widget (constructor: `{required String label}`)
- `accentSwatches` const list of `({int argb, Key key})`
- `segmentTapTargetStyle` const `ButtonStyle`

## Implementation (from plan, with controller-noted correction)

**IMPORTANT correction:** The plan's code block for Task 2 imports `package:sitemark/l10n/app_strings.dart` and `package:sitemark/motion.dart`, but neither `SettingsSectionScaffold` nor `SectionHeader` actually uses them. These would be flagged as `unused_import` by `flutter analyze`. **Drop both imports** — only `package:flutter/material.dart` is needed.

Corrected code:

```dart
// lib/features/settings/settings_section_scaffold.dart
import 'package:flutter/material.dart';

/// Accent swatches offered as new-project watermark defaults.
const accentSwatches = <({int argb, Key key})>[
  (argb: 0xff37c58b, key: Key('accent-green')),
  (argb: 0xff1565c0, key: Key('accent-blue')),
  (argb: 0xffef6c00, key: Key('accent-orange')),
];

/// Segmented buttons default to 40dp; lifting to 48dp meets Android tap-target.
const segmentTapTargetStyle = ButtonStyle(
  minimumSize: WidgetStatePropertyAll<Size>(Size.fromHeight(48)),
);

/// Standard scaffold for a settings sub-page: AppBar with the section title,
/// scrollable body with consistent padding.
class SettingsSectionScaffold extends StatelessWidget {
  const SettingsSectionScaffold({
    super.key,
    required this.title,
    required this.body,
  });

  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [body],
      ),
    );
  }
}

/// Section header label used inside sub-pages.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
```

## Context for the implementer

- The existing `lib/features/settings/global_settings_screen.dart` (lines 21–31) has private `_accentSwatches` and `_segmentTapTargetStyle` with IDENTICAL values and the same `WidgetStatePropertyAll` API. Task 2 creates the PUBLIC versions in the new file. Task 10 (later) will rewrite `global_settings_screen.dart` and remove the now-redundant private copies. Do NOT modify `global_settings_screen.dart` in this task.
- `WidgetStatePropertyAll` (not `MaterialStatePropertyAll`) is the correct Flutter 3.x API — matches existing code.
- `SectionHeader` is in the plan's Produces list but may not be used by every later task. Keep it per the plan; the final whole-branch review will triage if it ends up unused (YAGNI).

## Verification

Run: `flutter analyze lib/features/settings/settings_section_scaffold.dart`
Expected: No issues (in particular, no `unused_import` warnings).

## Commit

```bash
git add lib/features/settings/settings_section_scaffold.dart
git commit -m "feat: add shared settings section scaffold and helpers"
```

## Global Constraints (binding)
- All existing widget test assertions must pass after refactor (234+ tests).
- l10n keys are unchanged — reuse existing `AppStrings` keys.
- No new dependencies; no schema changes.
- Commit messages in English; code comments follow user language (Chinese for domain logic, English for technical).
