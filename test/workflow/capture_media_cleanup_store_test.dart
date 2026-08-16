import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/workflow/capture_media_cleanup_store.dart';

void main() {
  late Directory root;
  late AppCaptureMediaCleanupPendingStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('capture-media-cleanup-test-');
    store = AppCaptureMediaCleanupPendingStore(
      documentsDirectory: () async => root,
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'round-trips IDs losslessly and clears only the selected kind',
    () async {
      const captureId = '东区/record:1';
      await store.write(
        const PendingCaptureMediaCleanup(
          captureId: captureId,
          kind: CaptureMediaCleanupKind.clearOriginal,
          paths: ['/private/original.jpg'],
        ),
      );
      await store.write(
        const PendingCaptureMediaCleanup(
          captureId: captureId,
          kind: CaptureMediaCleanupKind.deleteCapture,
          paths: ['/private/original.jpg', '/private/rendered.jpg'],
          publishedUri: 'content://media/site-mark/1',
        ),
      );

      expect(await store.list(), hasLength(2));
      await store.clear(captureId, CaptureMediaCleanupKind.clearOriginal);

      final remaining = await store.list();
      expect(remaining, hasLength(1));
      expect(remaining.single.captureId, captureId);
      expect(remaining.single.kind, CaptureMediaCleanupKind.deleteCapture);
      expect(remaining.single.publishedUri, 'content://media/site-mark/1');
    },
  );

  test('round-trips a delete-superseded marker across restarts', () async {
    const captureId = 'capture-superseded';
    await store.write(
      const PendingCaptureMediaCleanup(
        captureId: captureId,
        kind: CaptureMediaCleanupKind.deleteSuperseded,
        paths: [],
        publishedUri: 'content://media/site-mark/1',
      ),
    );

    // A fresh store instance simulates the next launch reading the marker.
    final restored = AppCaptureMediaCleanupPendingStore(
      documentsDirectory: () async => root,
    );
    final remaining = await restored.list();
    expect(remaining, hasLength(1));
    expect(remaining.single.captureId, captureId);
    expect(remaining.single.kind, CaptureMediaCleanupKind.deleteSuperseded);
    expect(remaining.single.publishedUri, 'content://media/site-mark/1');
    expect(remaining.single.paths, isEmpty);

    await restored.clear(captureId, CaptureMediaCleanupKind.deleteSuperseded);
    expect(await restored.list(), isEmpty);
  });

  test('skips corrupt and identity-mismatch markers and continues', () async {
    await store.write(
      const PendingCaptureMediaCleanup(
        captureId: 'capture-mismatch',
        kind: CaptureMediaCleanupKind.clearOriginal,
        paths: ['/private/original.jpg'],
      ),
    );
    await store.write(
      const PendingCaptureMediaCleanup(
        captureId: 'capture-corrupt',
        kind: CaptureMediaCleanupKind.clearOriginal,
        paths: ['/private/corrupt.jpg'],
      ),
    );
    await store.write(
      const PendingCaptureMediaCleanup(
        captureId: 'capture-good',
        kind: CaptureMediaCleanupKind.deleteCapture,
        paths: ['/private/original.jpg', '/private/rendered.jpg'],
        publishedUri: 'content://media/site-mark/1',
      ),
    );
    final directory = Directory('${root.path}/capture-media-cleanup');
    final clearOriginalFiles = await directory
        .list()
        .where((entry) => entry is File)
        .cast<File>()
        .where((file) => file.uri.pathSegments.last.contains('clear-original'))
        .toList();
    expect(clearOriginalFiles, hasLength(2));
    await clearOriginalFiles[0].writeAsString(
      '{"captureId":"capture-2","kind":"clearOriginal","paths":[]}',
    );
    await clearOriginalFiles[1].writeAsString('not-json');

    final remaining = await store.list();
    expect(remaining, hasLength(1));
    expect(remaining.single.captureId, 'capture-good');
    expect(remaining.single.kind, CaptureMediaCleanupKind.deleteCapture);
  });
}
