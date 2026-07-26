import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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

/// Builds the shared-axis transition used by hierarchical pages.
///
/// Capture-list pages set [freezeSecondary] so they stay fully painted while a
/// photo detail route is on top. This prevents the returning Hero from landing
/// on a list that is simultaneously fading and translating underneath it.
Widget buildSharedAxisRouteTransition({
  required Animation<double> animation,
  required Animation<double> secondaryAnimation,
  required Widget child,
  bool freezeSecondary = false,
}) {
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
  required Animation<double> animation,
  required Animation<double> secondaryAnimation,
  required Widget child,
  bool freezeSecondary = false,
}) {
  return FadeThroughTransition(
    animation: animation,
    secondaryAnimation: freezeSecondary
        ? kAlwaysDismissedAnimation
        : secondaryAnimation,
    child: child,
  );
}
