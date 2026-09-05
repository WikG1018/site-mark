import 'package:animations/animations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sitemark/motion.dart';

Widget _androidPageSlide({
  required Animation<double> animation,
  required Widget child,
  Animation<double>? secondaryAnimation,
  Offset begin = const Offset(0.08, 0),
  Offset exitOffset = const Offset(0.30, 0),
  Key? clipKey,
  Key? slideKey,
}) {
  // Push and pop share one timeline but not one travel distance: the page
  // enters from [begin], yet must visibly leave toward [exitOffset] while
  // fading out — stopping at [begin] and then vanishing reads as a glitch.
  // The status flips to reverse before the first pop frame, so the exit
  // tween engages without switching the widget tree. Curves are applied to
  // the raw progress here instead of via CurvedAnimation, whose forward/
  // reverse direction is decided by status-change order and not by the
  // status the builder observes.
  Widget page = ClipRect(
    key: clipKey ?? const Key('android-page-slide'),
    child: ListenableBuilder(
      listenable: animation,
      builder: (context, _) {
        final exiting = animation.status == AnimationStatus.reverse;
        final progress = exiting
            ? AppMotion.emphasizedAccelerate.transform(animation.value)
            : AppMotion.emphasizedDecelerate.transform(animation.value);
        return FadeTransition(
          opacity: exiting
              ? AlwaysStoppedAnimation<double>(progress)
              : const AlwaysStoppedAnimation<double>(1.0),
          child: SlideTransition(
            key: slideKey,
            position: Tween<Offset>(
              begin: exiting ? exitOffset : begin,
              end: Offset.zero,
            ).animate(AlwaysStoppedAnimation<double>(progress)),
            child: child,
          ),
        );
      },
    ),
  );
  final secondary = secondaryAnimation;
  if (secondary != null) {
    // The covered page drifts a little toward the incoming one and settles
    // back when it pops — depth without an extra blur or scale layer. The
    // curve is symmetric, so direction handling is a non-issue here.
    page = SlideTransition(
      key: const Key('android-page-secondary-slide'),
      position: Tween<Offset>(begin: Offset.zero, end: const Offset(-0.04, 0))
          .animate(
            CurvedAnimation(
              parent: secondary,
              curve: AppMotion.standard,
              reverseCurve: AppMotion.standard,
            ),
          ),
      child: page,
    );
  }
  return page;
}

/// Builds the page-body transition used by photo details and their editor.
///
/// The Hero image flies in the navigator overlay and is therefore unaffected
/// by this fade. The page body fades continuously while sliding, instead of
/// staying fully opaque until the route is abruptly removed at the end.
Widget buildCaptureDetailRouteTransition({
  required Animation<double> animation,
  Animation<double>? secondaryAnimation,
  required Widget child,
}) {
  if (defaultTargetPlatform == TargetPlatform.android) {
    return _androidPageSlide(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
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

/// Builds the lightweight transition between the project list and detail.
///
/// Unlike a shared-axis transition this does not transform the project list
/// underneath the incoming page. Keeping that list geometrically stable
/// prevents its recent-photo strip from flashing across the screen while the
/// detail route is popped.
Widget buildProjectDetailRouteTransition({
  required BuildContext context,
  required Animation<double> animation,
  Animation<double>? secondaryAnimation,
  required Widget child,
}) {
  if (MediaQuery.disableAnimationsOf(context)) {
    return child;
  }
  if (defaultTargetPlatform == TargetPlatform.android) {
    return _androidPageSlide(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      begin: const Offset(0.045, 0),
      clipKey: const Key('project-detail-route-clip'),
      slideKey: const Key('project-detail-route-slide'),
      child: child,
    );
  }

  final curvedAnimation = CurvedAnimation(
    parent: animation,
    curve: AppMotion.emphasizedDecelerate,
    reverseCurve: AppMotion.emphasizedAccelerate,
  );
  final position = Tween<Offset>(
    begin: const Offset(0.045, 0),
    end: Offset.zero,
  ).animate(curvedAnimation);

  return ClipRect(
    key: const Key('project-detail-route-clip'),
    child: FadeTransition(
      key: const Key('project-detail-route-fade'),
      opacity: curvedAnimation,
      child: SlideTransition(
        key: const Key('project-detail-route-slide'),
        position: position,
        child: child,
      ),
    ),
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
  if (defaultTargetPlatform == TargetPlatform.android) {
    return _androidPageSlide(
      animation: animation,
      secondaryAnimation: freezeSecondary ? null : secondaryAnimation,
      child: child,
    );
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
  if (defaultTargetPlatform == TargetPlatform.android) {
    return _androidPageSlide(
      animation: animation,
      secondaryAnimation: freezeSecondary ? null : secondaryAnimation,
      child: child,
    );
  }
  return FadeThroughTransition(
    animation: animation,
    secondaryAnimation: freezeSecondary
        ? kAlwaysDismissedAnimation
        : secondaryAnimation,
    child: child,
  );
}
