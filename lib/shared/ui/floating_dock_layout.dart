import 'package:flutter/material.dart';
import 'package:sitemark/motion.dart';
import 'package:sitemark/navigation/scroll_chrome.dart';

const double floatingDockHorizontalInset = 14;
const double floatingDockBottomInset = 12;
const double floatingDockHeight = 68;
const double floatingDockReservedSpace = 100;
const double floatingDockFabReservedSpace = 164;

/// Bottom content inset that keeps the final item scrollable above root
/// chrome on devices with any gesture-navigation safe area.
double floatingDockReservedSpaceOf(
  BuildContext context, {
  bool avoidFloatingActionButton = false,
}) {
  final base = avoidFloatingActionButton
      ? floatingDockFabReservedSpace
      : floatingDockReservedSpace;
  return base + MediaQuery.paddingOf(context).bottom;
}

/// Keeps page content full-height while positioning bottom chrome above the
/// system safe area.
class FloatingDockLayout extends StatelessWidget {
  const FloatingDockLayout({
    super.key,
    required this.child,
    this.dock,
    this.floatingActionButton,
    this.animateDock = true,
    this.dockKey = const Key('floating-dock-slot'),
  });

  final Widget child;
  final Widget? dock;
  final Widget? floatingActionButton;
  final bool animateDock;
  final Key dockKey;

  @override
  Widget build(BuildContext context) {
    final bottomSafeArea = MediaQuery.paddingOf(context).bottom;
    final duration = animateDock
        ? AppMotion.durationOf(context, AppMotion.medium4)
        : Duration.zero;
    final chromeVisible = ScrollChromeScope.visibleOf(context);
    final chromeDuration = scrollChromeAnimationOf(context);
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
            child: _slideChrome(
              visible: chromeVisible,
              duration: chromeDuration,
              hiddenOffset: const Offset(0, 1.8),
              child: action,
            ),
          ),
        Positioned(
          left: floatingDockHorizontalInset,
          right: floatingDockHorizontalInset,
          bottom: bottomSafeArea + floatingDockBottomInset,
          child: _slideChrome(
            visible: chromeVisible,
            duration: chromeDuration,
            hiddenOffset: const Offset(0, 1.5),
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
        ),
      ],
    );
  }
}

Widget _slideChrome({
  required bool visible,
  required Duration duration,
  required Offset hiddenOffset,
  required Widget child,
}) {
  return AnimatedSlide(
    duration: duration,
    curve: AppMotion.emphasized,
    offset: visible ? Offset.zero : hiddenOffset,
    child: IgnorePointer(ignoring: !visible, child: child),
  );
}
