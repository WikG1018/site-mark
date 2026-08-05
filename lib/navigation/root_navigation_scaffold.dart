import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';
import 'package:sitemark/navigation/root_chrome_controller.dart';
import 'package:sitemark/shared/ui/floating_dock_layout.dart';
import 'package:sitemark/shared/ui/glass_surface.dart';

class RootNavigationScaffold extends ConsumerWidget {
  const RootNavigationScaffold({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = GoRouter.of(context);
    return ListenableBuilder(
      listenable: router.routeInformationProvider,
      builder: (context, _) {
        final strings = AppStrings.of(context);
        final path = router.routeInformationProvider.value.uri.path;
        final showRootNavigation =
            path == '/' || path == '/records' || path == '/settings';
        final recordsSelecting = ref.watch(allCapturesSelectionModeProvider);
        final hideForSelection = path == '/records' && recordsSelecting;
        return Scaffold(
          body: FloatingDockLayout(
            animateDock: path != '/records',
            dock: showRootNavigation && !hideForSelection
                ? GlassSurface(
                    key: const Key('root-dock'),
                    borderRadius: BorderRadius.circular(24),
                    child: SizedBox(
                      height: floatingDockHeight,
                      child: NavigationBar(
                        backgroundColor: Colors.transparent,
                        selectedIndex: navigationShell.currentIndex,
                        onDestinationSelected: (index) =>
                            navigationShell.goBranch(
                              index,
                              initialLocation:
                                  index == navigationShell.currentIndex,
                            ),
                        destinations: [
                          NavigationDestination(
                            key: const Key('root-destination-projects'),
                            icon: const Icon(Icons.domain_outlined),
                            label: strings.projects,
                          ),
                          NavigationDestination(
                            key: const Key('root-destination-records'),
                            icon: const Icon(Icons.photo_library_outlined),
                            label: strings.allRecords,
                          ),
                          NavigationDestination(
                            key: const Key('root-destination-settings'),
                            icon: const Icon(Icons.settings_outlined),
                            label: strings.settings,
                          ),
                        ],
                      ),
                    ),
                  )
                : null,
            floatingActionButton:
                showRootNavigation && navigationShell.currentIndex == 0
                ? FloatingActionButton(
                    key: const Key('new-project-fab'),
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

class RootBranchContainer extends StatelessWidget {
  const RootBranchContainer({
    super.key,
    required this.currentIndex,
    required this.children,
  });

  final int currentIndex;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      for (final (index, child) in children.indexed)
        Positioned.fill(
          child: AnimatedOpacity(
            opacity: index == currentIndex ? 1 : 0,
            duration: AppMotion.durationOf(context, AppMotion.rootSwitch),
            child: TickerMode(
              enabled: index == currentIndex,
              child: IgnorePointer(
                ignoring: index != currentIndex,
                child: ExcludeSemantics(
                  excluding: index != currentIndex,
                  child: child,
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
