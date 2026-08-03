import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/domain/project_lifecycle.dart';
import 'package:sitemark/domain/project_summary.dart';
import 'package:sitemark/features/projects/project_status_filter_sheet.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';
import 'package:sitemark/workflow/project_lifecycle_service.dart';
import 'package:skeletonizer/skeletonizer.dart';

enum _ProjectCardAction { pin, unpin, complete, archive, reopen }

class ProjectListScreen extends ConsumerStatefulWidget {
  const ProjectListScreen({super.key, this.initialStatus});

  final ProjectLifecycleStatus? initialStatus;

  @override
  ConsumerState<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends ConsumerState<ProjectListScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
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

  Future<void> _handleCardAction(
    ProjectSummary summary,
    _ProjectCardAction action,
  ) async {
    final database = ref.read(databaseProvider);
    final strings = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);

    switch (action) {
      case _ProjectCardAction.pin:
        await database.setProjectPinned(summary.project.id, true);
        return;
      case _ProjectCardAction.unpin:
        await database.setProjectPinned(summary.project.id, false);
        return;
      case _ProjectCardAction.complete:
        await _transitionLifecycle(
          summary.project.id,
          ProjectLifecycleStatus.completed,
          strings,
          messenger,
        );
      case _ProjectCardAction.archive:
        await _transitionLifecycle(
          summary.project.id,
          ProjectLifecycleStatus.archived,
          strings,
          messenger,
        );
      case _ProjectCardAction.reopen:
        await _transitionLifecycle(
          summary.project.id,
          ProjectLifecycleStatus.active,
          strings,
          messenger,
        );
    }
  }

  Future<void> _transitionLifecycle(
    String projectId,
    ProjectLifecycleStatus target,
    AppStrings strings,
    ScaffoldMessengerState messenger,
  ) async {
    final service = ref.read(projectLifecycleServiceProvider);
    try {
      final preview = await service.preview(projectId, target);
      if (preview.processingCount > 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              strings.projectLifecycleProcessingBlocked(
                preview.processingCount,
              ),
            ),
          ),
        );
        return;
      }
      var confirmFailed = false;
      if (preview.failedCount > 0) {
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            content: Text(
              strings.projectLifecycleFailedConfirm(preview.failedCount),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(strings.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(strings.projectLifecycleContinue),
              ),
            ],
          ),
        );
        if (confirmed != true) {
          return;
        }
        confirmFailed = true;
      }
      await service.transition(preview, confirmFailed: confirmFailed);
    } on ProjectLifecycleProcessingException catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            strings.projectLifecycleProcessingBlocked(error.processingCount),
          ),
        ),
      );
    } on ProjectLifecycleConfirmationRequiredException catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            strings.projectLifecycleFailedConfirm(error.failedCount),
          ),
        ),
      );
    } on ProjectLifecycleConflictException {
      messenger.showSnackBar(
        SnackBar(content: Text(strings.projectLifecycleConflict)),
      );
    } on ProjectLifecycleInvalidTransitionException {
      messenger.showSnackBar(
        SnackBar(content: Text(strings.projectLifecycleConflict)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final database = ref.watch(databaseProvider);
    final searching = _searching && _query.trim().isNotEmpty;
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
              IconButton(
                key: const Key('project-status-filter'),
                onPressed: _openStatusFilter,
                tooltip: strings.projectStatusFilterTitle,
                icon: const Icon(Icons.filter_list),
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: summaries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final summary = summaries[index];
                return _ProjectSummaryCard(
                  summary: summary,
                  strings: strings,
                  showStatusBadge: searching,
                  statusLabel: _statusLabel(
                    strings,
                    summary.project.lifecycleStatus,
                  ),
                  onOpen: () => context.push(
                    '/projects/${summary.project.id}',
                    extra: summary.project,
                  ),
                  onAction: (action) => _handleCardAction(summary, action),
                );
              },
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push('/projects/new'),
          icon: const Icon(Icons.add),
          label: Text(strings.newProject),
        ),
      ),
    );
  }
}

class _ProjectSummaryCard extends StatelessWidget {
  const _ProjectSummaryCard({
    required this.summary,
    required this.strings,
    required this.showStatusBadge,
    required this.statusLabel,
    required this.onOpen,
    required this.onAction,
  });

  final ProjectSummary summary;
  final AppStrings strings;
  final bool showStatusBadge;
  final String statusLabel;
  final VoidCallback onOpen;
  final ValueChanged<_ProjectCardAction> onAction;

  @override
  Widget build(BuildContext context) {
    final project = summary.project;
    final theme = Theme.of(context);
    final lastCaptureLabel = summary.lastCaptureAt == null
        ? strings.noCaptureRecordsYet
        : strings.lastCaptureAtLabel(
            DateFormat.yMMMd(
              Localizations.localeOf(context).toString(),
            ).add_Hm().format(summary.lastCaptureAt!),
          );
    final menuItems = <PopupMenuEntry<_ProjectCardAction>>[
      PopupMenuItem(
        key: Key('project-pin-${project.id}'),
        value: project.isPinned
            ? _ProjectCardAction.unpin
            : _ProjectCardAction.pin,
        child: Text(
          project.isPinned ? strings.unpinProject : strings.pinProject,
        ),
      ),
      ...switch (project.lifecycleStatus) {
        ProjectLifecycleStatus.active => [
          PopupMenuItem(
            key: Key('project-lifecycle-${project.id}'),
            value: _ProjectCardAction.complete,
            child: Text(strings.markProjectCompleted),
          ),
          PopupMenuItem(
            value: _ProjectCardAction.archive,
            child: Text(strings.archiveProject),
          ),
        ],
        ProjectLifecycleStatus.completed => [
          PopupMenuItem(
            key: Key('project-lifecycle-${project.id}'),
            value: _ProjectCardAction.reopen,
            child: Text(strings.reopenProject),
          ),
          PopupMenuItem(
            value: _ProjectCardAction.archive,
            child: Text(strings.archiveProject),
          ),
        ],
        ProjectLifecycleStatus.archived => [
          PopupMenuItem(
            key: Key('project-lifecycle-${project.id}'),
            value: _ProjectCardAction.reopen,
            child: Text(strings.restoreProjectToActive),
          ),
        ],
      },
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(child: Text(project.name.characters.first)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(project.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(project.description ?? strings.localOnly),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (showStatusBadge)
                          _MetaChip(
                            key: Key(
                              'project-status-badge-${project.lifecycleStatus.name}',
                            ),
                            label: statusLabel,
                          ),
                        if (project.isPinned)
                          _MetaChip(label: strings.projectPinnedBadge),
                        _MetaChip(
                          label: strings.projectPhotoCount(
                            summary.captureCount,
                          ),
                        ),
                        _MetaChip(label: lastCaptureLabel),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_ProjectCardAction>(
                tooltip: strings.projectActions,
                onSelected: onAction,
                itemBuilder: (_) => menuItems,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
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
