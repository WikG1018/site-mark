import 'dart:io';

import 'package:sitemark_system_api/src/ohos/capture_target_policy.dart';
import 'package:sitemark_system_api/src/system_api.g.dart';

abstract class KeyValueStore {
  Future<void> write(Map<String, String> entries);
  Future<String?> read(String key);
  Future<void> remove(Iterable<String> keys);
}

class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> write(Map<String, String> entries) async {
    _values.addAll(entries);
  }

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> remove(Iterable<String> keys) async {
    for (final key in keys) {
      _values.remove(key);
    }
  }
}

class CaptureSessionStore {
  CaptureSessionStore(this._store);

  static const String keyCaptureId = 'capture_id';
  static const String keyCapturePath = 'capture_path';

  final KeyValueStore _store;

  Future<void> write({
    required String captureId,
    required String outputPath,
  }) {
    return _store.write(<String, String>{
      keyCaptureId: captureId,
      keyCapturePath: outputPath,
    });
  }

  Future<RecoveredCameraCapture?> recover() async {
    final captureId = await _store.read(keyCaptureId);
    final outputPath = await _store.read(keyCapturePath);
    if (captureId == null ||
        captureId.isEmpty ||
        outputPath == null ||
        outputPath.isEmpty) {
      return null;
    }
    final file = File(outputPath);
    final exists = file.existsSync();
    final length = exists ? file.lengthSync() : 0;
    return RecoveredCameraCapture(
      captureId: captureId,
      outputPath: outputPath,
      hasContent: CaptureTargetPolicy.isCaptured(
        exists: exists,
        length: length,
      ),
    );
  }

  Future<void> clear() {
    return _store.remove(const <String>[keyCaptureId, keyCapturePath]);
  }
}
