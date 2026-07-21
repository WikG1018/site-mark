import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_filter.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/domain/capture_summary_filter.dart';
import 'package:sitemark/features/capture/capture_batch_action_bar.dart';
import 'package:sitemark/features/capture/capture_date_filter_bar.dart';
import 'package:sitemark/features/capture/capture_record_card.dart';
import 'package:sitemark/features/capture/capture_selection_controller.dart';
import 'package:sitemark/features/capture/compact_filter_menu.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';
import 'package:skeletonizer/skeletonizer.dart';

/// Global capture-records surface.
///
/// Combines an optional project filter, the shared [CaptureDateFilterBar], and
/// [CaptureRecordCard]s sourced from [AppDatabase.watchCaptureSummaries]. The
/// unfiltered [AppDatabase.watchAllCaptureSummaries] stream drives the project
/// dropdown and is narrowed to the selected project before supplying cascading
/// date options. Record taps route to the existing project-scoped capture
/// detail using the IDs carried by each [CaptureSummary].
class AllCapturesScreen extends ConsumerStatefulWidget {
  const AllCapturesScreen({super.key});

  @override
  ConsumerState<AllCapturesScreen> createState() => _AllCapturesScreenState();
}

class _AllCapturesScreenState extends ConsumerState<AllCapturesScreen> {
  CaptureFilter _filter = const CaptureFilter();
  final CaptureSelectionController _selectionController =
      CaptureSelectionController();

  /// Cached streams so a rebuild does not re-open the same watch. Drift
  /// deduplicates identical stream subscriptions, but holding the reference
  /// avoids building a new stream object on every `build` and keeps the
  /// `AnimatedSwitcher` skeleton → content cross-fade stable across rebuilds.
  late Stream<List<Project>> _projectsStream;
  late Stream<List<CaptureSummary>> _captureSummariesStream;

  /// Latest filtered captures emitted by the inner StreamBuilder. Updated
  /// synchronously during build (no `setState`) so the AppBar's select-all
  /// action and the bottom action bar can resolve status without an extra
  /// async hop. Stays empty until the first emit.
  List<CaptureSummary> _latestCaptures = const [];

  @override
  void initState() {
    super.initState();
    final database = ref.read(databaseProvider);
    _projectsStream = database.watchProjects();
    _captureSummariesStream = database.watchAllCaptureSummaries();
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

  Widget _captureListContent(
    BuildContext context,
    AppStrings strings,
    List<CaptureSummary> allSummaries,
    List<CaptureSummary> rows,
  ) {
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            allSummaries.isEmpty ? strings.noCaptures : strings.filteredEmpty,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final summary = rows[index];
        final id = summary.capture.id;
        return CaptureRecordCard(
          summary: summary,
          showProjectName: true,
          selectionMode: _selectionController.editing,
          selected: _selectionController.selectedIds.contains(id),
          selectable:
              summary.capture.status == CaptureStatus.ready ||
              summary.capture.status == CaptureStatus.failed,
          onSelectedChanged: (selected) {
            if (selected && !_selectionController.editing) {
              // Long-press entry: the card reports a selection outside
              // selection mode, so enter editing and select it in one step.
              _selectionController.enterWithSelection(id);
            } else {
              _selectionController.toggle(id);
            }
          },
          onTap: () => context.push(
            '/projects/${summary.capture.projectId}'
            '/captures/$id',
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final editing = _selectionController.editing;
    final allEligibleSelected = _selectionController.allSelected(
      _selectableIds(_latestCaptures),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.allRecords),
        actions: [
          if (editing)
            IconButton(
              key: const Key('select-all-captures'),
              onPressed: () {
                _selectionController.toggleAll(_selectableIds(_latestCaptures));
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
      body: StreamBuilder<List<Project>>(
        stream: _projectsStream,
        builder: (context, projectSnapshot) {
          return StreamBuilder<List<CaptureSummary>>(
            stream: _captureSummariesStream,
            builder: (context, allSnapshot) {
              final allSummaries = allSnapshot.data ?? const [];
              final projects = projectSnapshot.data ?? const [];
              final dateOptionSummaries = filterCaptureSummaries(
                allSummaries,
                CaptureFilter(projectId: _filter.projectId),
              );
              final rows = filterCaptureSummaries(allSummaries, _filter);
              return Column(
                children: [
                  _filterBar(context, strings, projects, dateOptionSummaries),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: AppMotion.short4,
                      child: !allSnapshot.hasData
                          ? const Skeletonizer(
                              key: Key('capture-list-skeleton'),
                              child: _CaptureListSkeleton(),
                            )
                          : KeyedSubtree(
                              key: const Key('capture-list-content'),
                              child: Builder(
                                builder: (context) {
                                  _latestCaptures = rows;
                                  return _captureListContent(
                                    context,
                                    strings,
                                    allSummaries,
                                    rows,
                                  );
                                },
                              ),
                            ),
                    ),
                  ),
                ],
              );
            },
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
    );
  }

  Widget _filterBar(
    BuildContext context,
    AppStrings strings,
    List<Project> projects,
    List<CaptureSummary> allSummaries,
  ) {
    final projectEntries = <(String?, String)>[(null, strings.allProjects)];
    for (final project in projects) {
      projectEntries.add((project.id, project.name));
    }
    String projectLabel() {
      if (_filter.projectId == null) return strings.allProjects;
      for (final project in projects) {
        if (project.id == _filter.projectId) return project.name;
      }
      return strings.allProjects;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: CompactFilterMenu<String?>(
              key: const Key('project-filter'),
              label: projectLabel(),
              selectedValue: _filter.projectId,
              entries: projectEntries,
              onSelected: (value) => setState(() {
                // Reset the entire filter so the project -> year -> month ->
                // day cascade clears invalid children: changing the project
                // must drop a previously-selected year/month/day that may not
                // exist under the new project.
                _filter = CaptureFilter(projectId: value);
                _selectionController.clearForFilterChange();
              }),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 3,
            child: CaptureDateFilterBar(
              padding: EdgeInsets.zero,
              filter: _filter,
              summaries: allSummaries,
              onChanged: _onFilterChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// Placeholder card list painted by [Skeletonizer] while the first capture
/// summary emit is in flight. Mirrors the [CaptureRecordCard] row layout
/// (thumbnail + title + two metadata lines) so the cross-fade to real content
/// does not jump. Text glyphs are only filler -- Skeletonizer replaces them
/// with bone shapes, so they stay locale-neutral placeholders.
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
