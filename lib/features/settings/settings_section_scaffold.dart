// lib/features/settings/settings_section_scaffold.dart
import 'package:flutter/material.dart';

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
      body: ListView(padding: const EdgeInsets.all(20), children: [body]),
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
