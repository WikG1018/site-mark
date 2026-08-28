import 'dart:async';

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
import 'package:sitemark/shared/ui/adaptive_skeleton_count.dart';
import 'package:sitemark/shared/ui/floating_dock_layout.dart';
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

  /// Debounced query actually applied to the list. Typing updates [_query]
  /// immediately so the field stays responsive, while the list query (and the
  /// full StreamBuilder rebuild) waits for a pause — matching the records
  /// screen's 250ms debounce.
  String _effectiveQuery = '';
  Timer? _queryDebounce;
  late ProjectLifecycleStatus _status;
  Stream<List<ProjectSummary>>? _summaryStream;
  String? _summaryStreamKey;

  static const Duration _searchDebounce = Duration(milliseconds: 250);

  /// Reuses the Drift stream across rebuilds: creating a new stream in build()
  /// would resubscribe (and re-run) the query on every setState, e.g. on each
  /// keystroke.
  Stream<List<ProjectSummary>> _summariesFor({
    required ProjectLifecycleStatus? status,
    required String search,
  }) {
    final key = '${status?.name}|$search';
    if (_summaryStreamKey != key || _summaryStream == null) {
      _summaryStreamKey = key;
      _summaryStream = ref
          .read(databaseProvider)
          .watchProjectSummaries(status: status, search: search);
    }
    return _summaryStream!;
  }

  void _onSearchChanged(String value) {
    _queryDebounce?.cancel();
    final next = value;
    setState(() => _query = next);
    _queryDebounce = Timer(_searchDebounce, () {
      if (!mounted || _effectiveQuery == next) return;
      setState(() => _effectiveQuery = next);
    });
  }

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
    _queryDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _searchScrollController.dispose();
    for (final controller in _statusScrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Closes the project search when a system back arrives while it is open;
  /// otherwise the back falls through to the navigator.
  void _handleRootBack() {
    if (!_searching) return;
    _closeSearch();
  }

  void _startSearch() {
    setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchFocus.requestFocus(),
    );
  }

  void _closeSearch() {
    _queryDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _query = '';
      _effectiveQuery = '';
      _searching = false;
    });
  }

  void _handleSearchAction() {
    if (_query.isNotEmpty) {
      _queryDebounce?.cancel();
      _searchController.clear();
      setState(() {
        _query = '';
        _effectiveQuery = '';
      });
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
    final outputPaths = ref.watch(captureOutputPathsProvider);
    final searching = _searching && _effectiveQuery.trim().isNotEmpty;
    final listController = searching
        ? _searchScrollController
        : _statusScrollControllers[_status]!;
    final stream = _summariesFor(
      status: searching ? null : _status,
      search: searching ? _effectiveQuery : '',
    );
    // The PopScope closes the project search on a system back while the
    // search is open; otherwise the back falls through.
    return PopScope(
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleRootBack();
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
                      onChanged: _onSearchChanged,
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
        body: LayoutBuilder(
          key: const Key('project-list-content'),
          builder: (context, constraints) =>
              StreamBuilder<List<ProjectSummary>>(
                key: ValueKey('project-summaries-$_summaryStreamKey'),
                stream: stream,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    final skeletonCount = adaptiveSkeletonCount(
                      viewportHeight: constraints.maxHeight,
                      itemExtent: 118,
                    );
                    return Skeletonizer(
                      key: const Key('project-list-skeleton'),
                      child: ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          16,
                          16,
                          floatingDockReservedSpaceOf(
                            context,
                            avoidFloatingActionButton: true,
                          ),
                        ),
                        itemCount: skeletonCount,
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
                    padding: EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      floatingDockReservedSpaceOf(
                        context,
                        avoidFloatingActionButton: true,
                      ),
                    ),
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
      ),
    );
  }
}

/// Placeholder card used only by Skeletonizer while the first projects emit.
class _ProjectCardSkeleton extends StatelessWidget {
  const _ProjectCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: const CircleAvatar(child: Text('P')),
        title: Text(
          strings.projectNamePlaceholder,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Text(strings.localOnly),
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
