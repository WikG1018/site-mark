import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';
import 'package:sitemark/navigation/root_chrome_controller.dart';
import 'package:sitemark/navigation/root_navigation_dock.dart';
import 'package:sitemark/shared/ui/floating_dock_layout.dart';
import 'package:sitemark/shared/ui/adaptive_floating_button.dart';
import 'package:sitemark/shared/ui/glass_surface.dart';

class RootNavigationScaffold extends ConsumerWidget {
  const RootNavigationScaffold({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// [WidgetsApp.onNavigationNotification] for the root shell contract.
  ///
  /// The shell claims every system back, so the framework always handles
  /// backs and the engine's predictive-back callback must stay registered.
  /// Reporting the raw [NavigationNotification.canHandlePop] instead lets it
  /// oscillate with branch-level PopScope state: an idle root page reports
  /// false (unregistering the callback), and re-arming it when the user
  /// enters selection mode races the system — a back press then exits to the
  /// launcher instead of cancelling the selection.
  static bool handleSystemBackContract(NavigationNotification notification) {
    SystemNavigator.setFrameworkHandlesBack(true);
    return true;
  }

  /// Only the three top-level tabs own the home dock.
  ///
  /// Nested routes such as project detail (`/projects/:id`) and capture detail
  /// must keep this false. The home dock must never appear on project screens.
  static bool isRootTabPath(String path) {
    return path == '/' || path == '/records' || path == '/settings';
  }

  /// Visible location used for root chrome decisions.
  ///
  /// Prefer [GoRouter.state] over [RouteInformationProvider.value.uri]:
  /// `context.push` / imperative routes leave the browser-style URI on the
  /// previous shell location (`/`) while the real top page is nested. Using
  /// that URI is what made the home dock reappear over project detail.
  static String visiblePathOf(GoRouter router) {
    final statePath = router.state.uri.path;
    if (statePath.isNotEmpty) {
      return statePath;
    }
    return router.routeInformationProvider.value.uri.path;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = GoRouter.of(context);
    // Listen to both providers: go() updates RouteInformation, push/pop of
    // imperative routes notifies the router delegate.
    return ListenableBuilder(
      listenable: Listenable.merge([
        router.routeInformationProvider,
        router.routerDelegate,
      ]),
      builder: (context, _) {
        final strings = AppStrings.of(context);
        final path = visiblePathOf(router);
        final showRootNavigation = isRootTabPath(path);
        final recordsSelecting = ref.watch(allCapturesSelectionModeProvider);
        final hideForSelection = path == '/records' && recordsSelecting;
        // The shell is the deepest system-back guard: branch screens
        // (selection mode, search, filters) consume backs first through their
        // own PopScopes, so a back that reaches this scope means nothing in
        // the active branch wanted it and the app should exit. Claiming the
        // back unconditionally also keeps the engine's predictive-back
        // callback registered at all times: if frameworkHandlesBack ever
        // drops to false on an idle root page, re-arming it when the user
        // enters selection mode races the system and a back press then exits
        // to the launcher instead of cancelling the selection.
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            SystemNavigator.pop();
          },
          child: Scaffold(
            body: FloatingDockLayout(
              animateDock: path != '/records',
              dock: showRootNavigation && !hideForSelection
                  ? GlassSurface(
                      key: const Key('root-dock'),
                      borderRadius: BorderRadius.circular(22),
                      child: SizedBox(
                        height: floatingDockHeight,
                        child: RootNavigationDock(
                          selectedIndex: navigationShell.currentIndex,
                          onDestinationSelected: (index) =>
                              navigationShell.goBranch(
                                index,
                                initialLocation:
                                    index == navigationShell.currentIndex,
                              ),
                        ),
                      ),
                    )
                  : null,
              floatingActionButton:
                  showRootNavigation && navigationShell.currentIndex == 0
                  ? AdaptiveFloatingButton(
                      key: const Key('new-project-fab'),
                      heroTag: 'new-project-fab',
                      onPressed: () => context.push('/projects/new'),
                      tooltip: strings.newProject,
                      icon: Icons.add,
                    )
                  : null,
              child: navigationShell,
            ),
          ),
        );
      },
    );
  }
}

class RootBranchContainer extends StatefulWidget {
  const RootBranchContainer({
    super.key,
    required this.currentIndex,
    required this.children,
  });

  final int currentIndex;
  final List<Widget> children;

  /// Plans the next dock-switch animation's page offsets.
  ///
  /// Returns a map of page index -> (start, end) screen-width-fraction
  /// offsets. Every page still covering the viewport during the transition is
  /// in the map; pages that have fully exited (|position| >= 1 at the moment
  /// of the switch) are dropped so the build offstages them. The current page
  /// always tweens to 0; every other planned page tweens to |end| == 1 so the
  /// viewport [0, 1] is fully covered by the union of page spans at every
  /// animation progress (asserted by the planner tests).
  ///
  /// [interruptProgress] is the curve-transformed controller progress (0..1)
  /// sampled at the moment of the switch, or null when the switch starts from
  /// rest. A mid-flight switch samples each active page's real on-screen
  /// position so the next segment continues from where pages are now instead
  /// of snapping back to the center.
  ///
  /// Pure (no state, no animation side effects) so the interruption geometry
  /// can be exhaustively property-tested.
  @visibleForTesting
  static Map<int, (double, double)> planTweens({
    required Map<int, (double, double)> previous,
    required int currentIndex,
    required int targetIndex,
    double? interruptProgress,
  }) {
    final direction = targetIndex > currentIndex ? 1.0 : -1.0;
    final newTweens = <int, (double, double)>{};

    if (interruptProgress == null) {
      // Clean switch from rest: the outgoing page exits to the far side of
      // the new direction while the incoming page enters from that side.
      newTweens[currentIndex] = (0, -direction);
      newTweens[targetIndex] = (direction, 0);
      return newTweens;
    }

    double currentPosition(int index) {
      final tween = previous[index];
      if (tween == null) return 0;
      return lerpDouble(tween.$1, tween.$2, interruptProgress)!;
    }

    // The page that was sliding in becomes the new outgoing page.
    newTweens[currentIndex] = (currentPosition(currentIndex), -direction);

    if (previous.containsKey(targetIndex)) {
      // The target page is already on-screen (e.g. snapping back to a page
      // that was mid-exit during a rapid chain like 0->1->2->0). Continue
      // from its current position so it doesn't jump.
      newTweens[targetIndex] = (currentPosition(targetIndex), 0);
    } else {
      // Enter from just outside the outgoing page on the new direction's
      // side, so the incoming page stays edge-to-edge with the outgoing page.
      // Starting from the far edge (|direction| == 1) would leave a
      // background gap when the outgoing page is still near the center —
      // e.g. reverse 0->2->1: page 2 sits at ~+0.6, page 1 entering from
      // -1 leaves a gap in the middle until page 1 crosses the center.
      newTweens[targetIndex] = (currentPosition(currentIndex) + direction, 0);
    }

    // Any other page still on-screen keeps sliding out so no background gap
    // appears. The exit direction is based on the page's index relative to
    // the new target, NOT its current pixel position and NOT the new switch
    // direction: pages with index < target must exit left, pages with
    // index > target must exit right. Using position (e.g. `pos < 0`) is
    // wrong because during a long rapid chain a page can momentarily cross
    // the center (e.g. 0->1->2->0 late-interrupt: page 1 may be at -0.1
    // after sliding left fast, but index 1 > 0 so it must exit right —
    // sending it left would pull it away from page 2 and open a gap). Using
    // `-direction` is also wrong for reverse jumps (e.g. 0->2->1: page 0 is
    // on the left, but -direction = +1 would send it across the screen to
    // the right).
    for (final index in previous.keys) {
      if (index == currentIndex || index == targetIndex) continue;
      final pos = currentPosition(index);
      if (pos.abs() < 1) {
        newTweens[index] = (pos, index < targetIndex ? -1.0 : 1.0);
      }
    }
    return newTweens;
  }

  @override
  State<RootBranchContainer> createState() => _RootBranchContainerState();
}

class _RootBranchContainerState extends State<RootBranchContainer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late int _fromIndex;
  late int _currentIndex;
  bool _disableAnimations = false;

  /// Active branch page tweens during a transition: [index] -> (start, end)
  /// screen-width-fraction offsets. Planned by [planTweens]; the current page
  /// tweens to 0 and every other page still on screen exits to a side
  /// (|end| == 1) so the viewport is always fully covered by pages.
  Map<int, (double, double)> _activeTweens = const {};

  @override
  void initState() {
    super.initState();
    _fromIndex = _currentIndex = widget.currentIndex;
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.rootSwitch,
      value: 1,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (_disableAnimations && _controller.value != 1) {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant RootBranchContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex == _currentIndex) return;
    if (_disableAnimations) {
      _fromIndex = _currentIndex;
      _currentIndex = widget.currentIndex;
      _activeTweens = const {};
      _controller.value = 1;
      return;
    }
    final interrupted = _controller.isAnimating && _controller.value < 1;
    _activeTweens = RootBranchContainer.planTweens(
      previous: _activeTweens,
      currentIndex: _currentIndex,
      targetIndex: widget.currentIndex,
      interruptProgress: interrupted
          ? AppMotion.emphasized.transform(_controller.value)
          : null,
    );
    _fromIndex = _currentIndex;
    _currentIndex = widget.currentIndex;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    assert(widget.currentIndex >= 0);
    assert(widget.currentIndex < widget.children.length);
    return ClipRect(
      child: AnimatedBuilder(
        animation: _controller,
        // Branch page trees are passed as [child] so animation ticks only
        // rebuild the transform wrappers, not the branch content.
        builder: (context, child) {
          final progress = AppMotion.emphasized.transform(_controller.value);
          final transitioning =
              !_disableAnimations &&
              _controller.value < 1 &&
              _fromIndex != _currentIndex;
          // Mode wrappers stay in the builder so _currentIndex/_fromIndex
          // update every tick. Page content lives in [child] and is stable.
          final branches = (child! as Stack).children;
          return Stack(
            fit: StackFit.expand,
            children: [
              for (final (index, branchChild) in branches.indexed)
                Offstage(
                  key: Key('root-branch-offstage-$index'),
                  offstage:
                      index != _currentIndex &&
                      !(transitioning && _activeTweens.containsKey(index)),
                  child: RepaintBoundary(
                    // Full-width horizontal slide ("one continuous take"):
                    // outgoing page exits by one full width while the incoming
                    // page enters by one full width. No scale — scale made the
                    // switch feel like a zoom/card handoff instead of a pan.
                    // [_activeTweens] holds each visible page's (start, end)
                    // offset; pages still on-screen when a switch is
                    // interrupted keep sliding out so no background gap shows.
                    child: FractionalTranslation(
                      key: Key('root-branch-translation-$index'),
                      translation: Offset(
                        transitioning && _activeTweens.containsKey(index)
                            ? lerpDouble(
                                _activeTweens[index]!.$1,
                                _activeTweens[index]!.$2,
                                progress,
                              )!
                            : 0,
                        0,
                      ),
                      child: HeroMode(
                        enabled: index == _currentIndex,
                        child: TickerMode(
                          enabled: index == _currentIndex,
                          child: IgnorePointer(
                            ignoring: index != _currentIndex,
                            child: ExcludeSemantics(
                              excluding: index != _currentIndex,
                              child: branchChild,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
        child: Stack(children: widget.children),
      ),
    );
  }
}
