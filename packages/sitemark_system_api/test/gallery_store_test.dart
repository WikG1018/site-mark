import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark_system_api/src/ohos/gallery_access.dart';
import 'package:sitemark_system_api/src/ohos/gallery_store.dart';

void main() {
  test(
    'ACL publish reports only the passed publishedUri plus leftover journal',
    () async {
      final photos = MemoryPhotoAccess();
      final store = AclGalleryStore(photos);
      photos.seed('ph://old', bytes: [1]);
      final result = await store.publish(
        sourcePath: '/tmp/new.jpg',
        displayName: 'IMG-0001',
        captureId: 'c1',
        publishedUri: 'ph://old',
        leftoverJournalUris: ['ph://leftover'],
      );
      expect(result.contentUri, isNot('ph://old'));
      expect(result.supersededUris, containsAll(['ph://old', 'ph://leftover']));
      expect(result.enteredSystemAlbum, isTrue);
      expect(
        photos.exists('ph://old'),
        isTrue,
        reason: 'native must not delete',
      );
    },
  );

  test('ACL publish never scans by display name', () async {
    final photos = MemoryPhotoAccess();
    final store = AclGalleryStore(photos);
    photos.seed('ph://other', displayName: 'IMG-0001', bytes: [9]);
    final result = await store.publish(
      sourcePath: '/tmp/new.jpg',
      displayName: 'IMG-0001',
      captureId: 'c1',
      publishedUri: null,
      leftoverJournalUris: const [],
    );
    expect(result.supersededUris, isEmpty);
    expect(photos.exists('ph://other'), isTrue);
  });

  test('picker fallback does not claim system album parity', () async {
    final store = PickerFallbackStore(MemorySandbox());
    final result = await store.publish(
      sourcePath: '/tmp/new.jpg',
      displayName: 'IMG-0001',
      captureId: 'c1',
      publishedUri: null,
      leftoverJournalUris: const [],
    );
    expect(result.enteredSystemAlbum, isFalse);
    expect(result.contentUri, startsWith('file://'));
  });

  test('picker publish of same displayName is keyed by captureId', () async {
    final sandbox = MemorySandbox();
    final store = PickerFallbackStore(sandbox);
    const name = '东区厂房改造-SM-20260716-001';
    final first = await store.publish(
      sourcePath: '/tmp/a.jpg',
      displayName: name,
      captureId: 'capture-1',
    );
    final second = await store.publish(
      sourcePath: '/tmp/b.jpg',
      displayName: name,
      captureId: 'capture-2',
    );
    expect(first.contentUri, 'file:///sandbox/capture-1.jpg');
    expect(second.contentUri, 'file:///sandbox/capture-2.jpg');
    expect(first.supersededUris, isEmpty);
    expect(second.supersededUris, isEmpty);
    expect(sandbox.files.keys, [
      'file:///sandbox/capture-1.jpg',
      'file:///sandbox/capture-2.jpg',
    ]);
  });

  test(
    'ACL delete removes only the given URI, never the same displayName',
    () async {
      final photos = MemoryPhotoAccess();
      final store = AclGalleryStore(photos);
      photos.seed('ph://keep', displayName: 'IMG-0001', bytes: [1]);
      photos.seed('ph://drop', displayName: 'IMG-0001', bytes: [2]);
      await store.delete('ph://drop');
      expect(photos.exists('ph://drop'), isFalse);
      expect(photos.exists('ph://keep'), isTrue);
    },
  );

  test(
    'picker delete of one captureId leaves the sibling sandbox file',
    () async {
      final sandbox = MemorySandbox();
      final store = PickerFallbackStore(sandbox);
      const name = '东区厂房改造-SM-20260716-001';
      final first = await store.publish(
        sourcePath: '/tmp/a.jpg',
        displayName: name,
        captureId: 'capture-1',
      );
      final second = await store.publish(
        sourcePath: '/tmp/b.jpg',
        displayName: name,
        captureId: 'capture-2',
      );
      await store.delete(first.contentUri);
      expect(sandbox.files.containsKey(first.contentUri), isFalse);
      expect(sandbox.files.containsKey(second.contentUri), isTrue);
    },
  );

  test('picker-mode store still deletes an ACL URI by identity', () async {
    final photos = MemoryPhotoAccess();
    photos.seed('ph://published-1', bytes: [1]);
    photos.seed('ph://sibling', displayName: 'IMG-0001', bytes: [9]);
    final store = ProbingGalleryStore(
      probe: GalleryAccessProbe(reader: () async => false),
      acl: AclGalleryStore(photos),
      picker: PickerFallbackStore(MemorySandbox()),
    );
    await store.delete('ph://published-1');
    expect(photos.exists('ph://published-1'), isFalse);
    expect(photos.exists('ph://sibling'), isTrue);
  });

  test('acl-mode store still deletes a sandbox URI by identity', () async {
    final sandbox = MemorySandbox();
    sandbox.files['file:///sandbox/capture-1.jpg'] = '/tmp/a.jpg';
    sandbox.files['file:///sandbox/capture-2.jpg'] = '/tmp/b.jpg';
    final store = ProbingGalleryStore(
      probe: GalleryAccessProbe(reader: () async => true),
      acl: AclGalleryStore(MemoryPhotoAccess()),
      picker: PickerFallbackStore(sandbox),
    );
    await store.delete('file:///sandbox/capture-1.jpg');
    expect(sandbox.files.containsKey('file:///sandbox/capture-1.jpg'), isFalse);
    expect(sandbox.files.containsKey('file:///sandbox/capture-2.jpg'), isTrue);
  });
}
