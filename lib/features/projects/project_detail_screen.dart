import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_filter.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/features/capture/capture_batch_action_bar.dart';
import 'package:sitemark/features/capture/capture_date_filter_bar.dart';
import 'package:sitemark/features/capture/capture_record_card.dart';
import 'package:sitemark/features/capture/capture_selection_controller.dart';
import 'package:sitemark/l10n/app_strings.dart';

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

  /// Latest filtered captures emitted by the inner StreamBuilder. Updated
  /// synchronously during build (no `setState`) so the AppBar's select-all
  /// action and the bottom action bar can resolve status without an extra
  /// async hop. Stays empty until the first emit.
  List<CaptureSummary> _latestCaptures = const [];

  @override
  void initState() {
    super.initState();
    _selectionController.addListener(_onSelectionChanged);
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
    final database = ref.watch(databaseProvider);
    final strings = AppStrings.of(context);
    final filter = _filterForProject();
    final editing = _selectionController.editing;
    final allEligibleSelected = _selectionController.allSelected(
      _selectableIds(_latestCaptures),
    );
    return FutureBuilder<Project?>(
      future: database.projectById(widget.projectId),
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
                  tooltip: strings.watermarkSettings,
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
                icon: Icon(editing ? Icons.done : Icons.edit_outlined),
              ),
            ],
          ),
          body: project == null
              ? const Center(child: CircularProgressIndicator())
              : StreamBuilder<List<CaptureSummary>>(
                  stream: database.watchCaptureSummaries(filter),
                  builder: (context, captureSnapshot) {
                    if (!captureSnapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final captures = captureSnapshot.data!;
                    _latestCaptures = captures;
                    return StreamBuilder<List<CaptureSummary>>(
                      stream: database.watchCaptureSummaries(
                        CaptureFilter(projectId: widget.projectId),
                      ),
                      builder: (context, projectSummarySnapshot) {
                        final allProjectSummaries =
                            projectSummarySnapshot.data ?? const [];
                        final hasAnyRecord = allProjectSummaries.isNotEmpty;
                        return CustomScrollView(
                          slivers: [
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  20,
                                  16,
                                  8,
                                ),
                                child: _ProjectHeader(project: project),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  12,
                                  20,
                                  4,
                                ),
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
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyLarge,
                                  ),
                                ),
                              )
                            else if (captures.isEmpty)
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: Center(
                                  child: Text(
                                    strings.filteredEmpty,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyLarge,
                                  ),
                                ),
                              )
                            else
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  96,
                                ),
                                sliver: SliverList.separated(
                                  itemCount: captures.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    final summary = captures[index];
                                    final id = summary.capture.id;
                                    return CaptureRecordCard(
                                      summary: summary,
                                      selectionMode: editing,
                                      selected: _selectionController.selectedIds
                                          .contains(id),
                                      selectable:
                                          summary.capture.status ==
                                              CaptureStatus.ready ||
                                          summary.capture.status ==
                                              CaptureStatus.failed,
                                      onSelectedChanged: (_) =>
                                          _selectionController.toggle(id),
                                      onTap: () => context.go(
                                        '/projects/${widget.projectId}'
                                        '/captures/$id',
                                      ),
                                    );
                                  },
                                ),
                              ),
                          ],
                        );
                      },
                    );
                  },
                ),
          bottomNavigationBar:
              editing && _selectionController.selectedIds.isNotEmpty
              ? CaptureBatchActionBar(
                  controller: _selectionController,
                  mediaService: ref.watch(captureMediaServiceProvider),
                  exportService: ref.watch(projectExportServiceProvider),
                  shareService: ref.watch(shareFileServiceProvider),
                  summaries: _latestCaptures,
                )
              : null,
          floatingActionButton: project == null || editing
              ? null
              : FloatingActionButton.extended(
                  onPressed: () =>
                      context.go('/projects/${widget.projectId}/capture'),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(strings.capture),
                ),
        );
      },
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
