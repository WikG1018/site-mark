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
