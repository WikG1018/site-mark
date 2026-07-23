import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Snapshot of the capture form's text fields at the moment a MEMORY_KILL
/// broadcast arrives. Persisted by a [KillBackupHook] registered in
/// `CaptureFormScreen` so an in-progress (not-yet-captured) draft survives
/// the process being killed by the OEM fair-memory mechanism.
///
/// Only the user-entered text fields are persisted; `projectId` keys the
/// snapshot so multiple projects do not clobber each other. The snapshot is
/// cleared after a successful capture (the draft becomes a real record) and
/// is intentionally not cleared on form dispose without capture — the user
/// may have backgrounded the app and gotten killed mid-entry.
@immutable
class CaptureFormDraftSnapshot {
  const CaptureFormDraftSnapshot({
    required this.projectId,
    required this.workLocation,
    required this.workContent,
    required this.photographer,
    required this.notes,
  });

  final String projectId;
  final String workLocation;
  final String workContent;
  final String photographer;
  final String notes;

  Map<String, dynamic> toJson() => {
    'projectId': projectId,
    'workLocation': workLocation,
    'workContent': workContent,
    'photographer': photographer,
    'notes': notes,
  };

  static CaptureFormDraftSnapshot fromJson(Map<String, dynamic> json) {
    return CaptureFormDraftSnapshot(
      projectId: json['projectId'] as String? ?? '',
      workLocation: json['workLocation'] as String? ?? '',
      workContent: json['workContent'] as String? ?? '',
      photographer: json['photographer'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
    );
  }
}

/// Persists [CaptureFormDraftSnapshot]s so an in-progress capture form
/// survives a MEMORY_KILL. Implementations must be safe to call from the
/// KILL handler's background context (no main-thread-only APIs).
abstract class CaptureFormDraftStore {
  Future<void> save(CaptureFormDraftSnapshot snapshot);
  Future<CaptureFormDraftSnapshot?> load(String projectId);
  Future<void> clear(String projectId);
}

/// File-backed implementation. Writes one JSON file per project under the
/// app's documents directory: `kill_form_draft_<projectId>.json`.
class FileCaptureFormDraftStore implements CaptureFormDraftStore {
  Future<File> _fileFor(String projectId) async {
    final dir = await getApplicationDocumentsDirectory();
    // Sanitize the projectId for the filesystem: it is expected to be a
    // UUID-like string, but replace any path separators just in case.
    final safe = projectId.replaceAll(RegExp(r'[/\\]'), '_');
    return File('${dir.path}/kill_form_draft_$safe.json');
  }

  @override
  Future<void> save(CaptureFormDraftSnapshot snapshot) async {
    final file = await _fileFor(snapshot.projectId);
    await file.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
  }

  @override
  Future<CaptureFormDraftSnapshot?> load(String projectId) async {
    final file = await _fileFor(projectId);
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return CaptureFormDraftSnapshot.fromJson(json);
    } catch (_) {
      // Corrupt or partial write (e.g. process killed mid-write). Treat as
      // no snapshot so the form falls back to the carry-forward draft.
      return null;
    }
  }

  @override
  Future<void> clear(String projectId) async {
    final file = await _fileFor(projectId);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

/// In-memory implementation for tests that don't want to touch the
/// filesystem.
class MemoryCaptureFormDraftStore implements CaptureFormDraftStore {
  final Map<String, CaptureFormDraftSnapshot> _store = {};

  @override
  Future<void> save(CaptureFormDraftSnapshot snapshot) async {
    _store[snapshot.projectId] = snapshot;
  }

  @override
  Future<CaptureFormDraftSnapshot?> load(String projectId) async {
    return _store[projectId];
  }

  @override
  Future<void> clear(String projectId) async {
    _store.remove(projectId);
  }
}

/// Riverpod provider. Production wires [FileCaptureFormDraftStore]; tests
/// override with [MemoryCaptureFormDraftStore].
final captureFormDraftStoreProvider = Provider<CaptureFormDraftStore>((ref) {
  return FileCaptureFormDraftStore();
});
