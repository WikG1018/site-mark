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

  test('ready is terminal', () {
    expect(CaptureStatus.ready.allowedNext, isEmpty);
  });
}
