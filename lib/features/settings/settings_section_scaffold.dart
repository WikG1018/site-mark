// lib/features/settings/settings_section_scaffold.dart
import 'package:flutter/material.dart';

/// Accent swatches offered as new-project watermark defaults AND app theme
/// seed colors. Each entry carries a stable [Key] for test discovery and a
/// `labelKey` string that callers map to an [AppStrings] getter via
/// [accentLabel].
const accentSwatches = <({int argb, Key key, String labelKey})>[
  (argb: 0xff37c58b, key: Key('accent-green'),  labelKey: 'green'),
  (argb: 0xff1565c0, key: Key('accent-blue'),   labelKey: 'blue'),
  (argb: 0xffef6c00, key: Key('accent-orange'), labelKey: 'orange'),
  (argb: 0xffc62828, key: Key('accent-red'),    labelKey: 'red'),
  (argb: 0xff6a1b9a, key: Key('accent-purple'), labelKey: 'purple'),
  (argb: 0xff00838f, key: Key('accent-teal'),   labelKey: 'teal'),
  (argb: 0xffad1457, key: Key('accent-pink'),   labelKey: 'pink'),
  (argb: 0xfff9a825, key: Key('accent-yellow'), labelKey: 'yellow'),
  (argb: 0xff283593, key: Key('accent-indigo'), labelKey: 'indigo'),
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
