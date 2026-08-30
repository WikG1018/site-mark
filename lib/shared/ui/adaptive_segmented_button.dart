import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Segmented selection that follows each platform's control shape.
///
/// The API mirrors [SegmentedButton] (segments/selected/onSelectionChanged),
/// so call sites only swap the class name: Material platforms render the
/// original [SegmentedButton]; iOS renders a `CupertinoSlidingSegmentedControl`
/// — the native sliding segmented control.
class AdaptiveSegmentedButton<T extends Object> extends StatelessWidget {
  const AdaptiveSegmentedButton({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
    this.style,
  });

  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>> onSelectionChanged;

  /// Material-only tuning (e.g. the 48dp tap-target style); iOS sizes the
  /// control natively and ignores it.
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return SegmentedButton<T>(
        segments: segments,
        selected: selected,
        onSelectionChanged: onSelectionChanged,
        style: style,
      );
    }
    return CupertinoSlidingSegmentedControl<T>(
      groupValue: selected.isEmpty ? null : selected.single,
      onValueChanged: (value) {
        if (value == null) return;
        // The sliding control has no built-in selection haptic; native iOS
        // segmented controls tick on every change.
        HapticFeedback.selectionClick();
        onSelectionChanged({value});
      },
      children: {
        for (final segment in segments)
          segment.value: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: segment.label,
          ),
      },
    );
  }
}
