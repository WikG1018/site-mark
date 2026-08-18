import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark_system_api/src/ohos/gallery_store.dart';

void main() {
  test('ACL publish reports only the passed publishedUri plus leftover journal', () async {
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
    expect(photos.exists('ph://old'), isTrue, reason: 'native must not delete');
  });

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
}
