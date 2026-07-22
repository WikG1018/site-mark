import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';
import 'package:skeletonizer/skeletonizer.dart';

class ProjectListScreen extends ConsumerStatefulWidget {
  const ProjectListScreen({super.key});

  @override
  ConsumerState<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends ConsumerState<ProjectListScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searching = false;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<Project> _filteredProjects(List<Project> projects) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return projects;
    return projects
        .where((project) => project.name.toLowerCase().contains(query))
        .toList(growable: false);
  }

  void _startSearch() {
    setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchFocus.requestFocus(),
    );
  }

  void _closeSearch() {
    _searchController.clear();
    setState(() {
      _query = '';
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final database = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(
        // Cross-fade between the app title and the inline search field; the
        // ValueKey swap drives the AnimatedSwitcher transition.
        title: AnimatedSwitcher(
          duration: AppMotion.short4,
          child: _searching
              ? TextField(
                  key: const Key('project-search-field'),
                  controller: _searchController,
                  focusNode: _searchFocus,
                  decoration: InputDecoration(
                    hintText: strings.searchProjectsHint,
                    border: InputBorder.none,
                  ),
                  onChanged: (value) => setState(() => _query = value),
                )
              : Text(strings.appName, key: const ValueKey('project-title')),
        ),
        actions: [
          if (_searching) ...[
            if (_query.isNotEmpty)
              IconButton(
                key: const Key('clear-project-search'),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
                icon: const Icon(Icons.clear),
              ),
            IconButton(
              key: const Key('close-project-search'),
              onPressed: _closeSearch,
              icon: const Icon(Icons.close),
            ),
          ] else ...[
            IconButton(
              key: const Key('search-projects'),
              onPressed: _startSearch,
              tooltip: strings.searchProjects,
              icon: AnimatedRotation(
                turns: _searching ? 0.5 : 0,
                duration: AppMotion.short4,
                child: const Icon(Icons.search),
              ),
            ),
            IconButton(
              onPressed: () => context.go('/records'),
              tooltip: strings.allRecords,
              icon: const Icon(Icons.photo_library_outlined),
            ),
            IconButton(
              onPressed: () => context.go('/settings'),
              tooltip: strings.settings,
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ],
      ),
      body: StreamBuilder<List<Project>>(
        stream: database.watchProjects(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const _ProjectListSkeleton();
          }
          final projects = snapshot.data!;
          if (projects.isEmpty) {
            return _EmptyState(strings: strings);
          }
          final filtered = _filteredProjects(projects);
          if (filtered.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  strings.noMatchingProjects,
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: filtered.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final project = filtered[index];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    child: Text(project.name.characters.first),
                  ),
                  title: Text(
                    project.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  subtitle: Text(project.description ?? strings.localOnly),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/projects/${project.id}'),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/projects/new'),
        icon: const Icon(Icons.add),
        label: Text(strings.newProject),
      ),
    );
  }
}

/// First-frame loading placeholder: six bone cards mimicking the real
/// project card layout (CircleAvatar + two-line ListTile). Taps are disabled
/// while the stream has not delivered its first value.
class _ProjectListSkeleton extends StatelessWidget {
  const _ProjectListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(
      enabled: true,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: 6,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) => Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: const CircleAvatar(child: Text('项')),
            title: Text(
              '项目骨架占位',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            subtitle: const Text('项目描述骨架占位文本'),
            trailing: const Icon(Icons.chevron_right),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.domain_add_outlined,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                strings.noProjects,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                strings.noProjectsHint,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
