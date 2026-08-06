import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';
import 'package:sitemark/navigation/root_chrome_controller.dart';
import 'package:sitemark/navigation/root_navigation_dock.dart';
import 'package:sitemark/shared/ui/floating_dock_layout.dart';
import 'package:sitemark/shared/ui/glass_surface.dart';

class RootNavigationScaffold extends ConsumerWidget {
  const RootNavigationScaffold({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

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
        return Scaffold(
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
                ? FloatingActionButton(
                    key: const Key('new-project-fab'),
                    heroTag: 'new-project-fab',
                    onPressed: () => context.push('/projects/new'),
                    tooltip: strings.newProject,
                    child: const Icon(Icons.add),
                  )
                : null,
            child: navigationShell,
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
  /// screen-width-fraction offsets. The current page tweens to 0; the
  /// outgoing page tweens to -direction; pages still on-screen when a
  /// switch is interrupted mid-flight continue exiting to -direction so
  /// the viewport never shows the scaffold background through a gap.
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
    final direction = widget.currentIndex > _currentIndex ? 1.0 : -1.0;
    final newTweens = <int, (double, double)>{};

    if (_controller.isAnimating && _controller.value < 1) {
      // Interrupted mid-flight: sample each active page's real on-screen
      // position so the next segment continues from where pages are now.
      final vp = AppMotion.emphasized.transform(_controller.value);
      double currentPosition(int index) {
        final tween = _activeTweens[index];
        if (tween == null) return 0;
        return lerpDouble(tween.$1, tween.$2, vp)!;
      }

      // The page that was sliding in becomes the new outgoing page.
      newTweens[_currentIndex] = (currentPosition(_currentIndex), -direction);

      // The new incoming page.
      if (widget.currentIndex == _fromIndex) {
        // Switching back to the old "from": it is still partially visible
        // on the opposite side, so enter from its current position.
        newTweens[widget.currentIndex] = (currentPosition(_fromIndex), 0);
      } else {
        // Switching to a third page: it starts fully off-screen.
        newTweens[widget.currentIndex] = (direction, 0);
      }

      // Any other page still on-screen (e.g. the old "from" in a chain
      // 0->1->2) keeps sliding out so no background gap appears.
      for (final index in _activeTweens.keys) {
        if (index == _currentIndex || index == widget.currentIndex) continue;
        final pos = currentPosition(index);
        if (pos.abs() < 1) {
          newTweens[index] = (pos, -direction);
        }
      }
    } else {
      // Clean switch from rest.
      newTweens[_currentIndex] = (0, -direction);
      newTweens[widget.currentIndex] = (direction, 0);
    }

    _activeTweens = newTweens;
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
