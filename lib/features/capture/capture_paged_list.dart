import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/data/capture_query_repository.dart';
import 'package:sitemark/domain/capture_list_query.dart';
import 'package:sitemark/features/capture/capture_pager_controller.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';
import 'package:skeletonizer/skeletonizer.dart';

typedef CapturePagedItemBuilder =
    Widget Function(
      BuildContext context,
      CaptureSummary summary,
      List<CaptureSummary> visibleRows,
    );

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
    this.skeletonItemCount = 6,
  });

  final CapturePagerController controller;
  final CaptureQuerySource source;
  final String emptyMessage;
  final CapturePagedItemBuilder itemBuilder;
  final List<Widget> sliversBefore;
  final EdgeInsetsGeometry padding;
  final Key skeletonKey;
  final Key contentKey;
  final int skeletonItemCount;

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
      widget.controller.replaceWatchedRows(rows);
    });
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
    final child = state.initialLoading && state.rows.isEmpty
        ? _buildSkeleton()
        : state.initialError != null && state.rows.isEmpty
        ? _buildInitialError()
        : _buildContent(state);
    return AnimatedSwitcher(
      key: const Key('capture-page-switcher'),
      duration: AppMotion.durationOf(context, AppMotion.short4),
      child: child,
    );
  }

  Widget _buildSkeleton() {
    return Skeletonizer(
      key: widget.skeletonKey,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          ...widget.sliversBefore,
          SliverPadding(
            padding: widget.padding,
            sliver: SliverList.separated(
              itemCount: widget.skeletonItemCount,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, _) => const _CaptureCardSkeleton(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialError() {
    final strings = AppStrings.of(context);
    return CustomScrollView(
      key: const Key('capture-initial-error'),
      controller: _scrollController,
      slivers: [
        ...widget.sliversBefore,
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    strings.captureListLoadFailed,
                    textAlign: TextAlign.center,
                  ),
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
        ),
      ],
    );
  }

  Widget _buildContent(CapturePagerState state) {
    final strings = AppStrings.of(context);
    return Stack(
      key: widget.contentKey,
      children: [
        CustomScrollView(
          controller: _scrollController,
          slivers: [
            ...widget.sliversBefore,
            if (state.rows.isEmpty)
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
            else
              SliverPadding(
                padding: widget.padding,
                sliver: SliverList.separated(
                  itemCount: state.rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    _scheduleLoadMore(index, state);
                    return widget.itemBuilder(
                      context,
                      state.rows[index],
                      state.rows,
                    );
                  },
                ),
              ),
            if (state.loadingMore)
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
            else if (state.nextPageError != null)
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
        if (state.hasNewer)
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
