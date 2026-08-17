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
}
