type NotificationLaunchConsumer = (captureId: string) => void;

export function captureIdFromWantParameters(parameters: Record<string, Object>
  | undefined): string {
  if (!parameters) {
    return '';
  }
  const raw: Object | undefined = parameters['captureId'];
  if (typeof raw === 'string') {
    return raw.trim();
  }
  if (typeof raw === 'number' && Number.isFinite(raw)) {
    return `${raw}`;
  }
  return '';
}

export class PendingNotificationLaunch {
  private static pendingCaptureId: string = '';
  private static consumer: NotificationLaunchConsumer | null = null;

  static put(captureId: string): void {
    const normalized = captureId.trim();
    if (normalized.length === 0) {
      return;
    }
    const consumer = PendingNotificationLaunch.consumer;
    if (consumer !== null) {
      consumer(normalized);
      return;
    }
    PendingNotificationLaunch.pendingCaptureId = normalized;
  }

  static attach(consumer: NotificationLaunchConsumer): void {
    PendingNotificationLaunch.consumer = consumer;
    const pending = PendingNotificationLaunch.pendingCaptureId;
    PendingNotificationLaunch.pendingCaptureId = '';
    if (pending.length > 0) {
      consumer(pending);
    }
  }

  static reset(): void {
    PendingNotificationLaunch.pendingCaptureId = '';
    PendingNotificationLaunch.consumer = null;
  }
}
