import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sitemark/workflow/project_import_service.dart'
    show AtomicMarkerWriter, DartAtomicMarkerWriter;

enum CaptureMediaCleanupKind { clearOriginal, deleteCapture }

class PendingCaptureMediaCleanup {
  const PendingCaptureMediaCleanup({
    required this.captureId,
    required this.kind,
    required this.paths,
    this.publishedUri,
  });

  final String captureId;
  final CaptureMediaCleanupKind kind;
  final List<String> paths;
  final String? publishedUri;

  Map<String, dynamic> toJson() => {
    'captureId': captureId,
    'kind': kind.name,
    'paths': paths,
    if (publishedUri != null) 'publishedUri': publishedUri,
  };

  factory PendingCaptureMediaCleanup.fromJson(Map<String, dynamic> json) {
    final captureId = json['captureId'];
    final kindName = json['kind'];
    final paths = json['paths'];
    if (captureId is! String ||
        captureId.isEmpty ||
        kindName is! String ||
        paths is! List ||
        paths.any((path) => path is! String) ||
        (json['publishedUri'] != null && json['publishedUri'] is! String)) {
      throw const FormatException('Invalid capture media cleanup marker');
    }
    CaptureMediaCleanupKind? kind;
    for (final candidate in CaptureMediaCleanupKind.values) {
      if (candidate.name == kindName) {
        kind = candidate;
        break;
      }
    }
    if (kind == null) {
      throw const FormatException('Unknown capture media cleanup kind');
    }
    return PendingCaptureMediaCleanup(
      captureId: captureId,
      kind: kind,
      paths: paths.cast<String>().toList(growable: false),
      publishedUri: json['publishedUri'] as String?,
    );
  }
}

abstract interface class CaptureMediaCleanupPendingStore {
  Future<void> write(PendingCaptureMediaCleanup pending);

  Future<List<PendingCaptureMediaCleanup>> list();

  Future<void> clear(String captureId, CaptureMediaCleanupKind kind);
}

/// In-process fallback for tests and callers that do not inject app storage.
class MemoryCaptureMediaCleanupPendingStore
    implements CaptureMediaCleanupPendingStore {
  final Map<String, PendingCaptureMediaCleanup> _pendings = {};

  @override
  Future<void> write(PendingCaptureMediaCleanup pending) async {
    _pendings[_key(pending.captureId, pending.kind)] = pending;
  }

  @override
  Future<List<PendingCaptureMediaCleanup>> list() async =>
      _pendings.values.toList(growable: false);

  @override
  Future<void> clear(String captureId, CaptureMediaCleanupKind kind) async {
    _pendings.remove(_key(captureId, kind));
  }

  static String _key(String captureId, CaptureMediaCleanupKind kind) =>
      '${kind.name}\u0000$captureId';
}

/// Stores crash-recovery markers under `<documents>/capture-media-cleanup/`.
class AppCaptureMediaCleanupPendingStore
    implements CaptureMediaCleanupPendingStore {
  AppCaptureMediaCleanupPendingStore({
    Future<Directory> Function()? documentsDirectory,
    AtomicMarkerWriter? writer,
  }) : _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory,
       _writer = writer ?? DartAtomicMarkerWriter();

  final Future<Directory> Function() _documentsDirectory;
  final AtomicMarkerWriter _writer;

  Future<Directory> _cleanupDirectory() async {
    final root = await _documentsDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}capture-media-cleanup',
    );
    await directory.create(recursive: true);
    return directory;
  }

  @override
  Future<void> write(PendingCaptureMediaCleanup pending) async {
    final directory = await _cleanupDirectory();
    final marker = File(
      '${directory.path}${Platform.pathSeparator}${_markerName(pending.captureId, pending.kind)}',
    );
    await _writer.write(marker, jsonEncode(pending.toJson()));
  }

  @override
  Future<List<PendingCaptureMediaCleanup>> list() async {
    final directory = await _cleanupDirectory();
    final result = <PendingCaptureMediaCleanup>[];
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final identity = _parseMarkerName(name);
      if (identity == null) continue;
      final decoded = jsonDecode(await entity.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Cleanup marker is not a JSON object');
      }
      final pending = PendingCaptureMediaCleanup.fromJson(decoded);
      if (pending.captureId != identity.captureId ||
          pending.kind != identity.kind) {
        throw const FormatException('Cleanup marker identity mismatch');
      }
      result.add(pending);
    }
    return result;
  }

  @override
  Future<void> clear(String captureId, CaptureMediaCleanupKind kind) async {
    final directory = await _cleanupDirectory();
    final marker = File(
      '${directory.path}${Platform.pathSeparator}${_markerName(captureId, kind)}',
    );
    if (await marker.exists()) await marker.delete();
  }

  static String _markerName(String captureId, CaptureMediaCleanupKind kind) {
    final encodedId = base64Url
        .encode(utf8.encode(captureId))
        .replaceAll('=', '');
    return 'capture-${_kindName(kind)}-$encodedId.json';
  }

  static _CaptureCleanupMarkerIdentity? _parseMarkerName(String name) {
    final match = RegExp(
      r'^capture-(clear-original|delete-capture)-([A-Za-z0-9_-]+)\.json$',
    ).firstMatch(name);
    if (match == null) return null;
    try {
      final encodedId = match.group(2)!;
      final paddingLength = (4 - encodedId.length % 4) % 4;
      final captureId = utf8.decode(
        base64Url.decode('$encodedId${'=' * paddingLength}'),
      );
      final kind = _kindFromName(match.group(1)!);
      if (kind == null) return null;
      if (_markerName(captureId, kind) != name) return null;
      return _CaptureCleanupMarkerIdentity(captureId: captureId, kind: kind);
    } catch (_) {
      return null;
    }
  }

  static String _kindName(CaptureMediaCleanupKind kind) => switch (kind) {
    CaptureMediaCleanupKind.clearOriginal => 'clear-original',
    CaptureMediaCleanupKind.deleteCapture => 'delete-capture',
  };

  static CaptureMediaCleanupKind? _kindFromName(String name) => switch (name) {
    'clear-original' => CaptureMediaCleanupKind.clearOriginal,
    'delete-capture' => CaptureMediaCleanupKind.deleteCapture,
    _ => null,
  };
}

class _CaptureCleanupMarkerIdentity {
  const _CaptureCleanupMarkerIdentity({
    required this.captureId,
    required this.kind,
  });

  final String captureId;
  final CaptureMediaCleanupKind kind;
}
