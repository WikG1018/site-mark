import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/data/capture_query_repository.dart';
import 'package:sitemark/domain/capture_list_query.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/features/capture/capture_pager_controller.dart';

CaptureSummary _summary(String id, {int minute = 0, String? projectName}) {
  final capturedAt = DateTime(2026, 1, 1).add(Duration(minutes: minute));
  return CaptureSummary(
    capture: CaptureRecord(
      id: id,
      projectId: 'project-1',
      workLocation: 'A 区',
      workContent: '风管',
      photographer: '张工',
      originalPath: '/private/$id.jpg',
      status: CaptureStatus.ready,
      createdAt: capturedAt,
      capturedAt: capturedAt,
      processingAttempts: 0,
      watermarkLocaleCode: 'zh',
      locationResolution: 'resolved',
    ),
    projectName: projectName ?? '项目',
  );
}

CapturePage _page(List<CaptureSummary> rows, {required bool hasMore}) =>
    CapturePage(
      rows: rows,
      nextCursor: rows.isEmpty
          ? null
          : (
              sortTime:
                  rows.last.capture.capturedAt ?? rows.last.capture.createdAt,
              id: rows.last.capture.id,
            ),
      hasMore: hasMore,
    );

CapturePageCursor _cursor(CaptureSummary row) => (
  sortTime: row.capture.capturedAt ?? row.capture.createdAt,
  id: row.capture.id,
);

void main() {
  test('drops an older response after query changes', () async {
    final source = _ControlledCaptureQuerySource();
    addTearDown(source.dispose);
    final controller = CapturePagerController(source);
    addTearDown(controller.dispose);

    final old = controller.setQuery(const CaptureListQuery(searchText: '旧'));
    final fresh = controller.setQuery(const CaptureListQuery(searchText: '新'));
    source.completePage('新', _page([_summary('new')], hasMore: false));
    await fresh;
    source.completePage('旧', _page([_summary('old')], hasMore: false));
    await old;

    expect(controller.state.rows.single.capture.id, 'new');
  });

  test('page display does not wait for the independent count', () async {
    final source = _ControlledCaptureQuerySource(deferCounts: true);
    addTearDown(source.dispose);
    final controller = CapturePagerController(source);
    addTearDown(controller.dispose);

    final loading = controller.setQuery(
      const CaptureListQuery(searchText: 'q'),
    );
    source.completePage('q', _page([_summary('row')], hasMore: false));
    await loading;

    expect(controller.state.rows.single.capture.id, 'row');
    expect(controller.state.totalCount, isNull);
    source.completeCount('q', 7);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.totalCount, 7);
  });

  test('loadMore appends a de-duplicated next page in order', () async {
    final source = _ControlledCaptureQuerySource();
    addTearDown(source.dispose);
    final controller = CapturePagerController(source);
    addTearDown(controller.dispose);
    final first = controller.setQuery(const CaptureListQuery(searchText: 'q'));
    source.completePage(
      'q',
      _page([_summary('a'), _summary('b', minute: 1)], hasMore: true),
    );
    await first;

    final next = controller.loadMore();
    source.completePage(
      'q',
      _page([
        _summary('b', minute: 1),
        _summary('c', minute: 2),
      ], hasMore: false),
      afterId: 'b',
    );
    await next;

    expect(controller.state.rows.map((row) => row.capture.id), ['a', 'b', 'c']);
    expect(controller.state.hasMore, isFalse);
  });

  test('loadMore ignores a duplicate concurrent request', () async {
    final source = _ControlledCaptureQuerySource();
    addTearDown(source.dispose);
    final controller = CapturePagerController(source);
    addTearDown(controller.dispose);
    final first = controller.setQuery(const CaptureListQuery(searchText: 'q'));
    source.completePage('q', _page([_summary('a')], hasMore: true));
    await first;

    final firstMore = controller.loadMore();
    final secondMore = controller.loadMore();

    expect(source.pageRequestCount, 2);
    source.completePage(
      'q',
      _page([_summary('b', minute: 1)], hasMore: false),
      afterId: 'a',
    );
    await Future.wait([firstMore, secondMore]);
  });

  test('a failed next page preserves rows and can be retried', () async {
    final source = _ControlledCaptureQuerySource();
    addTearDown(source.dispose);
    final controller = CapturePagerController(source);
    addTearDown(controller.dispose);
    final first = controller.setQuery(const CaptureListQuery(searchText: 'q'));
    source.completePage('q', _page([_summary('a')], hasMore: true));
    await first;

    final failed = controller.loadMore();
    source.failPage('q', StateError('next page failed'), afterId: 'a');
    await failed;
    expect(controller.state.rows.map((row) => row.capture.id), ['a']);
    expect(controller.state.nextPageError, isA<StateError>());

    final retry = controller.loadMore();
    source.completePage(
      'q',
      _page([_summary('b', minute: 1)], hasMore: false),
      afterId: 'a',
    );
    await retry;
    expect(controller.state.rows.map((row) => row.capture.id), ['a', 'b']);
    expect(controller.state.nextPageError, isNull);
  });

  test('refresh blocks pagination against the old first-page cursor', () async {
    final source = _ControlledCaptureQuerySource();
    addTearDown(source.dispose);
    final controller = CapturePagerController(source);
    addTearDown(controller.dispose);
    final first = controller.setQuery(const CaptureListQuery(searchText: 'q'));
    source.completePage('q', _page([_summary('old')], hasMore: true));
    await first;

    final refresh = controller.refresh();
    final ignoredMore = controller.loadMore();
    expect(controller.state.initialLoading, isTrue);
    expect(source.pageRequestCount, 2);

    source.completePage(
      'q',
      _page([_summary('new', minute: 1)], hasMore: true),
    );
    await Future.wait([refresh, ignoredMore]);
    final next = controller.loadMore();
    expect(source.pageRequestCount, 3);
    source.completePage(
      'q',
      _page([_summary('later', minute: 2)], hasMore: false),
      afterId: 'new',
    );
    await next;
    expect(controller.state.rows.map((row) => row.capture.id), [
      'new',
      'later',
    ]);
  });

  test(
    'an empty first page refreshes when a newer cursor arrives at the top',
    () async {
      final source = _ControlledCaptureQuerySource();
      addTearDown(source.dispose);
      final controller = CapturePagerController(source);
      addTearDown(controller.dispose);
      final first = controller.setQuery(
        const CaptureListQuery(searchText: 'q'),
      );
      source.completePage('q', _page([], hasMore: false));
      await first;

      source.emitNewest('q', _cursor(_summary('new', minute: 1)));
      await Future<void>.delayed(Duration.zero);
      expect(source.pageRequestCount, 2);
      source.completePage(
        'q',
        _page([_summary('new', minute: 1)], hasMore: false),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.rows.single.capture.id, 'new');
    },
  );

  test('a replayed newest cursor starts only one at-top refresh', () async {
    final source = _ControlledCaptureQuerySource(
      replayNewestOnListen: true,
      maxNewestReplays: 1,
    );
    addTearDown(source.dispose);
    final controller = CapturePagerController(source);
    addTearDown(controller.dispose);
    final first = controller.setQuery(const CaptureListQuery(searchText: 'q'));
    final old = _summary('old', minute: 1);
    source.completePage('q', _page([old], hasMore: false));
    await first;
    source.emitNewest('q', _cursor(old));

    final newest = _summary('new', minute: 2);
    source.emitNewest('q', _cursor(newest));
    await Future<void>.delayed(Duration.zero);
    expect(source.pageRequestCount, 2);

    source.emitNewest('q', _cursor(newest));
    await Future<void>.delayed(Duration.zero);
    expect(source.pageRequestCount, 2);

    source.completePage('q', _page([newest], hasMore: false));
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.rows.single.capture.id, 'new');

    source.emitNewest('q', _cursor(newest));
    await Future<void>.delayed(Duration.zero);
    expect(source.pageRequestCount, 2);
  });

  test('a newer cursor at the top refreshes the first page', () async {
    final source = _ControlledCaptureQuerySource();
    addTearDown(source.dispose);
    final controller = CapturePagerController(source);
    addTearDown(controller.dispose);
    final first = controller.setQuery(const CaptureListQuery(searchText: 'q'));
    final old = _summary('old', minute: 1);
    source.completePage('q', _page([old], hasMore: false));
    await first;
    source.emitNewest('q', _cursor(old));

    source.emitNewest('q', _cursor(_summary('new', minute: 2)));
    await Future<void>.delayed(Duration.zero);
    source.completePage(
      'q',
      _page([_summary('new', minute: 2)], hasMore: false),
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.rows.single.capture.id, 'new');
    expect(controller.state.hasNewer, isFalse);

    source.emitNewest('q', _cursor(_summary('newest', minute: 3)));
    await Future<void>.delayed(Duration.zero);
    expect(source.pageRequestCount, 3);
    source.completePage(
      'q',
      _page([_summary('newest', minute: 3)], hasMore: false),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.rows.single.capture.id, 'newest');
  });

  test('a newer cursor while scrolled marks hasNewer until accepted', () async {
    final source = _ControlledCaptureQuerySource();
    addTearDown(source.dispose);
    final controller = CapturePagerController(source);
    addTearDown(controller.dispose);
    final first = controller.setQuery(const CaptureListQuery(searchText: 'q'));
    final old = _summary('old', minute: 1);
    source.completePage('q', _page([old], hasMore: false));
    await first;
    source.emitNewest('q', _cursor(old));
    controller.setAtTop(false);

    source.emitNewest('q', _cursor(_summary('new', minute: 2)));
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.hasNewer, isTrue);
    expect(source.pageRequestCount, 1);

    final accepted = controller.acceptNewer();
    source.completePage(
      'q',
      _page([_summary('new', minute: 2)], hasMore: false),
    );
    await accepted;
    expect(controller.state.rows.single.capture.id, 'new');
    expect(controller.state.hasNewer, isFalse);
  });

  test(
    'watched rows replace in place without reordering or duplicates',
    () async {
      final source = _ControlledCaptureQuerySource();
      addTearDown(source.dispose);
      final controller = CapturePagerController(source);
      addTearDown(controller.dispose);
      final first = controller.setQuery(
        const CaptureListQuery(searchText: 'q'),
      );
      source.completePage(
        'q',
        _page([_summary('a'), _summary('b', minute: 1)], hasMore: false),
      );
      await first;

      controller.replaceWatchedRows([
        _summary('b', minute: 1, projectName: '第一次更新'),
        _summary('b', minute: 1, projectName: '第二次更新'),
      ]);

      expect(controller.state.rows.map((row) => row.capture.id), ['a', 'b']);
      expect(controller.state.rows.last.projectName, '第二次更新');
    },
  );

  test(
    'disposing prevents later async results from notifying listeners',
    () async {
      final source = _ControlledCaptureQuerySource();
      addTearDown(source.dispose);
      final controller = CapturePagerController(source);
      var notifications = 0;
      controller.addListener(() => notifications++);

      final loading = controller.setQuery(
        const CaptureListQuery(searchText: 'q'),
      );
      notifications = 0;
      controller.dispose();
      source.completePage('q', _page([_summary('late')], hasMore: false));
      await loading;

      expect(notifications, 0);
    },
  );

  test('a newest-cursor stream error triggers a refresh', () async {
    final source = _ControlledCaptureQuerySource();
    addTearDown(source.dispose);
    final controller = CapturePagerController(source);
    addTearDown(controller.dispose);

    final first = controller.setQuery(const CaptureListQuery(searchText: 'q'));
    source.completePage('q', _page([_summary('row')], hasMore: false));
    await first;
    expect(source.pageRequestCount, 1);

    source.failNewest('q', StateError('watch failed'));
    await Future<void>.delayed(Duration.zero);
    expect(source.pageRequestCount, 2);

    source.completePage('q', _page([_summary('refreshed')], hasMore: false));
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.rows.single.capture.id, 'refreshed');
  });
}

final class _ControlledCaptureQuerySource implements CaptureQuerySource {
  _ControlledCaptureQuerySource({
    this.deferCounts = false,
    this.replayNewestOnListen = false,
    this.maxNewestReplays = 0,
  });

  final bool deferCounts;
  final bool replayNewestOnListen;
  final int maxNewestReplays;
  final List<_PageRequest> _pageRequests = [];
  final List<_CountRequest> _countRequests = [];
  final Map<String, StreamController<CapturePageCursor?>> _newestControllers =
      {};
  final Map<String, CapturePageCursor?> _newestValues = {};
  int _newestReplayCount = 0;

  int get pageRequestCount => _pageRequests.length;

  @override
  Future<CapturePage> loadPage(
    CaptureListQuery query, {
    CapturePageCursor? after,
    int limit = 50,
  }) {
    final request = _PageRequest(query, after);
    _pageRequests.add(request);
    return request.completer.future;
  }

  @override
  Future<int> count(CaptureListQuery query) {
    if (!deferCounts) return Future.value(0);
    final request = _CountRequest(query);
    _countRequests.add(request);
    return request.completer.future;
  }

  @override
  Stream<CapturePageCursor?> watchNewestCursor(CaptureListQuery query) {
    final searchText = query.searchText;
    final source = _newestControllers
        .putIfAbsent(
          searchText,
          () => StreamController<CapturePageCursor?>.broadcast(),
        )
        .stream;
    if (!replayNewestOnListen) return source;
    return Stream.multi((listener) {
      final subscription = source.listen(
        listener.addSync,
        onError: listener.addErrorSync,
        onDone: listener.closeSync,
      );
      listener.onCancel = subscription.cancel;
      final current = _newestValues[searchText];
      if (current != null && _newestReplayCount < maxNewestReplays) {
        _newestReplayCount++;
        listener.addSync(current);
      }
    }, isBroadcast: true);
  }

  void completePage(String searchText, CapturePage page, {String? afterId}) {
    _pageRequest(searchText, afterId).completer.complete(page);
  }

  void failPage(String searchText, Object error, {String? afterId}) {
    _pageRequest(searchText, afterId).completer.completeError(error);
  }

  void completeCount(String searchText, int count) {
    _countRequests
        .firstWhere(
          (request) =>
              request.query.searchText == searchText &&
              !request.completer.isCompleted,
        )
        .completer
        .complete(count);
  }

  void emitNewest(String searchText, CapturePageCursor? cursor) {
    _newestValues[searchText] = cursor;
    _newestControllers[searchText]?.add(cursor);
  }

  void failNewest(String searchText, Object error) {
    _newestControllers[searchText]?.addError(error);
  }

  _PageRequest _pageRequest(String searchText, String? afterId) =>
      _pageRequests.firstWhere(
        (request) =>
            request.query.searchText == searchText &&
            request.after?.id == afterId &&
            !request.completer.isCompleted,
      );

  Future<void> dispose() async {
    await Future.wait(
      _newestControllers.values.map((controller) => controller.close()),
    );
  }

  @override
  Future<CaptureDateOptions> loadDateOptions(CaptureListQuery query) =>
      throw UnimplementedError();

  @override
  Future<CaptureSelectionSnapshot> loadSelectable(CaptureListQuery query) =>
      throw UnimplementedError();

  @override
  Future<CaptureSelectionSnapshot> inspectSelection(Set<String> ids) =>
      throw UnimplementedError();

  @override
  Future<List<CaptureSummary>> loadAdjacent(
    CaptureListQuery query,
    CapturePageCursor cursor, {
    required bool newer,
    int limit = 10,
  }) => throw UnimplementedError();

  @override
  Stream<List<CaptureSummary>> watchByIds(Set<String> ids) =>
      throw UnimplementedError();
}

final class _PageRequest {
  _PageRequest(this.query, this.after);

  final CaptureListQuery query;
  final CapturePageCursor? after;
  final Completer<CapturePage> completer = Completer<CapturePage>();
}

final class _CountRequest {
  _CountRequest(this.query);

  final CaptureListQuery query;
  final Completer<int> completer = Completer<int>();
}
