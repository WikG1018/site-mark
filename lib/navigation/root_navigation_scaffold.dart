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

  /// Visual offsets (in screen-width fractions) at the start of the current
  /// animation. When an animation is interrupted mid-flight, these capture
  /// the actual on-screen positions so the next segment starts from where
  /// the pages currently are — no snap-back to center.
  double _fromStartOffset = 0;
  double _toStartOffset = 0;

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
      _fromStartOffset = 0;
      _toStartOffset = 0;
      _controller.value = 1;
      return;
    }
    // Compute the current visual positions so the new animation segment
    // continues smoothly from where the pages are right now. Without this,
    // resetting the controller to 0 makes the intermediate page snap back
    // to center before the next transition begins.
    final isAnimating = _controller.isAnimating && _controller.value < 1;
    if (isAnimating) {
      final vp = AppMotion.emphasized.transform(_controller.value);
      final oldDirection = _currentIndex > _fromIndex ? 1.0 : -1.0;
      // The page that was sliding in (old "to") becomes the new "from".
      _fromStartOffset = oldDirection * (1 - vp);
      if (widget.currentIndex == _fromIndex) {
        // Switching back: the old "from" page (now the new "to") is
        // partially visible on the opposite side.
        _toStartOffset = -oldDirection * vp;
      } else {
        // Switching to a new page: it starts fully off-screen.
        _toStartOffset = widget.currentIndex > _currentIndex ? 1.0 : -1.0;
      }
    } else {
      _fromStartOffset = 0;
      _toStartOffset = widget.currentIndex > _currentIndex ? 1.0 : -1.0;
    }
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
          final direction = _currentIndex > _fromIndex ? 1.0 : -1.0;
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
                      !(transitioning && index == _fromIndex),
                  child: RepaintBoundary(
                    // Full-width horizontal slide ("one continuous take"):
                    // outgoing page exits by one full width while the incoming
                    // page enters by one full width. No scale — scale made the
                    // switch feel like a zoom/card handoff instead of a pan.
                    // When a switch interrupts an in-flight animation, the
                    // start offsets [_fromStartOffset]/[_toStartOffset] ensure
                    // pages begin from their actual on-screen positions.
                    child: FractionalTranslation(
                      key: Key('root-branch-translation-$index'),
                      translation: Offset(switch (index) {
                        _ when index == _currentIndex && transitioning =>
                          lerpDouble(_toStartOffset, 0, progress)!,
                        _ when index == _fromIndex && transitioning =>
                          lerpDouble(_fromStartOffset, -direction, progress)!,
                        _ => 0,
                      }, 0),
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
