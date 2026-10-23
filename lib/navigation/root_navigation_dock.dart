import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sitemark/design_tokens.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';
import 'package:sitemark/shared/ui/glass_surface.dart';

/// Colorless glass chrome. The lens moves and deforms, while navigation and
/// branch lifetimes remain owned by the shell.
class RootNavigationDock extends StatefulWidget {
  const RootNavigationDock({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  }) : assert(selectedIndex >= 0 && selectedIndex < 3);

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  State<RootNavigationDock> createState() => _RootNavigationDockState();
}

class _RootNavigationDockState extends State<RootNavigationDock>
    with TickerProviderStateMixin {
  late final AnimationController _travel;
  late final AnimationController _press;
  late double _from;
  late double _to;
  double _shapeFrom = 0;
  bool _reduceMotion = false;

  double get _position =>
      lerpDouble(_from, _to, AppMotion.emphasized.transform(_travel.value))!;

  double get _deformation {
    if (_reduceMotion) return 0;
    final progress = _travel.value;
    return (_shapeFrom * (1 - AppMotion.emphasized.transform(progress)) +
            AppMotion.dockLensDeformation(progress) *
                math.min((_to - _from).abs(), 1.5))
        .clamp(0.0, 1.8);
  }

  @override
  void initState() {
    super.initState();
    _from = _to = widget.selectedIndex.toDouble();
    _travel = AnimationController(
      vsync: this,
      duration: AppMotion.rootSwitch,
      value: 1,
    );
    _press = AnimationController(vsync: this, duration: AppMotion.short4);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _travel.value = 1;
      _press.value = 0;
    }
  }

  @override
  void didUpdateWidget(covariant RootNavigationDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex == oldWidget.selectedIndex) return;
    // Sample the real visible position before retargeting rapid taps.
    final position = _position;
    _shapeFrom = _deformation;
    _from = position;
    _to = widget.selectedIndex.toDouble();
    _press.value = 0;
    if (_reduceMotion) {
      _travel.value = 1;
    } else {
      _travel.forward(from: 0);
    }
  }

  void _setPressed(int index, bool pressed) {
    if (_reduceMotion || (pressed && index != widget.selectedIndex)) return;
    if (pressed) {
      _press.animateTo(1, curve: AppMotion.standard);
    } else {
      _press.animateBack(0, curve: AppMotion.springSnapBack);
    }
  }

  @override
  void dispose() {
    _travel.dispose();
    _press.dispose();
    super.dispose();
  }

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDock.outerInset,
        0,
        AppDock.outerInset,
        AppDock.bottomInset,
      ),
      child: Align(
        alignment: Alignment.center,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppDock.maxWidth),
          child: GlassSurface(
            key: const Key('root-dock-surface'),
            style: GlassSurfaceStyle.navigation,
            borderRadius: AppDock.radius,
            blurOnAndroid: true,
            boxShadow: AppShadow.navigation(context),
            child: SizedBox(
              height: AppDock.height,
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.5,
                child: Padding(
                  padding: const EdgeInsets.all(AppDock.contentInset),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final rtl =
                          Directionality.of(context) == TextDirection.rtl;
                      final slotWidth =
                          constraints.maxWidth / destinations.length;
                      final restingWidth = slotWidth - AppDock.lensInset * 2;
                      return AnimatedBuilder(
                        animation: Listenable.merge([_travel, _press]),
                        child: Row(
                          children: [
                            for (final (index, destination)
                                in destinations.indexed)
                              Expanded(
                                child: _RootDestinationButton(
                                  destination: destination,
                                  selected: widget.selectedIndex == index,
                                  onPressedChanged: (pressed) =>
                                      _setPressed(index, pressed),
                                  onTap: () =>
                                      widget.onDestinationSelected(index),
                                ),
                              ),
                          ],
                        ),
                        builder: (context, buttons) {
                          final position = _position;
                          final center = slotWidth * (position + .5);
                          final centerX = rtl
                              ? constraints.maxWidth - center
                              : center;
                          final deformation = _deformation;
                          final pressed = _reduceMotion ? 0.0 : _press.value;
                          final width = math.min(
                            restingWidth *
                                (1 + deformation * .14 + pressed * .035),
                            math.min(centerX, constraints.maxWidth - centerX) *
                                2,
                          );
                          final height =
                              constraints.maxHeight *
                              (1 - deformation * .035 - pressed * .05);
                          final direction = (_to - _from).sign * (rtl ? -1 : 1);
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              Positioned(
                                left: centerX - width / 2,
                                top: (constraints.maxHeight - height) / 2,
                                width: width,
                                height: height,
                                child: IgnorePointer(
                                  child: GlassSurface(
                                    key: const Key('root-dock-glass-indicator'),
                                    style: GlassSurfaceStyle.lens,
                                    lightDirection: direction * deformation,
                                    borderRadius: AppDock.radius,
                                    blurSigma: 0,
                                    boxShadow: AppShadow.glassLens(context),
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                              ),
                              buttons!,
                            ],
                          );
                        },
                      );
                    },
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
    required this.onPressedChanged,
  });

  final _RootDestination destination;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<bool> onPressedChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final duration = AppMotion.durationOf(context, AppMotion.short4);
    final foreground = selected ? colors.onSurface : colors.onSurfaceVariant;
    return Tooltip(
      message: destination.label,
      child: Semantics(
        button: true,
        selected: selected,
        label: destination.label,
        child: Listener(
          onPointerDown: (_) => onPressedChanged(true),
          onPointerUp: (_) => onPressedChanged(false),
          onPointerCancel: (_) => onPressedChanged(false),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: Key('root-destination-${destination.keyName}'),
              onTap: () {
                if (!selected) HapticFeedback.selectionClick();
                onTap();
              },
              borderRadius: AppDock.radius,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ExcludeSemantics(
                    child: Column(
                      key: Key(
                        'root-destination-${destination.keyName}-content',
                      ),
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
                            size: AppDock.iconSize,
                            color: color,
                          ),
                        ),
                        const SizedBox(height: 2),
                        AnimatedDefaultTextStyle(
                          duration: duration,
                          curve: AppMotion.standard,
                          style:
                              (Theme.of(context).textTheme.labelSmall ??
                                      const TextStyle())
                                  .copyWith(
                                    fontSize: AppDock.labelSize,
                                    height: 1.15,
                                    color: foreground,
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  ),
                          // The full label remains visible even on a narrow
                          // phone with enlarged English text. Hit targets and
                          // semantics retain their full size.
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              destination.label,
                              maxLines: 1,
                              textAlign: TextAlign.center,
                            ),
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
