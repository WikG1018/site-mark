import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedAlign(
              alignment: Alignment(-1 + selectedIndex.toDouble(), 0),
              duration: AppMotion.durationOf(context, AppMotion.rootSwitch),
              curve: AppMotion.emphasized,
              child: FractionallySizedBox(
                widthFactor: 1 / destinations.length,
                heightFactor: 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: DecoratedBox(
                    key: const Key('root-dock-glass-indicator'),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          scheme.surface.withValues(alpha: isDark ? .48 : .42),
                          scheme.surfaceContainerHighest.withValues(
                            alpha: isDark ? .28 : .22,
                          ),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: scheme.onSurface.withValues(alpha: .14),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.shadow.withValues(
                            alpha: isDark ? .14 : .08,
                          ),
                          blurRadius: isDark ? 14 : 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(
                            alpha: isDark ? 0.08 : 0.18,
                          ),
                          width: 1,
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(
                              alpha: isDark ? 0.10 : 0.16,
                            ),
                            Colors.white.withValues(alpha: 0),
                          ],
                          stops: const [0.0, 0.45],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Row(
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
    final foreground = selected ? colors.onSurface : colors.onSurfaceVariant;
    return Tooltip(
      message: destination.label,
      child: Semantics(
        button: true,
        selected: selected,
        label: destination.label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: Key('root-destination-${destination.keyName}'),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            borderRadius: radius,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 76),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: ExcludeSemantics(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TweenAnimationBuilder<Color?>(
                          tween: ColorTween(end: foreground),
                          duration: duration,
                          curve: AppMotion.standard,
                          builder: (context, color, _) => Icon(
                            selected
                                ? destination.selectedIcon
                                : destination.icon,
                            size: 22,
                            color: color,
                          ),
                        ),
                        const SizedBox(height: 1),
                        AnimatedDefaultTextStyle(
                          duration: duration,
                          curve: AppMotion.standard,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: foreground,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ) ??
                              TextStyle(color: foreground),
                          child: Text(
                            destination.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
