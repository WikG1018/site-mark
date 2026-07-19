import 'package:flutter/material.dart';

/// Compact 44dp dropdown-style filter menu for one-row filter bars.
///
/// Wraps a [MenuAnchor] with an [OutlinedButton] builder so multiple menus can
/// share a single [Row] at narrow widths (e.g. 360dp) without overflowing.
/// The label stays centered without a trailing chevron so four controls remain
/// readable when they share a single narrow row.
class CompactFilterMenu<T> extends StatelessWidget {
  const CompactFilterMenu({
    super.key,
    required this.label,
    required this.selectedValue,
    required this.entries,
    required this.onSelected,
    this.enabled = true,
  });

  final String label;
  final T selectedValue;
  final List<(T, String)> entries;
  final ValueChanged<T> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colorScheme.surfaceContainer),
        surfaceTintColor: WidgetStatePropertyAll(colorScheme.surfaceTint),
        shadowColor: WidgetStatePropertyAll(
          colorScheme.shadow.withValues(alpha: 0.18),
        ),
        elevation: const WidgetStatePropertyAll(6),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 6),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(152, 0)),
        maximumSize: const WidgetStatePropertyAll(Size(280, double.infinity)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      alignmentOffset: const Offset(0, 6),
      clipBehavior: Clip.antiAlias,
      animated: true,
      menuChildren: [
        for (final entry in entries)
          MenuItemButton(
            onPressed: () => onSelected(entry.$1),
            style: MenuItemButton.styleFrom(
              foregroundColor: entry.$1 == selectedValue
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurface,
              backgroundColor: entry.$1 == selectedValue
                  ? colorScheme.primaryContainer
                  : Colors.transparent,
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            leadingIcon: entry.$1 == selectedValue
                ? const Icon(Icons.check_rounded, size: 20)
                : const SizedBox.square(dimension: 20),
            child: Text(entry.$2, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      builder: (context, controller, _) => SizedBox(
        height: 44,
        child: OutlinedButton(
          onPressed: enabled ? controller.open : null,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
