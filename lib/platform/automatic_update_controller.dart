import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sitemark/domain/release_check.dart';
import 'package:sitemark/platform/github_release_client.dart';
import 'package:sitemark/platform/release_check_mode_store.dart';

class AutomaticUpdateState {
  const AutomaticUpdateState({
    this.enabled = true,
    this.lastCheck,
    this.remindedTag,
    this.remindedAt,
  });

  final bool enabled;
  final DateTime? lastCheck;
  final String? remindedTag;
  final DateTime? remindedAt;

  AutomaticUpdateState copyWith({
    bool? enabled,
    DateTime? lastCheck,
    String? remindedTag,
    DateTime? remindedAt,
  }) => AutomaticUpdateState(
    enabled: enabled ?? this.enabled,
    lastCheck: lastCheck ?? this.lastCheck,
    remindedTag: remindedTag ?? this.remindedTag,
    remindedAt: remindedAt ?? this.remindedAt,
  );
}

abstract interface class AutomaticUpdateStore {
  Future<AutomaticUpdateState> read();
  Future<void> write(AutomaticUpdateState state);
}

/// Only update preferences/timestamps; never engineering data or identifiers.
/// A corrupt/unreadable preference is an error, not permission to enable HTTP.
class FileAutomaticUpdateStore implements AutomaticUpdateStore {
  FileAutomaticUpdateStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _directory;

  Future<File> _file() async => File(
    '${(await _directory()).path}${Platform.pathSeparator}automatic_update.json',
  );

  @override
  Future<AutomaticUpdateState> read() async {
    final file = await _file();
    if (!await file.exists()) return const AutomaticUpdateState();
    final json = jsonDecode(await file.readAsString());
    if (json is! Map<String, dynamic> || json['enabled'] is! bool) {
      throw const FormatException('Invalid update preferences');
    }
    DateTime? date(String key) {
      final value = json[key];
      return value == null ? null : DateTime.parse(value as String).toUtc();
    }

    return AutomaticUpdateState(
      enabled: json['enabled'] as bool,
      lastCheck: date('lastCheck'),
      remindedTag: json['remindedTag'] as String?,
      remindedAt: date('remindedAt'),
    );
  }

  @override
  Future<void> write(AutomaticUpdateState state) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'enabled': state.enabled,
        'lastCheck': state.lastCheck?.toUtc().toIso8601String(),
        'remindedTag': state.remindedTag,
        'remindedAt': state.remindedAt?.toUtc().toIso8601String(),
      }),
      flush: true,
    );
    await temporary.rename(file.path);
  }
}

/// Foreground-only, bounded checks. Owns neither downloads nor installation.
/// Failure is silent here; About retains the explicit check/error workflow.
class AutomaticUpdateController extends ChangeNotifier {
  AutomaticUpdateController({
    required this._store,
    required this._lookup,
    required this._modes,
    required this._version,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const checkInterval = Duration(hours: 24);
  final AutomaticUpdateStore _store;
  final ReleaseLookup _lookup;
  final ReleaseCheckModeStore _modes;
  final Future<String?> Function() _version;
  final DateTime Function() _clock;
  AutomaticUpdateState _state = const AutomaticUpdateState();
  Future<void>? _loading;
  Future<void>? _writes;
  bool _alive = true;
  bool _checking = false;
  bool _foreground = true;
  bool _storageHealthy = true;
  bool loaded = false;
  bool saving = false;
  int _generation = 0;
  ReleaseCheckOutcome? outcome;

  bool get enabled => _state.enabled;
  bool _recent(DateTime? date) {
    if (date == null) return false;
    final elapsed = _clock().toUtc().difference(date);
    // Clock corrections should not suppress checks forever.
    return !elapsed.isNegative && elapsed < checkInterval;
  }

  ReleaseCheckOutcome? get pendingReminder {
    if (!enabled || saving || !_storageHealthy || outcome?.hasUpdate != true) {
      return null;
    }
    if (_state.remindedTag == outcome!.tag && _recent(_state.remindedAt)) {
      return null;
    }
    return outcome;
  }

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    try {
      _state = await _store.read();
    } catch (_) {
      _state = const AutomaticUpdateState(enabled: false);
      _storageHealthy = false;
    }
    loaded = true;
    _emit();
  }

  Future<bool> _persist() async {
    final snapshot = _state;
    var succeeded = false;
    // Serialize writes so a late check/dismiss cannot undo a newer opt-out.
    Future<void> write() async {
      try {
        await _store.write(snapshot);
        succeeded = true;
      } catch (_) {
        /* Settings UI reports failures; checks stay silent. */
      }
    }

    _writes = _writes?.then((_) => write()) ?? write();
    await _writes;
    _storageHealthy = succeeded;
    return succeeded;
  }

  Future<bool> setEnabled(bool value) async {
    await load();
    if (!_alive || saving) return false;
    saving = true;
    _generation++;
    _state = _state.copyWith(enabled: value);
    // Opting out suppresses future requests/reminders, not a known update
    // already displayed in About's explicit download workflow.
    _emit();
    final success = await _persist();
    saving = false;
    _emit();
    return success;
  }

  void setForeground(bool value) => _foreground = value;

  Future<void> checkOnForeground() async {
    await load();
    if (!_alive ||
        !_foreground ||
        !enabled ||
        saving ||
        !_storageHealthy ||
        _checking ||
        _recent(_state.lastCheck)) {
      return;
    }
    _checking = true;
    final generation = _generation;
    bool current() => _alive && enabled && !saving && generation == _generation;
    try {
      final version = await _version();
      if (!current() ||
          !_foreground ||
          version == null ||
          parseVersion(version) == null) {
        return;
      }
      final mode = await _modes.read();
      if (!current() || !_foreground) return;
      _state = _state.copyWith(lastCheck: _clock().toUtc());
      // Persist before HTTP: crashes/offline failures still respect cooldown.
      if (!await _persist() || !current() || !_foreground) return;
      final result = await _lookup.check(localVersion: version, mode: mode);
      if (!current()) return;
      outcome = result;
      _emit();
    } catch (_) {
      // No error toast from an automatic check, and no automatic retry loop.
    } finally {
      _checking = false;
    }
  }

  Future<void> markReminded() async {
    final available = outcome;
    if (!_alive || available?.hasUpdate != true) return;
    _state = _state.copyWith(
      remindedTag: available!.tag,
      remindedAt: _clock().toUtc(),
    );
    _emit();
    await _persist();
  }

  void _emit() {
    if (_alive) notifyListeners();
  }

  @override
  void dispose() {
    _alive = false;
    _generation++;
    super.dispose();
  }
}
