import 'package:flutter/material.dart';
import 'package:sitemark/motion.dart';

const double floatingDockHorizontalInset = 14;
const double floatingDockBottomInset = 12;
const double floatingDockHeight = 80;
const double floatingDockReservedSpace = 112;

/// Keeps page content full-height while positioning bottom chrome above the
/// system safe area.
class FloatingDockLayout extends StatelessWidget {
  const FloatingDockLayout({
    super.key,
    required this.child,
    this.dock,
    this.floatingActionButton,
    this.dockKey = const Key('floating-dock-slot'),
  });

  final Widget child;
  final Widget? dock;
  final Widget? floatingActionButton;
  final Key dockKey;

  @override
  Widget build(BuildContext context) {
    final bottomSafeArea = MediaQuery.paddingOf(context).bottom;
    final duration = AppMotion.durationOf(context, AppMotion.medium4);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: child),
        if (floatingActionButton case final action?)
          Positioned(
            right: 16,
            bottom:
                bottomSafeArea +
                floatingDockBottomInset +
                floatingDockHeight +
                12,
            child: action,
          ),
        Positioned(
          left: floatingDockHorizontalInset,
          right: floatingDockHorizontalInset,
          bottom: bottomSafeArea + floatingDockBottomInset,
          child: AnimatedSwitcher(
            key: dockKey,
            duration: duration,
            switchInCurve: AppMotion.emphasizedDecelerate,
            switchOutCurve: AppMotion.emphasizedAccelerate,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, .12),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: dock == null
                ? const SizedBox.shrink(key: ValueKey('floating-dock-empty'))
                : SizedBox(
                    key: ValueKey(('floating-dock-content', dock!.key)),
                    width: double.infinity,
                    child: dock,
                  ),
          ),
        ),
      ],
    );
  }
}
