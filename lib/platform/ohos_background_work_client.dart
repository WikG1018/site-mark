import 'dart:async';

import 'package:sitemark/background/capture_background_scheduler.dart';

class UnimplementedOhosBackgroundWorkClient implements BackgroundWorkClient {
  @override
  Future<void> initialize(void Function() dispatcher) async {}

  @override
  Future<void> appendCapture({
    required String queueName,
    required String taskName,
    required String captureId,
    required String tag,
  }) {
    throw StateError('ohos_queue_not_ready');
  }
}

class InAppSerialBackgroundWorkClient implements BackgroundWorkClient {
  InAppSerialBackgroundWorkClient({required this.runner});

  final Future<void> Function(String captureId) runner;

  final List<String> _pending = <String>[];
  bool _draining = false;

  @override
  Future<void> initialize(void Function() dispatcher) async {}

  @override
  Future<void> appendCapture({
    required String queueName,
    required String taskName,
    required String captureId,
    required String tag,
  }) async {
    _pending.remove(captureId);
    _pending.add(captureId);
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_pending.isNotEmpty) {
        final captureId = _pending.removeAt(0);
        await runner(captureId);
      }
    } finally {
      _draining = false;
      if (_pending.isNotEmpty) {
        unawaited(_drain());
      }
    }
  }
}
