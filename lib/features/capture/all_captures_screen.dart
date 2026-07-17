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
import 'package:sitemark/features/capture/compact_filter_menu.dart';
import 'package:sitemark/l10n/app_strings.dart';

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
    final database = ref.watch(databaseProvider);
    final editing = _selectionController.editing;
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.allRecords),
        actions: [
          if (editing)
            IconButton(
              key: const Key('select-all-captures'),
              onPressed: () {
                _selectionController.selectAll(_selectableIds(_latestCaptures));
              },
              tooltip: strings.selectAll,
              icon: const Icon(Icons.select_all_outlined),
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
      body: StreamBuilder<List<Project>>(
        stream: database.watchProjects(),
        builder: (context, projectSnapshot) {
          return StreamBuilder<List<CaptureSummary>>(
            stream: database.watchAllCaptureSummaries(),
            builder: (context, allSnapshot) {
              final allSummaries = allSnapshot.data ?? const [];
              final projects = projectSnapshot.data ?? const [];
              final dateOptionSummaries = _filter.projectId == null
                  ? allSummaries
                  : allSummaries
                        .where(
                          (summary) =>
                              summary.capture.projectId == _filter.projectId,
                        )
                        .toList(growable: false);
              return Column(
                children: [
                  _filterBar(
                    context,
                    strings,
                    database,
                    projects,
                    dateOptionSummaries,
                  ),
                  Expanded(
                    child: StreamBuilder<List<CaptureSummary>>(
                      stream: database.watchCaptureSummaries(_filter),
                      builder: (context, filteredSnapshot) {
                        if (!filteredSnapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final rows = filteredSnapshot.data!;
                        _latestCaptures = rows;
                        if (rows.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text(
                                allSummaries.isEmpty
                                    ? strings.noCaptures
                                    : strings.filteredEmpty,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ),
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                          itemCount: rows.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final summary = rows[index];
                            final id = summary.capture.id;
                            return CaptureRecordCard(
                              summary: summary,
                              showProjectName: true,
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
                                '/projects/${summary.capture.projectId}'
                                '/captures/$id',
                              ),
                            );
                          },
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
    );
  }

  Widget _filterBar(
    BuildContext context,
    AppStrings strings,
    AppDatabase database,
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
