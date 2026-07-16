import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/domain/capture_status.dart';

void main() {
  test('pending camera can only become captured or failed', () {
    expect(CaptureStatus.pendingCamera.allowedNext, {
      CaptureStatus.captured,
      CaptureStatus.failed,
    });
  });

  test('rendering can become ready or failed', () {
    expect(CaptureStatus.rendering.allowedNext, {
      CaptureStatus.ready,
      CaptureStatus.failed,
    });
  });

  test('ready can transition back to captured for regeneration', () {
    expect(CaptureStatus.ready.allowedNext, {CaptureStatus.captured});
  });

  test('failed can transition back to captured for retry', () {
    expect(CaptureStatus.failed.allowedNext, {CaptureStatus.captured});
  });

  test('self transitions are idempotent for repeated worker invocations', () {
    for (final status in CaptureStatus.values) {
      expect(status.canTransitionTo(status), isTrue, reason: status.name);
    }
  });

  test('captured can become rendering or failed', () {
    expect(CaptureStatus.captured.allowedNext, {
      CaptureStatus.rendering,
      CaptureStatus.failed,
    });
  });
}
