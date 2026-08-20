import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark_system_api/src/ohos/publish_journal_store.dart';

void main() {
  test('record recover round-trips captureId not photo number', () {
    final store = HarmonyPublishJournalStore(MemoryKeyValueStore());
    expect(
      store.record(
        captureId: 'capture-1',
        contentUri: 'ph://new',
        supersededUris: ['ph://old'],
      ),
      isTrue,
    );
    final entry = store.recover().single;
    expect(entry.captureId, 'capture-1');
    expect(entry.contentUri, 'ph://new');
    expect(entry.supersededUris, ['ph://old']);
  });

  test('clear is conditional on expectedContentUri', () {
    final store = HarmonyPublishJournalStore(MemoryKeyValueStore());
    store.record(
      captureId: 'c1',
      contentUri: 'ph://v2',
      supersededUris: ['ph://v1'],
    );
    expect(store.clear('c1', 'ph://v1'), isFalse);
    expect(store.recover().single.contentUri, 'ph://v2');
    expect(store.clear('c1', 'ph://v2'), isTrue);
    expect(store.recover(), isEmpty);
    expect(store.clear('c1', 'ph://v2'), isTrue);
  });

  test('same-capture record folds previous uri into later peek', () {
    final store = HarmonyPublishJournalStore(MemoryKeyValueStore());
    store.record(
      captureId: 'c1',
      contentUri: 'ph://v1',
      supersededUris: ['ph://v0'],
    );
    store.record(
      captureId: 'c1',
      contentUri: 'ph://v2',
      supersededUris: ['ph://v1', 'ph://v0'],
    );
    expect(store.peek('c1')!.contentUri, 'ph://v2');
    expect(store.peek('c1')!.supersededUris, ['ph://v1', 'ph://v0']);
  });

  test('hostile capture ids stay in a safe key alphabet', () {
    final prefs = MemoryKeyValueStore();
    final store = HarmonyPublishJournalStore(prefs);
    const hostile = 'cap\u0000.id.值📷';
    expect(
      store.record(
        captureId: hostile,
        contentUri: 'ph://x',
        supersededUris: const [],
      ),
      isTrue,
    );
    for (final key in prefs.keys) {
      expect(RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(key), isTrue);
    }
    expect(store.recover().single.captureId, hostile);
  });

  test('clearing one capture journal leaves the restored sibling', () {
    final store = HarmonyPublishJournalStore(MemoryKeyValueStore());
    expect(
      store.record(
        captureId: 'capture-1',
        contentUri: 'ph://orig',
        supersededUris: const [],
      ),
      isTrue,
    );
    expect(
      store.record(
        captureId: 'capture-2',
        contentUri: 'ph://restored',
        supersededUris: const [],
      ),
      isTrue,
    );

    expect(store.clear('capture-2', 'ph://restored'), isTrue);

    final remaining = store.recover().single;
    expect(remaining.captureId, 'capture-1');
    expect(remaining.contentUri, 'ph://orig');
    expect(store.peek('capture-2'), isNull);
  });
}
