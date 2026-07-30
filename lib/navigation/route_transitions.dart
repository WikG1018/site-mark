import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/motion.dart';

/// Whether the route currently covering a project page is a photo detail
/// route (or its editor).
///
/// [GoRouterState.uri] on a parent page does not include routes added with
/// `context.push`, while [GoRouterState.topRoute] does. Inspecting the latter
/// therefore covers both normal taps and deep links, while deliberately
/// excluding sibling project routes such as settings and capture forms.
bool shouldFreezeProjectCaptureList(GoRouterState state) {
  final topRoute = state.topRoute;
  return topRoute is GoRoute &&
      (topRoute.path == 'captures/:captureId' || topRoute.path == 'edit');
}

/// Builds the page-body transition used by photo details and their editor.
///
/// The Hero image flies in the navigator overlay and is therefore unaffected
/// by this fade. The page body fades continuously while sliding, instead of
/// staying fully opaque until the route is abruptly removed at the end.
Widget buildCaptureDetailRouteTransition({
  required Animation<double> animation,
  required Widget child,
}) {
  final position = Tween<Offset>(begin: const Offset(0.08, 0), end: Offset.zero)
      .animate(
        CurvedAnimation(
          parent: animation,
          curve: AppMotion.emphasizedDecelerate,
          reverseCurve: AppMotion.emphasizedAccelerate,
        ),
      );
  final opacity = CurvedAnimation(
    parent: animation,
    curve: AppMotion.standard,
    reverseCurve: AppMotion.standard,
  );

  return FadeTransition(
    opacity: opacity,
    child: SlideTransition(position: position, child: child),
  );
}

/// Builds the shared-axis transition used by hierarchical pages.
///
/// Capture-list pages set [freezeSecondary] so they stay fully painted while a
/// photo detail route is on top. This prevents the returning Hero from landing
/// on a list that is simultaneously fading and translating underneath it.
Widget buildSharedAxisRouteTransition({
  required BuildContext context,
  required Animation<double> animation,
  required Animation<double> secondaryAnimation,
  required Widget child,
  bool freezeSecondary = false,
}) {
  if (MediaQuery.disableAnimationsOf(context)) {
    return child;
  }
  return SharedAxisTransition(
    animation: animation,
    secondaryAnimation: freezeSecondary
        ? kAlwaysDismissedAnimation
        : secondaryAnimation,
    transitionType: SharedAxisTransitionType.horizontal,
    child: child,
  );
}

/// Builds the fade-through transition used by top-level destinations.
///
/// See [buildSharedAxisRouteTransition] for why capture-list destinations
/// freeze their secondary animation while a photo detail route covers them.
Widget buildFadeThroughRouteTransition({
  required BuildContext context,
  required Animation<double> animation,
  required Animation<double> secondaryAnimation,
  required Widget child,
  bool freezeSecondary = false,
}) {
  if (MediaQuery.disableAnimationsOf(context)) {
    return child;
  }
  return FadeThroughTransition(
    animation: animation,
    secondaryAnimation: freezeSecondary
        ? kAlwaysDismissedAnimation
        : secondaryAnimation,
    child: child,
  );
}
