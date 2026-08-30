// lib/features/settings/settings_section_scaffold.dart
import 'package:flutter/material.dart';
import 'package:sitemark/shared/ui/adaptive_page_scaffold.dart';

/// Segmented buttons default to 40dp; lifting to 48dp meets Android tap-target.
const segmentTapTargetStyle = ButtonStyle(
  minimumSize: WidgetStatePropertyAll<Size>(Size.fromHeight(48)),
);

/// Standard scaffold for a settings sub-page: AppBar with the section title,
/// scrollable body with consistent padding. On iOS this is the large-title
/// collapsing nav bar (see [AdaptivePageScaffold]).
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
    return AdaptivePageScaffold(title: title, body: body);
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
