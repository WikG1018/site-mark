import 'dart:io';

import 'package:sitemark/diagnostics/diagnostic_event.dart';

class DiagnosticEventStore {
  DiagnosticEventStore({
    required this.directory,
    DateTime Function()? clock,
    this.maxBytes = 2 * 1024 * 1024,
    this.retention = const Duration(days: 7),
  }) : _clock = clock ?? DateTime.now;

  final Directory directory;
  final int maxBytes;
  final Duration retention;
  final DateTime Function() _clock;
  Future<void> _pending = Future.value();

  File get _file =>
      File('${directory.path}${Platform.pathSeparator}events.jsonl');

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final operation = _pending.then((_) => action());
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> append(DiagnosticEvent event) =>
      _enqueue(() => _appendLocked(event));

  Future<void> _appendLocked(DiagnosticEvent event) async {
    await directory.create(recursive: true);
    final existing = await _readRecent();
    final events = [...existing, event]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    var lines = events.map((value) => value.encode()).toList();
    while (lines.length > 1 &&
        lines.fold<int>(0, (sum, line) => sum + line.length + 1) > maxBytes) {
      lines = lines.sublist(1);
    }
    final handle = await _file.open(mode: FileMode.write);
    try {
      await handle.lock(FileLock.exclusive);
      await handle.writeString(lines.isEmpty ? '' : '${lines.join('\n')}\n');
      await handle.flush();
      await handle.unlock();
    } finally {
      await handle.close();
    }
  }

  Future<List<DiagnosticEvent>> readRecent() => _enqueue(_readRecent);

  Future<List<DiagnosticEvent>> _readRecent() async {
    if (!await _file.exists()) return const [];
    final cutoff = _clock().toUtc().subtract(retention);
    final lines = await _file.readAsLines();
    return lines
        .map(DiagnosticEvent.tryDecode)
        .whereType<DiagnosticEvent>()
        .where((event) => !event.timestamp.toUtc().isBefore(cutoff))
        .toList(growable: false);
  }

  Future<int> sizeBytes() =>
      _enqueue(() async => await _file.exists() ? _file.length() : 0);

  Future<void> clear() => _enqueue(() async {
    if (await _file.exists()) await _file.delete();
  });
}
