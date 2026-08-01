import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/domain/capture_failure.dart';

void main() {
  test('stable capture failure codes round-trip from storage', () {
    for (final code in CaptureFailureCode.values) {
      expect(CaptureFailureCode.fromStorage(code.storageCode), code);
    }
  });

  test('legacy and missing failure text maps to a safe generic code', () {
    expect(
      CaptureFailureCode.fromStorage('Bad state: native bridge exploded'),
      CaptureFailureCode.unexpected,
    );
    expect(CaptureFailureCode.fromStorage(null), CaptureFailureCode.unexpected);
  });
}
