import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/data/capture_query_repository.dart';
import 'package:sitemark/domain/capture_list_query.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/features/capture/capture_pager_controller.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/shared/ui/adaptive_page_scaffold.dart';
import 'package:sitemark/shared/ui/adaptive_progress.dart';
import 'package:sitemark/motion.dart';
import 'package:sitemark/shared/ui/adaptive_skeleton_count.dart';
import 'package:skeletonizer/skeletonizer.dart';

typedef CapturePagedItemBuilder =
    Widget Function(
      BuildContext context,
      CaptureSummary summary,
      List<CaptureSummary> visibleRows,
    );

typedef CapturePagedGroupKey = String Function(CaptureSummary summary);

/// Lazy capture list that owns scrolling, loaded-row watches, and page chrome.
class CapturePagedList extends StatefulWidget {
  const CapturePagedList({
    super.key,
    required this.controller,
    required this.source,
    required this.emptyMessage,
    required this.itemBuilder,
    this.sliversBefore = const [],
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 96),
    this.skeletonKey = const Key('capture-list-skeleton'),
    this.contentKey = const Key('capture-list-content'),
    this.skeletonItemCount = 8,
    this.forceInitialLoading = false,
    this.groupKey,
    this.onVisibleGroupChanged,
  }) : assert(
         groupKey != null || onVisibleGroupChanged == null,
         'onVisibleGroupChanged requires groupKey',
       ),
       assert(
         skeletonItemCount >= 2,
         'skeletonItemCount must be at least the adaptive minimum of 2',
       );

  final CapturePagerController controller;
  final CaptureQuerySource source;
  final String emptyMessage;
  final CapturePagedItemBuilder itemBuilder;
  final List<Widget> sliversBefore;
  final EdgeInsetsGeometry padding;
  final Key skeletonKey;
  final Key contentKey;
  final int skeletonItemCount;
  final bool forceInitialLoading;

  /// Groups adjacent rows. The source must order equal keys contiguously.
  final CapturePagedGroupKey? groupKey;
  final ValueChanged<String?>? onVisibleGroupChanged;

  @override
  State<CapturePagedList> createState() => _CapturePagedListState();
}

class _CapturePagedListState extends State<CapturePagedList> {
  final GlobalKey _viewportKey = GlobalKey();
  final Map<String, GlobalKey> _rowKeys = <String, GlobalKey>{};
  final Map<String, String> _rowGroups = <String, String>{};
  late final ScrollController _ownedScrollController = ScrollController(
    keepScrollOffset: true,
  );
  ScrollController? _activeScrollController;
  StreamSubscription<List<CaptureSummary>>? _watchedRowsSubscription;
  List<String> _watchedIds = const [];
  CaptureListQuery? _visibleQuery;
  int _watchGeneration = 0;
  bool _loadMoreScheduled = false;
  bool _visibleGroupReportScheduled = false;
  String? _lastReportedGroup;

  @override
  void initState() {
    super.initState();
    _visibleQuery = widget.controller.state.query;
    widget.controller.addListener(_onPagerChanged);
    _syncWatchedRows();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindScrollController();
  }

  ScrollController get _scrollController =>
      _activeScrollController ?? _ownedScrollController;

  void _bindScrollController() {
    final next =
        nestedInnerScrollControllerOf(context) ?? _ownedScrollController;
    if (identical(next, _activeScrollController)) return;
    _activeScrollController?.removeListener(_onScroll);
    _activeScrollController = next;
    next.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant CapturePagedList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onPagerChanged);
      widget.controller.addListener(_onPagerChanged);
      _visibleQuery = widget.controller.state.query;
      _watchedIds = const [];
      _lastReportedGroup = null;
      _rowKeys.clear();
      _rowGroups.clear();
      _syncWatchedRows();
    } else if (oldWidget.source != widget.source) {
      _watchedIds = const [];
      _syncWatchedRows();
    }
    if (oldWidget.groupKey != widget.groupKey ||
        oldWidget.onVisibleGroupChanged != widget.onVisibleGroupChanged) {
      _lastReportedGroup = null;
      _rowGroups.clear();
      _scheduleVisibleGroupReport();
    }
  }

  void _onPagerChanged() {
    final query = widget.controller.state.query;
    if (!identical(query, _visibleQuery)) {
      _visibleQuery = query;
      _lastReportedGroup = null;
      widget.controller.setAtTop(true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _jumpToTop();
        }
      });
    }
    final visibleIds = widget.controller.state.rows
        .map((summary) => summary.capture.id)
        .toSet();
    _rowKeys.removeWhere((id, _) => !visibleIds.contains(id));
    _rowGroups.removeWhere((id, _) => !visibleIds.contains(id));
    _syncWatchedRows();
    if (mounted) {
      setState(() {});
      _scheduleVisibleGroupReport();
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    widget.controller.setAtTop(_scrollController.offset <= 0.5);
    _scheduleVisibleGroupReport();
  }

  void _scheduleVisibleGroupReport() {
    if (_visibleGroupReportScheduled ||
        widget.groupKey == null ||
        widget.onVisibleGroupChanged == null) {
      return;
    }
    _visibleGroupReportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibleGroupReportScheduled = false;
      if (mounted) _reportVisibleGroup();
    });
  }

  void _reportVisibleGroup() {
    final callback = widget.onVisibleGroupChanged;
    final groupKey = widget.groupKey;
    if (callback == null || groupKey == null) return;
    if (widget.controller.state.rows.isEmpty) {
      _emitVisibleGroup(null);
      return;
    }
    final viewport = _viewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.attached) return;
    final viewportTop = viewport.localToGlobal(Offset.zero).dy;
    var nearestTop = double.infinity;
    String? nearestGroup;
    final detachedIds = <String>[];
    for (final entry in _rowKeys.entries) {
      final renderObject = entry.value.currentContext?.findRenderObject();
      if (renderObject is! RenderBox ||
          !renderObject.attached ||
          !renderObject.hasSize) {
        detachedIds.add(entry.key);
        continue;
      }
      final top = renderObject.localToGlobal(Offset.zero).dy;
      if (top + renderObject.size.height > viewportTop + .5 &&
          top < nearestTop) {
        nearestTop = top;
        nearestGroup = _rowGroups[entry.key];
      }
    }
    for (final id in detachedIds) {
      _rowKeys.remove(id);
      _rowGroups.remove(id);
    }
    if (nearestGroup != null) _emitVisibleGroup(nearestGroup);
  }

  void _emitVisibleGroup(String? value) {
    if (_lastReportedGroup == value) return;
    _lastReportedGroup = value;
    widget.onVisibleGroupChanged?.call(value);
  }

  bool _sameIds(List<String> next) {
    if (_watchedIds.length != next.length) return false;
    for (var index = 0; index < next.length; index++) {
      if (_watchedIds[index] != next[index]) return false;
    }
    return true;
  }

  void _syncWatchedRows() {
    final ids = widget.controller.state.rows
        .map((row) => row.capture.id)
        .toList(growable: false);
    if (_sameIds(ids)) return;
    _watchedIds = ids;
    final generation = ++_watchGeneration;
    final previous = _watchedRowsSubscription;
    _watchedRowsSubscription = null;
    if (previous != null) unawaited(previous.cancel());
    if (ids.isEmpty) return;
    _watchedRowsSubscription = widget.source
        .watchByIds(ids.toSet())
        .listen(
          (rows) {
            if (!mounted || generation != _watchGeneration) return;
            final returnedIds = rows.map((row) => row.capture.id).toSet();
            if (_watchedIds.any((id) => !returnedIds.contains(id))) {
              unawaited(widget.controller.refresh());
              return;
            }
            if (_watchedRowsChangeQueryMembershipOrOrder(rows)) {
              unawaited(widget.controller.refresh());
              return;
            }
            widget.controller.replaceWatchedRows(rows);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!mounted || generation != _watchGeneration) return;
            // A transient stream error should not silently break the real-time feed;
            // trigger a full refresh so the controller either surfaces the error
            // through its error state or succeeds on the next load.
            unawaited(widget.controller.refresh());
          },
        );
  }

  bool _watchedRowsChangeQueryMembershipOrOrder(
    Iterable<CaptureSummary> watchedRows,
  ) {
    final visibleRows = {
      for (final row in widget.controller.state.rows) row.capture.id: row,
    };
    final query = widget.controller.state.query;
    for (final row in watchedRows) {
      final previous = visibleRows[row.capture.id];
      if (previous == null ||
          _rowChangesQueryMembershipOrOrder(previous, row, query)) {
        return true;
      }
    }
    return false;
  }

  bool _rowChangesQueryMembershipOrOrder(
    CaptureSummary previous,
    CaptureSummary current,
    CaptureListQuery query,
  ) {
    final before = previous.capture;
    final after = current.capture;
    if ((before.status == CaptureStatus.pendingCamera) !=
            (after.status == CaptureStatus.pendingCamera) ||
        before.capturedAt != after.capturedAt ||
        before.createdAt != after.createdAt) {
      return true;
    }
    if (query.filter.projectId != null && before.projectId != after.projectId) {
      return true;
    }
    if (query.normalizedTerms.isEmpty) return false;
    return previous.projectName != current.projectName ||
        before.workLocation != after.workLocation ||
        before.workContent != after.workContent ||
        before.photographer != after.photographer ||
        before.notes != after.notes ||
        before.photoNumber != after.photoNumber ||
        before.address != after.address;
  }

  void _scheduleLoadMore(int index, CapturePagerState state) {
    if (_loadMoreScheduled ||
        state.loadingMore ||
        state.nextPageError != null ||
        !state.hasMore ||
        index < state.rows.length - 8) {
      return;
    }
    _loadMoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMoreScheduled = false;
      if (mounted) unawaited(widget.controller.loadMore());
    });
  }

  void _jumpToTop() {
    jumpNestedScrollViewsToTop(context);
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.minScrollExtent);
    }
  }

  Future<void> _acceptNewer() async {
    widget.controller.setAtTop(true);
    if (nestedScrollViewStateOf(context) != null) {
      _jumpToTop();
    } else if (_scrollController.hasClients) {
      final duration = AppMotion.durationOf(context, AppMotion.short4);
      if (duration == Duration.zero) {
        _scrollController.jumpTo(0);
      } else {
        await _scrollController.animateTo(
          0,
          duration: duration,
          curve: AppMotion.emphasizedDecelerate,
        );
      }
    }
    await widget.controller.acceptNewer();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onPagerChanged);
    _activeScrollController?.removeListener(_onScroll);
    _ownedScrollController.dispose();
    _watchGeneration++;
    final subscription = _watchedRowsSubscription;
    _watchedRowsSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final showSkeleton =
        widget.forceInitialLoading ||
        (state.initialLoading && state.rows.isEmpty);
    final showInitialError =
        !showSkeleton && state.initialError != null && state.rows.isEmpty;
    final showContent = !showSkeleton && !showInitialError;
    final strings = AppStrings.of(context);
    _scheduleVisibleGroupReport();
    return LayoutBuilder(
      key: widget.contentKey,
      builder: (context, constraints) => AnimatedSwitcher(
        key: const Key('capture-page-switcher'),
        duration: AppMotion.durationOf(context, AppMotion.short4),
        child: Stack(
          key: const ValueKey('capture-page-surface'),
          children: [
            CustomScrollView(
              key: _viewportKey,
              controller: _scrollController,
              // iOS pattern: dragging the results pulls the search
              // keyboard down with the finger.
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                ...widget.sliversBefore,
                SliverToBoxAdapter(
                  child: AnimatedSwitcher(
                    duration: AppMotion.durationOf(context, AppMotion.short4),
                    child: showSkeleton
                        ? _buildSkeletonStatus(constraints.maxHeight)
                        : showInitialError
                        ? _buildInitialErrorStatus(strings)
                        : const SizedBox.shrink(
                            key: ValueKey('capture-page-ready'),
                          ),
                  ),
                ),
                if (showContent && state.rows.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          widget.emptyMessage,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    ),
                  )
                else if (showContent)
                  ..._buildContentSlivers(context, state),
                if (showContent && state.loadingMore)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
                      child: Center(
                        child: SizedBox.square(
                          key: Key('capture-next-page-loading'),
                          dimension: 24,
                          child: AdaptiveProgressIndicator(size: 18),
                        ),
                      ),
                    ),
                  )
                else if (showContent && state.nextPageError != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      child: Center(
                        child: TextButton.icon(
                          key: const Key('capture-next-page-retry'),
                          onPressed: widget.controller.loadMore,
                          icon: const Icon(Icons.refresh),
                          label: Text(strings.loadMoreFailedRetry),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (showContent && state.hasNewer)
              Positioned(
                top: 12,
                left: 0,
                right: 0,
                child: Center(
                  child: FilledButton.tonalIcon(
                    key: const Key('capture-new-records'),
                    onPressed: _acceptNewer,
                    icon: const Icon(Icons.arrow_upward),
                    label: Text(strings.newCaptureRecords),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildContentSlivers(
    BuildContext context,
    CapturePagerState state,
  ) {
    final groupKey = widget.groupKey;
    if (groupKey == null) {
      return [
        SliverPadding(
          padding: widget.padding,
          sliver: SliverList.separated(
            itemCount: state.rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _buildRow(context, state, index),
          ),
        ),
      ];
    }

    final groups = <_CaptureRowGroup>[];
    for (var index = 0; index < state.rows.length; index++) {
      final key = groupKey(state.rows[index]);
      if (groups.isEmpty || groups.last.key != key) {
        groups.add(_CaptureRowGroup(key: key, startIndex: index, length: 1));
      } else {
        groups.last.length++;
      }
    }
    final padding = widget.padding.resolve(Directionality.of(context));
    return [
      for (var groupIndex = 0; groupIndex < groups.length; groupIndex++)
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            padding.left,
            groupIndex == 0 ? padding.top : 0,
            padding.right,
            groupIndex == groups.length - 1 ? padding.bottom : 12,
          ),
          sliver: SliverList.separated(
            itemCount: groups[groupIndex].length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, localIndex) => _buildRow(
              context,
              state,
              groups[groupIndex].startIndex + localIndex,
            ),
          ),
        ),
    ];
  }

  Widget _buildRow(BuildContext context, CapturePagerState state, int index) {
    _scheduleLoadMore(index, state);
    final summary = state.rows[index];
    final id = summary.capture.id;
    final rowKey = _rowKeys.putIfAbsent(id, GlobalKey.new);
    final groupKey = widget.groupKey;
    if (groupKey == null) {
      _rowGroups.remove(id);
    } else {
      _rowGroups[id] = groupKey(summary);
    }
    return KeyedSubtree(
      key: rowKey,
      child: widget.itemBuilder(context, summary, state.rows),
    );
  }

  Widget _buildSkeletonStatus(double viewportHeight) {
    final skeletonCount = adaptiveSkeletonCount(
      viewportHeight: viewportHeight,
      itemExtent: 118,
      max: widget.skeletonItemCount,
    );
    return Skeletonizer(
      key: widget.skeletonKey,
      child: Padding(
        padding: widget.padding,
        child: Column(
          children: List.generate(
            skeletonCount,
            (index) => Padding(
              padding: EdgeInsets.only(
                bottom: index == skeletonCount - 1 ? 0 : 10,
              ),
              child: const _CaptureCardSkeleton(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInitialErrorStatus(AppStrings strings) {
    return SizedBox(
      key: const Key('capture-initial-error'),
      height: MediaQuery.sizeOf(context).height * 0.55,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(strings.captureListLoadFailed, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.tonal(
                key: const Key('capture-initial-retry'),
                onPressed: widget.controller.refresh,
                child: Text(strings.retry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _CaptureRowGroup {
  _CaptureRowGroup({
    required this.key,
    required this.startIndex,
    required this.length,
  });

  final String key;
  final int startIndex;
  int length;
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
