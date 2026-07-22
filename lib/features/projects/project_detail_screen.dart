import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_filter.dart';
import 'package:sitemark/domain/capture_summary_filter.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/features/capture/capture_batch_action_bar.dart';
import 'package:sitemark/features/capture/capture_date_filter_bar.dart';
import 'package:sitemark/features/capture/capture_record_card.dart';
import 'package:sitemark/features/capture/capture_selection_controller.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';
import 'package:skeletonizer/skeletonizer.dart';

class ProjectDetailScreen extends ConsumerStatefulWidget {
  const ProjectDetailScreen({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<ProjectDetailScreen> createState() =>
      _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends ConsumerState<ProjectDetailScreen> {
  CaptureFilter? _filter;
  final CaptureSelectionController _selectionController =
      CaptureSelectionController();
  late Future<Project?> _projectFuture;
  late Stream<List<CaptureSummary>> _captureSummariesStream;

  /// Latest filtered captures emitted by the inner StreamBuilder. Updated
  /// synchronously during build (no `setState`) so the AppBar's select-all
  /// action and the bottom action bar can resolve status without an extra
  /// async hop. Stays empty until the first emit.
  List<CaptureSummary> _latestCaptures = const [];

  @override
  void initState() {
    super.initState();
    _loadPageData();
    _selectionController.addListener(_onSelectionChanged);
  }

  @override
  void didUpdateWidget(covariant ProjectDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) {
      _filter = null;
      _latestCaptures = const [];
      _loadPageData();
    }
  }

  void _loadPageData() {
    final database = ref.read(databaseProvider);
    _projectFuture = database.projectById(widget.projectId);
    _captureSummariesStream = database.watchCaptureSummaries(
      CaptureFilter(projectId: widget.projectId),
    );
  }

  void _onSelectionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _selectionController.removeListener(_onSelectionChanged);
    _selectionController.dispose();
    super.dispose();
  }

  CaptureFilter _filterForProject() =>
      _filter?.selectProject(widget.projectId) ??
      CaptureFilter(projectId: widget.projectId);

  void _onFilterChanged(CaptureFilter next) {
    setState(() {
      _filter = next;
      _selectionController.clearForFilterChange();
    });
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
    final allEligibleSelected = _selectionController.allSelected(
      _selectableIds(_latestCaptures),
    );
    return FutureBuilder<Project?>(
      future: _projectFuture,
      builder: (context, projectSnapshot) {
        final project = projectSnapshot.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(project?.name ?? strings.appName),
            actions: [
              if (project != null && !editing) ...[
                IconButton(
                  onPressed: () =>
                      context.go('/projects/${project.id}/settings'),
                  tooltip: strings.projectWatermarkSettings,
                  icon: const Icon(Icons.tune_outlined),
                ),
                IconButton(
                  onPressed: () => _exportProject(context, ref, project.id),
                  tooltip: strings.exportProject,
                  icon: const Icon(Icons.archive_outlined),
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
                  duration: AppMotion.short4,
                  child: Icon(
                    editing ? Icons.done : Icons.edit_outlined,
                    key: ValueKey(editing),
                  ),
                ),
              ),
            ],
          ),
          body: project == null
              ? const Skeletonizer(child: _CaptureListSkeleton())
              : StreamBuilder<List<CaptureSummary>>(
                  stream: _captureSummariesStream,
                  builder: (context, captureSnapshot) {
                    final allProjectSummaries = captureSnapshot.data;
                    final captures = allProjectSummaries == null
                        ? null
                        : filterCaptureSummaries(allProjectSummaries, filter);
                    if (captures != null) {
                      _latestCaptures = captures;
                    }
                    return AnimatedSwitcher(
                      duration: AppMotion.short4,
                      child: captures == null
                          ? const Skeletonizer(
                              key: Key('capture-list-skeleton'),
                              child: _CaptureListSkeleton(),
                            )
                          : KeyedSubtree(
                              key: const Key('capture-list-content'),
                              child: _projectCaptureList(
                                context,
                                strings,
                                project,
                                filter,
                                allProjectSummaries!,
                                captures,
                              ),
                            ),
                    );
                  },
                ),
          bottomNavigationBar: AnimatedSwitcher(
            duration: AppMotion.medium4,
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
          floatingActionButton: AnimatedScale(
            scale: project == null || editing ? 0 : 1,
            duration: AppMotion.medium2,
            curve: AppMotion.emphasized,
            child: FloatingActionButton.extended(
              onPressed: () =>
                  context.go('/projects/${widget.projectId}/capture'),
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(strings.capture),
            ),
          ),
        );
      },
    );
  }

  Widget _projectCaptureList(
    BuildContext context,
    AppStrings strings,
    Project project,
    CaptureFilter filter,
    List<CaptureSummary> allProjectSummaries,
    List<CaptureSummary> captures,
  ) {
    final hasAnyRecord = allProjectSummaries.isNotEmpty;
    return CustomScrollView(
      slivers: [
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
        if (hasAnyRecord)
          SliverToBoxAdapter(
            child: CaptureDateFilterBar(
              filter: filter,
              summaries: allProjectSummaries,
              onChanged: _onFilterChanged,
            ),
          ),
        if (!hasAnyRecord)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                strings.noCaptures,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          )
        else if (captures.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                strings.filteredEmpty,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            sliver: SliverList.separated(
              itemCount: captures.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final summary = captures[index];
                final id = summary.capture.id;
                return CaptureRecordCard(
                  summary: summary,
                  selectionMode: _selectionController.editing,
                  selected: _selectionController.selectedIds.contains(id),
                  selectable:
                      summary.capture.status == CaptureStatus.ready ||
                      summary.capture.status == CaptureStatus.failed,
                  onSelectedChanged: (selected) {
                    if (selected && !_selectionController.editing) {
                      // Long-press entry: the card reports a selection outside
                      // selection mode, so enter editing and select it in one
                      // step.
                      _selectionController.enterWithSelection(id);
                    } else {
                      _selectionController.toggle(id);
                    }
                  },
                  onTap: () => context.push(
                    '/projects/${widget.projectId}'
                    '/captures/$id',
                  ),
                );
              },
            ),
          ),
        ],
      );
  }

  Future<void> _exportProject(
    BuildContext context,
    WidgetRef ref,
    String projectId,
  ) async {
    final strings = AppStrings.of(context);
    var includeOriginals = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(strings.exportProjectData),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: includeOriginals,
                title: Text(strings.includeOriginals),
                onChanged: (value) {
                  setDialogState(() => includeOriginals = value ?? false);
                },
              ),
              Text(strings.includeOriginalsHint),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(strings.generateAndShare),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final result = await ref
          .read(projectExportServiceProvider)
          .exportProject(
            projectId: projectId,
            includeOriginals: includeOriginals,
          );
      await ref.read(shareFileServiceProvider).shareFile(result.outputZipPath);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${strings.exportFailed}: $error')),
      );
    }
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

class _CaptureListSkeleton extends StatelessWidget {
  const _CaptureListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      itemCount: 6,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => const _CaptureCardSkeleton(),
    );
  }
}

class _CaptureCardSkeleton extends StatelessWidget {
  const _CaptureCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: const ColoredBox(color: Colors.grey),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SM-0000-000', style: textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('0000/00/00 00:00', style: textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text('---', style: textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
