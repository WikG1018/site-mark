import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/data/capture_query_repository.dart';
import 'package:sitemark/domain/capture_filter.dart';
import 'package:sitemark/domain/capture_list_query.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/domain/project_name.dart';
import 'package:sitemark/features/capture/capture_batch_action_bar.dart';
import 'package:sitemark/features/capture/capture_date_filter_bar.dart';
import 'package:sitemark/features/capture/capture_detail_screen.dart';
import 'package:sitemark/features/capture/capture_paged_list.dart';
import 'package:sitemark/features/capture/capture_pager_controller.dart';
import 'package:sitemark/features/capture/capture_record_card.dart';
import 'package:sitemark/features/capture/capture_search_field.dart';
import 'package:sitemark/features/capture/capture_selection_controller.dart';
import 'package:sitemark/features/settings/sections/project_backup_selection_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';
import 'package:sitemark/workflow/project_deletion_service.dart';

enum _ProjectAction { rename, delete }

class ProjectDetailScreen extends ConsumerStatefulWidget {
  const ProjectDetailScreen({
    super.key,
    required this.projectId,
    this.initialProject,
    this.querySource,
  });

  final String projectId;
  final Project? initialProject;
  final CaptureQuerySource? querySource;

  @override
  ConsumerState<ProjectDetailScreen> createState() =>
      _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends ConsumerState<ProjectDetailScreen> {
  CaptureFilter? _filter;
  String _searchText = '';
  bool _searching = false;
  CaptureDateOptions _dateOptions = const CaptureDateOptions();
  int _dateOptionsGeneration = 0;
  final CaptureSelectionController _selectionController =
      CaptureSelectionController();
  late Future<Project?> _projectFuture;
  late final CaptureQuerySource _querySource;
  late final CapturePagerController _pagerController;

  List<CaptureSummary> _latestCaptures = const [];

  @override
  void initState() {
    super.initState();
    _querySource =
        widget.querySource ?? ref.read(captureQueryRepositoryProvider);
    _pagerController = CapturePagerController(_querySource, pageSize: 50);
    _loadPageData();
    unawaited(_pagerController.setQuery(_query));
    unawaited(_loadDateOptions(_query));
    _pagerController.addListener(_onPagerChanged);
    _selectionController.addListener(_onSelectionChanged);
  }

  @override
  void didUpdateWidget(covariant ProjectDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) {
      _filter = null;
      _searchText = '';
      _searching = false;
      _latestCaptures = const [];
      _selectionController.clearForFilterChange();
      _loadPageData();
      _startQuery();
    }
  }

  void _loadPageData() {
    _projectFuture = ref.read(databaseProvider).projectById(widget.projectId);
  }

  void _onPagerChanged() {
    if (mounted) setState(() {});
  }

  void _onSelectionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _dateOptionsGeneration++;
    _pagerController.removeListener(_onPagerChanged);
    _pagerController.dispose();
    _selectionController.removeListener(_onSelectionChanged);
    _selectionController.dispose();
    super.dispose();
  }

  CaptureFilter _filterForProject() =>
      _filter?.selectProject(widget.projectId) ??
      CaptureFilter(projectId: widget.projectId);

  CaptureListQuery get _query =>
      CaptureListQuery(filter: _filterForProject(), searchText: _searchText);

  Future<void> _loadDateOptions(CaptureListQuery query) async {
    final generation = ++_dateOptionsGeneration;
    try {
      final options = await _querySource.loadDateOptions(query);
      if (!mounted || generation != _dateOptionsGeneration) return;
      setState(() => _dateOptions = options);
    } catch (_) {
      if (!mounted || generation != _dateOptionsGeneration) return;
      setState(() => _dateOptions = const CaptureDateOptions());
    }
  }

  void _startQuery() {
    final query = _query;
    unawaited(_pagerController.setQuery(query));
    unawaited(_loadDateOptions(query));
  }

  void _onFilterChanged(CaptureFilter next) {
    setState(() => _filter = next);
    _selectionController.clearForFilterChange();
    _startQuery();
  }

  void _onSearchChanged(String value) {
    _searchText = value;
    _selectionController.clearForFilterChange();
    _startQuery();
  }

  void _exitSearch() {
    final clearQuery = _searchText.isNotEmpty;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _searching = false;
      if (clearQuery) _searchText = '';
    });
    if (clearQuery) {
      _selectionController.clearForFilterChange();
      _startQuery();
    }
  }

  List<String> _selectableIds(List<CaptureSummary> captures) {
    return captures
        .where(
          (summary) =>
              summary.capture.status == CaptureStatus.ready ||
              summary.capture.status == CaptureStatus.failed,
        )
        .map((summary) => summary.capture.id)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final filter = _filterForProject();
    final editing = _selectionController.editing;
    _latestCaptures = _pagerController.state.rows;
    final allEligibleSelected = _selectionController.allSelected(
      _selectableIds(_latestCaptures),
    );
    return PopScope(
      canPop: !editing && !_searching,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_selectionController.editing) {
          _selectionController.exit();
        } else if (_searching) {
          _exitSearch();
        }
      },
      child: FutureBuilder<Project?>(
        future: _projectFuture,
        initialData: widget.initialProject,
        builder: (context, projectSnapshot) {
          final project = projectSnapshot.data;
          return Scaffold(
            appBar: AppBar(
              title: AnimatedSwitcher(
                key: const Key('capture-search-title-switcher'),
                duration: AppMotion.durationOf(context, AppMotion.short4),
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...previousChildren, ?currentChild],
                ),
                child: _searching
                    ? CaptureSearchField(
                        key: const ValueKey('capture-search-title'),
                        initialText: _searchText,
                        onChanged: _onSearchChanged,
                      )
                    : Text(
                        project?.name ?? strings.appName,
                        key: const ValueKey('capture-list-title'),
                      ),
              ),
              actions: [
                if (!_searching && !editing)
                  IconButton(
                    key: const Key('search-captures'),
                    onPressed: () => setState(() => _searching = true),
                    tooltip: strings.searchCaptures,
                    icon: const Icon(Icons.search),
                  ),
                if (project != null && !editing && !_searching) ...[
                  IconButton(
                    onPressed: () =>
                        context.push('/projects/${project.id}/settings'),
                    tooltip: strings.projectWatermarkSettings,
                    icon: const Icon(Icons.tune_outlined),
                  ),
                  IconButton(
                    onPressed: () => context.push(
                      '/settings/backup-restore/backup',
                      extra: ProjectBackupSelectionArguments(
                        initialProjectIds: {project.id},
                      ),
                    ),
                    tooltip: strings.backupProjects,
                    icon: const Icon(Icons.archive_outlined),
                  ),
                  PopupMenuButton<_ProjectAction>(
                    key: const Key('project-actions'),
                    tooltip: strings.projectActions,
                    icon: const Icon(Icons.more_vert),
                    onSelected: (action) async {
                      switch (action) {
                        case _ProjectAction.rename:
                          await _renameProject(project);
                        case _ProjectAction.delete:
                          await _deleteProject(project);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        key: const Key('rename-project'),
                        value: _ProjectAction.rename,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.drive_file_rename_outline),
                          title: Text(strings.renameProject),
                        ),
                      ),
                      PopupMenuItem(
                        key: const Key('delete-project'),
                        value: _ProjectAction.delete,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.delete_outline,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          title: Text(
                            strings.deleteProject,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (editing)
                  IconButton(
                    key: const Key('select-all-captures'),
                    onPressed: () {
                      _selectionController.toggleAll(
                        _selectableIds(_latestCaptures),
                      );
                    },
                    tooltip: allEligibleSelected
                        ? strings.deselectAll
                        : strings.selectAll,
                    icon: Icon(
                      allEligibleSelected
                          ? Icons.check_box_outline_blank
                          : Icons.select_all_outlined,
                    ),
                  ),
                IconButton(
                  key: const Key('edit-captures'),
                  onPressed: () {
                    if (_selectionController.editing) {
                      _selectionController.exit();
                    } else {
                      _selectionController.enter();
                    }
                  },
                  tooltip: editing ? strings.done : strings.editRecords,
                  icon: AnimatedSwitcher(
                    duration: AppMotion.durationOf(context, AppMotion.short4),
                    child: Icon(
                      editing ? Icons.done : Icons.edit_outlined,
                      key: ValueKey(editing),
                    ),
                  ),
                ),
              ],
            ),
            body: project == null
                ? const SizedBox.shrink()
                : _projectCaptureList(context, strings, project, filter),
            bottomNavigationBar: AnimatedSwitcher(
              duration: AppMotion.durationOf(context, AppMotion.medium4),
              transitionBuilder: (child, animation) {
                final curved = animation.drive(
                  CurveTween(curve: AppMotion.emphasizedDecelerate),
                );
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(curved),
                  child: FadeTransition(opacity: curved, child: child),
                );
              },
              child: editing && _selectionController.selectedIds.isNotEmpty
                  ? CaptureBatchActionBar(
                      key: const Key('batch-bar'),
                      controller: _selectionController,
                      mediaService: ref.watch(captureMediaServiceProvider),
                      exportService: ref.watch(projectExportServiceProvider),
                      shareService: ref.watch(shareFileServiceProvider),
                      summaries: _latestCaptures,
                    )
                  : const SizedBox.shrink(key: Key('batch-bar-empty')),
            ),
            floatingActionButton: AnimatedSwitcher(
              duration: AppMotion.durationOf(context, AppMotion.medium2),
              switchInCurve: AppMotion.emphasized,
              switchOutCurve: AppMotion.emphasized,
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: project == null || editing
                  ? const SizedBox.shrink()
                  : FloatingActionButton.extended(
                      key: const ValueKey('capture-fab'),
                      onPressed: () =>
                          context.push('/projects/${widget.projectId}/capture'),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: Text(strings.capture),
                    ),
            ),
          );
        },
      ),
    );
  }

  Widget _projectCaptureList(
    BuildContext context,
    AppStrings strings,
    Project project,
    CaptureFilter filter,
  ) {
    final hasDateFilter =
        filter.year != null || filter.month != null || filter.day != null;
    final hasActiveQuery =
        hasDateFilter ||
        _pagerController.state.query.normalizedTerms.isNotEmpty;
    return CapturePagedList(
      controller: _pagerController,
      source: _querySource,
      emptyMessage: hasActiveQuery ? strings.filteredEmpty : strings.noCaptures,
      skeletonKey: const Key('project-capture-list-skeleton'),
      contentKey: const Key('project-capture-list-content'),
      skeletonItemCount: 4,
      sliversBefore: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: _ProjectHeader(project: project),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Text(
              strings.captureRecords,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
        if (_dateOptions.years.isNotEmpty || hasDateFilter)
          SliverToBoxAdapter(
            child: CaptureDateFilterBar(
              filter: filter,
              options: _dateOptions,
              onChanged: _onFilterChanged,
            ),
          ),
      ],
      itemBuilder: (context, summary, visibleRows) {
        final id = summary.capture.id;
        return CaptureRecordCard(
          key: ValueKey(id),
          summary: summary,
          searchTerms: _pagerController.state.query.normalizedTerms,
          selectionMode: _selectionController.editing,
          selected: _selectionController.selectedIds.contains(id),
          selectable:
              summary.capture.status == CaptureStatus.ready ||
              summary.capture.status == CaptureStatus.failed,
          onSelectedChanged: (selected) {
            if (selected && !_selectionController.editing) {
              _selectionController.enterWithSelection(id);
            } else {
              _selectionController.toggle(id);
            }
          },
          onTap: (initialImagePath) => context.push(
            '/projects/${widget.projectId}/captures/$id',
            extra: CaptureDetailArguments(
              capture: summary.capture,
              initialImagePath: initialImagePath,
              siblingCaptures: visibleRows
                  .map((row) => row.capture)
                  .toList(growable: false),
            ),
          ),
        );
      },
    );
  }

  Future<void> _renameProject(Project project) async {
    final renamed = await showDialog<Project>(
      context: context,
      builder: (dialogContext) => _RenameProjectDialog(
        project: project,
        database: ref.read(databaseProvider),
      ),
    );
    if (!mounted || renamed == null) return;
    setState(() {
      _projectFuture = Future.value(renamed);
    });
  }

  Future<void> _deleteProject(Project project) async {
    final strings = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(projectDeletionServiceProvider);
    late final ProjectDeletionPreview preview;
    try {
      preview = await service.preview(project.id);
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(strings.deleteProjectPreviewFailed)),
      );
      return;
    }
    if (!mounted) return;
    final result = await showDialog<ProjectDeletionResult>(
      context: context,
      builder: (dialogContext) => _DeleteProjectDialog(
        projectId: project.id,
        preview: preview,
        service: service,
      ),
    );
    if (!mounted || result == null) return;
    context.go('/');
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.cleanupPending
              ? strings.projectDeletedCleanupPending
              : strings.projectDeleted,
        ),
      ),
    );
  }
}

class _RenameProjectDialog extends StatefulWidget {
  const _RenameProjectDialog({required this.project, required this.database});

  final Project project;
  final AppDatabase database;

  @override
  State<_RenameProjectDialog> createState() => _RenameProjectDialogState();
}

class _RenameProjectDialogState extends State<_RenameProjectDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;
  String? _nameError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.project.name);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _nameError = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final renamed = await widget.database.renameProject(
        projectId: widget.project.id,
        name: _controller.text,
      );
      if (mounted) Navigator.of(context).pop(renamed);
    } on ProjectNameConflictException catch (error) {
      if (!mounted) return;
      final strings = AppStrings.of(context);
      setState(() {
        _saving = false;
        _nameError = error.kind == ProjectNameConflictKind.displayName
            ? strings.projectNameAlreadyExists
            : strings.projectFileNameConflict;
      });
      _formKey.currentState!.validate();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _nameError = AppStrings.of(context).renameProjectFailed;
      });
      _formKey.currentState!.validate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(strings.renameProjectTitle),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: TextFormField(
              key: const Key('rename-project-name'),
              controller: _controller,
              autofocus: true,
              maxLength: 120,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(labelText: strings.projectName),
              onFieldSubmitted: (_) => _submit(),
              onChanged: (_) {
                if (_nameError != null) {
                  setState(() => _nameError = null);
                }
              },
              validator: (value) {
                final name = value?.trim() ?? '';
                if (name.isEmpty) return strings.projectNameRequired;
                if (name.length > 120) return strings.projectNameTooLong;
                return _nameError;
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: Text(strings.cancel),
          ),
          FilledButton(
            key: const Key('confirm-rename-project'),
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(strings.save),
          ),
        ],
      ),
    );
  }
}

class _DeleteProjectDialog extends StatefulWidget {
  const _DeleteProjectDialog({
    required this.projectId,
    required this.preview,
    required this.service,
  });

  final String projectId;
  final ProjectDeletionPreview preview;
  final ProjectDeletionService service;

  @override
  State<_DeleteProjectDialog> createState() => _DeleteProjectDialogState();
}

class _DeleteProjectDialogState extends State<_DeleteProjectDialog> {
  bool _deleting = false;
  bool _failed = false;

  Future<void> _delete() async {
    if (_deleting) return;
    setState(() {
      _deleting = true;
      _failed = false;
    });
    try {
      final result = await widget.service.deleteProject(widget.projectId);
      if (mounted) Navigator.of(context).pop(result);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_deleting,
      child: AlertDialog(
        title: Text(strings.deleteProjectTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.deleteProjectSummary(
                  projectName: widget.preview.projectName,
                  captureCount: widget.preview.captureCount,
                  privateOriginalCount: widget.preview.privateOriginalCount,
                ),
              ),
              const SizedBox(height: 16),
              Text(strings.deleteProjectRetentionNotice),
              const SizedBox(height: 8),
              Text(
                strings.deleteProjectIrreversible,
                style: TextStyle(color: colors.error),
              ),
              if (_failed) ...[
                const SizedBox(height: 12),
                Text(
                  strings.deleteProjectFailed,
                  style: TextStyle(color: colors.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _deleting ? null : () => Navigator.of(context).pop(),
            child: Text(strings.cancel),
          ),
          FilledButton(
            key: const Key('confirm-delete-project'),
            style: FilledButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onError,
            ),
            onPressed: _deleting ? null : _delete,
            child: _deleting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(strings.deleteProject),
          ),
        ],
      ),
    );
  }
}

class _ProjectHeader extends StatelessWidget {
  const _ProjectHeader({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(
              Icons.apartment_outlined,
              size: 42,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (project.description != null) ...[
                    const SizedBox(height: 4),
                    Text(project.description!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
