import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark_system_api/src/ohos/capture_session_store.dart';

void main() {
  test('recover returns the durable session and clear is idempotent', () async {
    final prefs = MemoryKeyValueStore();
    final store = CaptureSessionStore(prefs);
    await store.write(captureId: 'capture-1', outputPath: '/docs/originals/capture-1.jpg');

    final first = await store.recover();
    expect(first!.captureId, 'capture-1');
    expect(first.outputPath, '/docs/originals/capture-1.jpg');

    await store.clear();
    expect(await store.recover(), isNull);
    await store.clear();
  });

  test('write replaces the previous unfinished session', () async {
    final store = CaptureSessionStore(MemoryKeyValueStore());
    await store.write(captureId: 'old', outputPath: '/old.jpg');
    await store.write(captureId: 'new', outputPath: '/new.jpg');
    expect((await store.recover())!.captureId, 'new');
  });

  test('recover reports empty on-disk target as no content', () async {
    final directory = await Directory.systemTemp.createTemp('sitemark-empty-');
    addTearDown(() => directory.delete(recursive: true));
    final empty = File('${directory.path}/empty.jpg')..createSync();
    final filled = File('${directory.path}/filled.jpg')
      ..writeAsBytesSync(const <int>[1, 2, 3]);

    final store = CaptureSessionStore(MemoryKeyValueStore());
    await store.write(captureId: 'empty', outputPath: empty.path);
    expect((await store.recover())!.hasContent, isFalse);

    await store.write(captureId: 'filled', outputPath: filled.path);
    expect((await store.recover())!.hasContent, isTrue);
  });
}
