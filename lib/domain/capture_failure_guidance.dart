import 'package:sitemark/domain/capture_failure.dart';
import 'package:sitemark/domain/original_photo_state.dart';

enum CaptureFailureGuidanceSurface { list, detail }

final class CaptureFailureGuidance {
  const CaptureFailureGuidance._({
    required this.code,
    required this.surface,
    required this.originalState,
    required this.projectActive,
  });

  final CaptureFailureCode code;
  final CaptureFailureGuidanceSurface surface;
  final OriginalPhotoState? originalState;
  final bool projectActive;

  bool get canRetry =>
      surface == CaptureFailureGuidanceSurface.detail &&
      projectActive &&
      originalState == OriginalPhotoState.retained &&
      code.canRetryProcessing;
}

CaptureFailureGuidance captureFailureGuidanceForList(CaptureFailureCode code) =>
    CaptureFailureGuidance._(
      code: code,
      surface: CaptureFailureGuidanceSurface.list,
      originalState: null,
      projectActive: false,
    );

CaptureFailureGuidance captureFailureGuidanceForDetail({
  required CaptureFailureCode code,
  required OriginalPhotoState? originalState,
  required bool projectActive,
}) => CaptureFailureGuidance._(
  code: code,
  surface: CaptureFailureGuidanceSurface.detail,
  originalState: originalState,
  projectActive: projectActive,
);
