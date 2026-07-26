import 'package:flutter/material.dart';
import 'package:sitemark/features/settings/settings_section_scaffold.dart';
import 'package:sitemark/l10n/app_strings.dart';

/// Shared ChoiceChip for accent color selection.
///
/// Used by the appearance screen (app theme seed color), the watermark
/// defaults screen, and the project watermark settings screen.
class AccentChoiceChip extends StatelessWidget {
  const AccentChoiceChip({
    super.key,
    required this.argb,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final int argb;
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      avatar: CircleAvatar(backgroundColor: Color(argb)),
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }
}

/// Maps a swatch ARGB value to its localized label.
///
/// Returns the empty string for unknown ARGB values.
String accentLabel(AppStrings strings, int argb) {
  for (final swatch in accentSwatches) {
    if (swatch.argb == argb) {
      return switch (swatch.labelKey) {
        'green' => strings.green,
        'blue' => strings.blue,
        'orange' => strings.orange,
        'red' => strings.red,
        'purple' => strings.purple,
        'teal' => strings.teal,
        'pink' => strings.pink,
        'yellow' => strings.yellow,
        'indigo' => strings.indigo,
        _ => '',
      };
    }
  }
  return '';
}
