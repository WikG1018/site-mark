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
import 'package:sitemark/features/capture/capture_active_filter_chips.dart';
import 'package:sitemark/features/capture/capture_batch_action_bar.dart';
import 'package:sitemark/features/capture/capture_detail_screen.dart';
import 'package:sitemark/features/capture/capture_filter_sheet.dart';
import 'package:sitemark/features/capture/capture_fullscreen_sequence.dart';
import 'package:sitemark/features/capture/capture_paged_list.dart';
import 'package:sitemark/features/capture/capture_pager_controller.dart';
import 'package:sitemark/features/capture/capture_record_card.dart';
import 'package:sitemark/features/capture/capture_search_field.dart';
import 'package:sitemark/features/capture/capture_selection_controller.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/shared/ui/adaptive_progress.dart';
import 'package:sitemark/shared/ui/adaptive_toast.dart';
import 'package:sitemark/motion.dart';
import 'package:sitemark/navigation/root_chrome_controller.dart';
import 'package:sitemark/navigation/scroll_chrome.dart';
import 'package:sitemark/shared/ui/floating_dock_layout.dart';
import 'package:sitemark/shared/ui/adaptive_page_scaffold.dart';

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
  String? _visibleDateKey;
  final CaptureSelectionController _selectionController =
      CaptureSelectionController();
  late final Stream<List<Project>> _projectsStream;
  late final CaptureQuerySource _querySource;
  late final CapturePagerController _pagerController;
  late final AllCapturesSelectionModeController _rootChromeController;
  CaptureListQuery get _query =>
      CaptureListQuery(filter: _filter, searchText: _searchText);

  @override
  void initState() {
    super.initState();
    _projectsStream = ref.read(databaseProvider).watchProjects();
    _querySource =
        widget.querySource ?? ref.read(captureQueryRepositoryProvider);
    _pagerController = CapturePagerController(_querySource, pageSize: 50);
    _rootChromeController = ref.read(allCapturesSelectionModeProvider.notifier);
    _rootChromeController.setActive(false);
    _startQuery();
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
    _rootChromeController.setActive(_selectionController.editing);
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
    _rootChromeController.setActive(false);
    super.dispose();
  }

  /// Consumes a system back on the root records page: exit selection mode
  /// first, then close search, then clear applied filters — in that order,
  /// mirroring the UX hierarchy.
  bool _handleRootBack() {
    if (_selectionController.editing) {
      _invalidateSelectionRequests();
      _selectionController.exit();
      return true;
    }
    if (_searching) {
      _exitSearch();
      return true;
    }
    if (_hasFilter) {
      _onFilterChanged(const CaptureFilter());
      return true;
    }
    return false;
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
    _dateOptions = const CaptureDateOptions();
    _visibleDateKey = null;
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
    // The PopScope intercepts a system back while selection mode, search or a
    // filter is active on this root branch page. Without it the router
    // delegate stops at the shell's first page (nothing to pop) and Android
    // finishes the activity, so the back would exit the app instead of
    // exiting selection mode — the reported bug this guards against.
    return PopScope(
      canPop: !editing && !_searching && !_hasFilter,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleRootBack();
      },
      child: ScrollChromeForce(
        reason: 'records-search',
        active: _searching,
        child: ScrollChromeForce(
          reason: 'records-selection',
          active: editing,
          child: StreamBuilder<List<Project>>(
            stream: _projectsStream,
            builder: (context, snapshot) {
              final projects = snapshot.data ?? const <Project>[];
              return AdaptivePageScaffold.raw(
                hideOnScroll: true,
                title: strings.allRecords,
                titleWidget: AnimatedSwitcher(
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
                              child: AdaptiveProgressIndicator(size: 20),
                            )
                          : Icon(
                              allEligibleSelected
                                  ? Icons.check_box_outline_blank
                                  : Icons.select_all_outlined,
                            ),
                    ),
                  if (!_searching || editing)
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
                        duration: AppMotion.durationOf(
                          context,
                          AppMotion.short4,
                        ),
                        child: Icon(
                          editing ? Icons.done : Icons.edit_outlined,
                          key: ValueKey(editing),
                        ),
                      ),
                    ),
                ],
                bottom: _searching
                    ? null
                    : PreferredSize(
                        preferredSize: const Size.fromHeight(
                          scrollChromeFilterBarHeight,
                        ),
                        child: _filterBar(context, strings, projects),
                      ),
                iosBodyPadding: EdgeInsets.zero,
                body: FloatingDockLayout(
                  animateDock: false,
                  dock: editing
                      ? CaptureBatchActionBar(
                          key: const Key('batch-bar'),
                          controller: _selectionController,
                          mediaService: ref.watch(captureMediaServiceProvider),
                          exportService: ref.watch(
                            projectExportServiceProvider,
                          ),
                          shareService: ref.watch(shareFileServiceProvider),
                        )
                      : null,
                  child: CapturePagedList(
                    controller: _pagerController,
                    source: _querySource,
                    emptyMessage: _hasActiveQuery
                        ? strings.filteredEmpty
                        : strings.noCaptures,
                    itemBuilder: _buildCaptureCard,
                    padding: EdgeInsets.fromLTRB(
                      16,
                      4 +
                          scrollChromeTopInsetOf(
                            context,
                            extra: _searching ? 0 : scrollChromeFilterBarHeight,
                          ),
                      16,
                      floatingDockReservedSpaceOf(context),
                    ),
                    groupKey: _captureDateKey,
                    onVisibleGroupChanged: _onVisibleDateChanged,
                  ),
                ),
              );
            },
          ),
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
    final dateKey = _exactFilteredDateKey ?? _visibleDateKey;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          OutlinedButton.icon(
            key: const Key('filter-sheet-trigger'),
            onPressed: () => unawaited(_openFilterSheet(projects)),
            icon: const Icon(Icons.filter_list_outlined),
            label: Text(strings.filterAction),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                if (_hasFilter)
                  Expanded(
                    child: CaptureActiveFilterChips(
                      filter: _filter,
                      projects: projects,
                      onChanged: _onFilterChanged,
                    ),
                  )
                else
                  const Spacer(),
                if (dateKey != null) ...[
                  if (_hasFilter) const SizedBox(width: 8),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Semantics(
                        label: strings.currentVisibleDate(dateKey),
                        child: Text(
                          dateKey,
                          key: const Key('visible-capture-date'),
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool get _hasFilter =>
      _filter.projectId != null ||
      _filter.year != null ||
      _filter.month != null ||
      _filter.day != null;

  Future<void> _openFilterSheet(List<Project> projects) async {
    if (_searching) return;
    final chrome = ScrollChromeScope.maybeOf(context);
    chrome?.setForce('records-filter', true);
    final CaptureFilter? next;
    try {
      next = await showCaptureFilterSheet(
        context: context,
        initial: _filter,
        projects: projects,
        options: _dateOptions,
        optionsLoader: (draft) => _querySource.loadDateOptions(
          CaptureListQuery(filter: draft, searchText: _searchText),
        ),
      );
    } finally {
      chrome?.setForce('records-filter', false);
    }
    if (!mounted || next == null || _searching) return;
    _onFilterChanged(next);
  }

  String _captureDateKey(CaptureSummary summary) {
    final time = summary.capture.capturedAt ?? summary.capture.createdAt;
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)}';
  }

  String? get _exactFilteredDateKey {
    final year = _filter.year;
    final month = _filter.month;
    final day = _filter.day;
    if (year == null || month == null || day == null) return null;
    String two(int value) => value.toString().padLeft(2, '0');
    return '$year-${two(month)}-${two(day)}';
  }

  void _onVisibleDateChanged(String? value) {
    if (!mounted || _visibleDateKey == value) return;
    setState(() => _visibleDateKey = value);
  }
}
