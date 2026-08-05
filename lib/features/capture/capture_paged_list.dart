import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/data/capture_query_repository.dart';
import 'package:sitemark/domain/capture_list_query.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/features/capture/capture_pager_controller.dart';
import 'package:sitemark/l10n/app_strings.dart';
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
typedef CapturePagedGroupHeaderBuilder =
    Widget Function(BuildContext context, String groupKey);

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
    this.groupHeaderBuilder,
  }) : assert(
         (groupKey == null) == (groupHeaderBuilder == null),
         'groupKey and groupHeaderBuilder must be provided together',
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
  final CapturePagedGroupHeaderBuilder? groupHeaderBuilder;

  @override
  State<CapturePagedList> createState() => _CapturePagedListState();
}

class _CapturePagedListState extends State<CapturePagedList> {
  late final ScrollController _scrollController = ScrollController(
    keepScrollOffset: true,
  );
  StreamSubscription<List<CaptureSummary>>? _watchedRowsSubscription;
  List<String> _watchedIds = const [];
  CaptureListQuery? _visibleQuery;
  int _watchGeneration = 0;
  bool _loadMoreScheduled = false;

  @override
  void initState() {
    super.initState();
    _visibleQuery = widget.controller.state.query;
    widget.controller.addListener(_onPagerChanged);
    _scrollController.addListener(_onScroll);
    _syncWatchedRows();
  }

  @override
  void didUpdateWidget(covariant CapturePagedList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onPagerChanged);
      widget.controller.addListener(_onPagerChanged);
      _visibleQuery = widget.controller.state.query;
      _watchedIds = const [];
      _syncWatchedRows();
    } else if (oldWidget.source != widget.source) {
      _watchedIds = const [];
      _syncWatchedRows();
    }
  }

  void _onPagerChanged() {
    final query = widget.controller.state.query;
    if (!identical(query, _visibleQuery)) {
      _visibleQuery = query;
      widget.controller.setAtTop(true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    }
    _syncWatchedRows();
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    widget.controller.setAtTop(_scrollController.offset <= 0.5);
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
    _watchedRowsSubscription = widget.source.watchByIds(ids.toSet()).listen((
      rows,
    ) {
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
    });
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

  Future<void> _acceptNewer() async {
    widget.controller.setAtTop(true);
    if (_scrollController.hasClients) {
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
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
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
    return LayoutBuilder(
      key: widget.contentKey,
      builder: (context, constraints) => AnimatedSwitcher(
        key: const Key('capture-page-switcher'),
        duration: AppMotion.durationOf(context, AppMotion.short4),
        child: Stack(
          key: const ValueKey('capture-page-surface'),
          children: [
            CustomScrollView(
              controller: _scrollController,
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
                          child: CircularProgressIndicator(strokeWidth: 2),
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
    final groupHeaderBuilder = widget.groupHeaderBuilder;
    if (groupKey == null || groupHeaderBuilder == null) {
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
    final groupHeaderExtent = _groupHeaderExtent(context);
    return [
      for (var groupIndex = 0; groupIndex < groups.length; groupIndex++)
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            padding.left,
            groupIndex == 0 ? padding.top : 0,
            padding.right,
            groupIndex == groups.length - 1 ? padding.bottom : 12,
          ),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _CaptureGroupHeaderDelegate(
                  child: groupHeaderBuilder(context, groups[groupIndex].key),
                  extent: groupHeaderExtent,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.only(top: 8),
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
            ],
          ),
        ),
    ];
  }

  double _groupHeaderExtent(BuildContext context) {
    final style =
        (Theme.of(context).textTheme.titleSmall ??
                DefaultTextStyle.of(context).style)
            .copyWith(fontWeight: FontWeight.w600);
    final painter = TextPainter(
      text: TextSpan(text: '0000-00-00', style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final extent = painter.height + 16;
    painter.dispose();
    return extent;
  }

  Widget _buildRow(BuildContext context, CapturePagerState state, int index) {
    _scheduleLoadMore(index, state);
    return widget.itemBuilder(context, state.rows[index], state.rows);
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

class _CaptureGroupHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _CaptureGroupHeaderDelegate({
    required this.child,
    required this.extent,
  });

  final Widget child;
  final double extent;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => child;

  @override
  bool shouldRebuild(covariant _CaptureGroupHeaderDelegate oldDelegate) =>
      oldDelegate.child != child || oldDelegate.extent != extent;
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
