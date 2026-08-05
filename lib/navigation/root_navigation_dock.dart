import 'package:flutter/material.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';

class RootNavigationDock extends StatelessWidget {
  const RootNavigationDock({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final destinations = [
      _RootDestination(
        keyName: 'projects',
        icon: Icons.domain_outlined,
        selectedIcon: Icons.domain,
        label: strings.projects,
      ),
      _RootDestination(
        keyName: 'records',
        icon: Icons.photo_library_outlined,
        selectedIcon: Icons.photo_library,
        label: strings.allRecords,
      ),
      _RootDestination(
        keyName: 'settings',
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        label: strings.settings,
      ),
    ];
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          children: [
            for (final (index, destination) in destinations.indexed)
              Expanded(
                child: _RootDestinationButton(
                  destination: destination,
                  selected: selectedIndex == index,
                  onTap: () => onDestinationSelected(index),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RootDestination {
  const _RootDestination({
    required this.keyName,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final String keyName;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class _RootDestinationButton extends StatelessWidget {
  const _RootDestinationButton({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _RootDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(18);
    final duration = AppMotion.durationOf(context, AppMotion.short4);
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('root-destination-${destination.keyName}'),
          onTap: onTap,
          borderRadius: radius,
          child: Center(
            child: AnimatedContainer(
              key: selected
                  ? Key(
                      'root-destination-${destination.keyName}-selected-surface',
                    )
                  : null,
              duration: duration,
              curve: AppMotion.standard,
              constraints: const BoxConstraints(minWidth: 76),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: selected
                    ? colors.secondaryContainer
                    : Colors.transparent,
                borderRadius: radius,
              ),
              child: ExcludeSemantics(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      selected ? destination.selectedIcon : destination.icon,
                      size: 22,
                      color: selected
                          ? colors.onSecondaryContainer
                          : colors.onSurfaceVariant,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      destination.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: selected
                            ? colors.onSecondaryContainer
                            : colors.onSurfaceVariant,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
