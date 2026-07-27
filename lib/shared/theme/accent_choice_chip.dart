// lib/shared/theme/accent_choice_chip.dart
import 'package:flutter/material.dart';

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
