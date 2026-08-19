import { describe, expect, it } from '@ohos/hypium';
import { CaptureStatus, canCaptureTransition, ProjectLifecycleStatus,
  canProjectTransition } from '../main/ets/domain/StateMachine';

export default function captureStateTest(): void {
  describe('StateMachine', () => {
    it('locks capture transitions to Android parity', 0, () => {
      expect(canCaptureTransition(CaptureStatus.PENDING_CAMERA, CaptureStatus.CAPTURED)).assertTrue();
      expect(canCaptureTransition(CaptureStatus.PENDING_CAMERA, CaptureStatus.FAILED)).assertTrue();
      expect(canCaptureTransition(CaptureStatus.CAPTURED, CaptureStatus.RENDERING)).assertTrue();
      expect(canCaptureTransition(CaptureStatus.RENDERING, CaptureStatus.READY)).assertTrue();
      expect(canCaptureTransition(CaptureStatus.READY, CaptureStatus.CAPTURED)).assertTrue();
      expect(canCaptureTransition(CaptureStatus.FAILED, CaptureStatus.CAPTURED)).assertTrue();
      expect(canCaptureTransition(CaptureStatus.PENDING_CAMERA, CaptureStatus.READY)).assertFalse();
      expect(canCaptureTransition(CaptureStatus.RENDERING, CaptureStatus.CAPTURED)).assertFalse();
    });

    it('allows idempotent capture transitions', 0, () => {
      expect(canCaptureTransition(CaptureStatus.CAPTURED, CaptureStatus.CAPTURED)).assertTrue();
      expect(canCaptureTransition(CaptureStatus.READY, CaptureStatus.READY)).assertTrue();
    });

    it('locks lifecycle transitions and allows reopening', 0, () => {
      expect(canProjectTransition(ProjectLifecycleStatus.ACTIVE,
        ProjectLifecycleStatus.COMPLETED)).assertTrue();
      expect(canProjectTransition(ProjectLifecycleStatus.ACTIVE,
        ProjectLifecycleStatus.ARCHIVED)).assertTrue();
      expect(canProjectTransition(ProjectLifecycleStatus.COMPLETED,
        ProjectLifecycleStatus.ACTIVE)).assertTrue();
      expect(canProjectTransition(ProjectLifecycleStatus.ARCHIVED,
        ProjectLifecycleStatus.ACTIVE)).assertTrue();
      expect(canProjectTransition(ProjectLifecycleStatus.ARCHIVED,
        ProjectLifecycleStatus.COMPLETED)).assertFalse();
    });
  });
}
