import 'dart:async';

import 'package:sitemark/background/capture_background_scheduler.dart';
import 'package:sitemark/workflow/capture_processor.dart';

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
  InAppSerialBackgroundWorkClient({
    required this.runner,
    Future<void> Function(Duration duration)? wait,
  }) : wait = wait ?? ((duration) => Future<void>.delayed(duration));

  final Future<CaptureProcessResult> Function(String captureId) runner;
  final Future<void> Function(Duration duration) wait;

  static const Duration initialBackoff = Duration(seconds: 30);
  static const int maxScheduledRetries = 3;

  final List<String> _pending = <String>[];
  final Map<String, int> _retryAttempts = <String, int>{};
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
        CaptureProcessResult result;
        try {
          result = await runner(captureId);
        } catch (_) {
          result = CaptureProcessResult.retry;
        }
        if (result == CaptureProcessResult.retry) {
          unawaited(_scheduleRetry(captureId));
        } else {
          _retryAttempts.remove(captureId);
        }
      }
    } finally {
      _draining = false;
      if (_pending.isNotEmpty) {
        unawaited(_drain());
      }
    }
  }

  Future<void> _scheduleRetry(String captureId) async {
    final attempt = (_retryAttempts[captureId] ?? 0) + 1;
    if (attempt > maxScheduledRetries) {
      _retryAttempts.remove(captureId);
      return;
    }
    _retryAttempts[captureId] = attempt;
    final delay = initialBackoff * (1 << (attempt - 1));
    await wait(delay);
    await appendCapture(
      queueName: captureProcessingQueue,
      taskName: captureProcessingTask,
      captureId: captureId,
      tag: 'capture:$captureId',
    );
  }
}
