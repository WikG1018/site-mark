import 'package:sitemark_system_api/src/ohos/gallery_access.dart';

class GalleryPublishResult {
  const GalleryPublishResult({
    required this.contentUri,
    required this.supersededUris,
    required this.enteredSystemAlbum,
  });

  final String contentUri;
  final List<String> supersededUris;
  final bool enteredSystemAlbum;
}

abstract interface class GalleryStore {
  Future<GalleryPublishResult> publish({
    required String sourcePath,
    required String displayName,
    required String captureId,
    String? publishedUri,
    List<String> leftoverJournalUris = const [],
  });

  Future<void> delete(String contentUri);
}

class _PhotoRecord {
  const _PhotoRecord({required this.bytes, this.displayName});

  final List<int> bytes;
  final String? displayName;
}

class MemoryPhotoAccess {
  final Map<String, _PhotoRecord> _photos = <String, _PhotoRecord>{};
  int _nextId = 0;

  void seed(String uri, {List<int>? bytes, String? displayName}) {
    _photos[uri] = _PhotoRecord(
      bytes: List<int>.from(bytes ?? const <int>[]),
      displayName: displayName,
    );
  }

  bool exists(String uri) => _photos.containsKey(uri);

  String write({required String sourcePath, required String displayName}) {
    _nextId += 1;
    final uri = 'ph://published-$_nextId';
    _photos[uri] = _PhotoRecord(
      bytes: const <int>[0],
      displayName: displayName,
    );
    return uri;
  }

  void delete(String uri) {
    _photos.remove(uri);
  }
}

class MemorySandbox {
  final Map<String, String> files = <String, String>{};

  String write({
    required String sourcePath,
    required String displayName,
    required String captureId,
  }) {
    final uri = 'file:///sandbox/$captureId.jpg';
    files[uri] = sourcePath;
    return uri;
  }

  void delete(String uri) {
    files.remove(uri);
  }
}

class AclGalleryStore implements GalleryStore {
  AclGalleryStore(this._photos);

  final MemoryPhotoAccess _photos;

  @override
  Future<GalleryPublishResult> publish({
    required String sourcePath,
    required String displayName,
    required String captureId,
    String? publishedUri,
    List<String> leftoverJournalUris = const [],
  }) async {
    final contentUri = _photos.write(
      sourcePath: sourcePath,
      displayName: displayName,
    );
    return GalleryPublishResult(
      contentUri: contentUri,
      supersededUris: _superseded(
        publishedUri: publishedUri,
        leftoverJournalUris: leftoverJournalUris,
        contentUri: contentUri,
      ),
      enteredSystemAlbum: true,
    );
  }

  @override
  Future<void> delete(String contentUri) async {
    _photos.delete(contentUri);
  }
}

class PickerFallbackStore implements GalleryStore {
  PickerFallbackStore(this._sandbox);

  final MemorySandbox _sandbox;

  @override
  Future<GalleryPublishResult> publish({
    required String sourcePath,
    required String displayName,
    required String captureId,
    String? publishedUri,
    List<String> leftoverJournalUris = const [],
  }) async {
    final contentUri = _sandbox.write(
      sourcePath: sourcePath,
      displayName: displayName,
      captureId: captureId,
    );
    return GalleryPublishResult(
      contentUri: contentUri,
      supersededUris: _superseded(
        publishedUri: publishedUri,
        leftoverJournalUris: leftoverJournalUris,
        contentUri: contentUri,
      ),
      enteredSystemAlbum: false,
    );
  }

  @override
  Future<void> delete(String contentUri) async {
    if (isSandboxPublishedUri(contentUri)) {
      _sandbox.delete(contentUri);
    }
  }
}

class ProbingGalleryStore implements GalleryStore {
  ProbingGalleryStore({
    required GalleryAccessProbe probe,
    required GalleryStore acl,
    required GalleryStore picker,
  }) : _probe = probe,
       _acl = acl,
       _picker = picker;

  final GalleryAccessProbe _probe;
  final GalleryStore _acl;
  final GalleryStore _picker;

  GalleryAccessMode? lastMode;

  Future<GalleryStore> _resolve() async {
    lastMode ??= await _probe.detect();
    return lastMode == GalleryAccessMode.acl ? _acl : _picker;
  }

  @override
  Future<GalleryPublishResult> publish({
    required String sourcePath,
    required String displayName,
    required String captureId,
    String? publishedUri,
    List<String> leftoverJournalUris = const [],
  }) async {
    final store = await _resolve();
    return store.publish(
      sourcePath: sourcePath,
      displayName: displayName,
      captureId: captureId,
      publishedUri: publishedUri,
      leftoverJournalUris: leftoverJournalUris,
    );
  }

  @override
  Future<void> delete(String contentUri) async {
    if (contentUri.isEmpty) return;
    // Match OhosSystemHost.deletePublishedImage: route by URI identity, not
    // the current gallery probe. A restored duplicate may have been written
    // under ACL and later deleted after the probe fell back to picker.
    if (isSandboxPublishedUri(contentUri)) {
      await _picker.delete(contentUri);
      return;
    }
    await _acl.delete(contentUri);
  }
}

/// Sandbox publishes live at `file://` paths the app owns. Media-library
/// `file://media/` / `datashare://` URIs must go through ACL deleteAssets.
bool isSandboxPublishedUri(String uri) {
  if (!uri.startsWith('file://')) return false;
  if (uri.startsWith('file://media/')) return false;
  if (uri.startsWith('datashare://')) return false;
  if (uri.contains('/media/')) return false;
  return true;
}

List<String> _superseded({
  required String? publishedUri,
  required List<String> leftoverJournalUris,
  required String contentUri,
}) {
  final uris = <String>[];
  final seen = <String>{contentUri};
  void add(String? uri) {
    if (uri == null || uri.isEmpty || !seen.add(uri)) return;
    uris.add(uri);
  }

  add(publishedUri);
  for (final uri in leftoverJournalUris) {
    add(uri);
  }
  return uris;
}
