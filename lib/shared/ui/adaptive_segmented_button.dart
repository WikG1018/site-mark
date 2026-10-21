import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sitemark/design_tokens.dart';

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
      return LayoutBuilder(
        builder: (context, constraints) {
          // Preserve readable labels instead of splitting words to squeeze
          // three choices into a narrow phone or a large-text setting.
          final textStyle =
              style?.textStyle?.resolve({}) ??
              Theme.of(context).textTheme.labelLarge;
          var widest = 0.0;
          for (final segment in segments) {
            final label = segment.label;
            if (label is! Text) continue;
            final painter = TextPainter(
              text: TextSpan(
                text: label.data,
                style: textStyle?.merge(label.style),
              ),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
              maxLines: 1,
            )..layout();
            // Horizontal padding plus room for the selection checkmark.
            final width = painter.width + 56;
            if (width > widest) widest = width;
            painter.dispose();
          }
          final vertical =
              constraints.hasBoundedWidth &&
              widest * segments.length > constraints.maxWidth;
          final control = SegmentedButton<T>(
            segments: vertical
                ? [
                    for (final segment in segments)
                      ButtonSegment<T>(
                        value: segment.value,
                        icon: segment.icon,
                        tooltip: segment.tooltip,
                        enabled: segment.enabled,
                        label: segment.label == null
                            ? null
                            : ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: (constraints.maxWidth - 56).clamp(
                                    0,
                                    double.infinity,
                                  ),
                                ),
                                child: segment.label,
                              ),
                      ),
                  ]
                : segments,
            selected: selected,
            direction: vertical ? Axis.vertical : Axis.horizontal,
            // Material's control ships without haptics while the iOS branch
            // ticks natively; parity lives here, on real changes only.
            onSelectionChanged: (value) {
              if (!setEquals(value, selected)) {
                HapticFeedback.selectionClick();
              }
              onSelectionChanged(value);
            },
            // Stadium corners on a vertical control cut across the first
            // and last label. A full-width rounded group remains readable.
            style: vertical
                ? (style ?? const ButtonStyle()).copyWith(
                    shape: const WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(AppRadius.md),
                      ),
                    ),
                  )
                : style,
          );
          return vertical
              ? SizedBox(width: constraints.maxWidth, child: control)
              : control;
        },
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
