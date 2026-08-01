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
import 'package:sitemark/features/capture/capture_batch_action_bar.dart';
import 'package:sitemark/features/capture/capture_date_filter_bar.dart';
import 'package:sitemark/features/capture/capture_detail_screen.dart';
import 'package:sitemark/features/capture/capture_fullscreen_sequence.dart';
import 'package:sitemark/features/capture/capture_paged_list.dart';
import 'package:sitemark/features/capture/capture_pager_controller.dart';
import 'package:sitemark/features/capture/capture_record_card.dart';
import 'package:sitemark/features/capture/capture_search_field.dart';
import 'package:sitemark/features/capture/capture_selection_controller.dart';
import 'package:sitemark/features/capture/compact_filter_menu.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';

/// Global capture-records surface backed by a fixed-size cursor pager.
class AllCapturesScreen extends ConsumerStatefulWidget {
  const AllCapturesScreen({super.key, this.querySource});

  final CaptureQuerySource? querySource;

  @override
  ConsumerState<AllCapturesScreen> createState() => _AllCapturesScreenState();
}

class _AllCapturesScreenState extends ConsumerState<AllCapturesScreen> {
  CaptureFilter _filter = const CaptureFilter();
  String _searchText = '';
  bool _searching = false;
  CaptureDateOptions _dateOptions = const CaptureDateOptions();
  int _dateOptionsGeneration = 0;
  int _selectionGeneration = 0;
  bool _selectAllLoading = false;
  bool _allQuerySelected = false;
  final CaptureSelectionController _selectionController =
      CaptureSelectionController();
  late final Stream<List<Project>> _projectsStream;
  late final CaptureQuerySource _querySource;
  late final CapturePagerController _pagerController;
  CaptureListQuery get _query =>
      CaptureListQuery(filter: _filter, searchText: _searchText);

  @override
  void initState() {
    super.initState();
    _projectsStream = ref.read(databaseProvider).watchProjects();
    _querySource =
        widget.querySource ?? ref.read(captureQueryRepositoryProvider);
    _pagerController = CapturePagerController(_querySource, pageSize: 50);
    unawaited(_pagerController.setQuery(_query));
    unawaited(_loadDateOptions(_query));
    _pagerController.addListener(_onPagerChanged);
    _selectionController.addListener(_onSelectionChanged);
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
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(strings.captureListLoadFailed),
        action: SnackBarAction(label: strings.retry, onPressed: retry),
      ),
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

  bool get _hasActiveQuery =>
      _filter.projectId != null ||
      _filter.year != null ||
      _filter.month != null ||
      _filter.day != null ||
      _query.normalizedTerms.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final editing = _selectionController.editing;
    final allEligibleSelected =
        _allQuerySelected && _selectionController.selectedIds.isNotEmpty;
    return PopScope(
      canPop: !editing && !_searching,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_selectionController.editing) {
          _invalidateSelectionRequests();
          _selectionController.exit();
        } else if (_searching) {
          _exitSearch();
        }
      },
      child: Scaffold(
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
                    strings.allRecords,
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
            if (editing)
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
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        allEligibleSelected
                            ? Icons.check_box_outline_blank
                            : Icons.select_all_outlined,
                      ),
              ),
            IconButton(
              key: const Key('edit-captures'),
              onPressed: () {
                if (_selectionController.editing) {
                  _invalidateSelectionRequests();
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
        body: StreamBuilder<List<Project>>(
          stream: _projectsStream,
          builder: (context, snapshot) {
            final projects = snapshot.data ?? const <Project>[];
            return Column(
              children: [
                _filterBar(context, strings, projects),
                Expanded(
                  child: CapturePagedList(
                    controller: _pagerController,
                    source: _querySource,
                    emptyMessage: _hasActiveQuery
                        ? strings.filteredEmpty
                        : strings.noCaptures,
                    itemBuilder: _buildCaptureCard,
                  ),
                ),
              ],
            );
          },
        ),
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
                )
              : const SizedBox.shrink(key: Key('batch-bar-empty')),
        ),
      ),
    );
  }

  Widget _buildCaptureCard(
    BuildContext context,
    CaptureSummary summary,
    List<CaptureSummary> _,
  ) {
    final id = summary.capture.id;
    return CaptureRecordCard(
      key: ValueKey(id),
      summary: summary,
      showProjectName: true,
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
        '/projects/${summary.capture.projectId}/captures/$id',
        extra: CaptureDetailArguments(
          capture: summary.capture,
          initialImagePath: initialImagePath,
          navigationContext: CaptureNavigationContext(
            query: _pagerController.state.query,
            cursor: (
              sortTime: summary.capture.capturedAt ?? summary.capture.createdAt,
              id: summary.capture.id,
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterBar(
    BuildContext context,
    AppStrings strings,
    List<Project> projects,
  ) {
    final projectEntries = <(String?, String)>[(null, strings.allProjects)];
    for (final project in projects) {
      projectEntries.add((project.id, project.name));
    }
    var projectLabel = strings.allProjects;
    for (final project in projects) {
      if (project.id == _filter.projectId) projectLabel = project.name;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: CompactFilterMenu<String?>(
              key: const Key('project-filter'),
              label: projectLabel,
              selectedValue: _filter.projectId,
              entries: projectEntries,
              onSelected: (value) =>
                  _onFilterChanged(CaptureFilter(projectId: value)),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 3,
            child: CaptureDateFilterBar(
              padding: EdgeInsets.zero,
              filter: _filter,
              options: _dateOptions,
              onChanged: _onFilterChanged,
            ),
          ),
        ],
      ),
    );
  }
}
