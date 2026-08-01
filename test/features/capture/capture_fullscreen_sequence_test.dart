import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/features/capture/capture_fullscreen_sequence.dart';

CaptureFullscreenPhoto _photo(String id) =>
    CaptureFullscreenPhoto(id: id, resolvePath: () async => '/$id.jpg');

void main() {
  test('starts with only the current photo and loads older photos', () async {
    final sequence = CaptureFullscreenSequence(
      current: _photo('current'),
      loader: (direction, anchorId) async {
        expect(direction, CaptureFullscreenDirection.older);
        expect(anchorId, 'current');
        return [_photo('older-1')];
      },
    );

    expect(sequence.photos.map((photo) => photo.id), ['current']);
    await sequence.loadOlder();

    expect(sequence.photos.map((photo) => photo.id), ['current', 'older-1']);
    expect(sequence.currentId, 'current');
  });

  test('loads newer and older directions independently', () async {
    final calls = <(CaptureFullscreenDirection, String)>[];
    final sequence = CaptureFullscreenSequence(
      current: _photo('current'),
      loader: (direction, anchorId) async {
        calls.add((direction, anchorId));
        return switch (direction) {
          CaptureFullscreenDirection.newer => [_photo('newer-1')],
          CaptureFullscreenDirection.older => [_photo('older-1')],
        };
      },
    );

    await Future.wait([sequence.loadNewer(), sequence.loadOlder()]);

    expect(calls, contains((CaptureFullscreenDirection.newer, 'current')));
    expect(calls, contains((CaptureFullscreenDirection.older, 'current')));
    expect(sequence.photos.map((photo) => photo.id), [
      'newer-1',
      'current',
      'older-1',
    ]);
  });

  test('suppresses concurrent requests in the same direction', () async {
    final response = Completer<List<CaptureFullscreenPhoto>>();
    var calls = 0;
    final sequence = CaptureFullscreenSequence(
      current: _photo('current'),
      loader: (direction, anchorId) {
        calls++;
        return response.future;
      },
    );

    final first = sequence.loadOlder();
    final second = sequence.loadOlder();
    expect(calls, 1);
    response.complete([_photo('older-1')]);
    await Future.wait([first, second]);

    expect(sequence.photos.map((photo) => photo.id), ['current', 'older-1']);
  });

  test('deduplicates IDs returned across adjacent pages', () async {
    var call = 0;
    final sequence = CaptureFullscreenSequence(
      current: _photo('current'),
      loader: (direction, anchorId) async {
        call++;
        return call == 1
            ? [_photo('current'), _photo('older-1')]
            : [_photo('older-1'), _photo('older-2')];
      },
      pageSize: 2,
    );

    await sequence.loadOlder();
    await sequence.loadOlder();

    expect(sequence.photos.map((photo) => photo.id), [
      'current',
      'older-1',
      'older-2',
    ]);
  });

  test('short and empty pages mark only that direction as ended', () async {
    var newerCalls = 0;
    var olderCalls = 0;
    final sequence = CaptureFullscreenSequence(
      current: _photo('current'),
      loader: (direction, anchorId) async {
        if (direction == CaptureFullscreenDirection.newer) {
          newerCalls++;
          return const [];
        }
        olderCalls++;
        return [_photo('older-1')];
      },
      pageSize: 10,
    );

    await sequence.loadNewer();
    await sequence.loadNewer();
    await sequence.loadOlder();
    await sequence.loadOlder();

    expect(newerCalls, 1);
    expect(olderCalls, 1);
    expect(sequence.newerEnded, isTrue);
    expect(sequence.olderEnded, isTrue);
  });

  test('edge failure keeps photos and retries only that direction', () async {
    var attempts = 0;
    final sequence = CaptureFullscreenSequence(
      current: _photo('current'),
      loader: (direction, anchorId) async {
        attempts++;
        if (attempts == 1) throw StateError('temporary failure');
        return [_photo('older-1')];
      },
    );

    await sequence.loadOlder();
    expect(sequence.photos.map((photo) => photo.id), ['current']);
    expect(sequence.olderError, isA<StateError>());
    expect(sequence.newerError, isNull);

    await sequence.retryOlder();
    expect(sequence.olderError, isNull);
    expect(sequence.photos.map((photo) => photo.id), ['current', 'older-1']);
  });

  test('prepending newer photos preserves the selected current ID', () async {
    final sequence = CaptureFullscreenSequence(
      current: _photo('current'),
      loader: (direction, anchorId) async => [
        _photo('newer-2'),
        _photo('newer-1'),
      ],
    );

    await sequence.loadNewer();

    expect(sequence.photos.map((photo) => photo.id), [
      'newer-2',
      'newer-1',
      'current',
    ]);
    expect(sequence.currentId, 'current');
  });

  test('completion after dispose cannot mutate sequence state', () async {
    final response = Completer<List<CaptureFullscreenPhoto>>();
    final sequence = CaptureFullscreenSequence(
      current: _photo('current'),
      loader: (direction, anchorId) => response.future,
    );
    var notifications = 0;
    sequence.addListener(() => notifications++);

    final pending = sequence.loadOlder();
    sequence.dispose();
    final notificationsAtDispose = notifications;
    response.complete([_photo('older-1')]);
    await pending;

    expect(sequence.photos.map((photo) => photo.id), ['current']);
    expect(notifications, notificationsAtDispose);
  });

  test(
    'skipped rows advance the edge anchor without becoming visible',
    () async {
      final anchors = <String>[];
      var call = 0;
      final sequence = CaptureFullscreenSequence(
        current: _photo('current'),
        loader: (direction, anchorId) async {
          anchors.add(anchorId);
          call++;
          if (call == 1) {
            return [
              for (var index = 0; index < 10; index++)
                CaptureFullscreenPhoto(
                  id: 'deleted-$index',
                  includeInSequence: false,
                  resolvePath: () async => null,
                ),
            ];
          }
          return [_photo('older-1')];
        },
      );

      await sequence.loadOlder();
      expect(sequence.photos.map((photo) => photo.id), ['current']);
      expect(sequence.olderEnded, isFalse);

      await sequence.loadOlder();
      expect(anchors, ['current', 'deleted-9']);
      expect(sequence.photos.map((photo) => photo.id), ['current', 'older-1']);
    },
  );
}
