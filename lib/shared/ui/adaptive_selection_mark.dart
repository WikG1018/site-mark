import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sitemark/motion.dart';

/// Selection affordance that follows each platform: a Material [Checkbox]
/// everywhere else; a Photos-style round checkmark on iOS.
class AdaptiveSelectionMark extends StatelessWidget {
  const AdaptiveSelectionMark({
    super.key,
    required this.selected,
    this.onChanged,
    this.size = 26,
  });

  final bool selected;

  /// Null disables interaction, mirroring [Checkbox.onChanged].
  final ValueChanged<bool>? onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return SizedBox.square(
        dimension: size + 6,
        child: Checkbox(
          value: selected,
          onChanged: onChanged == null
              ? null
              : (value) => onChanged!(value ?? false),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!selected),
      // Photos-style round checkmark: pop in with a scale settle so the
      // state change reads as lively rather than a hard swap.
      child: AnimatedScale(
        duration: AppMotion.short4,
        curve: AppMotion.springScaleSettle,
        scale: selected ? 1 : .82,
        child: Icon(
          selected
              ? CupertinoIcons.checkmark_circle_fill
              : CupertinoIcons.circle,
          size: size,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
