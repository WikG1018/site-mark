import 'package:flutter/material.dart';

/// Compact 44dp dropdown-style filter menu for one-row filter bars.
///
/// Wraps a [MenuAnchor] with an [OutlinedButton] builder so multiple menus can
/// share a single [Row] at narrow widths (e.g. 360dp) without overflowing.
/// The label stays centered in the entire control while the chevron is pinned
/// to the right, so its visual center does not shift.
class CompactFilterMenu<T> extends StatelessWidget {
  const CompactFilterMenu({
    super.key,
    required this.label,
    required this.entries,
    required this.onSelected,
    this.enabled = true,
  });

  final String label;
  final List<(T, String)> entries;
  final ValueChanged<T> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    menuChildren: [
      for (final entry in entries)
        MenuItemButton(
          onPressed: () => onSelected(entry.$1),
          child: Text(entry.$2),
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
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            const Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Center(child: Icon(Icons.arrow_drop_down, size: 18)),
            ),
          ],
        ),
      ),
    ),
  );
}
