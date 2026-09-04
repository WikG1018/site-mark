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
import 'package:sitemark/domain/project_lifecycle.dart';
import 'package:sitemark/shared/ui/adaptive_dialog.dart';
import 'package:sitemark/shared/ui/adaptive_progress.dart';
import 'package:sitemark/domain/project_name.dart';
import 'package:sitemark/features/capture/capture_batch_action_bar.dart';
import 'package:sitemark/features/capture/capture_date_filter_bar.dart';
import 'package:sitemark/features/capture/capture_detail_screen.dart';
import 'package:sitemark/features/capture/capture_fullscreen_sequence.dart';
import 'package:sitemark/features/capture/capture_paged_list.dart';
import 'package:sitemark/features/capture/capture_pager_controller.dart';
import 'package:sitemark/features/capture/capture_record_card.dart';
import 'package:sitemark/features/capture/capture_search_field.dart';
import 'package:sitemark/features/capture/capture_selection_controller.dart';
import 'package:sitemark/features/projects/project_action_sheet.dart';
import 'package:sitemark/features/settings/sections/project_backup_selection_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/shared/ui/adaptive_toast.dart';
import 'package:sitemark/shared/ui/adaptive_page_scaffold.dart';
import 'package:sitemark/shared/ui/adaptive_floating_button.dart';
import 'package:sitemark/motion.dart';
import 'package:sitemark/navigation/scroll_chrome.dart';
import 'package:sitemark/shared/ui/floating_dock_layout.dart';
import 'package:sitemark/shared/ui/glass_surface.dart';
import 'package:sitemark/workflow/project_deletion_service.dart';
import 'package:sitemark/workflow/project_lifecycle_service.dart';

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
  int _selectionGeneration = 0;
  bool _selectAllLoading = false;
  bool _allQuerySelected = false;
  final CaptureSelectionController _selectionController =
      CaptureSelectionController();
  late final CaptureQuerySource _querySource;
  late final CapturePagerController _pagerController;
  late Stream<Project?> _projectStream;

  @override
  void initState() {
    super.initState();
    _querySource =
        widget.querySource ?? ref.read(captureQueryRepositoryProvider);
    _pagerController = CapturePagerController(_querySource, pageSize: 50);
    _projectStream = ref
        .read(databaseProvider)
        .watchProjectById(widget.projectId);
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
      _invalidateSelectionRequests();
      _selectionController.clearForFilterChange();
      _projectStream = ref
          .read(databaseProvider)
          .watchProjectById(widget.projectId);
      _startQuery();
    }
  }

  void _onPagerChanged() {
    if (mounted) setState(() {});
  }

  void _onSelectionChanged() {
    if (!_selectionController.editing) {
      _selectionGeneration++;
      _selectAllLoading = false;
      _allQuerySelected = false;
    } else if (_selectionController.selectedIds.isEmpty) {
      _allQuerySelected = false;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _dateOptionsGeneration++;
    _selectionGeneration++;
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
    _invalidateSelectionRequests();
    setState(() => _filter = next);
    _selectionController.clearForFilterChange();
    _startQuery();
  }

  bool get _hasAppliedDateFilter =>
      _filter?.year != null || _filter?.month != null || _filter?.day != null;

  void _clearAppliedDateFilter() {
    _onFilterChanged(CaptureFilter(projectId: widget.projectId));
  }

  void _onSearchChanged(String value) {
    _invalidateSelectionRequests();
    _searchText = value;
    _selectionController.clearForFilterChange();
    _startQuery();
  }

  void _exitSearch() {
    final clearQuery = _searchText.isNotEmpty;
    _invalidateSelectionRequests();
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

  void _invalidateSelectionRequests() {
    _selectionGeneration++;
    _selectAllLoading = false;
    _allQuerySelected = false;
  }

  Future<void> _toggleSelectAll() async {
    if (!_selectionController.editing || _selectAllLoading) return;
    final generation = ++_selectionGeneration;
    final query = _query;
    setState(() => _selectAllLoading = true);
    try {
      final snapshot = await _querySource.loadSelectable(query);
      if (!mounted || generation != _selectionGeneration) return;
      _selectAllLoading = false;
      _selectionController.toggleAllSnapshot(snapshot);
      _allQuerySelected =
          snapshot.ids.isNotEmpty &&
          _selectionController.selectedIds.length == snapshot.ids.length &&
          snapshot.ids.every(_selectionController.selectedIds.contains);
    } catch (_) {
      if (!mounted || generation != _selectionGeneration) return;
      setState(() => _selectAllLoading = false);
      _showSelectionRetry(() => unawaited(_toggleSelectAll()));
    }
  }

  Future<void> _inspectSelection() async {
    if (!_selectionController.editing) return;
    final ids = _selectionController.selectedIds;
    if (ids.isEmpty) return;
    final generation = ++_selectionGeneration;
    try {
      final snapshot = await _querySource.inspectSelection(ids);
      if (!mounted || generation != _selectionGeneration) return;
      _selectionController.replaceAll(
        snapshot.ids,
        allReady: snapshot.allReady,
      );
    } catch (_) {
      if (!mounted || generation != _selectionGeneration) return;
      _showSelectionRetry(() => unawaited(_inspectSelection()));
    }
  }

  void _showSelectionRetry(VoidCallback retry) {
    final strings = AppStrings.of(context);
    showAppToast(
      context,
      strings.captureListLoadFailed,
      action: AppToastAction(label: strings.retry, onPressed: retry),
    );
  }

  void _toggleSelection(String id, bool selected) {
    _invalidateSelectionRequests();
    if (selected && !_selectionController.editing) {
      _selectionController.enterWithSelection(id);
    } else {
      _selectionController.toggle(id);
    }
    unawaited(_inspectSelection());
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final filter = _filterForProject();
    final editing = _selectionController.editing;
    final allEligibleSelected =
        _allQuerySelected && _selectionController.selectedIds.isNotEmpty;
    return PopScope(
      canPop: !editing && !_searching && !_hasAppliedDateFilter,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_selectionController.editing) {
          _invalidateSelectionRequests();
          _selectionController.exit();
        } else if (_searching) {
          _exitSearch();
        } else if (_hasAppliedDateFilter) {
          _clearAppliedDateFilter();
        }
      },
      child: StreamBuilder<Project?>(
        stream: _projectStream,
        initialData: widget.initialProject,
        builder: (context, projectSnapshot) {
          final project = projectSnapshot.data;
          final waitingForProject =
              project == null &&
              projectSnapshot.connectionState == ConnectionState.waiting;
          final projectLoadFailed = project == null && projectSnapshot.hasError;
          final projectMissing =
              project == null && !waitingForProject && !projectLoadFailed;
          final title =
              project?.name ??
              (projectLoadFailed
                  ? strings.projectLoadFailed
                  : projectMissing
                  ? strings.projectNotFound
                  : strings.appName);
          final canCapture =
              project != null &&
              project.lifecycleStatus == ProjectLifecycleStatus.active &&
              !editing;
          return ScrollChromeForce(
            reason: 'project-detail-search',
            active: _searching,
            child: ScrollChromeForce(
              reason: 'project-detail-selection',
              active: editing,
              child: AdaptivePageScaffold.raw(
                hideOnScroll: true,
                title: title,
                titleWidget: AnimatedSwitcher(
                  key: const Key('capture-search-title-switcher'),
                  duration: AppMotion.durationOf(context, AppMotion.short4),
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [...previousChildren, ?currentChild],
                  ),
                  child: project != null && _searching
                      ? CaptureSearchField(
                          key: const ValueKey('capture-search-title'),
                          initialText: _searchText,
                          onChanged: _onSearchChanged,
                        )
                      : Text(title, key: const ValueKey('capture-list-title')),
                ),
                actions: [
                  if (project != null && !_searching && !editing)
                    IconButton(
                      key: const Key('search-captures'),
                      onPressed: () => setState(() => _searching = true),
                      tooltip: strings.searchCaptures,
                      icon: const Icon(Icons.search),
                    ),
                  if (project != null && !editing && !_searching)
                    IconButton(
                      key: const Key('project-actions'),
                      tooltip: strings.projectActions,
                      icon: const Icon(Icons.more_vert),
                      onPressed: () => _showProjectActions(project),
                    ),
                  if (project != null && editing)
                    IconButton(
                      key: const Key('select-all-captures'),
                      onPressed: _selectAllLoading ? null : _toggleSelectAll,
                      tooltip: allEligibleSelected
                          ? strings.deselectAll
                          : strings.selectAll,
                      icon: _selectAllLoading
                          ? const SizedBox.square(
                              key: Key('select-all-progress'),
                              dimension: 20,
                              child: AdaptiveProgressIndicator(size: 20),
                            )
                          : Icon(
                              allEligibleSelected
                                  ? Icons.check_box_outline_blank
                                  : Icons.select_all_outlined,
                            ),
                    ),
                ],
                iosBodyPadding: EdgeInsets.zero,
                body: Builder(
                  builder: (context) => FloatingDockLayout(
                    dock: project != null && editing
                        ? CaptureBatchActionBar(
                            key: const Key('batch-bar'),
                            controller: _selectionController,
                            mediaService: ref.watch(
                              captureMediaServiceProvider,
                            ),
                            exportService: ref.watch(
                              projectExportServiceProvider,
                            ),
                            shareService: ref.watch(shareFileServiceProvider),
                          )
                        : null,
                    child: waitingForProject
                        ? _projectLoadingList(strings)
                        : projectLoadFailed
                        ? _ProjectUnavailableState(
                            key: const Key('project-load-error'),
                            icon: Icons.cloud_off_outlined,
                            message: strings.projectLoadFailed,
                          )
                        : projectMissing
                        ? _ProjectUnavailableState(
                            key: const Key('project-not-found'),
                            icon: Icons.folder_off_outlined,
                            message: strings.projectNotFound,
                          )
                        : _projectCaptureList(
                            context,
                            strings,
                            project!,
                            filter,
                          ),
                  ),
                ),
                floatingActionButton: AnimatedSlide(
                  duration: scrollChromeAnimationOf(context),
                  curve: AppMotion.emphasized,
                  offset: ScrollChromeScope.visibleOf(context)
                      ? Offset.zero
                      : const Offset(0, 2),
                  child: IgnorePointer(
                    ignoring: !ScrollChromeScope.visibleOf(context),
                    child: AnimatedSwitcher(
                      duration: AppMotion.durationOf(
                        context,
                        AppMotion.medium2,
                      ),
                      switchInCurve: AppMotion.emphasized,
                      switchOutCurve: AppMotion.emphasized,
                      transitionBuilder: (child, animation) =>
                          ScaleTransition(scale: animation, child: child),
                      child: !canCapture
                          ? const SizedBox.shrink()
                          : AdaptiveFloatingButton(
                              key: const ValueKey('capture-fab'),
                              heroTag:
                                  'project-capture-fab-${widget.projectId}',
                              onPressed: () => context.push(
                                '/projects/${widget.projectId}/capture',
                              ),
                              icon: Icons.photo_camera_outlined,
                              label: strings.capture,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _projectLoadingList(AppStrings strings) {
    return CapturePagedList(
      controller: _pagerController,
      source: _querySource,
      emptyMessage: strings.noCaptures,
      skeletonKey: const Key('project-capture-list-skeleton'),
      contentKey: const Key('project-capture-list-content'),
      skeletonItemCount: 4,
      forceInitialLoading: true,
      itemBuilder: (_, _, _) => const SizedBox.shrink(),
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
      padding: EdgeInsets.fromLTRB(
        16,
        4,
        16,
        floatingDockReservedSpaceOf(context),
      ),
      sliversBefore: [
        scrollChromeOverlaySliver(
          context: context,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: _ProjectHeader(
                  project: project,
                  captureCount:
                      _pagerController.state.totalCount ??
                      _pagerController.state.rows.length,
                  editing: _selectionController.editing,
                  onToggleSelection: () {
                    if (_selectionController.editing) {
                      _invalidateSelectionRequests();
                      _selectionController.exit();
                    } else {
                      _selectionController.enter();
                    }
                  },
                ),
              ),
            ),
            if (project.lifecycleStatus != ProjectLifecycleStatus.active)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: _ProjectStatusBanner(project: project),
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
        ),
      ],
      itemBuilder: (context, summary, _) {
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
            _toggleSelection(id, selected);
          },
          onTap: (initialImagePath) => context.push(
            '/projects/${widget.projectId}/captures/$id',
            extra: CaptureDetailArguments(
              capture: summary.capture,
              initialImagePath: initialImagePath,
              navigationContext: CaptureNavigationContext(
                query: _pagerController.state.query,
                cursor: (
                  sortTime:
                      summary.capture.capturedAt ?? summary.capture.createdAt,
                  id: summary.capture.id,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showProjectActions(Project project) async {
    final openedProjectId = widget.projectId;
    final action = await showProjectActionSheet(context, project);
    if (!mounted || action == null || widget.projectId != openedProjectId) {
      return;
    }
    final database = ref.read(databaseProvider);
    final latestProject = await database.projectById(openedProjectId);
    if (!mounted ||
        widget.projectId != openedProjectId ||
        latestProject == null) {
      return;
    }
    final actionIsStillAllowed = projectActionsFor(
      latestProject,
      AppStrings.of(context),
    ).any((item) => item.action == action);
    if (!actionIsStillAllowed) return;
    switch (action) {
      case ProjectAction.watermark:
        await context.push('/projects/${latestProject.id}/settings');
      case ProjectAction.backup:
        await context.push(
          '/settings/backup-restore/backup',
          extra: ProjectBackupSelectionArguments(
            initialProjectIds: {latestProject.id},
          ),
        );
      case ProjectAction.rename:
        await _renameProject(latestProject);
      case ProjectAction.pin:
        await database.setProjectPinned(latestProject.id, true);
      case ProjectAction.unpin:
        await database.setProjectPinned(latestProject.id, false);
      case ProjectAction.complete:
        await _transitionLifecycle(
          latestProject.id,
          ProjectLifecycleStatus.completed,
        );
      case ProjectAction.archive:
        await _transitionLifecycle(
          latestProject.id,
          ProjectLifecycleStatus.archived,
        );
      case ProjectAction.reopen:
        await _transitionLifecycle(
          latestProject.id,
          ProjectLifecycleStatus.active,
        );
      case ProjectAction.delete:
        await _deleteProject(latestProject);
    }
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
    // StreamBuilder watches the project row and refreshes the title automatically.
  }

  Future<void> _transitionLifecycle(
    String projectId,
    ProjectLifecycleStatus target,
  ) async {
    final strings = AppStrings.of(context);
    final service = ref.read(projectLifecycleServiceProvider);
    try {
      final preview = await service.preview(projectId, target);
      final requiresSettledCaptures = target != ProjectLifecycleStatus.active;
      if (requiresSettledCaptures && preview.processingCount > 0) {
        if (!mounted) return;
        showAppToast(
          context,
          strings.projectLifecycleProcessingBlocked(preview.processingCount),
        );
        return;
      }
      var confirmFailed = false;
      if (requiresSettledCaptures && preview.failedCount > 0) {
        if (!mounted) return;
        final confirmed = await showAppDialog<bool>(
          context: context,
          content: Text(
            strings.projectLifecycleFailedConfirm(preview.failedCount),
          ),
          actions: [
            AppDialogAction(label: strings.cancel, result: false),
            AppDialogAction(
              label: strings.projectLifecycleContinue,
              result: true,
              isDefault: true,
            ),
          ],
        );
        if (confirmed != true) {
          return;
        }
        confirmFailed = true;
      }
      await service.transition(preview, confirmFailed: confirmFailed);
    } on ProjectLifecycleProcessingException catch (error) {
      if (!mounted) return;
      showAppToast(
        context,
        strings.projectLifecycleProcessingBlocked(error.processingCount),
      );
    } on ProjectLifecycleConfirmationRequiredException catch (error) {
      if (!mounted) return;
      showAppToast(
        context,
        strings.projectLifecycleFailedConfirm(error.failedCount),
      );
    } on ProjectLifecycleConflictException {
      if (!mounted) return;
      showAppToast(context, strings.projectLifecycleConflict);
    } on ProjectLifecycleInvalidTransitionException {
      if (!mounted) return;
      showAppToast(context, strings.projectLifecycleConflict);
    }
  }

  Future<void> _deleteProject(Project project) async {
    final strings = AppStrings.of(context);
    final service = ref.read(projectDeletionServiceProvider);
    late final ProjectDeletionPreview preview;
    try {
      preview = await service.preview(project.id);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, strings.deleteProjectPreviewFailed);
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
    showAppToast(
      context,
      result.cleanupPending
          ? strings.projectDeletedCleanupPending
          : strings.projectDeleted,
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
      child: buildAdaptiveAlertDialog<Project>(
        dialogContext: context,
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
          AppDialogAction(label: strings.cancel, enabled: !_saving),
          AppDialogAction(
            key: const Key('confirm-rename-project'),
            label: strings.save,
            enabled: !_saving,
            // _submit pops the dialog itself, and only after a successful
            // save — validation failures keep it open.
            onPressed: _submit,
            autoPop: false,
            isDefault: true,
            child: _saving ? const AdaptiveProgressIndicator(size: 18) : null,
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
      child: buildAdaptiveAlertDialog<ProjectDeletionResult>(
        dialogContext: context,
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
          AppDialogAction(label: strings.cancel, enabled: !_deleting),
          AppDialogAction(
            key: const Key('confirm-delete-project'),
            label: strings.deleteProject,
            enabled: !_deleting,
            // _delete pops the dialog itself with the deletion result.
            onPressed: _delete,
            autoPop: false,
            isDestructive: true,
            child: _deleting ? const AdaptiveProgressIndicator(size: 18) : null,
          ),
        ],
      ),
    );
  }
}

class _ProjectUnavailableState extends StatelessWidget {
  const _ProjectUnavailableState({
    super.key,
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectHeader extends StatelessWidget {
  const _ProjectHeader({
    required this.project,
    required this.captureCount,
    required this.editing,
    required this.onToggleSelection,
  });

  final Project project;
  final int captureCount;
  final bool editing;
  final VoidCallback onToggleSelection;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final status = switch (project.lifecycleStatus) {
      ProjectLifecycleStatus.active => strings.projectStatusActive,
      ProjectLifecycleStatus.completed => strings.projectStatusCompleted,
      ProjectLifecycleStatus.archived => strings.projectStatusArchived,
    };
    return GlassSurface(
      key: const Key('project-summary'),
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          Icon(
            Icons.apartment_outlined,
            size: 32,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  project.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  children: [
                    Text(status, style: Theme.of(context).textTheme.bodySmall),
                    Text(
                      strings.projectPhotoCount(captureCount),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                if (project.description case final description?) ...[
                  const SizedBox(height: 2),
                  Text(
                    description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            key: const Key('edit-captures'),
            onPressed: onToggleSelection,
            child: Text(editing ? strings.done : strings.selectRecords),
          ),
        ],
      ),
    );
  }
}

class _ProjectStatusBanner extends StatelessWidget {
  const _ProjectStatusBanner({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final colors = Theme.of(context).colorScheme;
    final message = switch (project.lifecycleStatus) {
      ProjectLifecycleStatus.completed => strings.projectStatusBannerCompleted,
      ProjectLifecycleStatus.archived => strings.projectStatusBannerArchived,
      ProjectLifecycleStatus.active => '',
    };
    return Material(
      key: const Key('project-status-banner'),
      color: colors.secondaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: colors.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
