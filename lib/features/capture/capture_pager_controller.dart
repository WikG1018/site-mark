import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/data/capture_query_repository.dart';
import 'package:sitemark/domain/capture_list_query.dart';

/// Immutable visible state for a paged capture query.
final class CapturePagerState {
  CapturePagerState({
    required this.query,
    List<CaptureSummary> rows = const [],
    this.initialLoading = false,
    this.loadingMore = false,
    this.hasMore = true,
    this.hasNewer = false,
    this.totalCount,
    this.initialError,
    this.nextPageError,
  }) : rows = List.unmodifiable(rows);

  final CaptureListQuery query;
  final List<CaptureSummary> rows;
  final bool initialLoading;
  final bool loadingMore;
  final bool hasMore;
  final bool hasNewer;
  final int? totalCount;
  final Object? initialError;
  final Object? nextPageError;

  CapturePagerState copyWith({
    CaptureListQuery? query,
    List<CaptureSummary>? rows,
    bool? initialLoading,
    bool? loadingMore,
    bool? hasMore,
    bool? hasNewer,
    Object? totalCount = _unset,
    Object? initialError = _unset,
    Object? nextPageError = _unset,
  }) => CapturePagerState(
    query: query ?? this.query,
    rows: rows ?? this.rows,
    initialLoading: initialLoading ?? this.initialLoading,
    loadingMore: loadingMore ?? this.loadingMore,
    hasMore: hasMore ?? this.hasMore,
    hasNewer: hasNewer ?? this.hasNewer,
    totalCount: identical(totalCount, _unset)
        ? this.totalCount
        : totalCount as int?,
    initialError: identical(initialError, _unset)
        ? this.initialError
        : initialError,
    nextPageError: identical(nextPageError, _unset)
        ? this.nextPageError
        : nextPageError,
  );
}

const _unset = Object();

/// Owns one capture-list query, its cursor, and stale-result protection.
///
/// The host owns scrolling and any watched-row subscription, then forwards
/// those events through [setAtTop] and [replaceWatchedRows].
final class CapturePagerController extends ChangeNotifier {
  CapturePagerController(this._source, {this.pageSize = 50})
    : _state = CapturePagerState(query: const CaptureListQuery());

  final CaptureQuerySource _source;
  final int pageSize;

  CapturePagerState _state;
  CapturePagerState get state => _state;

  int _generation = 0;
  bool _disposed = false;
  bool _atTop = true;
  CapturePageCursor? _nextCursor;
  CapturePageCursor? _newestCursor;
  CapturePageCursor? _observedNewestCursor;
  StreamSubscription<CapturePageCursor?>? _newestSubscription;
  CaptureListQuery? _watchedQuery;

  /// Replaces the active query. Results started by any earlier generation are
  /// ignored when they eventually settle.
  Future<void> setQuery(CaptureListQuery query) {
    if (_disposed) return Future.value();
    final generation = ++_generation;
    _nextCursor = null;
    _newestCursor = null;
    _observedNewestCursor = null;
    _state = CapturePagerState(query: query, initialLoading: true);
    _emit();
    _watchNewestCursor(query);
    unawaited(_loadCount(query, generation));
    return _loadFirstPage(query, generation, replaceRows: true);
  }

  /// Reloads the first page while retaining displayed rows until it arrives.
  Future<void> refresh() {
    if (_disposed) return Future.value();
    final generation = ++_generation;
    final query = _state.query;
    _state = _state.copyWith(
      initialLoading: true,
      loadingMore: false,
      hasNewer: false,
      initialError: null,
      nextPageError: null,
    );
    _emit();
    _watchNewestCursor(query);
    unawaited(_loadCount(query, generation));
    return _loadFirstPage(query, generation, replaceRows: true);
  }

  /// Requests the next cursor exactly once while a request is in flight.
  Future<void> loadMore() async {
    if (_disposed ||
        _state.initialLoading ||
        _state.loadingMore ||
        !_state.hasMore ||
        _nextCursor == null) {
      return;
    }
    final generation = _generation;
    final query = _state.query;
    final after = _nextCursor!;
    _state = _state.copyWith(loadingMore: true, nextPageError: null);
    _emit();
    try {
      final page = await _source.loadPage(query, after: after, limit: pageSize);
      if (!_isCurrent(generation)) return;
      _nextCursor = page.nextCursor;
      _state = _state.copyWith(
        rows: _mergeRows(_state.rows, page.rows),
        loadingMore: false,
        hasMore: page.hasMore,
        nextPageError: null,
      );
      _emit();
    } catch (error) {
      if (!_isCurrent(generation)) return;
      _state = _state.copyWith(loadingMore: false, nextPageError: error);
      _emit();
    }
  }

  /// Updates whether the visible list is scrolled to its newest edge.
  void setAtTop(bool atTop) {
    if (_disposed) return;
    _atTop = atTop;
  }

  /// Accepts the pending newer-items indication by refreshing page one.
  Future<void> acceptNewer() {
    if (_disposed || !_state.hasNewer) return Future.value();
    return refresh();
  }

  /// Replaces only already-visible watched rows, preserving list order.
  void replaceWatchedRows(Iterable<CaptureSummary> watchedRows) {
    if (_disposed || _state.rows.isEmpty) return;
    final replacements = <String, CaptureSummary>{
      for (final row in watchedRows) row.capture.id: row,
    };
    if (replacements.isEmpty) return;
    final rows = _state.rows
        .map((row) => replacements[row.capture.id] ?? row)
        .toList(growable: false);
    _state = _state.copyWith(rows: rows);
    _emit();
  }

  void _watchNewestCursor(CaptureListQuery query) {
    if (identical(_watchedQuery, query) && _newestSubscription != null) {
      return;
    }
    final previous = _newestSubscription;
    _watchedQuery = null;
    _newestSubscription = null;
    if (previous != null) unawaited(previous.cancel());
    _watchedQuery = query;
    _newestSubscription = _source
        .watchNewestCursor(query)
        .listen(
          (cursor) {
            if (_disposed || !identical(_watchedQuery, query)) return;
            _handleNewestCursor(cursor);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (_disposed || !identical(_watchedQuery, query)) return;
            // A transient stream error should not silently break the real-time feed;
            // trigger a full refresh so the next load either surfaces the error via
            // the existing _state.initialError/nextPageError path or succeeds.
            unawaited(refresh());
          },
        );
  }

  void _handleNewestCursor(CapturePageCursor? cursor) {
    if (_disposed || cursor == null) return;
    _observedNewestCursor = cursor;
    if (_state.initialLoading) return;
    final current = _newestCursor;
    if (current == null) {
      if (_atTop) {
        _observedNewestCursor = null;
        unawaited(refresh());
      } else if (!_state.hasNewer) {
        _state = _state.copyWith(hasNewer: true);
        _emit();
      }
      return;
    }
    if (!_isNewer(cursor, current)) return;
    if (_atTop) {
      unawaited(refresh());
      return;
    }
    if (!_state.hasNewer) {
      _state = _state.copyWith(hasNewer: true);
      _emit();
    }
  }

  Future<void> _loadFirstPage(
    CaptureListQuery query,
    int generation, {
    required bool replaceRows,
  }) async {
    try {
      final page = await _source.loadPage(query, limit: pageSize);
      if (!_isCurrent(generation)) return;
      _nextCursor = page.nextCursor;
      final rows = replaceRows ? _mergeRows(const [], page.rows) : page.rows;
      _state = _state.copyWith(
        rows: rows,
        initialLoading: false,
        loadingMore: false,
        hasMore: page.hasMore,
        hasNewer: false,
        initialError: null,
        nextPageError: null,
      );
      _newestCursor = rows.isEmpty ? null : _cursorFor(rows.first);
      _emit();
      final observed = _observedNewestCursor;
      if (observed != null &&
          (_newestCursor == null || _isNewer(observed, _newestCursor!))) {
        _handleNewestCursor(observed);
      }
    } catch (error) {
      if (!_isCurrent(generation)) return;
      _state = _state.copyWith(initialLoading: false, initialError: error);
      _emit();
    }
  }

  Future<void> _loadCount(CaptureListQuery query, int generation) async {
    try {
      final total = await _source.count(query);
      if (!_isCurrent(generation)) return;
      _state = _state.copyWith(totalCount: total);
      _emit();
    } catch (_) {
      // A count is supporting metadata: page display remains usable without it.
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  bool _isNewer(CapturePageCursor candidate, CapturePageCursor current) {
    final byTime = candidate.sortTime.compareTo(current.sortTime);
    return byTime > 0 ||
        (byTime == 0 && candidate.id.compareTo(current.id) > 0);
  }

  CapturePageCursor _cursorFor(CaptureSummary row) => (
    sortTime: row.capture.capturedAt ?? row.capture.createdAt,
    id: row.capture.id,
  );

  List<CaptureSummary> _mergeRows(
    Iterable<CaptureSummary> first,
    Iterable<CaptureSummary> second,
  ) => List.unmodifiable(
    LinkedHashMap<String, CaptureSummary>.fromEntries([
      for (final row in first) MapEntry(row.capture.id, row),
      for (final row in second) MapEntry(row.capture.id, row),
    ]).values,
  );

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    final subscription = _newestSubscription;
    _newestSubscription = null;
    _watchedQuery = null;
    if (subscription != null) unawaited(subscription.cancel());
    super.dispose();
  }
}
