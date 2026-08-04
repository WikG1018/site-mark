import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/domain/project_lifecycle.dart';
import 'package:sitemark/domain/project_summary.dart';
import 'package:sitemark/features/projects/project_summary_card.dart';
import 'package:sitemark/features/projects/project_status_filter_sheet.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';
import 'package:skeletonizer/skeletonizer.dart';

class ProjectListScreen extends ConsumerStatefulWidget {
  const ProjectListScreen({super.key, this.initialStatus});

  final ProjectLifecycleStatus? initialStatus;

  @override
  ConsumerState<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends ConsumerState<ProjectListScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _searchScrollController = ScrollController();
  final _statusScrollControllers = <ProjectLifecycleStatus, ScrollController>{
    for (final status in ProjectLifecycleStatus.values)
      status: ScrollController(),
  };
  bool _searching = false;
  String _query = '';
  late ProjectLifecycleStatus _status;

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus ?? ProjectLifecycleStatus.active;
  }

  @override
  void didUpdateWidget(covariant ProjectListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialStatus != widget.initialStatus &&
        widget.initialStatus != null) {
      setState(() => _status = widget.initialStatus!);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _searchScrollController.dispose();
    for (final controller in _statusScrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
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

  void _handleSearchAction() {
    if (_query.isNotEmpty) {
      _searchController.clear();
      setState(() => _query = '');
      _searchFocus.requestFocus();
      return;
    }
    _closeSearch();
  }

  Future<void> _openStatusFilter() async {
    final selected = await showProjectStatusFilterSheet(
      context,
      current: _status,
    );
    if (!mounted || selected == null || selected == _status) {
      return;
    }
    setState(() => _status = selected);
  }

  String _statusLabel(AppStrings strings, ProjectLifecycleStatus status) {
    return switch (status) {
      ProjectLifecycleStatus.active => strings.projectStatusActive,
      ProjectLifecycleStatus.completed => strings.projectStatusCompleted,
      ProjectLifecycleStatus.archived => strings.projectStatusArchived,
    };
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final database = ref.watch(databaseProvider);
    final outputPaths = ref.watch(captureOutputPathsProvider);
    final searching = _searching && _query.trim().isNotEmpty;
    final listController = searching
        ? _searchScrollController
        : _statusScrollControllers[_status]!;
    final stream = database.watchProjectSummaries(
      status: searching ? null : _status,
      search: searching ? _query : '',
    );
    return PopScope(
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _searching) _closeSearch();
      },
      child: Scaffold(
        appBar: AppBar(
          title: SizedBox(
            height: kToolbarHeight,
            child: Align(
              alignment: Alignment.centerLeft,
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
                  : Text(strings.appName, key: const Key('project-title')),
            ),
          ),
          actions: [
            if (_searching)
              IconButton(
                key: const Key('project-search-action'),
                onPressed: _handleSearchAction,
                tooltip: _query.isNotEmpty ? strings.clear : strings.cancel,
                icon: Icon(_query.isNotEmpty ? Icons.clear : Icons.close),
              )
            else ...[
              Semantics(
                key: const Key('project-status-filter'),
                label:
                    '${strings.projectStatusFilterTitle}: '
                    '${_statusLabel(strings, _status)}',
                button: true,
                onTap: _openStatusFilter,
                excludeSemantics: true,
                child: TextButton.icon(
                  onPressed: _openStatusFilter,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: const Icon(Icons.filter_list, size: 20),
                  label: Text(_statusLabel(strings, _status)),
                ),
              ),
              IconButton(
                key: const Key('search-projects'),
                onPressed: _startSearch,
                tooltip: strings.searchProjects,
                icon: AnimatedRotation(
                  turns: _searching ? 0.5 : 0,
                  duration: AppMotion.durationOf(context, AppMotion.short4),
                  child: const Icon(Icons.search),
                ),
              ),
            ],
          ],
        ),
        body: StreamBuilder<List<ProjectSummary>>(
          key: ValueKey(
            'project-summaries-${searching ? 'search' : _status.name}-$_query',
          ),
          stream: stream,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return Skeletonizer(
                key: const Key('project-list-skeleton'),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: 5,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, _) => const _ProjectCardSkeleton(),
                ),
              );
            }
            final summaries = snapshot.data!;
            if (summaries.isEmpty) {
              if (_searching && _query.trim().isNotEmpty) {
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
              return _EmptyState(strings: strings, status: _status);
            }
            return ListView.separated(
              key: PageStorageKey<String>(
                searching
                    ? 'project-list-search'
                    : 'project-list-${_status.name}',
              ),
              controller: listController,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: summaries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final summary = summaries[index];
                return ProjectSummaryCard(
                  key: Key('project-card-${summary.project.id}'),
                  summary: summary,
                  outputPaths: outputPaths,
                  onOpen: () => context.push(
                    '/projects/${summary.project.id}',
                    extra: summary.project,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Placeholder card used only by Skeletonizer while the first projects emit.
class _ProjectCardSkeleton extends StatelessWidget {
  const _ProjectCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: const CircleAvatar(child: Text('P')),
        title: Text(
          'Project Name Placeholder',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: const Text('Local only'),
        trailing: const Icon(Icons.more_vert),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.strings, required this.status});

  final AppStrings strings;
  final ProjectLifecycleStatus status;

  @override
  Widget build(BuildContext context) {
    final (title, hint) = switch (status) {
      ProjectLifecycleStatus.active => (
        strings.noActiveProjects,
        strings.noActiveProjectsHint,
      ),
      ProjectLifecycleStatus.completed => (
        strings.noCompletedProjects,
        strings.noCompletedProjectsHint,
      ),
      ProjectLifecycleStatus.archived => (
        strings.noArchivedProjects,
        strings.noArchivedProjectsHint,
      ),
    };
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
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                hint,
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
