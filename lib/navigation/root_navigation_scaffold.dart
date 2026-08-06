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
  /// Project detail (`/projects/:id`), capture detail, and every other nested
  /// route must keep this false — otherwise the home dock covers the project
  /// capture FAB after returning from a root-navigator photo page.
  static bool isRootTabPath(String path) {
    return path == '/' || path == '/records' || path == '/settings';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = GoRouter.of(context);
    return ListenableBuilder(
      listenable: router.routeInformationProvider,
      builder: (context, _) {
        final strings = AppStrings.of(context);
        final path = router.routeInformationProvider.value.uri.path;
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
    _fromIndex = _currentIndex;
    _currentIndex = widget.currentIndex;
    if (_disableAnimations) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
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
                    child: FractionalTranslation(
                      key: Key('root-branch-translation-$index'),
                      translation: Offset(switch (index) {
                        _ when index == _currentIndex && transitioning =>
                          direction * (1 - progress),
                        _ when index == _fromIndex && transitioning =>
                          -direction * progress,
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
