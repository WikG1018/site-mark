import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark_system_api/src/ohos/capture_target_policy.dart';

void main() {
  test('accepts the same capture id alphabet as Android', () {
    expect(CaptureTargetPolicy.fileName('capture-1'), 'capture-1.jpg');
    expect(CaptureTargetPolicy.fileName('A' * 96), 'A' * 96 + '.jpg');
  });

  test('rejects empty, dotted, or overlong ids', () {
    expect(() => CaptureTargetPolicy.fileName(''), throwsArgumentError);
    expect(() => CaptureTargetPolicy.fileName('bad.id'), throwsArgumentError);
    expect(() => CaptureTargetPolicy.fileName('A' * 97), throwsArgumentError);
  });

  test('recovery treats missing or empty file as cancelled', () {
    expect(CaptureTargetPolicy.isCaptured(exists: true, length: 12), isTrue);
    expect(CaptureTargetPolicy.isCaptured(exists: true, length: 0), isFalse);
    expect(CaptureTargetPolicy.isCaptured(exists: false, length: 0), isFalse);
  });
}
