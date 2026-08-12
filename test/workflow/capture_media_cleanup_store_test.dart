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

  test('rejects a marker whose payload does not match its filename', () async {
    await store.write(
      const PendingCaptureMediaCleanup(
        captureId: 'capture-1',
        kind: CaptureMediaCleanupKind.clearOriginal,
        paths: ['/private/original.jpg'],
      ),
    );
    final directory = Directory('${root.path}/capture-media-cleanup');
    final marker = await directory.list().where((entry) => entry is File).first;
    await File(marker.path).writeAsString(
      '{"captureId":"capture-2","kind":"clearOriginal","paths":[]}',
    );

    await expectLater(store.list(), throwsFormatException);
  });
}
