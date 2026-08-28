export class AppText {
  private static english: boolean = false;

  static apply(localeCode: string, systemLocale: string): void {
    const selected = localeCode.length > 0 ? localeCode : systemLocale;
    AppText.english = selected.toLowerCase().startsWith('en');
  }

  static isEnglish(): boolean {
    return AppText.english;
  }
}

export function tr(chinese: string, english: string): string {
  return AppText.isEnglish() ? english : chinese;
}

const USER_FACING_ERROR_NAME: string = 'UserFacingError';

/** Builds an Error whose message is final, localized copy ready to show. */
export function userFacingError(message: string): Error {
  const error = new Error(message);
  error.name = USER_FACING_ERROR_NAME;
  return error;
}

/**
 * Returns the message of an error created by [userFacingError], or the
 * generic fallback pair for anything else (native pipeline failures, internal
 * sentinels) so raw diagnostics never reach a user-visible surface.
 */
export function userFacingMessage(error: Object, chinese: string, english: string): string {
  const err = error as Error;
  return err.name === USER_FACING_ERROR_NAME && err.message.length > 0 ?
    err.message : tr(chinese, english);
}

/**
 * Returns [error] itself when it is user-facing copy, otherwise wraps the
 * generic fallback pair — used by service boundaries that must not let
 * unclassified failures cross toward a screen.
 */
export function ensureUserFacing(error: Object, chinese: string, english: string): Error {
  const err = error as Error;
  return err.name === USER_FACING_ERROR_NAME && err.message.length > 0 ?
    err : userFacingError(tr(chinese, english));
}

/**
 * Renders the stable code persisted in `captures.failure_reason` as copy in
 * the current locale. Rows written before codes were introduced may hold a
 * localized sentence instead; those are shown unchanged.
 */
export function captureFailureReason(reason: string): string {
  if (reason === 'retry_limit_reached') {
    return tr('处理失败次数过多，请检查原图后重试',
      'Processing failed too many times. Check the original and try again.');
  }
  if (reason === 'album_save_cancelled') {
    return tr('水印图已生成，但未保存到系统相册；点击重试可再次保存',
      'The watermark was generated but not saved to the gallery. Retry to save it again.');
  }
  if (reason === 'invalid_data') {
    return tr('照片数据不符合处理要求，请检查原图后重试',
      'The photo data cannot be processed. Check the original and try again.');
  }
  if (reason === 'original_missing') {
    return tr('原图不存在或为空，请重新拍摄', 'The original is missing or empty. Capture it again.');
  }
  if (reason === 'processing_failed') {
    return tr('照片处理失败，请稍后重试', 'Photo processing failed. Try again later.');
  }
  return reason;
}
