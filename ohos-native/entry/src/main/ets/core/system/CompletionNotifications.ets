import { common } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { tr } from '../../shared/AppText';

export class CompletionNotifications {
  private readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async requestEnable(): Promise<boolean> {
    try {
      await notificationManager.requestEnableNotification(this.context);
      return await notificationManager.isNotificationEnabled();
    } catch (_) {
      return false;
    }
  }

  async publish(captureId: string, succeeded: boolean): Promise<void> {
    try {
      await notificationManager.publish({
        id: this.notificationId(captureId),
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: succeeded ? tr('工程照片处理完成', 'Engineering photo processed') :
              tr('工程照片处理失败', 'Engineering photo processing failed'),
            text: succeeded ? tr('水印成片已生成，可在拍摄记录中查看。',
              'The watermarked image is ready in Capture Records.') :
              tr('请打开拍摄记录查看原因并重试。', 'Open Capture Records to review the cause and retry.')
          }
        }
      });
    } catch (_) {
      // Completion notifications are best-effort and never change processing state.
    }
  }

  private notificationId(value: string): number {
    let hash = 17;
    for (let index = 0; index < value.length; index++) {
      hash = ((hash * 31) + value.charCodeAt(index)) & 0x7fffffff;
    }
    return hash;
  }
}
