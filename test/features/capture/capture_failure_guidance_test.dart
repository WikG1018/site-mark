import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/domain/capture_failure.dart';
import 'package:sitemark/domain/capture_failure_guidance.dart';
import 'package:sitemark/domain/original_photo_state.dart';

void main() {
  test('list guidance never promises a retry action', () {
    for (final code in CaptureFailureCode.values) {
      expect(captureFailureGuidanceForList(code).canRetry, isFalse);
    }
  });

  test('detail retry requires code, retained original, and active project', () {
    CaptureFailureGuidance guidance({
      CaptureFailureCode code = CaptureFailureCode.processingFailed,
      OriginalPhotoState state = OriginalPhotoState.retained,
      bool projectActive = true,
    }) => captureFailureGuidanceForDetail(
      code: code,
      originalState: state,
      projectActive: projectActive,
    );

    expect(guidance().canRetry, isTrue);
    expect(guidance(state: OriginalPhotoState.missing).canRetry, isFalse);
    expect(guidance(state: OriginalPhotoState.cleared).canRetry, isFalse);
    expect(guidance(projectActive: false).canRetry, isFalse);
    expect(
      guidance(code: CaptureFailureCode.originalModified).canRetry,
      isFalse,
    );
  });
}
