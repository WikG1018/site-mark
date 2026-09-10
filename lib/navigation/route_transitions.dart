import 'package:animations/animations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sitemark/motion.dart';

/// Travel distance of the secondary-page drift under an Android push.
const Offset _androidSecondaryDrift = Offset(-0.04, 0);

/// Push enter travel for hierarchical pages (list → detail).
const Offset _androidEnterBegin = Offset(0.14, 0);

/// Push enter travel for project detail, which stays lighter than a full
/// hierarchical push so the project list under it remains the visual anchor.
const Offset _androidProjectEnterBegin = Offset(0.08, 0);

/// Pop exit travel. Push and pop share one timeline but not one travel
/// distance: the page enters from a short offset, yet must visibly leave
/// toward [exitOffset] while fading out.
const Offset _androidExitOffset = Offset(0.28, 0);

/// Floor of the enter fade. The page is already mostly opaque at the first
/// frame so content is readable, then settles fully opaque as it lands.
const double _androidEnterOpacityFloor = 0.72;

/// Enter depth cue applied to the page body only. Hero flights live in the
/// navigator overlay and stay outside this scale.
const double _androidEnterScaleStart = 0.985;

Widget _androidPageSlide({
  required Animation<double> animation,
  required Widget child,
  Animation<double>? secondaryAnimation,
  Offset begin = _androidEnterBegin,
  Offset exitOffset = _androidExitOffset,
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
        // Enter: light fade-in + settle scale while sliding. Exit: fade out
        // with the slide. Both paths keep a continuous opacity timeline so
        // the page never pops out at full opacity and then disappears.
        //
        // Scale tracks the raw controller value (not the direction-curved
        // progress) so a pop mid-enter continues from the current size
        // instead of snapping 0.985 → 1.0 on the first reverse frame.
        final opacity = exiting
            ? progress
            : _androidEnterOpacityFloor +
                  (1 - _androidEnterOpacityFloor) * progress;
        final scale =
            _androidEnterScaleStart +
            (1 - _androidEnterScaleStart) * animation.value;
        return FadeTransition(
          opacity: AlwaysStoppedAnimation<double>(opacity),
          child: SlideTransition(
            key: slideKey,
            position: Tween<Offset>(
              begin: exiting ? exitOffset : begin,
              end: Offset.zero,
            ).animate(AlwaysStoppedAnimation<double>(progress)),
            // Isolate the page paint so the transform/fade only moves a
            // layer instead of re-rasterizing list and photo subtrees every
            // transition frame. Scale sits on the page body only.
            // Scale must wrap the RepaintBoundary, not sit inside it: the
            // boundary caches one raster of the page, and a changing scale
            // outside only re-composites that layer instead of re-rasterizing
            // photo-heavy subtrees every enter frame.
            child: Transform.scale(
              key: const Key('android-page-scale'),
              scale: scale,
              alignment: Alignment.center,
              child: RepaintBoundary(child: child),
            ),
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
      position: Tween<Offset>(begin: Offset.zero, end: _androidSecondaryDrift)
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
    // Freeze the covered capture list: a secondary drift re-rasterizes the
    // thumbnail grid every frame and is the main source of push jank on
    // mid-range Android devices. Matches the shared-axis freeze policy.
    return _androidPageSlide(
      animation: animation,
      secondaryAnimation: null,
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
      begin: _androidProjectEnterBegin,
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
///
/// On Android the covered page is always frozen: photo-heavy lists re-rasterize
/// under a secondary drift every frame, which is the main source of push jank
/// on mid-range devices.
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
      secondaryAnimation: null,
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
      secondaryAnimation: null,
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
