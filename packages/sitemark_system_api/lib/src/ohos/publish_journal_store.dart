import 'dart:convert';

import 'package:sitemark_system_api/src/ohos/capture_session_store.dart';

export 'package:sitemark_system_api/src/ohos/capture_session_store.dart'
    show MemoryKeyValueStore;

class PublishJournalEntry {
  const PublishJournalEntry({
    required this.captureId,
    required this.contentUri,
    required this.supersededUris,
  });

  final String captureId;
  final String contentUri;
  final List<String> supersededUris;
}

class HarmonyPublishJournalStore {
  HarmonyPublishJournalStore(this._prefs);

  static const String _prefix = 'journal.';
  static const String _exists = 'exists';
  static const String _newUri = 'newUri';
  static const String _staleCount = 'staleCount';
  static const String _stalePrefix = 'stale.';

  final MemoryKeyValueStore _prefs;

  bool record({
    required String captureId,
    required String contentUri,
    required List<String> supersededUris,
  }) {
    final prefix = _keyPrefix(captureId);
    final previousCount = int.tryParse(_prefs.get('$prefix$_staleCount') ?? '') ?? 0;
    _prefs.put('$prefix$_newUri', contentUri);
    _prefs.put('$prefix$_staleCount', '${supersededUris.length}');
    _prefs.put('$prefix$_exists', 'true');
    for (var index = 0; index < supersededUris.length; index++) {
      _prefs.put('$prefix$_stalePrefix$index', supersededUris[index]);
    }
    for (var index = supersededUris.length; index < previousCount; index++) {
      _prefs.removeKey('$prefix$_stalePrefix$index');
    }
    return _prefs.commit();
  }

  PublishJournalEntry? peek(String captureId) {
    final prefix = _keyPrefix(captureId);
    if (_prefs.get('$prefix$_exists') == null) return null;
    final contentUri = _prefs.get('$prefix$_newUri');
    if (contentUri == null) return null;
    return PublishJournalEntry(
      captureId: captureId,
      contentUri: contentUri,
      supersededUris: _staleUris(prefix),
    );
  }

  List<PublishJournalEntry> recover() {
    final recovered = <PublishJournalEntry>[];
    for (final key in _prefs.keys.toList()) {
      if (!key.endsWith('.$_exists')) continue;
      final prefix = '${key.substring(0, key.length - '.$_exists'.length)}.';
      final contentUri = _prefs.get('$prefix$_newUri');
      if (contentUri == null) continue;
      final captureId = _decodeCaptureId(prefix);
      if (captureId == null) continue;
      recovered.add(
        PublishJournalEntry(
          captureId: captureId,
          contentUri: contentUri,
          supersededUris: _staleUris(prefix),
        ),
      );
    }
    return recovered;
  }

  bool clear(String captureId, String expectedContentUri) {
    final prefix = _keyPrefix(captureId);
    if (_prefs.get('$prefix$_exists') == null) return true;
    final current = _prefs.get('$prefix$_newUri');
    if (current != null && current != expectedContentUri) return false;
    for (final key in _prefs.keys.toList()) {
      if (key.startsWith(prefix)) {
        _prefs.removeKey(key);
      }
    }
    return _prefs.commit();
  }

  List<String> _staleUris(String prefix) {
    final count = int.tryParse(_prefs.get('$prefix$_staleCount') ?? '') ?? 0;
    final uris = <String>[];
    for (var index = 0; index < count; index++) {
      final uri = _prefs.get('$prefix$_stalePrefix$index');
      if (uri != null) uris.add(uri);
    }
    return uris;
  }

  static String _keyPrefix(String captureId) =>
      '$_prefix${encodeJournalCaptureId(captureId)}.';

  static String? _decodeCaptureId(String keyPrefix) {
    if (!keyPrefix.startsWith(_prefix)) return null;
    final encoded = keyPrefix.substring(_prefix.length, keyPrefix.length - 1);
    if (encoded.isEmpty) return null;
    try {
      return utf8.decode(base64Url.decode(base64Url.normalize(encoded)));
    } on FormatException {
      return null;
    }
  }
}

String encodeJournalCaptureId(String captureId) =>
    base64Url.encode(utf8.encode(captureId)).replaceAll('=', '');
