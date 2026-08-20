export enum CaptureStatus {
  PENDING_CAMERA = 'pendingCamera',
  CAPTURED = 'captured',
  RENDERING = 'rendering',
  READY = 'ready',
  FAILED = 'failed'
}

export enum ProjectLifecycleStatus {
  ACTIVE = 'active',
  COMPLETED = 'completed',
  ARCHIVED = 'archived'
}

export function canCaptureTransition(current: CaptureStatus, next: CaptureStatus): boolean {
  if (current === next) {
    return true;
  }
  switch (current) {
    case CaptureStatus.PENDING_CAMERA:
      return next === CaptureStatus.CAPTURED || next === CaptureStatus.FAILED;
    case CaptureStatus.CAPTURED:
      return next === CaptureStatus.RENDERING || next === CaptureStatus.FAILED;
    case CaptureStatus.RENDERING:
      return next === CaptureStatus.READY || next === CaptureStatus.FAILED;
    case CaptureStatus.READY:
    case CaptureStatus.FAILED:
      return next === CaptureStatus.CAPTURED;
    default:
      return false;
  }
}

export function canProjectTransition(current: ProjectLifecycleStatus,
  next: ProjectLifecycleStatus): boolean {
  if (current === next) {
    return true;
  }
  switch (current) {
    case ProjectLifecycleStatus.ACTIVE:
      return next === ProjectLifecycleStatus.COMPLETED || next === ProjectLifecycleStatus.ARCHIVED;
    case ProjectLifecycleStatus.COMPLETED:
      return next === ProjectLifecycleStatus.ACTIVE || next === ProjectLifecycleStatus.ARCHIVED;
    case ProjectLifecycleStatus.ARCHIVED:
      return next === ProjectLifecycleStatus.ACTIVE;
    default:
      return false;
  }
}
